# ダッシュボードフィルター機能 - 改善要件定義

## ドキュメント情報
- 作成日: 2026-02-15
- バージョン: 1.0
- 関連ドキュメント: `01_current_state_analysis.md`

---

## 🎯 改善目標

### パフォーマンス目標

| 指標 | 現状 | 目標 | 改善率 |
|------|------|------|--------|
| **ダッシュボード初期表示** | 3-5秒 | 300-500ms | **10倍** |
| **フィルタリング応答** | 2-3秒 | 200-300ms | **10倍** |
| **メモリ使用量** | 50MB | 5MB | **90%削減** |
| **同時実行可能数** | 10リクエスト | 100リクエスト | **10倍** |

### スケーラビリティ目標

- ✅ **500事業所** × 100利用者 = 50,000レコードで快適動作
- ✅ **1,000事業所** × 100利用者 = 100,000レコードでも許容範囲
- ✅ **レスポンス時間**が利用者数に対して線形増加しない

---

## 📋 Phase 1: クエリ最適化（優先度: 最高）

### 1.1 COUNT(*) クエリへの変更

#### 対象ファイル
`k_back/app/api/v1/endpoints/dashboard.py` (Line 43-44)

#### 現在のコード
```python
all_recipients = await crud.office.get_recipients_by_office_id(db=db, office_id=office.id)
current_user_count = len(all_recipients)
```

#### 改善後のコード
```python
# 専用のcount メソッドを使用
current_user_count = await crud.dashboard.count_office_recipients(
    db=db,
    office_id=office.id
)
```

#### 実装詳細

**CRUD実装** (`crud_dashboard.py` に既に存在 - Line 45-56):
```python
async def count_office_recipients(self, db: AsyncSession, *, office_id: uuid.UUID) -> int:
    """
    指定された事業所の利用者数を取得します。
    """
    query = (
        select(func.count())
        .select_from(WelfareRecipient)
        .join(OfficeWelfareRecipient)
        .where(OfficeWelfareRecipient.office_id == office_id)
    )
    result = await db.execute(query)
    return result.scalar_one()
```

#### テスト要件
```python
async def test_count_office_recipients_performance():
    """COUNT(*)クエリのパフォーマンステスト"""
    # 500事業所 × 100利用者のデータを作成
    # クエリ時間が100ms以下であることを確認
    start = time.time()
    count = await crud.dashboard.count_office_recipients(db, office_id=office.id)
    elapsed = time.time() - start

    assert elapsed < 0.1  # 100ms以下
    assert count == 100
```

#### 期待効果
- メモリ使用量: 50MB → 1KB（99.998%削減）
- クエリ時間: 500ms → 10ms（50倍高速化）
- **実装工数**: 10分（既存メソッド利用のため変更のみ）

---

### 1.2 サブクエリの統合

#### 対象ファイル
`k_back/app/crud/crud_dashboard.py` (Line 70-89)

#### 現在のコード
```python
# 2つのサブクエリが独立実行
cycle_count_sq = (
    select(
        SupportPlanCycle.welfare_recipient_id,
        func.count(SupportPlanCycle.id).label("cycle_count"),
    )
    .group_by(SupportPlanCycle.welfare_recipient_id)
    .subquery("cycle_count_sq")
)

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

#### 改善後のコード
```python
# 1つのサブクエリに統合
cycle_info_sq = (
    select(
        SupportPlanCycle.welfare_recipient_id,
        func.count(SupportPlanCycle.id).label("cycle_count"),
        func.max(
            func.case(
                (SupportPlanCycle.is_latest_cycle == true(), SupportPlanCycle.id),
                else_=None
            )
        ).label("latest_cycle_id")
    )
    .group_by(SupportPlanCycle.welfare_recipient_id)
    .subquery("cycle_info_sq")
)
```

#### メインクエリの変更
```python
# 変更前（Line 92-106）
stmt = select(
    WelfareRecipient,
    func.coalesce(cycle_count_sq.c.cycle_count, 0).label("cycle_count"),
    SupportPlanCycle,
).join(OfficeWelfareRecipient).where(...)

