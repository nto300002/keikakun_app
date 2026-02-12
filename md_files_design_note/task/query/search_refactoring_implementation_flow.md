# 検索機能リファクタリング実装フロー

## 📋 概要

**目的**: ダッシュボード検索機能のパフォーマンス改善と、検索・フィルタリング・ソートの複数条件組み合わせ対応

**対象ファイル**:
- `k_back/app/crud/crud_dashboard.py`
- `k_back/app/models/support_plan_cycle.py`
- `k_back/app/models/welfare_recipient.py`

**参照ドキュメント**:
- @md_files_design_note/task/query/search.md
- @md_files_design_note/task/query/Query_Optimization.md

---

## 🎯 目標指標

| 指標 | 現状 | 目標（Phase 2完了時） | 目標（Phase 4完了時） |
|------|------|---------------------|---------------------|
| **レスポンスタイム（100人）** | ~500ms | ~100ms | ~50ms |
| **レスポンスタイム（500人）** | ~2000ms | ~300ms | ~100ms |
| **同時検索処理数** | 5 req/s | 20 req/s | 50 req/s |
| **複合検索条件対応** | ❌ | ✅ | ✅ |
| **全文検索精度** | 部分一致のみ | あいまい検索対応 | あいまい検索 + ランキング |

---

## 🚀 実装フェーズ

### Phase 1: 緊急対応 - インデックス追加（最優先）

**目的**: 最小限の変更で最大の効果を得る

**期間**: 1日

**実装内容**:

#### 1.1 データベースマイグレーション作成

```bash
cd k_back
alembic revision -m "add_critical_search_indexes"
```

#### 1.2 マイグレーションファイル編集

**ファイル**: `k_back/alembic/versions/XXXXXX_add_critical_search_indexes.py`

```python
"""add critical search indexes

Revision ID: XXXXXX
Revises: YYYYYY
Create Date: 2026-02-06
"""
from alembic import op

def upgrade() -> None:
    # 🔴 最優先1: ステータスフィルター高速化
    op.create_index(
        'idx_support_plan_statuses_latest_step',
        'support_plan_statuses',
        ['is_latest_status', 'step_type'],
        postgresql_where='is_latest_status = true'  # Partial index for efficiency
    )

    # 🔴 最優先2: 事業所-利用者JOIN高速化
    op.create_index(
        'idx_office_welfare_recipients_composite',
        'office_welfare_recipients',
        ['office_id', 'welfare_recipient_id']
    )

    # 🟡 中優先1: サイクル検索高速化
    op.create_index(
        'idx_support_plan_cycle_latest_renewal',
        'support_plan_cycles',
        ['welfare_recipient_id', 'is_latest_cycle', 'next_renewal_deadline']
    )

    # 🟡 中優先2: 日付範囲検索高速化（Partial index）
    op.create_index(
        'idx_support_plan_cycle_renewal_date',
        'support_plan_cycles',
        ['next_renewal_deadline'],
        postgresql_where='is_latest_cycle = true'
    )

def downgrade() -> None:
    op.drop_index('idx_support_plan_cycle_renewal_date', table_name='support_plan_cycles')
    op.drop_index('idx_support_plan_cycle_latest_renewal', table_name='support_plan_cycles')
    op.drop_index('idx_office_welfare_recipients_composite', table_name='office_welfare_recipients')
    op.drop_index('idx_support_plan_statuses_latest_step', table_name='support_plan_statuses')
```

#### 1.3 マイグレーション適用

```bash
# ローカル環境でテスト
docker exec keikakun_app-backend-1 alembic upgrade head

# インデックス作成確認
docker exec keikakun_app-backend-1 psql $DATABASE_URL -c "
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename IN ('support_plan_statuses', 'office_welfare_recipients', 'support_plan_cycles')
ORDER BY tablename, indexname;
"
```

#### 1.4 テスト項目

- [ ] マイグレーション適用成功
- [ ] インデックスが正しく作成されている
- [ ] 既存のテストが全てパス
- [ ] ダッシュボード表示速度が改善（目視確認）
- [ ] ステータスフィルター使用時の速度改善（目視確認）

#### 1.5 ロールバックプラン

```bash
# マイグレーション巻き戻し
docker exec keikakun_app-backend-1 alembic downgrade -1

# インデックス削除確認
docker exec keikakun_app-backend-1 psql $DATABASE_URL -c "
DROP INDEX IF EXISTS idx_support_plan_statuses_latest_step;
DROP INDEX IF EXISTS idx_office_welfare_recipients_composite;
DROP INDEX IF EXISTS idx_support_plan_cycle_latest_renewal;
DROP INDEX IF EXISTS idx_support_plan_cycle_renewal_date;
"
```

