# アーキテクチャ違反 実態調査レポート

**調査日**: 2026-02-20
**調査対象**: `k_back/app/` 全体
**調査基準**: `issue_01` / `issue_02` / `issue_03` の定義に基づく

---

## サマリー

| Issue | 内容 | 違反件数 | 深刻度 |
|-------|------|---------|--------|
| #01 | API層の `await db.commit()` 違反 | **45件 / 17ファイル** | 🔴 Critical |
| #01 | API層の `from app.crud.` 直接import | **11件 / 10ファイル** | 🔴 Critical |
| #02 | Service層のcommit漏れ | **2ファイル** | 🔴 Critical |
| #02 | Service層のrollback欠如 | **3ファイル** | 🔴 Critical |
| #02 | Service層の `from app.crud.` 直接import | **16件 / 6ファイル** | 🟠 High |
| #02 | Service層の複数commit（分断トランザクション） | **6ファイル** | 🟠 High |
| #03 | 英語エラーメッセージ（HTTPException.detail） | **6件 / 1ファイル** | 🟠 High |
| #03 | マジックナンバー（timedelta ハードコード） | **9件** | 🟡 Medium |

---

## Issue #01: API層のcommit違反・import違反

### 1-A. `await db.commit()` 違反（計45件）

`CLAUDE.md` の原則: **API層はcommit禁止。commitはCRUD層またはService層の責務。**

| ファイル | 違反件数 | 優先度 |
|---------|---------|--------|
| `auths.py` | 7件 | 🔴 High |
| `mfa.py` | 7件 | 🔴 High |
| `messages.py` | 5件 | 🔴 High |
| `role_change_requests.py` | 4件 | 🔴 High |
| `calendar.py` | 4件 | 🟠 Medium |
| `withdrawal_requests.py` | 3件 | 🟠 Medium |
| `admin_inquiries.py` | 3件 | 🟠 Medium |
| `welfare_recipients.py` | 2件 | 🟠 Medium |
| `staffs.py` | 2件 | 🟠 Medium |
| `terms.py` | 1件 | 🟡 Low |
| `support_plans.py` | 1件 | 🟡 Low |
| `support_plan_statuses.py` | 1件 | 🟡 Low |
| `offices.py` | 1件 | 🟡 Low |
| `notices.py` | 1件 | 🟡 Low |
| `inquiries.py` | 1件 | 🟡 Low |
| `employee_action_requests.py` | 1件 | 🟡 Low |
| `admin_announcements.py` | 1件 | 🟡 Low |

**注**: issue_01作成時(2026-02-18)から**25件増加**（20件超 → 45件）。

### 1-B. `from app.crud.` 直接import違反（計11件 / 10ファイル）

`CLAUDE.md` の原則: **`from app import crud` を使うこと。個別CRUDのimportは循環依存を引き起こす。**

```
app/api/v1/endpoints/admin_inquiries.py   : from app.crud.crud_inquiry import crud_inquiry
app/api/v1/endpoints/notices.py           : from app.crud.crud_notice import crud_notice
app/api/v1/endpoints/inquiries.py         : from app.crud.crud_inquiry import crud_inquiry
app/api/v1/endpoints/admin_audit_logs.py  : from app.crud.crud_audit_log import audit_log ...
app/api/v1/endpoints/welfare_recipients.py: from app.crud.crud_welfare_recipient import ...
app/api/v1/endpoints/messages.py          : from app.crud.crud_message import crud_message
app/api/v1/endpoints/withdrawal_requests.py: from app.crud.crud_approval_request import ...（2件）
app/api/v1/endpoints/admin_announcements.py: from app.crud.crud_message import crud_message
app/api/v1/endpoints/archived_staffs.py  : from app.crud.crud_archived_staff import ...
```

---

## Issue #02: トランザクション境界の問題

### 2-A. Service層のcommit漏れ（2ファイル）

`await crud.xxx()` を呼んでいるが `await db.commit()` が存在しない。

| ファイル | 状況 |
|---------|------|
| `app/services/assessment_service.py` | `crud.family_member.create` / `crud.employment.upsert` 等を呼ぶがcommitなし。CRUD層内部でcommitしている前提の設計と思われるが、境界が不明確。 |
| `app/services/withdrawal_service.py` | commitが0件。withdrawal（退会）という重大な処理でcommit管理がService層に存在しない。 |

### 2-B. Service層のrollback欠如（3ファイル）

`await db.commit()` があるが `await db.rollback()` が存在しない。エラー時にデータ不整合が発生するリスクがある。

| ファイル | commitの件数 | 危険度 |
|---------|------------|--------|
| `app/services/role_change_service.py` | 3件 | 🔴 High（さらにtry-exceptも存在しない） |
| `app/services/staff_profile_service.py` | 4件 | 🔴 High |
| `app/services/support_plan_service.py` | 4件 | 🔴 High |

特に `role_change_service.py` は commit が3件ありながら try-except ブロックが存在しない。

### 2-C. Service層の `from app.crud.` 直接import違反（16件 / 6ファイル）

API層と同様、`from app import crud` を使うべきところを個別importしている。

