# フロントエンド要件とバックエンド実装のギャップ分析

**作成日**: 2026-02-17
**分析対象**: `4_kensaku.md` (フロントエンド要件)
**現在のバックエンド状態**: Phase 1-3 最適化完了（セキュリティレビュー済み）

---

## 📊 実装状況サマリー

| 要件 | 状態 | 優先度 | 工数 |
|------|------|--------|------|
| ✅ デフォルトソート変更 | **完了** | - | 0h |
| ✅ COUNT(*)クエリ最適化 | **完了** | - | 0h |
| ❌ `filtered_count` フィールド追加 | **未実装** | 🔴 高 | 1.5h |
| ❌ `has_assessment_due` フィルター | **未実装** | 🔴 高 | 3h |
| ❌ フロントエンド全体 | **未着手** | 🔴 高 | 11h |

---

## ✅ 既に実装済み (Backend)

### 1. デフォルトソート変更 ✅
**要件**: Line 132-144 (`4_kensaku.md`)

**実装状況**:
```python
# app/api/v1/endpoints/dashboard.py:27
sort_by: str = 'next_renewal_deadline',  # ← Already done!
```

**確認**:
- ✅ デフォルトソートが `next_renewal_deadline` (昇順)
- ✅ 要件ドキュメント Line 36-37 で「改善されています」と記載あり

### 2. COUNT(*)クエリ最適化 ✅
**要件**: Line 76-79 (`4_kensaku.md`)

**実装状況**:
```python
# app/crud/crud_dashboard.py:45-56
async def count_office_recipients(self, db: AsyncSession, *, office_id: uuid.UUID) -> int:
    query = (
        select(func.count())
        .select_from(WelfareRecipient)
        .join(OfficeWelfareRecipient)
        .where(OfficeWelfareRecipient.office_id == office_id)
    )
    return result.scalar_one()
```

**確認**:
- ✅ Phase 1.1 で実装済み
- ✅ API endpoint (Line 52-55) で使用中
- ✅ セキュリティレビュー: 92/100 (Excellent)

### 3. ステータスフィルター (EXISTS clause) ✅
**実装状況**:
```python
# app/crud/crud_dashboard.py:156-171
stmt = stmt.where(
    exists(
        select(1).where(
            and_(
                SupportPlanStatus.plan_cycle_id == SupportPlanCycle.id,
                SupportPlanStatus.is_latest_status == true(),
                SupportPlanStatus.step_type == status_enum
            )
        )
    )
)
```

**確認**:
- ✅ Phase 3.2 で実装済み
- ✅ パフォーマンス: EXISTS句による早期終了最適化

---

## ❌ 未実装の Backend 要件

### 1. `filtered_count` フィールド追加 ❌

**優先度**: 🔴 **必須** (フロントエンドの根幹機能)

**要件**: Line 54-93 (`4_kensaku.md`)

#### 1.1 スキーマ拡張

**ファイル**: `app/schemas/dashboard.py:55-59`

**現在のコード**:
```python
class DashboardData(DashboardBase):
    """ダッシュボード情報(レスポンス)"""
    recipients: List[DashboardSummary]
    model_config = ConfigDict(from_attributes=True)
```

**必要な変更**:
```python
class DashboardData(DashboardBase):
    """ダッシュボード情報(レスポンス)"""
    filtered_count: int = Field(..., ge=0, description="検索結果数")  # ← 追加
    recipients: List[DashboardSummary]

    model_config = ConfigDict(from_attributes=True)

    @field_validator('filtered_count')
    @classmethod
    def _validate_filtered_count_le_current_count(cls, v: int, info) -> int:
        """filtered_count <= current_user_count を検証"""
        current_count = info.data.get('current_user_count')
        if current_count is not None and v > current_count:
            raise ValueError(f"filtered_count ({v}) cannot exceed current_user_count ({current_count})")
        return v
```

**工数**: 30分

#### 1.2 API レスポンス変更

**ファイル**: `app/api/v1/endpoints/dashboard.py:120-129`

