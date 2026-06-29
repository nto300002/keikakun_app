# Stripe 課金ステータス遷移・バッチ設計調査

作成日: 2026-06-17

## 調査対象

ローカル環境の `billings` テーブルで、選択中のレコードが以下の状態になっている。

```text
stripe_customer_id = cus_...
stripe_subscription_id = NULL
billing_status = free
trial_end_date = 未来日
```

この事業所はすでに支払い処理を終えている認識だが、期待される `early_payment` になっていない。

期待動作:

- トライアル期間中に支払い・サブスク登録が完了した場合、`billing_status` は `early_payment` になる。
- トライアル終了後、バッチで `early_payment -> active` になる。

## 結論

現在の実装では、Checkout Session 作成だけでは `billing_status` は `early_payment` にならない。

`early_payment` への変更は Stripe Webhook の以下いずれかで行われる。

- `customer.subscription.created`
- `invoice.payment_succeeded`

したがって、画像のように `stripe_customer_id` は入っているが `stripe_subscription_id = NULL` かつ `billing_status = free` の場合、最も可能性が高い原因は以下。

1. ローカル環境に Stripe Webhook が届いていない。
2. Webhook は届いたが、署名設定や endpoint 違いで処理されていない。
3. Webhook は届いたが、`customer` がローカルDBの `stripe_customer_id` と一致せず skipped になった。
4. `customer.subscription.created` が処理されていないため、`stripe_subscription_id` が保存されていない。

`stripe_customer_id` が入っているだけでは「支払い処理後のDB更新まで完了した」とは判断できない。

## 実装上の状態遷移

### Checkout Session 作成時

対象:

- `k_back/app/api/v1/endpoints/billing.py`
- `k_back/app/services/billing_service.py`

Checkout Session 作成時に行う主なDB更新:

- Customer 未作成ルート:
  - Stripe Customer を作成する。
  - `billings.stripe_customer_id` を保存する。
  - 期限切れ `free` の場合は `past_due` に補正する。
- 既存 Customer ありルート:
  - 既存 `stripe_customer_id` で Checkout Session を作る。
  - 期限切れ `free` の場合は `past_due` に補正する。

この時点では、基本的に `billing_status=free` のままでも正常。

理由:

- Checkout Session 作成は「支払い画面を作った」だけ。
- 実際にユーザーがCheckoutを完了したかは、Stripe Webhookで確定する設計。

### customer.subscription.created

対象:

- `BillingService.process_subscription_created()`

処理内容:

- `customer` から Billing を検索する。
- `stripe_subscription_id` を保存する。
- `trial_end_date > now` かつ `billing_status == free` の場合、`early_payment` にする。
- それ以外は `active` にする。

現在の判定:

```python
is_trial_active = (
    billing.billing_status == BillingStatus.free and
    billing.trial_end_date and
    billing.trial_end_date > now
)

new_status = BillingStatus.early_payment if is_trial_active else BillingStatus.active
```

### invoice.payment_succeeded

対象:

- `BillingService.process_payment_succeeded()`
- `crud.billing.record_payment()`

処理内容:

- `customer` から Billing を検索する。
- `last_payment_date` を保存する。
- `trial_end_date > now` なら `early_payment` にする。
- `trial_end_date <= now` なら `active` にする。

`record_payment()` は現在の `billing_status` に依存せず、`trial_end_date` を見て `early_payment` / `active` を決める。

### check_trial_expiration batch

対象:

- `app/tasks/billing_check.py`

処理内容:

- `billing_status=free` かつ `trial_end_date < now` を `past_due` にする。
- `billing_status=early_payment` かつ `trial_end_date < now` を `active` にする。

## 画像の状態が起きる具体的な理由

画像の状態:

```text
stripe_customer_id = cus_...
stripe_subscription_id = NULL
billing_status = free
trial_end_date = 未来日
```

この状態は、Checkout Session 作成後、Webhookによるサブスク確定処理がDBに反映されていない状態と一致する。

特にローカル環境では以下を確認する必要がある。

### 1. Stripe CLI webhook forwarding が起動しているか

ローカルでは通常、Stripeから直接 `localhost` へWebhookは届かない。

確認例:

```bash
stripe listen --forward-to localhost:8000/api/v1/billing/webhook
```

この forward 先が実際のバックエンドURL・ポートと一致している必要がある。

### 2. `STRIPE_WEBHOOK_SECRET` が `stripe listen` の `whsec_...` と一致しているか

`stripe listen` を起動すると、ローカル用の webhook signing secret が表示される。

ローカル backend の `STRIPE_WEBHOOK_SECRET` がその値と違う場合、署名検証で弾かれ、DB更新は行われない。

### 3. webhook_events に対象イベントが記録されているか

確認SQL:

