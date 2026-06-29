# Stripe Checkout 500 Green フェーズ実装レビュー

作成日: 2026-06-17

## レビュー対象

- `k_back/app/services/billing_service.py`
- `k_back/tests/api/test_billing.py`
- `k_back/tests/services/test_billing_service.py`
- 参照元: `md_files_design_note/task/bug_fix/stripe/checkout_500_checklist.md`

## 実行した確認

Docker コンテナ内で追加テスト 3 件を実行した。

```bash
docker exec keikakun_app-backend-1 pytest \
  tests/api/test_billing.py::test_create_checkout_session_expired_free_without_customer_recovers_to_past_due \
  tests/services/test_billing_service.py::TestBillingServiceStripeIntegration::test_create_checkout_session_with_customer_excludes_expired_trial_end \
  tests/services/test_billing_service.py::TestBillingServiceStripeIntegration::test_create_checkout_session_with_customer_includes_future_trial_end \
  -m "not performance"
```

結果:

- 3 passed
- 15 warnings

## 実装の確認結果

### 確認できたこと

- `BillingService.create_checkout_session_with_customer()` の `trial_end_date` が `Optional[datetime]` に変更されている。
- `trial_end_date` が `None` の場合は `trial_end` を Stripe に渡さない。
- `trial_end_date` が過去の場合は `trial_end` を Stripe に渡さない。
- `trial_end_date` が未来の場合は従来どおり `trial_end` を Stripe に渡す。
- `billing_status=free` かつ期限切れ trial の場合、Customer 新規作成ルートでは `past_due` に補正される。
- Customer 新規作成、Billing の `stripe_customer_id` 更新、Checkout Session 作成、commit は Service 層内で完結している。
- API 層に新しい `commit()` / `flush()` は追加されておらず、現時点では `.codex/skills/SKILLS.md` の 4 層アーキテクチャ方針に大きく反していない。

### 残っている懸念

#### 1. 既存 Customer ルートでは期限切れ `free -> past_due` 補正が行われない

該当箇所:

- `k_back/app/api/v1/endpoints/billing.py`
- `if billing.stripe_customer_id:` の既存 Customer ルート

現行の既存 Customer ルートは、期限切れ `trial_end` を Stripe に渡さないため Checkout 500 の直接原因は避けられる。一方で、`billing_status=free` かつ `trial_end_date < now` の DB 状態を `past_due` に補正しない。

影響:

- `stripe_customer_id` が既に存在する期限切れ事業所では、Checkout に進めても DB が `free` のまま残る。
- チェックリストにある「Checkout 作成前に `billing_status=free` かつ `trial_end_date < now` を検知したら `past_due` に補正する」を全ルートで満たしていない。
- UI / 権限制御 / billing status 表示が `past_due` 前提の場合、不整合が継続する。

推奨:

- 期限切れ `free -> past_due` 補正を Customer 有無に依存しない共通処理にする。
- 可能なら Checkout Session 作成処理を既存 Customer ルートも Service 層へ寄せ、API 層の Stripe 呼び出しを減らす。

#### 2. 既存 Customer ルートの回帰テストが不足している

追加された API テストは `stripe_customer_id IS NULL` の Customer 新規作成ルートを確認している。既存 Customer ルートについては未確認。

不足しているテスト:

- `billing_status=free`
- `trial_end_date < now`
- `stripe_customer_id IS NOT NULL`
- `POST /api/v1/billing/create-checkout-session` が 200
- Stripe に渡す `subscription_data` に `trial_end` が含まれない
- DB の `billing_status` が `past_due` に補正される

推奨:

- `test_billing.py` に既存 Customer ルート用のテストを追加する。

#### 3. Service テストの `stripe_customer_id` が固定値で、DB 残存データに弱い

該当箇所:

- `cus_mock_expired_trial`
- `cus_mock_future_trial`

今回の再実行では通過したが、`billings.stripe_customer_id` は unique 制約がある。過去の失敗時には固定値が残存データと衝突して `UniqueViolation` が発生した。

推奨:

- `uuid4().hex` などを使い、テストごとに一意な Customer ID にする。
- 例: `cus_mock_expired_trial_{uuid4().hex[:8]}`

#### 4. Service の期限切れテストで DB の `trial_end_date` と引数が一致していない

該当テスト:

- `test_create_checkout_session_with_customer_excludes_expired_trial_end`

`setup_office_with_billing` は未来の `trial_end_date` を持つ Billing を作成する。一方、テストではメソッド引数にだけ過去の `expired_trial_end` を渡している。

影響:

- 実運用の API 経路では DB の `billing.trial_end_date` が Service に渡るため、DB 状態と引数がズレたケースは実態と少し離れている。
- 自己修復ロジックのテストとしては、DB の Billing も期限切れ状態に更新したうえで実行した方が正確。

