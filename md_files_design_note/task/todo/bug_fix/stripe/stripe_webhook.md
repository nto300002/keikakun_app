# Stripe 課金機能 本番 Checkout Session 500 エラー調査メモ

作成日: 2026-06-16

## 現象

Stripe の課金機能において、サンドボックス環境または local では正常に Stripe Checkout 画面へ遷移できるが、本番環境では `POST /api/v1/billing/create-checkout-session` が `500 Internal Server Error` になる。

スクリーンショットから確認できる事実:

- Image #1: 管理者設定 > プラン画面で「サブスクリプションに登録する」実行後、画面上に `Checkout Sessionの作成に失敗しました` が表示されている。
- Image #1: DevTools Console でも `https://api.keikakun.com/api/v1/billing/create-checkout-session` への POST が 500 で失敗している。
- Image #2: local またはサンドボックス環境では `checkout.stripe.com` の Checkout 画面へ遷移でき、6,000円/月のサブスクリプション申し込み画面が表示されている。
- Image #3: 本番 API のレスポンスは `500 Internal Server Error`。CORS は通っており、`Access-Control-Allow-Origin: https://www.keikakun.com` が返っているため、フロントから API へ到達できている。

重要: 現象が出ているのは Webhook 受信時ではなく、Webhook より前段の Checkout Session 作成 API である。したがって、まず `create-checkout-session` の Stripe API 呼び出し失敗を調査する。

## 実装側の確認結果

該当実装:

- フロント: `k_front/lib/api/billing.ts`
- バックエンド: `k_back/app/api/v1/endpoints/billing.py`
- サービス層: `k_back/app/services/billing_service.py`
- 設定値: `k_back/app/core/config.py`

フロントは `POST /api/v1/billing/create-checkout-session` を呼び出し、バックエンドから返った `url` に遷移するだけの実装。Image #3 では本番 API が 500 を返しているため、フロント側の遷移処理が主因である可能性は低い。

バックエンドは以下の条件で Checkout Session を作成している。

- `STRIPE_SECRET_KEY` と `STRIPE_PRICE_ID` が必須。
- owner 権限のユーザーのみ実行可能。
- staff の所属 office から billing を取得する。
- `billing.stripe_customer_id` がある場合は既存 Customer で `stripe.checkout.Session.create(...)` を実行する。
- `billing.stripe_customer_id` がない場合は Stripe Customer を作成し、DB に Customer ID を保存してから `stripe.checkout.Session.create(...)` を実行する。
- Checkout Session 作成時に `automatic_tax={'enabled': True}`、`customer_update={'address': 'auto'}`、`billing_address_collection='required'` を指定している。
- 失敗時は `Checkout Sessionの作成に失敗しました` という共通メッセージで 500 を返す。

現時点で実装から見える注意点:

- Stripe 設定未投入なら本来は 503 `Stripe連携が設定されていません` になるため、今回の 500 は `STRIPE_SECRET_KEY` / `STRIPE_PRICE_ID` が未設定というより、Stripe API 呼び出し時の例外である可能性が高い。
- 本番のみ 500 なので、local と本番で `STRIPE_SECRET_KEY` と `STRIPE_PRICE_ID` の組み合わせが違う、または Stripe 本番アカウント側の設定が不足している可能性が高い。
- `automatic_tax={'enabled': True}` を使っているため、Stripe 本番側で Tax の有効化、住所収集、税務設定、商品/価格設定が Checkout Session 作成条件を満たしているか確認が必要。
- 新規 Customer 作成ルートでは `trial_end` を常に指定している。対象 billing の `trial_end_date` が過去または不正値の場合、Stripe 側で Checkout Session 作成が失敗する可能性がある。既存 Customer ルートでは未来日の場合のみ `trial_end` を設定しており、挙動が少し異なる。
- 例外ログは `logger.error(f"Stripe API error: {e}")` または `logger.error(f"Stripe Checkout Session作成エラー: {e}")` に出るが、API レスポンスには詳細が返らない。Cloud Run など本番ログで Stripe の実エラー文を確認する必要がある。

## 実装側で確認すること

