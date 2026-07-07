# ダッシュボード複合条件検索機能 - タスク全体像

## 📋 プロジェクト概要

**目的**: 利用者ダッシュボードの複合条件検索機能を完全実装し、ユーザビリティを向上させる

**期間**: 約3.5日（26時間）

**優先度**: 🔴 高（ユーザー体験に直接影響）

---

## 🎯 解決する課題

### 1. 総利用者数と検索結果数が混在している
- **現状**: `current_user_count` が検索結果数を表示
- **問題**: フィルタリング前の総利用者数が分からない
- **影響**: 請求管理（利用者数制限）との整合性が取れない

### 2. フィルター名が曖昧
- **現状**: 「期限切れ」「期限間近」
- **問題**: 何の期限か不明
- **影響**: ユーザーが混乱し、誤った絞り込みをする可能性

### 3. アセスメント開始期限でフィルタリングできない
- **現状**: フィルターが存在しない
- **問題**: アセスメント開始期限が迫っている利用者を抽出できない
- **影響**: アセスメント開始漏れのリスク
- **備考**: 個別支援計画は5つのステータス（アセスメント → 個別支援計画書原案 → 担当者会議 → 個別支援計画書本案 → モニタリング）で管理される

### 4. 選択中のフィルター条件が分からない【新規】
- **現状**: フィルターボタンを押すだけで、何が選択されているか視覚的に不明確
- **問題**: 複合条件で絞り込んだ時、どの条件が有効か忘れる
- **影響**: ユーザーが意図しない絞り込み結果を見る可能性

### 5. デフォルトソートが不適切
- 改善されています: 現在は計画期限の昇順
- **現状**: ふりがな昇順（あいうえお順）
- **問題**: 期限が近い利用者が優先表示されない
- **影響**: 緊急度の高いタスクを見逃す可能性

---

## 🎨 実装要件

### Phase 1: バックエンド実装

#### 1.1 スキーマ拡張（30分）

**ファイル**: `app/schemas/dashboard.py`

**変更内容**:
```python
class DashboardData(DashboardBase):
    """ダッシュボード情報（レスポンス）"""
    current_user_count: int      # 総利用者数（固定）
    filtered_count: int           # 検索結果数（新規追加）← これを追加
    max_user_count: int
    billing_status: BillingStatus
    recipients: List[DashboardSummary]
```

**バリデーション**:
- `filtered_count`: 必須、0以上の整数
- `filtered_count <= current_user_count`（通常）

#### 1.2 API実装変更（1時間）

**ファイル**: `app/api/v1/endpoints/dashboard.py`

**変更内容**:
```python
@router.get("/", response_model=schemas.dashboard.DashboardData)
async def get_dashboard(...):
    # 1. 総利用者数を取得（フィルタリング無視）
    current_user_count = await crud.dashboard.count_office_recipients(
        db=db,
        office_id=office.id
    )  # ← 既存メソッド（Phase 1.1で実装済み）

    # 2. フィルタリング後のリストを取得
    filtered_results = await crud.dashboard.get_filtered_summaries(...)

    # 3. 検索結果数を計算
    filtered_count = len(filtered_results)  # ← 追加

    # 4. レスポンス構築
    return schemas.dashboard.DashboardData(
        current_user_count=current_user_count,  # 総利用者数（固定）
        filtered_count=filtered_count,          # 検索結果数（新規）
        recipients=recipient_summaries
    )
```

#### 1.3 アセスメント開始期限フィルター追加（3時間）

**ファイル**: `app/api/v1/endpoints/dashboard.py`

**クエリパラメータ追加**:
```python
@router.get("/", response_model=schemas.dashboard.DashboardData)
async def get_dashboard(
    ...
    has_assessment_due: Annotated[
        Optional[bool],
        Query(description="アセスメント開始期限が設定されている利用者のみ")
    ] = None,
):
```

**ファイル**: `app/crud/crud_dashboard.py`

**フィルター条件追加**:
```python
# Line 145付近に追加
if filters.get("has_assessment_due"):
    # 未完了のアセスメント期限が設定されている利用者
    # 個別支援計画のステータス: アセスメント → 原案 → 担当者会議 → 本案 → モニタリング
    assessment_exists_subq = exists(
        select(1).where(
            and_(
                SupportPlanStatus.plan_cycle_id == SupportPlanCycle.id,
                SupportPlanStatus.step_type == SupportPlanStep.assessment,
                SupportPlanStatus.completed == False,
                SupportPlanStatus.due_date.isnot(None)
            )
        )
    )
    stmt = stmt.where(assessment_exists_subq)
```