推奨:

- テスト前に対象 Billing の `trial_end_date` を過去日に更新する。
- そのうえで `billing_status` が `past_due` に補正されることも assert する。

## テストの評価

### 良い点

- 期限切れ trial では `trial_end` を Stripe に渡さない、という今回の直接原因に対する回帰テストが追加されている。
- 未来の trial では従来どおり `trial_end` を渡すテストがあり、既存挙動の保持を確認できる。
- API テストで `billing_status=free`、`trial_end_date < now`、`stripe_customer_id IS NULL` の実 HTTP 経路を確認している。
- API テストで DB の `billing_status=past_due` 補正と `stripe_customer_id` 保存まで確認している。

### 追加したいテスト

- [ ] 既存 Customer あり、期限切れ free の API テスト。
- [ ] 既存 Customer あり、trial 中 free の API テスト。
- [ ] `billing_status=past_due`、期限切れ trial の API テスト。
- [ ] Customer 新規作成ルートで Stripe Checkout Session 作成が失敗した場合、`stripe_customer_id` と `billing_status` 補正が rollback されること。
- [ ] `trial_end_date` が naive datetime の場合でも比較で 500 にならないこと。既存 Customer ルートも含める。

## 総評

Green フェーズとして、今回の直接原因である「Customer 新規作成ルートで過去の `trial_end` を Stripe に渡す」問題は修正されている。追加テスト 3 件も Docker 上で通過した。

一方で、チェックリスト全体から見ると、既存 Customer ルートの DB 状態補正とテストがまだ不足している。Checkout 500 の直接対策としては前進しているが、「期限切れ `free` を Checkout 前に `past_due` に補正する」という仕様を全ルートで保証するには追加対応が必要。

## 推奨対応順

1. 既存 Customer ルートでも期限切れ `free -> past_due` 補正を行う。
2. 既存 Customer ルート用の API テストを追加する。
3. Service テストの固定 `stripe_customer_id` を一意値に変更する。
4. Service の期限切れテストで DB の `trial_end_date` も過去日に揃える。
5. 必要に応じて Checkout Session 作成処理を Service 層へ寄せ、API 層の Stripe 呼び出し重複を減らす。

## 周辺機能への影響調査結果

追記日: 2026-06-17

今回の変更による周辺機能への影響を確認するため、課金 API、BillingService、バッチ、課金ステータス helper、キャンセル関連のテストを Docker コンテナ内で実行した。

```bash
docker exec keikakun_app-backend-1 pytest \
  tests/api/test_billing.py \
  tests/services/test_billing_service.py \
  tests/tasks/test_billing_check.py \
  tests/services/test_billing_status_helpers.py \
  tests/services/test_billing_canceling.py \
  -m "not performance"
```

結果:

- 61 passed
- 1 failed
- 15 warnings

失敗したテスト:

```text
tests/api/test_billing.py::test_create_checkout_session_expired_free_with_existing_customer_recovers_to_past_due
```

失敗内容:

```text
assert billing_after.billing_status == BillingStatus.past_due
actual: BillingStatus.free
```

### 影響範囲の結論

- Customer 未作成ルートでは、期限切れ `free` の Checkout 500 対策は有効。
- Customer 未作成ルートでは、過去 `trial_end` を Stripe に渡さず、Checkout 前に `past_due` へ補正できている。
- 既存 Customer ありルートでは、過去 `trial_end` を Stripe に渡さないため Checkout 500 は避けられる可能性が高い。
- ただし、既存 Customer ありルートでは `billing_status=free` かつ `trial_end_date < now` の DB 状態が `past_due` に補正されない。
- そのため、既存 Customer ありの期限切れ事業所では、Checkout に進めても DB が `free` のまま残る。

### バックエンド権限制御への影響

`app/api/deps.py` の `require_active_billing()` は、`past_due` または `canceled` の場合に書き込み操作を 402 で制限する。

既存 Customer ありルートで期限切れ `free` が `past_due` に補正されない場合、以下の影響が残る。

- Trial 期限切れにもかかわらず `billing_status=free` のままになる。
- `require_active_billing()` が制限対象と判定しない。
- `support_plans` や `welfare_recipients` など、`require_active_billing` が付いた書き込み API を利用できてしまう可能性がある。

### フロントエンド表示への影響

`k_front/contexts/BillingContext.tsx` は、`billing_status=past_due` の場合に `canWrite=false`、`isPastDue=true` と判定する。

既存 Customer ありルートで `free` のまま残る場合、以下の影響がある。

- `PastDueModalWrapper` が支払い遅延モーダルを表示しない。
- `BillingProtectedButton` などの `canWrite` 判定が制限状態にならない。
- `TrialExpiryBanner` は `free` のみ対象だが、期限切れの場合は表示しないため、グローバルな警告が出ない。
- 管理画面プランタブでは、期限切れ `free` 用の黄色警告が表示される。
- `past_due` 用の赤い警告や支払い遅延扱いにはならない。

