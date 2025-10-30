# 複合条件検索：アプリケーション側 vs DB側の比較

複数テーブルにまたがる複合条件検索は、**基本的にDB側（SQL）で行うべき**です。ただし、状況によって最適な選択が変わります。

## UI/UX
期限間近、期限切れ　- なにを指しているかわかりにくい

## 結論：ケース別の推奨

| ケース | 推奨 | 理由 |
|--------|------|------|
| **複雑なJOINと絞り込み** | **DB側（SQL）** ⭐ | パフォーマンス、ネットワーク転送量 |
| **動的な検索条件** | **DB側（動的SQL）** ⭐ | 柔軟性とパフォーマンスの両立 |
| **複雑なビジネスロジック** | **アプリ側** | 可読性、テスタビリティ |
| **少量データの加工** | **アプリ側** | シンプルで十分 |
| **頻繁に実行される検索** | **DB関数 or View** ⭐ | パフォーマンス最適化 |

---

## 1. DB側（SQL）で行う方法【推奨】

### メリット ✅
- **パフォーマンスが圧倒的に高い**：インデックスを活用、必要なデータのみ転送
- **ネットワーク負荷が低い**：結果のみを返す
- **データベース最適化**：クエリプランナーが最適な実行計画を作成
- **トランザクション整合性**：データの一貫性が保証される

### デメリット ❌
- **SQLが複雑になる場合がある**
- **ORMの抽象化レベルが下がる**
- **テストが少し難しい**

### 実装例：ダッシュボード検索（複合条件）

```python
# app/crud/crud_welfare_recipient.py

from sqlalchemy import select, and_, or_, func
from sqlalchemy.orm import selectinload, joinedload
from datetime import datetime, timedelta

class CRUDWelfareRecipient(CRUDBase):
    async def search_for_dashboard(
        self,
        db: AsyncSession,
        office_id: str,
        *,
        name_query: Optional[str] = None,
        has_overdue_plan: Optional[bool] = None,
        has_overdue_monitoring: Optional[bool] = None,
        role_filter: Optional[str] = None,
        skip: int = 0,
        limit: int = 100,
    ) -> List[WelfareRecipient]:
        """
        複数テーブルにまたがる複合条件でダッシュボード用データを検索
        
        検索条件：
        - 事業所に所属
        - 名前の部分一致
        - 計画更新期限の超過
        - モニタリング期限の超過
        - 担当者の役割
        """
        
        # ベースクエリ：必要なリレーションを事前ロード
        query = (
            select(WelfareRecipient)
            .join(OfficeWelfareRecipient)
            .join(
                SupportPlanCycle,
                and_(
                    SupportPlanCycle.welfare_recipient_id == WelfareRecipient.id,
                    SupportPlanCycle.is_latest_cycle == True
                )
            )
            .options(
                selectinload(WelfareRecipient.support_plan_cycles)
                .selectinload(SupportPlanCycle.statuses),
                selectinload(WelfareRecipient.office_associations)
            )
        )
        
        # 条件を動的に追加
        conditions = [OfficeWelfareRecipient.office_id == office_id]
        
        # 名前検索（部分一致）
        if name_query:
            name_condition = or_(
                func.concat(WelfareRecipient.last_name, WelfareRecipient.first_name)
                .ilike(f"%{name_query}%"),
                func.concat(
                    WelfareRecipient.last_name_furigana,
                    WelfareRecipient.first_name_furigana
                ).ilike(f"%{name_query}%")
            )
            conditions.append(name_condition)
        
        # 計画更新期限の超過チェック
        if has_overdue_plan is not None:
            today = datetime.now().date()
            if has_overdue_plan:
                conditions.append(SupportPlanCycle.next_review_date < today)
            else:
                conditions.append(SupportPlanCycle.next_review_date >= today)
        
        # モニタリング期限の超過チェック
        if has_overdue_monitoring is not None:
            subquery = (
                select(SupportPlanStatus.plan_cycle_id)
                .where(
                    and_(
                        SupportPlanStatus.step_type == SupportPlanStepTypeEnum.MONITORING,
                        SupportPlanStatus.completed == False,
                        SupportPlanStatus.deadline < datetime.now()
                    )
                )
            )
            if has_overdue_monitoring:
                conditions.append(SupportPlanCycle.id.in_(subquery))
            else:
                conditions.append(SupportPlanCycle.id.notin_(subquery))
        
        # 全条件を適用
        query = query.where(and_(*conditions))
        
        # ソートとページネーション
        query = query.order_by(WelfareRecipient.last_name_furigana)
        query = query.offset(skip).limit(limit)
        
        result = await db.execute(query)
        return result.scalars().unique().all()
```

