# Stripe Checkout 500 エラー解決チェックリスト

作成日: 2026-06-16

## 現在の状態

- Stripe 開発者画面で本番用の制限付き API キー作成は完了済み。
- 作成済みキー名: `keikakun_prod`
- トークン表示: `rk_live_...aI59`
- 最優先チェックは、デプロイまたはバックエンド再起動以外は完了済み。
- 次に必要なのは、更新済みの本番環境変数を Cloud Run などの本番バックエンドへ反映し、バックエンドを再デプロイまたは再起動すること。

## 最優先チェック

- [x] 本番バックエンド環境変数 `STRIPE_SECRET_KEY` に、今回作成した制限付きキー `rk_live_...` を設定する。
- [x] 既存の標準シークレットキー `sk_live_...` を使い続ける場合でも、本番 Stripe アカウントのキーであることを確認する。
- [x] 本番バックエンド環境変数 `STRIPE_PRICE_ID` が、本番の商品 `けいかくん有料課金` の `price_...` になっていることを確認する。
- [x] `rk_live_...` / `sk_live_...` と `price_...` が同じ本番 Stripe アカウントに属していることを確認する。
- [ ] Cloud Run など本番環境に環境変数を反映後、バックエンドを再デプロイまたは再起動する。

## Stripe 環境変数の説明

本番環境で設定する Stripe 関連の環境変数は以下。

| 環境変数 | 値の形式 | 用途 | 確認場所 | 注意点 |
| --- | --- | --- | --- | --- |
| `STRIPE_PRICE_ID` | `price_...` | Checkout Session 作成時に、月額 6,000 円の課金プランを指定する。 | Stripe Dashboard > 商品カタログ > `けいかくん有料課金` > 料金/価格 | 本番用の Price ID を設定する。テスト環境の `price_...` を本番キーと組み合わせると失敗する。 |
| `STRIPE_PUBLISHABLE_KEY` | `pk_live_...` | フロントエンドで Stripe.js などを使う場合の公開可能キー。 | Stripe Dashboard > 開発者 > API キー | 公開可能キーなので秘匿情報ではない。ただし本番は `pk_live_...`、テストは `pk_test_...` を使い分ける。現実装では Checkout 遷移はバックエンド作成 URL を使うため、直接利用が限定的な可能性がある。 |
| `STRIPE_SECRET_KEY` | `sk_live_...` または `rk_live_...` | バックエンドから Stripe API を呼ぶための秘密キー。Checkout Session 作成、Customer 作成、Portal Session 作成、Subscription 削除に使う。 | Stripe Dashboard > 開発者 > API キー > シークレットキー / 制限付きキー | 本番では `sk_live_...` または今回作成した制限付きキー `rk_live_...` を設定する。外部公開禁止。権限不足だと Checkout 作成が 500 になる。 |
| `STRIPE_WEBHOOK_SECRET` | `whsec_...` | Stripe から届いた Webhook の署名検証に使う。 | Stripe Dashboard > 開発者 > Webhook > 対象 endpoint > 署名シークレット | `STRIPE_SECRET_KEY` とは別物。endpoint ごとに値が異なる。本番 endpoint の `whsec_...` を設定する。 |

環境ごとの対応:

- 本番: `pk_live_...`、`sk_live_...` または `rk_live_...`、本番 `price_...`、本番 endpoint の `whsec_...`
- テスト: `pk_test_...`、`sk_test_...` または `rk_test_...`、テスト `price_...`、テスト endpoint の `whsec_...`

混在させてはいけない例:

- `STRIPE_SECRET_KEY=rk_live_...` に `STRIPE_PRICE_ID=price_...` のテスト用 Price ID を組み合わせる。
- 本番 Webhook endpoint にテスト endpoint の `whsec_...` を設定する。
- 本番 DB の `stripe_customer_id` にテスト環境で作成された `cus_...` を残す。

## 制限付き API キーの権限

最低限、以下が必要。

- [ ] `Checkout Sessions`: 書き込み
- [ ] `Customers`: 書き込み
- [ ] `Products`: 読み取り
- [ ] `Prices`: 読み取り
- [ ] `Subscriptions`: 書き込み
- [ ] `Billing` または `Billing Portal / Customer Portal` 相当: 書き込み
- [ ] `Invoices`: 読み取り
- [ ] `Payment Methods`: 読み取り以上
- [ ] `Tax`: 書き込み

補足:

- アプリは `stripe.checkout.Session.create(...)`、`stripe.Customer.create(...)`、`stripe.billing_portal.Session.create(...)`、`stripe.Subscription.delete(...)` を使う。
- Webhook endpoint をアプリから作成・更新していないため、`Webhook Endpoints` の書き込み権限はアプリ実行時には不要。

## Stripe 商品・価格

- [ ] 商品カタログに本番モードの商品 `けいかくん有料課金` が存在する。
- [ ] 価格が `¥6,000 / 月` の recurring price になっている。
- [ ] 価格が active になっている。
- [ ] 本番環境変数 `STRIPE_PRICE_ID` がその価格の `price_...` と一致している。

## Automatic Tax

実装では Checkout Session 作成時に `automatic_tax={'enabled': True}` を指定している。

- [ ] Stripe Tax / Automatic Tax が有効化されている。
- [ ] 本社住所の確認が完了している。
- [ ] デフォルト税コードが設定されている。
- [ ] 商品または価格に適切な税コードが設定されている。
- [ ] 税務登録が必要な場合、登録が追加されている。

## Webhook 設定

Checkout 500 の直接原因ではないが、Checkout 成功後の課金ステータス更新に必要。

- [ ] 本番 Webhook endpoint が `https://api.keikakun.com/api/v1/billing/webhook` になっている。
- [ ] 本番環境変数 `STRIPE_WEBHOOK_SECRET` に、該当 endpoint の `whsec_...` が設定されている。
- [ ] 購読イベントに `customer.subscription.created` が含まれている。
- [ ] 購読イベントに `customer.subscription.updated` が含まれている。
- [ ] 購読イベントに `customer.subscription.deleted` が含まれている。
- [ ] 購読イベントに `invoice.payment_succeeded` が含まれている。
- [ ] 購読イベントに `invoice.payment_failed` が含まれている。

## DB 側確認

対象事業所の billing レコードを確認する。

- [ ] `stripe_customer_id` が本番 Stripe アカウントに存在する Customer ID か。
- [ ] テスト環境の `cus_...` が本番 DB に入っていないか。
- [ ] `trial_end_date` が不正な過去日になっていないか。
- [ ] `billing_status` が想定どおりか。

## Stripe 顧客 ID の確認場所

Stripe 顧客 ID は `cus_...` で始まる値。

確認方法:

- Stripe Dashboard 左メニューの `顧客` を開き、対象メールアドレスまたは事業所名で検索する。
- 顧客詳細画面の URL または詳細欄で `cus_...` を確認する。
- Checkout に遷移済みの場合は、Stripe Dashboard の `決済`、`Checkout セッション`、または `イベント` から対象セッションを開き、関連する Customer を確認する。
- Webhook 到達後であれば、`customer.subscription.created` や `invoice.payment_succeeded` のイベント詳細内の `customer` に `cus_...` が表示される。
- アプリ側 DB では `billings.stripe_customer_id` に保存される。

今回の確認ポイント:

- 本番 DB の `billings.stripe_customer_id` が空なら、次回 Checkout Session 作成時に Stripe Customer が新規作成される。
- `billings.stripe_customer_id` に値がある場合、その `cus_...` が Stripe 本番モードの `顧客` に存在するか確認する。
- テストモードの顧客 ID が本番 DB に入っている場合、本番 Checkout Session 作成時に `No such customer` 系のエラーになる可能性がある。

## 再テスト手順

- [x] 本番環境変数を更新する。
- [ ] バックエンドを再デプロイまたは再起動する。
- [ ] 本番画面の管理者設定 > プランから「サブスクリプションに登録する」を押す。
- [ ] `POST https://api.keikakun.com/api/v1/billing/create-checkout-session` が 200 になることを確認する。
- [ ] Stripe Checkout 画面へ遷移することを確認する。
- [ ] まだ 500 の場合、本番ログで `Stripe API error:` または `Stripe Checkout Session作成エラー:` の直後のエラー本文を確認する。

## よくある原因

- `STRIPE_SECRET_KEY` は本番だが、`STRIPE_PRICE_ID` がテスト環境の `price_...`。
- 制限付きキーに `Checkout Sessions` 書き込み権限がない。
- 制限付きキーに `Customers` 書き込み権限がない。
- 制限付きキーに `Subscriptions` 書き込み権限がない。
- Automatic Tax の本番設定が未完了。
- 本番 DB にテスト環境の `stripe_customer_id` が残っている。

## 新たに判明した問題: Trial 期限切れ事業所の Checkout 500

