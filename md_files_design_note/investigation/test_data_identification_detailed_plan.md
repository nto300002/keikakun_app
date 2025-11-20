# テストデータ識別戦略の詳細実装計画

## 問題の概要

### 現在の問題
1. テスト実行時に、テストデータ以外のofficesデータも削除される
2. 本番環境でも同じ問題が発生している
3. 命名規則ベースの識別は脆弱で誤削除のリスクがある

### 根本原因
現在の`SafeTestDataCleanup`は命名規則（名前に「テスト」を含む等）でテストデータを識別しているため:
- 本番環境で「テスト」を含む正規データが削除される可能性
- 命名規則に従わないテストデータは削除されない
- TEST_DATABASE_URLのチェックにより本番環境では動作しない

### 関連ファイル
- `/k_back/tests/utils/safe_cleanup.py:51-312` - 現在のクリーンアップ実装
- `/k_back/tests/conftest.py:266-750` - Factory関数群
- `/k_back/app/models/` - 対象モデル定義

---

## 提案する解決策

### アプローチ: メタデータフラグによる識別

各テーブルに `is_test_data` カラム (Boolean) を追加し、ファクトリ関数で生成されるデータには必ず `is_test_data=True` を設定する。

### メリット
1. **確実な識別**: 命名規則に依存せず、確実にテストデータを識別可能
2. **環境非依存**: 開発・ステージング・本番環境すべてで同じロジックが動作
3. **監査可能**: クエリで簡単にテストデータの存在を確認可能
4. **段階的削除**: フラグベースで削除優先度を制御可能

### デメリットと対策
- **マイグレーション必須**: 既存環境への適用に注意が必要
  - 対策: デフォルト値 `False` で追加し、既存データには影響なし
- **Factory関数の更新**: すべてのFactory関数で設定が必要
  - 対策: 基底Factory関数を作成し、継承で強制

---

## 実装詳細

### Phase 0: 対象テーブルの完全リスト

#### 必須 (MUST) - 常にテストで作成される: 19テーブル
1. `offices` - 事業所
2. `staffs` - スタッフ
3. `office_staffs` - 事業所-スタッフ中間テーブル
4. `welfare_recipients` - 福祉受給者
5. `office_welfare_recipients` - 事業所-福祉受給者中間テーブル
6. `support_plan_cycles` - 支援計画サイクル
7. `support_plan_statuses` - 支援計画ステータス
8. `calendar_event_series` - カレンダー繰り返しイベント
9. `calendar_event_instances` - カレンダーイベントインスタンス
10. `notices` - 通知
11. `role_change_requests` - ロール変更リクエスト
12. `employee_action_requests` - 従業員アクションリクエスト
13. `service_recipient_details` - 受給者詳細情報
14. `disability_statuses` - 障害ステータス
15. `disability_details` - 障害詳細
16. `family_of_service_recipients` - 家族構成
17. `medical_matters` - 医療情報
18. `employment_related` - 雇用関連情報
19. `issue_analyses` - 課題分析

#### オプション (OPTIONAL) - 頻度は低いが追加推奨: 5テーブル
20. `calendar_events` - カレンダーイベント（レガシー）
21. `plan_deliverables` - 計画成果物
22. `emergency_contacts` - 緊急連絡先
23. `welfare_services_used` - 利用済み福祉サービス履歴
24. `history_of_hospital_visits` - 病院訪問履歴

#### 追加しない - システム全体で共有またはセキュリティ関連: 8テーブル以上
- `notification_patterns` - システムデフォルトのテンプレート
- `office_calendar_accounts` - カレンダー連携アカウント
- `staff_calendar_accounts` - スタッフカレンダー連携
- `mfa_backup_codes` - MFAバックアップコード
- `mfa_audit_logs` - MFA監査ログ
- `terms_agreements` - 利用規約同意
- `email_change_requests` - メールアドレス変更リクエスト
- `password_histories` - パスワード履歴
- `audit_logs` - 監査ログ

---

### Phase 1: データベーススキーマ変更

#### 対象テーブル
**必須19テーブル + オプション5テーブル = 合計24テーブル** に `is_test_data` カラムを追加

#### マイグレーションスクリプト（完全版）

