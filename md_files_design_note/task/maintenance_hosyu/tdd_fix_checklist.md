# アーキテクチャ違反 TDD修正チェックリスト

**作成日**: 2026-02-20
**最終更新**: 2026-02-20
**方針**: Red → Green → Refactor（テストを先に書いてから修正）
**参照**: `architecture_violation_audit_2026-02-20.md`

---

## 🔖 次回再開位置

**ステータス**: 🎉 全79項目完了（2026-03-01）

### 完了確認コマンド

```bash
# API層に await db.commit() が0件になることを確認
grep -rn "await db.commit()" k_back/app/api/v1/endpoints/

# API層に from app.crud. 直接importが0件になることを確認
grep -rn "from app\.crud\." k_back/app/api/v1/endpoints/

# テスト全体を実行
docker exec keikakun_app-backend-1 pytest tests/ -v -m "not performance"
```

### 完了した 1-1 の内容（参考）

```
tests/services/test_role_change_service.py
  L829: test_create_request_rollback_on_error   ← 1-1-b ✅ Green完了
  L870: test_approve_request_rollback_on_error  ← 1-1-d ✅ Green完了
  L916: test_reject_request_rollback_on_error   ← 1-1-f ✅ Green完了

patch path 変更:
  "app.services.role_change_service.crud_notice.create"
    → "app.crud.crud_notice.crud_notice.create"
  "app.services.role_change_service.crud_notice.update_type_by_link_url"
    → "app.crud.crud_notice.crud_notice.update_type_by_link_url"
```

---

## TDD手順（各チェック項目共通）

```
1. [ ] Red:   失敗するテストを書く
2. [ ] Green: テストが通る最小限のコードを書く
3. [ ] ✅:    pytest -n auto -m "not performance" でパスを確認してチェック
```

---

## 優先度1: Service層 rollback欠如（本番データ整合性リスク）

### 1-1. `role_change_service.py` — commit×3・rollbackなし・try-exceptなし

> **背景**: `create_request` / `approve_request` / `reject_request` の3メソッドに
> commitがあるがtry-except・rollbackが一切ない。エラー時にデータ不整合が発生する。

- [x] **1-1-a** `create_request`: 失敗テスト作成（例外時にロールバックされることを確認）✅ Red確認済
- [x] **1-1-b** `create_request`: try-except-rollbackパターンを適用してテスト通過 ✅ Green完了
- [x] **1-1-c** `approve_request`: 失敗テスト作成（例外時にロールバックされることを確認）✅ Red確認済
- [x] **1-1-d** `approve_request`: try-except-rollbackパターンを適用してテスト通過 ✅ Green完了
- [x] **1-1-e** `reject_request`: 失敗テスト作成（例外時にロールバックされることを確認）✅ Red確認済
- [x] **1-1-f** `reject_request`: try-except-rollbackパターンを適用してテスト通過 ✅ Green完了
- [x] **1-1-g** `from app.crud.` 直接import (3件) を `from app import crud` に統一してテスト通過 ✅ 完了（テストpatch pathも更新済み）

---

### 1-2. `staff_profile_service.py` — commit×4・rollbackなし

> **背景**: `update_name` / `change_password` / `request_email_change` / `verify_email_change`
> にcommitがあるが rollback 処理が存在しない。パスワード変更等で例外時にデータ不整合のリスク。

- [x] **1-2-a** `update_name`: 失敗テスト作成（例外時にロールバックされることを確認）✅ Red確認済
- [x] **1-2-b** `update_name`: try-except-rollbackパターンを適用してテスト通過 ✅ Green完了
- [x] **1-2-c** `change_password`: 失敗テスト作成（flush後に例外、パスワード変更がrollbackされることを確認）✅ Red確認済
- [x] **1-2-d** `change_password`: except内にrollback追加（finally前にrollback → finally で試行ログ commit）✅ Green完了
- [x] **1-2-e** `request_email_change`: 失敗テスト作成（commit失敗時、flush済みEmailChangeRequestが残らないことを確認）✅ Red確認済
- [x] **1-2-f** `request_email_change`: try-except-rollbackパターンを適用してテスト通過 ✅ Green完了
- [x] **1-2-g** `verify_email_change`: 失敗テスト作成（2回目flush失敗時、email変更がrollbackされることを確認）✅ Red確認済
- [x] **1-2-h** `verify_email_change`: try-except-rollbackパターンを適用してテスト通過 ✅ Green完了