### Checkout / Portal 導線への影響

Customer 未作成ルートでは、Checkout Session 作成成功時点で `stripe_customer_id` と `past_due` が保存される。

この場合、ユーザーが Stripe Checkout を途中でキャンセルしても DB 上は以下の状態になる。

```text
billing_status = past_due
stripe_customer_id = cus_...
stripe_subscription_id = NULL
```

想定される影響:

- `past_due` として書き込み制限がかかる。
- 管理画面ではサブスク登録ボタンが表示される。
- `past_due` では支払い方法変更・解約ボタンも表示されるため、Subscription 未作成 Customer に対して Portal を開く UX は別途確認が必要。

### 影響が見つからなかった範囲

以下の周辺テストは通過した。

- `process_payment_succeeded`
- `process_payment_failed`
- `process_subscription_created`
- `process_subscription_updated`
- `process_subscription_deleted`
- missing customer 系 Webhook 処理
- `check_trial_expiration`
- `check_scheduled_cancellation`
- `BillingStatus` helper
- `canceling -> canceled` 関連
- キャンセル予定、キャンセル取り消し、解約 Webhook 関連

現時点では、Webhook、キャンセル、バッチ、課金ステータス helper への直接的な回帰は確認されていない。

### 追加で必要な対応

- [ ] 既存 Customer ありルートでも期限切れ `free -> past_due` 補正を行う。
- [ ] `test_create_checkout_session_expired_free_with_existing_customer_recovers_to_past_due` を通す。
- [ ] Customer 有無に依存しない共通の期限切れ補正処理を Service 層へ切り出す。
- [ ] `past_due` かつ `stripe_subscription_id IS NULL` の場合に Customer Portal を表示する UX が妥当か確認する。
- [ ] Checkout キャンセル後の DB 状態とフロント表示を手動または E2E で確認する。

### 判定

今回の変更は、Customer 未作成ルートで発生していた Checkout 500 の直接対策としては有効。

ただし、既存 Customer ありの期限切れ `free` 事業所では DB 状態補正が未完了であり、課金制限・フロント表示・テストの観点で不整合が残る。

したがって、現時点では「Checkout 500 の主要原因は緩和されたが、周辺機能まで含めた Green 完了ではない」と判断する。

## 追加修正後の再レビュー

追記日: 2026-06-17

レビュー指摘をもとに、以下の追加修正が入った状態を再確認した。

確認対象:

- `k_back/app/services/billing_service.py`
- `k_back/app/api/v1/endpoints/billing.py`
- `k_back/tests/api/test_billing.py`
- `k_back/tests/services/test_billing_service.py`

主な追加修正:

- `BillingService.correct_expired_free_billing_before_checkout()` が追加された。
- `BillingService._normalize_trial_end_date()` が追加された。
- Customer 未作成ルートと既存 Customer ありルートの両方で、期限切れ `free -> past_due` 補正を呼ぶようになった。
- 既存 Customer ありの期限切れ `free` API テストが追加された。
- Service テストでは DB 側の `trial_end_date` も過去日に揃えるようになった。
- テスト用 `stripe_customer_id` / `checkout_session_id` は `uuid4()` 付きで一意化された。

### 再実行したテスト

まず、修正者が提示した対象テストを Docker コンテナ内で再実行した。

```bash
docker exec keikakun_app-backend-1 pytest \
  tests/services/test_billing_service.py::TestBillingServiceStripeIntegration \
  tests/api/test_billing.py::test_create_checkout_session_includes_metadata \
  tests/api/test_billing.py::test_create_checkout_session_expired_free_without_customer_recovers_to_past_due \
  tests/api/test_billing.py::test_create_checkout_session_expired_free_with_existing_customer_recovers_to_past_due \
  -q
```

結果:

- 7 passed
- 15 warnings

次に、前回 1 failed だった課金周辺テスト一式を再実行した。

```bash
docker exec keikakun_app-backend-1 pytest \
  tests/api/test_billing.py \
  tests/services/test_billing_service.py \
  tests/tasks/test_billing_check.py \
  tests/services/test_billing_status_helpers.py \
  tests/services/test_billing_canceling.py \
  -m "not performance" \
  -q
```

結果:

- 62 passed
- 15 warnings

前回失敗していた以下のテストは通過した。

```text
tests/api/test_billing.py::test_create_checkout_session_expired_free_with_existing_customer_recovers_to_past_due
```

### 解消された指摘