**現在のコード**:
```python
return schemas.dashboard.DashboardData(
    staff_name=staff.full_name,
    staff_role=staff.role,
    office_id=office.id,
    office_name=office.name,
    current_user_count=current_user_count,
    max_user_count=max_user_count,
    billing_status=billing.billing_status,
    recipients=recipient_summaries
)
```

**必要な変更**:
```python
# フィルタリング結果の件数を計算
filtered_count = len(recipient_summaries)  # ← 追加

return schemas.dashboard.DashboardData(
    staff_name=staff.full_name,
    staff_role=staff.role,
    office_id=office.id,
    office_name=office.name,
    current_user_count=current_user_count,
    filtered_count=filtered_count,  # ← 追加
    max_user_count=max_user_count,
    billing_status=billing.billing_status,
    recipients=recipient_summaries
)
```

**工数**: 1時間

#### 1.3 テスト実装

**新規ファイル**: `tests/schemas/test_dashboard_schema.py`

**テストケース**:
```python
import pytest
from app.schemas.dashboard import DashboardData, DashboardBase
from app.models.enums import BillingStatus, StaffRole


class TestDashboardDataSchema:
    """DashboardData スキーマのバリデーションテスト"""

    def test_filtered_count_field_exists(self):
        """filtered_count フィールドが存在することを確認"""
        data = DashboardData(
            staff_name="テストスタッフ",
            staff_role=StaffRole.admin,
            office_id="123e4567-e89b-12d3-a456-426614174000",
            office_name="テスト事業所",
            current_user_count=100,
            filtered_count=50,  # ← 新規フィールド
            max_user_count=200,
            billing_status=BillingStatus.active,
            recipients=[]
        )
        assert data.filtered_count == 50

    def test_filtered_count_cannot_be_negative(self):
        """filtered_count が負の値の場合エラー"""
        with pytest.raises(ValueError):
            DashboardData(
                staff_name="テストスタッフ",
                staff_role=StaffRole.admin,
                office_id="123e4567-e89b-12d3-a456-426614174000",
                office_name="テスト事業所",
                current_user_count=100,
                filtered_count=-1,  # ← 負の値
                max_user_count=200,
                billing_status=BillingStatus.active,
                recipients=[]
            )

    def test_filtered_count_can_equal_current_count(self):
        """filtered_count が current_user_count と同じ値を許容"""
        data = DashboardData(
            staff_name="テストスタッフ",
            staff_role=StaffRole.admin,
            office_id="123e4567-e89b-12d3-a456-426614174000",
            office_name="テスト事業所",
            current_user_count=100,
            filtered_count=100,  # ← 同じ値
            max_user_count=200,
            billing_status=BillingStatus.active,
            recipients=[]
        )
        assert data.filtered_count == 100

    def test_filtered_count_cannot_exceed_current_count(self):
        """filtered_count が current_user_count を超える場合エラー"""
        with pytest.raises(ValueError, match="cannot exceed current_user_count"):
            DashboardData(
                staff_name="テストスタッフ",
                staff_role=StaffRole.admin,
                office_id="123e4567-e89b-12d3-a456-426614174000",
                office_name="テスト事業所",
                current_user_count=100,
                filtered_count=150,  # ← current_count を超える
                max_user_count=200,
                billing_status=BillingStatus.active,
                recipients=[]
            )

    def test_filtered_count_zero_is_valid(self):
        """filtered_count = 0 (検索結果なし) が有効"""
        data = DashboardData(
            staff_name="テストスタッフ",
            staff_role=StaffRole.admin,
            office_id="123e4567-e89b-12d3-a456-426614174000",
            office_name="テスト事業所",
            current_user_count=100,
            filtered_count=0,  # ← 0件
            max_user_count=200,
            billing_status=BillingStatus.active,
            recipients=[]
        )
        assert data.filtered_count == 0
```

**統合テスト追加**: `tests/integration/test_dashboard_api.py`