```sql
SELECT event_id, event_type, status, billing_id, office_id, processed_at, error_message
FROM webhook_events
ORDER BY processed_at DESC
LIMIT 50;
```

見たいイベント:

- `customer.subscription.created`
- `invoice.payment_succeeded`

対象Customerで絞る場合:

```sql
SELECT event_id, event_type, status, billing_id, office_id, processed_at, payload
FROM webhook_events
WHERE payload::text LIKE '%cus_Uiao%'
ORDER BY processed_at DESC;
```

### 4. Stripe側のCustomerとローカルDBのCustomer IDが一致しているか

ローカルDBに `cus_...` が入っていても、実際に支払い完了したStripe Customerが別IDなら、Webhookは対象Billingを見つけられない。

この場合、現在の実装では missing customer として `skipped` 記録されることがある。

## 2026-06-18 ローカル再検証結果

2026-06-18 にローカル環境で再検証した結果、Stripe CLI listener を起動した状態では、Webhookが正常にlocal backendへ到達し、`billing_status=early_payment` へ遷移することを確認した。

確認できた `billings` の状態:

```text
stripe_customer_id = cus_Uiax...
stripe_subscription_id = sub_1Tj9m...
billing_status = early_payment
trial_end_date = 未来日
```

確認できた `webhook_events`:

```text
customer.subscription.created -> success
invoice.payment_succeeded     -> success
```

Stripe CLI ログでも、対象イベントが local backend に `200` で届いている。

抜粋:

```text
2026-06-17 12:04:49 --> customer.subscription.created [evt_1Tj9mXBxyBErCNcAqviNa7Zp]
2026-06-17 12:04:50 --> invoice.payment_succeeded [evt_1Tj9mXBxyBErCNcAO97jYCxe]
2026-06-17 12:04:53 <-- [200] POST http://localhost:8000/api/v1/billing/webhook [evt_1Tj9mXBxyBErCNcAqviNa7Zp]
2026-06-17 12:04:54 <-- [200] POST http://localhost:8000/api/v1/billing/webhook [evt_1Tj9mXBxyBErCNcAO97jYCxe]
```

この結果から、前回の `stripe_customer_id` はあるが `billing_status=free` のまま残っていた問題は、実装上の `early_payment` 遷移不具合ではなく、ローカル検証時に Stripe CLI listener を起動していなかったことが主因と判断する。

つまり、前回の状態は以下の途中状態だった。

```text
Checkout Session 作成
-> Stripe Customer 作成
-> billings.stripe_customer_id 保存
-> しかし Stripe Webhook が local backend に届かない
-> customer.subscription.created / invoice.payment_succeeded がDBに反映されない
-> billing_status は free のまま
```

ローカルでWebhook込みの課金検証を行う場合は、以下が必須。

```bash
stripe listen --forward-to localhost:8000/api/v1/billing/webhook
```

さらに、`stripe listen` が表示する `whsec_...` を local backend の `STRIPE_WEBHOOK_SECRET` に設定し、backendコンテナを再作成する必要がある。

今回の再検証により、以下は確認済み。

- ローカルでもWebhookが届けば `early_payment` へ正常遷移する。
- `customer.subscription.created` で `stripe_subscription_id` が保存される。
- `invoice.payment_succeeded` で支払い成功処理が記録される。
- `webhook_events` に対象イベントが `success` で保存される。

一方で、Stripeイベントの到達順は環境やタイミングに依存するため、イベント順序に強い実装へ改善する価値は残る。

## 設計上の懸念

## 2026-06-18 確定方針: `past_due` の責務分離

`past_due` は存在そのものは残す。

ただし、新規の状態遷移では `past_due` に複数の意味を持たせ続けず、既存データ互換と移行元として扱う。

既存の `past_due` データは、状態を確認したうえで `trial_expired` または `payment_failed` へ移行する。

### 確定status定義

```text
trial_expired
  trial終了後、未課金、Stripe Subscription なし。
  主な導線はサブスクリプション登録。

payment_failed
  trial期間外で、Stripe Subscription / Invoice は存在するが、支払い失敗または支払いアクションが必要。
  主な導線は支払い方法更新、再決済、Customer Portal。

past_due
  既存データ互換用として残す。
  新規の業務的意味付けには使わない。
```

### 書き込み制限方針

制限対象:

```text
trial_expired
payment_failed
past_due
canceled
```

許可対象:

```text
free
early_payment
active
canceling
```

`past_due` は互換用として制限対象に残す。

### Frontend 表示方針

`trial_expired` と `payment_failed` には、それぞれ専用のモーダルを設定する。

- `trial_expired`
  - 表示意味: 無料期間終了。
  - ユーザーに促す操作: サブスクリプション登録。