```python
"""Add is_test_data flag to all test-related tables

Revision ID: xxxxx
Revises: (latest)
Create Date: 2025-xx-xx
"""
from alembic import op
import sqlalchemy as sa


def upgrade() -> None:
    """すべての対象テーブルに is_test_data カラムとインデックスを追加"""

    # 必須テーブル群 (19テーブル)
    tables = [
        'offices',
        'staffs',
        'office_staffs',
        'welfare_recipients',
        'office_welfare_recipients',
        'support_plan_cycles',
        'support_plan_statuses',
        'calendar_event_series',
        'calendar_event_instances',
        'notices',
        'role_change_requests',
        'employee_action_requests',
        'service_recipient_details',
        'disability_statuses',
        'disability_details',
        'family_of_service_recipients',
        'medical_matters',
        'employment_related',
        'issue_analyses',
    ]

    # オプションテーブル群 (5テーブル)
    optional_tables = [
        'calendar_events',
        'plan_deliverables',
        'emergency_contacts',
        'welfare_services_used',
        'history_of_hospital_visits',
    ]

    # 全テーブルに対して is_test_data カラムとインデックスを追加
    all_tables = tables + optional_tables

    for table_name in all_tables:
        op.add_column(
            table_name,
            sa.Column('is_test_data', sa.Boolean(),
                     nullable=False, server_default='false')
        )
        op.create_index(
            f'idx_{table_name}_is_test_data',
            table_name,
            ['is_test_data']
        )


def downgrade() -> None:
    """すべてのインデックスとカラムを削除"""

    all_tables = [
        'offices', 'staffs', 'office_staffs', 'welfare_recipients',
        'office_welfare_recipients', 'support_plan_cycles',
        'support_plan_statuses', 'calendar_event_series',
        'calendar_event_instances', 'notices', 'role_change_requests',
        'employee_action_requests', 'service_recipient_details',
        'disability_statuses', 'disability_details',
        'family_of_service_recipients', 'medical_matters',
        'employment_related', 'issue_analyses', 'calendar_events',
        'plan_deliverables', 'emergency_contacts',
        'welfare_services_used', 'history_of_hospital_visits',
    ]

    for table_name in all_tables:
        op.drop_index(f'idx_{table_name}_is_test_data')
        op.drop_column(table_name, 'is_test_data')
```

#### モデル定義の更新（全24モデル）

各モデルに以下のフィールドを追加:

```python
# すべてのモデルに共通で追加するフィールド
is_test_data: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False, index=True)
```

**更新が必要なモデルファイル一覧:**

1. `app/models/office.py`
   - `Office` クラス
   - `OfficeStaff` クラス

2. `app/models/staff.py`
   - `Staff` クラス

3. `app/models/welfare_recipient.py`
   - `WelfareRecipient` クラス
   - `OfficeWelfareRecipient` クラス
   - `ServiceRecipientDetail` クラス
   - `EmergencyContact` クラス（オプション）
   - `DisabilityStatus` クラス
   - `DisabilityDetail` クラス

4. `app/models/notice.py`
   - `Notice` クラス

5. `app/models/support_plan_cycle.py`
   - `SupportPlanCycle` クラス
   - `SupportPlanStatus` クラス
   - `PlanDeliverable` クラス（オプション）

6. `app/models/calendar_events.py`
   - `CalendarEvent` クラス（オプション）
   - `CalendarEventSeries` クラス
   - `CalendarEventInstance` クラス

7. `app/models/role_change_request.py`
   - `RoleChangeRequest` クラス

8. `app/models/employee_action_request.py`
   - `EmployeeActionRequest` クラス

9. `app/models/assessment.py`
   - `FamilyOfServiceRecipients` クラス
   - `WelfareServicesUsed` クラス（オプション）
   - `MedicalMatters` クラス
   - `HistoryOfHospitalVisits` クラス（オプション）
   - `EmploymentRelated` クラス
   - `IssueAnalysis` クラス

**実装例:**

```python
# app/models/office.py
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy import Boolean

class Office(Base):
    __tablename__ = "offices"

    # ... 既存フィールド

    # 新規追加
    is_test_data: Mapped[bool] = mapped_column(
        Boolean,
        default=False,
        nullable=False,
        index=True,
        comment="テストデータフラグ。Factory関数で生成されたデータはTrue"
    )


class OfficeStaff(Base):
    __tablename__ = "office_staffs"

    # ... 既存フィールド

    # 新規追加
    is_test_data: Mapped[bool] = mapped_column(
        Boolean,
        default=False,
        nullable=False,
        index=True
    )


# 他のすべてのモデルも同様のパターンで追加
```