```python
@pytest.mark.asyncio
async def test_api_returns_filtered_count(client, auth_headers, db_session):
    """API レスポンスに filtered_count が含まれることを確認"""
    # Setup: 総利用者数 10名, フィルタリング結果 3名
    office = await create_test_office(db_session)
    recipients = await create_test_recipients(db_session, office.id, count=10)

    # 期限切れの利用者を3名作成
    for i in range(3):
        cycle = await create_test_cycle(
            db_session,
            recipients[i].id,
            office.id,
            next_renewal_deadline=date.today() - timedelta(days=10)
        )

    # API呼び出し: 期限切れフィルター
    response = await client.get(
        "/api/v1/dashboard/",
        headers=auth_headers,
        params={"is_overdue": True}
    )

    assert response.status_code == 200
    data = response.json()

    # 検証
    assert data["current_user_count"] == 10  # 総利用者数
    assert data["filtered_count"] == 3       # フィルタリング結果数 ← 新規検証
    assert len(data["recipients"]) == 3
```

**工数**: 2時間

**合計工数**: **3.5時間**

---

### 2. `has_assessment_due` フィルター追加 ❌

**優先度**: 🔴 **高** (新規機能要件)

**要件**: Line 95-130 (`4_kensaku.md`)

#### 2.1 API パラメータ追加

**ファイル**: `app/api/v1/endpoints/dashboard.py:20-38`

**現在のパラメータ**:
```python
async def get_dashboard(
    ...
    is_overdue: Optional[bool] = None,
    is_upcoming: Optional[bool] = None,
    status: Optional[str] = None,
    cycle_number: Optional[int] = None,
    ...
):
```

**必要な変更**:
```python
async def get_dashboard(
    ...
    is_overdue: Optional[bool] = None,
    is_upcoming: Optional[bool] = None,
    has_assessment_due: Annotated[  # ← 追加
        Optional[bool],
        Query(description="未完了のアセスメント開始期限が設定されている利用者のみ")
    ] = None,
    status: Optional[str] = None,
    cycle_number: Optional[int] = None,
    ...
):
```

**filters 辞書への追加** (Line 58-62):
```python
filters = {}
if is_overdue is not None: filters["is_overdue"] = is_overdue
if is_upcoming is not None: filters["is_upcoming"] = is_upcoming
if has_assessment_due is not None: filters["has_assessment_due"] = has_assessment_due  # ← 追加
if status: filters["status"] = status
if cycle_number is not None: filters["cycle_number"] = cycle_number
```

**工数**: 30分

#### 2.2 CRUD フィルター実装

**ファイル**: `app/crud/crud_dashboard.py:145-171`

**現在のフィルター処理**:
```python
# --- フィルター ---
if filters:
    if filters.get("is_overdue"):
        stmt = stmt.where(SupportPlanCycle.next_renewal_deadline < date.today())
    if filters.get("is_upcoming"):
        stmt = stmt.where(SupportPlanCycle.next_renewal_deadline.between(date.today(), date.today() + timedelta(days=30)))
    if filters.get("cycle_number"):
        stmt = stmt.where(func.coalesce(cycle_info_sq.c.cycle_count, 0) == filters["cycle_number"])
    if filters.get("status"):
        # ... EXISTS clause ...
```

**必要な変更** (Line 171の後に追加):
```python
    if filters.get("has_assessment_due"):
        # 未完了のアセスメント開始期限が設定されている利用者を抽出
        # 個別支援計画のステータス: アセスメント → 原案 → 担当者会議 → 本案 → モニタリング
        assessment_exists_subq = exists(
            select(1).where(
                and_(
                    SupportPlanStatus.plan_cycle_id == SupportPlanCycle.id,
                    SupportPlanStatus.step_type == SupportPlanStep.assessment,
                    SupportPlanStatus.completed == False,  # 未完了のみ
                    SupportPlanStatus.due_date.isnot(None)  # 期限が設定されている
                )
            )
        )
        stmt = stmt.where(assessment_exists_subq)
```

**ポイント**:
- ✅ EXISTS句を使用してパフォーマンス最適化
- ✅ `completed == False` で未完了のみ
- ✅ `due_date.isnot(None)` で期限設定済みのみ
- ✅ 既存の `status` フィルターとは **別の目的** (未完了 + 期限設定済みの組み合わせ)