2026-06-16 時点で、新しく作成したアカウントでは Stripe Checkout 画面まで正常に遷移できた。一方で、`trial_end_date` が現在日時を過ぎている既存事業所では `create-checkout-session` が 500 になる。

この結果から、`STRIPE_SECRET_KEY`、`STRIPE_PRICE_ID`、Checkout Sessions 権限、Customers 権限、Automatic Tax の基本設定は大枠では通っていると考えられる。今回の 500 は Stripe 設定だけではなく、期限切れ trial の DB 状態と実装の組み合わせで発生している可能性が高い。

### 実装上の期待動作

`k_back/app/tasks/billing_check.py` の `check_trial_expiration()` は、以下の条件で billing を抽出する。

```python
Billing.billing_status.in_([BillingStatus.free, BillingStatus.early_payment])
Billing.trial_end_date < now
```

更新先は以下。

- `free` → `past_due`
- `early_payment` → `active`

つまり、`trial_end_date` が過去になっただけでは自動で `past_due` にならない。`check_trial_expiration()` が実行されて初めて `billing_status` が更新される。

### バッチ起動処理の懸念

`k_back/app/scheduler/billing_scheduler.py` には、ジョブ登録を行う独自の `start()` 関数がある。

```python
def start():
    billing_scheduler.add_job(...)
    billing_scheduler.add_job(...)
    billing_scheduler.start()
```

しかし `k_back/app/main.py` では以下のように `AsyncIOScheduler` インスタンス自体を import している。

```python
from app.scheduler.billing_scheduler import billing_scheduler
```

startup でも以下を実行している。

```python
billing_scheduler.start()
```

これは `billing_scheduler.py` の独自 `start()` 関数ではなく、`AsyncIOScheduler.start()` を直接呼ぶ形になる。そのため、`add_job(...)` が実行されず、`check_trial_expiration` ジョブが登録されていない可能性が高い。

この場合、以下の状態遷移が本番で発生しない。

- `free` → `past_due`
- `early_payment` → `active`
- `canceling` → `canceled`

Cloud Run が scale-to-zero する構成の場合、仮にジョブ登録を修正しても、指定時刻にインスタンスが起動していなければ APScheduler は実行されない。課金状態の更新は Cloud Scheduler / Cloud Run Jobs など外部バッチ基盤で実行する設計も検討する。

### 500 が起きる推定シナリオ

問題が起きやすい DB 状態:

```text
billing_status = 'free'
trial_end_date < now()
stripe_customer_id IS NULL
```

発生シナリオ:

1. Trial 期限が切れる。
2. 本来はバッチで `free → past_due` になるべきだが、バッチが実行されず `free` のまま残る。
3. ユーザーが管理者設定 > プランから「サブスクリプションに登録する」を押す。
4. `k_back/app/api/v1/endpoints/billing.py` の `create_checkout_session()` が呼ばれる。
5. `stripe_customer_id` がないため、`BillingService.create_checkout_session_with_customer()` へ進む。
6. `k_back/app/services/billing_service.py` で Customer 作成後、Checkout Session 作成時に常に `trial_end` を渡す。

```python
subscription_data={
    'trial_end': int(trial_end_date.timestamp()),
    'metadata': ...
}
```

7. `trial_end_date` が過去のため、Stripe API が `trial_end` 不正として Checkout Session 作成を拒否する可能性がある。
8. アプリは `Checkout Sessionの作成に失敗しました` として 500 を返す。

既存 Customer がある場合は別ルートで、`trial_end_date` が未来の場合のみ `trial_end` を渡す実装になっている。

```python
if billing.trial_end_date and billing.trial_end_date > now:
    subscription_data_params['trial_end'] = int(billing.trial_end_date.timestamp())
```

そのため、特に `stripe_customer_id IS NULL` の期限切れ事業所で 500 が起きやすい。

### 実装修正候補

- [ ] `main.py` の billing scheduler 起動を修正し、`billing_scheduler.py` の独自 `start()` 関数でジョブ登録されるようにする。
- [ ] `BillingService.create_checkout_session_with_customer()` でも、既存 Customer ルートと同様に `trial_end_date > now` の場合のみ `trial_end` を渡す。
- [ ] Checkout 作成前に `billing_status=free` かつ `trial_end_date < now` を検知したら `past_due` に補正する。
- [ ] Cloud Run の scale-to-zero を前提に、課金バッチを Cloud Scheduler / Cloud Run Jobs で確実に実行する運用を検討する。

### 暫定復旧 SQL