stmt = stmt.outerjoin(cycle_count_sq, ...)
stmt = stmt.outerjoin(latest_cycle_id_sq, ...)
stmt = stmt.outerjoin(SupportPlanCycle, SupportPlanCycle.id == latest_cycle_id_sq.c.latest_cycle_id)

# 変更後
stmt = select(
    WelfareRecipient,
    func.coalesce(cycle_info_sq.c.cycle_count, 0).label("cycle_count"),
    SupportPlanCycle,
).join(OfficeWelfareRecipient).where(...)

stmt = stmt.outerjoin(cycle_info_sq, WelfareRecipient.id == cycle_info_sq.c.welfare_recipient_id)
stmt = stmt.outerjoin(SupportPlanCycle, SupportPlanCycle.id == cycle_info_sq.c.latest_cycle_id)
```

#### SQL実行計画の改善

**変更前**:
```sql
-- 2つのサブクエリが独立実行
WITH cycle_count_sq AS (
    SELECT welfare_recipient_id, COUNT(*) as cycle_count
    FROM support_plan_cycles
    GROUP BY welfare_recipient_id
),
latest_cycle_id_sq AS (
    SELECT welfare_recipient_id, MAX(id) as latest_cycle_id
    FROM support_plan_cycles
    WHERE is_latest_cycle = true
    GROUP BY welfare_recipient_id
)
SELECT ...
```

**変更後**:
```sql
-- 1つのサブクエリで両方の情報を取得
WITH cycle_info_sq AS (
    SELECT
        welfare_recipient_id,
        COUNT(*) as cycle_count,
        MAX(CASE WHEN is_latest_cycle THEN id END) as latest_cycle_id
    FROM support_plan_cycles
    GROUP BY welfare_recipient_id
)
SELECT ...
```

#### テスト要件
```python
async def test_subquery_integration():
    """統合サブクエリの動作テスト"""
    results = await crud.dashboard.get_filtered_summaries(
        db=db,
        office_ids=[office_id],
        sort_by='next_renewal_deadline',
        sort_order='asc',
        filters={},
        search_term=None,
        skip=0,
        limit=100
    )

    for recipient, cycle_count, latest_cycle in results:
        # cycle_countが正しい
        assert cycle_count == len(recipient.support_plan_cycles)

        # latest_cycleがis_latest_cycle=trueのサイクルである
        if latest_cycle:
            assert latest_cycle.is_latest_cycle == True
```

#### 期待効果
- サブクエリ実行: 2回 → 1回（50%削減）
- GROUP BY 操作: 2回 → 1回（50%削減）
- クエリ時間: 200ms → 120ms（40%高速化）
- **実装工数**: 2時間

---

### 1.3 JOIN戦略の統一

#### 対象ファイル
`k_back/app/crud/crud_dashboard.py` (Line 101-106)

#### 現在のコード
```python
if sort_by == "next_renewal_deadline":
    stmt = stmt.join(latest_cycle_id_sq, ...)
    stmt = stmt.join(SupportPlanCycle, ...)
else:
    stmt = stmt.outerjoin(latest_cycle_id_sq, ...)
    stmt = stmt.outerjoin(SupportPlanCycle, ...)
```

#### 改善後のコード
```python
# 常にOUTER JOINを使用（条件分岐を削除）
stmt = stmt.outerjoin(
    cycle_info_sq,
    WelfareRecipient.id == cycle_info_sq.c.welfare_recipient_id
)
stmt = stmt.outerjoin(
    SupportPlanCycle,
    SupportPlanCycle.id == cycle_info_sq.c.latest_cycle_id
)
```

#### NULLハンドリングの改善
```python
# ソート時のNULL処理を明示的に
if sort_by == "next_renewal_deadline":
    sort_column = SupportPlanCycle.next_renewal_deadline
    # 昇順: 期限がある利用者を優先、NULLは最後
    order_func = sort_column.asc().nullslast() if sort_order == "asc" else sort_column.desc().nullslast()
