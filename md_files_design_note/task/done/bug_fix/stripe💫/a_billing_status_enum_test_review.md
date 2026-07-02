# Billing Status enum追加後 テスト修正レビュー

作成日: 2026-06-18

## レビュー対象

enum追加後に修正された `billing_status` 関連テストを確認した。

主な対象:

- `k_back/tests/tasks/test_billing_check.py`
- `k_back/tests/services/test_billing_service.py`
- `k_back/tests/services/test_billing_status_helpers.py`
- 関連実装:
  - `k_back/app/models/enums.py`
  - `k_back/app/tasks/billing_check.py`
  - `k_back/app/services/billing_service.py`
  - `k_back/app/crud/crud_billing.py`
  - `k_back/app/api/deps.py`

照合資料:

- `.codex/skills/SKILLS.md`
- `md_files_design_note/task/bug_fix/stripe/billing_status_refactor_task_list.md`

## 実行確認

`.codex/skills/SKILLS.md` の backend Docker 実行ルールに従い、Docker backend コンテナ内で実行した。

実行コマンド:

```bash
docker exec keikakun_app-backend-1 pytest \
  tests/services/test_billing_status_helpers.py \
  tests/tasks/test_billing_check.py \
  tests/services/test_billing_service.py::TestBillingServiceTransactionIntegrity \
  -q
```

結果:

```text
36 passed, 1 failed, 16 warnings
```

補足:

- テスト開始時の safe cleanup で `office_staffs_office_id_fkey` の外部キー警告が出た。
- テスト本体は継続した。
- 失敗は `billing_status` 新statusの期待値不一致ではなく、固定Stripe Customer IDのunique制約衝突。

## 指摘事項

### 1. 固定 `stripe_customer_id` によりテストがunique制約で失敗する

重要度: High

該当:

- `k_back/tests/services/test_billing_service.py`
  - `test_process_payment_succeeded_rollback_on_error`
  - `stripe_customer_id="cus_test_12345"`
  - `event_id="evt_test_12345"`

失敗内容:

```text
sqlalchemy.exc.IntegrityError:
duplicate key value violates unique constraint "uq_billings_stripe_customer_id"
DETAIL: Key (stripe_customer_id)=(cus_test_12345) already exists.
```

問題:

- `billings.stripe_customer_id` はunique制約がある。
- 固定値 `cus_test_12345` は、他テストや過去データと衝突しやすい。
- `.codex/skills/SKILLS.md` の Docker コンテナ実行ルールに従って実DB付きテストを回す場合、テストデータの残存や並列実行の影響を受ける。

推奨修正:

- `uuid4()` を使い、`stripe_customer_id` と `event_id` を一意化する。

例:

```python
unique_id = uuid4().hex
customer_id = f"cus_test_rollback_{unique_id}"
event_id = f"evt_test_rollback_{unique_id}"
```

評価:

- この修正はテストの安定性改善であり、仕様変更ではない。
- 先行のCheckout系テストではUUID付きIDに寄せているため、同じ方針に揃えるのが妥当。

### 2. Checkout期限切れ補正テストがまだ `past_due` を新規遷移先として期待している

重要度: Medium

該当:

- `k_back/tests/api/test_billing.py`
  - `test_create_checkout_session_expired_free_without_customer_recovers_to_past_due`
  - `test_create_checkout_session_expired_free_with_existing_customer_recovers_to_past_due`
- `k_back/tests/services/test_billing_service.py`
  - 期限切れ `free` の Checkout Session 作成系テスト
- `k_back/app/services/billing_service.py`
  - `correct_expired_free_billing_before_checkout()`

現状:

- `check_trial_expiration()` は `free -> trial_expired` に変更されている。
- `process_payment_failed()` は trial期間外で `payment_failed` に変更されている。
- 一方で Checkout 前の期限切れ `free` 補正は、まだ `past_due` を期待している。

タスクリストとの照合:

`billing_status_refactor_task_list.md` では以下が確定している。

- `past_due` は互換用として残す。
- 新規の状態遷移では `past_due` に複数の意味を持たせず、`trial_expired` / `payment_failed` へ分離する。
- `trial_expired`: trial終了後、未課金、Stripe Subscriptionなし。

判断:

- Checkout前の「期限切れfree + 未課金」は意味として `trial_expired` に近い。
- 既存のCheckout 500修正由来で `past_due` 補正が残っているのは理解できるが、新仕様に寄せるならテスト名・期待値・実装を `trial_expired` へ変更する必要がある。

推奨:

- 方針A: 今回のタスク5ではCheckout補正は既存互換として `past_due` のまま残し、別タスクで `trial_expired` 化する。
- 方針B: タスク5の完了条件に含めるなら、Checkout補正も `trial_expired` へ変更し、テスト名を `recovers_to_trial_expired` に変える。

現時点では、タスクリストの「新規遷移ではpast_dueを使わない」と完全一致させるなら方針Bが自然。

### 3. `check_trial_expiration()` の遷移ログが旧statusを正しく出していない