---

### Phase 2: Factory関数の更新

#### conftest.py の全Factory関数を更新

各Factory関数に `is_test_data=True` パラメータを追加:

```python
# tests/conftest.py

async def service_admin_user_factory(
    db_session: AsyncSession,
    name: Optional[str] = None,
    # ... 既存パラメータ
    is_test_data: bool = True,  # 新規追加
) -> Staff:
    # ... 既存処理
    user = Staff(
        email=email,
        # ... 既存フィールド
        is_test_data=is_test_data,  # 新規追加
    )
    # ... 残りの処理

async def office_factory(
    db_session: AsyncSession,
    creator: Optional[Staff] = None,
    # ... 既存パラメータ
    is_test_data: bool = True,  # 新規追加
) -> Office:
    # ... 既存処理
    office = Office(
        name=office_name,
        # ... 既存フィールド
        is_test_data=is_test_data,  # 新規追加
    )
    # ... 残りの処理

# 同様に以下のFactory関数も更新:
# - employee_user_factory
# - manager_user_factory
# - owner_user_factory
# - staff_factory
# - welfare_recipient_factory
# - その他すべてのFactory関数
```

---

### Phase 3: SafeTestDataCleanup の改修

#### 新しいクリーンアップロジック（全24テーブル対応）

```python
# tests/utils/safe_cleanup.py

class SafeTestDataCleanup:
    """is_test_data フラグベースのテストデータ削除 - 全24テーブル対応"""

    @staticmethod
    async def delete_test_data(db: AsyncSession) -> Dict[str, int]:
        """
        is_test_data=True のデータのみを削除

        環境を問わず安全に動作する
        削除順序は外部キー制約を考慮して設計
        """
        result = {}

        try:
            # ========================================
            # STEP 1: テストデータのIDを収集
            # ========================================

            # テスト事業所のIDを取得
            office_ids_query = text("SELECT id FROM offices WHERE is_test_data = true")
            test_office_ids = [row[0] for row in (await db.execute(office_ids_query)).fetchall()]

            # テストスタッフのIDを取得
            staff_ids_query = text("SELECT id FROM staffs WHERE is_test_data = true")
            test_staff_ids = [row[0] for row in (await db.execute(staff_ids_query)).fetchall()]

            # テスト福祉受給者のIDを取得
            welfare_ids_query = text("SELECT id FROM welfare_recipients WHERE is_test_data = true")
            test_welfare_ids = [row[0] for row in (await db.execute(welfare_ids_query)).fetchall()]

            # ========================================
            # STEP 2: 子テーブルの削除（外部キー制約順）
            # ========================================

            # 2-1. 最下層: 履歴・詳細データ（オプション）
            if test_welfare_ids:
                r = await db.execute(text("DELETE FROM history_of_hospital_visits WHERE is_test_data = true"))
                if r.rowcount > 0: result["history_of_hospital_visits"] = r.rowcount

                r = await db.execute(text("DELETE FROM welfare_services_used WHERE is_test_data = true"))
                if r.rowcount > 0: result["welfare_services_used"] = r.rowcount

                r = await db.execute(text("DELETE FROM emergency_contacts WHERE is_test_data = true"))
                if r.rowcount > 0: result["emergency_contacts"] = r.rowcount

            # 2-2. 中層: アセスメントデータ
            for table in ["issue_analyses", "employment_related", "medical_matters",
                         "family_of_service_recipients", "disability_details", "disability_statuses",
                         "service_recipient_details"]:
                r = await db.execute(text(f"DELETE FROM {table} WHERE is_test_data = true"))
                if r.rowcount > 0:
                    result[table] = r.rowcount

            # 2-3. 支援計画関連
            for table in ["plan_deliverables", "support_plan_statuses", "support_plan_cycles"]:
                r = await db.execute(text(f"DELETE FROM {table} WHERE is_test_data = true"))
                if r.rowcount > 0:
                    result[table] = r.rowcount

            # 2-4. カレンダー関連
            for table in ["calendar_event_instances", "calendar_event_series", "calendar_events"]:
                r = await db.execute(text(f"DELETE FROM {table} WHERE is_test_data = true"))
                if r.rowcount > 0:
                    result[table] = r.rowcount

            # 2-5. リクエスト・通知
            for table in ["employee_action_requests", "role_change_requests", "notices"]:
                r = await db.execute(text(f"DELETE FROM {table} WHERE is_test_data = true"))
                if r.rowcount > 0:
                    result[table] = r.rowcount

            # ========================================
            # STEP 3: 中間テーブルの削除
            # ========================================
            for table in ["office_welfare_recipients", "office_staffs"]:
                r = await db.execute(text(f"DELETE FROM {table} WHERE is_test_data = true"))
                if r.rowcount > 0:
                    result[table] = r.rowcount

            # ========================================
            # STEP 4: 親テーブルの削除（created_by対策あり）
            # ========================================

            # 4-1. スタッフ削除前の created_by/last_modified_by 再割当
            if test_staff_ids:
                replacement_query = text("""
                    SELECT s.id FROM staffs s
                    WHERE s.role = 'owner'
                      AND s.is_test_data = false
                    LIMIT 1
                """)
                replacement = (await db.execute(replacement_query)).fetchone()

                if replacement:
                    replacement_id = replacement[0]
                    # テストデータでないofficeのcreated_by/last_modified_byを再割当
                    await db.execute(text("""
                        UPDATE offices
                        SET created_by = :rid
                        WHERE created_by = ANY(:sids) AND is_test_data = false
                    """), {"rid": replacement_id, "sids": test_staff_ids})

                    await db.execute(text("""
                        UPDATE offices
                        SET last_modified_by = :rid
                        WHERE last_modified_by = ANY(:sids) AND is_test_data = false
                    """), {"rid": replacement_id, "sids": test_staff_ids})

            # 4-2. 親テーブル削除
            for table in ["welfare_recipients", "staffs", "offices"]:
                r = await db.execute(text(f"DELETE FROM {table} WHERE is_test_data = true"))
                if r.rowcount > 0:
                    result[table] = r.rowcount

            await db.commit()

            if result:
                total = sum(result.values())
                logger.info(f"🧹 Cleaned up {total} test data records (is_test_data=true)")
            else:
                logger.debug("✓ No test data found (is_test_data=true)")

        except Exception as e:
            await db.rollback()
            logger.error(f"Error during test data cleanup: {e}")
            raise

        return result
```