対象事業所だけ救済する場合:

```sql
UPDATE billings
SET billing_status = 'past_due',
    updated_at = NOW()
WHERE office_id = '<対象 office_id>'
  AND billing_status = 'free'
  AND trial_end_date < NOW();
```

期限切れの `free` をまとめて補正する場合:

```sql
UPDATE billings
SET billing_status = 'past_due',
    updated_at = NOW()
WHERE billing_status = 'free'
  AND trial_end_date < NOW();
```

実行前に必ず対象件数を確認する。

```sql
SELECT id, office_id, billing_status, trial_end_date, stripe_customer_id
FROM billings
WHERE billing_status = 'free'
  AND trial_end_date < NOW();
```

## 本番環境での Checkout / 課金処理テスト方針

本番環境で確認したい内容は、実課金が必要なものと不要なものに分ける。

### 実課金なしで確認できること

以下は本番 Checkout 画面まで到達すれば確認できる。

- `POST /api/v1/billing/create-checkout-session` が 200 になること。
- Stripe Checkout URL が返ること。
- Stripe Checkout 画面に遷移できること。
- 商品名、価格、通貨、月額設定が正しいこと。
- Automatic Tax / 住所入力 / Link / カード入力 UI が表示されること。
- Stripe Dashboard に Checkout Session が作成されること。
- アプリが Stripe Customer を作成できること。

ただし、Checkout 画面を開いただけでは `customer.subscription.created` や `invoice.payment_succeeded` は発火しない。アプリの `billing_status` 更新までは確認できない。

### 実課金または本番カード決済が必要なこと

以下は原則として本番決済を完了しないと確認できない。

- 本番カードで支払いが成功すること。
- 本番 Stripe で Subscription が作成されること。
- `customer.subscription.created` Webhook が本番 API に届くこと。
- `invoice.payment_succeeded` Webhook が届くこと。
- アプリ DB の `stripe_subscription_id` が保存されること。
- `billing_status` が `early_payment` または `active` に変わること。

本番モードでは Stripe のテストカードは使えない。テストカードで課金フロー全体を確認する場合は、テストモードまたは sandbox 環境で行う。

### 実課金を避けたい場合の確認方法

本番で実課金せずに確認できる範囲:

1. Checkout 画面まで遷移して、支払い直前で止める。
2. Stripe Dashboard の Checkout Session 作成履歴を確認する。
3. 本番ログで `Stripe Checkout Session created` 相当のログを確認する。
4. DB に `stripe_customer_id` が保存されているか確認する。

これで「Checkout Session 作成」「Customer 作成」「Price / API Key / Tax 設定」は確認できる。

ただし、Webhook によるサブスク作成後の状態更新は確認できない。Webhook まで含めた本番検証をするには、少額の本番 Price を別途用意して決済する、または本番で実際に 6,000 円決済して即時返金する運用が必要になる。

### 本番で課金まで確認する場合の安全な手順

- [ ] 本番用の一時テスト事業所を作成する。
- [ ] 可能なら Stripe 本番に少額の検証用 recurring Price を作成し、検証時だけ `STRIPE_PRICE_ID` を差し替える。ただし本番設定変更のリスクがあるため慎重に行う。
- [ ] 少額 Price を使わない場合は、実際に 6,000 円の本番決済を行う。
- [ ] 決済成功後、Stripe Dashboard で Payment / Subscription / Customer を確認する。
- [ ] Webhook endpoint の配信結果が 2xx になっていることを確認する。
- [ ] DB の `billings.billing_status`、`stripe_customer_id`、`stripe_subscription_id` を確認する。
- [ ] 検証後、必要に応じて Stripe Dashboard で返金またはサブスク解約を行う。
- [ ] 返金は `invoice.payment_succeeded` の検証とは別物。返金してもサブスク状態やアプリ DB 状態の扱いは別途確認する。

### テストモードで確認すべきこと

本番で実課金したくない場合、以下は Stripe テストモードで重点確認する。

- Checkout 完了。
- `customer.subscription.created` の Webhook 到達。
- `invoice.payment_succeeded` の Webhook 到達。
- `invoice.payment_failed` の Webhook 到達。
- `customer.subscription.updated` の Webhook 到達。
- `customer.subscription.deleted` の Webhook 到達。
- `free → past_due` のバッチ更新。
- `early_payment → active` のバッチ更新。

特に `free → past_due` は Stripe Webhook ではなくアプリ側バッチでしか起きないため、Stripe の本番設定確認だけでは検証できない。
