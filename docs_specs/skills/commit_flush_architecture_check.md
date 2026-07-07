# Skill: 4層アーキテクチャにおけるcommit/flush使い分けチェック

**スキルID**: `commit-flush-check`
**カテゴリ**: アーキテクチャレビュー / コード品質
**作成日**: 2026-02-18

---

## 目的

4層アーキテクチャの各層における責務に応じて、`commit()` と `flush()` が正しく使い分けられているかをチェックする。

---

## 4層アーキテクチャにおけるcommit/flushルール

### 📋 各層の責務とDB操作ルール

| 層 | ディレクトリ | commit() | flush() | 理由 |
|----|------------|----------|---------|------|
| **API層** | `app/api/v1/endpoints/` | ❌ **禁止** | ❌ **禁止** | HTTP処理のみ、ビジネスロジック/DB操作はService層に委譲 |
| **Services層** | `app/services/` | ✅ **必須** | ✅ **許可** | 複数CRUD操作のトランザクション境界を管理 |
| **CRUD層** | `app/crud/` | ✅ **許可** | ✅ **必須** | 単一モデルのCRUD操作後にcommit（単純な場合） |
| **Models層** | `app/models/` | ❌ **禁止** | ❌ **禁止** | データ定義のみ、DB操作なし |

---

## チェック項目

### 1. API層のcommit/flush禁止チェック

**❌ 悪い例**:
```python
# app/api/v1/endpoints/users.py
@router.post("/")
async def create_user(
    user_in: UserCreate,
    db: AsyncSession = Depends(get_db)
):
    user = User(**user_in.dict())
    db.add(user)
    await db.commit()  # ❌ API層でcommitしてはいけない
    await db.refresh(user)
    return user
```

**✅ 良い例**:
```python
# app/api/v1/endpoints/users.py
@router.post("/")
async def create_user(
    user_in: UserCreate,
    db: AsyncSession = Depends(get_db),
    current_user: Staff = Depends(deps.get_current_user)
):
    # ビジネスロジック/DB操作はService層に委譲
    user = await user_service.create_user(db=db, user_in=user_in, created_by=current_user.id)
    return user  # ✅ API層はService層を呼ぶだけ
```

---

### 2. Service層のcommit必須チェック

**❌ 悪い例**:
```python
# app/services/user_service.py
async def create_user_with_profile(
    db: AsyncSession,
    user_in: UserCreate,
    profile_in: ProfileCreate
):
    # 複数のCRUD操作を呼ぶが、commitしていない
    user = await crud.user.create(db=db, obj_in=user_in)
    profile = await crud.profile.create(db=db, user_id=user.id, obj_in=profile_in)
    # ❌ commitがないため、トランザクションが完了しない
    return user
```

**✅ 良い例**:
```python
# app/services/user_service.py
async def create_user_with_profile(
    db: AsyncSession,
    user_in: UserCreate,
    profile_in: ProfileCreate
):
    # 複数CRUD操作のトランザクション境界を管理
    user = await crud.user.create(db=db, obj_in=user_in)
    await db.flush()  # ✅ user.idを取得するためflush

    profile = await crud.profile.create(db=db, user_id=user.id, obj_in=profile_in)

    await db.commit()  # ✅ Service層でトランザクションをcommit
    await db.refresh(user)
    await db.refresh(profile)
    return user, profile
```

---

### 3. CRUD層のflush必須チェック（ID取得が必要な場合）

**❌ 悪い例**:
```python
# app/crud/crud_user.py
async def create(
    db: AsyncSession,
    obj_in: UserCreate
) -> User:
    user = User(**obj_in.dict())
    db.add(user)
    # ❌ user.idが必要な場合、flushしないとIDが取得できない
    return user  # user.id is None!
```

**✅ 良い例**:
```python
# app/crud/crud_user.py
async def create(
    db: AsyncSession,
    obj_in: UserCreate
) -> User:
    user = User(**obj_in.dict())
    db.add(user)
    await db.flush()  # ✅ IDを取得するためflush
    return user  # user.id is available
```

---

### 4. CRUD層のcommit判断チェック

**単純なCRUD操作の場合**:
```python
# ✅ 良い例: 単一モデルの単純なCRUD操作
async def create(db: AsyncSession, obj_in: UserCreate) -> User:
    user = User(**obj_in.dict())
    db.add(user)
    await db.commit()  # ✅ 単純な操作はCRUD層でcommit可
    await db.refresh(user)
    return user
```

