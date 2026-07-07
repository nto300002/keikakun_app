# 本番環境 環境変数設定ガイド

## 概要

### 1.4 Stripe決済設定（重要）

#### STRIPE_SECRET_KEY
- **説明**: Stripe APIシークレットキー（本番用）
- **必須**: Yes
- **形式**: `sk_live_...`（本番環境）
- **取得方法**:
  1. Stripe Dashboard > Developers > API keys
  2. "Secret key" をコピー（本番モード）
- **セキュリティ**:
  - 絶対に公開しない
  - Secret Managerに保存必須
  - フロントエンドに送信しない

#### STRIPE_PUBLISHABLE_KEY
- **説明**: Stripe公開可能キー（本番用）
- **必須**: Yes
- **形式**: `pk_live_...`（本番環境）
- **取得方法**:
  1. Stripe Dashboard > Developers > API keys
  2. "Publishable key" をコピー（本番モード）
- **用途**: フロントエンドでStripe Checkoutを初期化
- **セキュリティ**: 公開可能（フロントエンドで使用）

#### STRIPE_WEBHOOK_SECRET
- **説明**: Stripe Webhook署名検証用シークレット
- **必須**: Yes
- **形式**: `whsec_...`
- **取得方法**:
  1. Stripe Dashboard > Developers > Webhooks
  2. 本番用Webhookエンドポイントを作成
  3. "Signing secret" をコピー
- **エンドポイント**: `https://YOUR_DOMAIN/api/v1/billing/webhook`
- **必要なイベント**:
  - `invoice.payment_succeeded`
  - `invoice.payment_failed`
  - `customer.subscription.created`
  - `customer.subscription.updated`
  - `customer.subscription.deleted`
- **セキュリティ**:
  - Secret Managerに保存必須
  - Webhook署名検証で不正リクエストを防止

#### STRIPE_PRICE_ID
- **説明**: 月額プランのStripe Price ID（本番用）
- **必須**: Yes
- **形式**: `price_...`
- **取得方法**:
  1. Stripe Dashboard > Products
  2. 本番用の商品を作成（例: 月額6,000円プラン）
  3. Price IDをコピー
- **設定例**:
  - 商品名: "Keikakun Pro Plan"
  - 価格: 6,000 JPY / month
  - 請求サイクル: 毎月
- **用途**: Checkout Session作成時に使用


## 7. 環境変数テンプレート

デプロイ時に使用する環境変数テンプレート（コピー用）:

```bash
# Stripe設定（本番用）
STRIPE_SECRET_KEY="<Secret Managerから取得 - sk_live_で始まる>"
STRIPE_PUBLISHABLE_KEY="pk_live_xxxxx"
STRIPE_WEBHOOK_SECRET="<Secret Managerから取得 - whsec_で始まる>"
STRIPE_PRICE_ID="price_xxxxx"
```

---

## 8. デプロイ前最終チェック

- [ ] 全ての必須環境変数が設定されている
- [ ] Stripe関連の設定が全て本番モード（Live mode）
- [ ] `FRONTEND_URL`が本番ドメイン
- [ ] `DATABASE_URL`が本番データベース
- [ ] Secret Managerを使用して機密情報を保護
- [ ] Cloud Runサービスアカウントに適切な権限が付与されている
- [ ] Stripe Webhookエンドポイントが本番URLで登録されている
- [ ] 本番環境でテスト決済を実施（テストモードで）

---

**最終更新**: 2025-12-29
**作成者**: Claude Sonnet 4.5