---

### Phase 4: 既存テストデータの移行

開発・ステージング環境の既存テストデータに `is_test_data=True` を設定するマイグレーションスクリプト（全24テーブル対応）:

```python
# 一時的な移行スクリプト: scripts/migrate_existing_test_data.py

import asyncio
from sqlalchemy import text
from app.db.session import AsyncSessionLocal

async def migrate_existing_test_data():
    """既存のテストデータに is_test_data=True を設定（全24テーブル対応）"""
    async with AsyncSessionLocal() as db:
        try:
            print("🔄 既存テストデータの移行を開始...")

            # ========================================
            # ステップ1: 親テーブルの識別
            # ========================================

            # Offices - 命名規則で識別
            result = await db.execute(text("""
                UPDATE offices
                SET is_test_data = true
                WHERE (name LIKE '%テスト事業所%'
                   OR name LIKE '%test%'
                   OR name LIKE '%Test%')
                AND is_test_data = false
            """))
            print(f"  ✓ Offices: {result.rowcount}件")

            # Staffs - メールアドレスと名前で識別
            result = await db.execute(text("""
                UPDATE staffs
                SET is_test_data = true
                WHERE (email LIKE '%@test.com'
                   OR email LIKE '%@example.com'
                   OR last_name LIKE '%テスト%'
                   OR full_name LIKE '%テスト%')
                AND is_test_data = false
            """))
            print(f"  ✓ Staffs: {result.rowcount}件")

            # Welfare Recipients - 名前で識別
            result = await db.execute(text("""
                UPDATE welfare_recipients
                SET is_test_data = true
                WHERE (first_name LIKE '%テスト%'
                   OR last_name LIKE '%テスト%'
                   OR first_name LIKE '%test%'
                   OR last_name LIKE '%test%'
                   OR first_name LIKE '%部分修復%'
                   OR last_name LIKE '%部分修復%'
                   OR first_name LIKE '%修復対象%'
                   OR last_name LIKE '%修復対象%'
                   OR first_name LIKE '%エラー%'
                   OR last_name LIKE '%エラー%'
                   OR first_name LIKE '%新規%'
                   OR last_name LIKE '%新規%'
                   OR first_name LIKE '%更新後%'
                   OR last_name LIKE '%更新後%')
                AND is_test_data = false
            """))
            print(f"  ✓ Welfare Recipients: {result.rowcount}件")

            # ========================================
            # ステップ2: 中間テーブルの移行
            # ========================================

            # Office_Staffs - テストofficeまたはテストstaffに関連
            result = await db.execute(text("""
                UPDATE office_staffs
                SET is_test_data = true
                WHERE (office_id IN (SELECT id FROM offices WHERE is_test_data = true)
                   OR staff_id IN (SELECT id FROM staffs WHERE is_test_data = true))
                AND is_test_data = false
            """))
            print(f"  ✓ Office_Staffs: {result.rowcount}件")

            # Office_Welfare_Recipients - テストofficeまたはテスト受給者に関連
            result = await db.execute(text("""
                UPDATE office_welfare_recipients
                SET is_test_data = true
                WHERE (office_id IN (SELECT id FROM offices WHERE is_test_data = true)
                   OR welfare_recipient_id IN (SELECT id FROM welfare_recipients WHERE is_test_data = true))
                AND is_test_data = false
            """))
            print(f"  ✓ Office_Welfare_Recipients: {result.rowcount}件")

            # ========================================
            # ステップ3: 子テーブルの移行（関連性に基づく）
            # ========================================

            # 支援計画関連
            for table in ["support_plan_cycles", "support_plan_statuses", "plan_deliverables"]:
                result = await db.execute(text(f"""
                    UPDATE {table}
                    SET is_test_data = true
                    WHERE office_id IN (SELECT id FROM offices WHERE is_test_data = true)
                    AND is_test_data = false
                """))
                print(f"  ✓ {table}: {result.rowcount}件")

            # カレンダー関連
            for table in ["calendar_events", "calendar_event_series", "calendar_event_instances"]:
                result = await db.execute(text(f"""
                    UPDATE {table}
                    SET is_test_data = true
                    WHERE office_id IN (SELECT id FROM offices WHERE is_test_data = true)
                    AND is_test_data = false
                """))
                print(f"  ✓ {table}: {result.rowcount}件")

            # 通知・リクエスト
            result = await db.execute(text("""
                UPDATE notices
                SET is_test_data = true
                WHERE (office_id IN (SELECT id FROM offices WHERE is_test_data = true)
                   OR recipient_staff_id IN (SELECT id FROM staffs WHERE is_test_data = true))
                AND is_test_data = false
            """))
            print(f"  ✓ Notices: {result.rowcount}件")

            result = await db.execute(text("""
                UPDATE role_change_requests
                SET is_test_data = true
                WHERE office_id IN (SELECT id FROM offices WHERE is_test_data = true)
                AND is_test_data = false
            """))
            print(f"  ✓ Role_Change_Requests: {result.rowcount}件")

            result = await db.execute(text("""
                UPDATE employee_action_requests
                SET is_test_data = true
                WHERE office_id IN (SELECT id FROM offices WHERE is_test_data = true)
                AND is_test_data = false
            """))
            print(f"  ✓ Employee_Action_Requests: {result.rowcount}件")

            # アセスメント関連（受給者に紐づく）
            assessment_tables = [
                "service_recipient_details", "disability_statuses", "disability_details",
                "family_of_service_recipients", "medical_matters", "employment_related",
                "issue_analyses", "emergency_contacts", "welfare_services_used",
                "history_of_hospital_visits"
            ]
            for table in assessment_tables:
                result = await db.execute(text(f"""
                    UPDATE {table}
                    SET is_test_data = true
                    WHERE welfare_recipient_id IN (SELECT id FROM welfare_recipients WHERE is_test_data = true)
                    AND is_test_data = false
                """))
                if result.rowcount > 0:
                    print(f"  ✓ {table}: {result.rowcount}件")

            await db.commit()
            print("✅ 既存テストデータの移行完了")

        except Exception as e:
            await db.rollback()
            print(f"❌ 移行エラー: {e}")
            raise

if __name__ == "__main__":
    asyncio.run(migrate_existing_test_data())
```

