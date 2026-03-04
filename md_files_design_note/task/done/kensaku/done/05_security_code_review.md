# ダッシュボードフィルター機能 - セキュリティ & コードレビュー

## ドキュメント情報
- レビュー日: 2026-02-14
- レビュー対象: ダッシュボード機能実装
- レビュアー: Claude Sonnet 4.5
- ステータス: ✅ 承認（条件付き）

---

## 📊 レビュー対象ファイル

| ファイル | 行数 | 役割 |
|---------|------|------|
| `app/crud/crud_dashboard.py` | 243 | CRUD層 - データベースクエリ |
| `app/api/v1/endpoints/dashboard.py` | 118 | API層 - HTTPエンドポイント |
| `app/services/dashboard_service.py` | ~200+ | サービス層 - ビジネスロジック |

---

## 🔒 セキュリティレビュー

### ✅ 1. SQLインジェクション対策

#### 評価: **EXCELLENT**

**検証項目**:
- ✅ パラメータ化クエリの使用
- ✅ ORM（SQLAlchemy）による保護
- ✅ ユーザー入力の適切な処理

**詳細**:

```python
# ✅ GOOD: パラメータ化クエリ（crud_dashboard.py:53）
where(OfficeWelfareRecipient.office_id == office_id)

# ✅ GOOD: IN句もパラメータ化（Line 91）
where(OfficeWelfareRecipient.office_id.in_(office_ids))

# ✅ GOOD: ILIKE でもパラメータ化（Line 132-135）
WelfareRecipient.last_name.ilike(f"%{word}%")
```

**リスク**: なし

**推奨事項**: 現状の実装を維持

---

### ✅ 2. 認証・認可

#### 評価: **EXCELLENT**

**検証項目**:
- ✅ JWT認証の実装（`deps.get_current_user`）
- ✅ 事業所スコープの検証
- ✅ マルチテナンシーの保護

**詳細**:

```python
# ✅ GOOD: JWT認証（dashboard.py:18）
current_user: models.Staff = Depends(deps.get_current_user)

# ✅ GOOD: 事業所スコープの検証（Line 36-39）
staff_office_info = await crud.staff.get_staff_with_primary_office(
    db=db, staff_id=current_user.id
)
if not staff_office_info:
    raise HTTPException(status_code=404, detail=ja.DASHBOARD_OFFICE_NOT_FOUND)

# ✅ GOOD: マルチテナンシー保護（Line 55-64）
filtered_results = await crud.dashboard.get_filtered_summaries(
    db=db,
    office_ids=[office.id],  # ← 自分の事業所のみ
    ...
)
```

**マルチテナンシーの保護**:
- ✅ `office_ids` パラメータでスコープを制限
- ✅ ログインユーザーの事業所IDのみ使用
- ✅ 他事業所のデータにアクセス不可

**リスク**: なし

**推奨事項**: 現状の実装を維持

---

### ⚠️ 3. 入力バリデーション

#### 評価: **GOOD（改善余地あり）**

**検証項目**:
- ✅ Pydantic によるスキーマバリデーション
- ⚠️ 検索ワードのサニタイゼーション（部分的）
- ⚠️ フィルターパラメータの検証（部分的）

**詳細**:

#### 3.1 検索ワードの処理（Line 129-138）

```python
# ⚠️ MODERATE RISK: 正規表現分割のみ
if search_term:
    search_words = re.split(r'[\s　]+', search_term.strip())
    conditions = [or_(
        WelfareRecipient.last_name.ilike(f"%{word}%"),
        WelfareRecipient.first_name.ilike(f"%{word}%"),
        WelfareRecipient.last_name_furigana.ilike(f"%{word}%"),
        WelfareRecipient.first_name_furigana.ilike(f"%{word}%"),
    ) for word in search_words if word]
```

**リスク分析**:
- ✅ SQLインジェクション: **保護済み**（ILIKE パラメータ化）
- ⚠️ ReDoS攻撃: **低リスク**（単純な正規表現）
- ⚠️ 長大な入力: **対策なし**（文字数制限なし）

**推奨事項**:

```python
# 改善案: 文字数制限を追加
MAX_SEARCH_TERM_LENGTH = 100

if search_term:
    # 文字数制限
    if len(search_term) > MAX_SEARCH_TERM_LENGTH:
        raise HTTPException(
            status_code=400,
            detail=f"検索ワードは{MAX_SEARCH_TERM_LENGTH}文字以内で入力してください"
        )

    search_words = re.split(r'[\s　]+', search_term.strip())
    # ワード数制限（DoS対策）
    if len(search_words) > 10:
        search_words = search_words[:10]
```

#### 3.2 フィルターパラメータの検証（Line 148-166）

```python
# ✅ GOOD: Enum検証で不正値を無視
if filters.get("status"):
    try:
        status_enum = SupportPlanStep[filters["status"]]
    except KeyError:
        pass  # 無効なステータスは無視
```

**評価**: 適切な実装

---

### ✅ 4. データ漏洩対策

#### 評価: **EXCELLENT**

**検証項目**:
- ✅ 事業所スコープの厳格な適用
- ✅ レスポンススキーマによる制御
- ✅ 機密情報のフィルタリング

**詳細**:

```python
# ✅ GOOD: 必要な情報のみ返却（dashboard.py:78-90）
summary = schemas.dashboard.DashboardSummary(
    id=str(recipient.id),
    full_name=f"{recipient.last_name} {recipient.first_name}",
    # ... 必要な情報のみ
)
# ❌ 機密情報（住所、電話番号、SSN等）は含まれない
```

**リスク**: なし

**推奨事項**: 現状の実装を維持

---

### ⚠️ 5. レート制限・DoS対策

#### 評価: **MODERATE（改善推奨）**

**検証項目**:
- ⚠️ ページネーション制限（部分的）
- ❌ レート制限（未実装）
- ⚠️ タイムアウト設定（要確認）

**詳細**:

#### 5.1 ページネーション制限

```python
# ⚠️ MODERATE RISK: limit の上限チェックなし（dashboard.py:27）
limit: int = 100,  # デフォルト100だが、上限チェックなし
```

**リスク**:
- ユーザーが `limit=999999` を指定可能
- メモリ枯渇の可能性

**推奨事項**:

```python
# 改善案: 上限チェックを追加
MAX_LIMIT = 1000

@router.get("/", response_model=schemas.dashboard.DashboardData)
async def get_dashboard(
    ...
    limit: int = 100,
) -> schemas.dashboard.DashboardData:
    # Limit の上限チェック
    if limit > MAX_LIMIT:
        raise HTTPException(
            status_code=400,
            detail=f"limitは{MAX_LIMIT}以下で指定してください"
        )
    if limit < 1:
        raise HTTPException(
            status_code=400,
            detail="limitは1以上で指定してください"
        )
```

#### 5.2 レート制限

**現状**: エンドポイントにレート制限なし

**推奨事項**:

```python
# 改善案: FastAPI-Limiter または Slowapi を使用
from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address)

@router.get("/", response_model=schemas.dashboard.DashboardData)
@limiter.limit("30/minute")  # 1分間に30リクエストまで
async def get_dashboard(...):
    ...
```

---

### ✅ 6. エラーハンドリング

#### 評価: **GOOD**

**検証項目**:
- ✅ 適切なHTTPステータスコード
- ✅ 日本語エラーメッセージ
- ⚠️ スタックトレースの漏洩（要確認）

**詳細**:

```python
# ✅ GOOD: 適切なHTTPステータスコード（dashboard.py:38）
if not staff_office_info:
    raise HTTPException(status_code=404, detail=ja.DASHBOARD_OFFICE_NOT_FOUND)
```

**推奨事項**:
- 本番環境で `DEBUG=False` を確認
- スタックトレースがユーザーに返されないことを確認

---

## 🏗️ コード品質レビュー

### ✅ 1. アーキテクチャ準拠

#### 評価: **EXCELLENT**

**検証項目**:
- ✅ 4層アーキテクチャの遵守
- ✅ 責任の分離
- ✅ 依存関係の一方向性

**詳細**:

```
API層 (dashboard.py)
  ↓ calls
Service層 (dashboard_service.py)
  ↓ calls
CRUD層 (crud_dashboard.py)
  ↓ accesses
Models層
```

**評価**: 完璧に遵守

---

### ✅ 2. N+1クエリ対策

#### 評価: **EXCELLENT**

**検証項目**:
- ✅ `selectinload` の使用
- ✅ フィルタリング付き `selectinload`（Phase 3.1最適化）
- ✅ サブクエリの統合（Phase 1.2最適化）

**詳細**:

#### 2.1 selectinload フィルタリング（Line 104-126）

```python
# ✅ EXCELLENT: 最新ステータスのみロード
selectinload(
    SupportPlanCycle.statuses.and_(SupportPlanStatus.is_latest_status == true())
)

# ✅ EXCELLENT: アセスメントPDFのみロード
selectinload(
    SupportPlanCycle.deliverables.and_(
        PlanDeliverable.deliverable_type == DeliverableType.assessment_sheet
    )
)
```

**評価**: Phase 3.1の最適化が完璧に実装されている

#### 2.2 サブクエリ統合（Line 71-84）

```python
# ✅ EXCELLENT: 2つのサブクエリを1つに統合
cycle_info_sq = (
    select(
        SupportPlanCycle.welfare_recipient_id,
        func.count(SupportPlanCycle.id).label("cycle_count"),
        func.max(
            case(
                (SupportPlanCycle.is_latest_cycle == true(), SupportPlanCycle.id),
                else_=None
            )
        ).label("latest_cycle_id")
    )
    .group_by(SupportPlanCycle.welfare_recipient_id)
    .subquery("cycle_info_sq")
)
```

**評価**: Phase 1.2の最適化が完璧に実装されている

---

### ✅ 3. EXISTS句の使用（Phase 3.2最適化）

#### 評価: **EXCELLENT**

**詳細**:

```python
# ✅ EXCELLENT: EXISTS句でステータスフィルタリング（Line 154-166）
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

**評価**: Phase 3.2の最適化が完璧に実装されている

---

### ✅ 4. JOIN戦略の統一（Phase 1.3最適化）

#### 評価: **EXCELLENT**

**詳細**:

```python
# ✅ EXCELLENT: 常にOUTER JOIN（Line 93-101）
stmt = stmt.outerjoin(
    cycle_info_sq,
    WelfareRecipient.id == cycle_info_sq.c.welfare_recipient_id
)
stmt = stmt.outerjoin(
    SupportPlanCycle,
    SupportPlanCycle.id == cycle_info_sq.c.latest_cycle_id
)
```

**評価**: Phase 1.3の最適化が完璧に実装されている

---

### ✅ 5. NULLハンドリング

#### 評価: **EXCELLENT**

**詳細**:

```python
# ✅ EXCELLENT: nullslast() でソート（Line 179）
order_func = sort_column.desc().nullslast() if sort_order == "desc" else sort_column.asc().nullslast()

# ✅ EXCELLENT: COALESCE でデフォルト値（Line 89）
func.coalesce(cycle_info_sq.c.cycle_count, 0).label("cycle_count")
```

**評価**: 完璧なNULL処理

---

### ✅ 6. コーディング規約

#### 評価: **EXCELLENT**

**検証項目**:
- ✅ 型ヒント: すべての関数で使用
- ✅ コメント: 日本語で記述
- ✅ Docstring: 日本語で記述
- ✅ インポート順序: 正しい

**詳細**:

```python
# ✅ GOOD: 型ヒント（Line 45）
async def count_office_recipients(self, db: AsyncSession, *, office_id: uuid.UUID) -> int:

# ✅ GOOD: 日本語Docstring（Line 46-47）
"""
指定された事業所の利用者数を取得します。
"""
```

---

## ⚠️ 改善推奨事項

### 優先度: 高

#### 1. 入力バリデーションの強化

**ファイル**: `app/api/v1/endpoints/dashboard.py`

```python
# 現在
@router.get("/", response_model=schemas.dashboard.DashboardData)
async def get_dashboard(
    ...
    search_term: Optional[str] = None,
    limit: int = 100,
):

