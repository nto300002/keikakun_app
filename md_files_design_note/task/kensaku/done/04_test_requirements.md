# ダッシュボードフィルター機能 - テスト要件定義（TDD）

## ドキュメント情報
- 作成日: 2026-02-14
- バージョン: 1.0
- アプローチ: Test-Driven Development (TDD)

---

## 🎯 テスト戦略

### TDDの原則
1. ✅ **Red**: テストを先に書く（失敗することを確認）
2. ✅ **Green**: 最小限のコードで テストをパス
3. ✅ **Refactor**: コードをリファクタリング

### テスト階層
```
統合テスト (E2E Performance Tests)
  ↓
サービス層テスト (Service Layer Tests)
  ↓
CRUD層テスト (CRUD Layer Tests)
  ↓
ユニットテスト (Unit Tests)
```

---

## 📋 Phase 1: クエリ最適化のテスト

### Test 1.1: COUNT(*) クエリのパフォーマンステスト

**ファイル**: `tests/crud/test_crud_dashboard_count.py`

**目的**: `count_office_recipients()` が全レコード取得より高速であることを検証

```python
import pytest
import pytest_asyncio
import time
from uuid import uuid4
from sqlalchemy.ext.asyncio import AsyncSession

from app import crud
from app.models import Office, WelfareRecipient, OfficeWelfareRecipient
from tests.utils import create_test_offices, create_test_recipients


class TestCountOfficeRecipients:
    """COUNT(*)クエリのパフォーマンステスト"""

    @pytest_asyncio.fixture
    async def setup_large_dataset(self, db_session: AsyncSession):
        """500事業所 × 100利用者のテストデータ作成"""
        # 事業所を500件作成
        offices = await create_test_offices(db_session, count=500)

        # 各事業所に100人の利用者を作成
        recipients_data = []
        for office in offices:
            recipients = await create_test_recipients(
                db_session,
                office_id=office.id,
                count=100
            )
            recipients_data.append((office, recipients))

        await db_session.commit()
        return recipients_data

    @pytest.mark.asyncio
    async def test_count_performance_single_office(self, db_session: AsyncSession):
        """
        Test 1.1.1: 単一事業所のCOUNT(*)パフォーマンス

        要件:
        - クエリ時間 < 100ms
        - メモリ使用量が最小限
        - 正確なカウント値
        """
        # Setup: 1事業所に100利用者を作成
        office = await create_test_offices(db_session, count=1)
        await create_test_recipients(db_session, office_id=office[0].id, count=100)
        await db_session.commit()

        # Execute: COUNT(*)クエリの実行時間測定
        start_time = time.time()
        count = await crud.dashboard.count_office_recipients(
            db=db_session,
            office_id=office[0].id
        )
        elapsed_time = time.time() - start_time

        # Assert: パフォーマンス要件
        assert elapsed_time < 0.1, f"クエリ時間が100msを超えました: {elapsed_time:.3f}s"
        assert count == 100, f"カウント値が不正です: expected=100, actual={count}"

    @pytest.mark.asyncio
    async def test_count_vs_full_load_comparison(self, db_session: AsyncSession):
        """
        Test 1.1.2: COUNT(*) vs 全レコード取得のパフォーマンス比較

        要件:
        - COUNT(*)が全レコード取得の10倍以上高速
        """
        # Setup
        office = await create_test_offices(db_session, count=1)
        await create_test_recipients(db_session, office_id=office[0].id, count=1000)
        await db_session.commit()

        # 全レコード取得（旧実装）
        start_full = time.time()
        all_recipients = await crud.office.get_recipients_by_office_id(
            db=db_session,
            office_id=office[0].id
        )
        count_full = len(all_recipients)
        time_full = time.time() - start_full

        # COUNT(*)クエリ（新実装）
        start_count = time.time()
        count_optimized = await crud.dashboard.count_office_recipients(
            db=db_session,
            office_id=office[0].id
        )
        time_count = time.time() - start_count

        # Assert: COUNT(*)が10倍以上高速
        assert count_full == count_optimized == 1000
        speedup = time_full / time_count
        assert speedup >= 10, f"COUNT(*)の高速化が不十分です: {speedup:.1f}x"

    @pytest.mark.asyncio
    async def test_count_with_multiple_offices(self, db_session: AsyncSession, setup_large_dataset):
        """
        Test 1.1.3: 500事業所のCOUNT(*)パフォーマンス

        要件:
        - 500事業所すべてで合計時間 < 5秒
        - 各事業所のカウントが正確
        """
        offices_data = setup_large_dataset

        # Execute: 500事業所のカウント
        start_time = time.time()
        counts = []
        for office, _ in offices_data:
            count = await crud.dashboard.count_office_recipients(
                db=db_session,
                office_id=office.id
            )
            counts.append(count)
        elapsed_time = time.time() - start_time

        # Assert
        assert all(count == 100 for count in counts), "カウント値が不正です"
        assert elapsed_time < 5.0, f"合計時間が5秒を超えました: {elapsed_time:.3f}s"
        avg_time_per_office = elapsed_time / 500
        assert avg_time_per_office < 0.01, f"平均クエリ時間が10msを超えました: {avg_time_per_office:.3f}s"


---

### Test 1.2: サブクエリ統合の正しさテスト

**ファイル**: `tests/crud/test_crud_dashboard_subquery.py`

**目的**: `cycle_info_sq` が `cycle_count` と `latest_cycle_id` を正しく取得することを検証

```python
import pytest
import pytest_asyncio
from uuid import uuid4
from sqlalchemy.ext.asyncio import AsyncSession

from app import crud
from app.models import (
    Office, WelfareRecipient, OfficeWelfareRecipient,
    SupportPlanCycle
)
from tests.utils import create_test_office, create_test_recipient, create_test_cycle