- `payment_failed`
  - 表示意味: 支払い失敗。
  - 表示条件: trial期間外の場合に表示する。
  - ユーザーに促す操作: 支払い方法更新、再決済、Customer Portal。
- `past_due`
  - 互換表示として残す。
  - 新規の意味付けには使わない。

### Migration 方針

`past_due` は削除しない。

既存データは以下の方針で移行する。

- `stripe_subscription_id IS NULL` かつ trial終了後の `past_due`
  - `trial_expired` 候補。
- `stripe_subscription_id IS NOT NULL` かつ trial期間外の `past_due`
  - `payment_failed` 候補。
- `past_due + trial中`
  - 一括移行しない。
  - 不整合として個別確認または診断対象にする。

DB定義変更が発生する場合は、Alembic migration と同内容の手動実行用SQLを作成する。

### 懸念 0: Frontend の制限ロジックが `past_due` 前提になっている

Frontend では、課金状態による制限・警告表示が `billing_status=past_due` を中心に実装されている。

主な該当箇所:

- `k_front/contexts/BillingContext.tsx`
  - `canWrite` は `past_due` / `canceled` の場合のみ `false`。
  - `isPastDue` は `billing_status === past_due` の場合のみ `true`。
- `k_front/components/billing/BillingProtectedButton.tsx`
  - `canWrite` に基づきボタンを無効化している。
  - 無効化メッセージは `isPastDue` かどうかで分岐している。
- `k_front/components/billing/PastDueModalWrapper.tsx`
  - `isPastDue` の場合のみ支払い遅延モーダルを表示している。
- `k_front/components/protected/admin/PlanTab.tsx`
  - status badge、支払い遅延警告、サブスク登録ボタン、支払い方法変更ボタンの条件に `past_due` が直接使われている。
- `k_front/components/protected/dashboard/Dashboard.tsx`
  - `canEdit` は `free` / `active` / `early_payment` のみ許可している。
  - 警告表示は `past_due` の場合のみ行っている。
- `k_front/components/billing/TrialExpiryBanner.tsx`
  - `free` のみ無料トライアル中として表示し、期限切れ後は表示しない。

このため、backendで `trial_expired` / `payment_failed` を追加する場合、frontend を修正しないと以下の不整合が起きる。

- backendでは制限対象なのに、frontendの `canWrite` では制限されない。
- `trial_expired` や `payment_failed` の警告モーダル・警告バナーが表示されない。
- 管理画面で次に取るべき導線が `past_due` のまま流用され、無料期間終了と支払い失敗の区別がつかない。

したがって、status分離の実装範囲には frontend の表示・制限ロジックも含める。

frontend側の設計方針:

- `past_due` 専用の `isPastDue` だけで制限を表現しない。
- `requiresPaymentAction` のような、backendの制限対象と対応する概念を追加する。
- `trial_expired` は「無料期間終了・プラン登録が必要」として表示する。
- `payment_failed` は「支払い失敗・支払い方法更新または再決済が必要」として表示する。
- `past_due` は既存データ互換のため制限対象として残すが、新規の意味付けには使わない。

### 懸念 1: Webhook依存が強いが、Checkout完了との突合せ手段が弱い

現在の設計では、Checkout完了後の状態更新はWebhookに依存している。

Webhookが届かない、署名が違う、ローカルDBとStripe Customerがずれる、などが起きると以下のような中途半端な状態が残る。

```text
stripe_customer_id = cus_...
stripe_subscription_id = NULL
billing_status = free
```

影響:

- 支払い済みの認識なのにアプリ上は無料扱いのままになる。
- `early_payment -> active` のバッチ対象にもならない。
- `stripe_subscription_id` がないため、Customer Portal やキャンセル処理でも不整合が出やすい。

改善案:

- Checkout Session ID をDBに保存し、成功URL到達後または管理画面表示時にStripeへ照会できるようにする。
- `stripe_customer_id` だけではなく `stripe_subscription_id` の有無を課金設定完了判定に使う。
- `stripe_customer_id IS NOT NULL AND stripe_subscription_id IS NULL AND billing_status=free` を異常検知対象にする。

### 懸念 2: Webhookイベント順序に弱い箇所がある

`process_subscription_created()` は `billing_status == free` の場合だけ、trial中を `early_payment` と判定する。

このため、仮に以下の順序でイベントが処理されると、意図しない状態になる可能性がある。

1. `invoice.payment_succeeded` が先に処理される。
2. `record_payment()` により trial中なので `early_payment` になる。
3. その後 `customer.subscription.created` が処理される。
4. `billing_status == free` ではないため `is_trial_active=False` になる。
5. `active` に更新される。

つまり、trial期間中でもイベント順序によって `active` になる可能性がある。

改善案:

- `process_subscription_created()` の判定を `billing_status == free` に依存させず、`trial_end_date > now` と subscription の存在で判断する。
- ただし `past_due` や `canceled` からの復帰仕様も絡むため、テストを追加して慎重に変更する。

### 懸念 2-補足: trial判定と `past_due` の条件

今後の方向性として、厳密に以下の定義へ寄せる。

```text
trial中 = trial_end_date > now
trial終了後 = trial_end_date <= now

free = trial中、未課金
early_payment = trial中、課金設定済み
active = trial終了後、課金済み
past_due = trial終了後、支払いが必要
```

この定義では、`past_due` は trial終了後だけに発生する状態とする。

したがって、以下は不整合状態として扱う。

```text
billing_status = past_due
trial_end_date > now
```

現行実装では、この不整合は発生し得る。

- DB制約がなく、`billing_status` と `trial_end_date` を自由に組み合わせられる。
- `process_payment_failed()` は trial中かどうかを見ずに `past_due` にする。
- テストに `past_due` かつ `trial_end_date > now` を許容するケースがある。

この方向性を採用する場合、状態遷移は `billing_status` よりも `trial_end_date` を正として判定する。

特に `process_subscription_created()` は、Webhook順序に強くするため、trial判定から `billing_status == free` を外す。

```python
is_trial_active = (
    billing.trial_end_date and
    billing.trial_end_date > now
)
```

これにより、`invoice.payment_succeeded` が先に来て `early_payment` になったあと、`customer.subscription.created` が後から来ても、trial中なら `early_payment` が維持される。

ただし、`past_due` を trial終了後だけに限定するなら、以下もあわせて見直す必要がある。

- `process_payment_failed()` は trial中の失敗を `past_due` にしない。
- `past_due + trial中` の既存テストは削除または仕様変更する。
- `past_due + trial中` の既存データを検知して補正する。
- `requires_payment_action()` は `past_due` のみを見る現状でよいか、trial判定も含めるか確認する。

### 懸念 3: skipped webhook が永続的に処理済み扱いになる

Webhook受信時、最初に `event_id` が存在するかを確認し、存在すれば処理をスキップする。

missing customer の場合、処理は `skipped` として記録される。

この場合、あとからDBにCustomer IDが保存されても、同じ `event_id` は処理済み扱いになり再処理されない。

影響:

- 一時的なDB反映遅延や環境違いで skipped になったイベントを復旧しづらい。
- ローカル検証では特に起きやすい。

改善案:

- `status=skipped` を完全な処理済みとみなすか再検討する。
- `skipped` イベントの再処理用コマンドまたは管理タスクを用意する。
- `is_event_processed()` は `success` のみを処理済みとみなすか、イベントタイプごとに扱いを分ける。

### 懸念 4: billing scheduler がジョブ登録wrapperを呼んでいない可能性

`app/scheduler/billing_scheduler.py` にはジョブ登録を行う `start()` wrapper がある。

しかし `app/main.py` では以下のように `billing_scheduler` インスタンスを import している。

```python
from app.scheduler.billing_scheduler import billing_scheduler
```

startup では以下を呼んでいる。

```python
billing_scheduler.start()
```

これは `billing_scheduler.py` の独自 `start()` wrapper ではなく、`AsyncIOScheduler.start()` を直接呼ぶ形になる。

そのため、以下のジョブが登録されない可能性がある。

- `check_trial_expiration`
- `check_scheduled_cancellation`

影響:

- `free -> past_due` が定期実行されない。
- `early_payment -> active` が定期実行されない。
- `canceling -> canceled` が定期実行されない。

改善案:

- `main.py` では module wrapper の `start()` / `shutdown()` を呼ぶ。
- 起動時に登録済みジョブ数とjob idをログに出す。
- scheduler 起動テストを追加する。

### 懸念 5: ローカル環境とStripe環境の対応が見えにくい

ローカルDB、Stripe test mode、Stripe CLI forwarding、`.env` の webhook secret がずれると、支払い処理を完了してもDB状態は更新されない。

改善案:

- ローカル課金検証手順を固定する。
- `STRIPE_SECRET_KEY`、`STRIPE_PRICE_ID`、`STRIPE_WEBHOOK_SECRET`、Stripe CLI の接続先をチェックリスト化する。
- webhook_events を確認するSQLを検証手順に含める。

## 直近で確認すべきSQL

対象Billing:

```sql
SELECT id, office_id, stripe_customer_id, stripe_subscription_id,
       billing_status, trial_start_date, trial_end_date,
       last_payment_date, subscription_start_date, next_billing_date
FROM billings
WHERE id = '<対象 billing id>';
```

対象CustomerのWebhook:

```sql
SELECT event_id, event_type, status, billing_id, office_id,
       processed_at, error_message
FROM webhook_events
WHERE payload::text LIKE '%<対象 cus_...>%'
ORDER BY processed_at DESC;
```

異常候補:

```sql
SELECT id, office_id, stripe_customer_id, stripe_subscription_id,
       billing_status, trial_end_date
FROM billings
WHERE stripe_customer_id IS NOT NULL
  AND stripe_subscription_id IS NULL
  AND billing_status = 'free';
```

期限切れバッチ未反映:

```sql
SELECT id, office_id, billing_status, trial_end_date
FROM billings
WHERE billing_status IN ('free', 'early_payment')
  AND trial_end_date < NOW();
```

`past_due` だが trial中の不整合:

```sql
SELECT id, office_id, stripe_customer_id, stripe_subscription_id,
       billing_status, trial_end_date
FROM billings
WHERE billing_status = 'past_due'
  AND trial_end_date > NOW();
```

## 推奨対応順

### Phase 1: ローカル原因切り分け

- Stripe CLI forwarding が起動しているか確認する。
- `STRIPE_WEBHOOK_SECRET` が `stripe listen` の値と一致しているか確認する。
- `webhook_events` に `customer.subscription.created` があるか確認する。
- `webhook_events` に `invoice.payment_succeeded` があるか確認する。
- 対象 `cus_...` が支払い完了したCustomerと一致しているか確認する。

### Phase 2: 調査性改善

- Webhook処理ログに `event_id`、`event_type`、`billing_id`、`office_id`、`status transition` を出す。
- skipped webhook の理由を `webhook_events.error_message` に残す。
- `stripe_customer_id IS NOT NULL AND stripe_subscription_id IS NULL AND billing_status=free` の検知ログまたは管理用SQLを用意する。

### Phase 3: ステータス遷移の堅牢化

- `process_subscription_created()` の `early_payment` 判定をイベント順序に強い形へ修正する。
- `invoice.payment_succeeded` と `customer.subscription.created` の順序が入れ替わっても、trial中なら最終的に `early_payment` になるテストを追加する。
- `past_due` は trial終了後だけ、という定義を状態遷移ルールとして明文化する。
- `process_payment_failed()` で trial中に `past_due` へ落とさない仕様にするか検討する。
- `past_due + trial中` の既存テストと既存データを見直す。
- `skipped` webhook の再処理方針を決める。

### Phase 4: scheduler 起動修正

- `main.py` から billing scheduler wrapper の `start()` を呼ぶ。
- `check_trial_expiration` と `check_scheduled_cancellation` が登録されるテストを追加する。
- 起動ログに登録済み job id を出す。
- shutdown が未起動状態でも安全に動くようにする。

## TDDで追加したいテスト

- `customer.subscription.created` 単体で、trial中なら `free -> early_payment` になる。
- `invoice.payment_succeeded` 単体で、trial中なら `free -> early_payment` になる。
- `invoice.payment_succeeded` の後に `customer.subscription.created` が来ても、trial中なら `early_payment` のまま維持される。
- `customer.subscription.created` の後に `invoice.payment_succeeded` が来ても、trial中なら `early_payment` のまま維持される。
- `invoice.payment_failed` が trial中に来た場合、`past_due` へ遷移しないことを確認する。
- `trial_end_date > now` かつ `billing_status=past_due` を不整合として検知できることを確認する。
- `trial_end_date <= now` の未課金状態だけが `past_due` になることを確認する。
- missing customer で skipped になったWebhookをどう扱うかの仕様テスト。
- billing scheduler startup で `check_trial_expiration` と `check_scheduled_cancellation` が登録される。

## `past_due` を trial終了後だけに限定する場合の注意点

### 1. 既存データの補正が必要

すでに `past_due + trial_end_date > now` のデータが存在する可能性がある。

まずは検知SQLで件数を確認し、補正方針を決める。

補正候補:

- `stripe_subscription_id IS NOT NULL` なら `early_payment`
- `stripe_subscription_id IS NULL` なら `free`

ただし、Stripe側で支払い失敗や未払いがある場合、単純に `free` へ戻すと課金制限が外れる。補正前に Stripe Subscription / Invoice の状態確認が必要。

### 2. `process_payment_failed()` の意味が変わる

現行実装では `invoice.payment_failed` は常に `past_due` にする。

`past_due` を trial終了後だけに限定するなら、trial中の `invoice.payment_failed` をどう扱うか決める必要がある。

候補:

- trial中は `free` または `early_payment` を維持し、失敗ログだけ残す。
- subscription が存在する trial中なら `early_payment` を維持し、支払い方法更新の警告だけ出す。
- trial終了後の支払い失敗だけ `past_due` にする。

### 3. `record_payment()` の既存テストを見直す

