# ダッシュボード検索・フィルタリング機能要件

## 概要
利用者ダッシュボードでの複合条件検索とフィルタリング機能を改善する。

## 現在の問題点

### 1. 複合条件が正しく機能していない
- 現象: 検索やフィルタリングを行うと、以前の結果がリセットされる
- 原因: フロントエンド側で状態管理が不十分
- 期待動作: 複数の条件を組み合わせて絞り込みができる

### 2. 利用者数の表示が不正確
- 現象: フィルタリング後の利用者数が `current_user_count` として表示される
- 問題: 総利用者数と検索結果数が区別されていない
- 期待動作:
  - 総利用者数（フィルタリングに関わらず固定）
  - 検索結果数（フィルタリング後の件数）

### 3. UI/UXの改善が必要
- 「期限間近」「期限切れ」が何を指すか不明確
- モニタリング期限と次回更新期限が混在している

---

## 実装状況

### バックエンド（k_back）

#### APIエンドポイント
`GET /api/v1/dashboard/` (`k_back/app/api/v1/endpoints/dashboard.py`)

**クエリパラメータ**:
```python
search_term: Optional[str] = None       # 名前検索
sort_by: str = 'name_phonetic'          # ソート項目
sort_order: str = 'asc'                 # ソート順
is_overdue: Optional[bool] = None       # 期限切れフィルタ
is_upcoming: Optional[bool] = None      # 期限間近フィルタ
status: Optional[str] = None            # ステータスフィルタ
cycle_number: Optional[int] = None      # サイクル番号フィルタ
skip: int = 0                           # ページネーション
limit: int = 100                        # ページネーション
```

#### レスポンススキーマ
`DashboardData` (`k_back/app/schemas/dashboard.py`)

```python
{
  "staff_name": str,
  "staff_role": StaffRole,
  "office_id": UUID,
  "office_name": str,
  "current_user_count": int,  # ← 問題: 総利用者数が検索結果数になっている
  "max_user_count": int,
  "billing_status": BillingStatus,
  "recipients": List[DashboardSummary]  # ← フィルタリング後のリスト
}
```

`DashboardSummary`:
```python
{
  "id": str,
  "full_name": str,
  "furigana": Optional[str],
  "current_cycle_number": int,
  "latest_step": Optional[SupportPlanStep],
  "next_renewal_deadline": Optional[date],  # 次回更新期限（6ヶ月）
  "monitoring_due_date": Optional[date],    # モニタリング期限
  "monitoring_deadline": Optional[int]      # モニタリング期限（日数）
}
```

#### CRUD実装
`CRUDDashboard` (`k_back/app/crud/crud_dashboard.py`)

**主要メソッド**:
- `get_filtered_summaries()`: フィルタリングとソートを適用した利用者リストを取得
- `count_office_recipients()`: 事業所の総利用者数を取得（Line 45-56）

**フィルタリング実装** (Line 123-143):
```python
if filters.get("is_overdue"):
    stmt = stmt.where(SupportPlanCycle.next_renewal_deadline < date.today())
if filters.get("is_upcoming"):
    stmt = stmt.where(
        SupportPlanCycle.next_renewal_deadline.between(
            date.today(),
            date.today() + timedelta(days=30)
        )
    )
```

**ソート実装** (Line 145-161):
- `name_phonetic`: ふりがな昇順/降順
- `next_renewal_deadline`: 次回更新期限昇順/降順（NULLS FIRST/LAST対応）
- `created_at`: 作成日昇順/降順

### フロントエンド（k_front）

#### 実装ファイル
`k_front/components/protected/dashboard/Dashboard.tsx`

**状態管理**:
```typescript
const [searchTerm, setSearchTerm] = useState('');
const [sortBy, setSortBy] = useState('name_phonetic');
const [sortOrder, setSortOrder] = useState<'asc' | 'desc'>('asc');
const [activeFilters, setActiveFilters] = useState({
  isOverdue: false,
  isUpcoming: false,
  status: null,
});
```

**問題点**:
- `current_user_count` が検索結果数を表示してしまう（Line 42: `all_recipients` の長さ）
- フィルタリング前の総利用者数が保持されていない

---

## 改善要件

### 1. 総利用者数と検索結果数の分離

#### バックエンド

##### スキーマ変更
`DashboardData` に `filtered_count` を追加:

```python
class DashboardData(DashboardBase):
    """ダッシュボード情報（レスポンス）"""
    current_user_count: int      # 総利用者数（常に固定）
    filtered_count: int           # 検索結果数（新規追加）
    recipients: List[DashboardSummary]
```

##### API実装変更
`k_back/app/api/v1/endpoints/dashboard.py`:

```python
@router.get("/", response_model=schemas.dashboard.DashboardData)
async def get_dashboard(...):
    # 1. 総利用者数を取得（フィルタリングに関わらず固定）
    current_user_count = await crud.dashboard.count_office_recipients(
        db=db,
        office_id=office.id
    )

    # 2. フィルタリング後のリストを取得
    filtered_results = await crud.dashboard.get_filtered_summaries(...)

    # 3. フィルタリング後の件数をカウント
    filtered_count = len(filtered_results)

    return schemas.dashboard.DashboardData(
        current_user_count=current_user_count,  # 総利用者数（常に固定）
        filtered_count=filtered_count,          # 検索結果数
        recipients=recipient_summaries
    )
```

#### フロントエンド

##### 表示変更
```typescript
// 総利用者数の表示（常に固定）
<div>総利用者数: {dashboardData.current_user_count}名</div>

// 検索結果数の表示（フィルタリング後）
{dashboardData.filtered_count !== dashboardData.current_user_count && (
  <div>検索結果: {dashboardData.filtered_count}名</div>
)}
```

---

### 2. フィルターの明確化

#### UI/UX改善

##### 現在のフィルター名
- ❌ 「期限切れ」 → 何の期限か不明
- ❌ 「期限間近」 → 何の期限か不明

##### 改善後のフィルター名
- ✅ 「計画期限切れ」 (`is_overdue`) - 次回更新期限が現在日時を超過
- ✅ 「計画期限間近（残り1ヶ月）」 (`is_upcoming`) - 次回更新期限まで30日以内
- ✅ 「モニタリング期限」 (`has_monitoring_due`) - モニタリング期限が設定されている（新規追加）

#### バックエンド: モニタリングフィルター追加

##### クエリパラメータ追加
```python
has_monitoring_due: Optional[bool] = None  # モニタリング期限が設定されている
```

##### CRUD実装追加
`k_back/app/crud/crud_dashboard.py`:

```python
if filters.get("has_monitoring_due"):
    # monitoring_due_date が設定されていて、未完了のモニタリングがある
    monitoring_subquery = (
        select(SupportPlanStatus.plan_cycle_id)
        .where(
            and_(
                SupportPlanStatus.step_type == SupportPlanStep.MONITORING,
                SupportPlanStatus.completed == False,
                SupportPlanStatus.due_date.isnot(None)
            )
        )
    )
    stmt = stmt.where(SupportPlanCycle.id.in_(monitoring_subquery))
```

---

### 3. デフォルトソート順の変更

#### 現在の実装
- デフォルト: `name_phonetic`（ふりがな昇順）

#### 改善後
- デフォルト: `next_renewal_deadline`（次回更新期限昇順、NULLは最後）
- 理由: 期限が近い利用者を優先的に表示

##### バックエンド変更
`k_back/app/api/v1/endpoints/dashboard.py`:

```python
@router.get("/", response_model=schemas.dashboard.DashboardData)
async def get_dashboard(
    sort_by: str = 'next_renewal_deadline',  # デフォルトを変更
    sort_order: str = 'asc',
    ...
):
```

##### フロントエンド変更
`k_front/components/protected/dashboard/Dashboard.tsx`:

```typescript
const [sortBy, setSortBy] = useState('next_renewal_deadline');  // デフォルトを変更
```

---

### 4. フィルタリングの詳細仕様

#### 複合条件の動作

**AND条件**（すべて満たす）:
- 名前検索 + 計画期限切れ + モニタリング期限
- 各条件は独立してON/OFFできる

**実装例**:
```python
# バックエンド
conditions = []
if search_term:
    conditions.append(...)
if filters.get("is_overdue"):
    conditions.append(SupportPlanCycle.next_renewal_deadline < date.today())
if filters.get("is_upcoming"):
    conditions.append(SupportPlanCycle.next_renewal_deadline.between(...))
if filters.get("has_monitoring_due"):
    conditions.append(...)

stmt = stmt.where(and_(*conditions))
```

---

## 実装タスク

### Phase 1: バックエンド改修（1週間）

| タスク | 詳細 | 工数 |
|--------|------|------|
| スキーマ拡張 | `DashboardData`に`filtered_count`追加 | 1時間 |
| API実装変更 | 総利用者数と検索結果数を分離 | 2時間 |
| モニタリングフィルター追加 | `has_monitoring_due`パラメータ実装 | 3時間 |
| デフォルトソート変更 | `next_renewal_deadline`をデフォルトに | 1時間 |
| テスト | ユニットテスト、統合テスト | 4時間 |

**小計**: 11時間（約1.5日）

### Phase 2: フロントエンド改修（1週間）

| タスク | 詳細 | 工数 |
|--------|------|------|
| 型定義更新 | `DashboardData`型に`filtered_count`追加 | 0.5時間 |
| UI改修 | 総利用者数と検索結果数の表示 | 2時間 |
| フィルター名変更 | 「計画期限切れ」「計画期限間近」に変更 | 1時間 |
| モニタリングフィルター追加 | UIにモニタリング期限フィルターを追加 | 2時間 |
| デフォルトソート変更 | 初期表示を次回更新期限昇順に | 0.5時間 |
| テスト | E2Eテスト | 3時間 |