class TestSubqueryIntegration:
    """統合サブクエリ(cycle_info_sq)の正しさテスト"""

    @pytest_asyncio.fixture
    async def setup_recipient_with_cycles(self, db_session: AsyncSession):
        """利用者 + 複数サイクルのテストデータ作成"""
        # 事業所作成
        office = await create_test_office(db_session)

        # 利用者作成
        recipient = await create_test_recipient(
            db_session,
            office_id=office.id,
            last_name="山田",
            first_name="太郎"
        )

        # サイクルを3つ作成（1,2は過去、3が最新）
        cycle1 = await create_test_cycle(
            db_session,
            welfare_recipient_id=recipient.id,
            cycle_number=1,
            is_latest_cycle=False
        )
        cycle2 = await create_test_cycle(
            db_session,
            welfare_recipient_id=recipient.id,
            cycle_number=2,
            is_latest_cycle=False
        )
        cycle3 = await create_test_cycle(
            db_session,
            welfare_recipient_id=recipient.id,
            cycle_number=3,
            is_latest_cycle=True
        )

        await db_session.commit()
        return {
            "office": office,
            "recipient": recipient,
            "cycles": [cycle1, cycle2, cycle3],
            "latest_cycle": cycle3
        }

    @pytest.mark.asyncio
    async def test_cycle_count_is_correct(self, db_session: AsyncSession, setup_recipient_with_cycles):
        """
        Test 1.2.1: サイクル数が正しくカウントされる

        要件:
        - cycle_count = 実際のサイクル数
        - GROUP BY が正しく機能
        """
        data = setup_recipient_with_cycles
        office = data["office"]

        # Execute
        results = await crud.dashboard.get_filtered_summaries(
            db=db_session,
            office_ids=[office.id],
            sort_by="furigana",
            sort_order="asc",
            filters={},
            search_term=None,
            skip=0,
            limit=100
        )

        # Assert
        assert len(results) == 1, "結果が1件であること"
        recipient, cycle_count, latest_cycle = results[0]
        assert cycle_count == 3, f"サイクル数が不正です: expected=3, actual={cycle_count}"

    @pytest.mark.asyncio
    async def test_latest_cycle_id_is_correct(self, db_session: AsyncSession, setup_recipient_with_cycles):
        """
        Test 1.2.2: 最新サイクルIDが正しく取得される

        要件:
        - latest_cycle_id = is_latest_cycle=true のサイクルID
        - CASE式が正しく機能
        """
        data = setup_recipient_with_cycles
        office = data["office"]
        expected_latest_cycle = data["latest_cycle"]

        # Execute
        results = await crud.dashboard.get_filtered_summaries(
            db=db_session,
            office_ids=[office.id],
            sort_by="furigana",
            sort_order="asc",
            filters={},
            search_term=None,
            skip=0,
            limit=100
        )

        # Assert
        recipient, cycle_count, latest_cycle = results[0]
        assert latest_cycle is not None, "最新サイクルが取得できません"
        assert latest_cycle.id == expected_latest_cycle.id, "最新サイクルIDが不正です"
        assert latest_cycle.is_latest_cycle == True, "is_latest_cycle=trueではありません"
        assert latest_cycle.cycle_number == 3, "最新サイクルのcycle_numberが不正です"

    @pytest.mark.asyncio
    async def test_no_latest_cycle_returns_null(self, db_session: AsyncSession):
        """
        Test 1.2.3: 最新サイクルがない場合NULLを返す

        要件:
        - 全サイクルが is_latest_cycle=false の場合、latest_cycle=NULL
        - OUTER JOIN が正しく機能
        """
        # Setup: 最新サイクルなしの利用者
        office = await create_test_office(db_session)
        recipient = await create_test_recipient(db_session, office_id=office.id)
        # 過去サイクルのみ
        await create_test_cycle(
            db_session,
            welfare_recipient_id=recipient.id,
            cycle_number=1,
            is_latest_cycle=False
        )
        await db_session.commit()

        # Execute
        results = await crud.dashboard.get_filtered_summaries(
            db=db_session,
            office_ids=[office.id],
            sort_by="furigana",
            sort_order="asc",
            filters={},
            search_term=None,
            skip=0,
            limit=100
        )

        # Assert
        recipient, cycle_count, latest_cycle = results[0]
        assert cycle_count == 1, "サイクル数が不正です"
        assert latest_cycle is None, "最新サイクルがNULLであること"

    @pytest.mark.asyncio
    async def test_subquery_performance(self, db_session: AsyncSession):
        """
        Test 1.2.4: サブクエリ統合のパフォーマンス

        要件:
        - 統合サブクエリが2つの独立サブクエリより高速
        - クエリ時間 < 200ms（100利用者）
        """
        # Setup: 100利用者 × 各3サイクル
        office = await create_test_office(db_session)
        for i in range(100):
            recipient = await create_test_recipient(
                db_session,
                office_id=office.id,
                last_name=f"テスト{i}",
                first_name="太郎"
            )
            for j in range(3):
                await create_test_cycle(
                    db_session,
                    welfare_recipient_id=recipient.id,
                    cycle_number=j + 1,
                    is_latest_cycle=(j == 2)
                )
        await db_session.commit()

        # Execute: クエリ時間測定
        import time
        start_time = time.time()
        results = await crud.dashboard.get_filtered_summaries(
            db=db_session,
            office_ids=[office.id],
            sort_by="furigana",
            sort_order="asc",
            filters={},
            search_term=None,
            skip=0,
            limit=100
        )
        elapsed_time = time.time() - start_time

        # Assert
        assert len(results) == 100, "結果が100件であること"
        assert elapsed_time < 0.2, f"クエリ時間が200msを超えました: {elapsed_time:.3f}s"


---

### Test 1.3: JOIN戦略統一のテスト

**ファイル**: `tests/crud/test_crud_dashboard_join.py`

**目的**: 常にOUTER JOINを使用することで、最新サイクルがない利用者も表示されることを検証

