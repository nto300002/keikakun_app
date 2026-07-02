## 概要
Stripe有料会員管理とログイン時CSRFの不具合を修正し、SQLAlchemy async環境でのlazy loadによる `MissingGreenlet` 再発リスクを下げました。

## 変更内容

### バックエンド
- [x] `create-checkout-session` / `create-portal-session` でoffice付きOwner依存を使うよう修正
- [x] `require_owner_with_office` を追加し、office情報が必要なOwner APIで `office_associations` をeager load
- [x] Stripe Customer Portal作成失敗時のログに `billing_id` / `office_id` / Stripe error type を追加
- [x] `check_employee_restriction()` を `office_id` 引数化し、関数内で `current_staff.office` / `office_associations` を参照しない形に修正
- [x] welfare recipient / support plan status のEmployee制限チェック呼び出し元で、検証済みの `office_id` を渡すよう修正
- [x] `/api/v1/auth/token` とMFAログイン検証系をCSRF除外に追加
  - 古い `access_token` Cookie が残っていても、ログイン本体の退会済み判定メッセージまで到達できるように修正

### ドキュメント
- [x] lazy load / MissingGreenlet リスク調査文書に判断記録、対応状況、検証結果を追記

### DB migration確認
- [x] DB変更なし
- [x] Alembic migration追加なし

## テスト
```bash
docker exec keikakun_app-backend-1 pytest tests/api/v1/test_csrf_protection.py
# 9 passed

docker exec keikakun_app-backend-1 pytest tests/api/v1/test_mfa_api.py tests/api/v1/test_mfa_verify_error_handling.py tests/api/v1/test_auth_session_duration.py tests/api/v1/test_app_admin_login_with_names.py
# 29 passed

docker exec keikakun_app-backend-1 pytest tests/api/test_deps_permissions.py tests/api/test_billing.py::test_create_portal_session_loads_office_associations_for_token_auth tests/api/test_billing.py::test_create_portal_session_loads_office_associations_for_cookie_auth tests/api/test_billing.py::test_create_checkout_session_loads_office_associations_for_cookie_auth
# 21 passed

docker exec keikakun_app-backend-1 pytest tests/api/test_billing.py tests/api/test_deps_permissions.py tests/api/v1/test_support_plan_statuses_employee_restriction.py tests/api/v1/test_support_plan_statuses.py
# 45 passed

docker exec keikakun_app-backend-1 pytest tests/api/v1/test_welfare_recipients.py tests/api/v1/test_support_plans_employee_restriction.py
# 10 passed
```

## レビュー観点
- `require_owner` / `require_manager_or_owner` / `require_app_admin` の戻り値でrelationshipを直接参照していないか
- office情報が必要なAPIで `get_current_user_with_office` / `require_owner_with_office` / 明示的な `selectinload` 再取得が使われているか
- ログインAPIがCSRFで先に遮断されず、退会済みなどの業務メッセージを返せるか
- Cookie認証 + CSRF付きのStripe Checkout / Portal作成で `MissingGreenlet` が再発しないか

## 関連Issue
Closes #
