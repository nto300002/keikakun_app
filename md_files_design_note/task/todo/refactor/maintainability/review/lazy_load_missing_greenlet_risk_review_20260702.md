# リファクタリング後 lazy load / MissingGreenlet リスク調査

作成日: 2026-07-02

## 2026-07-02 判断記録

判定: **修正すべき。ただし全項目を同じ優先度で即時実装する必要はない。**

理由:

- `billing.create_portal_session` で実際に `MissingGreenlet` が発生しており、これは実害のある High 優先度の不具合。
- `get_current_user_minimal` / `require_owner` / `require_manager_or_owner` の戻り値で relationship を触る実装は、今後も同じ事故を起こしやすい。
- `check_employee_restriction()` は現行呼び出し元が `require_active_billing` や `get_current_user` 由来で office 付き Staff になっているため、直ちに本番障害化する可能性は高くない。ただし関数単体の契約が曖昧で、minimal Staff を渡すと再発し得るため、保守性改善として修正対象にする。

対応方針:

- **完了扱い**: `create_checkout_session` / `create_portal_session` は `require_owner_with_office` を使うよう修正し、office association を eager load する。
- **追加済み**: `create_portal_session` は token 認証経路で `office_associations` が未ロードになっても `MissingGreenlet` にならない回帰テストを追加。
- **完了扱い**: `check_employee_restriction()` は `office_id` を引数として受け取る形へ変更し、関数内で `current_staff.office` / `current_staff.office_associations` を参照しないよう修正済み。
- **追加済み**: `create_portal_session` / `create_checkout_session` は Cookie 認証 + CSRF トークン付きの回帰テストを追加済み。
- **レビュー基準化**: `require_owner` / `require_manager_or_owner` / `require_app_admin` の戻り値で `office_associations` / `office` に触らない。office 情報が必要なら `get_current_user_with_office` / `require_owner_with_office` を使うか、endpoint 内で `selectinload` 付き再取得を行う。

今回の実装状況:

- `k_back/app/api/deps.py`
  - `require_owner_with_office` を追加済み。
- `k_back/app/api/v1/endpoints/billing.py`
  - `create_checkout_session` と `create_portal_session` を `require_owner_with_office` に変更済み。
  - Portal Session 作成失敗ログに `billing_id` / `office_id` / Stripe error type を残すよう改善済み。
- `k_back/tests/api/test_billing.py`
  - `test_create_portal_session_loads_office_associations_for_token_auth` を追加済み。
- `k_back/tests/api/test_deps_permissions.py`
  - `require_owner_with_office` が `get_current_user_with_office` を使うことを固定済み。
- `k_back/app/api/deps.py`
  - `check_employee_restriction()` を `office_id` 引数化し、Employee時の office ID 解決を呼び出し元責務へ変更済み。
- `k_back/app/api/v1/endpoints/welfare_recipients.py`
  - `check_employee_restriction()` 呼び出し時に、既に検証済みの `office_id` を渡すよう変更済み。
- `k_back/app/api/v1/endpoints/support_plan_statuses.py`
  - `check_employee_restriction()` 呼び出し時に、アクセス確認済みの `recipient_office_assoc.office_id` を渡すよう変更済み。

検証:

```bash
docker exec keikakun_app-backend-1 pytest tests/api/test_deps_permissions.py tests/api/test_billing.py::test_create_portal_session_loads_office_associations_for_token_auth tests/api/test_billing.py::test_create_portal_session_loads_office_associations_for_cookie_auth tests/api/test_billing.py::test_create_checkout_session_loads_office_associations_for_cookie_auth
# 21 passed

docker exec keikakun_app-backend-1 pytest tests/api/test_billing.py tests/api/test_deps_permissions.py tests/api/v1/test_support_plan_statuses_employee_restriction.py tests/api/v1/test_support_plan_statuses.py
# 45 passed

docker exec keikakun_app-backend-1 pytest tests/api/v1/test_welfare_recipients.py tests/api/v1/test_support_plans_employee_restriction.py
# 10 passed
```

残タスク:

- [x] `check_employee_restriction()` の `office_id` 引数化、または office付き Staff 必須契約のテスト化。
- [x] `create_checkout_session` についても `office_associations` eager load の回帰テストを追加する。
- [x] Cookie 認証での `create_portal_session` / `create_checkout_session` 回帰テストを追加する。
- [ ] minimal 依存を使う endpoint の追加レビュー項目として、この文書の判定基準をPRチェックリストへ反映する。

## 背景

local の有料会員管理画面で `POST /api/v1/billing/create-portal-session` が `500 Internal Server Error` になり、frontend では CORS ブロックおよび `Failed to fetch` として表示された。