---

### Phase 5: テストの追加

#### is_test_data フラグの動作確認テスト

```python
# tests/test_safe_cleanup_with_flag.py

import pytest
from sqlalchemy import select, text
from app.models import Office, Staff, WelfareRecipient, Notice
from tests.utils.safe_cleanup import SafeTestDataCleanup

@pytest.mark.asyncio
async def test_delete_only_test_data(db_session, office_factory, staff_factory):
    """is_test_data=True のデータのみが削除されることを確認"""

    # テストデータを作成 (is_test_data=True)
    test_office = await office_factory(db_session, is_test_data=True)
    test_staff = await staff_factory(db_session, office_id=test_office.id, is_test_data=True)

    # 本番データを作成 (is_test_data=False)
    prod_office = await office_factory(db_session, name="本番事業所", is_test_data=False)
    prod_staff = await staff_factory(
        db_session,
        office_id=prod_office.id,
        email="real@production.com",
        is_test_data=False
    )

    await db_session.flush()

    # クリーンアップ実行
    result = await SafeTestDataCleanup.delete_test_data(db_session)

    # テストデータが削除されていることを確認
    test_office_exists = await db_session.execute(
        select(Office).where(Office.id == test_office.id)
    )
    assert test_office_exists.scalar_one_or_none() is None

    test_staff_exists = await db_session.execute(
        select(Staff).where(Staff.id == test_staff.id)
    )
    assert test_staff_exists.scalar_one_or_none() is None

    # 本番データが残っていることを確認
    prod_office_exists = await db_session.execute(
        select(Office).where(Office.id == prod_office.id)
    )
    assert prod_office_exists.scalar_one_or_none() is not None

    prod_staff_exists = await db_session.execute(
        select(Staff).where(Staff.id == prod_staff.id)
    )
    assert prod_staff_exists.scalar_one_or_none() is not None


@pytest.mark.asyncio
async def test_cleanup_with_cascade_relationships(db_session, office_factory, welfare_recipient_factory):
    """CASCADE削除の関係があるデータでも正しく動作することを確認"""

    # テスト事業所と福祉受給者を作成
    test_office = await office_factory(db_session, is_test_data=True)
    test_recipient = await welfare_recipient_factory(
        db_session,
        office_id=test_office.id,
        is_test_data=True
    )

    await db_session.flush()

    # クリーンアップ実行
    result = await SafeTestDataCleanup.delete_test_data(db_session)

    # 両方とも削除されていることを確認
    office_exists = await db_session.execute(
        select(Office).where(Office.id == test_office.id)
    )
    assert office_exists.scalar_one_or_none() is None

    recipient_exists = await db_session.execute(
        select(WelfareRecipient).where(WelfareRecipient.id == test_recipient.id)
    )
    assert recipient_exists.scalar_one_or_none() is None


@pytest.mark.asyncio
async def test_no_production_data_deleted(db_session, office_factory):
    """本番データ(is_test_data=False)が削除されないことを確認"""

    # 本番データを複数作成
    prod_offices = []
    for i in range(5):
        office = await office_factory(
            db_session,
            name=f"本番事業所{i}",
            is_test_data=False
        )
        prod_offices.append(office)

    await db_session.flush()

    # 作成前の本番データ数を記録
    count_before = await db_session.execute(
        select(Office).where(Office.is_test_data == False)
    )
    count_before_num = len(count_before.scalars().all())

    # クリーンアップ実行
    result = await SafeTestDataCleanup.delete_test_data(db_session)

    # 本番データの数が変わっていないことを確認
    count_after = await db_session.execute(
        select(Office).where(Office.is_test_data == False)
    )
    count_after_num = len(count_after.scalars().all())

    assert count_before_num == count_after_num
```