# 推奨
from pydantic import Field, constr

@router.get("/", response_model=schemas.dashboard.DashboardData)
async def get_dashboard(
    ...
    search_term: Optional[constr(max_length=100)] = None,
    limit: int = Field(default=100, ge=1, le=1000),
):
```

#### 2. レート制限の実装

**推奨**: Slowapi または FastAPI-Limiter を導入

```python
from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address)

@router.get("/", response_model=schemas.dashboard.DashboardData)
@limiter.limit("30/minute")
async def get_dashboard(...):
    ...
```

---

### 優先度: 中

#### 3. エラーハンドリングの強化

**推奨**: カスタム例外ハンドラーの実装

```python
# app/api/errors.py
from fastapi import Request, status
from fastapi.responses import JSONResponse
from sqlalchemy.exc import SQLAlchemyError

async def sqlalchemy_exception_handler(request: Request, exc: SQLAlchemyError):
    logger.error(f"Database error: {exc}", exc_info=True)
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={"detail": "データベースエラーが発生しました"}
    )
```

#### 4. ロギングの強化

**推奨**: 構造化ログの導入

```python
logger.info(
    "Dashboard accessed",
    extra={
        "staff_id": str(current_user.id),
        "office_id": str(office.id),
        "filters": filters,
        "search_term": search_term,
        "response_time_ms": elapsed_time
    }
)
```

---

### 優先度: 低

#### 5. パフォーマンスモニタリング

**推奨**: APMツールの導入（Sentry, New Relic等）

---

## 📊 レビュー結果サマリー

| カテゴリ | 評価 | 状態 |
|---------|------|------|
| **セキュリティ** | | |
| SQLインジェクション対策 | ✅ EXCELLENT | 承認 |
| 認証・認可 | ✅ EXCELLENT | 承認 |
| 入力バリデーション | ⚠️ GOOD | 改善推奨 |
| データ漏洩対策 | ✅ EXCELLENT | 承認 |
| レート制限・DoS対策 | ⚠️ MODERATE | 改善推奨 |
| エラーハンドリング | ✅ GOOD | 承認 |
| **コード品質** | | |
| アーキテクチャ準拠 | ✅ EXCELLENT | 承認 |
| N+1クエリ対策 | ✅ EXCELLENT | 承認 |
| EXISTS句の使用 | ✅ EXCELLENT | 承認 |
| JOIN戦略の統一 | ✅ EXCELLENT | 承認 |
| NULLハンドリング | ✅ EXCELLENT | 承認 |
| コーディング規約 | ✅ EXCELLENT | 承認 |

---

## ✅ 総合評価

### 承認（条件付き）

**総合スコア**: 92/100

**評価**:
- ✅ **セキュリティ**: 85/100
- ✅ **コード品質**: 98/100
- ✅ **パフォーマンス**: 95/100

**コメント**:
実装品質は非常に高く、Phase 1-3 の最適化がすべて適切に実装されています。セキュリティ面でも基本的な対策は十分ですが、以下の改善を推奨します：

1. **必須**: 入力バリデーションの強化（検索ワード文字数制限、limit上限チェック）
2. **推奨**: レート制限の実装
3. **推奨**: エラーハンドリングの強化

これらの改善を実装することで、本番環境への投入が可能となります。

---

## 📋 次のアクション

### 即座に実施

- [ ] 入力バリデーションの強化（検索ワード、limit）
- [ ] レート制限の実装検討

### Phase 2で実施

- [ ] Phase 2インデックスの追加
  - `idx_support_plan_cycles_recipient_latest`
  - `idx_support_plan_statuses_cycle_latest`
  - `idx_welfare_recipients_furigana`
  - `idx_office_welfare_recipients_office`

### 将来的に検討

- [ ] APMツールの導入
- [ ] 構造化ログの実装
- [ ] パフォーマンスモニタリング強化

---

**レビュー完了日**: 2026-02-14
**レビュアー**: Claude Sonnet 4.5
**承認ステータス**: ✅ 承認（条件付き）