```

#### 期待効果
- コードの簡潔化（条件分岐削除）
- クエリプランの一貫性向上
- 最新サイクルがない利用者も正しく表示
- **実装工数**: 30分

---

## 📋 Phase 2: 複合インデックスの追加（優先度: 最高）

### 2.1 最新サイクル検索の最適化

#### インデックス定義
```sql
CREATE INDEX idx_support_plan_cycles_recipient_latest
ON support_plan_cycles (welfare_recipient_id, is_latest_cycle)
WHERE is_latest_cycle = true;
```

#### 適用されるクエリ
- `cycle_info_sq` サブクエリ（統合後）
- `latest_cycle_id_sq` サブクエリ（統合前）

#### マイグレーションファイル
```python
# alembic/versions/YYYYMMDD_add_dashboard_indexes.py
"""add dashboard performance indexes

Revision ID: xxxxx
Revises: xxxxx
Create Date: 2026-02-15

"""
from alembic import op

def upgrade():
    # 最新サイクル検索用の部分インデックス
    op.execute("""
        CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_support_plan_cycles_recipient_latest
        ON support_plan_cycles (welfare_recipient_id, is_latest_cycle)
        WHERE is_latest_cycle = true
    """)

def downgrade():
    op.execute("DROP INDEX IF EXISTS idx_support_plan_cycles_recipient_latest")
```

#### 期待効果
- インデックススキャン: フルスキャン → 部分インデックス
- クエリ時間: 500ms → 50ms（10倍高速化）
- 対象レコード: 50,000 → 5,000（is_latest_cycle=trueのみ）
- **実装工数**: 15分

---

### 2.2 最新ステータス検索の最適化

#### インデックス定義
```sql
CREATE INDEX idx_support_plan_statuses_cycle_latest
ON support_plan_statuses (plan_cycle_id, is_latest_status, step_type)
WHERE is_latest_status = true;
```

#### 適用されるクエリ
- ステータスフィルター（Line 135-147）
- `selectinload(SupportPlanCycle.statuses)` の暗黙的WHERE句

#### マイグレーション
```python
def upgrade():
    # 最新ステータス検索用の部分インデックス
    op.execute("""
        CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_support_plan_statuses_cycle_latest
        ON support_plan_statuses (plan_cycle_id, is_latest_status, step_type)
        WHERE is_latest_status = true
    """)

def downgrade():
    op.execute("DROP INDEX IF EXISTS idx_support_plan_statuses_cycle_latest")
```

#### 期待効果
- ステータスフィルター: 300ms → 30ms（10倍高速化）
- `selectinload` サブクエリ: 500ms → 50ms（10倍高速化）
- **実装工数**: 15分

---

### 2.3 ふりがなソートの最適化

#### インデックス定義
```sql
CREATE INDEX idx_welfare_recipients_furigana
ON welfare_recipients (last_name_furigana, first_name_furigana);
```

#### 適用されるクエリ
- `ORDER BY CONCAT(last_name_furigana, first_name_furigana)`
- デフォルトソート

#### マイグレーション
```python
def upgrade():
    # ふりがなソート用のインデックス
    op.execute("""
        CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_welfare_recipients_furigana
        ON welfare_recipients (last_name_furigana, first_name_furigana)
    """)

def downgrade():
    op.execute("DROP INDEX IF EXISTS idx_welfare_recipients_furigana")