**Phase 1 完了条件**:
- ✅ 全インデックスが作成されている
- ✅ テストが全てパス
- ✅ 本番環境にデプロイ完了

---

### Phase 2: 検索機能改善 - 全文検索インデックス導入

**目的**: あいまい検索・複数単語検索の高速化

**期間**: 2-3日

**実装内容**:

#### 2.1 PostgreSQL拡張機能の有効化

```bash
docker exec keikakun_app-backend-1 psql $DATABASE_URL -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;"
```

#### 2.2 マイグレーション作成

```bash
alembic revision -m "add_fulltext_search_index"
```

**ファイル**: `k_back/alembic/versions/XXXXXX_add_fulltext_search_index.py`

```python
"""add fulltext search index

Revision ID: XXXXXX
Revises: YYYYYY
Create Date: 2026-02-06
"""
from alembic import op
import sqlalchemy as sa

def upgrade() -> None:
    # pg_trgm拡張機能の有効化
    op.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm;")

    # 名前検索用GINインデックス（トライグラム）
    op.execute("""
        CREATE INDEX idx_welfare_recipient_name_gin
        ON welfare_recipients
        USING gin(
            (
                COALESCE(last_name, '') || ' ' ||
                COALESCE(first_name, '') || ' ' ||
                COALESCE(last_name_furigana, '') || ' ' ||
                COALESCE(first_name_furigana, '')
            ) gin_trgm_ops
        );
    """)

    # 個別カラムのトライグラムインデックス（オプション）
    op.create_index(
        'idx_welfare_recipient_last_name_trgm',
        'welfare_recipients',
        ['last_name'],
        postgresql_using='gin',
        postgresql_ops={'last_name': 'gin_trgm_ops'}
    )

    op.create_index(
        'idx_welfare_recipient_first_name_trgm',
        'welfare_recipients',
        ['first_name'],
        postgresql_using='gin',
        postgresql_ops={'first_name': 'gin_trgm_ops'}
    )

    op.create_index(
        'idx_welfare_recipient_last_name_furigana_trgm',
        'welfare_recipients',
        ['last_name_furigana'],
        postgresql_using='gin',
        postgresql_ops={'last_name_furigana': 'gin_trgm_ops'}
    )

    op.create_index(
        'idx_welfare_recipient_first_name_furigana_trgm',
        'welfare_recipients',
        ['first_name_furigana'],
        postgresql_using='gin',
        postgresql_ops={'first_name_furigana': 'gin_trgm_ops'}
    )

def downgrade() -> None:
    op.drop_index('idx_welfare_recipient_first_name_furigana_trgm', table_name='welfare_recipients')
    op.drop_index('idx_welfare_recipient_last_name_furigana_trgm', table_name='welfare_recipients')
    op.drop_index('idx_welfare_recipient_first_name_trgm', table_name='welfare_recipients')
    op.drop_index('idx_welfare_recipient_last_name_trgm', table_name='welfare_recipients')
    op.execute("DROP INDEX IF EXISTS idx_welfare_recipient_name_gin;")
```

#### 2.3 CRUD層の改修

**ファイル**: `k_back/app/crud/crud_dashboard.py`

**変更前** (115-124行目):
```python
# 検索
if search_term:
    search_words = re.split(r'[\s　]+', search_term.strip())
    conditions = [or_(
        WelfareRecipient.last_name.ilike(f"%{word}%"),
        WelfareRecipient.first_name.ilike(f"%{word}%"),
        WelfareRecipient.last_name_furigana.ilike(f"%{word}%"),
        WelfareRecipient.first_name_furigana.ilike(f"%{word}%"),
    ) for word in search_words if word]
    if conditions:
        stmt = stmt.where(and_(*conditions))
```