1. 本番ログで `Stripe API error:` または `Stripe Checkout Session作成エラー:` の直後に出ている Stripe のエラー本文を確認する。
2. 本番環境変数の整合性を確認する。
   - `STRIPE_SECRET_KEY` が本番用 `sk_live_...` か。
   - `STRIPE_PRICE_ID` が本番 Stripe アカウント上の `price_...` か。
   - テスト環境の `price_...` と本番環境の `sk_live_...` を混在させていないか。
   - `FRONTEND_URL` が `https://www.keikakun.com` など本番 URL になっているか。
3. DB の対象 office の billing レコードを確認する。
   - `billing_status`
   - `stripe_customer_id`
   - `trial_end_date`
   - `current_plan_amount`
   - `stripe_customer_id` がテスト環境で作成された `cus_...` ではないか。
4. `trial_end_date` が現在時刻より過去になっていないか確認する。過去の場合、新規 Customer ルートで `trial_end` 指定により Stripe API が失敗する可能性がある。
5. 本番ログの Stripe エラーが設定不足系であれば、アプリコード修正より Stripe 管理画面側の設定修正を優先する。

## Stripe 側で確認すべき点

本番 Stripe ダッシュボードで以下を確認する。

1. API キーと Price ID の環境一致
   - 本番 API キー `sk_live_...` を使っているか。
   - `STRIPE_PRICE_ID` が同じ本番アカウントの Price ID か。
   - local / sandbox 用の `price_...` を本番に設定していないか。

2. 商品と価格
   - 月額 6,000 円の Product / Price が本番モードに存在するか。
   - Price が active か。
   - Price の通貨、請求間隔、金額が想定どおりか。
   - Checkout / Subscription で利用可能な recurring price になっているか。

3. Automatic Tax
   - 本番アカウントで Stripe Tax / Automatic Tax が有効化されているか。
   - 税務登録、住所、事業者情報など Automatic Tax に必要な設定が完了しているか。
   - Automatic Tax を有効にした Checkout Session 作成が本番で許可される状態か。

4. Checkout / Payment Methods
   - 本番モードでカード決済が有効か。
   - Checkout の利用制限、決済手段、国/通貨の設定に問題がないか。
   - Link 決済の表示自体は問題ではないが、本番カード決済が有効か確認する。

5. Customer
   - 既存 `stripe_customer_id` がある office の場合、その Customer が本番アカウントに存在するか。
   - テストモードの Customer ID を本番 DB に保存していないか。
   - Customer が削除済みではないか。

6. Webhook
   - 今回の 500 は Webhook 到達前の問題だが、Checkout 成功後のステータス更新には Webhook 設定が必要。
   - 本番 Webhook endpoint が `https://api.keikakun.com/api/v1/billing/webhook` になっているか。
   - 本番用の `STRIPE_WEBHOOK_SECRET` が設定されているか。
   - 購読イベントとして `customer.subscription.created`、`customer.subscription.updated`、`customer.subscription.deleted`、`invoice.payment_succeeded`、`invoice.payment_failed` が送信対象になっているか。

## 優先度の高い切り分け

最優先は本番ログの Stripe 例外本文を確認すること。現状の画面と DevTools だけでは、Stripe API が拒否した理由がフロントに返らない。

想定される原因の優先度:

1. 本番 `STRIPE_SECRET_KEY` と `STRIPE_PRICE_ID` の環境不一致。
2. 本番 Price が存在しない、inactive、または recurring price ではない。
3. `automatic_tax` を有効にしているが、本番 Stripe Tax 設定が未完了。
4. 本番 DB の `stripe_customer_id` がテスト環境の Customer ID、または削除済み Customer ID。
5. `trial_end_date` が過去で Stripe の trial 設定として不正。

ログで `No such price`、`No such customer`、`This customer has no attached payment source`、`automatic_tax`、`tax`、`trial_end` などの文言が出ていれば、その文言に沿って上記項目を確認する。

## Restricted API Key 作成時の権限確認

作成日: 2026-06-16

Stripe の Restricted API Key を作成する場合、このアプリの実装に必要な権限は「サブスクリプション課金の Checkout 作成」と「既存サブスクの管理」に限定できる。

該当実装:

- `k_back/app/api/v1/endpoints/billing.py`
  - `stripe.checkout.Session.create(...)`
  - `stripe.billing_portal.Session.create(...)`
  - `stripe.Webhook.construct_event(...)`
- `k_back/app/services/billing_service.py`
  - `stripe.Customer.create(...)`
  - `stripe.checkout.Session.create(...)`
- `k_back/app/services/withdrawal_service.py`
  - `stripe.Subscription.delete(subscription_id)`

アプリが受信して利用している Webhook イベント:

- `invoice.payment_succeeded`
- `invoice.payment_failed`
- `customer.subscription.created`
- `customer.subscription.updated`
- `customer.subscription.deleted`

追加で検討する Webhook イベント:

- `payment_intent.payment_failed`
- `charge.failed`

これらは Restricted API Key の権限項目ではなく、Webhook endpoint 側で購読するイベント種別である。Restricted API Key はアプリから Stripe API へ能動的に実行する `Customer.create`、`Checkout Session.create`、`Subscription.delete` などの権限を制限するもの。一方、Webhook は Stripe からアプリへ送られるイベントであり、受信可否は Webhook endpoint の購読イベント設定と `STRIPE_WEBHOOK_SECRET` による署名検証で決まる。

ただし、Webhook処理内で `stripe.Event.retrieve(...)`、`stripe.PaymentIntent.retrieve(...)`、`stripe.Charge.retrieve(...)` などを追加で呼び出す設計に変更する場合は、その取得APIに対応する読み取り権限が Restricted API Key 側にも必要になる。現在の実装のように受信payloadだけで処理する場合、`payment_intent.payment_failed` / `charge.failed` を受けること自体にAPI Key権限は不要。

ユーザーから提示された対象イベントには `customer.subscription.updated` が含まれていなかったが、実装上はキャンセル予定状態への変更に利用しているため、Webhook endpoint の購読イベントには追加しておく。

### 推奨するキー作成テンプレート

テンプレートを選ぶ場合は `Recurring subscriptions and billing` を選択する。

理由:

- このアプリは単発決済ではなく `mode='subscription'` の Checkout Session を作成している。
- 月額 6,000 円の recurring price を使う。
- Customer、Subscription、Invoice 系の Webhook を使って課金状態を更新している。
- Customer Portal からカード変更やキャンセル管理を行う。

### 最小構成に近い推奨権限

Restricted API Key の「自分で選択」で設定する場合、まず以下を設定する。

| Stripe 権限 | 推奨 | 理由 |
| --- | --- | --- |
| Checkout Sessions | 書き込み | `stripe.checkout.Session.create(...)` で必須。 |
| Customers | 書き込み | 初回課金登録時に `stripe.Customer.create(...)` を実行するため必須。既存 Customer 指定の Checkout 作成にも必要になる可能性が高い。 |
| Products | 読み取り | Checkout Session の line item が Price 経由で Product を参照するため、読み取りを付与しておく。アプリから Product 作成はしないため書き込みは不要。 |
| Prices | 読み取り | `STRIPE_PRICE_ID` の recurring price を Checkout Session に渡すため、読み取りを付与しておく。アプリから Price 作成はしないため書き込みは不要。 |
| Subscriptions | 書き込み | 退会処理で `stripe.Subscription.delete(subscription_id)` を実行するため必須。Checkout でサブスク作成も行われる。 |
| Billing Portal Sessions / Customer Portal | 書き込み | `stripe.billing_portal.Session.create(...)` でサブスク管理画面を作成するため必要。Stripe の画面上で個別項目がない場合は Billing 系の書き込みに含まれる可能性がある。 |
| Invoices | 読み取り | Webhook payload で請求結果を受けるだけなら API 読み取りは不要だが、`invoice.payment_succeeded` / `invoice.payment_failed` を扱う運用上、読み取りを付与しておくと安全。 |
| Payment Methods | 読み取り | Checkout / Portal でカード変更を扱うため、読み取りを付与しておくと安全。アプリから PaymentMethod 作成はしていないため書き込みは原則不要。 |
| Tax Calculations, Transactions | 書き込み | 実装で `automatic_tax={'enabled': True}` を指定しているため、画像 #9 の Tax 系権限は書き込みにしておくのが安全。 |
| Tax Settings, Registrations | 読み取り または 書き込み | Automatic Tax の設定状態を Stripe 側で利用するため、画像 #9 の Tax 系権限が書き込みなら問題なし。最小化するなら読み取りでも足りる可能性はあるが、Checkout 作成エラー切り分け中は書き込み推奨。 |
| Webhook Endpoints, Event Destinations | なし または 読み取り | アプリ実行時に Webhook endpoint を API で作成・更新していない。Dashboard で手動設定するだけなら Secret Key には不要。 |
| Events | 読み取り任意 | Webhook は Stripe から届く payload を署名検証して処理しており、`stripe.Event.retrieve(...)` は使っていない。通常は不要。 |