現行テストには `past_due` かつ trial中から `record_payment()` で `early_payment` に戻るケースがある。

このテストは、今後の定義では「不整合状態からの復旧テスト」として扱うか、削除するかを決める。

保守的には、まず不整合復旧テストとして残し、テスト名とコメントを変更する。

### 4. フロントエンド表示と権限制御への影響

`past_due` は書き込み制限や支払い遅延表示に使われている。

trial中に `past_due` を使わない設計へ変えると、trial中の支払い失敗は即時の書き込み制限にはならない。

これはユーザー体験としては自然だが、支払い方法更新の警告表示が別途必要になる可能性がある。

### 5. DB制約をすぐ入れるのは避ける

最終的には `past_due` と `trial_end_date` の整合性をDB制約で守る選択肢もある。

ただし、既存データやイベント順序の影響を受けるため、すぐにDB制約を入れるのは危険。

まずはアプリ層の状態遷移 helper とテストで守る。

### 6. `active` と `early_payment` の境界を明確にする

`active` は trial終了後の課金済み、`early_payment` は trial中の課金設定済み、と定義する。

この定義に寄せるなら、`customer.subscription.created` が trial中に `active` を設定する経路は避ける。

Webhook順序が変わっても、最終状態は以下になるべき。

```text
trial_end_date > now  + subscription/payment success = early_payment
trial_end_date <= now + subscription/payment success = active
trial_end_date <= now + unpaid/no subscription = past_due
```

## 将来的な変更要件: `invoice.payment_failed` と `past_due + trial中` の整理

`past_due` を trial終了後だけの状態として厳密化する場合、以下を変更要件として扱う。

### 要件 1: trial中の `invoice.payment_failed` では `past_due` にしない

現行実装では `invoice.payment_failed` を受けると、trial中かどうかに関係なく `billing_status=past_due` に更新する。

変更後は、`trial_end_date > now` の間は `past_due` に遷移させない。

期待する遷移:

```text
trial_end_date > now  + invoice.payment_failed + subscriptionなし = free を維持
trial_end_date > now  + invoice.payment_failed + subscriptionあり = early_payment を維持
trial_end_date <= now + invoice.payment_failed = past_due
```

補足:

- trial中の支払い失敗は「ただちに利用制限」ではなく「支払い方法の確認が必要な警告」として扱う。
- trial終了後に未払いが残っている場合だけ `past_due` にする。
- 支払い失敗の事実は `webhook_events`、`audit_logs`、必要なら専用フィールドに残す。

### 要件 2: `past_due + trial_end_date > now` を不整合状態として検知する

以下の状態は、今後の定義では正規状態ではない。

```text
billing_status = past_due
trial_end_date > now
```

変更後は、定期チェック、管理用SQL、または診断ログでこの状態を検知できるようにする。

検知SQL:

```sql
SELECT id, office_id, stripe_customer_id, stripe_subscription_id,
       billing_status, trial_end_date
FROM billings
WHERE billing_status = 'past_due'
  AND trial_end_date > NOW();
```

補正方針:

```text
stripe_subscription_id IS NOT NULL -> early_payment 候補
stripe_subscription_id IS NULL     -> free 候補
```

ただし、Stripe側の Subscription / Invoice 状態を確認せずに一括補正しない。

### 要件 3: 既存テストの意味を変更する

現行テストには、`past_due` かつ trial中から `record_payment()` で `early_payment` に戻るケースがある。

今後はこのケースを通常遷移ではなく、不整合状態からの復旧テストとして扱う。

対応方針:

- テスト名を「past_due during trial の通常動作」ではなく「不整合状態の復旧」に変更する。
- もしくは、`past_due + trial中` を作らない設計にしたあと削除する。
- 代わりに `invoice.payment_failed` が trial中に来ても `past_due` へ落ちないテストを追加する。

### 要件 4: フロントエンドの警告表示を分離する

`past_due` を trial終了後だけに限定すると、trial中の支払い失敗は `past_due` では表現しない。

そのため、trial中の支払い失敗をユーザーに知らせる必要がある場合、`billing_status=past_due` とは別の表示条件を用意する。

候補:

- `last_payment_failed_at`
- `payment_method_warning`
- `latest_invoice_status`
- `stripe_subscription_status`

ただし、これらは今回のステータス遷移修正とは別タスクで検討する。

### 要件 5: DB制約は最後に検討する

最終的に `past_due + trial中` をDBレベルで防ぐ選択肢はある。

ただし、既存データ、Webhook順序、手動復旧、テストデータ作成に影響するため、すぐにDB制約を入れない。

導入する場合は、以下の順に進める。

1. アプリ層の状態遷移を修正する。
2. 既存データを調査する。
3. 不整合データを補正する。
4. テストデータ生成を修正する。
5. 最後にDB制約を検討する。