**変更後**:
```python
# 検索（pg_trgm使用）
if search_term:
    search_words = re.split(r'[\s　]+', search_term.strip())

    # 全文検索用の連結カラム
    full_name_expr = func.concat(
        func.coalesce(WelfareRecipient.last_name, ''), ' ',
        func.coalesce(WelfareRecipient.first_name, ''), ' ',
        func.coalesce(WelfareRecipient.last_name_furigana, ''), ' ',
        func.coalesce(WelfareRecipient.first_name_furigana, '')
    )

    # 各単語に対してトライグラム類似度検索
    conditions = []
    for word in search_words:
        if not word:
            continue

        # トライグラム類似度検索（% 演算子）
        # similarity threshold は 0.3（30%一致で検索結果に含める）
        conditions.append(
            or_(
                WelfareRecipient.last_name.op('%')(word),
                WelfareRecipient.first_name.op('%')(word),
                WelfareRecipient.last_name_furigana.op('%')(word),
                WelfareRecipient.first_name_furigana.op('%')(word),
            )
        )

    if conditions:
        stmt = stmt.where(and_(*conditions))
```

#### 2.4 検索精度調整用のヘルパー関数追加

**ファイル**: `k_back/app/crud/crud_dashboard.py`（メソッド追加）

```python
def _build_search_condition(
    self,
    search_term: Optional[str],
    use_fuzzy_search: bool = True,
    similarity_threshold: float = 0.3
) -> Optional[Any]:
    """
    検索条件を構築する

    Args:
        search_term: 検索文字列
        use_fuzzy_search: あいまい検索を使用するか（pg_trgm）
        similarity_threshold: 類似度閾値（0.0-1.0）

    Returns:
        検索条件のSQLAlchemy式、または検索なしの場合None
    """
    if not search_term:
        return None

    search_words = re.split(r'[\s　]+', search_term.strip())
    search_words = [word for word in search_words if word]

    if not search_words:
        return None

    conditions = []

    if use_fuzzy_search:
        # トライグラムあいまい検索
        for word in search_words:
            conditions.append(
                or_(
                    WelfareRecipient.last_name.op('%')(word),
                    WelfareRecipient.first_name.op('%')(word),
                    WelfareRecipient.last_name_furigana.op('%')(word),
                    WelfareRecipient.first_name_furigana.op('%')(word),
                )
            )
    else:
        # 従来のILIKE検索（後方互換性のため残す）
        for word in search_words:
            conditions.append(
                or_(
                    WelfareRecipient.last_name.ilike(f"%{word}%"),
                    WelfareRecipient.first_name.ilike(f"%{word}%"),
                    WelfareRecipient.last_name_furigana.ilike(f"%{word}%"),
                    WelfareRecipient.first_name_furigana.ilike(f"%{word}%"),
                )
            )

    return and_(*conditions) if conditions else None
```

#### 2.5 API層の改修（オプション: 検索精度調整用パラメータ追加）

**ファイル**: `k_back/app/schemas/dashboard.py`（スキーマ追加）

```python
class DashboardSearchParams(BaseModel):
    """ダッシュボード検索パラメータ"""
    search_term: Optional[str] = None
    use_fuzzy_search: bool = True  # あいまい検索を使用
    similarity_threshold: float = Field(default=0.3, ge=0.0, le=1.0)  # 類似度閾値
```

#### 2.6 テスト追加

**ファイル**: `k_back/tests/crud/test_crud_dashboard_search.py`（新規作成）

```python
import pytest
from app.crud.crud_dashboard import crud_dashboard
from tests.utils.welfare_recipient import create_random_welfare_recipient

@pytest.mark.asyncio
async def test_fuzzy_search_similar_name(db_session, test_office):
    """トライグラムあいまい検索: 類似名前の検索"""
    # テストデータ作成
    # 正: 山田太郎 (やまだたろう)
    recipient1 = await create_random_welfare_recipient(
        db_session, test_office.id,
        last_name="山田", first_name="太郎",
        last_name_furigana="やまだ", first_name_furigana="たろう"
    )

    # 類似: 山口太郎 (やまぐちたろう)
    recipient2 = await create_random_welfare_recipient(
        db_session, test_office.id,
        last_name="山口", first_name="太郎",
        last_name_furigana="やまぐち", first_name_furigana="たろう"
    )

    # 非類似: 佐藤花子 (さとうはなこ)
    recipient3 = await create_random_welfare_recipient(
        db_session, test_office.id,
        last_name="佐藤", first_name="花子",
        last_name_furigana="さとう", first_name_furigana="はなこ"
    )

    # あいまい検索: "やまだ" → 山田、山口がヒット
    results = await crud_dashboard.get_filtered_summaries(
        db_session,
        office_ids=[test_office.id],
        sort_by="name_phonetic",
        sort_order="asc",
        filters={},
        search_term="やまだ",
        skip=0,
        limit=100
    )

    recipient_ids = [r.WelfareRecipient.id for r in results]
    assert recipient1.id in recipient_ids  # 完全一致
    # pg_trgmの閾値次第で山口もヒットする可能性あり

@pytest.mark.asyncio
async def test_multiple_word_search(db_session, test_office):
    """複数単語検索"""
    recipient = await create_random_welfare_recipient(
        db_session, test_office.id,
        last_name="山田", first_name="太郎",
        last_name_furigana="やまだ", first_name_furigana="たろう"
    )

    # 複数単語: "山田 太郎"
    results = await crud_dashboard.get_filtered_summaries(
        db_session,
        office_ids=[test_office.id],
        sort_by="name_phonetic",
        sort_order="asc",
        filters={},
        search_term="山田 太郎",
        skip=0,
        limit=100
    )

    assert len(results) >= 1
    assert results[0].WelfareRecipient.id == recipient.id

@pytest.mark.asyncio
async def test_search_with_filters_combination(db_session, test_office):
    """検索 + フィルター + ソートの複合条件"""
    # TODO: 複合条件テストを実装
    pass
```