---

### 1-3. `support_plan_service.py` — commit×4・rollbackなし

> **背景**: `handle_deliverable_upload`（2箇所）/ `handle_deliverable_update` /
> `handle_deliverable_delete` にcommitがあるが rollback処理が存在しない。

- [x] **1-3-a** `handle_deliverable_upload`（既存再アップロード L200）: 失敗テスト作成 ✅ Red確認済
- [x] **1-3-b** `handle_deliverable_upload`（既存再アップロード L200）: try-except-rollback適用してテスト通過 ✅ Green完了
- [x] **1-3-c** `handle_deliverable_upload`（新規作成 L369）: 失敗テスト作成 ✅ Red確認済
- [x] **1-3-d** `handle_deliverable_upload`（新規作成 L369）: rollback追加してテスト通過 ✅ Green完了
- [x] **1-3-e** `handle_deliverable_update`: 失敗テスト作成 ✅ Red確認済
- [x] **1-3-f** `handle_deliverable_update`: try-except-rollback適用してテスト通過 ✅ Green完了
- [x] **1-3-g** `handle_deliverable_delete`: 失敗テスト作成 ✅ Red確認済
- [x] **1-3-h** `handle_deliverable_delete`: try-except-rollback適用してテスト通過 ✅ Green完了

---

## 優先度2-A: API層 commit違反 — `auths.py`（7件）

> **背景**: `app/services/auth_service.py` が存在しない。新規作成してビジネスロジックを移管する。

- [x] **2-A-0** `app/services/auth_service.py` を新規作成 ✅ 完了

- [x] **2-A-1** `register_admin`（L74）: 失敗テスト作成 ✅ Red確認済
- [x] **2-A-2** `register_admin`（L74）: `auth_service.register_admin()` を実装、API層からcommitを除去してテスト通過 ✅ Green完了

- [x] **2-A-3** `register_staff`（L117）: 失敗テスト作成 ✅ Red確認済
- [x] **2-A-4** `register_staff`（L117）: `auth_service.register_staff()` を実装、API層からcommitを除去してテスト通過 ✅ Green完了

- [x] **2-A-5** `verify_email`（L162）: 失敗テスト作成 ✅ Red確認済
- [x] **2-A-6** `verify_email`（L162）: `auth_service.verify_email()` を実装、API層からcommitを除去してテスト通過 ✅ Green完了

- [x] **2-A-7** `verify_mfa_for_login`（リカバリーコード部分）: 失敗テスト作成 ✅ Red確認済
- [x] **2-A-8** `verify_mfa_for_login`（リカバリーコード部分）: `auth_service.use_recovery_code()` を実装してテスト通過 ✅ Green完了

- [x] **2-A-9** `verify_mfa_first_time`（L701）: 失敗テスト作成 ✅ Red確認済
- [x] **2-A-10** `verify_mfa_first_time`（L701）: `auth_service.set_mfa_verified_by_user()` を実装してテスト通過 ✅ Green完了

- [x] **2-A-11** `forgot_password`（L843）: 失敗テスト作成 ✅ Red確認済
- [x] **2-A-12** `forgot_password`（L843）: `auth_service.create_password_reset_token()` を実装してテスト通過 ✅ Green完了

- [x] **2-A-13** `reset_password`（L988）: 失敗テスト作成 ✅ Red確認済
- [x] **2-A-14** `reset_password`（L988）: `auth_service.reset_password()` を実装してテスト通過 ✅ Green完了

---

## 優先度2-B: API層 commit違反 — `mfa.py`（7件）

> **背景**: `app/services/mfa.py` が既存。未実装のメソッドを追加して移管する。

- [x] **2-B-1** `enroll_mfa`（L59）: 失敗テスト作成 ✅
  - `mfa_service.enroll_mfa()` がMFAシークレット作成・commitすることを確認
- [x] **2-B-2** `enroll_mfa`（L59）: `mfa_service.enroll_mfa()` を実装、API層からcommitを除去してテスト通過 ✅

- [x] **2-B-3** `verify_mfa`（L117）: 失敗テスト作成 ✅
  - MFA有効化フラグがcommitされることを確認
- [x] **2-B-4** `verify_mfa`（L117）: `mfa_service.verify_mfa()` を実装してテスト通過 ✅