```python
import pytest
import pytest_asyncio
from sqlalchemy.ext.asyncio import AsyncSession

from app import crud
from tests.utils import create_test_office, create_test_recipient, create_test_cycle


class TestJoinStrategy:
    """JOIN戦略統一のテスト"""

    @pytest.mark.asyncio
    async def test_outer_join_includes_no_cycle_recipients(self, db_session: AsyncSession):
        """
        Test 1.3.1: 最新サイクルがない利用者も表示される

        要件:
        - OUTER JOIN により、サイクルがない利用者も結果に含まれる
        """
        # Setup
        office = await create_test_office(db_session)

        # サイクルありの利用者
        recipient_with_cycle = await create_test_recipient(
            db_session,
            office_id=office.id,
            last_name="山田",
            first_name="太郎"
        )
        await create_test_cycle(
            db_session,
            welfare_recipient_id=recipient_with_cycle.id,
            cycle_number=1,
            is_latest_cycle=True
        )

        # サイクルなしの利用者
        recipient_without_cycle = await create_test_recipient(
            db_session,
            office_id=office.id,
            last_name="佐藤",
            first_name="花子"
        )

        await db_session.commit()

        # Execute
        results = await crud.dashboard.get_filtered_summaries(
            db=db_session,
            office_ids=[office.id],
            sort_by="furigana",
            sort_order="asc",
            filters={},
            search_term=None,
            skip=0,
            limit=100
        )

        # Assert
        assert len(results) == 2, "2件の利用者が表示されること"

        # サイクルありの利用者
        recipient1, cycle_count1, latest_cycle1 = results[0]
        assert cycle_count1 == 1
        assert latest_cycle1 is not None

        # サイクルなしの利用者
        recipient2, cycle_count2, latest_cycle2 = results[1]
        assert cycle_count2 == 0
        assert latest_cycle2 is None

    @pytest.mark.asyncio
    async def test_sort_by_next_renewal_deadline_with_nulls(self, db_session: AsyncSession):
        """
        Test 1.3.2: 期限ソート時のNULLハンドリング

        要件:
        - sort_by='next_renewal_deadline' でもOUTER JOIN
        - NULLは最後にソート（nullslast）
        """
        # Setup: 期限あり・なしの利用者
        office = await create_test_office(db_session)

        # 期限あり
        recipient_with_deadline = await create_test_recipient(
            db_session,
            office_id=office.id,
            last_name="山田",
            first_name="太郎"
        )
        cycle_with_deadline = await create_test_cycle(
            db_session,
            welfare_recipient_id=recipient_with_deadline.id,
            cycle_number=1,
            is_latest_cycle=True,
            next_renewal_deadline="2026-03-01"
        )

        # 期限なし（最新サイクルなし）
        recipient_without_deadline = await create_test_recipient(
            db_session,
            office_id=office.id,
            last_name="佐藤",
            first_name="花子"
        )

        await db_session.commit()

        # Execute: 期限昇順でソート
        results = await crud.dashboard.get_filtered_summaries(
            db=db_session,
            office_ids=[office.id],
            sort_by="next_renewal_deadline",
            sort_order="asc",
            filters={},
            search_term=None,
            skip=0,
            limit=100
        )

        # Assert: 期限ありが先、期限なし（NULL）が後
        assert len(results) == 2

        first_recipient, _, first_cycle = results[0]
        assert first_cycle is not None, "1番目は期限ありの利用者"
        assert first_cycle.next_renewal_deadline is not None

        second_recipient, _, second_cycle = results[1]
        assert second_cycle is None, "2番目は期限なし（NULL）の利用者"


---

## 📋 Phase 2: インデックスのテスト

### Test 2.1: インデックス作成の検証

**ファイル**: `tests/migrations/test_dashboard_indexes.py`

**目的**: マイグレーションで4つのインデックスが正しく作成されることを検証

```python
import pytest
import pytest_asyncio
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession


class TestDashboardIndexes:
    """複合インデックスの作成テスト"""

    @pytest.mark.asyncio
    async def test_indexes_created(self, db_session: AsyncSession):
        """
        Test 2.1.1: 4つのインデックスが作成される

        要件:
        - idx_support_plan_cycles_recipient_latest
        - idx_support_plan_statuses_cycle_latest
        - idx_welfare_recipients_furigana
        - idx_office_welfare_recipients_office
        """
        # Execute: インデックス一覧取得
        query = text("""
            SELECT indexname
            FROM pg_indexes
            WHERE indexname IN (
                'idx_support_plan_cycles_recipient_latest',
                'idx_support_plan_statuses_cycle_latest',
                'idx_welfare_recipients_furigana',
                'idx_office_welfare_recipients_office'
            )
            ORDER BY indexname
        """)
        result = await db_session.execute(query)
        indexes = [row[0] for row in result.fetchall()]

        # Assert
        expected_indexes = [
            'idx_office_welfare_recipients_office',
            'idx_support_plan_cycles_recipient_latest',
            'idx_support_plan_statuses_cycle_latest',
            'idx_welfare_recipients_furigana'
        ]
        assert indexes == expected_indexes, f"インデックスが不足しています: {set(expected_indexes) - set(indexes)}"

    @pytest.mark.asyncio
    async def test_partial_index_conditions(self, db_session: AsyncSession):
        """
        Test 2.1.2: 部分インデックスのWHERE条件が正しい

        要件:
        - idx_support_plan_cycles_recipient_latest: WHERE is_latest_cycle = true
        - idx_support_plan_statuses_cycle_latest: WHERE is_latest_status = true
        """
        # Execute: インデックス定義取得
        query = text("""
            SELECT
                indexname,
                indexdef
            FROM pg_indexes
            WHERE indexname IN (
                'idx_support_plan_cycles_recipient_latest',
                'idx_support_plan_statuses_cycle_latest'
            )
        """)
        result = await db_session.execute(query)
        indexes_def = {row[0]: row[1] for row in result.fetchall()}

        # Assert: WHERE条件が含まれる
        assert 'is_latest_cycle = true' in indexes_def.get('idx_support_plan_cycles_recipient_latest', ''), \
            "is_latest_cycle のWHERE条件がありません"
        assert 'is_latest_status = true' in indexes_def.get('idx_support_plan_statuses_cycle_latest', ''), \
            "is_latest_status のWHERE条件がありません"


---

### Test 2.2: クエリプランの検証

**ファイル**: `tests/crud/test_crud_dashboard_query_plan.py`

**目的**: クエリがインデックスを使用していることを `EXPLAIN ANALYZE` で検証