#### 1.4 デフォルトソート変更（30分）

**ファイル**: `app/api/v1/endpoints/dashboard.py`

**変更内容**:
```python
@router.get("/", response_model=schemas.dashboard.DashboardData)
async def get_dashboard(
    sort_by: str = 'next_renewal_deadline',  # ← 'name_phonetic' から変更
    sort_order: str = 'asc',
    ...
):
```

#### 1.5 テスト実装（5時間）

**新規ファイル**: `tests/schemas/test_dashboard_schema.py`
- `filtered_count` フィールドのバリデーションテスト

**新規ファイル**: `tests/crud/test_crud_dashboard_filtering.py`
- モニタリング期限フィルターのテスト
- 複合条件（AND）のテスト

**新規ファイル**: `tests/integration/test_dashboard_api.py`
- APIレスポンスに `filtered_count` が含まれることを確認
- 複合条件フィルターがAPI経由で動作することを確認

---

### Phase 2: フロントエンド実装

#### 2.1 型定義更新（30分）

**ファイル**: `k_front/types/dashboard.ts`

**変更内容**:
```typescript
export interface DashboardData {
  staff_name: string;
  staff_role: StaffRole;
  office_id: string;
  office_name: string;
  current_user_count: number;      // 総利用者数
  filtered_count: number;           // ← 新規追加: 検索結果数
  max_user_count: number;
  billing_status: BillingStatus;
  recipients: DashboardSummary[];
}
```

#### 2.2 総利用者数と検索結果数の表示分離（2時間）

**ファイル**: `k_front/components/protected/dashboard/Dashboard.tsx`

**UI実装**:
```typescript
// ヘッダー部分
<div className="dashboard-header">
  {/* 総利用者数（常に固定） */}
  <div className="user-count">
    <span className="label">総利用者数:</span>
    <span className="value">{dashboardData.current_user_count}名</span>
  </div>

  {/* 検索結果数（フィルタリング時のみ表示） */}
  {dashboardData.filtered_count !== dashboardData.current_user_count && (
    <div className="filtered-count">
      <span className="label">検索結果:</span>
      <span className="value highlight">{dashboardData.filtered_count}名</span>
    </div>
  )}
</div>
```

#### 2.3 フィルター名の明確化（1時間）

**ファイル**: `k_front/components/protected/dashboard/FilterButtons.tsx`

**UI変更**:
```typescript
// Before
<FilterButton>期限切れ</FilterButton>
<FilterButton>期限間近</FilterButton>

// After
<FilterButton>
  計画期限切れ
  <Tooltip>次回更新期限が過ぎた利用者</Tooltip>
</FilterButton>

<FilterButton>
  計画期限間近（残り30日）
  <Tooltip>次回更新期限まで30日以内の利用者</Tooltip>
</FilterButton>
```

#### 2.4 アセスメント開始期限フィルターUI追加（1.5時間）

**ファイル**: `k_front/components/protected/dashboard/FilterButtons.tsx`

**新規フィルターボタン追加**:
```typescript
const [activeFilters, setActiveFilters] = useState({
  isOverdue: false,
  isUpcoming: false,
  hasAssessmentDue: false,  // ← 追加（アセスメント開始期限）
  status: null,
});

// UI
<FilterButton
  active={activeFilters.hasAssessmentDue}
  onClick={() => handleFilterToggle('hasAssessmentDue')}
>
  アセスメント開始期限あり
  <Tooltip>未完了のアセスメント開始期限が設定されている利用者（5ステップ: アセスメント → 原案 → 担当者会議 → 本案 → モニタリング）</Tooltip>
</FilterButton>
```

#### 2.5 選択中の条件を画面表示【新規要件】（2時間）

**ファイル**: `k_front/components/protected/dashboard/ActiveFilters.tsx`（新規作成）

**機能**:
- 現在選択中のフィルター条件をチップ形式で表示
- 各チップに「×」ボタンで個別解除可能
- 「すべてクリア」ボタンで一括解除