### 画像の権限設定との照合

スクリーンショットから読み取れる範囲では、以下はアプリ要件に合っている。

- Image #1: `Customers` が書き込みになっているため、初回登録時の Customer 作成に合致。
- Image #2: `Payment Methods` が書き込みになっているため、必要量より広いが Checkout / Portal との相性上は問題なし。最小化するなら読み取りでもよい。
- Image #2: `Products` が書き込みになっているため、必要量より広い。アプリは Product を作成しないので読み取りで足りる想定。
- Image #3: `Billing` が書き込みになっているため、サブスクリプション課金系の操作には合致。
- Image #4: `Checkout Sessions` が書き込みになっているため、Checkout Session 作成に合致。
- Image #9: `Tax` が書き込みになっているため、`automatic_tax` 利用には合致。
- Image #10: `Webhook Endpoints, Event Destinations` が書き込みになっているが、アプリ実行時には不要。Dashboard で Webhook endpoint を手動作成・編集するだけなら Secret Key には付与しなくてよい。

画像から不足している可能性がある項目:

- `Prices` が見えていない。Stripe の権限一覧に `Prices` が別項目として存在する場合は読み取りを付与する。
- `Subscriptions` が見えていない。Stripe の権限一覧に `Subscriptions` が別項目として存在する場合は書き込みを付与する。
- `Billing Portal Sessions` または `Customer Portal` 相当の項目が見えていない。存在する場合は書き込みを付与する。

### 付与しなくてよい権限

このアプリの本番ランタイムでは以下は不要。

- Apple Pay Domains
- Balance / Balance Transfers / Payouts
- Charges and Refunds
- Payment Links
- Terminal
- Connect
- Financial Connections
- Identity
- Issuing
- Radar Reviews
- Sigma
- Stripe Apps Secrets
- Test Clocks
- Webhook Endpoints の書き込み

ただし、Stripe Dashboard 上で人が設定作業をするための権限と、アプリが使う Restricted API Key の権限は分けて考える。アプリの Secret Key に Dashboard 管理用の広い権限を持たせる必要はない。

### Webhook endpoint 側で設定するイベント

Secret Key の権限とは別に、Stripe Dashboard の Webhook endpoint では以下を購読する。

- `customer.subscription.created`
- `customer.subscription.updated`
- `customer.subscription.deleted`
- `invoice.payment_succeeded`
- `invoice.payment_failed`

期限切れ後のCheckout上でカード拒否されたケースも状態更新対象にする場合は、以下も購読候補に加える。

- `payment_intent.payment_failed`
- `charge.failed`

今回提示されたイベント一覧には `customer.subscription.updated` がなかったが、実装では `cancel_at_period_end` や `cancel_at` を見て `billing_status=canceling` に変更するため必要。

`payment_intent.payment_failed` / `charge.failed` は、Checkout画面上で即時課金が拒否されたときに発生し得る。特にtrial期限切れ後の登録では即時請求になるため、`invoice.payment_failed` ではなく `payment_intent.payment_failed` / `charge.failed` のみが届く場合がある。これを `billing_status=payment_failed` へ反映するかは別途実装判断が必要。

Webhook の署名検証には `STRIPE_WEBHOOK_SECRET`、通常の Stripe API 呼び出しには `STRIPE_SECRET_KEY` を使う。両者は別の値であり、Restricted API Key の権限設定は `STRIPE_SECRET_KEY` 側に関係する。