重要度: Low

観測ログ:

```text
Trial expired: ..., trial_expired → trial_expired
Trial expired: ..., active → active
```

問題:

- `crud.billing.update_status()` 後に `billing.billing_status.value` をログ出力しているため、旧statusではなく更新後statusが表示されている。
- テストはstatus結果だけを見ているため、この観測性の劣化を検出できない。

推奨:

- 更新前に `old_status = billing.billing_status` を保持し、ログでは `old_status.value -> new_status.value` を出す。
- 必要なら `caplog` で `free → trial_expired`、`early_payment → active` を確認する軽いテストを追加する。

### 4. `billing_status_refactor_task_list.md` のGreen結果と今回の再実行結果が一致していない

重要度: Medium

タスクリストには以下の記録がある。

```text
37 passed, 17 warnings
```

今回の再実行結果:

```text
36 passed, 1 failed, 16 warnings
```

差分理由:

- 今回は `test_process_payment_succeeded_rollback_on_error` が固定 `cus_test_12345` でunique制約に衝突した。
- テストデータ状態に依存する不安定性がある。

推奨:

- 固定ID修正後に同じコマンドを再実行する。
- 成功後、タスクリストの確認結果を最新化する。

### 5. Frontend側の新status対応は未完了のまま

重要度: Medium

タスクリストのタスク6に記載済み。

現状の懸念:

- backendの `require_active_billing()` は `trial_expired` / `payment_failed` を制限対象にしている。
- 一方で frontend の `BillingContext` は、少なくともタスクリスト上では `past_due` / `canceled` のみを `canWrite=false` にしている。

影響:

- backendでは402になるが、frontend上は操作可能に見える可能性がある。
- `trial_expired` / `payment_failed` 専用モーダル・表示導線が未実装なら、ユーザーに次アクションが伝わりにくい。

評価:

- 今回の「関連テスト修正」範囲では backend テスト中心として妥当。
- ただしタスク5完了後、タスク6を必ず続ける必要がある。

## 良い点

- `check_trial_expiration()` の `free -> trial_expired` テストが追加されている。
- `early_payment -> active` が維持されている。
- `invoice.payment_failed + trial終了後 -> payment_failed` がテストされている。
- `invoice.payment_failed + trial中` で `past_due/payment_failed` へ落とさないテストが追加されている。
- `customer.subscription.created` と `invoice.payment_succeeded` のイベント順序入れ替わりでも、trial中は `early_payment` が維持されることをテストしている。
- `trial_expired` / `payment_failed` の支払いアクション判定、表示文言、次アクション文言がテストされている。
- `.codex/skills/SKILLS.md` の通り、backendテストはDockerコンテナ内で確認できた。

## タスクリストとの照合

### タスク4: 新status追加のRedテスト

概ね満たしている。

確認できた項目:

- `check_trial_expiration()` で `free + trial_end_date <= now -> trial_expired`
- `check_trial_expiration()` で `early_payment + trial_end_date <= now -> active`
- `invoice.payment_failed + trial_end_date <= now -> payment_failed`
- `invoice.payment_failed + trial_end_date > now` は `past_due` にしない
- `customer.subscription.created + trial_end_date > now -> early_payment`
- `customer.subscription.created + trial_end_date <= now -> active`

不足または要確認:

- `trial_end_date > now + billing_status=past_due` を不整合として検知するテストは、今回確認した範囲では明確には見つからなかった。
- 既存 `past_due during trial` 系のテストは一部残っているため、「不整合復旧」としての位置づけにリネームまたはコメント整理が必要。

### タスク5: Backendに `trial_expired` / `payment_failed` を追加

実装・テストの方向性は概ね一致している。

満たしている項目:

- enum追加
- helper判定追加
- `check_trial_expiration()` の `free -> trial_expired`
- `process_payment_failed()` の `payment_failed` 対応
- `require_active_billing()` の制限対象追加

未完了または注意:

- 再実行結果が `1 failed` のため、現時点ではGreen完了とは言い切れない。
- Checkout前補正が `past_due` のままで、`past_due` を互換用に縮退する設計と一部ズレる。
- migration とSQLの内容差分レビューは、今回のテストレビューとは別に実施が必要。

### タスク6: Frontend表示と権限制御

未完了。

backend側の制限対象が増えたため、frontend側も以下を更新する必要がある。

- `canWrite`
- `isPastDue` の責務分離
- `trial_expired` / `payment_failed` の表示文言
- modal / banner / PlanTab の導線
- frontendテスト

## 結論

今回のテスト修正は、新statusの主要なbackend遷移をかなり押さえている。

ただし、現時点では以下2点により「完全なGreen」とは扱わない方がよい。

1. `test_process_payment_succeeded_rollback_on_error` が固定 `stripe_customer_id` でunique制約に衝突して失敗している。
2. Checkout前の期限切れ `free` 補正がまだ `past_due` 前提で、`past_due` を互換用に残す設計と一部ズレている。

完了判定:

- backend新status遷移テスト: 80〜85%程度は満たしている。
- タスク5 Green完了扱い: 固定ID衝突を直して再実行後に判断。
- タスク6 frontend対応: 別途必須。

## 次の推奨対応

1. `test_process_payment_succeeded_rollback_on_error` の `cus_test_12345` / `evt_test_12345` をUUID付きに変更する。
2. 同じDockerコマンドを再実行する。
3. Checkout前補正を `past_due` のまま互換扱いにするか、`trial_expired` に変更するかを決める。
4. `trial_end_date > now + billing_status=past_due` の不整合検知テストを追加する。
5. `check_trial_expiration()` の遷移ログを `old_status -> new_status` で出すように修正する。
6. frontendの `trial_expired` / `payment_failed` 対応へ進む。
==========

• 結論として、現行仕様が canceling になる理由は「Stripeの期間終了時キャンセル」をそのままDB statusへ写しているためです。た
  だし、試用期限切れで既に利用不可の事務所に対しては、この仕様の妥当性は低いです。あなたの言う「本来は canceled になる」
  が、業務仕様としては自然です。

  実装上の理由
  Customer Portal でキャンセルすると、Stripe側は多くの場合「即時キャンセル」ではなく「現在の請求期間終了時にキャンセル」を
  設定します。このとき customer.subscription.updated が飛び、payload に cancel_at_period_end=true または cancel_at が入りま
  す。

  現行backendはそれを受けると、状態に関係なく billing_status=canceling にします。

  該当箇所:

  - k_back/app/services/billing_service.py:731

  if cancel_at_period_end or cancel_at:
      await crud.billing.update_status(
          ...
          status=BillingStatus.canceling,
      )

  さらに cancel_at があれば scheduled_cancel_at に保存します。

  - k_back/app/services/billing_service.py:712

  その後、実際に customer.subscription.deleted が届くか、scheduled_cancel_at < now のバッチが動くと canceled になります。

  - k_back/app/services/billing_service.py:815
  - k_back/app/tasks/billing_check.py:107

  Stripe公式でも、cancel_at_period_end=true は「現在の請求期間終了時にキャンセル」であり、customer.subscription.updated と
  customer.subscription.deleted が別イベントとして扱われる設計です。つまり、Stripe連携としては canceling -> canceled は自然
  です。
  参考: Stripe docs の cancellation / cancel_at_period_end 説明 (docs.stripe.com
  (https://docs.stripe.com/billing/subscriptions/cancel))、Subscription object の cancel_at / cancel_at_period_end 属性
  (docs.stripe.com (https://docs.stripe.com/api/subscriptions/object))

  妥当性
  active または early_payment の事務所なら、canceling は妥当です。

  理由:

  - まだ利用可能な期間が残っている
  - キャンセル取り消しが可能
  - 期間終了まで書き込み許可を維持する設計に合う
  - 既存テストもこの前提です
    k_back/tests/services/test_billing_canceling.py:112

  一方で、試用期限が過ぎた事務所では妥当性が落ちます。

  理由:

  - trial_expired は「trial終了後、未課金、利用不可」の状態
  - すでに利用権がないので「1ヶ月後までキャンセル予定」という猶予を与える意味が薄い
  - frontend/backendでは trial_expired / payment_failed / past_due / canceled を制限対象として扱う方向に整理済み
  - canceling は利用可能扱いになりやすく、試用期限切れ状態を誤って復活させるリスクがある

  特に canceling は helper上「まだ利用可能なキャンセル予定」として扱われています。これは試用期限切れ事務所には合いません。

  なぜ1ヶ月先延ばしになるか
  おそらくStripeの月額Subscriptionの current_period_end が1ヶ月後で、Portalが「期間終了時キャンセル」を設定しているためで
  す。現行コードはその cancel_at を scheduled_cancel_at に保存します。アプリが意図的に1ヶ月延ばしているというより、Stripe側
  のSubscription期間終了日をそのまま受け入れている状態です。

  設計上の食い違い
  現在のキャンセル処理は、次の前提で作られています。

  active / early_payment
    -> canceling
    -> canceled

  しかし今回問題になっているのは、おそらく以下です。

  trial_expired / payment_failed / past_due
    -> キャンセル操作
    -> canceled が自然

  つまり、キャンセル処理が「利用可能なSubscriptionを期間終了で止める」ケースに寄りすぎていて、「すでに利用不可・期限切れの
  状態を終了させる」ケースを分けていないのが原因です。

  判断
  この仕様は、active / early_payment に対しては妥当です。
  ただし、試用期限切れ事務所に対しては妥当性は低く、canceled へ即時遷移させる仕様に分けるべきです。

  次に実装するなら、Redテストはこれです。

  trial_expired の billing に customer.subscription.updated(cancel_at_period_end=true) が来た場合、
  billing_status は canceling ではなく canceled になる

  あわせて payment_failed / past_due でも同じ扱いにするかは仕様判断が必要ですが、少なくとも trial_expired は即時 canceled
  が自然です。