## 状態を増やして責務を分離する設計方針

`past_due` に複数の意味を持たせ続けると、今後も `past_due かつ trial中か`、`subscription があるか`、`invoice が失敗したのか` といった条件分岐が増える。

課金処理は Stripe Webhook、Checkout、バッチ、フロント表示、権限制御が絡むため、実装コストよりも状態の意味が読みやすいことを優先する。

そのため、将来的には status を増やして以下のように責務を分離する方向を採用する。

```text
free
  trial中、未課金

early_payment
  trial中、課金設定済み

active
  trial終了後、課金中

trial_expired
  trial終了後、未課金
  旧 past_due のうち、stripe_subscription_id がない期限切れ状態

payment_failed
  支払い失敗、または請求失敗
  旧 past_due のうち、Stripe invoice/payment failure に由来する状態

canceling
  キャンセル予定、期間終了までは利用可能

canceled
  キャンセル済み、利用制限対象
```

`past_due` は以下のどちらかに整理する。

候補:

- 互換性維持のため一時的に残し、段階的に `trial_expired` / `payment_failed` へ移行する。
- Stripe の subscription status としてだけ扱い、アプリの主要 `billing_status` からは廃止する。

短期的には、既存コードとデータ移行のリスクを下げるため、`past_due` は互換用として残しつつ、新規遷移では `trial_expired` / `payment_failed` を使う方針が安全。

## 実装すべき優先度順

### 優先度 1: 状態定義と遷移表を固定する

目的:

- 実装前に、status の意味と遷移先を明文化する。
- `past_due` の曖昧な責務をこれ以上広げない。

実施内容:

- `trial_expired` と `payment_failed` を追加する方針を確定する。
- `past_due` を互換用に残すか、段階的廃止するか決める。
- `free / early_payment / active / trial_expired / payment_failed / canceling / canceled` の意味をREADMEまたは設計メモに固定する。
- 書き込み制限対象を明確にする。

想定する制限対象:

```text
trial_expired
payment_failed
canceled
```

`canceling` は期間終了まで利用可能、`free` は trial中なら利用可能とする。

完了条件:

- 状態一覧と遷移表がドキュメント化されている。
- `past_due` の扱いが互換用か廃止対象か決まっている。

### 優先度 2: Red テストで新しい状態遷移を固定する

目的:

- 実装前に、期待するステータス遷移をテストで固定する。

追加テスト:

- `check_trial_expiration()` で `free + trial_end_date <= now -> trial_expired` になる。
- `check_trial_expiration()` で `early_payment + trial_end_date <= now -> active` になる。
- `invoice.payment_failed + trial_end_date > now` では `payment_failed` または既存状態維持のどちらにするかを仕様化する。
- `invoice.payment_failed + trial_end_date <= now -> payment_failed` になる。
- `customer.subscription.created + trial_end_date > now -> early_payment` になる。
- `customer.subscription.created + trial_end_date <= now -> active` になる。
- `invoice.payment_succeeded` と `customer.subscription.created` の順序が入れ替わっても、trial中なら最終状態は `early_payment` になる。
- `past_due + trial_end_date > now` は不整合として検知される。

注意:

- `payment_failed` を trial中にも使うかどうかは設計判断が必要。
- trial中の支払い失敗で機能制限しない方針なら、status は `free` / `early_payment` を維持し、別フィールドまたはログで警告を表す。

完了条件:

- 現行実装では失敗するRedテストが追加されている。
- 期待状態がテスト名から読める。

### 優先度 3: Backend enum / schema / CRUD の状態追加

目的:

- 新しい状態をバックエンドで扱えるようにする。

実施内容:

- `BillingStatus` enum に `trial_expired` と `payment_failed` を追加する。
- Pydantic schema が新statusを受け取れることを確認する。
- `get_status_display_message()`、`get_next_action_message()`、`requires_payment_action()`、`can_access_paid_features()` を更新する。
- `require_active_billing()` の制限対象を更新する。

想定:

```text
can_access_paid_features:
  active, early_payment, canceling は True
  free は trial中の扱いに注意
  trial_expired, payment_failed, canceled は False

requires_payment_action:
  trial_expired, payment_failed は True
```

完了条件:

- 新statusを含むユニットテストが通る。
- 権限制御の期待結果が明確になっている。

### 優先度 4: Webhook とバッチの遷移先を変更する

目的:

- 実際の課金イベントで新statusへ遷移するようにする。

変更内容:

- `check_trial_expiration()`:
  - `free -> trial_expired`
  - `early_payment -> active`
- `process_payment_failed()`:
  - trial終了後の失敗は `payment_failed`
  - trial中の失敗は、仕様に応じて既存状態維持または `payment_failed`
