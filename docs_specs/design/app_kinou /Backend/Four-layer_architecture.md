# Four-Layer Architecture（4層アーキテクチャ）

## 概要

FastAPI バックエンドは厳格な4層構造で実装されている。各層は単一の責務を持ち、上位層から下位層への一方向依存のみ許可される。

```
API層 (app/api/v1/endpoints/)
  ↓  Depends() 経由でONEサービスメソッドを呼び出す
Services層 (app/services/)
  ↓  複数のCRUD操作を組み合わせてビジネスロジックを実装
CRUD層 (app/crud/)
  ↓  単一モデルのCRUD操作のみ（SELECT/INSERT/UPDATE/DELETE）
Models層 (app/models/)
  ↓  SQLAlchemy ORMクラス
PostgreSQL
```

---

## API層 (`app/api/v1/endpoints/`)

### 責務
- HTTPリクエスト / レスポンス処理
- パスパラメータ・クエリパラメータ・ボディのバリデーション
- `Depends()` による認証・権限チェック
- **ONE** サービスメソッドの呼び出し
- レスポンススキーマへの変換

### 禁止事項
- CRUD層の直接呼び出し
- ビジネスロジックの実装
- `db.commit()` の呼び出し

### 実装例
```python
@router.post("/register-admin", response_model=schemas.staff.Staff)
async def register_admin(
    *,
    db: AsyncSession = Depends(deps.get_db),
    staff_in: schemas.staff.AdminCreate,
):
    user = await staff_crud.get_by_email(db, email=staff_in.email)
    if user:
        raise HTTPException(status_code=409, detail="このメールアドレスは既に使用されています")

    user = await auth_service.register_admin(db=db, staff_in=staff_in)
    return user
```

---

## Services層 (`app/services/`)

### 責務
- ビジネスロジックの実装
- 複数のCRUD操作の組み合わせ
- トランザクション管理（`db.commit()` / `db.rollback()`）
- API層へのDTOレスポンス生成

### 禁止事項
- DBテーブル構造への直接依存
- API層の関心事（HTTP, スキーマ変換）

### 実装例
```python
class AuthService:
    async def register_admin(self, db: AsyncSession, *, staff_in):
        user = await crud.staff.create_admin(db=db, obj_in=staff_in)
        user_id = user.id
        try:
            await db.commit()
        except Exception:
            await db.rollback()
            raise

        stmt = (
            select(Staff)
            .options(selectinload(Staff.office_associations).selectinload(OfficeStaff.office))
            .where(Staff.id == user_id)
        )
        result = await db.execute(stmt)
        return result.scalar_one()
```

### 主なサービスファイル
| ファイル | 責務 |
|---------|------|
| `auth_service.py` | 登録・ログイン・MFA・パスワードリセット |
| `billing_service.py` | Stripe連携・課金ステータス管理 |
| `staff_service.py` | スタッフ管理・ロール変更 |
| `notification_service.py` | 通知・Push配信 |

---

## CRUD層 (`app/crud/`)

### 責務
- 単一モデルのCRUD操作のみ
- DB抽象化レイヤー
- `flush()` でIDを確定し、コミットはServices層に委譲

### 禁止事項
- ビジネスロジックの実装
- 複数モデルにまたがる操作
- `db.commit()` の呼び出し（flush のみ許可）

### 実装例
```python
class CRUDStaff:
    async def get(self, db: AsyncSession, *, id: uuid.UUID) -> Staff | None:
        query = select(Staff).filter(Staff.id == id).options(
            selectinload(Staff.office_associations).selectinload(OfficeStaff.office),
            selectinload(Staff.mfa_backup_codes)
        )
        result = await db.execute(query)
        return result.scalar_one_or_none()

    async def create_admin(self, db: AsyncSession, *, obj_in: AdminCreate) -> Staff:
        db_obj = Staff(
            email=obj_in.email,
            hashed_password=get_password_hash(obj_in.password),
        )
        db.add(db_obj)
        await db.flush()   # IDを確定（commitはServices層で）
        await db.refresh(db_obj)
        return db_obj
```

### CRUDインポートルール（循環依存防止）

```python
# ✅ 正しい: 集約インターフェース経由
from app import crud
billing = await crud.billing.get_by_office_id(db=db, office_id=office_id)

# ❌ 禁止: 直接インポート（循環依存の原因）
from app.crud.crud_billing import crud_billing
```

---

## Models層 (`app/models/`)

### 責務
- SQLAlchemy ORMクラス定義
- テーブル構造・リレーションシップ定義
- インデックス・制約定義

### 実装例
```python
class Staff(Base):
    __tablename__ = 'staffs'

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    hashed_password: Mapped[str] = mapped_column(String(255))
    role: Mapped[StaffRole] = mapped_column(SQLAlchemyEnum(StaffRole))
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, index=True)

    office_associations: Mapped[List["OfficeStaff"]] = relationship(...)
    mfa_backup_codes: Mapped[List["MFABackupCode"]] = relationship(...)
```

### 主なモデルファイル
| ファイル | テーブル |
|---------|---------|
| `staff.py` | staffs（スタッフ） |
| `billing.py` | billings（課金情報） |
| `office.py` | offices（事業所） |
| `mfa.py` | mfa_backup_codes, mfa_audit_logs |
| `staff_profile.py` | audit_logs（監査ログ） |

---

## 層間の依存関係

```
API層 ─── Depends(deps.get_db) ────────┐
  │                                    │
  │  Depends(deps.get_current_user)    │
  │  Depends(deps.require_owner)       │ AsyncSession
  ↓                                    │
Services層 ─── from app import crud ──→ CRUD層 ──→ Models層
                                         ↑
                                    単一モデル操作のみ
```

### コミットの責任範囲

| 層 | commit | rollback | flush |
|----|--------|----------|-------|
| API層 | ❌ | ❌ | ❌ |
| Services層 | ✅ | ✅ | ❌ |
| CRUD層 | ❌ | ❌ | ✅ |
