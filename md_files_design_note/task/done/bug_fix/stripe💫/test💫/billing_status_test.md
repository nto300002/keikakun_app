# Billing Status テスト要件チェックリスト

作成日: 2026-06-21

チェック欄の記法:

- `[local][prod]`
- 左側がlocal確認、右側がprod確認。

## 前提

- `billing_status` は以下を扱う。
  - `free`
  - `trial_expired`
  - `early_payment`
  - `active`
  - `payment_failed`
  - `past_due`
  - `canceling`
  - `canceled`
- `past_due` は後方互換用として残す。
- 新規遷移では、原則として以下へ意味を分離する。
  - trial終了後・未課金: `trial_expired`
  - 継続課金中の請求失敗: `payment_failed`
  - 期間終了キャンセル待ち: `canceling`
  - キャンセル完了: `canceled`
- Checkout画面での即時決済失敗は `payment_failed` に含めない。
  - 例: trial期限切れ後の登録Checkoutでカード拒否され、`payment_intent.payment_failed` / `charge.failed` が発生しただけの状態。
  - 理由: `payment_failed` は有効な課金契約または継続課金中の請求失敗を表すstatusとして扱い、単発の入力失敗・カード拒否とは分離する。
  - この場合は `trial_expired` のまま維持し、必要に応じてWebhookイベントログのみ記録する。

## 今回確認したケース

### 試用期限切れ・Stripe未紐づけ・登録導線表示

確認日: 2026-06-21

DB状態:

- `billing_status = trial_expired`
- `trial_end_date < now`
- `stripe_customer_id IS NULL`
- `stripe_subscription_id IS NULL`
- `scheduled_cancel_at IS NULL`

期待:
local/prod
- [x][ ] 画面ステータスが「無料期間終了」と表示される。
- [x][ ] Stripe Customer Portal / キャンセル導線ではなく、登録導線が表示される。
- [x][ ] ボタン文言が「有料会員に登録する」または同等の登録導線になる。
- [x][ ] 説明文が「有料会員登録が完了するまで、一部の操作が制限されている」趣旨になる。
- [x][ ] `stripe_customer_id` / `stripe_subscription_id` / `scheduled_cancel_at` が `NULL` のままでも異常扱いしない。

判断:

- この状態は正しい。
- 理由: Stripe未紐づけの期限切れtrialは、キャンセル対象のSubscriptionが存在しないため、キャンセルではなく登録導線を出すべき。

### 継続課金中の支払い失敗・payment_failed遷移

確認日: 2026-06-25

確認方法:

- Stripe Test Clock を CLI で作成。
- `pm_card_chargeCustomerFail` を Customer に attach し、Customer の `invoice_settings.default_payment_method` に設定。
- trial 付き Subscription を作成。
- Test Clock を trial 終了後、かつ invoice の `next_payment_attempt` より後まで進めた。

対象:

- Billing: `efed2984-c503-42a5-8d53-27dcbd7c898c`
- Stripe Customer: `cus_UlaK3MywP6FYR1`
- Stripe Subscription: `sub_1Tm5NlBxyBErCNcALarLanKJ`

確認結果:
local/prod
- [x][ ] Stripe 側で `invoice.payment_failed` が発生する。
- [x][ ] local webhook が `invoice.payment_failed` を受信する。
- [x][ ] `webhook_events` に `invoice.payment_failed` が `success` として記録される。
- [x][ ] 対象 Billing が `active` から `payment_failed` に遷移する。
- [x][ ] Stripe 側 Subscription が `past_due` になっても、アプリ側 Billing は意味分離した `payment_failed` になる。

根拠:

- Stripe invoice: `status = open`, `attempted = true`, `attempt_count = 1`
- `webhook_events.event_type = invoice.payment_failed`
- `webhook_events.status = success`
- `billings.billing_status = payment_failed`

実行コマンド:

前提確認として、Test Clock / Subscription / Invoice の状態を Stripe API で確認した。