---

## CASCADE削除のリスクと対策

### 主要なCASCADE削除の関係

1. **Office.created_by → Staff (CASCADE)**
   - Staffを削除すると、そのStaffが作成したOfficeも削除される
   - 対策: created_by を別のStaffに再割当してから削除

2. **Office.last_modified_by → Staff (CASCADE)**
   - Staffを削除すると、そのStaffが最終更新したOfficeも削除される
   - 対策: last_modified_by を別のStaffに再割当してから削除

3. **Notice.recipient_staff_id → Staff (CASCADE)**
   - Staffを削除すると、そのStaffへの通知が削除される
   - 対策: 通知は削除されてもOK（テストデータの通知は削除される）

4. **Notice.office_id → Office (CASCADE)**
   - Officeを削除すると、そのOfficeの通知が削除される
   - 対策: 通知は削除されてもOK（テストデータの通知は削除される）

### 実装での対策

SafeTestDataCleanupの実装では:
1. 本番データ（is_test_data=False）のOfficeに対してのみ、created_by/last_modified_by を再割当
2. テストデータのOfficeは再割当せずに削除
3. 削除順序を制御して、外部キー制約違反を回避

---

## ロールアウト計画

### ステージ1: 開発環境（1週間）
1. マイグレーション実行
2. Factory関数の更新
3. SafeTestDataCleanup の改修
4. 既存テストデータの移行スクリプト実行
5. 全テストの実行と確認