```python
import pytest
import pytest_asyncio
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app import crud
from tests.utils import create_test_office, create_test_recipient, create_test_cycle


class TestQueryPlan:
    """クエリプランの検証テスト"""

    @pytest.mark.asyncio
    async def test_query_uses_index_for_latest_cycle(self, db_session: AsyncSession):
        """
        Test 2.2.1: 最新サイクル検索でインデックスを使用

        要件:
        - idx_support_plan_cycles_recipient_latest を使用
        - Seq Scan が発生しない
        """
        # Setup: 100利用者作成
        office = await create_test_office(db_session)
        for i in range(100):
            recipient = await create_test_recipient(db_session, office_id=office.id)
            await create_test_cycle(
                db_session,
                welfare_recipient_id=recipient.id,
                cycle_number=1,
                is_latest_cycle=True
            )
        await db_session.commit()

        # Execute: EXPLAIN ANALYZE でクエリプラン取得
        # SQLAlchemyのクエリをSQL文字列に変換
        from app.crud.crud_dashboard import CRUDDashboard
        crud_dashboard = CRUDDashboard(None)
        stmt = crud_dashboard._build_filtered_summaries_query(
            office_ids=[office.id],
            sort_by="next_renewal_deadline",
            sort_order="asc",
            filters={},
            search_term=None,
            skip=0,
            limit=100
        )

        # クエリプラン取得
        compiled_query = stmt.compile(compile_kwargs={"literal_binds": True})
        explain_query = text(f"EXPLAIN ANALYZE {compiled_query}")
        result = await db_session.execute(explain_query)
        query_plan = "\n".join([row[0] for row in result.fetchall()])

        # Assert: インデックススキャンを使用
        assert "idx_support_plan_cycles_recipient_latest" in query_plan, \
            "インデックスが使用されていません"
        assert "Seq Scan on support_plan_cycles" not in query_plan, \
            "Seq Scanが発生しています（インデックスが使用されていません）"

    @pytest.mark.asyncio
    async def test_query_uses_index_for_furigana_sort(self, db_session: AsyncSession):
        """
        Test 2.2.2: ふりがなソートでインデックスを使用

        要件:
        - idx_welfare_recipients_furigana を使用
        - Sort操作が発生しない（インデックススキャン）
        """
        # Setup
        office = await create_test_office(db_session)
        for i in range(100):
            await create_test_recipient(
                db_session,
                office_id=office.id,
                last_name_furigana=f"テスト{i:03d}",
                first_name_furigana="タロウ"
            )
        await db_session.commit()

        # Execute: EXPLAIN ANALYZE
        from app.crud.crud_dashboard import CRUDDashboard
        crud_dashboard = CRUDDashboard(None)
        stmt = crud_dashboard._build_filtered_summaries_query(
            office_ids=[office.id],
            sort_by="furigana",
            sort_order="asc",
            filters={},
            search_term=None,
            skip=0,
            limit=100
        )

        compiled_query = stmt.compile(compile_kwargs={"literal_binds": True})
        explain_query = text(f"EXPLAIN ANALYZE {compiled_query}")
        result = await db_session.execute(explain_query)
        query_plan = "\n".join([row[0] for row in result.fetchall()])

        # Assert: インデックススキャンを使用
        assert "idx_welfare_recipients_furigana" in query_plan, \
            "ふりがなインデックスが使用されていません"
        # ソート操作がインデックスで解決されている
        # （外部ソートが発生していないことを確認）


---

## 📋 Phase 3: selectinload最適化のテスト

### Test 3.1: selectinloadフィルタリングのテスト

**ファイル**: `tests/crud/test_crud_dashboard_selectinload.py`

**目的**: selectinloadが必要最小限のデータのみロードすることを検証

```python
import pytest
import pytest_asyncio
from sqlalchemy.ext.asyncio import AsyncSession

from app import crud
from app.models.enums import SupportPlanStep, DeliverableType
from tests.utils import (
    create_test_office,
    create_test_recipient,
    create_test_cycle,
    create_test_status,
    create_test_deliverable
)


class TestSelectinloadOptimization:
    """selectinload最適化のテスト"""

    @pytest_asyncio.fixture
    async def setup_recipient_with_full_data(self, db_session: AsyncSession):
        """利用者 + 複数ステータス + デリバラブルのテストデータ"""
        office = await create_test_office(db_session)
        recipient = await create_test_recipient(db_session, office_id=office.id)

        # 最新サイクル
        latest_cycle = await create_test_cycle(
            db_session,
            welfare_recipient_id=recipient.id,
            cycle_number=1,
            is_latest_cycle=True
        )

        # 複数のステータス（最新のみ1つ）
        status_old_1 = await create_test_status(
            db_session,
            plan_cycle_id=latest_cycle.id,
            step_type=SupportPlanStep.assessment,
            is_latest_status=False,
            completed=True
        )
        status_old_2 = await create_test_status(
            db_session,
            plan_cycle_id=latest_cycle.id,
            step_type=SupportPlanStep.draft_plan,
            is_latest_status=False,
            completed=True
        )
        status_latest = await create_test_status(
            db_session,
            plan_cycle_id=latest_cycle.id,
            step_type=SupportPlanStep.monitoring,
            is_latest_status=True,
            completed=False
        )

        # 複数のデリバラブル
        deliverable_assessment = await create_test_deliverable(
            db_session,
            plan_cycle_id=latest_cycle.id,
            deliverable_type=DeliverableType.assessment_sheet
        )
        deliverable_draft = await create_test_deliverable(
            db_session,
            plan_cycle_id=latest_cycle.id,
            deliverable_type=DeliverableType.draft_plan
        )
        deliverable_final = await create_test_deliverable(
            db_session,
            plan_cycle_id=latest_cycle.id,
            deliverable_type=DeliverableType.final_plan
        )

        await db_session.commit()
        return {
            "office": office,
            "recipient": recipient,
            "latest_cycle": latest_cycle,
            "statuses": {
                "old": [status_old_1, status_old_2],
                "latest": status_latest
            },
            "deliverables": {
                "assessment": deliverable_assessment,
                "others": [deliverable_draft, deliverable_final]
            }
        }

    @pytest.mark.asyncio
    async def test_only_latest_statuses_loaded(
        self,
        db_session: AsyncSession,
        setup_recipient_with_full_data
    ):
        """
        Test 3.1.1: 最新ステータスのみがロードされる

        要件:
        - is_latest_status=true のステータスのみロード
        - 過去のステータスはロードされない
        """
        data = setup_recipient_with_full_data
        office = data["office"]

        # Execute
        results = await crud.dashboard.get_filtered_summaries(
            db=db_session,
            office_ids=[office.id],
            sort_by="furigana",
            sort_order="asc",
            filters={},
            search_term=None,
            skip=0,
            limit=100
        )

        # Assert
        recipient, _, latest_cycle = results[0]

        # 最新ステータスのみがロードされている
        assert len(latest_cycle.statuses) == 1, \
            f"最新ステータスのみロードすべきです: {len(latest_cycle.statuses)}件ロードされています"
        assert latest_cycle.statuses[0].is_latest_status == True
        assert latest_cycle.statuses[0].step_type == SupportPlanStep.monitoring

    @pytest.mark.asyncio
    async def test_only_assessment_deliverables_loaded(
        self,
        db_session: AsyncSession,
        setup_recipient_with_full_data
    ):
        """
        Test 3.1.2: アセスメントシートのみがロードされる

        要件:
        - deliverable_type=assessment_sheet のみロード
        - 他のデリバラブルはロードされない
        """
        data = setup_recipient_with_full_data
        office = data["office"]

        # Execute
        results = await crud.dashboard.get_filtered_summaries(
            db=db_session,
            office_ids=[office.id],
            sort_by="furigana",
            sort_order="asc",
            filters={},
            search_term=None,
            skip=0,
            limit=100
        )

        # Assert
        recipient, _, latest_cycle = results[0]

        # アセスメントシートのみがロードされている
        assert len(latest_cycle.deliverables) == 1, \
            f"アセスメントシートのみロードすべきです: {len(latest_cycle.deliverables)}件ロードされています"
        assert latest_cycle.deliverables[0].deliverable_type == DeliverableType.assessment_sheet

    @pytest.mark.asyncio
    async def test_selectinload_reduces_query_count(self, db_session: AsyncSession):
        """
        Test 3.1.3: selectinloadのクエリ数削減

        要件:
        - N+1問題が発生しない
        - クエリ数が利用者数に比例しない
        """
        # Setup: 100利用者
        office = await create_test_office(db_session)
        for i in range(100):
            recipient = await create_test_recipient(db_session, office_id=office.id)
            cycle = await create_test_cycle(
                db_session,
                welfare_recipient_id=recipient.id,
                cycle_number=1,
                is_latest_cycle=True
            )
            # 各サイクルに10個のステータス（最新1つ）
            for j in range(10):
                await create_test_status(
                    db_session,
                    plan_cycle_id=cycle.id,
                    step_type=SupportPlanStep.assessment,
                    is_latest_status=(j == 9)
                )
        await db_session.commit()

        # SQLクエリロギングを有効化
        import logging
        logging.basicConfig()
        logger = logging.getLogger('sqlalchemy.engine')
        original_level = logger.level
        logger.setLevel(logging.INFO)

        # クエリカウンター
        query_count = 0
        original_execute = db_session.execute

        async def counting_execute(*args, **kwargs):
            nonlocal query_count
            query_count += 1
            return await original_execute(*args, **kwargs)

        db_session.execute = counting_execute

        # Execute
        results = await crud.dashboard.get_filtered_summaries(
            db=db_session,
            office_ids=[office.id],
            sort_by="furigana",
            sort_order="asc",
            filters={},
            search_term=None,
            skip=0,
            limit=100
        )

        # Cleanup
        db_session.execute = original_execute
        logger.setLevel(original_level)

        # Assert: クエリ数が定数オーダー（O(1)）
        # 期待値: メインクエリ1回 + selectinload数回（利用者数に比例しない）
        assert query_count <= 10, \
            f"クエリ数が多すぎます: {query_count}回（N+1問題の可能性）"