```bash
docker exec keikakun_app-backend-1 python -c "import os, stripe, json, datetime; stripe.api_key=os.environ['STRIPE_SECRET_KEY']; clock=stripe.test_helpers.TestClock.retrieve('clock_1Tm2yyBxyBErCNcAiWIAUcPs'); sub=stripe.Subscription.retrieve('sub_1Tm5NlBxyBErCNcALarLanKJ', expand=['latest_invoice']); li=sub.get('latest_invoice'); print(json.dumps({'clock':{'id':clock.get('id'),'status':clock.get('status'),'frozen_time':clock.get('frozen_time'),'frozen_time_utc':datetime.datetime.fromtimestamp(clock.get('frozen_time'), datetime.UTC).isoformat()},'subscription':{'id':sub.get('id'),'status':sub.get('status')},'latest_invoice':{'id':li.get('id'),'status':li.get('status'),'attempted':li.get('attempted'),'attempt_count':li.get('attempt_count'),'next_payment_attempt':li.get('next_payment_attempt'),'next_payment_attempt_utc':datetime.datetime.fromtimestamp(li.get('next_payment_attempt'), datetime.UTC).isoformat() if li.get('next_payment_attempt') else None}}, ensure_ascii=False, indent=2))"
```

この時点では以下だった。

```text
clock.frozen_time = 1782192000
clock.frozen_time_utc = 2026-06-23T05:20:00+00:00
latest_invoice.status = draft
latest_invoice.attempted = false
latest_invoice.attempt_count = 0
latest_invoice.next_payment_attempt = 1782195600
latest_invoice.next_payment_attempt_utc = 2026-06-23T06:20:00+00:00
```

対象 Billing の事前状態を確認した。

```bash
docker exec keikakun_app-backend-1 python -c "import os; from sqlalchemy import create_engine, text; e=create_engine(os.environ['DATABASE_URL'].replace('+psycopg','')); c=e.connect(); rows=c.execute(text(\"SELECT id, stripe_customer_id, stripe_subscription_id, billing_status::text, trial_end_date, updated_at FROM billings WHERE id = 'efed2984-c503-42a5-8d53-27dcbd7c898c'\")).mappings().all(); [print(dict(r)) for r in rows]; c.close()"
```

事前状態:

```text
billing_status = active
stripe_customer_id = cus_UlaK3MywP6FYR1
stripe_subscription_id = sub_1Tm5NlBxyBErCNcALarLanKJ
```

Test Clock を `next_payment_attempt` より後の `1782199200` まで進めた。

```bash
docker exec keikakun_app-backend-1 python -c "import os, stripe, json, datetime; stripe.api_key=os.environ['STRIPE_SECRET_KEY']; clock=stripe.test_helpers.TestClock.advance('clock_1Tm2yyBxyBErCNcAiWIAUcPs', frozen_time=1782199200); print(json.dumps({'id':clock.get('id'),'status':clock.get('status'),'frozen_time':clock.get('frozen_time'),'frozen_time_utc':datetime.datetime.fromtimestamp(clock.get('frozen_time'), datetime.UTC).isoformat()}, ensure_ascii=False, indent=2))"
```

advance 直後は `status = advancing` だったため、20秒待ってから ready 復帰を確認した。

```bash
docker exec keikakun_app-backend-1 python -c "import os, stripe, time, json, datetime; stripe.api_key=os.environ['STRIPE_SECRET_KEY']; time.sleep(20); clock=stripe.test_helpers.TestClock.retrieve('clock_1Tm2yyBxyBErCNcAiWIAUcPs'); print(json.dumps({'id':clock.get('id'),'status':clock.get('status'),'frozen_time':clock.get('frozen_time'),'frozen_time_utc':datetime.datetime.fromtimestamp(clock.get('frozen_time'), datetime.UTC).isoformat()}, ensure_ascii=False, indent=2))"
```

ready 復帰後:

```text
clock.status = ready
clock.frozen_time = 1782199200
clock.frozen_time_utc = 2026-06-23T07:20:00+00:00
```

Clock advance 後の Stripe Subscription / Invoice 状態を確認した。

```bash
docker exec keikakun_app-backend-1 python -c "import os, stripe, json, datetime; stripe.api_key=os.environ['STRIPE_SECRET_KEY']; sub=stripe.Subscription.retrieve('sub_1Tm5NlBxyBErCNcALarLanKJ', expand=['latest_invoice.payment_intent','latest_invoice.charge']); li=sub.get('latest_invoice'); print(json.dumps({'subscription':{'id':sub.get('id'),'status':sub.get('status'),'trial_end':sub.get('trial_end'),'test_clock':sub.get('test_clock')},'latest_invoice':{'id':li.get('id'),'status':li.get('status'),'paid':li.get('paid'),'attempted':li.get('attempted'),'attempt_count':li.get('attempt_count'),'amount_due':li.get('amount_due'),'billing_reason':li.get('billing_reason'),'next_payment_attempt':li.get('next_payment_attempt'),'payment_intent':li.get('payment_intent').get('id') if hasattr(li.get('payment_intent'),'get') else li.get('payment_intent')}}, ensure_ascii=False, indent=2))"
```