### ステージ2: ステージング環境（1週間）
1. 同様の手順でステージング環境に適用
2. 統合テストの実行
3. パフォーマンステスト（インデックスの効果確認）

### ステージ3: 本番環境（慎重に実施）
1. メンテナンス時間帯にマイグレーション実行
2. 既存テストデータの確認（本番環境にテストデータが存在する場合）
3. 移行スクリプト実行（必要な場合のみ）
4. 動作確認

---

## 検証項目

### 機能検証
- [ ] is_test_data=True のデータのみが削除される
- [ ] is_test_data=False のデータは削除されない
- [ ] CASCADE削除が正しく動作する
- [ ] created_by/last_modified_by の再割当が正しく動作する
- [ ] 既存のテストが全てパスする

### パフォーマンス検証
- [ ] インデックスにより削除クエリが高速化される
- [ ] マイグレーション実行時間が許容範囲内
- [ ] クリーンアップ処理時間が許容範囲内

### 安全性検証
- [ ] 本番環境で誤削除が発生しない
- [ ] 環境を問わず同じロジックで動作する
- [ ] ロールバック可能なマイグレーション

---

## 影響範囲

### 変更が必要なファイル（24テーブル対応版）

#### 1. マイグレーション
- `/k_back/migrations/versions/` - 新規マイグレーション（24テーブルすべてに is_test_data カラムとインデックスを追加）

#### 2. モデル定義（9ファイル、24クラス）
1. `/k_back/app/models/office.py` - Office, OfficeStaff
2. `/k_back/app/models/staff.py` - Staff
3. `/k_back/app/models/welfare_recipient.py` - WelfareRecipient, OfficeWelfareRecipient, ServiceRecipientDetail, DisabilityStatus, DisabilityDetail, EmergencyContact
4. `/k_back/app/models/notice.py` - Notice
5. `/k_back/app/models/support_plan_cycle.py` - SupportPlanCycle, SupportPlanStatus, PlanDeliverable
6. `/k_back/app/models/calendar_events.py` - CalendarEvent, CalendarEventSeries, CalendarEventInstance
7. `/k_back/app/models/role_change_request.py` - RoleChangeRequest
8. `/k_back/app/models/employee_action_request.py` - EmployeeActionRequest
9. `/k_back/app/models/assessment.py` - FamilyOfServiceRecipients, WelfareServicesUsed, MedicalMatters, HistoryOfHospitalVisits, EmploymentRelated, IssueAnalysis

#### 3. テスト関連
- `/k_back/tests/conftest.py` - 全Factory関数の更新（最低8個のFactory関数）
- `/k_back/tests/utils/safe_cleanup.py` - ロジックの改修（24テーブル対応）
- `/k_back/scripts/migrate_existing_test_data.py` - 新規スクリプト（24テーブル対応）
- `/k_back/tests/test_safe_cleanup_with_flag.py` - 新規テスト

### 影響を受ける可能性のあるテスト
- すべてのモデルテスト（Factory関数を使用しているもの）
- 統合テスト（複数モデルを使用しているもの）
- 支援計画関連のテスト
- カレンダー同期テスト
- アセスメント機能のテスト

