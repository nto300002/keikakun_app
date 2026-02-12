# Stripe Webhook署名検証設計

## 概要

Stripe Webhookエンドポイントにおける署名検証の実装と、それが防御する攻撃シナリオについて解説します。

---

## 1. なぜ署名検証が必要か

### 攻撃シナリオ

Webhookエンドポイントは**公開URL**であるため、以下の攻撃リスクがあります:

```
攻撃者 → POST /api/v1/billing/webhook
         {
           "type": "checkout.session.completed",
           "data": {
             "object": {
               "customer": "攻撃者のStripe Customer ID",
               ...
             }
           }
         }
```

**署名検証がない場合の被害**:
- 攻撃者が偽の`checkout.session.completed`イベントを送信
- システムが正規のリクエストとして処理
- 攻撃者のアカウントが『課金済み』ステータスになる
- 無料で全機能を使い放題

### 署名検証の役割

リクエストが**本当にStripeから送信されたこと**を暗号学的に証明します。

---

## 2. 実装詳細

### コード実装 (`k_back/app/api/v1/endpoints/billing.py:265-310`)

```python
@router.post("/webhook")
async def stripe_webhook(
    request: Request,
    db: Annotated[AsyncSession, Depends(deps.get_db)],
    stripe_signature: Annotated[str, Header(alias="Stripe-Signature")]
):
    """
    Stripe Webhook受信API

    署名検証により、リクエストがStripeから送信されたことを保証
    """
    # 1. Webhook Secretの確認
    if not settings.STRIPE_WEBHOOK_SECRET:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=ja.BILLING_WEBHOOK_SECRET_NOT_SET
        )

    # 2. リクエストボディを取得（生データが必要）
    payload = await request.body()

    # 3. Stripe署名を検証
    try:
        event = stripe.Webhook.construct_event(
            payload,
            stripe_signature,
            settings.STRIPE_WEBHOOK_SECRET.get_secret_value()
        )
    except ValueError:
        # 不正なペイロード（JSONパースエラーなど）
        logger.error("Invalid payload")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=ja.BILLING_WEBHOOK_INVALID_PAYLOAD
        )
    except stripe.error.SignatureVerificationError:
        # 署名不一致 = 偽造されたリクエスト
        logger.error("Invalid signature")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=ja.BILLING_WEBHOOK_INVALID_SIGNATURE
        )

    # 4. 検証成功 → イベント処理へ
    event_type = event['type']
    event_data = event['data']['object']
    ...
```

### 署名検証の仕組み

**Stripeが送信するヘッダー**:
```
Stripe-Signature: t=1609459200,v1=5257a869e7ecebeda32affa62cdca3fa51cad7e77a0e56ff536d0ce8e108d8bd
```

| パラメータ | 説明 |
|-----------|------|
| `t` | タイムスタンプ（Unix時刻） |
| `v1` | HMAC-SHA256署名 |

**検証プロセス**:
1. ペイロード + タイムスタンプ を結合
2. `STRIPE_WEBHOOK_SECRET`を鍵としてHMAC-SHA256でハッシュ化
3. 計算結果と受信した`v1`署名を比較
4. 一致すれば正規のStripe送信、不一致なら偽造

```python
# Stripe SDK内部の処理（概念図）
expected_signature = hmac.new(
    webhook_secret.encode(),
    f"{timestamp}.{payload}".encode(),
    hashlib.sha256
).hexdigest()

if expected_signature != received_signature:
    raise SignatureVerificationError()
```

---

## 3. 防御している攻撃シナリオ

| 攻撃タイプ | 攻撃内容 | 防御方法 | コード箇所 |
|-----------|---------|---------|-----------|
| **偽イベント送信** | 攻撃者が偽の`checkout.session.completed`を送信して無料で課金済みになる | 署名検証で弾く（400エラー） | `billing.py:299-310` |
| **リプレイ攻撃** | 過去の正規イベントを再送信して不正な処理を実行 | 冪等性チェック（`webhook_events`テーブル） | `billing.py:317-321` |
| **中間者攻撃** | ペイロードを改ざんして不正なデータを注入 | 署名不一致で検出 | `billing.py:308-310` |
| **タイミング攻撃** | 古い署名を使って攻撃 | Stripeが5分以内のタイムスタンプのみ受け入れ | SDK内部 |

### コード例: 冪等性チェック

```python
# 同じイベントIDを2回処理しない
is_processed = await crud.webhook_event.is_event_processed(db=db, event_id=event_id)
if is_processed:
    logger.info(f"[Webhook:{event_id}] Event already processed - skipping")
    return {"status": "success", "message": "Event already processed"}
```

---

## 4. セキュリティ補足

### 4.1 なぜ400エラーを返すのか

```python
except stripe.error.SignatureVerificationError:
    raise HTTPException(status_code=400, ...)  # 500ではない
```

**理由**:
- **Stripeの推奨**: 署名エラーは`400 Bad Request`を返す
- **500エラーの問題**: Stripeが「サーバーエラー」と判断して再送信を繰り返す
- **400エラーの意味**: 「無効なリクエスト」= 再送不要 = 攻撃者に成功の機会を与えない

### 4.2 環境変数の安全性