#### 2.7 パフォーマンステスト

**ファイル**: `k_back/tests/performance/test_dashboard_performance.py`（新規作成）

```python
import pytest
import time
from app.crud.crud_dashboard import crud_dashboard

@pytest.mark.asyncio
@pytest.mark.performance
async def test_search_performance_100_recipients(db_session, test_office):
    """100人の利用者に対する検索パフォーマンステスト"""
    # 100人の利用者を作成（フィクスチャで事前準備）

    start_time = time.time()

    results = await crud_dashboard.get_filtered_summaries(
        db_session,
        office_ids=[test_office.id],
        sort_by="name_phonetic",
        sort_order="asc",
        filters={},
        search_term="太郎",
        skip=0,
        limit=20
    )

    elapsed = time.time() - start_time

    # 目標: 100ms以内
    assert elapsed < 0.1, f"Search took {elapsed:.3f}s (target: <0.1s)"
```

#### 2.8 テスト項目

- [ ] pg_trgm拡張機能が有効化されている
- [ ] GINインデックスが作成されている
- [ ] あいまい検索が動作する
- [ ] 複数単語検索が動作する
- [ ] 検索 + フィルター + ソートの組み合わせが動作する
- [ ] 既存のテストが全てパス
- [ ] パフォーマンステストが目標値をクリア

**Phase 2 完了条件**:
- ✅ 全文検索インデックスが作成されている
- ✅ 検索・フィルター・ソートの複合条件が動作
- ✅ パフォーマンステストがパス
- ✅ 本番環境にデプロイ完了

---

### Phase 3: クエリ構造リファクタリング - CTE化

**目的**: サブクエリの統合によるスキャン回数削減

**期間**: 3-5日

**実装内容**:

#### 3.1 CRUDメソッドの再設計

**ファイル**: `k_back/app/crud/crud_dashboard.py`

**変更前** (71-89行目):
```python
# 1. サイクル総数をカウントするサブクエリ
cycle_count_sq = (
    select(
        SupportPlanCycle.welfare_recipient_id,
        func.count(SupportPlanCycle.id).label("cycle_count"),
    )
    .group_by(SupportPlanCycle.welfare_recipient_id)
    .subquery("cycle_count_sq")
)

# 2. 最新サイクルIDを取得するためのサブクエリ
latest_cycle_id_sq = (
    select(
        SupportPlanCycle.welfare_recipient_id,
        func.max(SupportPlanCycle.id).label("latest_cycle_id"),
    )
    .where(SupportPlanCycle.is_latest_cycle == true())
    .group_by(SupportPlanCycle.welfare_recipient_id)
    .subquery("latest_cycle_id_sq")
)
```

**変更後** (CTE使用):
```python
from sqlalchemy import select, func, and_, or_, true, case
from sqlalchemy.sql import expression as sql_expr

# 統合CTE: サイクル情報を1回のスキャンで取得
cycle_info_cte = (
    select(
        SupportPlanCycle.welfare_recipient_id,
        # サイクル総数
        func.count(SupportPlanCycle.id).label("cycle_count"),
        # 最新サイクルID
        func.max(
            case(
                (SupportPlanCycle.is_latest_cycle == True, SupportPlanCycle.id),
                else_=None
            )
        ).label("latest_cycle_id"),
        # 最新サイクルの更新期限（ソート用）
        func.max(
            case(
                (SupportPlanCycle.is_latest_cycle == True, SupportPlanCycle.next_renewal_deadline),
                else_=None
            )
        ).label("latest_renewal_deadline"),
    )
    .group_by(SupportPlanCycle.welfare_recipient_id)
    .cte("cycle_info")
)
```

