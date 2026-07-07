# Webhook問題調査手順

## 🎯 問題の特定

### エラー詳細
- **stripe_customer_id**: `cus_TbcyUezfWZm0KY` ✅
- **stripe_subscription_id**: 空 ❌
- **billing_status**: `free` ❌ (期待値: `early_payment`)
- **office_id**: `0949d359-5e1a-42f3-87da-07b40946efc0`
- **billing_id**: `daae3740-ee95-4967-a34d-9eca0d487dc9`

---

## 📋 調査チェックリスト

### ✅ ステップ1: Stripe Dashboardでの確認

#### 1-1. Webhookエンドポイントの登録確認

```
1. Stripe Dashboard にログイン
   URL: https://dashboard.stripe.com/

2. テストモード/本番モードの確認
   - 右上のトグルを確認
   - サンドボックス = テストモード

3. Developers → Webhooks に移動

4. 登録されているエンドポイントを確認
   期待値:
   - エンドポイントURL: https://your-backend.com/api/v1/billing/webhook
   - ステータス: Enabled
   - リスニング中のイベント:
     * customer.subscription.created
     * customer.subscription.deleted
     * invoice.payment_succeeded
     * invoice.payment_failed
```

**❌ エンドポイントが未登録の場合**:
→ これが最も可能性の高い原因
→ ステップ2に進んで登録

**✅ エンドポイントが登録済みの場合**:
→ ステップ1-2に進む

---

#### 1-2. Webhookイベントログの確認

```
1. Webhooks → 登録済みエンドポイントをクリック

2. 「イベント」タブを確認

3. 最近のイベントで以下を確認:
   - customer_subscription_created イベントが送信されているか
   - レスポンスステータスコード
     * 200: 正常
     * 400: 署名検証エラー
     * 503: STRIPE_WEBHOOK_SECRET未設定
     * 5xx: サーバーエラー

4. customer_id で絞り込み検索:
   cus_TbcyUezfWZm0KY
```

**発見したイベント例**:
- イベントID: `evt_xxxxx`
- イベントタイプ: `customer.subscription.created`
- ステータス: `失敗 (400/503/500)`
- エラーメッセージ: `[記録する]`

---

#### 1-3. Customerとサブスクリプションの確認

```
1. Customers → 検索バーに customer_id を入力:
   cus_TbcyUezfWZm0KY

2. Customer詳細ページで確認:
   - Subscriptions セクションにサブスクリプションが存在するか
   - サブスクリプションID (sub_xxxxx) を記録

3. サブスクリプション詳細を確認:
   - ステータス: active / trialing / past_due など
   - メタデータに office_id が含まれているか
     期待値: office_id = 0949d359-5e1a-42f3-87da-07b40946efc0
```

**✅ サブスクリプションが存在する場合**:
→ Stripe側は正常、Webhook処理に問題あり

**❌ サブスクリプションが存在しない場合**:
→ Checkout Session作成時に失敗した可能性

---

### ✅ ステップ2: バックエンド環境変数の確認

#### 2-1. .env ファイルの確認

```bash
# .env ファイルを確認（本番環境の場合はCloud Runの環境変数）
cat .env | grep STRIPE

# 期待される出力:
# STRIPE_SECRET_KEY=sk_test_... または sk_live_...
# STRIPE_WEBHOOK_SECRET=whsec_...
# STRIPE_PRICE_ID=price_...
```

**確認ポイント**:
- [ ] `STRIPE_SECRET_KEY` が設定されているか
- [ ] `STRIPE_WEBHOOK_SECRET` が設定されているか
- [ ] Stripe Dashboardの Signing Secret と一致しているか
- [ ] テストモードとライブモードのキーが混在していないか

**❌ STRIPE_WEBHOOK_SECRET が未設定の場合**:
→ Webhookは503エラーで拒否される
→ ステップ2-2で設定

---

#### 2-2. Webhook Secretの取得と設定

```
1. Stripe Dashboard → Webhooks → エンドポイント詳細

2. 「Signing secret」セクションで「Reveal」をクリック

3. whsec_... で始まる秘密鍵をコピー

4. .env ファイルに追加:
   STRIPE_WEBHOOK_SECRET=whsec_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

5. バックエンドを再起動
   docker compose restart backend
   # または
   gcloud run services update keikakun-backend --update-env-vars STRIPE_WEBHOOK_SECRET=whsec_...
```

---

### ✅ ステップ3: バックエンドログの確認

#### 3-1. ログでWebhook受信を確認

```bash
# ローカル開発の場合
docker compose logs -f backend | grep -i webhook

# Cloud Runの場合
gcloud logging read "resource.type=cloud_run_revision \
  AND resource.labels.service_name=keikakun-backend" \
  --limit 50 --format json | jq '.[] | select(.textPayload | contains("Webhook"))'
```

**確認ポイント**:
- [ ] `[Webhook:evt_xxxxx]` のようなログが記録されているか
- [ ] `Event already processed` のメッセージが出ているか（冪等性チェック）
- [ ] `Webhook処理エラー` のエラーログがあるか
- [ ] `Invalid signature` のエラーログがあるか

---

#### 3-2. データベースでwebhook_eventsを確認

```sql
-- webhook_eventsテーブルでイベント受信履歴を確認
SELECT
    event_id,
    event_type,
    source,
    billing_id,
    office_id,
    status,
    created_at
FROM webhook_events
WHERE office_id = '0949d359-5e1a-42f3-87da-07b40946efc0'
ORDER BY created_at DESC
LIMIT 10;
```