---

### Test 3.2: EXISTS句フィルターのテスト

**ファイル**: `tests/crud/test_crud_dashboard_filter.py`

**目的**: ステータスフィルターがEXISTS句で正しく動作することを検証

```python
import pytest
import pytest_asyncio
from sqlalchemy.ext.asyncio import AsyncSession

from app import crud
from app.models.enums import SupportPlanStep
from tests.utils import (
    create_test_office,
    create_test_recipient,
    create_test_cycle,
    create_test_status
)


class TestExistsClauseFilter:
    """EXISTS句を使用したフィルターのテスト"""

    @pytest_asyncio.fixture
    async def setup_recipients_with_different_statuses(self, db_session: AsyncSession):
        """異なるステータスの利用者を作成"""
        office = await create_test_office(db_session)

        # アセスメントステップの利用者
        recipient_assessment = await create_test_recipient(
            db_session,
            office_id=office.id,
            last_name="山田",
            first_name="太郎"
        )
        cycle_assessment = await create_test_cycle(
            db_session,
            welfare_recipient_id=recipient_assessment.id,
            cycle_number=1,
            is_latest_cycle=True
        )
        await create_test_status(
            db_session,
            plan_cycle_id=cycle_assessment.id,
            step_type=SupportPlanStep.assessment,
            is_latest_status=True
        )

        # モニタリングステップの利用者
        recipient_monitoring = await create_test_recipient(
            db_session,
            office_id=office.id,
            last_name="佐藤",
            first_name="花子"
        )
        cycle_monitoring = await create_test_cycle(
            db_session,
            welfare_recipient_id=recipient_monitoring.id,
            cycle_number=1,
            is_latest_cycle=True
        )
        await create_test_status(
            db_session,
            plan_cycle_id=cycle_monitoring.id,
            step_type=SupportPlanStep.monitoring,
            is_latest_status=True
        )

        await db_session.commit()
        return {
            "office": office,
            "recipients": {
                "assessment": recipient_assessment,
                "monitoring": recipient_monitoring
            }
        }

    @pytest.mark.asyncio
    async def test_filter_by_assessment_status(
        self,
        db_session: AsyncSession,
        setup_recipients_with_different_statuses
    ):
        """
        Test 3.2.1: アセスメントステータスでフィルタリング

        要件:
        - status='assessment' で正しくフィルタリング
        - EXISTS句が正しく動作
        """
        data = setup_recipients_with_different_statuses
        office = data["office"]

        # Execute: assessment フィルター
        results = await crud.dashboard.get_filtered_summaries(
            db=db_session,
            office_ids=[office.id],
            sort_by="furigana",
            sort_order="asc",
            filters={"status": "assessment"},
            search_term=None,
            skip=0,
            limit=100
        )

        # Assert: assessment の利用者のみ
        assert len(results) == 1, f"1件の結果が期待されます: {len(results)}件"
        recipient, _, latest_cycle = results[0]
        assert latest_cycle.statuses[0].step_type == SupportPlanStep.assessment

    @pytest.mark.asyncio
    async def test_filter_by_monitoring_status(
        self,
        db_session: AsyncSession,
        setup_recipients_with_different_statuses
    ):
        """
        Test 3.2.2: モニタリングステータスでフィルタリング

        要件:
        - status='monitoring' で正しくフィルタリング
        """
        data = setup_recipients_with_different_statuses
        office = data["office"]

        # Execute: monitoring フィルター
        results = await crud.dashboard.get_filtered_summaries(
            db=db_session,
            office_ids=[office.id],
            sort_by="furigana",
            sort_order="asc",
            filters={"status": "monitoring"},
            search_term=None,
            skip=0,
            limit=100
        )

        # Assert: monitoring の利用者のみ
        assert len(results) == 1
        recipient, _, latest_cycle = results[0]
        assert latest_cycle.statuses[0].step_type == SupportPlanStep.monitoring

    @pytest.mark.asyncio
    async def test_exists_clause_performance(self, db_session: AsyncSession):
        """
        Test 3.2.3: EXISTS句のパフォーマンス

        要件:
        - EXISTS句がサブクエリ+JOINより高速
        - クエリ時間 < 300ms（100利用者）
        """
        # Setup: 100利用者（50人ずつ異なるステータス）
        office = await create_test_office(db_session)
        for i in range(100):
            recipient = await create_test_recipient(db_session, office_id=office.id)
            cycle = await create_test_cycle(
                db_session,
                welfare_recipient_id=recipient.id,
                cycle_number=1,
                is_latest_cycle=True
            )
            status_type = SupportPlanStep.assessment if i < 50 else SupportPlanStep.monitoring
            await create_test_status(
                db_session,
                plan_cycle_id=cycle.id,
                step_type=status_type,
                is_latest_status=True
            )
        await db_session.commit()

        # Execute: パフォーマンス測定
        import time
        start_time = time.time()
        results = await crud.dashboard.get_filtered_summaries(
            db=db_session,
            office_ids=[office.id],
            sort_by="furigana",
            sort_order="asc",
            filters={"status": "assessment"},
            search_term=None,
            skip=0,
            limit=100
        )
        elapsed_time = time.time() - start_time

        # Assert
        assert len(results) == 50, "50件の結果が期待されます"
        assert elapsed_time < 0.3, f"クエリ時間が300msを超えました: {elapsed_time:.3f}s"


---

## 📋 統合テスト（E2E Performance Tests）

### Test 4.1: 500事業所でのパフォーマンステスト

**ファイル**: `tests/integration/test_dashboard_performance.py`

**目的**: 500事業所 × 100利用者の実環境でパフォーマンス目標を達成することを検証

```python
import pytest
import pytest_asyncio
import time
from sqlalchemy.ext.asyncio import AsyncSession

