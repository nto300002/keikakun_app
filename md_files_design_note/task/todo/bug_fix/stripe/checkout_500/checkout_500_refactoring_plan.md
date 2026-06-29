# Stripe Checkout 500 追加リファクタリング計画

作成日: 2026-06-17

## 目的

`checkout_500_green_phase_review.md` の追加レビューで残った論点を、リスクを抑えて段階的に整理する。

今回の Checkout 500 修正は Green 到達済みであり、現時点の本番不具合をさらに広げないことを最優先にする。そのため、この計画では大きな責務移動を急がず、仕様の明文化、ログ改善、テスト追加、小さなリファクタリングの順で進める。

対象論点:

- 既存 Customer ありルートの `free -> past_due` 補正 commit タイミング。
- Stripe API エラー時ログの情報量。
- Checkout 作成処理を Service 層へ寄せるかどうか。

## 基本方針

- 現在通っている Checkout 導線を壊さない。
- 仕様が曖昧な状態で commit/rollback の挙動を変更しない。
- 本番調査性を先に上げ、挙動変更は後続の小さなPRで行う。
- API 層から Service 層への責務移動は一括で行わず、テストで守れる範囲から段階的に進める。
- Customer Portal、scheduler、Cloud Scheduler など周辺設計には同時に手を広げない。

## 現状整理

### 解消済み

- Customer 未作成ルートで過去の `trial_end` を Stripe に送らない。
- 既存 Customer ありルートでも過去の `trial_end` を Stripe に送らない。
- Customer 未作成ルートと既存 Customer ありルートの両方で、期限切れ `free -> past_due` 補正が行われる。
- 既存 Customer ありルートの回帰テストが追加されている。
- 課金周辺テスト一式は Green 到達済み。

### 残る懸念

#### 1. commit タイミング差分

既存 Customer ありルートでは、Checkout Session 作成前に `free -> past_due` 補正が commit される。

Customer 未作成ルートでは、Customer ID 更新、`free -> past_due` 補正、Checkout Session 作成が成功したあとにまとめて commit される。Stripe API エラー時には rollback される。

この差分は即時障害ではないが、仕様として未確定のまま挙動を変えると、以下のリスクがある。

- Checkout 失敗時に `past_due` を残すかどうかで、書き込み制限やフロント表示が変わる。
- 既存 Customer ありルートだけ挙動を変えると、過去に通った回帰テストの意味が変わる。
- Customer 未作成ルートの挙動を変えると、Checkout 失敗時に DB 状態が進む可能性がある。

#### 2. Stripe API エラー時ログ不足

現状のエラーログは Stripe エラー本文中心で、DB 状態やルート種別を追いにくい。

ただし、ログ改善にも以下のリスクがある。

- Stripe key、メールアドレス、氏名などを誤って出力する。
- Customer ID をそのまま出すことで、調査ログの取り扱いが難しくなる。
- 既存ログ基盤が structured logging を想定していない場合、`extra` が期待通り出ない。

#### 3. Service 層への集約

Checkout 作成処理を Service 層へ寄せる方向性は妥当だが、一括移動には以下のリスクがある。

- 既存テストのモック対象が大きく変わり、テストが実装詳細に引っ張られる。
- Customer 未作成ルートと既存 Customer ありルートの微妙な差分を見落とす。
- 例外変換、rollback、Stripe API 呼び出し順序が変わる。
- Green 到達済みの修正に対して、不要に大きな差分を作る。

## 推奨対応順

### Phase 1: 仕様を変えずに観測性を上げる

優先度: 高

目的:

- 本番で再発したときに原因を追えるようにする。
- 挙動変更を伴わないため、リスクが比較的小さい。

対応内容:

- Stripe API エラー時のログに、非秘匿の調査情報を追加する。
- ログには Customer ID の実値ではなく `has_stripe_customer_id` を出す。
- `billing_status`、`trial_end_date`、`billing_id`、`office_id`、`checkout_route` を出す。
- Stripe key、メールアドレス、氏名、住所、カード情報は出さない。

テスト観点:

- `caplog` などで、Stripe API エラー時に最低限の調査情報がログに含まれることを確認する。
- 個人情報や秘密鍵がログに含まれないことも確認する。

完了条件:

- 既存の Checkout 成功/失敗時の挙動は変えない。
- 課金周辺テストが通る。
- ログに必要な非秘匿情報が残る。

### Phase 2: commit タイミングを仕様として文書化する

優先度: 高

目的:

- 挙動を変える前に、どちらを正とするか決める。

検討する仕様:

#### 案 A: 期限切れ `free -> past_due` は Checkout 成否に関係なく確定する

メリット:

- 期限切れ free を確実に課金制限状態へ寄せられる。
- バッチ未実行の不整合をユーザー操作時に自己修復しやすい。

リスク:

- Checkout が失敗しても `past_due` が残る。
- ユーザーが支払い画面へ進めなかった場合でも書き込み制限が発生する。
- Customer 未作成ルートの現行 rollback 挙動を変える必要がある可能性がある。

#### 案 B: Checkout 作成処理は atomic とし、Stripe API エラー時は補正も rollback する

メリット:

- Checkout 作成失敗時に DB 状態だけ先に進まない。
- Customer 未作成ルートの現行挙動に近い。
- テストで rollback を明確に保証しやすい。

