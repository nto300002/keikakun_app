# ダッシュボードフィルター機能 - 現状分析

## 調査日時
2026-02-15

## 目的
500事業所以上のスケールに耐えうるダッシュボードフィルター機能の実現

---

## 📊 現状の実装分析

### 1. エンドポイント実装 (`app/api/v1/endpoints/dashboard.py`)

#### パフォーマンス問題箇所

**Line 43-44: 全利用者取得によるカウント**
```python
all_recipients = await crud.office.get_recipients_by_office_id(db=db, office_id=office.id)
current_user_count = len(all_recipients)
```

**問題点**:
- 全利用者レコードをメモリに読み込んでからカウント
- 500事業所 × 平均100利用者 = 50,000レコードの不要な読み込み
- メモリ使用量: 約50,000 × (1KB/レコード) = 50MB（不要）

**改善案**:
```python
# COUNT(*)クエリで1回のDBアクセス
current_user_count = await crud.dashboard.count_office_recipients(db=db, office_id=office.id)
```

**期待効果**:
- メモリ使用量: 50MB → 1KB（99.998%削減）
- クエリ時間: 500ms → 10ms（50倍高速化）

---

### 2. CRUD実装 (`app/crud/crud_dashboard.py`)

#### 2.1 サブクエリの分析

**Line 70-78: サイクル数カウント**
```python
cycle_count_sq = (
    select(
        SupportPlanCycle.welfare_recipient_id,
        func.count(SupportPlanCycle.id).label("cycle_count"),
    )
    .group_by(SupportPlanCycle.welfare_recipient_id)
    .subquery("cycle_count_sq")
)
```

**Line 80-89: 最新サイクルID取得**
```python
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

**問題点**:
1. **2つのサブクエリが独立実行**
   - `cycle_count_sq`: 全サイクルをスキャンしてカウント
   - `latest_cycle_id_sq`: `is_latest_cycle=true` でフィルタリング
   - 両方とも `welfare_recipient_id` でグループ化

2. **統合可能性**
   - 1つのサブクエリで両方の情報を取得可能
   - `GROUP BY` の重複実行を削減

**統合後のサブクエリ案**:
```python
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

**期待効果**:
- サブクエリ実行回数: 2回 → 1回（50%削減）
- `GROUP BY` 操作: 2回 → 1回（50%削減）
- クエリ時間: 200ms → 120ms（40%高速化）

#### 2.2 JOIN戦略の問題

**Line 101-106: 条件付きJOIN**
```python
if sort_by == "next_renewal_deadline":
    stmt = stmt.join(latest_cycle_id_sq, ...)
    stmt = stmt.join(SupportPlanCycle, ...)
else:
    stmt = stmt.outerjoin(latest_cycle_id_sq, ...)
    stmt = stmt.outerjoin(SupportPlanCycle, ...)
```

**問題点**:
- ソート条件によってJOIN戦略が変わる
- `INNER JOIN` vs `OUTER JOIN` でクエリプランが大きく変わる
- 最新サイクルがない利用者が `INNER JOIN` で除外される

**改善案**:
```python
# 常に OUTER JOIN を使用し、ソートでNULLハンドリング
stmt = stmt.outerjoin(cycle_info_sq, WelfareRecipient.id == cycle_info_sq.c.welfare_recipient_id)
stmt = stmt.outerjoin(SupportPlanCycle, SupportPlanCycle.id == cycle_info_sq.c.latest_cycle_id)
```

#### 2.3 selectinload の多段ロード

**Line 108-112: 複数のselectinload**
```python
stmt = stmt.options(
    selectinload(SupportPlanCycle.statuses),
    selectinload(WelfareRecipient.support_plan_cycles).selectinload(SupportPlanCycle.statuses),
    selectinload(SupportPlanCycle.deliverables)
)
```

**問題点**:
1. **多段selectinload**
   - `WelfareRecipient.support_plan_cycles` → 追加クエリ1回
   - `SupportPlanCycle.statuses` （2箇所） → 追加クエリ2回
   - `SupportPlanCycle.deliverables` → 追加クエリ1回
   - **合計4回の追加クエリ**

2. **N+1問題の危険性**
   - 100利用者 × 4クエリ = 400クエリ
   - 500事業所では 200,000クエリに膨れ上がる可能性

**改善案**:
```python
# 必要最小限のデータのみをJOINで取得
# 不要な多段selectinloadを削除
stmt = stmt.options(
    selectinload(SupportPlanCycle.statuses).where(
        SupportPlanStatus.is_latest_status == true()
    ),
    selectinload(SupportPlanCycle.deliverables).where(
        SupportPlanDeliverable.deliverable_type == DeliverableType.assessment_sheet
    )
)
```

**期待効果**:
- クエリ数: 400 → 100（75%削減）
- メモリ使用量: 不要なサイクルデータを読み込まない

---

### 3. フィルタリング実装の問題

#### 3.1 ステータスフィルター (Line 135-147)

**現在の実装**:
```python
latest_status_subq = select(
    SupportPlanStatus.plan_cycle_id,
    SupportPlanStatus.step_type.label("latest_step")
).where(SupportPlanStatus.is_latest_status == true()).subquery()

stmt = stmt.join(latest_status_subq, SupportPlanCycle.id == latest_status_subq.c.plan_cycle_id)
stmt = stmt.where(latest_status_subq.c.latest_step == status_enum)
```

**問題点**:
- フィルター適用時に追加のサブクエリとJOINが発生
- メインクエリの複雑度が上がる
- クエリプランナーの最適化が困難