確認結果:

```text
subscription.status = past_due
latest_invoice.status = open
latest_invoice.attempted = true
latest_invoice.attempt_count = 1
latest_invoice.amount_due = 6000
latest_invoice.billing_reason = subscription_cycle
```

Stripe 側イベントを確認した。

```bash
docker exec keikakun_app-backend-1 python -c "import os, stripe, json, datetime; stripe.api_key=os.environ['STRIPE_SECRET_KEY']; evs=stripe.Event.list(limit=50); data=[{'id':e.get('id'),'type':e.get('type'),'created_utc':datetime.datetime.fromtimestamp(e.get('created'), datetime.UTC).isoformat(),'object_id':e.data.object.get('id'),'customer':e.data.object.get('customer'),'status':e.data.object.get('status')} for e in evs.data if e.data.object.get('customer') == 'cus_UlaK3MywP6FYR1' or e.data.object.get('id') == 'clock_1Tm2yyBxyBErCNcAiWIAUcPs']; print(json.dumps(data, ensure_ascii=False, indent=2))"
```

確認できた主な Stripe event:

```text
invoice.finalized
customer.subscription.updated
charge.failed
payment_intent.payment_failed
payment_intent.created
invoice.updated
invoice.payment_failed
test_helpers.test_clock.ready
```

Clock advance 後の Billing 状態を確認した。

```bash
docker exec keikakun_app-backend-1 python -c "import os; from sqlalchemy import create_engine, text; e=create_engine(os.environ['DATABASE_URL'].replace('+psycopg','')); c=e.connect(); rows=c.execute(text(\"SELECT id, stripe_customer_id, stripe_subscription_id, billing_status::text, trial_end_date, updated_at FROM billings WHERE id = 'efed2984-c503-42a5-8d53-27dcbd7c898c'\")).mappings().all(); [print(dict(r)) for r in rows]; c.close()"
```

確認結果:

```text
billing_status = payment_failed
```

最後に `webhook_events` で `invoice.payment_failed` の受信と成功記録を確認した。

```bash
docker exec keikakun_app-backend-1 python -c "import os; from sqlalchemy import create_engine, text; e=create_engine(os.environ['DATABASE_URL'].replace('+psycopg','')); c=e.connect(); rows=c.execute(text(\"SELECT event_id, event_type, status, billing_id, office_id, payload, error_message, created_at FROM webhook_events WHERE payload::text LIKE '%cus_UlaK3MywP6FYR1%' OR billing_id = 'efed2984-c503-42a5-8d53-27dcbd7c898c'::uuid ORDER BY created_at DESC LIMIT 20\")).mappings().all(); print('events=', len(rows)); [print(dict(r)) for r in rows]; c.close()"
```

確認結果:

```text
event_type = invoice.payment_failed
status = success
billing_id = efed2984-c503-42a5-8d53-27dcbd7c898c
office_id = c8ccd252-3178-4cce-914d-75a7b9cab624
payload.customer_id = cus_UlaK3MywP6FYR1
```

## DB・Enum

- [x][ ] `billingstatus` enum に `trial_expired` が存在する。
- [x][ ] `billingstatus` enum に `payment_failed` が存在する。
- [x][ ] `billingstatus` enum に既存値 `past_due` が残っている。
- [x][ ] `billings.billing_status` のCHECK制約またはPostgreSQL enumが上記statusを許可している。("ck_billings_billing_status" CHECK (billing_status::text = ANY (ARRAY['free'::character varying::text, 'early_payment'::character varying::text, 'active'::character varying::text, 'past_due'::character varying::text, 'trial_expired'::character varying::text, 'payment_failed'::character varying::text, 'canceling'::character varying::text, 'canceled'::character varying::text])))
- [x][ ] 手動SQLとAlembic migrationの定義に差分がない。