**小計**: 9時間（約1日）

### Phase 3: テスト・デプロイ（0.5週間）

| タスク | 詳細 | 工数 |
|--------|------|------|
| 統合テスト | バックエンド + フロントエンド連携 | 3時間 |
| UIテスト | 複合条件検索の動作確認 | 2時間 |
| デプロイ | 本番環境へのデプロイ | 1時間 |

**小計**: 6時間（約1日）

**総実装期間**: 約3.5日

---

## 実装と要件の差異まとめ

| 項目 | 現在の実装 | 改善後 | 優先度 |
|------|-----------|--------|--------|
| 総利用者数 | 検索結果数が表示される | 総利用者数（固定）と検索結果数を分離 | 高 |
| フィルター名 | 「期限切れ」「期限間近」 | 「計画期限切れ」「計画期限間近」 | 中 |
| モニタリングフィルター | なし | モニタリング期限フィルター追加 | 中 |
| デフォルトソート | ふりがな昇順 | 次回更新期限昇順 | 低 |
| 複合条件 | 状態管理が不十分 | AND条件で複数フィルターを適用 | 高 |

---

## データベースクエリ例

### 総利用者数取得（フィルタリング無視）
```sql
SELECT COUNT(*)
FROM welfare_recipients wr
JOIN office_welfare_recipients owr ON wr.id = owr.welfare_recipient_id
WHERE owr.office_id = :office_id
```

### フィルタリング後の利用者リスト取得
```sql
SELECT
    wr.*,
    COALESCE(cycle_count_sq.cycle_count, 0) as cycle_count,
    spc.*
FROM welfare_recipients wr
JOIN office_welfare_recipients owr ON wr.id = owr.welfare_recipient_id
LEFT JOIN (
    SELECT welfare_recipient_id, COUNT(*) as cycle_count
    FROM support_plan_cycles
    GROUP BY welfare_recipient_id
) cycle_count_sq ON wr.id = cycle_count_sq.welfare_recipient_id
LEFT JOIN support_plan_cycles spc ON wr.id = spc.welfare_recipient_id AND spc.is_latest_cycle = true
WHERE
    owr.office_id = :office_id
    -- 名前検索
    AND (
        :search_term IS NULL OR
        wr.last_name ILIKE '%' || :search_term || '%' OR
        wr.first_name ILIKE '%' || :search_term || '%' OR
        wr.last_name_furigana ILIKE '%' || :search_term || '%' OR
        wr.first_name_furigana ILIKE '%' || :search_term || '%'
    )
    -- 計画期限切れ
    AND (:is_overdue IS NULL OR spc.next_renewal_deadline < CURRENT_DATE)
    -- 計画期限間近（残り30日）
    AND (:is_upcoming IS NULL OR spc.next_renewal_deadline BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days')
    -- モニタリング期限
    AND (
        :has_monitoring_due IS NULL OR
        spc.id IN (
            SELECT plan_cycle_id
            FROM support_plan_statuses
            WHERE step_type = 'MONITORING'
            AND completed = false
            AND due_date IS NOT NULL
        )
    )
ORDER BY
    CASE WHEN :sort_by = 'next_renewal_deadline' AND :sort_order = 'asc'
        THEN spc.next_renewal_deadline END ASC NULLS FIRST,
    CASE WHEN :sort_by = 'next_renewal_deadline' AND :sort_order = 'desc'
        THEN spc.next_renewal_deadline END DESC NULLS LAST,
    CASE WHEN :sort_by = 'name_phonetic' AND :sort_order = 'asc'
        THEN CONCAT(wr.last_name_furigana, wr.first_name_furigana) END ASC,
    CASE WHEN :sort_by = 'name_phonetic' AND :sort_order = 'desc'
        THEN CONCAT(wr.last_name_furigana, wr.first_name_furigana) END DESC
LIMIT :limit OFFSET :skip
```

---

## テスト要件

### バックエンドテスト

#### ユニットテスト
- `count_office_recipients()` が正しい件数を返すこと
- `get_filtered_summaries()` の各フィルター条件が正しく動作すること
- 複合条件（AND）が正しく機能すること

#### 統合テスト
- APIエンドポイントが正しいレスポンスを返すこと
- `current_user_count` が常に固定値であること
- `filtered_count` がフィルタリング後の件数と一致すること

### フロントエンドテスト

#### E2Eテスト
- 総利用者数が常に表示されること
- フィルター適用後、検索結果数が表示されること
- 複数フィルターを組み合わせて絞り込みができること
- ソート順の切り替えが正しく動作すること