#### 3.2 ステータスフィルター用CTE

```python
# ステータスフィルター用CTE（必要時のみ構築）
def _build_status_filter_cte(self, status_enum):
    """ステータスフィルター用CTEを構築"""
    return (
        select(
            SupportPlanStatus.plan_cycle_id,
            SupportPlanStatus.step_type.label("latest_step")
        )
        .where(
            and_(
                SupportPlanStatus.is_latest_status == True,
                SupportPlanStatus.step_type == status_enum
            )
        )
        .cte("latest_status")
    )
```

#### 3.3 メインクエリの再構築

```python
async def get_filtered_summaries(
    self,
    db: AsyncSession,
    *,
    office_ids: List[uuid.UUID],
    sort_by: str,
    sort_order: str,
    filters: dict,
    search_term: Optional[str],
    skip: int,
    limit: int,
) -> list:
    # CTE定義
    cycle_info_cte = self._build_cycle_info_cte()

    # メインクエリ構築
    stmt = (
        select(
            WelfareRecipient,
            func.coalesce(cycle_info_cte.c.cycle_count, 0).label("cycle_count"),
            SupportPlanCycle,
        )
        .join(
            OfficeWelfareRecipient,
            WelfareRecipient.id == OfficeWelfareRecipient.welfare_recipient_id
        )
        .where(OfficeWelfareRecipient.office_id.in_(office_ids))
        # CTEとJOIN
        .outerjoin(
            cycle_info_cte,
            WelfareRecipient.id == cycle_info_cte.c.welfare_recipient_id
        )
    )

    # 最新サイクル情報をJOIN（必要時のみ）
    if sort_by == "next_renewal_deadline" or filters:
        stmt = stmt.outerjoin(
            SupportPlanCycle,
            and_(
                SupportPlanCycle.id == cycle_info_cte.c.latest_cycle_id,
                SupportPlanCycle.is_latest_cycle == True
            )
        )

    # ステータスフィルター（必要時のみ）
    if filters.get("status"):
        try:
            status_enum = SupportPlanStep[filters["status"]]
            status_cte = self._build_status_filter_cte(status_enum)
            stmt = stmt.join(
                status_cte,
                SupportPlanCycle.id == status_cte.c.plan_cycle_id
            )
        except KeyError:
            pass

    # 検索条件
    search_condition = self._build_search_condition(search_term)
    if search_condition is not None:
        stmt = stmt.where(search_condition)

    # フィルター適用
    stmt = self._apply_filters(stmt, filters, cycle_info_cte)

    # ソート
    stmt = self._apply_sorting(stmt, sort_by, sort_order, cycle_info_cte)

    # selectinload（必要なもののみ）
    stmt = stmt.options(
        selectinload(SupportPlanCycle.statuses),
        selectinload(WelfareRecipient.support_plan_cycles).selectinload(SupportPlanCycle.statuses),
    )

    # ページネーション
    stmt = stmt.offset(skip).limit(limit)

    result = await db.execute(stmt)
    return result.all()

def _build_cycle_info_cte(self):
    """サイクル情報CTE構築"""
    # 上記のCTE定義
    pass

def _apply_filters(self, stmt, filters, cycle_info_cte):
    """フィルター適用"""
    if not filters:
        return stmt

    # 期限切れフィルター
    if filters.get("is_overdue"):
        stmt = stmt.where(
            cycle_info_cte.c.latest_renewal_deadline < date.today()
        )

    # 更新間近フィルター
    if filters.get("is_upcoming"):
        stmt = stmt.where(
            cycle_info_cte.c.latest_renewal_deadline.between(
                date.today(),
                date.today() + timedelta(days=30)
            )
        )

    # サイクル数フィルター
    if filters.get("cycle_number"):
        stmt = stmt.where(
            cycle_info_cte.c.cycle_count == filters["cycle_number"]
        )

    return stmt

def _apply_sorting(self, stmt, sort_by, sort_order, cycle_info_cte):
    """ソート適用"""
    order_func = None

    if sort_by == "name_phonetic":
        sort_column = func.concat(
            WelfareRecipient.last_name_furigana,
            WelfareRecipient.first_name_furigana
        )
        order_func = sort_column.desc() if sort_order == "desc" else sort_column.asc()

    elif sort_by == "created_at":
        sort_column = WelfareRecipient.created_at
        order_func = sort_column.desc() if sort_order == "desc" else sort_column.asc()

    elif sort_by == "next_renewal_deadline":
        # CTEから取得した更新期限でソート
        sort_column = cycle_info_cte.c.latest_renewal_deadline
        order_func = (
            sort_column.desc().nullslast()
            if sort_order == "desc"
            else sort_column.asc().nullslast()
        )

    if order_func is not None:
        stmt = stmt.order_by(order_func)
    else:
        # デフォルトソート
        default_sort_col = func.concat(
            WelfareRecipient.last_name_furigana,
            WelfareRecipient.first_name_furigana
        )
        stmt = stmt.order_by(default_sort_col.asc())

    return stmt
```