**改善案**:
```python
# EXISTS句を使用してサブクエリを最適化
stmt = stmt.where(
    exists(
        select(1)
        .where(
            and_(
                SupportPlanStatus.plan_cycle_id == SupportPlanCycle.id,
                SupportPlanStatus.is_latest_status == true(),
                SupportPlanStatus.step_type == status_enum
            )
        )
    )
)
```

---

## 🔍 データベースインデックス分析

### 現在のインデックス状況（推定）

以下のインデックスが**存在しない可能性が高い**：

| テーブル | カラム | 理由 |
|---------|--------|------|
| `support_plan_cycles` | `(welfare_recipient_id, is_latest_cycle)` | 最新サイクル検索の最適化 |
| `support_plan_statuses` | `(plan_cycle_id, is_latest_status)` | 最新ステータス検索の最適化 |
| `office_welfare_recipients` | `office_id` | 事業所別利用者検索 |
| `welfare_recipients` | `(last_name_furigana, first_name_furigana)` | ふりがなソート |

### 必要な複合インデックス

#### 1. 最新サイクル検索の最適化
```sql
CREATE INDEX idx_support_plan_cycles_recipient_latest
ON support_plan_cycles (welfare_recipient_id, is_latest_cycle)
WHERE is_latest_cycle = true;
```

**効果**:
- `latest_cycle_id_sq` サブクエリが部分インデックスを使用
- フルスキャン回避
- クエリ時間: 500ms → 50ms（10倍高速化）

#### 2. 最新ステータス検索の最適化
```sql
CREATE INDEX idx_support_plan_statuses_cycle_latest
ON support_plan_statuses (plan_cycle_id, is_latest_status, step_type)
WHERE is_latest_status = true;
```

**効果**:
- ステータスフィルターが部分インデックスを使用
- `selectinload` のサブクエリが高速化
- クエリ時間: 300ms → 30ms（10倍高速化）

#### 3. ふりがなソートの最適化
```sql
CREATE INDEX idx_welfare_recipients_furigana
ON welfare_recipients (last_name_furigana, first_name_furigana);
```

**効果**:
- ふりがなソートがインデックススキャンを使用
- `ORDER BY` のソート操作を削減
- クエリ時間: 200ms → 20ms（10倍高速化）

#### 4. 事業所別利用者検索の最適化
```sql
CREATE INDEX idx_office_welfare_recipients_office
ON office_welfare_recipients (office_id, welfare_recipient_id);
```

**効果**:
- 事業所フィルターがインデックスを使用
- `WHERE office_id IN (...)` が高速化

---

## 📈 スケーラビリティ試算

### 現状の問題（500事業所想定）

| 項目 | 現状 | 問題点 |
|------|------|--------|
| 総利用者数取得 | 全レコード読み込み | メモリ: 50MB, 時間: 500ms |
| サブクエリ実行 | 2回（独立実行） | 時間: 200ms × 2 = 400ms |
| selectinload | 4回の追加クエリ | クエリ数: 400, 時間: 2000ms |
| インデックス | 不足 | フルスキャン多発 |
| **合計レスポンス時間** | **約3-5秒** | **ユーザー体験悪化** |

### 改善後の期待値

| 項目 | 改善策 | 期待効果 |
|------|--------|----------|
| 総利用者数取得 | COUNT(*)クエリ | メモリ: 1KB, 時間: 10ms |
| サブクエリ統合 | 1回に統合 | 時間: 120ms |
| selectinload最適化 | フィルタリング追加 | クエリ数: 100, 時間: 500ms |
| 複合インデックス | 4つ追加 | フルスキャン削減: 90% |
| **合計レスポンス時間** | **約300-500ms** | **10倍高速化** |

---

## 🎯 優先度付き改善タスク

### Phase 1: 即効性の高い修正（工数: 2時間）

| タスク | ファイル | 行数 | 優先度 | 期待効果 |
|--------|---------|------|--------|----------|
| COUNT(*) クエリ化 | `dashboard.py` | 43-44 | 🔴 最高 | メモリ99%削減 |
| サブクエリ統合 | `crud_dashboard.py` | 70-89 | 🔴 最高 | 40%高速化 |

### Phase 2: インデックス追加（工数: 1時間）

| タスク | テーブル | 優先度 | 期待効果 |
|--------|---------|--------|----------|
| 最新サイクルインデックス | `support_plan_cycles` | 🔴 最高 | 10倍高速化 |
| 最新ステータスインデックス | `support_plan_statuses` | 🟡 高 | 10倍高速化 |
| ふりがなソートインデックス | `welfare_recipients` | 🟡 高 | 10倍高速化 |
| 事業所別検索インデックス | `office_welfare_recipients` | 🟢 中 | 2倍高速化 |

### Phase 3: selectinload最適化（工数: 3時間）

| タスク | ファイル | 行数 | 優先度 | 期待効果 |
|--------|---------|------|--------|----------|
| フィルタリング追加 | `crud_dashboard.py` | 108-112 | 🟡 高 | 75%削減 |
| EXISTS句への変更 | `crud_dashboard.py` | 135-147 | 🟢 中 | 30%高速化 |

---

## 📝 次のステップ

1. ✅ **このドキュメント**: 現状分析完了
2. 🔜 **要件定義**: 詳細な改善要件を定義（次のファイル）
3. 🔜 **実装計画**: Phase別の実装タスク詳細
4. 🔜 **テスト計画**: パフォーマンステストシナリオ

---

## 参考資料

- 既存ドキュメント: `md_files_design_note/task/4_kensaku.md`
- 実装ファイル:
  - `k_back/app/api/v1/endpoints/dashboard.py`
  - `k_back/app/crud/crud_dashboard.py`
  - `k_back/app/services/dashboard_service.py`