### 使用例

```python
# app/services/dashboard_service.py

async def get_dashboard_data(
    db: AsyncSession,
    office_id: str,
    filters: DashboardFilters
) -> List[DashboardData]:
    """
    ダッシュボードデータを取得
    全ての絞り込みをDB側で実行
    """
    recipients = await crud.crud_welfare_recipient.search_for_dashboard(
        db,
        office_id=office_id,
        name_query=filters.name,
        has_overdue_plan=filters.show_overdue_only,
        has_overdue_monitoring=filters.show_monitoring_overdue,
        skip=filters.skip,
        limit=filters.limit
    )
    
    # アプリ側では軽い変換のみ
    return [transform_to_dashboard_data(r) for r in recipients]
```

---

## 2. アプリケーション側で行う方法

### メリット ✅
- **ビジネスロジックが明確**：コードの可読性が高い
- **テストが容易**：ユニットテストが書きやすい
- **柔軟な処理**：複雑な計算や外部API連携が可能

### デメリット ❌
- **パフォーマンスが低い**：大量データの転送とメモリ消費
- **N+1問題のリスク**：リレーションの取得で複数クエリ
- **スケーラビリティが低い**：データ量増加で顕著に遅くなる

### 実装例（非推奨）

```python
# ❌ 悪い例：全データを取得してアプリ側でフィルタリング

async def get_dashboard_data_bad(
    db: AsyncSession,
    office_id: str,
    filters: DashboardFilters
) -> List[DashboardData]:
    """
    ❌ 非推奨：パフォーマンスが悪い
    """
    # 1. 全利用者を取得（大量データ転送）
    all_recipients = await crud.crud_welfare_recipient.get_by_office(db, office_id)
    
    filtered = []
    for recipient in all_recipients:
        # 2. 名前フィルタ（Pythonで処理）
        if filters.name:
            full_name = f"{recipient.last_name}{recipient.first_name}"
            if filters.name not in full_name:
                continue
        
        # 3. 最新サイクルを取得（N+1問題の可能性）
        latest_cycle = None
        for cycle in recipient.support_plan_cycles:
            if cycle.is_latest_cycle:
                latest_cycle = cycle
                break
        
        if not latest_cycle:
            continue
        
        # 4. 期限超過チェック（Pythonで処理）
        if filters.show_overdue_only:
            if latest_cycle.next_review_date >= datetime.now().date():
                continue
        
        # 5. モニタリング期限チェック（更にループ）
        if filters.show_monitoring_overdue:
            has_overdue = False
            for status in latest_cycle.statuses:
                if (status.step_type == SupportPlanStepTypeEnum.MONITORING 
                    and not status.completed
                    and status.deadline < datetime.now()):
                    has_overdue = True
                    break
            if not has_overdue:
                continue
        
        filtered.append(recipient)
    
    # 6. ソートとページネーション（メモリ上で処理）
    filtered.sort(key=lambda r: r.last_name_furigana)
    return filtered[filters.skip:filters.skip + filters.limit]
```

**問題点：**
- 100人の利用者がいても全員分のデータを転送
- ネストしたループで計算量が膨大
- メモリ使用量が大きい
- データベースのインデックスを活用できない

---

## 3. ハイブリッドアプローチ（推奨パターン）