```

#### 期待効果
- ソート操作: メモリソート → インデックススキャン
- クエリ時間: 200ms → 20ms（10倍高速化）
- **実装工数**: 10分

---

### 2.4 事業所別利用者検索の最適化

#### インデックス定義
```sql
CREATE INDEX idx_office_welfare_recipients_office
ON office_welfare_recipients (office_id, welfare_recipient_id);
```

#### 適用されるクエリ
- `WHERE office_id IN (...)`
- 事業所フィルター

#### マイグレーション
```python
def upgrade():
    # 事業所別検索用のインデックス
    op.execute("""
        CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_office_welfare_recipients_office
        ON office_welfare_recipients (office_id, welfare_recipient_id)
    """)

def downgrade():
    op.execute("DROP INDEX IF EXISTS idx_office_welfare_recipients_office")
```

#### 期待効果
- 事業所フィルター: 100ms → 10ms（10倍高速化）
- **実装工数**: 10分

---

## 📋 Phase 3: selectinload 最適化（優先度: 高）

### 3.1 フィルタリング条件の追加

#### 対象ファイル
`k_back/app/crud/crud_dashboard.py` (Line 108-112)

#### 現在のコード
```python
stmt = stmt.options(
    selectinload(SupportPlanCycle.statuses),
    selectinload(WelfareRecipient.support_plan_cycles).selectinload(SupportPlanCycle.statuses),
    selectinload(SupportPlanCycle.deliverables)
)
```

#### 改善後のコード
```python
from sqlalchemy.orm import contains_eager

stmt = stmt.options(
    # 最新ステータスのみをロード
    selectinload(SupportPlanCycle.statuses).where(
        SupportPlanStatus.is_latest_status == true()
    ),
    # next_plan_start_days_remaining計算用の最小限のサイクル
    selectinload(WelfareRecipient.support_plan_cycles).where(
        or_(
            SupportPlanCycle.is_latest_cycle == true(),
            SupportPlanCycle.cycle_number == SupportPlanCycle.cycle_number - 1
        )
    ).selectinload(SupportPlanCycle.statuses).where(
        and_(
            SupportPlanStatus.step_type == SupportPlanStep.final_plan_signed,
            SupportPlanStatus.completed == true()
        )
    ),
    # アセスメントPDFのみをロード
    selectinload(SupportPlanCycle.deliverables).where(
        SupportPlanDeliverable.deliverable_type == DeliverableType.assessment_sheet
    )
)
```

#### 期待効果
- ロードするステータス数: 500 → 100（80%削減）
- ロードするサイクル数: 500 → 200（60%削減）
- ロードするデリバラブル数: 1000 → 50（95%削減）
- メモリ使用量: 10MB → 2MB（80%削減）
- クエリ時間: 2000ms → 500ms（75%高速化）
- **実装工数**: 3時間

---

### 3.2 EXISTS句への変更

#### 対象ファイル
`k_back/app/crud/crud_dashboard.py` (Line 135-147)

#### 現在のコード
```python
latest_status_subq = select(
    SupportPlanStatus.plan_cycle_id,
    SupportPlanStatus.step_type.label("latest_step")
).where(SupportPlanStatus.is_latest_status == true()).subquery()

stmt = stmt.join(latest_status_subq, SupportPlanCycle.id == latest_status_subq.c.plan_cycle_id)
stmt = stmt.where(latest_status_subq.c.latest_step == status_enum)
```

#### 改善後のコード
```python
from sqlalchemy import exists

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

#### SQL実行計画の改善

**変更前**:
```sql
-- サブクエリ + JOINアプローチ
SELECT ...
FROM welfare_recipients wr
LEFT JOIN (
    SELECT plan_cycle_id, step_type as latest_step
    FROM support_plan_statuses
    WHERE is_latest_status = true
) latest_status ON spc.id = latest_status.plan_cycle_id
WHERE latest_status.latest_step = 'assessment'
```

**変更後**:
```sql
-- EXISTS句アプローチ（より効率的）
SELECT ...
FROM welfare_recipients wr
WHERE EXISTS (
    SELECT 1
    FROM support_plan_statuses sps
    WHERE sps.plan_cycle_id = spc.id
    AND sps.is_latest_status = true
    AND sps.step_type = 'assessment'
)
```