**複雑なビジネスロジックが絡む場合**:
```python
# ✅ 良い例: Service層でトランザクション管理
# CRUD層
async def create(db: AsyncSession, obj_in: UserCreate) -> User:
    user = User(**obj_in.dict())
    db.add(user)
    await db.flush()  # ✅ commitはService層に任せる
    return user

# Service層
async def create_user_with_billing(db: AsyncSession, user_in: UserCreate):
    user = await crud.user.create(db=db, obj_in=user_in)
    billing = await crud.billing.create_for_user(db=db, user_id=user.id)
    await db.commit()  # ✅ 複数操作のトランザクションをService層で管理
    return user
```

---

## チェックコマンド

### API層でのcommit/flush検出

```bash
# API層でcommit/flushを使っている箇所を検出（禁止）
grep -rn "await db.commit()\|await db.flush()" k_back/app/api/v1/endpoints/
```

**期待結果**: 0件（見つかったら修正が必要）

---

### Service層でのcommit漏れ検出

```bash
# Service層でcrud呼び出しがあるがcommitがないファイルを検出
for file in k_back/app/services/*.py; do
  if grep -q "await crud\." "$file" && ! grep -q "await db.commit()" "$file"; then
    echo "⚠️  Commit missing: $file"
  fi
done
```

---

### CRUD層のflush/commit使用状況確認

```bash
# CRUD層でのcommit/flush使用状況を確認
grep -rn "await db.commit()\|await db.flush()" k_back/app/crud/ | \
  grep -v "__pycache__" | \
  awk -F: '{print $1}' | sort | uniq -c
```

---

## よくある違反パターン

### パターン1: API層でのcommit（最も重大）

```python
# ❌ 違反例
@router.post("/users/")
async def create_user(user_in: UserCreate, db: AsyncSession = Depends(get_db)):
    user = User(**user_in.dict())
    db.add(user)
    await db.commit()  # ❌ API層でcommit
    return user
```

**問題点**:
- ビジネスロジックがAPI層に漏れる
- テストが困難
- トランザクション管理が分散

**修正方法**:
1. Service層に `create_user()` メソッドを作成
2. API層はService層を呼ぶだけに変更

---

### パターン2: Service層でのcommit漏れ

```python
# ❌ 違反例
async def create_user_and_send_email(db: AsyncSession, user_in: UserCreate):
    user = await crud.user.create(db=db, obj_in=user_in)
    await send_welcome_email(user.email)
    # ❌ commitがない → userがDBに保存されない
    return user
```

**問題点**:
- トランザクションが完了しない
- ロールバックができない
- データ整合性が保証されない

**修正方法**:
```python
# ✅ 修正後
async def create_user_and_send_email(db: AsyncSession, user_in: UserCreate):
    user = await crud.user.create(db=db, obj_in=user_in)
    await db.commit()  # ✅ commitを追加
    await db.refresh(user)
    await send_welcome_email(user.email)
    return user
```

---

### パターン3: flush()せずにIDを参照

```python
# ❌ 違反例
async def create_with_relation(db: AsyncSession, obj_in: UserCreate):
    user = User(**obj_in.dict())
    db.add(user)
    # ❌ flushしないとuser.idが取得できない
    profile = Profile(user_id=user.id)  # user.id is None!
    db.add(profile)
    await db.commit()
```

**修正方法**:
```python
# ✅ 修正後
async def create_with_relation(db: AsyncSession, obj_in: UserCreate):
    user = User(**obj_in.dict())
    db.add(user)
    await db.flush()  # ✅ IDを取得

    profile = Profile(user_id=user.id)  # ✅ user.idが利用可能
    db.add(profile)
    await db.commit()
```

---

## チェックリスト

- [ ] API層に `await db.commit()` または `await db.flush()` が存在しないか？
- [ ] Service層で複数のCRUD操作後に `await db.commit()` があるか？
- [ ] CRUD層で生成されたIDを使う場合、`await db.flush()` があるか？
- [ ] エラー発生時に適切にロールバックされるか？
- [ ] トランザクション境界が明確か？

---

## 修正優先度

| 優先度 | 違反パターン | 影響度 | 修正難易度 |
|-------|------------|-------|----------|
| 🔴 **最高** | API層でのcommit | データ整合性・アーキテクチャ崩壊 | 中 |
| 🟠 **高** | Service層でのcommit漏れ | データ未保存・トランザクション不完全 | 低 |
| 🟡 **中** | flush()せずにID参照 | NoneTypeエラー | 低 |
| 🟢 **低** | 不要なflush() | パフォーマンス低下（軽微） | 低 |

---

## 参考資料

- `/.claude/CLAUDE.md` - 4層アーキテクチャガイドライン
- `/.claude/rules/architecture.md` - アーキテクチャルール詳細
- `/.claude/rules/sqlalchemy-best-practices.md` - SQLAlchemy使用ガイド

---

**更新日**: 2026-02-18
**メンテナー**: Claude Sonnet 4.5