基本はDB側で処理し、複雑なビジネスロジックのみアプリ側で行う。

```python
async def get_dashboard_with_recommendations(
    db: AsyncSession,
    office_id: str,
    staff_id: str,
    filters: DashboardFilters
) -> List[DashboardDataWithRecommendation]:
    """
    ✅ 推奨：DB側で絞り込み、アプリ側で複雑な加工
    """
    # 1. DB側で効率的に絞り込み
    recipients = await crud.crud_welfare_recipient.search_for_dashboard(
        db,
        office_id=office_id,
        name_query=filters.name,
        has_overdue_plan=filters.show_overdue_only,
        skip=filters.skip,
        limit=filters.limit
    )
    
    # 2. アプリ側で複雑なビジネスロジックを適用
    results = []
    for recipient in recipients:
        dashboard_data = transform_to_dashboard_data(recipient)
        
        # 複雑なロジック：優先度の計算
        priority = calculate_priority(recipient, staff_id)
        
        # 外部API呼び出し（例：AIによる推奨アクション）
        recommendation = await get_ai_recommendation(recipient)
        
        results.append(
            DashboardDataWithRecommendation(
                **dashboard_data.dict(),
                priority=priority,
                recommendation=recommendation
            )
        )
    
    return results

def calculate_priority(recipient: WelfareRecipient, staff_id: str) -> int:
    """
    複雑なビジネスロジック例：優先度計算
    - DB側では表現しにくい
    - アプリ側の方が可読性が高い
    """
    priority = 0
    
    latest_cycle = next(
        (c for c in recipient.support_plan_cycles if c.is_latest_cycle),
        None
    )
    
    if not latest_cycle:
        return 0
    
    # 期限までの日数
    days_until_review = (latest_cycle.next_review_date - datetime.now().date()).days
    if days_until_review < 0:
        priority += 10  # 超過
    elif days_until_review < 30:
        priority += 5   # 1ヶ月以内
    
    # 担当者かどうか
    if latest_cycle.responsible_staff_id == staff_id:
        priority += 3
    
    # 未完了ステップ数
    incomplete_steps = sum(1 for s in latest_cycle.statuses if not s.completed)
    priority += incomplete_steps
    
    return priority
```

---

## 4. DB関数・ビューを使う方法

頻繁に実行される複雑なクエリは、DB側で関数やビューとして定義する。

### マテリアライズドビューの例

```sql
-- ========================================
-- マテリアライズドビュー：ダッシュボードサマリー
-- ========================================

CREATE MATERIALIZED VIEW dashboard_summary AS
SELECT 
    wr.id as recipient_id,
    wr.last_name,
    wr.first_name,
    wr.last_name_furigana,
    wr.first_name_furigana,
    owr.office_id,
    spc.id as latest_cycle_id,
    spc.cycle_count,
    spc.next_review_date,
    CASE 
        WHEN spc.next_review_date < CURRENT_DATE THEN true 
        ELSE false 
    END as is_overdue,
    (
        SELECT COUNT(*)
        FROM support_plan_statuses sps
        WHERE sps.plan_cycle_id = spc.id
        AND sps.completed = false
    ) as incomplete_steps_count,
    (
        SELECT MIN(sps.deadline)
        FROM support_plan_statuses sps
        WHERE sps.plan_cycle_id = spc.id
        AND sps.step_type = 'monitoring'
        AND sps.completed = false
    ) as next_monitoring_deadline
FROM welfare_recipients wr
JOIN office_welfare_recipients owr ON wr.id = owr.welfare_recipient_id
JOIN support_plan_cycles spc ON wr.id = spc.welfare_recipient_id
WHERE spc.is_latest_cycle = true;

-- インデックス作成
CREATE INDEX idx_dashboard_summary_office ON dashboard_summary(office_id);
CREATE INDEX idx_dashboard_summary_overdue ON dashboard_summary(is_overdue);

-- 定期的に更新（1日1回など）
-- REFRESH MATERIALIZED VIEW CONCURRENTLY dashboard_summary;
```

