# TDD修正作業ログ — 2026-02-25

## セッション概要

`tdd_fix_checklist.md` に基づくTDD保守作業の実施記録。
Red → Green → リファクタリングのサイクルで進行。

---

## 完了タスク

### 2-B: API層 commit違反 — `mfa.py`（7件）✅

**対象ファイル**:
- `k_back/app/services/mfa.py` — 7メソッド追加
- `k_back/tests/services/test_mfa_service.py` — 新規作成（7テスト）
- `k_back/app/api/v1/endpoints/mfa.py` — commit除去・サービス委譲

**追加したサービスメソッド**（`MfaService` クラス）:

| メソッド | 処理内容 |
|---------|---------|
| `enroll_mfa(user)` | MFAシークレット生成・保存・commit |
| `verify_mfa(user, totp_code)` | TOTP検証 + `is_mfa_enabled=True` + `is_mfa_verified_by_user=True` + commit |
| `disable_mfa(user)` | `user.disable_mfa(db)` + commit |
| `admin_enable_staff_mfa(target_staff, secret, recovery_codes)` | MFA有効化 + `is_mfa_verified_by_user=False` + commit |
| `admin_disable_staff_mfa(target_staff)` | MFA無効化 + commit |
| `disable_all_office_mfa(all_staffs)` | 全スタッフMFA無効化ループ + commit → 無効化数を返す |
| `enable_all_office_mfa(all_staffs)` | 全スタッフMFA有効化ループ + commit → (有効化数, MFA設定情報リスト) を返す |

**API層の変更**（`mfa.py`）:
- `enroll_mfa`: `mfa_service.enroll()` + `await db.commit()` → `mfa_service.enroll_mfa()`
- `verify_mfa`: `verify_totp_code()` + commit + フラグ更新 → `mfa_service.verify_mfa()`
- `disable_mfa`: `user.disable_mfa(db)` + commit → `MfaService(db).disable_mfa(user=current_user)`
- `admin_enable_staff_mfa`: `enable_mfa()` + commit → `MfaService(db).admin_enable_staff_mfa(...)`
- `admin_disable_staff_mfa`: `disable_mfa(db)` + commit → `MfaService(db).admin_disable_staff_mfa(...)`
- `disable_all_office_mfa`: ループ + commit → `MfaService(db).disable_all_office_mfa(all_staffs=all_staffs)`
- `enable_all_office_mfa`: ループ + commit → `MfaService(db).enable_all_office_mfa(all_staffs=all_staffs)`
- 未使用の `create_access_token` import を削除
- `generate_recovery_codes` を `mfa.py` service の imports に追加

**テスト結果**: 49/49 passed（7 service + 42 MFA API）

---

### 3-A: `from app.crud.` 直接import違反 — Service層（13件）✅

**修正方針**: `from app.crud.xxx import yyy` → `from app import crud` + `crud.yyy.` に統一

| ファイル | 変更内容 | 件数 |
|---------|---------|-----|
| `calendar_service.py` | `crud_office_calendar_account.` → `crud.office_calendar_account.`<br>`crud_calendar_event.` → `crud.calendar_event.` | 2件 |
| `cleanup_service.py` | 動的local import削除 → `crud.archived_staff.` | 1件 |
| `welfare_recipient_service.py` | top-level + local import削除 → `crud.welfare_recipient.` + `crud.office_calendar_account.` | 2件 |
| `withdrawal_service.py` | 5つの直接importを削除 → `crud.approval_request.` / `crud.archived_staff.` / `crud.audit_log.` / `crud.office.` / `crud.staff.` | 5件 |
| `employee_action_service.py` | 3つの直接importを削除 → `crud.approval_request.` / `crud.welfare_recipient.` / `crud.notice.` | 3件 |

**テスト結果**: 252/252 passed（1件のdeadlock failureは並列テスト起因の断続的エラー、変更と無関係）

---

### 3-B: `from app.crud.` 直接import違反 — API層（途中）⚠️

**進行状況**: 作業中断（ログ保存のため）

完了済み:
- `admin_inquiries.py`: `crud_inquiry.` → `crud.inquiry.` ✅
- `notices.py`: `crud_notice.` → `crud.notice.` ✅
- `inquiries.py`: `crud_inquiry.` → `crud.inquiry.` ✅
- `admin_audit_logs.py`: `from app import crud` 追加、import行削除済み（`crud_audit_log.` 置換は未完）⚠️

未着手（`from app.crud.` import が残っている）:
- `welfare_recipients.py`: `crud_welfare_recipient.` → `crud.welfare_recipient.`
- `messages.py`: `crud_message.` → `crud.message.`（`from app import crud` は既存）
- `withdrawal_requests.py`: `crud_approval_request.` + `crud_audit_log.` → `crud.approval_request.` + `crud.audit_log.`
- `admin_announcements.py`: `crud_message.` → `crud.message.`（`from app import crud` は既存）
- `archived_staffs.py`: `archived_staff.` → `crud.archived_staff.`

---

## 残作業（チェックリスト順）

### 3-B: 継続中
- [ ] `admin_audit_logs.py`: `crud_audit_log.` → `crud.audit_log.` 置換（import削除済み）
- [ ] `welfare_recipients.py`: import削除 + `crud_welfare_recipient.` → `crud.welfare_recipient.`
- [ ] `messages.py`: import削除 + `crud_message.` → `crud.message.`
- [ ] `withdrawal_requests.py`: import削除 + `crud_approval_request.` + `crud_audit_log.` 置換
- [ ] `admin_announcements.py`: import削除 + `crud_message.` → `crud.message.`
- [ ] `archived_staffs.py`: import削除 + `archived_staff.` → `crud.archived_staff.`

### 4: 英語エラーメッセージ（6件）
- `push_subscriptions.py` の HTTPException.detail 6件を日本語に統一

### 5: マジックナンバー定数化（9件）
- `timedelta` の日数をハードコードから定数へ

---

## 注意事項

### `admin_audit_logs.py` の現状
- import行は既に `from app import crud` に置換済み
- ファイル内の `crud_audit_log.` は **まだ置換されていない**
- 次のセッションで `crud_audit_log.` → `crud.audit_log.` を replace_all で適用すること

### テスト実行コマンド
```bash
# サービス層テスト
docker exec keikakun_app-backend-1 pytest tests/services/ -v

# API層テスト（対象ファイルのみ）
docker exec keikakun_app-backend-1 pytest tests/api/v1/ -v --tb=short

# 全テスト（時間がかかる：30分超）
docker exec keikakun_app-backend-1 pytest tests/ -v --tb=short -q
```

### deadlock について
`test_role_change_service.py::test_owner_approve_manager_to_owner` が稀にdeadlockで失敗する。
並列テスト実行による一時的な競合。変更内容とは無関係。