## Backend: Trial期限切れ

- [x][ ] `free + trial_end_date < now` は `check_trial_expiration()` で `trial_expired` になる。
- [x][ ] `early_payment + trial_end_date < now` は `check_trial_expiration()` で `active` になる。
- [x][ ] `/billing/status` 取得時に `free + trial_end_date < now` は `trial_expired` へ補正される。
- [x][ ] `/billing/status` 取得時に `early_payment + trial_end_date < now` は `active` へ補正される。
- [x][ ] `active` は trial期限切れバッチで変更されない。
- [x][ ] `past_due` は互換用として、trial期限切れバッチで自動変換しない。
- [x][ ] `canceling` は trial期限切れバッチで自動変換しない。
- [x][ ] trial期限切れバッチのログは更新前statusから更新後statusへの遷移を出す。

## Backend: Checkout

- 通常導線では、Checkout作成前に `/billing/status` 取得で期限切れ補正が走るため、画面操作から `free + trial_end_date < now` のままCheckout作成へ進む状態は原則再現しない。
- そのため、期限切れfreeのCheckout要件は「通常導線の画面テスト」ではなく、status取得を経由しない stale データに対する防御的APIテストとして検証する。
- [x][ ] 通常導線では、`free + trial_end_date < now` はCheckoutボタン押下前に `trial_expired` として扱われる。
- [x][ ] 防御的APIテストとして、`free + trial_end_date < now + stripe_customer_id IS NULL` でCheckout作成しても500にならない。
- [x][ ] 防御的APIテストとして、上記の場合、Checkout前補正で `trial_expired` になる。
- [x][ ] 防御的APIテストとして、上記の場合、Stripeへ過去の `trial_end` を渡さない。
- [x][ ] 防御的APIテストとして、`free + trial_end_date < now + stripe_customer_idあり` でもCheckout作成しても500にならない。
- [x][ ] 防御的APIテストとして、上記の場合、Checkout前補正で `trial_expired` になる。
- [x][ ] `free + trial_end_date > now` では従来どおりStripeへ `trial_end` を渡す。
- [x][ ] Checkout失敗時に、Customer作成やstatus補正のrollback方針がテストされている。

## Backend: Payment Webhook

- [x][ ] `invoice.payment_succeeded` で対象Billingが `active` または `early_payment` へ正しく遷移する。
- [x][ ] trial期間中の `invoice.payment_succeeded` は `early_payment` を維持する。
- [x][ ] trial期間外の `invoice.payment_succeeded` は `active` になる。
- [x][ ] `invoice.payment_failed + trial_end_date < now` は `payment_failed` になる。
- [x][ ] `invoice.payment_failed + trial_end_date > now` は `payment_failed` / `past_due` に落とさない。
- [x][ ] 継続課金中の支払い失敗は `invoice.payment_failed` を基準に `payment_failed` へ遷移する。
- [x][ ] `payment_intent.payment_failed` はCheckout中の即時決済失敗として扱い、`billing_status` を `payment_failed` に変更しない。
- [x][ ] `charge.failed` は補助ログ扱いとし、`billing_status` を `payment_failed` に変更しない。
- [x][ ] `trial_expired` のCheckout即時決済失敗では、`trial_expired` のまま維持される。
- [x][ ] 存在しないStripe CustomerのWebhookは `skipped` として記録される。

```
2026-06-22 11:33:00   --> invoice.payment_succeeded [evt_1TkxfUBxyBErCNcAXO7ceT5A]
2026-06-22 11:33:03  <--  [200] POST http://localhost:8000/api/v1/billing/webhook [evt_1TkxfTBxyBErCNcAL7oqVky0]
```
## Backend: Subscription Webhook

