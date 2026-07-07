# Dependency Injection（依存性注入）

## 概要

FastAPI の `Depends()` を活用し、DBセッション・認証・権限チェック・CSRF検証をエンドポイントに注入する。依存関数はすべて `app/api/deps.py` に集約されている。

---

## DBセッション注入

**ファイル**: `app/api/deps.py`

```python
async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """各APIリクエストに対して独立したDBセッションを提供"""
    async with AsyncSessionLocal() as session:
        yield session
```

- リクエストごとに新規セッションを作成
- レスポンス後に自動クローズ（コンテキストマネージャ）
- `autocommit=False`: 明示的なコミットが必要

### 使用例
```python
@router.get("/staffs/{staff_id}")
async def get_staff(
    staff_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
):
    ...
```

---

## 認証ユーザー注入

**ファイル**: `app/api/deps.py`（`get_current_user`）

### 認証優先順位
1. Cookie: `access_token`（ブラウザからのリクエスト）
2. Authorization ヘッダー: `Bearer <token>`（APIクライアント）

### 検証項目
| チェック項目 | 異常時のレスポンス |
|------------|----------------|
| JWTトークンのデコード | 401 Unauthorized |
| スタッフの論理削除フラグ（`is_deleted`） | 401 Unauthorized |
| 所属事業所の削除状態 | 401 Unauthorized |
| パスワード変更後のトークン失効（`password_changed_at > iat`） | 401 Unauthorized |

```python
async def get_current_user(
    request: Request,
    db: AsyncSession = Depends(get_db),
    token: Optional[str] = Depends(reusable_oauth2),
) -> Staff:
    # Cookie → Bearer の順でトークン取得
    # JWTデコード → スタッフ取得 → 各種検証
    ...
```

### リレーション読み込み
```python
stmt = select(Staff).where(Staff.id == user_id).options(
    selectinload(Staff.office_associations).selectinload(OfficeStaff.office)
)
```

---

## 権限チェック依存関数

**ファイル**: `app/api/deps.py`

### `require_manager_or_owner`
- 許可: Manager / Owner
- 拒否: Employee → 403 Forbidden

### `require_owner`
- 許可: Owner のみ
- 拒否: Manager, Employee → 403 Forbidden

### `require_app_admin`
- 許可: `app_admin` ロール（システム管理者）
- 拒否: その他すべて → 403 Forbidden

### 使用例
```python
@router.delete("/staffs/{staff_id}")
async def delete_staff(
    staff_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_staff: Staff = Depends(require_owner),  # Ownerのみ
):
    ...
```

---

## 課金ステータスチェック

**ファイル**: `app/api/deps.py`（`require_active_billing`）

```python
async def require_active_billing(
    current_staff: Staff = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Staff:
    billing = await crud.billing.get_by_office_id(db=db, office_id=current_staff.office_id)
    if billing.billing_status in (BillingStatus.past_due, BillingStatus.canceled):
        raise HTTPException(status_code=402, detail="お支払いが完了していません")
    return current_staff
```

| 課金ステータス | アクセス |
|--------------|---------|
| `free` | ✅ 許可 |
| `active` | ✅ 許可 |
| `past_due` | ❌ 402 Payment Required |
| `canceled` | ❌ 402 Payment Required |

---

## Employee 制限チェック

**ファイル**: `app/api/deps.py`（`check_employee_restriction`）

- Manager / Owner: 直接実行可能（`None` 返却）
- Employee: `ApprovalRequest` を作成して承認待ち状態にする

```python
async def check_employee_restriction(
    db: AsyncSession,
    current_staff: Staff,
    resource_type: ResourceType,
    action_type: ActionType,
    resource_id: Optional[uuid.UUID] = None,
    request_data: Optional[dict] = None,
) -> Optional[ApprovalRequest]:
    if current_staff.role in (StaffRole.manager, StaffRole.owner):
        return None  # 直接実行
    # Employee → 承認リクエスト作成
    return await crud.approval_request.create(...)
```

---

## CSRF 検証依存関数

**ファイル**: `app/api/deps.py`（`validate_csrf`）

```python
async def validate_csrf(request: Request) -> None:
    # Bearer認証はスキップ（APIクライアント向け）
    if request.headers.get("Authorization", "").startswith("Bearer "):
        return
    # Cookie認証時のみCSRF検証
    await csrf_protect.validate_csrf(request)
```

- 対象メソッド: POST / PUT / PATCH / DELETE
- スキップ条件: `Authorization: Bearer` ヘッダーが存在する場合

---

## 依存関数の組み合わせ例

```python
@router.post(
    "/individual-support-plans",
    response_model=schemas.SupportPlan,
)
async def create_support_plan(
    *,
    db: AsyncSession = Depends(get_db),                        # DBセッション
    current_staff: Staff = Depends(require_active_billing),    # 認証 + 課金チェック
    _: None = Depends(validate_csrf),                          # CSRF検証
    plan_in: schemas.SupportPlanCreate,
):
    approval = await check_employee_restriction(               # Employee制限
        db=db,
        current_staff=current_staff,
        resource_type=ResourceType.support_plan,
        action_type=ActionType.create,
    )
    if approval:
        return approval  # 承認待ちレスポンス
    return await support_plan_service.create(db=db, plan_in=plan_in)
```

---

## 依存関係の階層

```
get_db
  └─ get_current_user (get_db を内包)
       ├─ require_manager_or_owner (get_current_user を内包)
       ├─ require_owner (get_current_user を内包)
       ├─ require_app_admin (get_current_user を内包)
       └─ require_active_billing (get_current_user + get_db を内包)

validate_csrf (独立した依存関数)
```