**工数**: 1.5時間

#### 2.3 テスト実装

**新規ファイル**: `tests/crud/test_crud_dashboard_assessment_filter.py`

```python
import pytest
import pytest_asyncio
from datetime import date, timedelta
from sqlalchemy.ext.asyncio import AsyncSession

from app import crud
from app.models.enums import SupportPlanStep
from tests.utils.dashboard_helpers import (
    create_test_office,
    create_test_recipient,
    create_test_cycle,
    create_test_status
)


@pytest.mark.asyncio
class TestAssessmentDueFilter:
    """has_assessment_due フィルターのテスト"""

    @pytest_asyncio.fixture
    async def setup_assessment_data(self, db_session: AsyncSession):
        """テストデータセットアップ"""
        office = await create_test_office(db_session)

        # 利用者1: 未完了アセスメント + 期限あり
        recipient1 = await create_test_recipient(db_session, office.id, last_name="田中")
        cycle1 = await create_test_cycle(db_session, recipient1.id, office.id)
        status1 = await create_test_status(
            db_session,
            cycle1.id,
            recipient1.id,
            office.id,
            step_type=SupportPlanStep.assessment,
            completed=False,  # 未完了
            due_date=date.today() + timedelta(days=7)  # 期限あり
        )

        # 利用者2: 完了済みアセスメント + 期限あり（除外されるべき）
        recipient2 = await create_test_recipient(db_session, office.id, last_name="鈴木")
        cycle2 = await create_test_cycle(db_session, recipient2.id, office.id)
        status2 = await create_test_status(
            db_session,
            cycle2.id,
            recipient2.id,
            office.id,
            step_type=SupportPlanStep.assessment,
            completed=True,  # 完了済み
            due_date=date.today() + timedelta(days=7)
        )

        # 利用者3: 未完了アセスメント + 期限なし（除外されるべき）
        recipient3 = await create_test_recipient(db_session, office.id, last_name="佐藤")
        cycle3 = await create_test_cycle(db_session, recipient3.id, office.id)
        status3 = await create_test_status(
            db_session,
            cycle3.id,
            recipient3.id,
            office.id,
            step_type=SupportPlanStep.assessment,
            completed=False,  # 未完了
            due_date=None  # 期限なし
        )

        # 利用者4: 原案ステータス（除外されるべき）
        recipient4 = await create_test_recipient(db_session, office.id, last_name="高橋")
        cycle4 = await create_test_cycle(db_session, recipient4.id, office.id)
        status4 = await create_test_status(
            db_session,
            cycle4.id,
            recipient4.id,
            office.id,
            step_type=SupportPlanStep.draft_plan,  # アセスメント以外
            completed=False,
            due_date=date.today() + timedelta(days=7)
        )

        await db_session.commit()

        return {
            "office": office,
            "recipient1": recipient1,  # マッチするはず
            "recipient2": recipient2,  # 除外（完了済み）
            "recipient3": recipient3,  # 除外（期限なし）
            "recipient4": recipient4,  # 除外（別ステータス）
        }

    async def test_has_assessment_due_filter_returns_only_matching(
        self,
        db_session: AsyncSession,
        setup_assessment_data
    ):
        """未完了 + 期限設定済みのアセスメントのみ抽出される"""
        data = setup_assessment_data
        office = data["office"]

        # フィルター適用
        results = await crud.dashboard.get_filtered_summaries(
            db=db_session,
            office_ids=[office.id],
            sort_by="name_phonetic",
            sort_order="asc",
            filters={"has_assessment_due": True},
            search_term=None,
            skip=0,
            limit=100
        )

        # 検証: recipient1 のみがマッチ
        assert len(results) == 1
        recipient, cycle_count, latest_cycle = results[0]
        assert recipient.id == data["recipient1"].id

    async def test_has_assessment_due_excludes_completed(
        self,
        db_session: AsyncSession,
        setup_assessment_data
    ):
        """完了済みアセスメントは除外される"""
        data = setup_assessment_data
        office = data["office"]

        results = await crud.dashboard.get_filtered_summaries(
            db=db_session,
            office_ids=[office.id],
            sort_by="name_phonetic",
            sort_order="asc",
            filters={"has_assessment_due": True},
            search_term=None,
            skip=0,
            limit=100
        )

        # recipient2 (完了済み) は含まれない
        recipient_ids = [r[0].id for r in results]
        assert data["recipient2"].id not in recipient_ids

    async def test_has_assessment_due_excludes_no_due_date(
        self,
        db_session: AsyncSession,
        setup_assessment_data
    ):
        """期限未設定のアセスメントは除外される"""
        data = setup_assessment_data
        office = data["office"]

        results = await crud.dashboard.get_filtered_summaries(
            db=db_session,
            office_ids=[office.id],
            sort_by="name_phonetic",
            sort_order="asc",
            filters={"has_assessment_due": True},
            search_term=None,
            skip=0,
            limit=100
        )

        # recipient3 (期限なし) は含まれない
        recipient_ids = [r[0].id for r in results]
        assert data["recipient3"].id not in recipient_ids

    async def test_has_assessment_due_excludes_other_steps(
        self,
        db_session: AsyncSession,
        setup_assessment_data
    ):
        """アセスメント以外のステップは除外される"""
        data = setup_assessment_data
        office = data["office"]

        results = await crud.dashboard.get_filtered_summaries(
            db=db_session,
            office_ids=[office.id],
            sort_by="name_phonetic",
            sort_order="asc",
            filters={"has_assessment_due": True},
            search_term=None,
            skip=0,
            limit=100
        )

        # recipient4 (原案ステータス) は含まれない
        recipient_ids = [r[0].id for r in results]
        assert data["recipient4"].id not in recipient_ids

    async def test_has_assessment_due_combined_with_search(
        self,
        db_session: AsyncSession,
        setup_assessment_data
    ):
        """検索ワードとの複合条件で動作する"""
        data = setup_assessment_data
        office = data["office"]

        # "田中" + has_assessment_due
        results = await crud.dashboard.get_filtered_summaries(
            db=db_session,
            office_ids=[office.id],
            sort_by="name_phonetic",
            sort_order="asc",
            filters={"has_assessment_due": True},
            search_term="田中",
            skip=0,
            limit=100
        )

        # recipient1 (田中) のみマッチ
        assert len(results) == 1
        assert results[0][0].id == data["recipient1"].id
```