- `process_subscription_created()`:
  - `trial_end_date > now -> early_payment`
  - `trial_end_date <= now -> active`
  - `billing_status == free` 条件には依存しない
- `record_payment()`:
  - `trial_end_date > now -> early_payment`
  - `trial_end_date <= now -> active`
  - `past_due + trial中` は通常遷移ではなく不整合復旧として扱う

完了条件:

- Stripeイベント順序が入れ替わっても最終状態が安定する。
- `past_due` の新規発生が減り、`trial_expired` / `payment_failed` へ分離される。

### 優先度 5: Frontend 表示と制限ロジックを更新する

目的:

- ユーザーに「無料期間終了」と「支払い失敗」を別の意味として表示する。

変更内容:

- `trial_expired`: 無料期間終了、サブスク登録を促す。
- `payment_failed`: 支払い失敗、支払い方法更新を促す。
- `past_due`: 互換表示、または段階的廃止対象として扱う。
- `canWrite` / `isPastDue` のような名前を見直す。

注意:

- フロントでは `isPastDue` のような単一フラグに複数意味を持たせない。
- 例えば `requiresPaymentAction`、`isTrialExpired`、`isPaymentFailed` などに分ける。

完了条件:

- 画面上で `trial_expired` と `payment_failed` の文言が分かれる。
- 書き込み制限対象がbackendと一致する。

### 優先度 6: 既存データ移行と互換対応

目的:

- 既存の `past_due` データを新しい意味へ移行する。

移行候補:

```sql
-- trial期限切れ・未課金候補
UPDATE billings
SET billing_status = 'trial_expired'
WHERE billing_status = 'past_due'
  AND stripe_subscription_id IS NULL;

-- 支払い失敗・購読あり候補
UPDATE billings
SET billing_status = 'payment_failed'
WHERE billing_status = 'past_due'
  AND stripe_subscription_id IS NOT NULL;
```

注意:

- 上記SQLは仮案。実行前に Stripe 側の Subscription / Invoice 状態を確認する。
- `past_due + trial中` のデータは一括変換せず、個別確認する。
- rollback可能なmigrationにする。

完了条件:

- 移行前後の件数が記録されている。
- 不整合データの扱いが明確になっている。

### 優先度 7: DB制約・診断ジョブを検討する

目的:

- アプリ層で状態遷移が安定したあと、不整合を再発しにくくする。

候補:

- `trial_expired` は `trial_end_date <= now` 相当でのみ発生させる。
- `past_due + trial中` を検知する診断ジョブを用意する。
- DB制約は最後に検討する。

注意:

- `now()` を使うDB CHECK制約は扱いが難しいため、まずはアプリ層と診断SQLで守る。
- Webhook遅延やイベント順序を考慮し、即時に硬い制約を入れない。

## 推奨する最初の実装単位

最初のPRでは、まだDB migrationまで進めない。

推奨スコープ:

1. 状態遷移表をテストに落とす。
2. `process_subscription_created()` の `billing_status == free` 依存を外す。
3. Webhook順序が入れ替わっても trial中は `early_payment` になるようにする。

このPRでは `trial_expired` / `payment_failed` の追加は設計メモとRedテスト候補に留めてもよい。

理由:

- まず現行の明確なバグであるイベント順序問題を小さく直せる。
- status追加は backend/frontend/migration まで広がるため、別PRに分けた方が安全。

## 保守的な判断

現時点で画像のレコードをすぐ `early_payment` に手動更新する前に、まず webhook_events と Stripe 側Customer/Subscriptionを確認する。

`stripe_subscription_id = NULL` のまま `billing_status` だけ `early_payment` にすると、見かけ上は課金設定済みになるが、Portal、キャンセル、Webhook後続処理で別の不整合が出る可能性がある。

手動復旧する場合は、少なくとも以下をセットで確認・更新する。

- `stripe_customer_id`
- `stripe_subscription_id`
- `billing_status`
- `subscription_start_date`
- `last_payment_date`
- 対応する `webhook_events`

## まとめ

画像の `billing_status=free` は、支払い完了後のWebhook処理がローカルDBに反映されていない状態として説明できる。

実装上は `early_payment` への遷移ロジック自体は存在するが、Webhook到達、Customer ID一致、イベント順序、skippedイベント、scheduler起動に設計上の弱点がある。

特に優先して見るべき問題は以下。

1. ローカルWebhookが正しく届いているか。
2. `webhook_events` に成功または skipped の記録があるか。
3. `customer.subscription.created` が処理されて `stripe_subscription_id` が保存されているか。
4. `process_subscription_created()` がイベント順序に弱い点。
5. billing scheduler の wrapper が `main.py` から呼ばれていない点。