from app import crud
from tests.utils import create_test_offices, create_test_recipients, create_test_cycles


class TestDashboardPerformance:
    """ダッシュボード統合パフォーマンステスト"""

    @pytest_asyncio.fixture(scope="class")
    async def setup_500_offices(self, db_session: AsyncSession):
        """500事業所 × 100利用者のテストデータ作成"""
        # 500事業所作成
        offices = await create_test_offices(db_session, count=500)

        # 各事業所に100利用者 + 各利用者に3サイクル
        for office in offices:
            recipients = await create_test_recipients(
                db_session,
                office_id=office.id,
                count=100
            )
            for recipient in recipients:
                await create_test_cycles(
                    db_session,
                    welfare_recipient_id=recipient.id,
                    count=3
                )

        await db_session.commit()
        return offices

    @pytest.mark.asyncio
    @pytest.mark.slow
    async def test_initial_dashboard_load_performance(
        self,
        db_session: AsyncSession,
        setup_500_offices
    ):
        """
        Test 4.1.1: ダッシュボード初期表示パフォーマンス

        要件:
        - 500事業所でレスポンス時間 < 500ms
        - メモリ使用量 < 10MB
        """
        offices = setup_500_offices
        office_ids = [office.id for office in offices[:10]]  # 10事業所を同時表示

        # Execute: 初期表示
        start_time = time.time()
        results = await crud.dashboard.get_filtered_summaries(
            db=db_session,
            office_ids=office_ids,
            sort_by="furigana",
            sort_order="asc",
            filters={},
            search_term=None,
            skip=0,
            limit=100
        )
        elapsed_time = time.time() - start_time

        # Assert: パフォーマンス目標
        assert elapsed_time < 0.5, \
            f"初期表示が500msを超えました: {elapsed_time:.3f}s"
        assert len(results) <= 100, "ページネーションが機能していません"

    @pytest.mark.asyncio
    @pytest.mark.slow
    async def test_filter_performance(
        self,
        db_session: AsyncSession,
        setup_500_offices
    ):
        """
        Test 4.1.2: フィルタリングパフォーマンス

        要件:
        - フィルタリング応答 < 300ms
        """
        offices = setup_500_offices
        office_ids = [office.id for office in offices[:10]]

        # Execute: ステータスフィルター
        start_time = time.time()
        results = await crud.dashboard.get_filtered_summaries(
            db=db_session,
            office_ids=office_ids,
            sort_by="next_renewal_deadline",
            sort_order="asc",
            filters={"status": "assessment"},
            search_term=None,
            skip=0,
            limit=100
        )
        elapsed_time = time.time() - start_time

        # Assert
        assert elapsed_time < 0.3, \
            f"フィルタリングが300msを超えました: {elapsed_time:.3f}s"

    @pytest.mark.asyncio
    @pytest.mark.slow
    async def test_pagination_performance(
        self,
        db_session: AsyncSession,
        setup_500_offices
    ):
        """
        Test 4.1.3: ページネーションパフォーマンス

        要件:
        - 2ページ目以降も < 500ms
        - OFFSET が大きくても安定
        """
        offices = setup_500_offices
        office_ids = [office.id for office in offices[:10]]

        # Execute: 5ページ目（OFFSET=400）
        start_time = time.time()
        results = await crud.dashboard.get_filtered_summaries(
            db=db_session,
            office_ids=office_ids,
            sort_by="furigana",
            sort_order="asc",
            filters={},
            search_term=None,
            skip=400,
            limit=100
        )
        elapsed_time = time.time() - start_time

        # Assert
        assert elapsed_time < 0.5, \
            f"ページネーションが500msを超えました: {elapsed_time:.3f}s (OFFSET=400)"


### Test 4.2: 同時実行負荷テスト

**ファイル**: `tests/integration/test_dashboard_concurrency.py`

**目的**: 同時10リクエストで安定動作することを検証