#### 3.4 `get_summary_counts()` の最適化

**変更前** (4回のクエリ実行):
```python
# 各カウントを個別に実行
total_res = await db.execute(...)
overdue_res = await db.execute(...)
upcoming_res = await db.execute(...)
no_cycle_res = await db.execute(...)
```

**変更後** (1回のクエリで全カウント取得):
```python
async def get_summary_counts(
    self,
    db: AsyncSession,
    office_ids: List[uuid.UUID],
) -> Dict[str, int]:
    """ダッシュボード用のサマリー件数を1クエリで集計"""
    today = date.today()
    upcoming_deadline = today + timedelta(days=30)

    # 1回のクエリで全カウントを取得
    stmt = (
        select(
            func.count().label("total_recipients"),
            func.sum(
                case(
                    (SupportPlanCycle.next_renewal_deadline < today, 1),
                    else_=0
                )
            ).label("overdue_count"),
            func.sum(
                case(
                    (
                        and_(
                            SupportPlanCycle.next_renewal_deadline >= today,
                            SupportPlanCycle.next_renewal_deadline <= upcoming_deadline
                        ),
                        1
                    ),
                    else_=0
                )
            ).label("upcoming_count"),
            func.sum(
                case(
                    (SupportPlanCycle.id == None, 1),
                    else_=0
                )
            ).label("no_cycle_count"),
        )
        .select_from(WelfareRecipient)
        .join(
            OfficeWelfareRecipient,
            WelfareRecipient.id == OfficeWelfareRecipient.welfare_recipient_id
        )
        .outerjoin(
            SupportPlanCycle,
            and_(
                WelfareRecipient.id == SupportPlanCycle.welfare_recipient_id,
                SupportPlanCycle.is_latest_cycle == True
            )
        )
        .where(OfficeWelfareRecipient.office_id.in_(office_ids))
    )

    result = await db.execute(stmt)
    row = result.one()

    return {
        "total_recipients": row.total_recipients or 0,
        "overdue_count": row.overdue_count or 0,
        "upcoming_count": row.upcoming_count or 0,
        "no_cycle_count": row.no_cycle_count or 0,
    }
```

#### 3.5 テスト項目

- [ ] 既存の全テストがパス
- [ ] CTE使用後もクエリ結果が変わらない（レグレッションテスト）
- [ ] パフォーマンステストで改善が確認できる
- [ ] `get_summary_counts()` が1クエリで実行されている（ログ確認）

**Phase 3 完了条件**:
- ✅ CTE化によるリファクタリング完了
- ✅ テストが全てパス
- ✅ パフォーマンス目標達成（500人で300ms以内）
- ✅ 本番環境にデプロイ完了

---

### Phase 4: 高度な最適化（オプション）

**目的**: 1000人超規模への対応

**期間**: 5-7日

**実装内容**:

#### 4.1 Materialized View の導入

**マイグレーション**: `k_back/alembic/versions/XXXXXX_add_dashboard_materialized_view.py`