- [x][ ] `customer.subscription.created + trial_end_date > now` は `early_payment` になる。
- [x][ ] `customer.subscription.created + trial_end_date <= now` は `active` になる。
- [x][ ] `invoice.payment_succeeded` が先、`customer.subscription.created` が後でも、trial中なら `early_payment` を維持する。
- [x][ ] `customer.subscription.updated + cancel_at_period_end=true` は、通常の課金中Subscriptionでは `canceling` になる。
- [x][ ] `customer.subscription.updated + cancel_at_period_end=true` は、`trial_expired` では即時 `canceled` になる。
- [x][ ] `customer.subscription.updated + cancel_at_period_end=true` は、`free/canceling + trial_end_date < now + last_payment_date IS NULL + subscription_start_date IS NULL` では即時 `canceled` になる。
- [x][ ] 即時 `canceled` になる場合、`scheduled_cancel_at` は `NULL` になる。
- [x][ ] `customer.subscription.deleted` は `canceled` になり、`scheduled_cancel_at` を `NULL` にする。
- [x][ ] 直近10分以内に同一Billingの `invoice.payment_failed` が成功記録されている場合、`customer.subscription.deleted` は支払い失敗起因のStripe自動削除として扱い、`payment_failed` を維持する。
- [x][ ] `canceling + scheduled_cancel_at < now` はバッチで `canceled` になる。
- [x][ ] `canceling` のキャンセル取り消しWebhookでは、trial中なら `early_payment`、trial外なら `active` へ戻る。

確認日: 2026-06-28

local確認コマンド:

```bash
docker exec keikakun_app-backend-1 pytest \
  tests/services/test_billing_service.py \
  -k "subscription_created or subscription_updated or subscription_deleted or scheduled" \
  -q
```

結果:

```text
11 passed, 16 deselected in 95.84s
```

補足:

- 初回実行では `test_process_subscription_deleted_after_recent_payment_failed_keeps_payment_failed` が一時的に FK 制約で失敗した。
- 同テスト単体では `1 passed`。
- Subscription created/deleted 周辺5件でも `5 passed`。
- 最終的に上記11件の再実行で全件通過したため、local確認済みとした。

## Backend: Access Control

- [x][ ] `free` は有料機能不可。
- [x][ ] `trial_expired` は有料機能不可。
- [x][ ] `payment_failed` は有料機能不可。
- [x][ ] `past_due` は有料機能不可。
- [x][ ] `canceled` は有料機能不可。
- [x][ ] `early_payment` は有料機能可。
- [x][ ] `active` は有料機能可。
- [x][ ] `canceling` はキャンセル予定日までは有料機能可。
- [x][ ] `require_active_billing()` が `trial_expired` / `payment_failed` / `past_due` / `canceled` を制限する。

確認日: 2026-06-29

local確認コマンド:

```bash
docker exec keikakun_app-backend-1 pytest tests/services/test_billing_status_helpers.py -q
```

結果:

```text
12 passed in 123.10s
```

確認内容:

- `crud.billing.can_access_paid_features()` で `early_payment` / `active` / `canceling` が `True`。
- `crud.billing.can_access_paid_features()` で `free` / `past_due` / `trial_expired` / `payment_failed` / `canceled` が `False`。
- `require_active_billing()` が `past_due` / `trial_expired` / `payment_failed` / `canceled` を `402` で制限する。
- `require_active_billing()` が `free` / `early_payment` / `active` / `canceling` を通す。

補足:

- `free` は有料機能判定では不可。
- ただし `require_active_billing()` では無料期間中の通常利用を許可するため、制限対象には含めない。

## Frontend: 表示と導線

- [x][ ] `free` は無料期間中として表示される。
- [x][ ] `trial_expired` は「無料期間終了」と表示される。
- [x][ ] `trial_expired + stripe_customer_id IS NULL + stripe_subscription_id IS NULL` は登録導線を表示する。
- [x][ ] `trial_expired` でキャンセル導線を表示しない。
- [x][ ] `payment_failed` は「支払い失敗」と表示される。
- [x][ ] `payment_failed` は支払い方法更新またはCustomer Portal導線を表示する。
- [x][ ] `past_due` は互換表示として残る。
- [x][ ] `canceling` は「キャンセル予定」と表示され、予定日があれば表示する。
- [x][ ] `canceled` は「キャンセル済み」と表示され、再登録導線を表示する。
- [x][ ] `trial_expired` / `payment_failed + trial終了後` / `past_due` / `canceled` では `canWrite=false` になる。
- [x][ ] `early_payment` / `active` / `canceling` では `canWrite=true` になる。

### Frontend: `canceling` の条件とテスト方法

条件:

- [x][ ] `billing_status = canceling`
- [x][ ] `stripe_customer_id IS NOT NULL`
- [x][ ] `stripe_subscription_id IS NOT NULL`
- [x][ ] `scheduled_cancel_at IS NOT NULL`
- [x][ ] `scheduled_cancel_at > now()` の期間終了前状態で確認する。

