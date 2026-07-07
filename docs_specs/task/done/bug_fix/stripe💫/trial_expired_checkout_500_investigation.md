# Trial 期限切れ事業所の Stripe Checkout 500 調査

作成日: 2026-06-16

## 現象

本番環境で新しくアカウントを作成した場合は、Stripe の課金画面まで正常に遷移できた。

一方で、`trial_end_date` が現在日時を過ぎている既存事業所では `POST /api/v1/billing/create-checkout-session` が 500 になる。

期待としては、`billings.trial_end_date < now` かつ `billing_status = free` の事業所は `past_due` へ更新されるはずだが、実際には `free` のまま残っている可能性がある。

## 結論

実装側で影響していそうな点が 2 つある。

1. `free → past_due` に更新するバッチジョブが、アプリ起動時に正しくジョブ登録されていない可能性が高い。
2. `billing_status = free` のまま `trial_end_date` が過去になっている事業所で Checkout Session を作ると、過去の `trial_end` を Stripe に渡して 500 になる可能性が高い。

Stripe 側の API キーや Price ID は、新規アカウントで Checkout 画面まで遷移できたため、今回の主原因である可能性は下がる。

## 実装調査

### 1. 期限切れステータス更新の設計

該当ファイル:

- `k_back/app/tasks/billing_check.py`
- `k_back/app/scheduler/billing_scheduler.py`

`check_trial_expiration()` は以下の条件で対象 billing を抽出する。

```python
Billing.billing_status.in_([BillingStatus.free, BillingStatus.early_payment])
Billing.trial_end_date < now
```

更新先:

- `free` → `past_due`
- `early_payment` → `active`

つまり、`trial_end_date` が過去になっただけでは DB は自動更新されない。`check_trial_expiration()` が実行されて初めて `past_due` になる。

### 2. スケジューラー起動処理に問題がある可能性

該当ファイル:

- `k_back/app/main.py`
- `k_back/app/scheduler/billing_scheduler.py`

`billing_scheduler.py` には、ジョブを登録してから scheduler を起動する `start()` 関数がある。

```python
def start():
    billing_scheduler.add_job(...)
    billing_scheduler.add_job(...)
    billing_scheduler.start()
```

しかし `main.py` では以下のように、モジュールの `start()` 関数ではなく `AsyncIOScheduler` インスタンス自体を import している。

```python
from app.scheduler.billing_scheduler import billing_scheduler
```

その後、startup で以下を実行している。

```python
billing_scheduler.start()
```

この呼び出しは `billing_scheduler.py` の `start()` 関数ではなく、`AsyncIOScheduler.start()` を直接呼んでいる。つまり、`check_trial_expiration` と `check_scheduled_cancellation` の `add_job(...)` が実行されていない可能性が高い。

影響:

- APScheduler 自体は起動しても、課金チェックジョブが登録されない。
- `free → past_due` が発生しない。
- `early_payment → active` も発生しない。
- `canceling → canceled` も発生しない。

### 3. Cloud Run 運用上の注意

仮に `start()` 関数を正しく呼んでも、Cloud Run が `minScale: 0` でスケールダウンする構成の場合、アプリ内蔵 APScheduler は指定時刻にインスタンスが起動していないと実行されない。

`k_back/DEPLOYMENT.md` には Cloud Scheduler で朝のウォームアップを行う記載があるが、課金バッチそのものを外部 Cloud Scheduler で叩く設計ではなさそう。

本番で確実に `free → past_due` を行うには、アプリ内 APScheduler だけに依存せず、Cloud Scheduler + 管理用エンドポイント、Cloud Run Jobs、または別のバッチ実行基盤で `check_trial_expiration()` を定期実行する設計が望ましい。

## Checkout 500 との関係

該当ファイル:

- `k_back/app/api/v1/endpoints/billing.py`
- `k_back/app/services/billing_service.py`

`create_checkout_session()` は `billing.stripe_customer_id` の有無で分岐する。

### 既存 Customer がある場合

`billing.py` 側では、`trial_end_date` が未来の場合だけ `trial_end` を Stripe に渡している。

```python
if billing.trial_end_date and billing.trial_end_date > now:
    subscription_data_params['trial_end'] = int(billing.trial_end_date.timestamp())
```

この分岐は過去の `trial_end` を渡さないため安全。

### Customer がない場合

`BillingService.create_checkout_session_with_customer()` では、常に `trial_end` を Stripe に渡している。

```python
subscription_data={
    'trial_end': int(trial_end_date.timestamp()),
    'metadata': ...
}
```

`trial_end_date` が過去の場合、Stripe Checkout Session 作成時に Stripe API がエラーを返す可能性が高い。

今回の現象は以下の条件で発生しやすい。

- 既存事業所
- `trial_end_date < now`
- `billing_status = free` のまま
- `stripe_customer_id` が未設定
- 課金登録ボタン押下時に Customer 作成ルートへ入る
- 過去の `trial_end` を指定して Checkout Session 作成
- Stripe API エラー → アプリは 500 `Checkout Sessionの作成に失敗しました`