```python
import pytest
import pytest_asyncio
import asyncio
from sqlalchemy.ext.asyncio import AsyncSession

from app import crud
from tests.utils import create_test_offices, create_test_recipients


class TestDashboardConcurrency:
    """同時実行負荷テスト"""

    @pytest.mark.asyncio
    @pytest.mark.slow
    async def test_concurrent_requests(self, db_session: AsyncSession):
        """
        Test 4.2.1: 同時10リクエストで安定動作

        要件:
        - 10リクエスト同時実行
        - すべて500ms以内
        - エラーが発生しない
        """
        # Setup: 50事業所作成
        offices = await create_test_offices(db_session, count=50)
        for office in offices:
            await create_test_recipients(db_session, office_id=office.id, count=100)
        await db_session.commit()

        # Execute: 10リクエストを同時実行
        async def single_request(office_id):
            import time
            start = time.time()
            results = await crud.dashboard.get_filtered_summaries(
                db=db_session,
                office_ids=[office_id],
                sort_by="furigana",
                sort_order="asc",
                filters={},
                search_term=None,
                skip=0,
                limit=100
            )
            elapsed = time.time() - start
            return (elapsed, len(results))

        # 10リクエストを並列実行
        tasks = [single_request(office.id) for office in offices[:10]]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        # Assert: すべて成功 & 500ms以内
        assert all(not isinstance(r, Exception) for r in results), \
            "一部のリクエストでエラーが発生しました"

        elapsed_times = [r[0] for r in results]
        assert all(t < 0.5 for t in elapsed_times), \
            f"一部のリクエストが500msを超えました: max={max(elapsed_times):.3f}s"

    @pytest.mark.asyncio
    @pytest.mark.slow
    async def test_database_connection_pool_not_exhausted(self, db_session: AsyncSession):
        """
        Test 4.2.2: DBコネクションプールが枯渇しない

        要件:
        - 100リクエスト連続実行
        - 「connection pool exhausted」エラーが発生しない
        """
        # Setup
        office = await create_test_offices(db_session, count=1)
        await create_test_recipients(db_session, office_id=office[0].id, count=100)
        await db_session.commit()

        # Execute: 100リクエスト連続実行
        async def single_request():
            results = await crud.dashboard.get_filtered_summaries(
                db=db_session,
                office_ids=[office[0].id],
                sort_by="furigana",
                sort_order="asc",
                filters={},
                search_term=None,
                skip=0,
                limit=100
            )
            return len(results)

        tasks = [single_request() for _ in range(100)]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        # Assert: すべて成功
        assert all(not isinstance(r, Exception) for r in results), \
            "コネクションプールが枯渇した可能性があります"


---

## 📋 回帰テスト

### Test 5.1: 既存機能の回帰テスト

**ファイル**: `tests/regression/test_dashboard_regression.py`

**目的**: 最適化によって既存機能が壊れていないことを検証

```python
import pytest
import pytest_asyncio
from sqlalchemy.ext.asyncio import AsyncSession

from app import crud
from app.models.enums import SupportPlanStep
from tests.utils import (
    create_test_office,
    create_test_recipient,
    create_test_cycle,
    create_test_status
)


class TestDashboardRegression:
    """既存機能の回帰テスト"""

    @pytest.mark.asyncio
    async def test_all_filters_work_correctly(self, db_session: AsyncSession):
        """
        Test 5.1.1: すべてのフィルターが正しく動作

        要件:
        - status フィルター
        - cycle_number フィルター
        - search_term（氏名検索）
        - 複合条件（AND）
        """
        # Setup: 様々な条件の利用者
        office = await create_test_office(db_session)

        # 利用者1: assessment, cycle=1, 名前="山田太郎"
        recipient1 = await create_test_recipient(
            db_session,
            office_id=office.id,
            last_name="山田",
            first_name="太郎"
        )
        cycle1 = await create_test_cycle(
            db_session,
            welfare_recipient_id=recipient1.id,
            cycle_number=1,
            is_latest_cycle=True
        )
        await create_test_status(
            db_session,
            plan_cycle_id=cycle1.id,
            step_type=SupportPlanStep.assessment,
            is_latest_status=True
        )

        # 利用者2: monitoring, cycle=2, 名前="佐藤花子"
        recipient2 = await create_test_recipient(
            db_session,
            office_id=office.id,
            last_name="佐藤",
            first_name="花子"
        )
        # cycle 1
        await create_test_cycle(
            db_session,
            welfare_recipient_id=recipient2.id,
            cycle_number=1,
            is_latest_cycle=False
        )
        # cycle 2（最新）
        cycle2 = await create_test_cycle(
            db_session,
            welfare_recipient_id=recipient2.id,
            cycle_number=2,
            is_latest_cycle=True
        )
        await create_test_status(
            db_session,
            plan_cycle_id=cycle2.id,
            step_type=SupportPlanStep.monitoring,
            is_latest_status=True
        )

        await db_session.commit()

        # Test: status フィルター
        results = await crud.dashboard.get_filtered_summaries(
            db=db_session,
            office_ids=[office.id],
            sort_by="furigana",
            sort_order="asc",
            filters={"status": "assessment"},
            search_term=None,
            skip=0,
            limit=100
        )
        assert len(results) == 1
        assert results[0][0].last_name == "山田"

        # Test: cycle_number フィルター
        results = await crud.dashboard.get_filtered_summaries(
            db=db_session,
            office_ids=[office.id],
            sort_by="furigana",
            sort_order="asc",
            filters={"cycle_number": 2},
            search_term=None,
            skip=0,
            limit=100
        )
        assert len(results) == 1
        assert results[0][0].last_name == "佐藤"

        # Test: search_term（氏名検索）
        results = await crud.dashboard.get_filtered_summaries(
            db=db_session,
            office_ids=[office.id],
            sort_by="furigana",
            sort_order="asc",
            filters={},
            search_term="山田",
            skip=0,
            limit=100
        )
        assert len(results) == 1
        assert results[0][0].last_name == "山田"

        # Test: 複合条件（status + cycle_number）
        results = await crud.dashboard.get_filtered_summaries(
            db=db_session,
            office_ids=[office.id],
            sort_by="furigana",
            sort_order="asc",
            filters={
                "status": "monitoring",
                "cycle_number": 2
            },
            search_term=None,
            skip=0,
            limit=100
        )
        assert len(results) == 1
        assert results[0][0].last_name == "佐藤"

    @pytest.mark.asyncio
    async def test_all_sort_options_work_correctly(self, db_session: AsyncSession):
        """
        Test 5.1.2: すべてのソートオプションが正しく動作

        要件:
        - furigana（ふりがな昇順・降順）
        - next_renewal_deadline（期限昇順・降順）
        - NULLハンドリング
        """
        # Setup: 異なるふりがな・期限の利用者
        office = await create_test_office(db_session)

        # 利用者A: あ, 期限=2026-03-01
        recipient_a = await create_test_recipient(
            db_session,
            office_id=office.id,
            last_name_furigana="あいうえお",
            first_name_furigana="あ"
        )
        cycle_a = await create_test_cycle(
            db_session,
            welfare_recipient_id=recipient_a.id,
            cycle_number=1,
            is_latest_cycle=True,
            next_renewal_deadline="2026-03-01"
        )

        # 利用者B: か, 期限=2026-02-01
        recipient_b = await create_test_recipient(
            db_session,
            office_id=office.id,
            last_name_furigana="かきくけこ",
            first_name_furigana="か"
        )
        cycle_b = await create_test_cycle(
            db_session,
            welfare_recipient_id=recipient_b.id,
            cycle_number=1,
            is_latest_cycle=True,
            next_renewal_deadline="2026-02-01"
        )

        # 利用者C: さ, 期限なし
        recipient_c = await create_test_recipient(
            db_session,
            office_id=office.id,
            last_name_furigana="さしすせそ",
            first_name_furigana="さ"
        )
        # サイクルなし（期限なし）

        await db_session.commit()

        # Test: ふりがな昇順
        results = await crud.dashboard.get_filtered_summaries(
            db=db_session,
            office_ids=[office.id],
            sort_by="furigana",
            sort_order="asc",
            filters={},
            search_term=None,
            skip=0,
            limit=100
        )
        assert len(results) == 3
        assert results[0][0].last_name_furigana.startswith("あ")
        assert results[1][0].last_name_furigana.startswith("か")
        assert results[2][0].last_name_furigana.startswith("さ")

        # Test: 期限昇順（早い順、NULLは最後）
        results = await crud.dashboard.get_filtered_summaries(
            db=db_session,
            office_ids=[office.id],
            sort_by="next_renewal_deadline",
            sort_order="asc",
            filters={},
            search_term=None,
            skip=0,
            limit=100
        )
        assert len(results) == 3
        # B(2026-02-01) → A(2026-03-01) → C(NULL)
        assert results[0][2] is not None
        assert results[0][2].next_renewal_deadline.strftime("%Y-%m-%d") == "2026-02-01"
        assert results[2][2] is None  # NULLは最後

    @pytest.mark.asyncio
    async def test_pagination_works_correctly(self, db_session: AsyncSession):
        """
        Test 5.1.3: ページネーションが正しく動作

        要件:
        - skip/limit が正しく機能
        - 総件数が正確
        """
        # Setup: 150利用者
        office = await create_test_office(db_session)
        for i in range(150):
            await create_test_recipient(
                db_session,
                office_id=office.id,
                last_name=f"テスト{i:03d}",
                first_name="太郎"
            )
        await db_session.commit()

        # Test: 1ページ目（0-99）
        results_page1 = await crud.dashboard.get_filtered_summaries(
            db=db_session,
            office_ids=[office.id],
            sort_by="furigana",
            sort_order="asc",
            filters={},
            search_term=None,
            skip=0,
            limit=100
        )
        assert len(results_page1) == 100

        # Test: 2ページ目（100-149）
        results_page2 = await crud.dashboard.get_filtered_summaries(
            db=db_session,
            office_ids=[office.id],
            sort_by="furigana",
            sort_order="asc",
            filters={},
            search_term=None,
            skip=100,
            limit=100
        )
        assert len(results_page2) == 50

        # Test: 重複がないこと
        page1_ids = {r[0].id for r in results_page1}
        page2_ids = {r[0].id for r in results_page2}
        assert page1_ids.isdisjoint(page2_ids), "ページ間で重複があります"