期待:

- [x][ ] 管理者設定 > 有料会員でステータスが「キャンセル予定」と表示される。
- [x][ ] `scheduled_cancel_at` がある場合、キャンセル予定日が表示される。
- [x][ ] 「有料会員に登録する」導線ではなく、「支払い方法の変更・解約」導線が表示される。
- [x][ ] Dashboardでは支払い遅延・試用期限切れ・キャンセル済みの警告文を表示しない。
- [x][ ] Dashboardの新規作成・編集・削除などの操作は有効なまま。
- [x][ ] 支払いアクションモーダルは自動表示されない。

テスト方法:

1. 対象事務所のBillingを `canceling` にし、`scheduled_cancel_at` を未来日にする。
2. 管理者でログインし、管理者設定 > 有料会員を開く。
3. ステータス、キャンセル予定日、「支払い方法の変更・解約」導線を確認する。
4. 利用者ダッシュボードを開き、警告文が出ず、操作導線が有効なままであることを確認する。
5. `scheduled_cancel_at < now()` はBackendの期間終了処理で `canceled` へ遷移する対象のため、Frontendの `canceling` 手動確認では未来日を使う。

### Frontend: `canceled` の条件とテスト方法

条件:

- [x][ ] `billing_status = canceled`
- [x][ ] `scheduled_cancel_at IS NULL`
- [x][ ] `stripe_customer_id` / `stripe_subscription_id` が残っていても画面表示が破綻しない。
- [x][ ] `stripe_customer_id IS NULL` / `stripe_subscription_id IS NULL` の再登録ケースでも導線が表示される。

期待:

- [x][ ] 管理者設定 > 有料会員でステータスが「キャンセル済み」と表示される。
- [x][ ] 「支払い方法の変更・解約」導線ではなく、「有料会員に登録する」導線が表示される。
- [x][ ] Dashboardに「有料会員登録がキャンセル済みのため利用できません」の警告文が表示される。
- [x][ ] Dashboardの新規作成・編集・削除などの操作は無効化される。
- [x][ ] Dashboardで利用者名を表示する場合、名字だけでなくフルネームで表示される。
- [x][ ] 支払いアクションモーダルは自動表示されない。

テスト方法:

1. 対象事務所のBillingを `canceled` にし、`scheduled_cancel_at` を `NULL` にする。
2. 管理者でログインし、管理者設定 > 有料会員を開く。
3. ステータスが「キャンセル済み」と表示され、「有料会員に登録する」導線が表示されることを確認する。
4. 「支払い方法の変更・解約」導線が表示されないことを確認する。
5. 利用者ダッシュボードを開き、キャンセル済み警告、操作制限、フルネーム表示を確認する。
6. 再登録導線からStripe Checkoutへ遷移できることを確認する。

## 手動確認SQL

### 対象Billing確認

```sql
SELECT
  id,
  billing_status::text,
  trial_end_date,
  stripe_customer_id,
  stripe_subscription_id,
  subscription_start_date,
  next_billing_date,
  last_payment_date,
  scheduled_cancel_at,
  updated_at
FROM billings
WHERE id = '<BILLING_ID>'::uuid;
```

### Webhook確認

```sql
SELECT
  event_id,
  event_type,
  status,
  billing_id,
  office_id,
  payload,
  error_message,
  created_at
FROM webhook_events
ORDER BY created_at DESC
LIMIT 20;
```

### Stripe Customer未紐づけのWebhook skip確認

```sql
SELECT
  event_id,
  event_type,
  status,
  payload,
  created_at
FROM webhook_events
WHERE event_type = 'customer.subscription.updated'
ORDER BY created_at DESC
LIMIT 20;
```

## デプロイ判断

### local確認結果

- local環境では、本チェックリスト上の確認項目はすべて完了。
- `free` / `early_payment` / `active` / `trial_expired` / `payment_failed` / `past_due` / `canceling` / `canceled` の表示・導線・制限条件を確認済み。
- Stripe Test Clock を使い、継続課金中の `invoice.payment_failed` で `payment_failed` へ遷移することを確認済み。
- Checkout中の即時決済失敗は `payment_failed` にしない方針で整理済み。
- `canceling` は利用可能状態として扱い、`canceled` は利用制限状態として扱うことを確認済み。