## Stripe 設定側で影響しそうな部分

新規アカウントで Checkout 画面まで遷移できたため、以下は概ね正常と判断できる。

- `STRIPE_SECRET_KEY`
- `STRIPE_PRICE_ID`
- Checkout Sessions 権限
- Customers 権限
- Products / Prices の参照
- Automatic Tax が Checkout Session 作成を完全にはブロックしていないこと

ただし、期限切れ事業所で 500 が続く場合は Stripe Dashboard のイベントまたは本番ログで以下のエラー文を確認する。

- `trial_end`
- `must be in the future`
- `invalid timestamp`
- `No such customer`
- `No such price`
- `permission`

特に `trial_end` 系のエラーなら、Stripe 設定不備ではなくアプリ実装側の過去 `trial_end` 指定が原因。

## 確認すべき DB 状態

対象事業所の `billings` を確認する。

```sql
SELECT
  id,
  office_id,
  billing_status,
  trial_start_date,
  trial_end_date,
  stripe_customer_id,
  stripe_subscription_id,
  subscription_start_date,
  next_billing_date,
  updated_at
FROM billings
WHERE office_id = '<対象 office_id>';
```

問題が起きやすい状態:

```text
billing_status = 'free'
trial_end_date < now()
stripe_customer_id IS NULL
```

本来の期待状態:

```text
billing_status = 'past_due'
trial_end_date < now()
```

## 暫定復旧案

本番で対象事業所をすぐ救済するだけなら、対象 billing を `past_due` に更新する。

```sql
UPDATE billings
SET billing_status = 'past_due',
    updated_at = NOW()
WHERE office_id = '<対象 office_id>'
  AND billing_status = 'free'
  AND trial_end_date < NOW();
```

ただし、これだけでは根本原因は残る。次回以降もバッチが動かなければ同じ状態が発生する。

## 実装修正候補

### 修正候補 1: billing scheduler の起動修正

`main.py` で `AsyncIOScheduler` インスタンスの `start()` ではなく、`billing_scheduler.py` の `start()` 関数を呼ぶ。

例:

```python
from app.scheduler import billing_scheduler

# startup
billing_scheduler.start()

# shutdown
billing_scheduler.shutdown()
```

または関数を別名 import する。

```python
from app.scheduler.billing_scheduler import start as start_billing_scheduler
from app.scheduler.billing_scheduler import shutdown as shutdown_billing_scheduler
```

### 修正候補 2: Customer 作成ルートでも過去 trial_end を渡さない

`BillingService.create_checkout_session_with_customer()` でも既存 Customer ルートと同じように、`trial_end_date > now` の場合だけ `trial_end` を指定する。

現在:

```python
subscription_data={
    'trial_end': int(trial_end_date.timestamp()),
    'metadata': ...
}
```

修正方針:

```python
subscription_data_params = {
    'metadata': {...}
}

if trial_end_date and trial_end_date > datetime.now(timezone.utc):
    subscription_data_params['trial_end'] = int(trial_end_date.timestamp())
```

これにより、期限切れ trial の事業所でも Checkout Session 作成時に Stripe へ過去の `trial_end` を渡さなくなる。

### 修正候補 3: Checkout 作成前に期限切れ free を補正する

`create_checkout_session()` の冒頭で、取得した billing が以下に該当する場合に `past_due` へ更新する。

```text
billing_status = free
trial_end_date < now
```

この補正を入れると、バッチ実行漏れがあってもユーザー操作時に状態が正規化される。

ただし、状態遷移の責務が API に分散するため、バッチ修正と併用する場合は設計方針を明確にする。

## 推奨対応順

1. 本番 DB で対象事業所の `billing_status`、`trial_end_date`、`stripe_customer_id` を確認する。
2. 本番ログで Checkout 500 時の Stripe エラー本文を確認し、`trial_end` 系エラーか確認する。
3. 暫定復旧として対象 billing を `past_due` に更新する。
4. `main.py` の billing scheduler 起動方法を修正する。
5. `BillingService.create_checkout_session_with_customer()` で過去 `trial_end` を渡さないよう修正する。
6. Cloud Run の scale-to-zero 前提なら、アプリ内 APScheduler だけでなく Cloud Scheduler / Cloud Run Jobs で課金バッチを確実に実行する運用にする。

## テスト観点

- `billing_status=free`、`trial_end_date < now`、`stripe_customer_id IS NULL` の billing で Checkout Session 作成が 500 にならないこと。
- 同条件で Stripe に `trial_end` が渡されないこと。
- `billing_status=free`、`trial_end_date < now` の billing が `check_trial_expiration()` で `past_due` になること。
- `billing_status=early_payment`、`trial_end_date < now` の billing が `active` になること。
- アプリ startup 時に billing scheduler のジョブが登録されていること。