**統合テスト追加**: `tests/integration/test_dashboard_api.py`

```python
@pytest.mark.asyncio
async def test_api_has_assessment_due_filter(client, auth_headers, db_session):
    """API経由で has_assessment_due フィルターが動作することを確認"""
    office = await create_test_office(db_session)

    # 利用者1: 条件に合致
    recipient1 = await create_test_recipient(db_session, office.id, last_name="田中")
    cycle1 = await create_test_cycle(db_session, recipient1.id, office.id)
    await create_test_status(
        db_session, cycle1.id, recipient1.id, office.id,
        step_type=SupportPlanStep.assessment,
        completed=False,
        due_date=date.today() + timedelta(days=7)
    )

    # 利用者2: 完了済み（除外されるべき）
    recipient2 = await create_test_recipient(db_session, office.id, last_name="鈴木")
    cycle2 = await create_test_cycle(db_session, recipient2.id, office.id)
    await create_test_status(
        db_session, cycle2.id, recipient2.id, office.id,
        step_type=SupportPlanStep.assessment,
        completed=True,
        due_date=date.today() + timedelta(days=7)
    )

    await db_session.commit()

    # API呼び出し
    response = await client.get(
        "/api/v1/dashboard/",
        headers=auth_headers,
        params={"has_assessment_due": True}
    )

    assert response.status_code == 200
    data = response.json()

    # 検証
    assert data["current_user_count"] == 2
    assert data["filtered_count"] == 1  # recipient1 のみ
    assert len(data["recipients"]) == 1
    assert data["recipients"][0]["last_name"] == "田中"
```

**工数**: 3時間

**合計工数**: **5時間**

---

## 📝 実装優先順位