### デプロイ可否

- [x][ ] local確認結果だけを見る限り、デプロイしてよい。
- [x][ ] ただし本番環境では、DB手動更新による状態作成ではなく、Stripe Dashboard / Webhook / アプリ操作を通じた確認を優先する。
- [x][ ] 本番データに対して `billing_status` や `stripe_customer_id` / `stripe_subscription_id` を直接変更する確認は、ユーザー影響があるため原則行わない。
- [x][ ] 本番デプロイ後は、少数の既存データ確認とWebhook受信確認を先に行い、問題がなければ通常運用に進む。

## 本番環境でのテスト方針

### 事前確認

1. 本番のStripe Webhook送信先が正しいAPIエンドポイントを向いていることを確認する。
2. 本番のWebhook secretがアプリ環境変数と一致していることを確認する。
3. 本番DBの `billingstatus` enum / CHECK制約に `trial_expired` / `payment_failed` / `canceling` / `canceled` が含まれていることを確認する。
4. デプロイ直後に `webhook_events` の直近レコードを確認し、通常のWebhook処理が失敗していないことを確認する。

### 本番で確認する項目

- [ ][ ] 既存の `active` 事務所が「有料会員」と表示され、通常操作できる。
- [ ][ ] 既存の `early_payment` 事務所が「有料会員登録済み」と表示され、通常操作できる。
- [ ][ ] 既存の `canceling` 事務所がある場合、「キャンセル予定」と表示され、予定日が表示される。
- [ ][ ] 既存の `canceled` 事務所がある場合、「キャンセル済み」と表示され、再登録導線が表示される。
- [ ][ ] `trial_expired` / `payment_failed` / `past_due` / `canceled` の事務所では、Dashboardの新規作成・編集・削除が制限される。
- [ ][ ] `early_payment` / `active` / `canceling` の事務所では、Dashboardの新規作成・編集・削除が制限されない。

### 本番で避けること

- 本番DBで実在ユーザーの `billing_status` を手動変更して状態を作る。
- 本番Stripeの実Subscriptionをテスト目的でキャンセルする。
- 本番の支払い失敗を意図的に発生させる。
- `stripe_customer_id` / `stripe_subscription_id` を本番DBで別Customerや別Subscriptionに差し替える。

### 本番での安全な確認方法

1. デプロイ後、通常ログインで管理者設定 > 有料会員を開き、現在の課金状態表示が崩れていないことを確認する。
2. 利用者ダッシュボードを開き、`canWrite` によるボタン制御や警告文が想定通りであることを確認する。
3. `webhook_events` の直近レコードを確認し、`status = success` が継続していることを確認する。
4. Stripe DashboardでWebhook送信履歴を確認し、アプリ側の `webhook_events.event_id` と一致することを確認する。
5. 本番で自然発生した `invoice.payment_failed` / `customer.subscription.deleted` / `customer.subscription.updated` があれば、該当Billingの状態遷移だけを読み取り確認する。

### 本番確認SQL

```sql
SELECT
  billing_status::text AS billing_status,
  COUNT(*) AS count
FROM billings
GROUP BY billing_status::text
ORDER BY billing_status::text;
```

```sql
SELECT
  id,
  office_id,
  billing_status::text AS billing_status,
  stripe_customer_id,
  stripe_subscription_id,
  trial_end_date,
  next_billing_date,
  scheduled_cancel_at,
  updated_at
FROM billings
ORDER BY updated_at DESC
LIMIT 20;
```

```sql
SELECT
  event_id,
  event_type,
  status,
  billing_id,
  office_id,
  error_message,
  created_at
FROM webhook_events
ORDER BY created_at DESC
LIMIT 30;
```

### デプロイ後に異常があった場合

- `webhook_events.status = failed` またはHTTP 500が出ている場合、該当 `event_id` / `event_type` / `billing_id` を先に特定する。
- 画面表示だけの問題であればFrontendの表示条件を確認する。
- 課金状態が誤遷移している場合は、該当Webhook payloadとStripe Dashboard上のSubscription / Invoice状態を照合する。
- 本番DBを手動修正する場合は、対象Billingを1件に限定し、修正前後のSELECT結果を残してから行う。