- [x] **2-B-5** `disable_mfa`（L159）: 失敗テスト作成 ✅
  - MFA無効化がcommitされることを確認
- [x] **2-B-6** `disable_mfa`（L159）: `mfa_service.disable_mfa()` を実装してテスト通過 ✅

- [x] **2-B-7** `admin_enable_staff_mfa`（L222）: 失敗テスト作成 ✅
  - 管理者によるMFA有効化（シークレット生成・リカバリーコード保存）がcommitされることを確認
- [x] **2-B-8** `admin_enable_staff_mfa`（L222）: `mfa_service.admin_enable_staff_mfa()` を実装してテスト通過 ✅

- [x] **2-B-9** `admin_disable_staff_mfa`（L276）: 失敗テスト作成 ✅
  - 管理者によるMFA無効化がcommitされることを確認
- [x] **2-B-10** `admin_disable_staff_mfa`（L276）: `mfa_service.admin_disable_staff_mfa()` を実装してテスト通過 ✅

- [x] **2-B-11** `disable_all_office_mfa`（L348）: 失敗テスト作成 ✅
  - 事務所全体のMFA一括無効化がcommitされることを確認
- [x] **2-B-12** `disable_all_office_mfa`（L348）: `mfa_service.disable_all_office_mfa()` を実装してテスト通過 ✅

- [x] **2-B-13** `enable_all_office_mfa`（L454）: 失敗テスト作成 ✅
  - 事務所全体のMFA一括有効化がcommitされることを確認
- [x] **2-B-14** `enable_all_office_mfa`（L454）: `mfa_service.enable_all_office_mfa()` を実装してテスト通過 ✅

---

## 優先度3-A: `from app.crud.` 直接import違反 — Service層（16件）

> **背景**: `from app import crud` を使うべきところを個別importしている。
> 循環依存のリスクと保守性低下。修正は機械的で低リスク。

- [x] **3-A-1** `calendar_service.py`（2件）: importを `from app import crud` に統一してテスト通過 ✅
- [x] **3-A-2** `cleanup_service.py`（1件・動的import）: importを `from app import crud` に統一してテスト通過 ✅
- [x] **3-A-3** `welfare_recipient_service.py`（2件）: importを `from app import crud` に統一してテスト通過 ✅
- [x] **3-A-4** `role_change_service.py`（3件）: importを `from app import crud` に統一してテスト通過 ✅ 完了（1-1-g と統合済み）
- [x] **3-A-5** `withdrawal_service.py`（5件）: importを `from app import crud` に統一してテスト通過 ✅
- [x] **3-A-6** `employee_action_service.py`（3件）: importを `from app import crud` に統一してテスト通過 ✅

---

## 優先度3-B: `from app.crud.` 直接import違反 — API層（11件）

- [x] **3-B-1** `admin_inquiries.py`: importを `from app import crud` に統一してテスト通過 ✅（元々clean）
- [x] **3-B-2** `notices.py`: importを `from app import crud` に統一してテスト通過 ✅（元々clean）
- [x] **3-B-3** `inquiries.py`: importを `from app import crud` に統一してテスト通過 ✅（元々clean）
- [x] **3-B-4** `admin_audit_logs.py`: importを `from app import crud` に統一してテスト通過 ✅
- [x] **3-B-5** `welfare_recipients.py`: importを `from app import crud` に統一してテスト通過 ✅
- [x] **3-B-6** `messages.py`: importを `from app import crud` に統一してテスト通過 ✅
- [x] **3-B-7** `withdrawal_requests.py`（2件）: importを `from app import crud` に統一してテスト通過 ✅
- [x] **3-B-8** `admin_announcements.py`: importを `from app import crud` に統一してテスト通過 ✅
- [x] **3-B-9** `archived_staffs.py`: importを `from app import crud` に統一してテスト通過 ✅

---

## 優先度4: 英語エラーメッセージ（6件 / 1ファイル）

> **背景**: `push_subscriptions.py` の HTTPException.detail が英語のまま。