```python
"""add dashboard materialized view

Revision ID: XXXXXX
Revises: YYYYYY
Create Date: 2026-02-06
"""
from alembic import op

def upgrade() -> None:
    # Materialized Viewの作成
    op.execute("""
        CREATE MATERIALIZED VIEW mv_dashboard_summary AS
        SELECT
            wr.id AS welfare_recipient_id,
            wr.last_name,
            wr.first_name,
            wr.last_name_furigana,
            wr.first_name_furigana,
            wr.created_at,
            owr.office_id,
            -- サイクル情報
            COUNT(spc.id) AS cycle_count,
            MAX(CASE WHEN spc.is_latest_cycle THEN spc.id END) AS latest_cycle_id,
            MAX(CASE WHEN spc.is_latest_cycle THEN spc.next_renewal_deadline END) AS latest_renewal_deadline,
            -- 最新ステータス
            (
                SELECT sps.step_type
                FROM support_plan_statuses sps
                WHERE sps.plan_cycle_id = MAX(CASE WHEN spc.is_latest_cycle THEN spc.id END)
                  AND sps.is_latest_status = true
                LIMIT 1
            ) AS latest_status_step
        FROM welfare_recipients wr
        INNER JOIN office_welfare_recipients owr ON wr.id = owr.welfare_recipient_id
        LEFT JOIN support_plan_cycles spc ON wr.id = spc.welfare_recipient_id
        WHERE wr.is_test_data = false
        GROUP BY wr.id, owr.office_id
        WITH DATA;

        -- インデックス作成
        CREATE INDEX idx_mv_dashboard_office_id ON mv_dashboard_summary(office_id);
        CREATE INDEX idx_mv_dashboard_renewal_deadline ON mv_dashboard_summary(latest_renewal_deadline);
        CREATE INDEX idx_mv_dashboard_status_step ON mv_dashboard_summary(latest_status_step);

        -- 全文検索インデックス
        CREATE INDEX idx_mv_dashboard_name_gin ON mv_dashboard_summary
        USING gin(
            (
                COALESCE(last_name, '') || ' ' ||
                COALESCE(first_name, '') || ' ' ||
                COALESCE(last_name_furigana, '') || ' ' ||
                COALESCE(first_name_furigana, '')
            ) gin_trgm_ops
        );
    """)

def downgrade() -> None:
    op.execute("DROP MATERIALIZED VIEW IF EXISTS mv_dashboard_summary;")
```

#### 4.2 定期更新バッチの追加

**ファイル**: `k_back/app/tasks/refresh_dashboard_view.py`（新規作成）

```python
"""ダッシュボードMaterialized View更新バッチ"""
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import AsyncSessionLocal
import logging

logger = logging.getLogger(__name__)

async def refresh_dashboard_materialized_view():
    """
    ダッシュボードのMaterialized Viewを更新する

    実行タイミング:
    - 毎日午前2時（バッチ処理）
    - 大量データ更新後（手動トリガー）
    """
    async with AsyncSessionLocal() as db:
        try:
            logger.info("ダッシュボードMaterialized View更新開始")

            # CONCURRENTLY オプションでロックを最小化
            await db.execute(
                "REFRESH MATERIALIZED VIEW CONCURRENTLY mv_dashboard_summary;"
            )
            await db.commit()

            logger.info("ダッシュボードMaterialized View更新完了")
        except Exception as e:
            logger.error(f"Materialized View更新エラー: {e}")
            await db.rollback()
            raise
```

#### 4.3 CRUD層でMaterialized Viewを使用

```python
async def get_filtered_summaries_from_mv(
    self,
    db: AsyncSession,
    *,
    office_ids: List[uuid.UUID],
    sort_by: str,
    sort_order: str,
    filters: dict,
    search_term: Optional[str],
    skip: int,
    limit: int,
) -> list:
    """Materialized Viewを使用した高速検索"""
    from sqlalchemy import text

    # ベースクエリ（Materialized Viewから取得）
    stmt = select(text("*")).select_from(text("mv_dashboard_summary"))
    stmt = stmt.where(text("office_id = ANY(:office_ids)"))

    # 検索条件
    # フィルター
    # ソート
    # ページネーション

    # 実行
    result = await db.execute(stmt, {"office_ids": office_ids})
    return result.all()
```

#### 4.4 テスト項目

- [ ] Materialized Viewが正しく作成される
- [ ] 更新バッチが動作する
- [ ] Materialized Viewからのクエリ結果が正しい
- [ ] パフォーマンス目標達成（1000人で100ms以内）

**Phase 4 完了条件**:
- ✅ Materialized View導入完了
- ✅ 定期更新バッチが動作
- ✅ 1000人規模でのパフォーマンステストがパス

---

## 📊 各フェーズの期待効果

| フェーズ | 対象利用者数 | レスポンスタイム（before） | レスポンスタイム（after） | 改善率 |
|---------|-------------|-------------------------|------------------------|-------|
| **Phase 1** | 100人 | 500ms | 100ms | 5倍 |
| **Phase 2** | 100人 | 100ms | 50ms | 2倍 |
| **Phase 3** | 500人 | 2000ms | 300ms | 6.7倍 |
| **Phase 4** | 1000人 | 推定5000ms | 100ms | 50倍 |

