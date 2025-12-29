# Checkout Session作成エラー調査レポート

**エラー発生日時**: 2025-12-25 00:20:38
**エンドポイント**: `POST /api/v1/billing/create-checkout-session`
**ステータスコード**: 500 Internal Server Error

---

## 🔴 エラー内容

### HTTPレスポンス
```json
{
  "detail": "Checkout Sessionの作成に失敗しました"
}
```

### Stripeエラー詳細
```
error_code: None
error_message: 'The `trial_end` date has to be at least 2 days in the future.'
error_param: subscription_data[trial_end]
error_type: invalid_request_error
```

---

## 🔍 原因分析

### 1. Billing情報の状態

```sql
SELECT * FROM billings WHERE id='daae3740-ee95-4967-a34d-9eca0d487dc9';
```

| フィールド | 値 |
|-----------|-----|
| billing_status | `free` |
| trial_end_date | `2025-12-24 01:32:38` |
| stripe_customer_id | NULL |
| stripe_subscription_id | NULL |
| updated_at | `2025-12-24 02:37:33` |

### 2. エラー発生のタイムライン

```
エラー発生時刻: 2025-12-25 00:20:38
trial_end_date:  2025-12-24 01:32:38
                 ↑
                 約23時間前（過去）
```

**問題**: `trial_end_date`が**過去の日付**になっている

### 3. コードフロー

**`k_back/app/api/v1/endpoints/billing.py:160`**:
```python
checkout_session = stripe.checkout.Session.create(
    mode='subscription',
    customer=billing.stripe_customer_id,
    line_items=[{
        'price': settings.STRIPE_PRICE_ID,
        'quantity': 1
    }],
    subscription_data={
        'trial_end': int(billing.trial_end_date.timestamp()),  # ← ここ！過去の日付を送信
        'metadata': {
            'office_id': str(office_id),
            'office_name': office.name,
            'created_by_user_id': str(current_user.id),
        }
    },
    ...
)
```

**`k_back/app/services/billing_service.py:106`**:
```python
checkout_session = stripe.checkout.Session.create(
    ...
    subscription_data={
        'trial_end': int(trial_end_date.timestamp()),  # ← ここも！
        ...
    },
    ...
)
```

### 4. Stripeの制約

Stripeは以下の制約を持っています:
- ✅ `trial_end`は**現在時刻から最低2日後**でなければならない
- ❌ 過去の日付や2日未満の未来の日付は受け付けない

---

## 🎯 根本原因

**以前のテストで`batch_trigger_setup.py expire`を使用したため**

```bash
# このコマンドを実行した履歴がある
docker exec keikakun_app-backend-1 python3 scripts/batch_trigger_setup.py expire --billing-id daae3740-ee95-4967-a34d-9eca0d487dc9 --minutes 1
```

このコマンドにより:
1. `trial_end_date`が過去（2025-12-24 01:32:38）に設定された
2. バッチ処理テストのために意図的に過去にした
3. テスト後、リセットされなかった

---

## ✅ 解決方法

### 即座の解決: trial_end_dateをリセット

```bash
# 1. trial_end_dateを90日後に戻す
docker exec keikakun_app-backend-1 python3 scripts/batch_trigger_setup.py reset --billing-id daae3740-ee95-4967-a34d-9eca0d487dc9

# 2. 結果確認
docker exec keikakun_app-backend-1 python3 scripts/batch_trigger_setup.py list
```

**期待される結果**:
```
Billing ID: daae3740-ee95-4967-a34d-9eca0d487dc9
Status: free
Trial End: 2026-03-25 00:XX:XX (✅ 残り90日)
```

### 動作確認

リセット後、再度課金登録を試す:
1. フロントエンドから「課金登録」をクリック
2. Checkout Sessionが正常に作成される ✅
3. Stripeのチェックアウトページにリダイレクトされる ✅

---

## 🛡️ 恒久的な解決策（推奨）

### 1. エンドポイントにバリデーション追加

**`k_back/app/api/v1/endpoints/billing.py`**に以下を追加:

```python
@router.post("/create-checkout-session")
async def create_checkout_session(
    db: Annotated[AsyncSession, Depends(deps.get_db)],
    current_user: Annotated[Staff, Depends(deps.require_owner)]
):
    # ... 既存のコード ...

    # Billing情報を取得
    billing = await crud.billing.get_by_office_id(db=db, office_id=office_id)
    if not billing:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=ja.BILLING_INFO_NOT_FOUND
        )

    # ✅ 追加: trial_end_dateのバリデーション
    now = datetime.now(timezone.utc)
    min_trial_end = now + timedelta(days=2)  # Stripeの要件: 最低2日後

    if billing.trial_end_date < min_trial_end:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Trial期間は最低2日後に設定する必要があります。現在の設定: {billing.trial_end_date.strftime('%Y-%m-%d %H:%M:%S')}"
        )

    # ... 既存のコード続き ...
```

### 2. batch_trigger_setup.pyに警告を追加

**`k_back/scripts/batch_trigger_setup.py`**の`set_expiry()`関数に警告を追加:

```python
async def set_expiry(billing_id: str, minutes: int):
    # ... 既存のコード ...

    print(f"⚠️  警告: この操作により、課金登録ができなくなります")
    print(f"   理由: Stripeは trial_end が2日以上未来である必要があります")
    print(f"   テスト後は必ず reset コマンドでリセットしてください\n")

    # ... 既存のコード続き ...
```

---

## 📊 テストケース

### 正常系

**前提条件**:
- trial_end_date: 2026-03-25 00:00:00 (90日後)

**実行**:
```bash
curl -X POST http://localhost:8000/api/v1/billing/create-checkout-session \
  -H "Authorization: Bearer <token>"
```

**期待結果**:
```json
{
  "session_id": "cs_xxxxx",
  "url": "https://checkout.stripe.com/xxxxx"
}
```

### 異常系（バリデーション追加後）

**前提条件**:
- trial_end_date: 2025-12-24 01:32:38 (過去)

**実行**:
```bash
curl -X POST http://localhost:8000/api/v1/billing/create-checkout-session \
  -H "Authorization: Bearer <token>"
```

**期待結果**:
```json
{
  "detail": "Trial期間は最低2日後に設定する必要があります。現在の設定: 2025-12-24 01:32:38"
}
```
Status: 400 Bad Request

---

## 🎯 まとめ

### 原因
- `batch_trigger_setup.py expire`でtrial_end_dateを過去に設定
- テスト後、リセットを忘れた
- 過去の日付がStripeに送信されエラー

### 即座の対応
```bash
docker exec keikakun_app-backend-1 python3 scripts/batch_trigger_setup.py reset --billing-id daae3740-ee95-4967-a34d-9eca0d487dc9
```

### 再発防止
1. エンドポイントにtrial_end_dateバリデーション追加
2. batch_trigger_setup.pyに警告メッセージ追加
3. テスト後は必ずresetする運用ルールを明確化

---

**最終更新**: 2025-12-25