backend ログでは以下が確認された。

```text
k_back/app/api/v1/endpoints/billing.py:223
if not current_user.office_associations:

sqlalchemy.exc.MissingGreenlet: greenlet_spawn has not been called; can't call await_only() here.
```

これはブラウザ側の遅延ロードではなく、backend の SQLAlchemy async 環境で未ロードの relationship を lazy load しようとしたことによるエラー。

## 今回確認した原因

対象:

- `k_back/app/api/v1/endpoints/billing.py`
- `k_back/app/api/deps.py`

発生条件:

- endpoint または依存関係から返された `Staff` に `office_associations` が eager load されていない。
- その状態で `current_user.office_associations` にアクセスする。
- SQLAlchemy が relationship を追加取得しようとするが、async の通常処理中では implicit IO が許可されず `MissingGreenlet` になる。

現行ファイル上の設計:

- `get_current_user_minimal`: `Staff` 本体のみ。`office_associations` / `office` は eager load しない。
- `get_current_user_with_office`: `Staff.office_associations` と `OfficeStaff.office` を `selectinload` する。
- `get_current_user = get_current_user_with_office` として既存互換を維持。
- `require_owner_with_office` は `get_current_user_with_office` を使う。
- `require_owner` / `require_manager_or_owner` / `require_app_admin` は `get_current_user_minimal` を使う。

## 高リスク箇所

### 1. `billing.create_portal_session`

対象:

- `k_back/app/api/v1/endpoints/billing.py`
- `create_portal_session()`

現状:

- endpoint は `Depends(deps.require_owner_with_office)` になっているため、現行コードだけを見ると `office_associations` は eager load 済みであるべき。
- ただし local backend ログでは `current_user.office_associations` で `MissingGreenlet` が発生している。

確認すべきこと:

- docker コンテナ内の `app/api/deps.py` がローカルの現行ファイルと一致しているか。
- hot reload 前の古い `require_owner_with_office` / `get_current_user` が動いていないか。
- テスト override で `require_owner_with_office` または `get_current_user` に minimal な `Staff` を返していないか。

推奨:

- `create_portal_session` の回帰テストは Cookie 認証でも実行する。
- `create_checkout_session` と `create_portal_session` の両方で、`office_associations` が事前ロードされることをテストする。

### 2. `check_employee_restriction()`

対象:

- `k_back/app/api/deps.py`
- `check_employee_restriction()`

リスク:

```python
if current_staff.office:
    office_id = current_staff.office.id
elif current_staff.office_associations:
    ...
```

- `current_staff` が `get_current_user_minimal` / `require_manager_or_owner` / `require_owner` 由来の場合、`current_staff.office` や `current_staff.office_associations` は lazy load になる可能性がある。
- 現在の主な呼び出し元は `require_active_billing` や `get_current_user` 経由で office 付きになっているが、関数単体の契約としては office eager load を要求していない。

呼び出し元:

- `k_back/app/api/v1/endpoints/welfare_recipients.py`
- `k_back/app/api/v1/endpoints/support_plan_statuses.py`

推奨:

- `check_employee_restriction()` は `current_staff.office_associations` を直接参照しない。
- `office_id` を呼び出し元で確定して引数として渡す形にする。
- 少なくとも docstring に「office付き Staff が必須」と明記し、minimal Staff で呼ばれたらテストで落とす。

### 3. minimal 依存を使う権限チェック後に relationship を触る endpoint

対象:

- `Depends(deps.require_owner)`
- `Depends(deps.require_manager_or_owner)`
- `Depends(deps.require_app_admin)`

理由:

- これらは `get_current_user_minimal` を使う。
- role 判定だけなら問題ないが、その戻り値の `current_user` / `current_staff` で `office_associations` / `office` を触ると `MissingGreenlet` になる。

検索観点:

```bash
rg -n "Depends\\(deps\\.require_(owner|manager_or_owner|app_admin)\\)|current_(user|staff|admin)\\.office|current_(user|staff|admin)\\.office_associations" k_back/app
```

現時点の確認:

- `k_back/app/api/v1/endpoints/offices.py` は `require_owner` / `require_manager_or_owner` 後に、endpoint 内で `selectinload(Staff.office_associations).selectinload(OfficeStaff.office)` 付きで再取得しているため低リスク。
- `k_back/app/api/v1/endpoints/staffs.py` のスタッフ削除も、owner と対象 staff を `selectinload` 付きで再取得しているため低リスク。

注意:

- 今後、`require_owner` の戻り値をそのまま使って事務所IDを取る実装を追加すると再発する。
- office 情報が必要な endpoint は `require_owner_with_office` または `get_current_user_with_office` を使う。

## 中リスク箇所

### 1. schema serialization による暗黙 relationship 参照

対象例:

- `response_model=schemas.staff.StaffRead`
- `return current_user`
- `model_validate(orm_obj)`

リスク:

- Pydantic の `from_attributes` / `model_validate` が relationship フィールドを参照すると、未ロード relationship が lazy load される。
- 現行の `get_current_user` は office付きだが、minimal Staff を response に返す endpoint が増えると再発する。

確認済み:

- `k_back/app/api/v1/endpoints/staffs.py::get_current_user_info` は `Depends(deps.get_current_user)` で office付き依存のため低リスク。
- auth signup 系は登録後に `selectinload` 付きで再取得して返している。

推奨:

- response に relationship を含む schema を返す endpoint は、返却前に明示的に eager load する。
- minimal 依存で取得した ORM オブジェクトをそのまま relationship 付き schema に返さない。

### 2. CRUD / Service 内で渡された ORM の relationship を前提にする処理

対象例:

- `k_back/app/crud/crud_archived_staff.py`
- `staff.office_associations` / `assoc.office` を参照する処理

リスク:

- 呼び出し元が eager load 済み staff を渡す前提の場合、契約が崩れると `MissingGreenlet` になる。

推奨:

- CRUD / Service の public method は、IDを受け取って自身で必要な relationship を eager load する。
- ORM オブジェクトを受け取る場合は「どの relationship がロード済みである必要があるか」を関数名または docstring に明記する。

## 低リスクまたは対策済みの箇所

### `get_current_user` 利用 endpoint

現行では `get_current_user = get_current_user_with_office` のため、`Depends(deps.get_current_user)` を使う endpoint で `current_user.office_associations` を読む箇所は基本的に低リスク。

対象例:

- `k_back/app/api/v1/endpoints/support_plans.py`
- `k_back/app/api/v1/endpoints/messages.py`
- `k_back/app/api/v1/endpoints/role_change_requests.py`
- `k_back/app/api/v1/endpoints/employee_action_requests.py`
- `k_back/app/api/v1/endpoints/withdrawal_requests.py`
- `k_back/app/api/v1/endpoints/support_plan_statuses.py`
- `k_back/app/api/v1/endpoints/billing.py::get_billing_status`

ただし、テストや dependency override で minimal な `Staff` を返すとリスクが戻る。

### welfare recipient の対象者側 association

対象:

- `k_back/app/api/v1/endpoints/welfare_recipients.py`
- `crud_welfare_recipient.get_with_office_associations()`
- `crud_welfare_recipient.get_with_details()`

現状:

- 受給者側の `welfare_recipient.office_associations` は CRUD で `selectinload` されている箇所が多く、今回の Staff 側より低リスク。

注意:

- `crud_welfare_recipient.get()` のような素の取得結果で `office_associations` を読む実装を追加しない。

## 追加すべきテスト

- [x] `create_portal_session` を Cookie 認証で実行し、`MissingGreenlet` ではなく 200 または業務的な 4xx が返ること。
- [x] `create_checkout_session` を Cookie 認証で実行し、`office_associations` lazy load が起きないこと。
- [ ] `require_owner` を使う endpoint で office 情報が必要な場合、endpoint 内再取得または `require_owner_with_office` が使われていること。
- [x] `check_employee_restriction()` が minimal Staff で呼ばれた場合の扱いを明確化すること。
- [ ] relationship 付き schema を返す endpoint で、返却前に必要な relationship が eager load されていること。

## 修正優先度

### High

- `create_portal_session` の local 再現経路をテストで固定する。
- `check_employee_restriction()` の office_id 解決を呼び出し元責務に寄せる、または office付き Staff 必須の契約をテスト化する。

### Medium

- `require_owner` / `require_manager_or_owner` を使う endpoint の追加時レビュー観点を明文化する。
- relationship 付き response schema で minimal Staff を返していないか、静的検索をCIまたはレビュー項目に入れる。

### Low

- CRUD / Service の docstring に「必要な eager load 済み relationship」を追記する。

## レビュー時の判定基準

- office 情報が必要な endpoint は `get_current_user_with_office` / `require_owner_with_office` / `require_active_billing` のいずれかを使っている。
- minimal 依存の戻り値では `office_associations` / `office` に触らない。
- relationship を含む schema に ORM を渡す前に `selectinload` / `joinedload` が明示されている。
- テスト override は本番依存と同じ eager load 条件を再現している。