**UI実装**:
```typescript
interface ActiveFiltersProps {
  activeFilters: FilterState;
  searchTerm: string;
  onFilterRemove: (filterKey: string) => void;
  onClearAll: () => void;
}

export const ActiveFilters: React.FC<ActiveFiltersProps> = ({
  activeFilters,
  searchTerm,
  onFilterRemove,
  onClearAll
}) => {
  const hasActiveFilters = 
    searchTerm || 
    activeFilters.isOverdue || 
    activeFilters.isUpcoming || 
    activeFilters.hasMonitoringDue || 
    activeFilters.status;

  if (!hasActiveFilters) {
    return null;
  }

  return (
    <div className="active-filters">
      <span className="label">絞り込み中:</span>
      
      <div className="filter-chips">
        {/* 検索ワード */}
        {searchTerm && (
          <Chip onRemove={() => onFilterRemove('search')}>
            検索: "{searchTerm}"
          </Chip>
        )}

        {/* 計画期限切れ */}
        {activeFilters.isOverdue && (
          <Chip onRemove={() => onFilterRemove('isOverdue')}>
            計画期限切れ
          </Chip>
        )}

        {/* 計画期限間近 */}
        {activeFilters.isUpcoming && (
          <Chip onRemove={() => onFilterRemove('isUpcoming')}>
            計画期限間近（残り30日）
          </Chip>
        )}

        {/* アセスメント開始期限あり */}
        {activeFilters.hasAssessmentDue && (
          <Chip onRemove={() => onFilterRemove('hasAssessmentDue')}>
            アセスメント開始期限あり
          </Chip>
        )}

        {/* ステータス */}
        {activeFilters.status && (
          <Chip onRemove={() => onFilterRemove('status')}>
            ステータス: {activeFilters.status}
          </Chip>
        )}

        {/* すべてクリア */}
        <Button variant="text" onClick={onClearAll}>
          すべてクリア
        </Button>
      </div>
    </div>
  );
};
```

**使用例**:
```typescript
// Dashboard.tsx
<div className="dashboard-content">
  {/* フィルターボタン */}
  <FilterButtons
    activeFilters={activeFilters}
    onFilterToggle={handleFilterToggle}
  />

  {/* 選択中の条件を表示（新規） */}
  <ActiveFilters
    activeFilters={activeFilters}
    searchTerm={searchTerm}
    onFilterRemove={handleFilterRemove}
    onClearAll={handleClearAllFilters}
  />

  {/* 検索結果 */}
  <RecipientList recipients={recipients} />
</div>
```

**スタイリング例**:
```css
.active-filters {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px;
  background-color: #f5f5f5;
  border-radius: 8px;
  margin-bottom: 16px;
}

.filter-chips {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.chip {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 6px 12px;
  background-color: #e3f2fd;
  color: #1976d2;
  border-radius: 16px;
  font-size: 14px;
}

.chip-remove {
  cursor: pointer;
  font-weight: bold;
  color: #1976d2;
}

.chip-remove:hover {
  color: #d32f2f;
}
```

#### 2.6 状態管理の改善（2時間）

**ファイル**: `k_front/components/protected/dashboard/Dashboard.tsx`

**複合条件の状態管理**:
```typescript
const handleFilterToggle = (filterKey: string) => {
  setActiveFilters({
    ...activeFilters,  // ← 既存のフィルターを保持
    [filterKey]: !activeFilters[filterKey]
  });
};

const handleFilterRemove = (filterKey: string) => {
  if (filterKey === 'search') {
    setSearchTerm('');
  } else {
    setActiveFilters({
      ...activeFilters,
      [filterKey]: false
    });
  }
};

const handleClearAllFilters = () => {
  setSearchTerm('');
  setActiveFilters({
    isOverdue: false,
    isUpcoming: false,
    hasAssessmentDue: false,  // ← 変更: モニタリング → アセスメント
    status: null,
  });
};

// APIリクエスト時にすべてのアクティブフィルターを送信
const params = {
  search_term: searchTerm || undefined,
  sort_by: sortBy,
  sort_order: sortOrder,
  is_overdue: activeFilters.isOverdue || undefined,
  is_upcoming: activeFilters.isUpcoming || undefined,
  has_assessment_due: activeFilters.hasAssessmentDue || undefined,  // ← 変更
  status: activeFilters.status || undefined,
};
```

#### 2.7 デフォルトソート変更（30分）

**ファイル**: `k_front/components/protected/dashboard/Dashboard.tsx`

**変更内容**:
```typescript
const [sortBy, setSortBy] = useState('next_renewal_deadline');  // ← 'name_phonetic' から変更
```

#### 2.8 E2Eテスト作成（3時間）

**新規ファイル**: `k_front/e2e/dashboard-filtering.spec.ts`

**テストシナリオ**:
1. 総利用者数と検索結果数の表示確認
2. 複合条件フィルタリングの動作確認
3. 選択中の条件チップの表示・削除確認
4. 「すべてクリア」機能の確認

---