#### 期待効果
- クエリプランの単純化
- 早期終了（マッチした時点で次へ）
- クエリ時間: 300ms → 210ms（30%高速化）
- **実装工数**: 1時間

---

## 📊 総合的な改善効果

### パフォーマンス改善サマリー

| フェーズ | 改善項目 | 改善率 | 実装工数 |
|---------|---------|--------|----------|
| Phase 1 | COUNT(*)クエリ | 50倍 | 10分 |
| Phase 1 | サブクエリ統合 | 40%高速化 | 2時間 |
| Phase 1 | JOIN統一 | コード改善 | 30分 |
| Phase 2 | 最新サイクルINDEX | 10倍 | 15分 |
| Phase 2 | 最新ステータスINDEX | 10倍 | 15分 |
| Phase 2 | ふりがなソートINDEX | 10倍 | 10分 |
| Phase 2 | 事業所検索INDEX | 10倍 | 10分 |
| Phase 3 | selectinload最適化 | 75%高速化 | 3時間 |
| Phase 3 | EXISTS句変更 | 30%高速化 | 1時間 |
| **合計** | - | **約10倍** | **7時間40分** |

### レスポンス時間の改善

| シナリオ | 現状 | 改善後 | 改善率 |
|---------|------|--------|--------|
| ダッシュボード初期表示 | 3-5秒 | 300-500ms | **10倍** |
| フィルタリング（期限切れ） | 2-3秒 | 200-300ms | **10倍** |
| ソート（ふりがな） | 1-2秒 | 100-200ms | **10倍** |
| 検索（氏名） | 2-4秒 | 200-400ms | **10倍** |

---

## ✅ 受け入れ基準

### 機能要件
- ✅ すべてのフィルターが正しく動作する
- ✅ 複合条件（AND）が正しく適用される
- ✅ ソート順が正しく機能する
- ✅ ページネーションが正しく動作する

### 非機能要件
- ✅ **500事業所 × 100利用者**でレスポンス時間 < 500ms
- ✅ **同時10リクエスト**で安定動作
- ✅ **メモリ使用量** < 10MB/リクエスト
- ✅ **データベースCPU使用率** < 50%

### テスト要件
- ✅ ユニットテスト: 全テストPASS
- ✅ パフォーマンステスト: 目標値達成
- ✅ 負荷テスト: 100同時リクエストで安定
- ✅ 回帰テスト: 既存機能に影響なし

---

## 📅 実装スケジュール

### Week 1: Phase 1 + Phase 2（3時間）

| Day | タスク | 工数 | 担当 |
|-----|--------|------|------|
| Day 1 | COUNT(*)クエリ化 | 10分 | Backend |
| Day 1 | サブクエリ統合 | 2時間 | Backend |
| Day 1 | JOIN統一 | 30分 | Backend |
| Day 1 | インデックス追加（4件） | 50分 | Backend |

### Week 2: Phase 3（4時間40分）

| Day | タスク | 工数 | 担当 |
|-----|--------|------|------|
| Day 2 | selectinload最適化 | 3時間 | Backend |
| Day 2 | EXISTS句変更 | 1時間 | Backend |
| Day 2 | テスト実装 | 40分 | Backend |

### Week 3: テスト・デプロイ（2時間）

| Day | タスク | 工数 | 担当 |
|-----|--------|------|------|
| Day 3 | パフォーマンステスト | 1時間 | Backend |
| Day 3 | 負荷テスト | 30分 | Backend |
| Day 3 | デプロイ | 30分 | DevOps |

**総工数**: 9時間40分（約1.5日）

---

## 🔗 関連ドキュメント

- [現状分析](./01_current_state_analysis.md)
- [実装ガイド](./03_implementation_guide.md)（次に作成）
- [テスト計画](./04_test_plan.md)（次に作成）
