# 退会処理API レビューと修正

## 問題の概要

### MissingGreenletエラー
**エラー内容**: `sqlalchemy.exc.MissingGreenlet: greenlet_spawn has not been called; can't call await_only() here`

**発生箇所**: `POST /api/v1/withdrawal-requests` (Line 142)

**原因**:
```python
await db.commit()

# ❌ 問題: commitの後、デタッチされたオブジェクトのIDにアクセス
loaded_request = await crud_approval_request.get_by_id_with_relations(db, approval_req.id)
```

`db.commit()`の後、`approval_req`オブジェクトはセッションからデタッチされます。その後`approval_req.id`にアクセスしようとすると、SQLAlchemyが遅延ロードを試みますが、非同期コンテキストではないため`MissingGreenlet`エラーが発生します。

---

## 修正内容

### ✅ 修正: IDをcommit前にキャッシュ

**ファイル**: `k_back/app/api/v1/endpoints/withdrawal_requests.py`

```python
# commitの前にIDをキャッシュ（MissingGreenletエラー対策）
request_id = approval_req.id

# 監査ログを記録
await crud_audit_log.create_log(
    db,
    actor_id=current_user.id,
    action="withdrawal.requested",
    target_type="withdrawal_request",
    target_id=request_id,  # ✅ キャッシュしたIDを使用
    # ...
)

await db.commit()

# リレーションをロードして返す（キャッシュしたIDを使用）
loaded_request = await crud_approval_request.get_by_id_with_relations(db, request_id)  # ✅
```

---

## SQLAlchemy非同期プラクティスの検証

### ✅ 適切な実装箇所

#### 1. CRUD層のトランザクション管理
**ファイル**: `crud_approval_request.py`

```python
async def approve(self, db: AsyncSession, request_id: uuid.UUID, ...):
    """承認処理"""
    # ✅ UPDATE文で更新
    await db.execute(
        update(self.model)
        .where(self.model.id == request_id)
        .values(status=RequestStatus.approved, ...)
    )

    # ✅ flush()を使用（commitはエンドポイント層で実行）
    await db.flush()

    # ✅ リレーションシップを明示的にロード
    return await self.get_by_id_with_relations(db, request_id)
```

**良い点**:
- CRUD層では`flush()`を使用し、トランザクション境界をエンドポイント層で管理
- リレーションシップを`selectinload()`で明示的にロード

#### 2. リレーションシップの明示的ロード
**ファイル**: `crud_approval_request.py`

```python
async def get_by_id_with_relations(self, db: AsyncSession, request_id: uuid.UUID):
    """IDでリクエストを取得（関連データ含む）"""
    result = await db.execute(
        select(self.model)
        .where(self.model.id == request_id)
        .options(
            selectinload(self.model.requester),   # ✅ 明示的ロード
            selectinload(self.model.reviewer),    # ✅
            selectinload(self.model.office)       # ✅
        )
    )
    return result.scalar_one_or_none()
```

**良い点**:
- N+1問題を防ぐため`selectinload()`を使用
- 遅延ロードを避け、必要なリレーションシップを事前にロード

#### 3. 承認・却下エンドポイント
**ファイル**: `withdrawal_requests.py`

```python
@router.patch("/{request_id}/approve")
async def approve_withdrawal_request(..., request_id: UUID, ...):
    # ✅ リクエストIDをパラメータで受け取る
    approval_req = await crud_approval_request.get_by_id_with_relations(db, request_id)

    # ... 承認処理 ...

    await db.commit()

    # ✅ パラメータのrequest_idを使用（デタッチされたオブジェクトにアクセスしない）
    loaded_request = await crud_approval_request.get_by_id_with_relations(db, request_id)

    return _to_withdrawal_response(loaded_request)
```

**良い点**:
- パス パラメータから`request_id`を受け取るため、commit後も安全にアクセス可能

---

## 推奨事項とベストプラクティス

### 1. ✅ トランザクション境界の明確化

**原則**:
- **CRUD層**: `flush()`を使用
- **エンドポイント層**: `commit()`を使用

**理由**:
- トランザクション境界を明確にし、エラー処理とロールバックを適切に管理
- 複数のCRUD操作を1つのトランザクションにまとめられる

### 2. ✅ commit前の属性アクセス

**パターン1: IDをキャッシュ**
```python
# ✅ Good
obj_id = db_obj.id
await db.commit()
loaded_obj = await crud.get_by_id(db, obj_id)
```

**パターン2: commitの前にrefresh**
```python
# ✅ Good
await db.commit()
await db.refresh(db_obj)  # リレーションシップも再ロード
return db_obj
```

**パターン3: リレーションシップを事前ロード**
```python
# ✅ Good (create時)
db_obj = Model(...)
db.add(db_obj)
await db.flush()
await db.refresh(db_obj, ["relation1", "relation2"])  # 特定のリレーションをロード
```

### 3. ✅ リレーションシップの明示的ロード

**遅延ロードを避ける**:
```python
# ❌ Bad: 遅延ロードが発生する可能性
query = select(Model)
result = await db.execute(query)
obj = result.scalar_one()
# obj.relationにアクセスすると遅延ロードが発生

# ✅ Good: 明示的にロード
query = select(Model).options(
    selectinload(Model.relation1),
    selectinload(Model.relation2)
)
result = await db.execute(query)
obj = result.scalar_one()
```

### 4. ✅ 非同期セッションでのベストプラクティス

**DO**:
- ✅ `selectinload()`, `joinedload()`を使用してリレーションシップを事前ロード
- ✅ `await db.refresh(obj)`でオブジェクトを再ロード
- ✅ commitの前に必要な属性をキャッシュ
- ✅ CRUD層では`flush()`、エンドポイント層で`commit()`

**DON'T**:
- ❌ commitの後にデタッチされたオブジェクトの属性にアクセス
- ❌ 遅延ロードに依存する（`.lazy='select'`のデフォルト動作）
- ❌ 同期的なセッション操作を非同期コンテキストで使用

---

## チェック済みのエンドポイント

### ✅ 問題なし
1. **承認エンドポイント** (`approve_withdrawal_request`)
   - パラメータから`request_id`を受け取るため安全

2. **却下エンドポイント** (`reject_withdrawal_request`)
   - パラメータから`request_id`を受け取るため安全

3. **CRUD層** (`crud_approval_request.py`)
   - `flush()`を適切に使用
   - リレーションシップを明示的にロード

### ✅ 修正済み
1. **作成エンドポイント** (`create_withdrawal_request`)
   - IDをcommit前にキャッシュ

---

## テスト推奨事項

### 統合テスト
```python
async def test_create_withdrawal_request():
    """退会リクエスト作成のテスト"""
    # Arrange
    owner = await owner_user_factory()

    # Act
    response = await async_client.post(
        "/api/v1/withdrawal-requests",
        json={"title": "退会申請", "reason": "理由"}
    )

    # Assert
    assert response.status_code == 201
    data = response.json()
    assert data["requester_name"] is not None  # リレーションシップがロードされている
    assert data["office_name"] is not None
```

---

## まとめ

### 修正内容
- ✅ `create_withdrawal_request`エンドポイントでIDをcommit前にキャッシュ

### 検証済み
- ✅ CRUD層のトランザクション管理は適切
- ✅ リレーションシップの明示的ロードは適切
- ✅ 承認・却下エンドポイントは安全

### 推奨事項
- ✅ トランザクション境界を明確にする（CRUD層で`flush()`、エンドポイント層で`commit()`）
- ✅ commitの前に必要な属性をキャッシュ
- ✅ リレーションシップを`selectinload()`で明示的にロード
- ✅ 遅延ロードを避ける
