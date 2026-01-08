# asoBeフィードバック - 実装タスク一覧（TDD対応）

**作成日**: 2026-01-08
**実装方針**: Test-Driven Development (TDD)
**優先順位**: 🔴 High → 🟡 Medium → 🟢 Low

---

## 📋 目次

1. [影響範囲の全体調査](#影響範囲の全体調査)
2. [非機能要件の検討](#非機能要件の検討)
3. [実装タスク一覧](#実装タスク一覧)
4. [TDD実装フロー](#tdd実装フロー)

---

## 影響範囲の全体調査

### 調査結果サマリー

#### EmploymentRelated (就労関係) の使用状況

**影響ファイル数**: 9ファイル

1. `app/models/assessment.py` - DBモデル定義
2. `app/schemas/assessment.py` - Pydanticスキーマ定義
3. `app/crud/crud_employment.py` - CRUD操作
4. `app/services/assessment_service.py` - ビジネスロジック
5. `app/models/__init__.py` - モデルエクスポート
6. `app/models/welfare_recipient.py` - リレーション定義
7. `tests/models/test_assessment_models.py` - モデルテスト
8. `tests/services/test_assessment_service.py` - サービステスト
9. `tests/api/v1/test_assessment.py` - APIテスト

**現在の構造**:
```python
# app/models/assessment.py (102-127行目)
class EmploymentRelated(Base):
    __tablename__ = 'employment_related'
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    welfare_recipient_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey('welfare_recipients.id'), unique=True)
    # 既存フィールド12個 + created_at, updated_at, is_test_data
```

**Pydanticスキーマ**:
```python
# app/schemas/assessment.py (423-512行目)
class EmploymentBase(BaseModel):      # 基本スキーマ
class EmploymentCreate(EmploymentBase):  # 作成
class EmploymentUpdate(BaseModel):      # 更新（全フィールドOptional）
class EmploymentResponse(EmploymentBase): # レスポンス
```

---

#### SupportPlanStep (サイクル処理) の使用状況

**影響ファイル数**: 25ファイル（うち cycle_number 分岐あり: 6ファイル）

**cycle_number 分岐が存在するファイル**:
1. `app/services/support_plan_service.py` - 3箇所
2. `app/services/welfare_recipient_service.py` - 4箇所
3. `app/services/calendar_service.py` - 1箇所（条件スキップ）
4. `tests/services/test_support_plan_service.py` - テスト検証
5. `tests/services/test_welfare_recipient_service.py` - テスト検証
6. `tests/api/v1/test_plan_deliverables_update_delete.py` - テスト検証

---

## 非機能要件の検討

### 1. セキュリティ

#### 1-1. 入力バリデーション

**リスク**: XSS攻撃、SQLインジェクション

**対策**:
- ✅ **既存**: Pydantic field_validator による文字数制限
- ✅ **既存**: SQLAlchemy ORM によるパラメータ化クエリ
- 🆕 **追加**: 新規フィールドにも同様のバリデーション適用

**実装内容**:
```python
# app/schemas/assessment.py

# Task 1: 就労経験なし関連
@field_validator('employment_other_text')
def validate_employment_other_text(cls, v):
    if v and len(v) > 500:
        raise ValueError('その他テキストは500文字以内で入力してください')
    return v

# Task 2: asoBeで希望する作業
@field_validator('desired_tasks_on_asobe')
def validate_desired_tasks(cls, v):
    if v and len(v) > 1000:
        raise ValueError('asoBeで希望する作業は1000文字以内で入力してください')
    return v
```

#### 1-2. 認可チェック

**リスク**: 不正なデータアクセス

**対策**:
- ✅ **既存**: OAuth2 + JWT 認証
- ✅ **既存**: office_id による multi-tenancy
- ✅ **既存**: StaffRole による権限管理

**確認事項**:
- [ ] 新規フィールドへのアクセスも既存の認可フローを通過するか確認

---

### 2. パフォーマンス

#### 2-1. データベースインデックス

**現状**:
```python
# app/models/assessment.py:106
welfare_recipient_id: Mapped[uuid.UUID] = mapped_column(
    UUID(as_uuid=True),
    ForeignKey('welfare_recipients.id'),
    unique=True  # ← UNIQUE制約（自動的にインデックスが作成される）
)
```

**分析**:
- ✅ `welfare_recipient_id` には UNIQUE制約により自動インデックスあり
- ✅ `is_test_data` にはインデックスあり (122行目)
- 🟢 新規フィールドはBoolean/Textのため、インデックス不要
  - Boolean: カーディナリティ低い（True/False のみ）→ インデックス効果薄い
  - Text: 検索対象外 → インデックス不要

**結論**: **追加のインデックスは不要**

---

#### 2-2. APIレスポンスサイズ

**懸念**: フィールド追加による肥大化

**分析**:
```
Task 1: Boolean × 4 + Text(nullable) × 1 = 約 4 bytes + α
Task 2: Text(nullable) × 1 = 約 α bytes
合計増加量: 数バイト〜数百バイト（通常のテキスト入力を想定）
```

**影響**: **無視できる範囲** (< 1KB増加)

**対策不要**: 既存のページネーション機能で対応済み

---

#### 2-3. データベースクエリ数

**懸念**: N+1問題の発生

**分析**:
- EmploymentRelated は welfare_recipient に対して 1:1 関係
- 既存の `selectinload()` で eager loading 実装済み
- 新規フィールドは既存レコードの一部として取得される

**結論**: **N+1問題は発生しない**

---

### 3. データ整合性

#### 3-1. マイグレーションの安全性

**リスク**: ダウンタイム、データ損失

**対策**:

**Task 1 & 2: カラム追加**
```python
# マイグレーション戦略
def upgrade():
    # Boolean: DEFAULT False
    op.add_column('employment_related', sa.Column('no_employment_experience', sa.Boolean(), nullable=False, server_default='false'))

    # Text: NULLABLE
    op.add_column('employment_related', sa.Column('desired_tasks_on_asobe', sa.Text(), nullable=True))
```

**安全性評価**:
- ✅ `nullable=False` + `server_default='false'` → ダウンタイム不要
- ✅ `nullable=True` → ダウンタイム不要
- ✅ 既存データへの影響なし（新規カラムはデフォルト値で埋まる）
- ✅ ロールバック可能（`downgrade()` で `DROP COLUMN`）

**Task 4: サイクル統一**
```python
# ロジック変更のみ、スキーマ変更なし
# → マイグレーション不要
```

**安全性評価**:
- ✅ データベーススキーマ変更なし
- ⚠️ 既存サイクルとの整合性確認が必要
- ✅ 新規サイクルから段階的に適用可能

---

#### 3-2. トランザクション境界

**リスク**: 部分的な更新、データ不整合

**分析**:

**既存のトランザクション管理**:
```python
# app/api/v1/endpoints/*.py (API層)
# - トランザクション開始: get_db() 依存性注入
# - コミット: Service層またはCRUD層
# - ロールバック: 例外発生時に自動

# 4-Layer Architecture
# API層 → Services層 → CRUD層 → Models層
#         ↑ commit()はここ  ↑ commit()はここ
```

**Task 1 & 2: EmploymentRelated 更新**
- 既存のトランザクション境界内で処理
- `crud_employment.update()` が単一トランザクションで実行
- **対策不要**

**Task 4: サイクル統一**
- `_create_new_cycle_from_final_plan()` が複数ステータスを作成
- 既に単一トランザクション内で実装済み
- **対策不要**

**結論**: **既存のトランザクション管理で十分**

---

#### 3-3. 既存データへの影響

**Task 1 & 2: DB カラム追加**

| カラム名 | 型 | デフォルト値 | 既存データへの影響 |
|---------|---|------------|------------------|
| `no_employment_experience` | Boolean | `False` | ✅ 既存レコードは全て `False` |
| `attended_job_selection_office` | Boolean | `False` | ✅ 既存レコードは全て `False` |
| `received_employment_assessment` | Boolean | `False` | ✅ 既存レコードは全て `False` |
| `employment_other_experience` | Boolean | `False` | ✅ 既存レコードは全て `False` |
| `employment_other_text` | Text | `NULL` | ✅ 既存レコードは全て `NULL` |
| `desired_tasks_on_asobe` | Text | `NULL` | ✅ 既存レコードは全て `NULL` |

**影響なし**: 既存データの意味は変わらない（追加情報が未入力状態になるだけ）

---

**Task 4: サイクル処理統一**

**既存サイクルへの影響**:
- cycle_number == 1 の既存サイクル: **変更なし**（ステップ数4のまま）
- cycle_number >= 2 の既存サイクル: **変更なし**
- **新規作成サイクルのみ**: 5ステップで作成される

**段階的適用**:
```
既存サイクル（変更前に作成）→ 4 or 5ステップ（変更なし）
新規サイクル（変更後に作成）→ 5ステップ（統一）
```

**データ整合性**: ✅ 問題なし

---

### 4. 可用性

#### 4-1. デプロイメント戦略

**推奨**: Blue-Green Deployment または Rolling Update

**手順**:
1. マイグレーション実行（ダウンタイムなし）
2. バックエンドデプロイ（新APIは後方互換性あり）
3. フロントエンドデプロイ
4. 動作確認

**ロールバック計画**:
- マイグレーション: `alembic downgrade -1`
- コード: 前バージョンにロールバック
- データ: 新規カラムは nullable or default 値なので影響なし

---

### 5. 保守性

#### 5-1. テストカバレッジ

**既存カバレッジ**:
- モデルテスト: `tests/models/test_assessment_models.py`
- サービステスト: `tests/services/test_assessment_service.py`
- APIテスト: `tests/api/v1/test_assessment.py`

**追加が必要なテスト**:
- [ ] 新規フィールドのバリデーションテスト
- [ ] 新規フィールドのCRUDテスト
- [ ] 新規フィールドのAPIテスト
- [ ] サイクル統一後のステップ数検証テスト

---

## 実装タスク一覧

### 🔴 Priority 1: 就労関係のチェックボックス追加（Task 1）

**概要**: 「就労経験なし」チェックボックスとその子要素を追加

**影響範囲**:
- DB: `employment_related` テーブルに5カラム追加
- Backend: モデル、スキーマ、CRUD、マイグレーション
- Frontend: アセスメント編集モーダル
- Tests: 9ファイル

**非機能要件**:
- ✅ セキュリティ: Pydantic バリデーション追加
- ✅ パフォーマンス: インデックス不要
- ✅ データ整合性: デフォルト値 `False` で既存データに影響なし

---

#### 1.1 TDD Phase 1: Red（失敗するテストを書く）

**ファイル**: `k_back/tests/models/test_assessment_models.py`

```python
import pytest
from app.models.assessment import EmploymentRelated
from sqlalchemy.ext.asyncio import AsyncSession

@pytest.mark.asyncio
async def test_employment_related_no_experience_fields(db_session: AsyncSession):
    """就労経験なし関連フィールドのテスト"""
    # Arrange
    employment = EmploymentRelated(
        welfare_recipient_id=...,
        created_by_staff_id=...,
        work_conditions=WorkConditions.other,
        # 既存フィールド省略
        no_employment_experience=True,
        attended_job_selection_office=True,
        received_employment_assessment=False,
        employment_other_experience=True,
        employment_other_text="職業訓練を受けた"
    )

    # Act
    db_session.add(employment)
    await db_session.commit()
    await db_session.refresh(employment)

    # Assert
    assert employment.no_employment_experience is True
    assert employment.attended_job_selection_office is True
    assert employment.received_employment_assessment is False
    assert employment.employment_other_experience is True
    assert employment.employment_other_text == "職業訓練を受けた"
```

**ファイル**: `k_back/tests/services/test_assessment_service.py`

```python
@pytest.mark.asyncio
async def test_create_employment_with_no_experience(
    db_session: AsyncSession,
    employee_user_factory
):
    """就労経験なしフラグ付きで作成するテスト"""
    # Arrange
    staff = await employee_user_factory()
    recipient = await create_test_recipient(db_session, staff.office_associations[0].office_id)

    employment_data = EmploymentCreate(
        work_conditions=WorkConditions.other,
        # 既存フィールド省略
        no_employment_experience=True,
        attended_job_selection_office=True,
        received_employment_assessment=True,
        employment_other_experience=False,
        employment_other_text=None
    )

    # Act
    result = await crud.employment.create(
        db=db_session,
        obj_in=employment_data,
        welfare_recipient_id=recipient.id,
        created_by_staff_id=staff.id
    )

    # Assert
    assert result.no_employment_experience is True
```

**ファイル**: `k_back/tests/api/v1/test_assessment.py`

```python
@pytest.mark.asyncio
async def test_update_employment_no_experience_validation(
    async_client: AsyncClient,
    employee_user_factory
):
    """バリデーション: 親がFalseの時、子は自動的にFalseになる"""
    # Arrange
    staff = await employee_user_factory()
    token = create_access_token(str(staff.id), timedelta(minutes=30))

    # Act
    response = await async_client.patch(
        f"/api/v1/welfare-recipients/{recipient_id}/employment",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "no_employment_experience": False,  # 親をFalse
            "attended_job_selection_office": True,  # 子をTrue（無効になるべき）
        }
    )

    # Assert
    assert response.status_code == 200
    data = response.json()
    # バリデータにより自動的にFalseになることを検証
    assert data["no_employment_experience"] is False
    assert data["attended_job_selection_office"] is False
```

---

#### 1.2 TDD Phase 2: Green（最小限のコードで通す）

**Step 1: マイグレーション作成**

```bash
cd k_back
alembic revision -m "add_no_employment_experience_fields_to_employment_related"
```

**ファイル**: `k_back/migrations/versions/xxxx_add_no_employment_experience_fields.py`

```python
"""add_no_employment_experience_fields_to_employment_related

Revision ID: xxxx
Revises: yyyy
Create Date: 2026-01-08
"""
from alembic import op
import sqlalchemy as sa

revision = 'xxxx'
down_revision = 'yyyy'
branch_labels = None
depends_on = None

def upgrade():
    op.add_column('employment_related',
        sa.Column('no_employment_experience', sa.Boolean(), nullable=False, server_default='false')
    )
    op.add_column('employment_related',
        sa.Column('attended_job_selection_office', sa.Boolean(), nullable=False, server_default='false')
    )
    op.add_column('employment_related',
        sa.Column('received_employment_assessment', sa.Boolean(), nullable=False, server_default='false')
    )
    op.add_column('employment_related',
        sa.Column('employment_other_experience', sa.Boolean(), nullable=False, server_default='false')
    )
    op.add_column('employment_related',
        sa.Column('employment_other_text', sa.Text(), nullable=True)
    )

def downgrade():
    op.drop_column('employment_related', 'employment_other_text')
    op.drop_column('employment_related', 'employment_other_experience')
    op.drop_column('employment_related', 'received_employment_assessment')
    op.drop_column('employment_related', 'attended_job_selection_office')
    op.drop_column('employment_related', 'no_employment_experience')
```

**Step 2: モデル更新**

**ファイル**: `k_back/app/models/assessment.py` (102-127行目を更新)

```python
class EmploymentRelated(Base):
    """就労関係"""
    __tablename__ = 'employment_related'

    # 既存フィールド省略

    # 新規フィールド（Task 1）
    no_employment_experience: Mapped[bool] = mapped_column(Boolean, default=False)
    attended_job_selection_office: Mapped[bool] = mapped_column(Boolean, default=False)
    received_employment_assessment: Mapped[bool] = mapped_column(Boolean, default=False)
    employment_other_experience: Mapped[bool] = mapped_column(Boolean, default=False)
    employment_other_text: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    # タイムスタンプ、リレーション省略
```

**Step 3: Pydanticスキーマ更新**

**ファイル**: `k_back/app/schemas/assessment.py` (423-512行目を更新)

```python
class EmploymentBase(BaseModel):
    """就労関係の基本スキーマ"""
    model_config = ConfigDict(populate_by_name=True)

    # 既存フィールド省略

    # 新規フィールド（Task 1）
    no_employment_experience: bool = Field(False, description="就労経験なし")
    attended_job_selection_office: bool = Field(False, description="就労選択事業所に通所した")
    received_employment_assessment: bool = Field(False, description="就労アセスメント受けた")
    employment_other_experience: bool = Field(False, description="その他の就労経験")
    employment_other_text: Optional[str] = Field(None, max_length=500, description="その他の詳細")

    @field_validator('employment_other_text')
    @classmethod
    def validate_employment_other_text(cls, v: Optional[str]) -> Optional[str]:
        """その他テキストは500文字以内"""
        if v and len(v) > 500:
            raise ValueError('その他テキストは500文字以内で入力してください')
        return v

    @model_validator(mode='after')
    def validate_no_employment_children(self):
        """就労経験なしがFalseの場合、子チェックボックスも自動的にFalseにする"""
        if not self.no_employment_experience:
            self.attended_job_selection_office = False
            self.received_employment_assessment = False
            self.employment_other_experience = False
            self.employment_other_text = None
        return self

class EmploymentUpdate(BaseModel):
    """就労関係更新時のスキーマ"""
    # 既存フィールド省略

    # 新規フィールド（Task 1）
    no_employment_experience: Optional[bool] = None
    attended_job_selection_office: Optional[bool] = None
    received_employment_assessment: Optional[bool] = None
    employment_other_experience: Optional[bool] = None
    employment_other_text: Optional[str] = Field(None, max_length=500)
```

**Step 4: テスト実行**

```bash
cd k_back
docker exec keikakun_app-backend-1 pytest tests/models/test_assessment_models.py::test_employment_related_no_experience_fields -v
docker exec keikakun_app-backend-1 pytest tests/services/test_assessment_service.py::test_create_employment_with_no_experience -v
docker exec keikakun_app-backend-1 pytest tests/api/v1/test_assessment.py::test_update_employment_no_experience_validation -v
```

---

#### 1.3 TDD Phase 3: Refactor（リファクタリング）

**確認事項**:
- [ ] コード重複の除去
- [ ] バリデータの共通化
- [ ] ドキュメント更新

**実装なし**: 現時点では不要（シンプルな実装のため）

---

### 🔴 Priority 2: asoBeで希望する作業 テキストボックス追加（Task 2）

**概要**: `desired_tasks_on_asobe` フィールドを追加

**影響範囲**:
- DB: `employment_related` テーブルに1カラム追加
- Backend: モデル、スキーマ、マイグレーション
- Frontend: アセスメント編集モーダル
- Tests: 3ファイル

---

#### 2.1 TDD Phase 1: Red（失敗するテストを書く）

**ファイル**: `k_back/tests/models/test_assessment_models.py`

```python
@pytest.mark.asyncio
async def test_employment_related_desired_tasks_on_asobe(db_session: AsyncSession):
    """asoBeで希望する作業フィールドのテスト"""
    # Arrange
    employment = EmploymentRelated(
        welfare_recipient_id=...,
        created_by_staff_id=...,
        work_conditions=WorkConditions.continuous_support_b,
        # 既存フィールド省略
        desired_tasks_on_asobe="清掃作業、軽作業を希望します"
    )

    # Act
    db_session.add(employment)
    await db_session.commit()
    await db_session.refresh(employment)

    # Assert
    assert employment.desired_tasks_on_asobe == "清掃作業、軽作業を希望します"
```

**ファイル**: `k_back/tests/api/v1/test_assessment.py`

```python
@pytest.mark.asyncio
async def test_update_employment_desired_tasks_validation(
    async_client: AsyncClient,
    employee_user_factory
):
    """バリデーション: 1000文字を超えるとエラー"""
    # Arrange
    staff = await employee_user_factory()
    token = create_access_token(str(staff.id), timedelta(minutes=30))
    long_text = "あ" * 1001  # 1001文字

    # Act
    response = await async_client.patch(
        f"/api/v1/welfare-recipients/{recipient_id}/employment",
        headers={"Authorization": f"Bearer {token}"},
        json={"desired_tasks_on_asobe": long_text}
    )

    # Assert
    assert response.status_code == 422
    assert "1000文字以内" in response.json()["detail"][0]["msg"]
```

---

#### 2.2 TDD Phase 2: Green（最小限のコードで通す）

**Step 1: マイグレーション作成**

```bash
cd k_back
alembic revision -m "add_desired_tasks_on_asobe_to_employment_related"
```

**ファイル**: `k_back/migrations/versions/xxxx_add_desired_tasks_on_asobe.py`

```python
"""add_desired_tasks_on_asobe_to_employment_related

Revision ID: xxxx
Revises: yyyy
Create Date: 2026-01-08
"""
from alembic import op
import sqlalchemy as sa

revision = 'xxxx'
down_revision = 'yyyy'
branch_labels = None
depends_on = None

def upgrade():
    op.add_column('employment_related',
        sa.Column('desired_tasks_on_asobe', sa.Text(), nullable=True)
    )

def downgrade():
    op.drop_column('employment_related', 'desired_tasks_on_asobe')
```

**Step 2: モデル更新**

**ファイル**: `k_back/app/models/assessment.py` (追加)

```python
class EmploymentRelated(Base):
    # 既存フィールド省略

    # 新規フィールド（Task 2）
    desired_tasks_on_asobe: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
```

**Step 3: Pydanticスキーマ更新**

**ファイル**: `k_back/app/schemas/assessment.py` (追加)

```python
class EmploymentBase(BaseModel):
    # 既存フィールド省略

    # 新規フィールド（Task 2）
    desired_tasks_on_asobe: Optional[str] = Field(None, max_length=1000, description="asoBeで希望する作業")

    @field_validator('desired_tasks_on_asobe')
    @classmethod
    def validate_desired_tasks(cls, v: Optional[str]) -> Optional[str]:
        """asoBeで希望する作業は1000文字まで"""
        if v and len(v) > 1000:
            raise ValueError('asoBeで希望する作業は1000文字以内で入力してください')
        return v

class EmploymentUpdate(BaseModel):
    # 既存フィールド省略

    # 新規フィールド（Task 2）
    desired_tasks_on_asobe: Optional[str] = Field(None, max_length=1000)
```

**Step 4: テスト実行**

```bash
docker exec keikakun_app-backend-1 pytest tests/models/test_assessment_models.py::test_employment_related_desired_tasks_on_asobe -v
docker exec keikakun_app-backend-1 pytest tests/api/v1/test_assessment.py::test_update_employment_desired_tasks_validation -v
```

---

### 🔴 Priority 3: サイクル処理の統一（Task 4）

**概要**: cycle_number の分岐を削除し、全サイクルを統一

**影響範囲**:
- Backend: サービス層2ファイル、7箇所の分岐削除
- Tests: 6ファイル、ステップ数のアサーション変更
- Database: スキーマ変更なし
- Frontend: 変更なし

**非機能要件**:
- ✅ データ整合性: 既存サイクルに影響なし（新規サイクルのみ適用）
- ✅ パフォーマンス: ロジック簡略化により若干向上
- ⚠️ 注意: Google Calendar のモニタリングイベント作成条件は維持

---

#### 4.1 TDD Phase 1: Red（失敗するテストを書く）

**ファイル**: `k_back/tests/services/test_welfare_recipient_service.py`

```python
@pytest.mark.asyncio
async def test_create_initial_cycle_with_5_steps(
    db_session: AsyncSession,
    employee_user_factory
):
    """初期サイクル作成時、5ステップが作成されることを検証"""
    # Arrange
    staff = await employee_user_factory()
    office_id = staff.office_associations[0].office_id

    registration_data = UserRegistrationRequest(
        basic_info=BasicInfoCreate(...),
        # 省略
    )

    # Act
    recipient_id = await WelfareRecipientService.create_recipient_with_initial_plan(
        db=db_session,
        registration_data=registration_data,
        office_id=office_id
    )
    await db_session.commit()

    # Assert
    # サイクルを取得
    cycle_stmt = select(SupportPlanCycle).where(
        SupportPlanCycle.welfare_recipient_id == recipient_id,
        SupportPlanCycle.cycle_number == 1
    ).options(selectinload(SupportPlanCycle.statuses))
    cycle = (await db_session.execute(cycle_stmt)).scalar_one()

    # ステップ数を検証
    assert len(cycle.statuses) == 5  # 旧: 4 → 新: 5

    # ステップ内容を検証
    step_types = [s.step_type for s in cycle.statuses]
    expected = [
        SupportPlanStep.assessment,
        SupportPlanStep.draft_plan,
        SupportPlanStep.staff_meeting,
        SupportPlanStep.final_plan_signed,
        SupportPlanStep.monitoring,  # 追加
    ]
    assert step_types == expected
```

**ファイル**: `k_back/tests/services/test_support_plan_service.py`

```python
@pytest.mark.asyncio
async def test_create_new_cycle_starts_with_assessment(
    db_session: AsyncSession,
    employee_user_factory,
    welfare_recipient_factory
):
    """2回目以降のサイクルもassessmentから開始することを検証"""
    # Arrange
    staff = await employee_user_factory()
    recipient = await welfare_recipient_factory(office_id=staff.office_associations[0].office_id)

    # 1回目のサイクルを完了させる
    cycle1 = await create_completed_cycle(db_session, recipient.id)

    # Act: final_plan_signed PDFアップロード（新サイクル作成トリガー）
    deliverable = await support_plan_service.handle_deliverable_upload(
        db=db_session,
        deliverable_in=PlanDeliverableCreate(
            plan_cycle_id=cycle1.id,
            deliverable_type=DeliverableType.final_plan_signed_pdf,
            file_path="s3://...",
            original_filename="plan.pdf"
        ),
        uploaded_by_staff_id=staff.id
    )

    # Assert
    # 2回目のサイクルを取得
    cycle2_stmt = select(SupportPlanCycle).where(
        SupportPlanCycle.welfare_recipient_id == recipient.id,
        SupportPlanCycle.cycle_number == 2
    ).options(selectinload(SupportPlanCycle.statuses))
    cycle2 = (await db_session.execute(cycle2_stmt)).scalar_one()

    # 5ステップが作成され、最初が assessment であることを検証
    assert len(cycle2.statuses) == 5
    assert cycle2.statuses[0].step_type == SupportPlanStep.assessment
    assert cycle2.statuses[0].is_latest_status is True
```

---

#### 4.2 TDD Phase 2: Green（最小限のコードで通す）

**Step 1: support_plan_service.py の変更（3箇所）**

**ファイル**: `k_back/app/services/support_plan_service.py`

**変更1**: Lines 356-369 → 統一

```python
# BEFORE
if cycle.cycle_number == 1:
    cycle_steps = [
        SupportPlanStep.assessment,
        SupportPlanStep.draft_plan,
        SupportPlanStep.staff_meeting,
        SupportPlanStep.final_plan_signed,
    ]
else:
    cycle_steps = [
        SupportPlanStep.monitoring,
        SupportPlanStep.draft_plan,
        SupportPlanStep.staff_meeting,
        SupportPlanStep.final_plan_signed,
    ]

# AFTER
cycle_steps = [
    SupportPlanStep.assessment,
    SupportPlanStep.draft_plan,
    SupportPlanStep.staff_meeting,
    SupportPlanStep.final_plan_signed,
    SupportPlanStep.monitoring,
]
```

**変更2**: Lines 503-516 → 統一（削除処理も同様）

**変更3**: Lines 110-116 → 統一（新サイクル作成）

```python
# BEFORE
new_steps = [
    SupportPlanStep.monitoring,
    SupportPlanStep.draft_plan,
    SupportPlanStep.staff_meeting,
    SupportPlanStep.final_plan_signed,
]

# AFTER
new_steps = [
    SupportPlanStep.assessment,
    SupportPlanStep.draft_plan,
    SupportPlanStep.staff_meeting,
    SupportPlanStep.final_plan_signed,
    SupportPlanStep.monitoring,
]
```

---

**Step 2: welfare_recipient_service.py の変更（4箇所）**

**ファイル**: `k_back/app/services/welfare_recipient_service.py`

**変更1**: Lines 160-173 → 統一

```python
# BEFORE
if new_cycle_number == 1:
    initial_steps = [...]
else:
    initial_steps = [...]

# AFTER
initial_steps = [
    SupportPlanStep.assessment,
    SupportPlanStep.draft_plan,
    SupportPlanStep.staff_meeting,
    SupportPlanStep.final_plan_signed,
    SupportPlanStep.monitoring,
]
```

**変更2**: Lines 261-274 → 統一（同期版）

**変更3**: Lines 334-347 → 統一（整合性チェック）

**変更4**: Lines 433-446 → 統一（修復処理）

---

**Step 3: テスト実行**

```bash
# サイクル作成テスト
docker exec keikakun_app-backend-1 pytest tests/services/test_welfare_recipient_service.py::test_create_initial_cycle_with_5_steps -v

# 新サイクル作成テスト
docker exec keikakun_app-backend-1 pytest tests/services/test_support_plan_service.py::test_create_new_cycle_starts_with_assessment -v

# 全体テスト（影響範囲確認）
docker exec keikakun_app-backend-1 pytest tests/services/test_support_plan_service.py -v
docker exec keikakun_app-backend-1 pytest tests/services/test_welfare_recipient_service.py -v
```

---

#### 4.3 TDD Phase 3: Refactor（リファクタリング）

**確認事項**:
- [ ] 重複コードの除去（ステップ配列を定数化）
- [ ] ドキュメント更新

**リファクタリング案**:

```python
# app/services/support_plan_service.py

# 定数化
UNIFIED_CYCLE_STEPS = [
    SupportPlanStep.assessment,
    SupportPlanStep.draft_plan,
    SupportPlanStep.staff_meeting,
    SupportPlanStep.final_plan_signed,
    SupportPlanStep.monitoring,
]

# 使用箇所で参照
cycle_steps = UNIFIED_CYCLE_STEPS
```

---

### 🟡 Priority 4: モニタリングタブの配置変更（Task 3）

**概要**: フロントエンドのタブ表示順序のみ変更

**影響範囲**:
- Frontend: タブコンポーネントの順序変更
- Backend: **変更なし**
- Tests: E2Eテストのアサーション修正

**非機能要件**:
- ✅ セキュリティ: 影響なし
- ✅ パフォーマンス: 影響なし
- ✅ データ整合性: 影響なし

**実装詳細**: フロントエンド担当者に委譲

---

## TDD実装フロー

### 全体の流れ

```
1. Red: 失敗するテストを書く
   ↓
2. Green: テストが通る最小限のコードを書く
   ↓
3. Refactor: コードを整理する
   ↓
4. 次のタスクへ
```

### 推奨実装順序

```
Phase 1: Task 2（最もシンプル）
  → 1フィールド追加のみ
  → TDDの練習として最適

Phase 2: Task 1（やや複雑）
  → 5フィールド追加 + バリデーション
  → 相互依存のバリデーション実装

Phase 3: Task 4（最も影響範囲が広い）
  → 7箇所のロジック変更
  → 6ファイルのテスト修正
  → 慎重な実装が必要

Phase 4: Task 3（フロントエンドのみ）
  → バックエンド完了後に実装
```

---

## チェックリスト

### Task 1: 就労関係のチェックボックス追加

**Backend**:
- [ ] マイグレーション作成・実行
- [ ] モデル更新
- [ ] Pydanticスキーマ更新（Base, Create, Update, Response）
- [ ] バリデータ実装
- [ ] モデルテスト作成・実行
- [ ] サービステスト作成・実行
- [ ] APIテスト作成・実行

**Frontend**:
- [ ] TypeScript型定義更新
- [ ] モーダルUIにチェックボックス追加
- [ ] 条件付き表示ロジック実装
- [ ] バリデーション実装

**確認**:
- [ ] マイグレーション downgrade 動作確認
- [ ] 既存データへの影響確認（デフォルト値）
- [ ] セキュリティレビュー（XSS, SQLi）
- [ ] パフォーマンステスト（負荷なし）

---

### Task 2: asoBeで希望する作業 追加

**Backend**:
- [ ] マイグレーション作成・実行
- [ ] モデル更新
- [ ] Pydanticスキーマ更新
- [ ] バリデータ実装
- [ ] モデルテスト作成・実行
- [ ] APIテスト作成・実行

**Frontend**:
- [ ] TypeScript型定義更新
- [ ] モーダルUIにテキストボックス追加
- [ ] バリデーション実装（1000文字制限）

**確認**:
- [ ] マイグレーション downgrade 動作確認
- [ ] 既存データへの影響確認
- [ ] セキュリティレビュー

---

### Task 4: サイクル処理の統一

**Backend**:
- [ ] support_plan_service.py: 3箇所修正
- [ ] welfare_recipient_service.py: 4箇所修正
- [ ] 既存テストの修正（6ファイル）
- [ ] 新規テスト作成（統一後の動作検証）
- [ ] 全体テスト実行（リグレッション確認）

**確認**:
- [ ] 既存サイクルへの影響確認
- [ ] 新規サイクル作成の動作確認
- [ ] Google Calendar イベント作成の動作確認
- [ ] パフォーマンステスト

---

### Task 3: モニタリングタブ配置変更

**Frontend**:
- [ ] タブコンポーネント順序変更
- [ ] E2Eテスト修正

**確認**:
- [ ] タブクリック動作確認
- [ ] PDFアップロード順序が変わっていないことを確認

---

## 見積もり

| タスク | 工数（人日） | 優先度 |
|-------|------------|--------|
| Task 1: 就労関係のチェックボックス追加 | 3-4日 | 🔴 High |
| Task 2: asoBeで希望する作業 追加 | 1-2日 | 🔴 High |
| Task 4: サイクル処理の統一 | 3-5日 | 🔴 High |
| Task 3: モニタリングタブ配置変更 | 0.5-1日 | 🟡 Medium |
| **合計** | **7.5-12日** | - |

---

## リスクと対策

| リスク | 影響度 | 対策 |
|-------|-------|------|
| マイグレーション失敗 | High | ステージング環境で事前検証、ロールバック手順準備 |
| 既存データ不整合 | Medium | デフォルト値設定、データ移行テスト |
| テスト漏れ | Medium | カバレッジ測定、レビュー実施 |
| フロントエンド連携ミス | Low | APIスキーマ共有、統合テスト |

---

## 🎯 Task 4: フロントエンド対応の調査結果

### バックエンド完了状況（✅ 完了）

**完了日**: 2026-01-08
**Commit Hash**: `40b9c67`
**実装内容**:
- すべてのサイクル（1回目以降）で統一された5ステップ構造を採用
- `CYCLE_STEPS` 定数の追加（`app/models/enums.py`）
- `support_plan_service.py` および `welfare_recipient_service.py` の修正
- 全17テスト成功

**統一されたステップ順序**:
```
assessment → draft_plan → staff_meeting → final_plan_signed → monitoring
```

---

### フロントエンド現状分析（❌ 未対応）

#### 問題の症状
- **モニタリング列が空白**（ユーザー報告）
- cycle 1 のモニタリング欄に「-」が表示される
- cycle 2以降のアセスメント欄も表示されていない

#### 根本原因
**ファイル**: `k_front/components/protected/support_plan/SupportPlan.tsx`

**問題箇所1**: getStepLabel 関数（64-71行目）
```typescript
const getStepLabel = (stepType: string, cycleNumber: number) => {
  if (stepType === 'assessment' && cycleNumber === 1) return 'アセスメント';
  if (stepType === 'assessment' && cycleNumber > 1) return 'モニタリング'; // ❌ 古いロジック
  if (stepType === 'draft_plan') return '個別支援計画書作成';
  if (stepType === 'staff_meeting') return '担当者会議';
  if (stepType === 'final_plan_signed') return '個別支援計画書完成';
  // ❌ 'monitoring' ケースが存在しない
  return stepType;
};
```

**問題点**:
- バックエンドでは `assessment` と `monitoring` は別のステップ
- フロントエンドは cycle 2以降で `assessment` を「モニタリング」と表示
- 実際の `monitoring` ステップのラベルが定義されていない

**問題箇所2**: アセスメント列の条件（346-376行目）
```typescript
<td
  className={`... ${cycle.cycle_number === 1 ? 'cursor-pointer hover:bg-[#4f46e5]/20' : ''}`}
  onClick={cycle.cycle_number === 1 ? () => handleCellClick(cycle, 'assessment') : undefined}
>
  {cycle.cycle_number === 1 ? (
    // ✅ cycle 1 のみ表示
    <div className="flex flex-col items-center gap-2">
      {getStepIcon(assessmentStatus?.completed || false, daysRemaining || undefined)}
      {/* PDF リンク等 */}
    </div>
  ) : (
    // ❌ cycle 2以降は「-」表示
    <span className="text-xs text-[#6b7280]">-</span>
  )}
</td>
```

**問題箇所3**: モニタリング列の条件（459-489行目）
```typescript
<td
  className={`... ${cycle.cycle_number > 1 ? 'cursor-pointer hover:bg-[#4f46e5]/20' : ''}`}
  onClick={cycle.cycle_number > 1 ? () => handleCellClick(cycle, 'monitoring') : undefined}
>
  {cycle.cycle_number > 1 ? (
    // ✅ cycle 2以降のみ表示
    <div className="flex flex-col items-center gap-2">
      {getStepIcon(monitoringStatus?.completed || false)}
      {/* PDF リンク等 */}
    </div>
  ) : (
    // ❌ cycle 1 は「-」表示
    <span className="text-xs text-[#6b7280]">-</span>
  )}
</td>
```

**問題箇所4**: モバイル表示も同様（500-667行目）
- アセスメント: `cycle.cycle_number === 1` の条件（516行目）
- モニタリング: `cycle.cycle_number > 1` の条件（641行目）

---

### フロントエンド修正内容

#### 修正ファイル
`k_front/components/protected/support_plan/SupportPlan.tsx`

#### 修正箇所

**修正1: getStepLabel 関数（64-71行目）**
```typescript
// BEFORE
const getStepLabel = (stepType: string, cycleNumber: number) => {
  if (stepType === 'assessment' && cycleNumber === 1) return 'アセスメント';
  if (stepType === 'assessment' && cycleNumber > 1) return 'モニタリング'; // ❌
  if (stepType === 'draft_plan') return '個別支援計画書作成';
  if (stepType === 'staff_meeting') return '担当者会議';
  if (stepType === 'final_plan_signed') return '個別支援計画書完成';
  return stepType;
};

// AFTER
const getStepLabel = (stepType: string) => {
  if (stepType === 'assessment') return 'アセスメント'; // ✅ cycle番号不要
  if (stepType === 'draft_plan') return '個別支援計画書作成';
  if (stepType === 'staff_meeting') return '担当者会議';
  if (stepType === 'final_plan_signed') return '個別支援計画書完成';
  if (stepType === 'monitoring') return 'モニタリング'; // ✅ 追加
  return stepType;
};
```

**修正2: アセスメント列（デスクトップ表示 346-376行目）**
```typescript
// BEFORE
{cycle.cycle_number === 1 ? (
  <div className="flex flex-col items-center gap-2">
    {/* アセスメント表示 */}
  </div>
) : (
  <span className="text-xs text-[#6b7280]">-</span>
)}

// AFTER
{/* すべてのサイクルでアセスメント表示 */}
<div className="flex flex-col items-center gap-2">
  <div className="flex justify-center items-center">
    {getStepIcon(assessmentStatus?.completed || false, daysRemaining || undefined)}
  </div>
  <span className="text-xs text-[#9ca3af]">
    {assessmentStatus?.completed_at
      ? new Date(assessmentStatus.completed_at).toLocaleDateString('ja-JP')
      : '未完了'}
  </span>
  {assessmentStatus?.pdf_url && (
    <a
      href={assessmentStatus.pdf_url}
      target="_blank"
      rel="noopener noreferrer"
      className="text-xs text-[#00bcd4] hover:underline"
      onClick={(e) => e.stopPropagation()}
    >
      📄 PDF
    </a>
  )}
</div>
```

**修正3: モニタリング列（デスクトップ表示 459-489行目）**
```typescript
// BEFORE
{cycle.cycle_number > 1 ? (
  <div className="flex flex-col items-center gap-2">
    {/* モニタリング表示 */}
  </div>
) : (
  <span className="text-xs text-[#6b7280]">-</span>
)}

// AFTER
{/* すべてのサイクルでモニタリング表示 */}
<div className="flex flex-col items-center gap-2">
  <div className="flex justify-center items-center">
    {getStepIcon(monitoringStatus?.completed || false)}
  </div>
  <span className="text-xs text-[#9ca3af]">
    {monitoringStatus?.completed_at
      ? new Date(monitoringStatus.completed_at).toLocaleDateString('ja-JP')
      : '未完了'}
  </span>
  {monitoringStatus?.pdf_url && (
    <a
      href={monitoringStatus.pdf_url}
      target="_blank"
      rel="noopener noreferrer"
      className="text-xs text-[#00bcd4] hover:underline"
      onClick={(e) => e.stopPropagation()}
    >
      📄 PDF
    </a>
  )}
</div>
```

**修正4: モバイル表示（500-667行目）**
- アセスメント: `cycle.cycle_number === 1` の条件を削除（全サイクルで表示）
- モニタリング: `cycle.cycle_number > 1` の条件を削除（全サイクルで表示）

**修正5: onClick と className の調整**
```typescript
// アセスメント列
<td
  className="px-4 py-6 text-center border-r border-[#2a3441] cursor-pointer hover:bg-[#4f46e5]/20"
  onClick={() => handleCellClick(cycle, 'assessment')}
>

// モニタリング列
<td
  className="px-4 py-6 text-center cursor-pointer hover:bg-[#4f46e5]/20"
  onClick={() => handleCellClick(cycle, 'monitoring')}
>
```

---

### 影響範囲

#### 修正が必要なファイル
1. ✅ `k_front/components/protected/support_plan/SupportPlan.tsx`

#### 修正が不要なファイル
- `k_front/lib/support-plan.ts` - APIクライアント（バックエンドAPIが正しく5ステップを返すため変更不要）
- `k_front/types/enums.ts` - Enum定義（`monitoring` は既に定義済み）
- `k_front/lib/dashboardUtils.ts` - ダッシュボード集計ロジック（ステップ単位で処理しているため影響なし）

---

### テスト確認事項

#### 動作確認
- [ ] cycle 1 でアセスメント列とモニタリング列が両方表示される
- [ ] cycle 2 でアセスメント列とモニタリング列が両方表示される
- [ ] cycle 3以降も同様に5列すべて表示される
- [ ] PDFアップロード時のモーダルが正しく開く
- [ ] PDF再アップロードが正常に動作する
- [ ] モバイル表示でも全ステップが表示される

#### エッジケース
- [ ] 既存サイクル（4ステップのみ）の表示確認
  - assessment または monitoring が存在しない場合、「未完了」と表示されるか
- [ ] 新規サイクル（5ステップ）の表示確認
- [ ] ステップの完了状態アイコンが正しく表示されるか

---

### リスクと対策

| リスク | 影響度 | 対策 |
|-------|-------|------|
| 既存サイクル（4ステップ）で undefined エラー | Medium | `assessmentStatus?.completed` と optional chaining 使用済み（問題なし） |
| モバイル表示の崩れ | Low | レスポンシブデザイン維持、実機確認 |
| PDF アップロードモーダルの不具合 | Medium | 既存の handleCellClick ロジック変更なし（影響なし） |

---

### 実装順序

```
1. getStepLabel 関数の修正（cycleNumber パラメータ削除、monitoring ケース追加）
2. デスクトップ表示のアセスメント列修正（条件分岐削除）
3. デスクトップ表示のモニタリング列修正（条件分岐削除）
4. モバイル表示の同様の修正
5. ローカル環境での動作確認
6. 既存サイクルとの互換性確認
```

---

### 見積もり

| タスク | 工数 |
|-------|------|
| フロントエンド修正（SupportPlan.tsx） | 1-2時間 |
| 動作確認・テスト | 1時間 |
| **合計** | **2-3時間** |

---

## 🔄 Task 5: サイクル作成トリガーの変更調査

### 📋 要件

**変更内容**: 新サイクルの作成トリガーを「個別支援計画書本案」から「モニタリング」に変更

**現状**:
- ❌ `final_plan_signed_pdf` (個別支援計画書本案) アップロード時に次のサイクルが作成される
- これにより、モニタリング完了前に次のサイクルが表示されてしまう

**理想**:
- ✅ `monitoring_report_pdf` (モニタリング報告書) アップロード時に次のサイクルを作成
- モニタリング完了後に新しいサイクルを開始する自然な流れ

### 📊 現状仕様の調査結果

#### 1. サイクル作成トリガーの実装箇所

**ファイル**: `k_back/app/services/support_plan_service.py`

**トリガー検出部分** (Lines 306-337):
```python
if deliverable_in.deliverable_type == DeliverableType.final_plan_signed_pdf:
    logger.info(f"[FINAL_PLAN] Detected final_plan_signed_pdf upload for cycle {cycle.id}")

    # ステータス更新をデータベースに反映させるため、ここでflushを呼ぶ
    await db.flush()

    # cycle_numberが現在のサイクルより大きいサイクルがあるか確認
    future_cycle_stmt = select(SupportPlanCycle).where(
        SupportPlanCycle.welfare_recipient_id == cycle.welfare_recipient_id,
        SupportPlanCycle.cycle_number > cycle.cycle_number
    )
    future_cycle_result = await db.execute(future_cycle_stmt)
    has_future_cycles = future_cycle_result.scalar_one_or_none() is not None

    logger.info(f"[FINAL_PLAN] has_future_cycles={has_future_cycles}")

    # 既に次のサイクルが存在する場合は、未来のサイクルを削除して再定義
    if has_future_cycles:
        logger.info(f"[FINAL_PLAN] Resetting future cycles for recipient {cycle.welfare_recipient_id}")
        await SupportPlanService._reset_future_cycles(
            db,
            welfare_recipient_id=cycle.welfare_recipient_id,
            current_cycle_number=cycle.cycle_number
        )
        logger.info(f"[FINAL_PLAN] Future cycles reset completed")

    # 新しいサイクルを作成
    logger.info(f"[FINAL_PLAN] Creating new cycle from final_plan for cycle {cycle.id}")
    await SupportPlanService._create_new_cycle_from_final_plan(
        db, old_cycle=cycle, final_plan_completed_at=current_status.completed_at
    )
    logger.info(f"[FINAL_PLAN] New cycle creation completed")
```

#### 2. サイクル作成メソッド

**メソッド名**: `_create_new_cycle_from_final_plan` (Lines 72-169)

**処理内容**:
```python
async def _create_new_cycle_from_final_plan(
    db: AsyncSession,
    old_cycle: SupportPlanCycle,
    final_plan_completed_at: datetime.datetime
):
    """最終計画書アップロード時に新しいサイクルを作成する"""

    # 1. 現在のサイクルを「最新ではない」に更新
    old_cycle.is_latest_cycle = False

    # 2. 新しいサイクルを作成
    today = datetime.date.today()
    new_cycle = SupportPlanCycle(
        welfare_recipient_id=old_cycle.welfare_recipient_id,
        office_id=old_cycle.office_id,
        plan_cycle_start_date=today,
        next_renewal_deadline=today + datetime.timedelta(days=180),
        is_latest_cycle=True,
        cycle_number=old_cycle.cycle_number + 1
    )

    # 3. 新しいサイクル用の5つのステータスを作成
    for i, step_type in enumerate(CYCLE_STEPS):
        due_date = None

        if step_type == SupportPlanStep.monitoring:
            # モニタリング期限のデフォルトは7日
            monitoring_deadline = 7
            new_cycle.monitoring_deadline = monitoring_deadline
            due_date = (final_plan_completed_at + datetime.timedelta(days=monitoring_deadline)).date()

        new_status = SupportPlanStatus(
            plan_cycle_id=new_cycle.id,
            welfare_recipient_id=old_cycle.welfare_recipient_id,
            office_id=old_cycle.office_id,
            step_type=step_type,
            is_latest_status=(i == 0),  # 最初のステップ(assessment)を最新にする
            due_date=due_date
        )
        db.add(new_status)

    # 4. カレンダーイベントを作成
    # - 更新期限イベント（150日目～180日目）
    # - モニタリング期限イベント（cycle_number >= 2の場合、1日目～7日目）
    await calendar_service.create_renewal_deadline_events(...)
    await calendar_service.create_monitoring_deadline_events(...)
```

#### 3. 未来サイクルのリセットメソッド

**メソッド名**: `_reset_future_cycles` (Lines 33-68)

**目的**: 既存の未来のサイクルを削除して、新しいサイクルを再定義する

**処理内容**:
```python
async def _reset_future_cycles(
    db: AsyncSession,
    welfare_recipient_id: UUID,
    current_cycle_number: int
):
    """指定されたサイクル番号より大きいサイクルを削除し、最新のサイクルを再定義する"""

    # 現在のサイクル番号より大きいサイクルを削除
    future_cycles = await db.execute(
        select(SupportPlanCycle).where(
            SupportPlanCycle.welfare_recipient_id == welfare_recipient_id,
            SupportPlanCycle.cycle_number > current_cycle_number
        ).options(selectinload(SupportPlanCycle.statuses))
    )

    for cycle in future_cycles.scalars().all():
        # 関連するステータスを削除
        for status in cycle.statuses:
            await db.delete(status)
        # サイクルを削除
        await db.delete(cycle)

    # 最新のサイクルを再定義
    # ...
```

### 🎯 変更が必要な箇所

#### 1. トリガー条件の変更

**現状**:
```python
if deliverable_in.deliverable_type == DeliverableType.final_plan_signed_pdf:
    # サイクル作成ロジック
```

**変更後**:
```python
if deliverable_in.deliverable_type == DeliverableType.monitoring_report_pdf:
    # サイクル作成ロジック
```

#### 2. メソッド名の変更（オプション）

**現状**: `_create_new_cycle_from_final_plan`

**推奨**: `_create_new_cycle_from_monitoring` または `_create_new_cycle`

**理由**: メソッド名が「final_plan」を含むため、モニタリングトリガーには不適切

#### 3. カレンダーイベントのタイミング調整

**現状**: `final_plan_completed_at` を基準にモニタリング期限を計算

**変更後**: `monitoring_completed_at` を基準に次のサイクルの期限を計算

**影響**:
- 新しいサイクルのモニタリング期限は、前サイクルのモニタリング完了日 + 7日
- 更新期限は、前サイクルのモニタリング完了日 + 180日

#### 4. ログメッセージの更新

**現状**:
```python
logger.info(f"[FINAL_PLAN] Detected final_plan_signed_pdf upload for cycle {cycle.id}")
logger.info(f"[FINAL_PLAN] Creating new cycle from final_plan for cycle {cycle.id}")
```

**変更後**:
```python
logger.info(f"[MONITORING] Detected monitoring_report_pdf upload for cycle {cycle.id}")
logger.info(f"[MONITORING] Creating new cycle from monitoring for cycle {cycle.id}")
```

### ⚠️ 影響範囲の分析

#### 1. テストへの影響

**影響を受けるテストファイル**:
- `tests/test_support_plan_cycle.py`
  - `test_upload_final_plan_creates_new_cycle` の変更が必要
  - テスト名を `test_upload_monitoring_creates_new_cycle` に変更
  - アサーション条件を変更（final_plan → monitoring）

**検証項目**:
- モニタリングPDFアップロード後に新サイクルが作成されるか
- final_planアップロード後に新サイクルが作成**されない**か
- 新サイクルのcycle_numberが正しく増加するか
- カレンダーイベントが正しく作成されるか

#### 2. カレンダーサービスへの影響

**影響**: 軽微

**理由**:
- カレンダーイベント作成APIは変更不要
- 呼び出しタイミングが変わるだけ（final_plan時 → monitoring時）
- イベントの内容は同じ（更新期限、モニタリング期限）

#### 3. フロントエンドへの影響

**影響**: なし

**理由**:
- フロントエンドはAPIのレスポンスを表示するだけ
- サイクル作成のトリガーが変わっても、表示ロジックは同じ
- ユーザーはモニタリング完了後に自然に次のサイクルを見ることになる

### 📝 実装手順

#### Phase 1: バックエンド変更

1. **トリガー条件の変更**
   - `support_plan_service.py` Line 306 の条件を変更
   - `final_plan_signed_pdf` → `monitoring_report_pdf`

2. **メソッド名の変更**
   - `_create_new_cycle_from_final_plan` → `_create_new_cycle_from_monitoring`
   - パラメータ名を変更: `final_plan_completed_at` → `monitoring_completed_at`

3. **ログメッセージの更新**
   - `[FINAL_PLAN]` → `[MONITORING]`
   - ログ内容を適切に変更

4. **docstringの更新**
   - メソッドの説明を「モニタリングアップロード時」に変更

#### Phase 2: テスト変更

1. **テスト名の変更**
   - `test_upload_final_plan_creates_new_cycle` → `test_upload_monitoring_creates_new_cycle`

2. **テストロジックの変更**
   - final_planのアップロード → monitoringのアップロード
   - アサーション条件を調整

3. **新規テストの追加**
   - `test_upload_final_plan_does_not_create_new_cycle`（final_planアップロード時に新サイクルが作成されないことを確認）

#### Phase 3: 検証

1. **ユニットテスト実行**
   ```bash
   docker exec keikakun_app-backend-1 pytest tests/test_support_plan_cycle.py -v
   ```

2. **全テスト実行**
   ```bash
   docker exec keikakun_app-backend-1 pytest tests/ -v
   ```

3. **手動検証**
   - モニタリングPDFアップロード後の動作確認
   - カレンダーイベント作成の確認
   - フロントエンドでの表示確認

### 📊 見積もり

| タスク | 見積もり |
|--------|----------|
| バックエンド変更 | 30分 |
| テスト変更 | 30分 |
| テスト実行・デバッグ | 30分 |
| 手動検証 | 30分 |
| **合計** | **2時間** |

### ✅ 期待される結果

**変更前**:
1. アセスメント → 計画作成 → 担当者会議 → **個別支援計画書本案** ✅
2. **→ 新サイクル作成** 🆕
3. モニタリング ✅
4. サイクル2のアセスメント開始

**変更後**:
1. アセスメント → 計画作成 → 担当者会議 → 個別支援計画書本案 ✅
2. モニタリング ✅
3. **→ 新サイクル作成** 🆕
4. サイクル2のアセスメント開始

**ユーザー体験の改善**:
- より自然な流れ: モニタリング完了 → 次のサイクル開始
- 画面の混乱を防止: モニタリング中に次のサイクルが表示されない
- 期限管理の明確化: 現在のサイクルを完全に終了してから次へ

---

**最終更新**: 2026-01-08 15:10（サイクル作成トリガー調査完了）
**レビュー**: 未実施
**承認**: 未承認