### データベース影響
- **24テーブルにカラム追加**: 既存データへの影響なし（デフォルト値 false）
- **24個のインデックス追加**: クエリパフォーマンスへの影響は最小限
- **マイグレーション時間**: テーブルサイズによるが、通常数秒〜数分

---

## リスクと軽減策

### リスク1: マイグレーション失敗
- 確率: 低
- 影響: 高（データベースの整合性が失われる可能性）
- 軽減策:
  - ステージング環境で十分にテスト
  - ロールバックスクリプトを用意
  - メンテナンス時間帯に実施

### リスク2: 既存テストの破壊
- 確率: 中
- 影響: 中（テストが失敗する可能性）
- 軽減策:
  - Factory関数のデフォルト値で is_test_data=True を設定
  - 段階的にテストを実行して確認

### リスク3: パフォーマンス劣化
- 確率: 低
- 影響: 低（インデックスを追加するため）
- 軽減策:
  - インデックスを追加して高速化
  - パフォーマンステストを実施

---

## 今後の拡張性

### カバレッジ
この実装では **24テーブル** すべてに `is_test_data` フラグを追加しており、現在のシステムで必要なテストデータ管理は完全にカバーしています。

### 追加を検討しなかったテーブル
以下のテーブルには意図的に `is_test_data` を追加していません:
- **セキュリティ関連**: `mfa_backup_codes`, `mfa_audit_logs`, `password_histories`, `audit_logs`
- **システム全体共有**: `notification_patterns`（システムデフォルトのテンプレート）
- **連携アカウント**: `office_calendar_accounts`, `staff_calendar_accounts`（再作成コストが高い）
- **同意記録**: `terms_agreements`, `email_change_requests`（法的記録）

### 将来的な拡張案

#### 1. 段階的削除の実装
現在は単純に is_test_data=True のデータを削除していますが、将来的には以下のような拡張が考えられます:

```python
# 追加カラム案
test_data_priority: int  # 削除優先度（1=最初、2=次、など）
test_data_created_at: datetime  # テストデータ作成日時
test_data_expires_at: datetime  # 有効期限
```

#### 2. テストデータの自動有効期限
- 作成から N 日経過したテストデータを自動削除
- CI/CD パイプラインでの定期実行

#### 3. 新規テーブル追加時の対応
新しいテーブルを追加する際は:
1. テストで頻繁に作成されるか確認
2. 必要なら `is_test_data` カラムを追加
3. Factory関数で `is_test_data=True` を設定
4. `SafeTestDataCleanup` に削除ロジックを追加

---

## まとめ

### 実装の成果

この **24テーブル対応のis_test_dataフラグ実装** により:

1. **確実な識別**: 命名規則に依存せず、メタデータフラグで確実にテストデータを識別
2. **環境非依存**: 開発・ステージング・本番環境すべてで同じロジックが動作
3. **誤削除防止**: 本番データが「テスト」という名前を含んでいても安全
4. **監査可能性**: SQLクエリで簡単にテストデータの存在を確認可能
5. **完全なカバレッジ**: システム内の主要な24テーブルすべてに対応

### 技術的改善点

- **命名規則ベース** → **メタデータフラグベース** への移行
- **環境依存ロジック** → **環境非依存ロジック** への改善
- **部分的対応（4テーブル）** → **包括的対応（24テーブル）** への拡張
- **脆弱な識別** → **堅牢な識別** への進化

### 期待される効果

- テストデータの誤削除リスクが **大幅に低減**
- 本番環境でのテストデータ削除が **安全に実行可能**
- テストデータ管理の **保守性と信頼性が向上**
- 開発チーム全体の **テストデータに対する信頼度が向上**

---

## 参考: コードベース調査結果

この実装計画は、以下の包括的なコードベース調査に基づいています:
- **33モデル** の完全な分析
- **Factory関数** の使用パターン調査
- **CASCADE削除関係** のリスク分析
- **既存のクリーンアップメカニズム** の評価

調査により、24テーブルが **MUST** または **SHOULD** レベルで is_test_data フラグが必要であることが判明し、本実装計画ではこれらすべてをカバーしています。