- [x] 既存 Customer ありルートでも期限切れ `free -> past_due` 補正が行われる。
- [x] 既存 Customer ありルートで過去 `trial_end` が Stripe に渡されない。
- [x] 既存 Customer ありルート用 API テストが追加された。
- [x] Customer 未作成ルートと既存 Customer ありルートで、期限切れ `free` 補正の判定処理が共通化された。
- [x] Service テストの DB 状態と引数の `trial_end_date` が一致するようになった。
- [x] テスト用 Customer ID / Session ID の固定値衝突リスクが下がった。
- [x] 前回の課金周辺テスト一式 `61 passed / 1 failed` は `62 passed` になった。

### 追加レビュー所見

#### 1. 既存 Customer ありルートの補正は Checkout 作成前に commit される

該当箇所:

- `k_back/app/api/v1/endpoints/billing.py`
- `correct_expired_free_billing_before_checkout(..., auto_commit=True)`

既存 Customer ありルートでは、Checkout Session 作成前に `free -> past_due` 補正が commit される。これは「期限切れ free は Checkout 成否に関係なく past_due に補正すべき」という仕様なら妥当。

一方で、Customer 未作成ルートでは `auto_commit=False` で補正し、Customer ID 更新と Checkout Session 作成成功後にまとめて commit される。そのため、2 つのルートで補正の commit タイミングが異なる。

影響:

- 既存 Customer ありルートでは、Stripe Checkout Session 作成が失敗して 500 になっても `billing_status=past_due` の補正だけは残る。
- Customer 未作成ルートでは、Stripe Checkout Session 作成が失敗すると補正も rollback される。

判定:

- ブロッカーではない。
- ただし仕様として明文化しておくのが望ましい。
- 「期限切れ free の補正は Checkout 成否に関係なく確定する」なら、Customer 未作成ルートも同じ思想に寄せる余地がある。
- 「Checkout 作成処理は全体で atomic にしたい」なら、既存 Customer ありルートも Service 層へ移し、Checkout 成功後に commit する設計が望ましい。

#### 2. API 層に直接 `commit()` / `flush()` は追加されていない

`.codex/skills/SKILLS.md` の 4 層アーキテクチャルールでは、API 層での `commit()` / `flush()` は禁止。

今回の修正では、`billing.py` から Service メソッドを呼び、その Service メソッドが CRUD の `auto_commit=True` を使う形になっている。API 層に直接 `db.commit()` / `db.flush()` は追加されていない。

判定:

- ルール違反とは見なさない。
- ただし、既存 Customer ありルートには Stripe Checkout Session 作成そのものが API 層に残っているため、理想的には Checkout 作成処理全体を Service 層に寄せると責務がより明確になる。

#### 3. Stripe API エラー時ログの情報量はまだ未完了

チェックリストでは、Stripe API エラー時に `billing_id`、`office_id`、`stripe_customer_id` の有無、`trial_end_date`、`billing_status` が追えるログを残す項目がある。

現状:

- 補正時のログには `billing_id` と `office_id` が出る。
- Stripe API エラー時のログは、既存の `Stripe API error: {e}` または `Stripe Checkout Session作成エラー: {e}` が中心。

判定:

- 今回の Green フェーズの必須条件ではない。
- ただし本番調査性を上げるには、別タスクとして対応した方がよい。

#### 4. `trial_end_date=None` の直接テストは未追加

`BillingService.create_checkout_session_with_customer()` の引数は `Optional[datetime]` になったが、model 上の `Billing.trial_end_date` は nullable=False。

判定:

- 現行 DB 仕様では優先度は低い。
- Service 単体の堅牢性を上げるなら、`trial_end_date=None` でも `trial_end` を渡さず成功するテストを追加できる。

### 周辺機能への影響再評価

今回の再実行で、以下の範囲に直接的な回帰は確認されなかった。

- Billing API
- Checkout Session 作成
- Customer 未作成ルート
- 既存 Customer ありルート
- Webhook idempotency
- `process_payment_succeeded`
- `process_payment_failed`
- `process_subscription_created`
- `process_subscription_updated`
- `process_subscription_deleted`
- missing customer 系 Webhook 処理
- `check_trial_expiration`
- `check_scheduled_cancellation`
- BillingStatus helper
- `canceling -> canceled`
- キャンセル予定、キャンセル取り消し、解約 Webhook 関連

### 再レビュー判定

前回のブロッカーだった「既存 Customer ありの期限切れ `free` が `past_due` に補正されない」問題は解消された。

課金周辺テスト一式も `62 passed` になっており、今回の Checkout 500 修正としては Green 到達と判断できる。

残る主な論点は以下。

- 既存 Customer ありルートの補正 commit タイミングを仕様として許容するか。
- Stripe API エラー時ログを本番調査向けに拡充するか。
- Checkout 作成処理を将来的に Service 層へさらに集約するか。

現時点では、上記はいずれも追加改善または設計整理の範囲であり、今回の修正を止めるブロッカーではない。