### Phase 3: 統合テスト・デプロイ

#### 3.1 結合テスト（2時間）
- バックエンド + フロントエンド連携確認
- 選択中の条件表示が正しく動作することを確認

#### 3.2 UIテスト（1時間）
- 複合条件検索の動作確認（手動）
- フィルターチップの視認性確認

#### 3.3 パフォーマンステスト（1時間）
- 500事業所でのレスポンス確認

#### 3.4 デプロイ（1時間）
- ステージング → 本番

---

## 📊 工数サマリー

| Phase | タスク | 工数 | 期間 |
|-------|--------|------|------|
| **Phase 1** | バックエンド実装 | 10時間 | 1.5日 |
| - | スキーマ拡張 | 0.5時間 | |
| - | API実装変更 | 1時間 | |
| - | モニタリングフィルター追加 | 3時間 | |
| - | デフォルトソート変更 | 0.5時間 | |
| - | テスト実装 | 5時間 | |
| **Phase 2** | フロントエンド実装 | 11時間 | 1.5日 |
| - | 型定義更新 | 0.5時間 | |
| - | UI実装（件数表示） | 2時間 | |
| - | フィルター名変更 | 1時間 | |
| - | モニタリングフィルターUI | 1.5時間 | |
| - | **選択中の条件表示【新規】** | **2時間** | |
| - | 状態管理の改善 | 2時間 | |
| - | デフォルトソート変更 | 0.5時間 | |
| - | E2Eテスト作成 | 3時間 | |
| **Phase 3** | 統合テスト・デプロイ | 5時間 | 0.5日 |
| **合計** | | **26時間** | **約3.5日** |

---

## ✅ 完了条件

### 機能要件
- ✅ 総利用者数と検索結果数が分離して表示される
- ✅ フィルター名が明確になっている（計画期限切れ、計画期限間近、アセスメント開始期限あり）
- ✅ アセスメント開始期限フィルターが動作する（5ステータス対応: アセスメント → 原案 → 担当者会議 → 本案 → モニタリング）
- ✅ **選択中のフィルター条件が画面上にチップ形式で表示される【新規】**
- ✅ **各フィルターチップから個別に条件を解除できる【新規】**
- ✅ **「すべてクリア」ボタンで全条件を一括解除できる【新規】**
- ✅ 複数フィルターを組み合わせて絞り込みできる
- ✅ デフォルトソートが次回更新期限昇順になっている

### 非機能要件
- ✅ バックエンドテスト: カバレッジ80%以上
- ✅ フロントエンドE2Eテスト: 全シナリオ成功
- ✅ レスポンス時間: 500ms以下（500事業所規模）
- ✅ セキュリティ: 入力バリデーション完備

### UI/UX要件【新規】
- ✅ 選択中の条件が視覚的に分かりやすい
- ✅ チップのスタイルが統一されている
- ✅ フィルター解除の操作が直感的
- ✅ モバイル表示でも条件チップが見やすい

---

## 🎨 UI/UXワイヤーフレーム

### フィルター適用前
```
┌─────────────────────────────────────────┐
│ ダッシュボード                           │
├─────────────────────────────────────────┤
│ 総利用者数: 100名                        │
│                                         │
│ [検索]  [計画期限切れ] [計画期限間近]    │
│         [アセスメント開始期限あり]       │
├─────────────────────────────────────────┤
│ 利用者リスト（100名）                    │
└─────────────────────────────────────────┘
```

### フィルター適用後【新規UI】
```
┌─────────────────────────────────────────┐
│ ダッシュボード                           │
├─────────────────────────────────────────┤
│ 総利用者数: 100名                        │
│ 検索結果: 15名                           │
│                                         │
│ [検索]  [計画期限切れ] [計画期限間近]    │
│         [アセスメント開始期限あり]       │
│                                         │
│ 絞り込み中:                              │
│ [検索: "田中" ×] [計画期限切れ ×]        │
│ [アセスメント開始期限あり ×]             │
│ [すべてクリア]                           │
├─────────────────────────────────────────┤
│ 利用者リスト（15名）                     │
└─────────────────────────────────────────┘
```

---

## 🔗 関連ドキュメント

- [詳細要件定義](./README.md)
- [パフォーマンス最適化完了レポート](../README.md)
- [セキュリティレビュー](../05_security_code_review.md)

---

**作成日**: 2026-02-17
**更新日**: 2026-02-17
**ステータス**: 📋 TODO（未着手）
**優先度**: 🔴 高
**総工数**: 26時間（約3.5日）