---

## 🧪 テスト戦略

### 単体テスト
- CRUD層の各メソッド
- 検索条件構築ロジック
- フィルター適用ロジック

### 統合テスト
- 検索 + フィルター + ソートの複合条件
- ページネーション
- selectinloadの動作確認

### パフォーマンステスト
```python
# tests/performance/test_dashboard_performance.py

@pytest.mark.performance
class TestDashboardPerformance:

    async def test_100_recipients_search(self, db_with_100_recipients):
        """100人規模での検索パフォーマンス"""
        # 目標: 100ms以内
        pass

    async def test_500_recipients_search(self, db_with_500_recipients):
        """500人規模での検索パフォーマンス"""
        # 目標: 300ms以内
        pass

    async def test_1000_recipients_search(self, db_with_1000_recipients):
        """1000人規模での検索パフォーマンス（Phase 4のみ）"""
        # 目標: 100ms以内
        pass

    async def test_complex_filter_combination(self, db_session):
        """複雑なフィルター組み合わせ"""
        # 検索 + ステータスフィルター + 期限フィルター + ソート
        pass
```

### レグレッションテスト
- 既存の全CRUDテストがパス
- 既存のAPIテストがパス
- クエリ結果の整合性確認

---

## 🚨 ロールバック戦略

### Phase 1のロールバック
```bash
# マイグレーション巻き戻し
alembic downgrade -1

# インデックス削除
psql $DATABASE_URL -c "DROP INDEX IF EXISTS idx_support_plan_statuses_latest_step;"
psql $DATABASE_URL -c "DROP INDEX IF EXISTS idx_office_welfare_recipients_composite;"
```

### Phase 2のロールバック
```bash
# マイグレーション巻き戻し
alembic downgrade -1

# コード変更の巻き戻し（Gitリバート）
git revert <commit_hash>
```

### Phase 3のロールバック
```bash
# コード変更の巻き戻し
git revert <commit_hash>

# 緊急時: 旧メソッドの復活
# crud_dashboard.py の get_filtered_summaries_legacy() に切り替え
```

### Phase 4のロールバック
```bash
# Materialized View削除
psql $DATABASE_URL -c "DROP MATERIALIZED VIEW IF EXISTS mv_dashboard_summary;"

# マイグレーション巻き戻し
alembic downgrade -1
```

---

## 📋 チェックリスト

### Phase 1
- [ ] マイグレーションファイル作成
- [ ] ローカル環境でマイグレーション適用
- [ ] インデックス作成確認
- [ ] 既存テストがパス
- [ ] パフォーマンス改善確認
- [ ] 本番環境デプロイ

### Phase 2
- [ ] pg_trgm拡張機能有効化
- [ ] マイグレーションファイル作成
- [ ] CRUD層改修
- [ ] テスト追加
- [ ] 既存テストがパス
- [ ] パフォーマンステストがパス
- [ ] 本番環境デプロイ

### Phase 3
- [ ] CRUDメソッドリファクタリング
- [ ] CTE導入
- [ ] `get_summary_counts()` 最適化
- [ ] レグレッションテスト
- [ ] パフォーマンステストがパス
- [ ] 本番環境デプロイ

### Phase 4（オプション）
- [ ] Materialized View作成
- [ ] 更新バッチ実装
- [ ] CRUD層での使用実装
- [ ] テスト追加
- [ ] 本番環境デプロイ

---

## 📌 注意事項

1. **Phase 1は最優先**: インデックス追加だけで大幅な改善が見込める
2. **段階的デプロイ**: 各フェーズごとに本番デプロイし、効果を確認
3. **パフォーマンス計測**: 各フェーズの前後でベンチマークを取得
4. **ロールバック準備**: 問題発生時は即座にロールバック可能にする
5. **Phase 4は慎重に**: Materialized Viewは更新遅延が発生するため、要件確認が必要

---

## 📚 参考資料

- PostgreSQL公式ドキュメント: https://www.postgresql.org/docs/current/indexes.html
- pg_trgm公式ドキュメント: https://www.postgresql.org/docs/current/pgtrgm.html
- SQLAlchemy CTE: https://docs.sqlalchemy.org/en/20/core/selectable.html#sqlalchemy.sql.expression.CTE
- Materialized Views: https://www.postgresql.org/docs/current/rules-materializedviews.html

---

**最終更新**: 2026-02-06
**作成者**: Claude Sonnet 4.5