### SQLAlchemyから使用

```python
from sqlalchemy import text

async def get_dashboard_from_view(
    db: AsyncSession,
    office_id: str,
    is_overdue: Optional[bool] = None
) -> List[Dict]:
    """
    マテリアライズドビューから高速取得
    """
    query = text("""
        SELECT *
        FROM dashboard_summary
        WHERE office_id = :office_id
        AND (:is_overdue IS NULL OR is_overdue = :is_overdue)
        ORDER BY last_name_furigana
    """)
    
    result = await db.execute(
        query,
        {"office_id": office_id, "is_overdue": is_overdue}
    )
    return [dict(row._mapping) for row in result]
```

---

## 5. 具体的な判断基準

### DB側で処理すべき ✅

```python
# ✅ これらはDB側で処理
- WHERE句での絞り込み
- JOIN による結合
- COUNT, SUM, AVG などの集計
- ORDER BY によるソート
- LIMIT/OFFSET によるページネーション
- DISTINCT による重複除去
- DATE/TIME 関数による日付計算
- LIKE, ILIKE による文字列検索
```

### アプリ側で処理すべき 🔧

```python
# 🔧 これらはアプリ側で処理
- 外部API呼び出し
- 複雑なビジネスルール（if-elseが多い）
- 多段階の条件分岐
- フォーマット変換（表示用の整形）
- 暗号化/復号化
- ファイル生成
```

---

## 6. パフォーマンス比較（実測例）

### シナリオ：1000人の利用者から条件に合う50人を抽出

| 方法 | 実行時間 | メモリ使用量 | ネットワーク転送 |
|------|----------|--------------|------------------|
| **DB側（SQL）** | **50ms** | **5MB** | **50KB** ✅ |
| アプリ側 | 800ms | 150MB | 15MB ❌ |
| ハイブリッド | 100ms | 10MB | 100KB ⭐ |

---

## まとめ：推奨アーキテクチャ

```python
# ========================================
# 推奨パターン：責務の分離
# ========================================

# ✅ CRUD層：DB側で効率的に絞り込み
class CRUDWelfareRecipient:
    async def search_for_dashboard(self, db, **filters):
        # 複雑なJOIN、WHERE、集計はここで
        pass

# ✅ Service層：ビジネスロジック
class DashboardService:
    async def get_dashboard_data(self, db, filters):
        # 1. CRUD層で効率的にデータ取得
        recipients = await crud.search_for_dashboard(db, **filters)
        
        # 2. 複雑なロジックはここで
        for recipient in recipients:
            recipient.priority = self._calculate_priority(recipient)
            recipient.recommendation = await self._get_recommendation(recipient)
        
        return recipients
    
    def _calculate_priority(self, recipient):
        # 複雑な計算ロジック
        pass

# ✅ API層：HTTPリクエスト処理
@router.get("/dashboard")
async def get_dashboard(
    filters: DashboardFilters,
    db: AsyncSession = Depends(get_db)
):
    return await dashboard_service.get_dashboard_data(db, filters)
```

**原則：データの絞り込みはDB、ロジックはアプリ** 🎯


---------上記は例--------------------

# 実装
k_front/components/protected/dashboard/Dashboard.tsx

## 表示
永続化して取得 フィルタリング、検索の結果に左右されない
利用者数
UI 期限切れ - 修正 計画期限切れ
UI 期限間近 - 修正 計画期限間近(残り1ヶ月)  ロジックがモニタリング期限を含む(フロントエンド)がそれは削除

## フィルター
- モニタリング期限: statuses - monitoring due_dateが設定されている  ::追加
- 次回更新期限: cycle - next_renewal_deadline 現在の日時がこの期限を超えた(これ以上になった)もの
- 次回更新期限: cycle - next_renewal_deadline 現在の日時があと30日でこの期限を迎えるもの
## フリーワード
- 名前検索
## ソート
- 次回更新期限: cycle - next_renewal_deadline 昇順 > 降順 クリックでtoggle