```python
settings.STRIPE_WEBHOOK_SECRET.get_secret_value()  # SecretStr型
```

**Pydantic SecretStrの保護機能**:
```python
from pydantic import SecretStr

class Settings(BaseSettings):
    STRIPE_WEBHOOK_SECRET: SecretStr

# 安全性
print(settings.STRIPE_WEBHOOK_SECRET)  # Output: SecretStr('***')
logger.info(f"Secret: {settings.STRIPE_WEBHOOK_SECRET}")  # ログにも '***' のみ表示
```

| リスク | 対策 |
|--------|------|
| **ログ漏洩** | SecretStrで自動マスキング |
| **ダンプ漏洩** | `repr()`でも`***`表示 |
| **環境変数露出** | GitHub Secretsで管理 |

### 4.3 生ペイロードの必要性

```python
payload = await request.body()  # JSONパース前の生データ
```

**なぜFastAPIのPydanticモデルを使わないのか**:
- 署名検証には**受信した通りのバイト列**が必要
- JSONパース → 再シリアライズでは署名が一致しなくなる
- 空白、改行、キーの順序などが変わるため

---

## 5. 環境変数設定

### 開発環境

```bash
# Stripe CLIでローカルテスト
stripe listen --forward-to http://localhost:8000/api/v1/billing/webhook

# 出力されたWebhook Secretを設定
export STRIPE_WEBHOOK_SECRET="whsec_xxxxxxxxxxxxxxxxxxxxx"
```

### 本番環境

**GitHub Secrets → Cloud Build → Cloud Run**:
```yaml
# .github/workflows/cd-backend.yml
- name: Deploy to Cloud Run
  env:
    STRIPE_WEBHOOK_SECRET: ${{ secrets.STRIPE_WEBHOOK_SECRET }}
```

**Stripeダッシュボードで確認**:
1. Stripe Dashboard → Developers → Webhooks
2. エンドポイント選択 → "Signing secret" をコピー
3. `whsec_`で始まる文字列

---

## 6. テスト方法

### 正常系テスト

```python
import stripe
import time
import json

def test_valid_webhook():
    payload = json.dumps({
        "type": "invoice.payment_succeeded",
        "data": {"object": {...}}
    })

    # 署名生成
    timestamp = int(time.time())
    signed_payload = f"{timestamp}.{payload}"
    signature = hmac.new(
        webhook_secret.encode(),
        signed_payload.encode(),
        hashlib.sha256
    ).hexdigest()

    # リクエスト送信
    response = client.post(
        "/api/v1/billing/webhook",
        data=payload,
        headers={
            "Stripe-Signature": f"t={timestamp},v1={signature}"
        }
    )

    assert response.status_code == 200
```

### 異常系テスト（署名不正）

```python
def test_invalid_signature():
    response = client.post(
        "/api/v1/billing/webhook",
        json={"type": "invoice.payment_succeeded"},
        headers={
            "Stripe-Signature": "t=123456789,v1=invalid_signature"
        }
    )

    assert response.status_code == 400
    assert "Invalid signature" in response.json()["detail"]
```

---

## 7. 面接で強調すべきポイント

### 技術的深さ

1. **HMAC-SHA256の理解**
   - 「署名はHMAC-SHA256で計算され、タイムスタンプも含めることで再送攻撃を防いでいます」

2. **400 vs 500の判断**
   - 「署名エラーは400を返すことで、Stripeに再送信させず攻撃者に成功の機会を与えません」

3. **多層防御**
   - 「署名検証に加えて、冪等性チェック（`webhook_events`テーブル）でリプレイ攻撃も防いでいます」

### セキュリティ意識

1. **環境変数保護**
   - 「Pydantic SecretStrでログ漏洩を防ぎ、GitHub Secretsで本番環境の秘密鍵を管理しています」

2. **生ペイロードの必要性**
   - 「JSONパース前の生データで検証しないと、再シリアライズ時に署名が一致しなくなります」

3. **攻撃シナリオの理解**
   - 「公開URLなので、攻撃者が偽イベントを送信して不正に課金済みステータスを得るリスクがあります」

### 実装のベストプラクティス

```python
# ✅ Good: 署名検証 + 冪等性チェック + 監査ログ
try:
    event = stripe.Webhook.construct_event(...)
    is_processed = await crud.webhook_event.is_event_processed(...)
    if is_processed:
        return {"status": "success"}
    await billing_service.process_payment_succeeded(...)
except SignatureVerificationError:
    raise HTTPException(status_code=400, ...)

# ❌ Bad: 署名検証なし
@router.post("/webhook")
async def stripe_webhook(request: Request):
    data = await request.json()  # 直接JSONパース
    # 偽イベントを正規として処理してしまう
```

---

## 8. 参考資料

- [Stripe Webhooks: Signature Verification](https://stripe.com/docs/webhooks/signatures)
- [HMAC-SHA256 (RFC 2104)](https://datatracker.ietf.org/doc/html/rfc2104)
- [OWASP: Webhook Security](https://cheatsheetseries.owasp.org/cheatsheets/Webhook_Security_Cheat_Sheet.html)

---

**作成日**: 2026-01-29
**対象面接**: Web受託系アプリ開発 2次面接
**カテゴリ**: セキュリティ / Stripe決済 / Webhook