**期待される結果**:
- `customer.subscription.created` イベントが記録されている
- status = 'success'

**❌ レコードが0件の場合**:
→ Webhookが全く受信されていない
→ ステップ4に進む

**⚠️ status = 'failed' の場合**:
→ Webhook受信はしたが処理に失敗
→ payload カラムを確認してエラー原因を特定

---

### ✅ ステップ4: ローカル開発環境でのWebhook設定

#### 4-1. Stripe CLIのインストール

```bash
# macOS
brew install stripe/stripe-cli/stripe

# 認証
stripe login
```

#### 4-2. Webhookのフォワーディング

```bash
# ローカルバックエンドにWebhookをフォワード
stripe listen --forward-to localhost:8000/api/v1/billing/webhook

# 出力例:
# > Ready! Your webhook signing secret is whsec_xxxxx
# この whsec_xxxxx を .env に設定
```

#### 4-3. テストイベントの送信

```bash
# customer.subscription.created イベントを送信
stripe trigger customer.subscription.created

# レスポンスを確認:
# - バックエンドログで正常に処理されたか
# - DBでbilling_statusが更新されたか
```

---

### ✅ ステップ5: 手動でのWebhook再送信（応急処置）

Stripeに既にサブスクリプションが作成されている場合、Webhookイベントを手動で再送信できます。

#### 5-1. Stripe Dashboardから再送信

```
1. Webhooks → エンドポイント詳細 → イベントタブ

2. 失敗した customer.subscription.created イベントを見つける

3. 右上の「...」メニュー → 「Resend event」をクリック

4. バックエンドログとDBで処理結果を確認
```

#### 5-2. Stripe APIで手動処理（最終手段）

既にサブスクリプションIDが分かっている場合、バックエンドで手動更新:

```python
# Python shell または管理用スクリプトで実行
from app import crud
from app.db.session import AsyncSessionLocal
from app.models.enums import BillingStatus
from datetime import datetime, timezone
from uuid import UUID

async def manual_fix():
    async with AsyncSessionLocal() as db:
        billing_id = UUID("daae3740-ee95-4967-a34d-9eca0d487dc9")

        # Stripe Dashboardで確認したサブスクリプションID
        stripe_subscription_id = "sub_xxxxx"  # ← Stripeから取得

        # 手動で更新
        await crud.billing.update_stripe_subscription(
            db=db,
            billing_id=billing_id,
            stripe_subscription_id=stripe_subscription_id,
            subscription_start_date=datetime.now(timezone.utc)
        )

        # ステータスを early_payment に更新
        await crud.billing.update_status(
            db=db,
            billing_id=billing_id,
            status=BillingStatus.early_payment
        )

        await db.commit()
        print("✅ Manual fix completed")

# 実行
import asyncio
asyncio.run(manual_fix())
```

---

## 🎯 最も可能性の高い原因と解決策

### 原因1: Webhookエンドポイント未登録（80%の確率）

**症状**:
- Stripe Dashboardにエンドポイントが登録されていない
- ローカル開発でngrok/Stripe CLIを使用していない

**解決策**:
```
1. 本番環境/ステージング環境:
   → Stripe Dashboard → Webhooks → Add endpoint
   → URL: https://your-backend.com/api/v1/billing/webhook
   → イベント選択: customer.subscription.*, invoice.*

2. ローカル開発:
   → stripe listen --forward-to localhost:8000/api/v1/billing/webhook
```

---

### 原因2: STRIPE_WEBHOOK_SECRET未設定（15%の確率）

**症状**:
- Webhookリクエストが503エラー
- ログに "Webhook Secret not set" エラー

**解決策**:
```bash
# Stripe Dashboardから Signing Secret を取得
# .env に追加
STRIPE_WEBHOOK_SECRET=whsec_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# 再起動
docker compose restart backend
```

---

### 原因3: 署名検証エラー（5%の確率）

**症状**:
- Webhookリクエストが400エラー
- ログに "Invalid signature" エラー

**解決策**:
```
1. Stripe DashboardのSigning Secretと.envのSTRIPE_WEBHOOK_SECRETが一致するか確認
2. テストモードとライブモードのキーが混在していないか確認
3. Webhook Secretを再生成して設定し直す
```

---

## 📝 調査結果記録フォーマット

```
【調査日時】: 2025-12-15 XX:XX

【ステップ1: Stripe Dashboard確認】
- Webhookエンドポイント登録: ✅ / ❌
- エンドポイントURL:
- customer.subscription.created イベント: 送信済み / 未送信 / エラー
- イベントID: evt_xxxxx
- レスポンスステータス: 200 / 400 / 503 / 500
- エラーメッセージ:

【ステップ2: 環境変数確認】
- STRIPE_SECRET_KEY: 設定済み / 未設定
- STRIPE_WEBHOOK_SECRET: 設定済み / 未設定
- Signing Secretと一致: ✅ / ❌

【ステップ3: ログ確認】
- Webhook受信ログ: あり / なし
- エラーログ: あり / なし
- エラー内容:

【ステップ4: DB確認】
- webhook_events レコード数: X件
- 最新イベント: event_id, status
- billing_status: free / early_payment / active

【結論】
- 特定した原因:
- 実施した修正:
- 修正後の状態:
```

---

## 🚀 次のステップ

調査完了後、以下を実施:
1. [ ] 原因を特定
2. [ ] 修正を適用
3. [ ] テストで検証
4. [ ] ドキュメント更新