### 🔴 Phase A: Backend 必須実装 (8.5時間)

| タスク | 工数 | 優先度 | 理由 |
|--------|------|--------|------|
| 1. `filtered_count` フィールド追加 | 3.5h | 🔴 最高 | フロントエンドの根幹機能 |
| 2. `has_assessment_due` フィルター | 5h | 🔴 高 | 新規機能要件 |

**実装順序**:
1. **Phase A-1**: `filtered_count` を先に実装（3.5h）
   - フロントエンドが即座に活用できる
   - 既存のフィルターすべてに対応

2. **Phase A-2**: `has_assessment_due` フィルター実装（5h）
   - 新規機能として追加

### 🟡 Phase B: Frontend 実装 (11時間)

**要件**: `4_kensaku.md` Phase 2 (Line 161-463)

**実装順序** (優先度順):
1. **Phase B-1**: 型定義 + 件数表示 (2.5h)
   - TypeScript型定義更新
   - 総利用者数 vs 検索結果数の表示

2. **Phase B-2**: フィルター名明確化 (1h)
   - "期限切れ" → "計画期限切れ"
   - Tooltip追加

3. **Phase B-3**: アセスメントフィルターUI (1.5h)
   - 新規フィルターボタン追加

4. **Phase B-4**: Active Filters チップ表示 (2h) ← **新規要件**
   - 選択中の条件を視覚化
   - 個別削除 + 一括クリア機能

5. **Phase B-5**: 状態管理改善 (2h)
   - 複合条件の状態管理

6. **Phase B-6**: E2Eテスト (3h)

---

## 🎯 テスト要件サマリー

### Backend テスト (5.5時間)

**新規テストファイル**:
1. `tests/schemas/test_dashboard_schema.py` (2h)
   - `filtered_count` バリデーション: 5テスト

2. `tests/crud/test_crud_dashboard_assessment_filter.py` (3h)
   - `has_assessment_due` フィルター: 5テスト

3. `tests/integration/test_dashboard_api.py` (追加: 0.5h)
   - API経由の統合テスト: 2テスト

**テストカバレッジ目標**: 80%以上

### Frontend テスト (3時間)

**E2Eテスト**: `k_front/e2e/dashboard-filtering.spec.ts`
- 総利用者数 vs 検索結果数の表示確認
- 複合条件フィルタリング
- Active Filters チップの表示・削除
- "すべてクリア" 機能

---

## 🚀 実装ロードマップ

### Week 1: Backend 実装 (2日)

**Day 1** (4時間):
- ✅ `filtered_count` スキーマ拡張 (30分)
- ✅ API レスポンス変更 (1時間)
- ✅ スキーマテスト実装 (2時間)
- ✅ 統合テスト追加 (30分)

**Day 2** (5時間):
- ✅ `has_assessment_due` API パラメータ追加 (30分)
- ✅ CRUD フィルター実装 (1.5時間)
- ✅ テスト実装 (3時間)

### Week 2: Frontend 実装 (2日)

**Day 3** (5.5時間):
- 型定義更新 (30分)
- 件数表示UI (2時間)
- フィルター名変更 (1時間)
- アセスメントフィルターUI (1.5時間)
- デフォルトソート変更 (30分)

**Day 4** (5.5時間):
- Active Filters チップUI (2時間)
- 状態管理改善 (2時間)
- E2Eテスト (3時間)

### Week 3: 統合・デプロイ (0.5日)

**Day 5** (5時間):
- 結合テスト (2時間)
- UIテスト (1時間)
- パフォーマンステスト (1時間)
- デプロイ (1時間)

---

## ⚠️ 実装上の注意点

### 1. `filtered_count` vs `current_user_count`

**重要**: この2つのフィールドは **異なる意味** を持つ:

```python
# current_user_count: フィルター無視、総利用者数（固定）
current_user_count = await crud.dashboard.count_office_recipients(
    db=db,
    office_id=office.id
)  # フィルター条件を無視

# filtered_count: フィルター適用後の結果数
filtered_results = await crud.dashboard.get_filtered_summaries(
    db=db,
    office_ids=[office.id],
    filters=filters,  # ← フィルター適用
    search_term=search_term,
    skip=skip,
    limit=limit
)
filtered_count = len(filtered_results)  # フィルター後の件数
```