```
app/services/calendar_service.py       : crud_office_calendar_account, crud_calendar_event（2件）
app/services/cleanup_service.py        : crud_archived_staff（動的import）
app/services/welfare_recipient_service.py: crud_welfare_recipient, crud_office_calendar_account（2件）
app/services/role_change_service.py    : approval_request, crud_staff, crud_notice（3件）
app/services/withdrawal_service.py     : crud_approval_request, crud_archived_staff, crud_audit_log, crud_office, crud_staff（5件）
app/services/employee_action_service.py: approval_request, crud_welfare_recipient, crud_notice（3件）
```

### 2-D. Service層の複数commit（分断トランザクション）（6ファイル）

1関数内での複数commitはアトミック性を破壊する。

| ファイル | commit件数 | 備考 |
|---------|----------|------|
| `app/services/billing_service.py` | 6件 | 決済処理で特に危険 |
| `app/services/support_plan_service.py` | 4件 | rollbackも欠如 |
| `app/services/staff_profile_service.py` | 4件 | rollbackも欠如 |
| `app/services/role_change_service.py` | 3件 | rollback欠如＋try-except欠如 |
| `app/services/employee_action_service.py` | 3件 | |
| `app/services/welfare_recipient_service.py` | 2件 | |

---

## Issue #03: 保守性の問題

### 3-A. 英語エラーメッセージ（6件 / 1ファイル）

`CLAUDE.md` の原則: **ユーザー向けメッセージは必ず日本語。**

全件が `push_subscriptions.py` に集中している。

```python
# app/api/v1/endpoints/push_subscriptions.py
L79:  detail="Failed to subscribe push notifications"      # ❌
L111: detail="Subscription not found"                      # ❌
L114: detail="Not authorized to delete this subscription"  # ❌
L119: detail="Subscription not found"                      # ❌
L132: detail="Failed to unsubscribe push notifications"    # ❌
L165: detail="Failed to retrieve subscriptions"            # ❌
```

### 3-B. マジックナンバー（9件）

ビジネスルールの数値がハードコードされており、定数化されていない。

| 数値 | 意味 | 件数 | 場所 |
|------|------|------|------|
| `timedelta(days=180)` | 個別支援計画の更新期限 | 5件 | `crud_welfare_recipient.py`, `welfare_recipient_service.py`(×2), `support_plan_service.py`(×2) |
| `timedelta(days=30)` | 期限切れ間近の閾値 | 3件 | `crud_dashboard.py`(×3) |
| `timedelta(days=365)` | 監査ログ保持期間 | 1件 | `crud_audit_log.py` |

`app/core/constants.py` または `app/core/config.py` への定数化が必要。

---

## 修正優先度マップ

```
優先度1（本番データ整合性リスク）
├── role_change_service.py: commit×3・rollbackなし・try-exceptなし
├── staff_profile_service.py: commit×4・rollbackなし
└── support_plan_service.py: commit×4・rollbackなし

優先度2（アーキテクチャ原則違反・早急に是正）
├── auths.py: API層commit×7
├── mfa.py: API層commit×7
├── withdrawal_service.py: commit漏れ
└── assessment_service.py: commit漏れ

優先度3（import違反・保守性）
├── services/: from app.crud.直接import 16件
├── api/endpoints/: from app.crud.直接import 11件
└── billing_service.py: commit×6（分断トランザクション）

優先度4（ユーザー影響・言語ルール）
└── push_subscriptions.py: 英語エラーメッセージ×6

優先度5（技術的負債）
└── マジックナンバー: timedelta ハードコード×9件
```

---

## 比較: issue_01作成時（2026-02-18）との差異

| 項目 | 2026-02-18時点（推定） | 2026-02-20調査結果 | 増減 |
|------|-------------------|-----------------|------|
| API層 commit違反 | 20件超 | **45件** | ↑25件 |
| 対象ファイル数 | 6ファイル | **17ファイル** | ↑11ファイル |

issue_01 作成後も新機能追加時に違反が継続して増加している。**issueの認識はあるが修正が追いついていない状態。**

---

## 推奨アクション

### 即時対応（優先度1）

`role_change_service.py` / `staff_profile_service.py` / `support_plan_service.py` に
try-except-rollback パターンを適用する。

```python
# 修正テンプレート
async def some_service_method(db: AsyncSession, ...):
    try:
        # 既存の処理（複数commitを1つに統合）
        ...
        await db.commit()  # ← 最後に1回のみ
        return result
    except Exception as e:
        await db.rollback()
        logger.error(f"処理に失敗しました: {e}")
        raise
```

### 短期対応（1〜2週間）

1. `push_subscriptions.py` の英語エラーメッセージを日本語化（30分）
2. `withdrawal_service.py` / `assessment_service.py` のcommit境界を明確化
3. `services/` の `from app.crud.` 直接importを `from app import crud` に統一

### 中期対応（〜1ヶ月）

1. API層のcommit違反を段階的にService層へ移管
   - `auths.py` → `auth_service.py` 作成
   - `mfa.py` → `mfa_service.py` 拡張
   - `messages.py` → `message_service.py` 作成
2. マジックナンバーを `app/core/constants.py` に定数化

---

**作成日**: 2026-02-20
**調査ツール**: grep, bash スクリプト
**次回調査予定**: 修正完了後