- [x] **4-1** `push_subscriptions.py` L79: `"Failed to subscribe push notifications"` → `"プッシュ通知の登録に失敗しました"` ✅
- [x] **4-2** `push_subscriptions.py` L111: `"Subscription not found"` → `"サブスクリプションが見つかりません"` ✅
- [x] **4-3** `push_subscriptions.py` L114: `"Not authorized to delete this subscription"` → `"このサブスクリプションを削除する権限がありません"` ✅
- [x] **4-4** `push_subscriptions.py` L119: `"Subscription not found"` → `"サブスクリプションが見つかりません"` ✅
- [x] **4-5** `push_subscriptions.py` L132: `"Failed to unsubscribe push notifications"` → `"プッシュ通知の解除に失敗しました"` ✅
- [x] **4-6** `push_subscriptions.py` L165: `"Failed to retrieve subscriptions"` → `"サブスクリプション一覧の取得に失敗しました"` ✅

---

## 優先度5: マジックナンバー定数化（9件）

> **背景**: timedelta の日数がハードコードされており、仕様変更時に全箇所を修正する必要がある。
> `app/core/config.py` または `app/core/constants.py` に定数を追加する。

- [x] **5-1** `app/core/config.py` に定数を追加 ✅
  ```python
  SUPPORT_PLAN_RENEWAL_DAYS: int = 180      # 個別支援計画の次回更新期限
  DASHBOARD_DEADLINE_WARNING_DAYS: int = 30  # 期限切れ間近の警告閾値
  AUDIT_LOG_RETENTION_DAYS: int = 365        # 監査ログ保持期間
  ```
- [x] **5-2** `crud_welfare_recipient.py` L331: `timedelta(days=180)` → 定数に置換 ✅
- [x] **5-3** `welfare_recipient_service.py` L154, L242: `timedelta(days=180)` → 定数に置換 ✅
- [x] **5-4** `support_plan_service.py` L90, L253: `timedelta(days=180)` → 定数に置換 ✅
- [x] **5-5** `crud_dashboard.py` L150, L287, L340: `timedelta(days=30)` → 定数に置換 ✅
- [x] **5-6** `crud_audit_log.py` L453: `timedelta(days=365)` → 定数に置換 ✅

---

## 進捗サマリー

| 優先度 | 項目数 | 完了 | 残り | 状況 |
|-------|-------|------|------|------|
| 1: Service rollback欠如 | 23項目 | 23 | 0 | ✅ 全完了 |
| 2-A: auths.py commit違反 | 15項目 | 15 | 0 | ✅ 全完了 |
| 2-B: mfa.py commit違反 | 14項目 | 14 | 0 | ✅ 全完了 |
| 3-A: Service import違反 | 6項目 | 6 | 0 | ✅ 全完了 |
| 3-B: API import違反 | 9項目 | 9 | 0 | ✅ 全完了（2026-03-01） |
| 4: 英語エラーメッセージ | 6項目 | 6 | 0 | ✅ 全完了（2026-03-01） |
| 5: マジックナンバー | 6項目 | 6 | 0 | ✅ 全完了（2026-03-01） |
| **合計** | **79項目** | **79** | **0** | 🎉 全項目完了 |

---

## TDDテンプレート

### Service層 rollbackテストのテンプレート

```python
# tests/services/test_xxx_service.py
import pytest
from unittest.mock import AsyncMock, patch

async def test_rollback_on_error(db_session):
    """例外発生時にrollbackされることを確認"""
    # Arrange: エラーを発生させるモック
    with patch("app.crud.xxx.create", side_effect=Exception("DB Error")):
        # Act & Assert
        with pytest.raises(Exception):
            await some_service.some_method(db=db_session, ...)

    # Verify: DBにデータが残っていないことを確認
    result = await db_session.execute(select(SomeModel))
    assert result.scalars().all() == []
```

### API層 commitテストのテンプレート

```python
# tests/services/test_auth_service.py
async def test_register_admin_commits(db_session):
    """register_adminがDBにcommitされることを確認"""
    # Act
    result = await auth_service.register_admin(db=db_session, staff_in=...)

    # Assert: データがDBに保存されていることを確認
    saved = await db_session.execute(select(Staff).where(Staff.email == ...))
    assert saved.scalar_one_or_none() is not None
```

### import違反修正パターン

```python
# ❌ 修正前
from app.crud.crud_inquiry import crud_inquiry

# ✅ 修正後
from app import crud
# 使用箇所: crud_inquiry.xxx() → crud.inquiry.xxx()
```

---

**作成日**: 2026-02-20
**担当**: 未割当
**最終更新**: 2026-02-23（1-1/1-2 完全完了、3-A-4 完了）