**UI表示例**:
```
総利用者数: 100名
検索結果: 15名  ← filtered_count (フィルター適用時のみ表示)
```

### 2. `has_assessment_due` vs `status` フィルターの違い

| フィルター | 目的 | 条件 |
|-----------|------|------|
| `status=assessment` | アセスメントステータスの利用者を抽出 | `is_latest_status == True` AND `step_type == assessment` |
| `has_assessment_due=True` | **未完了** で **期限設定済み** のアセスメントを抽出 | `step_type == assessment` AND `completed == False` AND `due_date IS NOT NULL` |

**使い分け**:
- `status`: ステータスによる絞り込み（完了/未完了問わず）
- `has_assessment_due`: アクション必要な利用者の抽出（未完了 + 期限あり）

### 3. Pydantic Field Validator の順序

```python
@field_validator('filtered_count')
@classmethod
def _validate_filtered_count_le_current_count(cls, v: int, info) -> int:
    """filtered_count <= current_user_count を検証"""
    current_count = info.data.get('current_user_count')
    if current_count is not None and v > current_count:
        raise ValueError(...)
    return v
```

**注意**:
- `info.data.get('current_user_count')` は、**フィールド定義順序** に依存
- `DashboardBase` で `current_user_count` が先に定義されているため、`info.data` で取得可能

### 4. セキュリティ考慮事項

**既存の対策** (セキュリティレビュー: 85/100):
- ✅ SQL injection 防止 (parameterized queries)
- ✅ Multi-tenancy 保護 (office_id scoping)
- ✅ JWT authentication

**新規要件での注意点**:
- ✅ `has_assessment_due` は boolean のみ受け入れ (SQLi risk なし)
- ⚠️ `search_term` は既存の MAX_SEARCH_TERM_LENGTH (100文字) で制限済み

---

## 📊 完了条件チェックリスト

### Backend (Phase A)

- [ ] `filtered_count` フィールドが `DashboardData` スキーマに追加されている
- [ ] `filtered_count` のバリデーションテストが全て通る (5テスト)
- [ ] API レスポンスに `filtered_count` が含まれる
- [ ] `has_assessment_due` パラメータが API に追加されている
- [ ] `has_assessment_due` フィルターが正しく動作する (5テスト)
- [ ] 統合テストが全て通る (2テスト)
- [ ] セキュリティレビューで新規実装が 80点以上
- [ ] パフォーマンステストで 500ms 以下（500事業所規模）

### Frontend (Phase B)

- [ ] TypeScript型定義に `filtered_count` が追加されている
- [ ] 総利用者数と検索結果数が分離表示されている
- [ ] フィルター名が明確になっている（計画期限切れ、等）
- [ ] アセスメント開始期限フィルターUIが動作する
- [ ] Active Filters チップが表示される
- [ ] 各チップから個別に条件を解除できる
- [ ] "すべてクリア" ボタンが動作する
- [ ] E2Eテストが全て成功する

### 統合 (Phase C)

- [ ] バックエンド + フロントエンド連携が正常動作
- [ ] 複合条件検索が正しく動作する
- [ ] モバイル表示でもチップが見やすい
- [ ] 500事業所規模でレスポンス 500ms 以下

---

## 🔗 関連ドキュメント

- **フロントエンド要件**: `@md_files_design_note/task/kensaku/todo/4_kensaku.md`
- **セキュリティレビュー**: `@md_files_design_note/task/kensaku/05_security_code_review.md`
- **テスト要件**: `@md_files_design_note/task/kensaku/04_test_requirements.md`
- **パフォーマンス最適化**: `@md_files_design_note/task/kensaku/README.md`

---

**ステータス**: 📋 分析完了
**次のアクション**: Phase A-1 実装開始 (`filtered_count` フィールド追加)
**想定工数**: Backend 8.5h + Frontend 11h + 統合 5h = **24.5時間**