リスク:

- Stripe API エラーが続く限り、期限切れ `free` が残る可能性がある。
- バッチ未実行の根本問題は解決しない。
- 既存 Customer ありルートの現行 commit タイミングを変える場合、挙動変更になる。

保守的な推奨:

- まずは現行挙動を仕様として明文化し、すぐには変えない。
- 変更する場合は、別PRで案 A/B のどちらかを明示してから行う。
- そのPRでは Checkout 失敗時の DB 状態を Red テストで固定してから実装する。

### Phase 3: 小さなService層整理

優先度: 中

目的:

- API 層の責務を少しずつ薄くする。
- 大きな移動による回帰リスクを避ける。

安全な順序:

1. Checkout Session の `subscription_data` 生成を Service 層の helper に閉じ込める。
2. Customer 未作成ルートと既存 Customer ありルートで共通のパラメータ生成を使う。
3. Stripe Checkout Session 作成の wrapper を Service 層に用意する。
4. 最後に API 層の既存 Customer ありルートから直接 Stripe 呼び出しを消す。

注意:

- commit/rollback 方針は Phase 2 で決めるまで変更しない。
- 1PRで「Service層移動」と「commitタイミング変更」を同時に行わない。
- APIレスポンス、Stripe呼び出し引数、DB状態のテストを先に固定する。

### Phase 4: 必要ならCheckout処理をService層へ統合

優先度: 低から中

目的:

- 最終的に API 層を認証、Office/Billing 取得、設定確認、Service 呼び出しに寄せる。

実装候補:

- `BillingService.create_checkout_session(...)` を新設する。
- 既存の `create_checkout_session_with_customer()` と `create_checkout_session_for_existing_customer()` は、すぐ削除せず互換的に残す。
- 新メソッドの内部で Customer 有無を判断し、既存 helper を呼ぶ。
- 十分にテストが安定してから、重複メソッドの整理を検討する。

保守的な到達点:

```python
return await billing_service.create_checkout_session(
    db=db,
    billing_id=billing.id,
    office_id=office_id,
    office_name=office.name,
    user_email=current_user.email,
    user_id=current_user.id,
    stripe_secret_key=get_stripe_secret_key(),
    stripe_price_id=settings.STRIPE_PRICE_ID,
    frontend_url=settings.FRONTEND_URL,
)
```

ただし、この形にするのは Phase 1 から Phase 3 までのテストと仕様確認が終わった後にする。

## TDD 方針

### Red で先に追加するテスト

- Stripe API エラー時ログに、非秘匿の調査情報が含まれる。
- Stripe API エラー時ログに、Stripe key、メールアドレス、氏名が含まれない。
- 既存 Customer ありルートの Checkout Session 作成失敗時に、現行仕様どおりの DB 状態になる。
- Customer 未作成ルートの Checkout Session 作成失敗時に、現行仕様どおりの DB 状態になる。

### Green の最小実装

- まずログだけ改善する。
- commit/rollback 挙動は変えない。
- API 層から Service 層への移動は、ログ改善が安定してから行う。

### Refactor の条件

- 対象テストが通る。
- 課金周辺テストが通る。
- 差分が大きくなりすぎない。
- commit/rollback の仕様変更を含める場合は、PR本文または設計メモで明示する。

## 回帰テスト

最低限:

```bash
docker exec keikakun_app-backend-1 pytest \
  tests/services/test_billing_service.py::TestBillingServiceStripeIntegration \
  tests/api/test_billing.py::test_create_checkout_session_includes_metadata \
  tests/api/test_billing.py::test_create_checkout_session_expired_free_without_customer_recovers_to_past_due \
  tests/api/test_billing.py::test_create_checkout_session_expired_free_with_existing_customer_recovers_to_past_due \
  -q
```

周辺確認:

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

静的確認:

```bash
rg -n "await db\\.commit\\(|await db\\.flush\\(" k_back/app/api/v1/endpoints/billing.py
rg -n "stripe\\.checkout\\.Session\\.create" k_back/app/api/v1/endpoints/billing.py
```

## 完了条件

- 既存の Checkout 成功導線が壊れていない。
- Stripe API エラー時の調査ログが増えている。
- ログに秘匿情報や個人情報が出ない。
- commit/rollback タイミングが文書化されている。
- commit/rollback 挙動を変更する場合は、Red テストで仕様が固定されている。
- Service 層への移動を行う場合は、小さな段階で行われている。
- 課金周辺テスト一式が通る。

## 今回は対象外

- Scheduler 起動修正。
- Cloud Scheduler / Cloud Run Jobs への移行。
- Customer Portal の UX 変更。
- `trial_end_date=None` を DB 仕様として許容する変更。
- 本番 Stripe 設定、Webhook endpoint、Tax 設定の変更。
- Checkout 失敗時に `past_due` を残すかどうかの即時変更。

## 判断メモ

今回の Checkout 500 修正はすでに Green 到達しているため、次の一手は大きな責務移動ではなく、ログ改善と仕様固定を優先する。

Service 層への集約は方向性として妥当だが、commit/rollback の仕様を同時に変えると影響範囲が読みづらくなる。まずは現行挙動をテストと文書で固定し、挙動変更が必要な場合は独立したタスクとして扱う。