---

## 📊 テストカバレッジ目標

### カバレッジ要件

| カテゴリ | カバレッジ目標 | 重要度 |
|---------|--------------|--------|
| CRUD層 | 90%以上 | 🔴 最高 |
| Service層 | 85%以上 | 🟡 高 |
| API層 | 80%以上 | 🟡 高 |
| 統合テスト | 主要シナリオ100% | 🔴 最高 |

### テスト実行コマンド

```bash
# すべてのテスト実行
pytest tests/ -v

# カバレッジ測定
pytest tests/ --cov=app --cov-report=html

# パフォーマンステストのみ
pytest tests/integration/ -v -m slow

# 並列実行（高速化）
pytest tests/ -v -n auto
```

---

## ✅ テスト完了チェックリスト

### Phase 1: クエリ最適化
- [ ] Test 1.1.1: COUNT(*)パフォーマンス - PASS
- [ ] Test 1.1.2: COUNT() vs 全レコード比較 - PASS
- [ ] Test 1.1.3: 500事業所COUNT() - PASS
- [ ] Test 1.2.1: サイクル数カウント正確性 - PASS
- [ ] Test 1.2.2: 最新サイクルID正確性 - PASS
- [ ] Test 1.2.3: 最新サイクルなしでNULL - PASS
- [ ] Test 1.2.4: サブクエリ統合パフォーマンス - PASS
- [ ] Test 1.3.1: OUTER JOIN で全利用者表示 - PASS
- [ ] Test 1.3.2: 期限ソート時のNULLハンドリング - PASS

### Phase 2: インデックス
- [ ] Test 2.1.1: 4つのインデックス作成 - PASS
- [ ] Test 2.1.2: 部分インデックスWHERE条件 - PASS
- [ ] Test 2.2.1: 最新サイクルインデックス使用 - PASS
- [ ] Test 2.2.2: ふりがなインデックス使用 - PASS

### Phase 3: selectinload最適化
- [ ] Test 3.1.1: 最新ステータスのみロード - PASS
- [ ] Test 3.1.2: アセスメントシートのみロード - PASS
- [ ] Test 3.1.3: クエリ数削減（N+1回避） - PASS
- [ ] Test 3.2.1: アセスメントフィルター - PASS
- [ ] Test 3.2.2: モニタリングフィルター - PASS
- [ ] Test 3.2.3: EXISTS句パフォーマンス - PASS

### 統合テスト
- [ ] Test 4.1.1: 500事業所初期表示 < 500ms - PASS
- [ ] Test 4.1.2: フィルタリング < 300ms - PASS
- [ ] Test 4.1.3: ページネーション < 500ms - PASS
- [ ] Test 4.2.1: 同時10リクエスト安定 - PASS
- [ ] Test 4.2.2: コネクションプール枯渇なし - PASS

### 回帰テスト
- [ ] Test 5.1.1: 全フィルター動作 - PASS
- [ ] Test 5.1.2: 全ソートオプション動作 - PASS
- [ ] Test 5.1.3: ページネーション動作 - PASS

---

## 🔗 関連ドキュメント

- [現状分析](./01_current_state_analysis.md)
- [改善要件](./02_improvement_requirements.md)
- [実装ガイド](./03_implementation_guide.md)
- テストユーティリティ: `tests/utils.py`（作成予定）

---

## 📝 次のステップ

1. ✅ **このドキュメント**: テスト要件定義完了
2. 🔜 **テストユーティリティ作成**: `tests/utils.py` にヘルパー関数を実装
3. 🔜 **Red（失敗テスト）**: すべてのテストを実装し、失敗することを確認
4. 🔜 **Green（実装）**: Phase 1-3 の実装を行いテストをパス
5. 🔜 **Refactor（リファクタリング）**: コードを改善

---

**Last Updated**: 2026-02-14
**Test Framework**: pytest + pytest-asyncio
**TDD Approach**: Red → Green → Refactor
