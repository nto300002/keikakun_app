# フロントエンド
元々あるメソッドを許可なく削除するな(例: handle xx Createなどの基本に関わるメソッド)



from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

async_session = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False  # commit後もオブジェクトを使用可能に
)

async def delete_with_session():
    async with async_session() as session:
        async with session.begin():
            # 削除処理
            result = await session.execute(
                delete(Task).where(Task.id == 1)
            )
            # トランザクションは自動的にコミットされる


sqlalchemy.exc.MissingGreenletの主な原因
sqlalchemy.exc.MissingGreenletエラーは、SQLAlchemyの非同期処理において頻繁に発生する問題です。このエラーの主な原因と対処法について解説します。
主な原因
1. 遅延ロード（Lazy Loading）による非同期処理の失敗
最も一般的な原因は、AsyncSessionを使用している際に、リレーションシップ属性へのアクセス時に遅延ロード（lazy loading）が発生することです。
# エラーが発生する例
user = await session.get(User, user_id)
organization_id = user.organization_id # ここでMissingGreenletエラー
非同期環境では、属性アクセス時に暗黙的にawaitを呼び出すことができないため、エラーが発生します。
2. awaitキーワードの欠落
非同期クエリの実行時にawaitを付け忘れた場合にも発生します。
# 誤り
result = session.execute(select(User)) # awaitが必要
# 正しい
result = await session.execute(select(User))
3. 同期処理と非同期処理の混在
同期的なSessionと非同期的なAsyncSessionを混在させた場合、または非同期コンテキスト外で非同期操作を試みた場合に発生します。
解決方法
方法1: Eager Loadingの使用
クエリ実行時にjoinedload()やselectinload()を使用して、関連データを事前にロードします。
from sqlalchemy.orm import selectinload, joinedload
# selectinloadを使用（推奨）
result = await session.execute(
 select(User)
 .where(User.id == user_id)
 .options(selectinload(User.organization))
 .options(selectinload(User.email_addresses))
)
user = result.scalars().first()
# これで安全にアクセス可能
organization_id = user.organization_id
ロード戦略の違い:
 * selectinload: 別のSELECT文を発行してデータを取得（推奨）
 * joinedload: LEFT OUTER JOINを使用して一度に取得
方法2: lazy属性の設定
モデル定義時にrelationshipのlazy属性を変更します。
from sqlalchemy.orm import relationship
class User(Base):
 __tablename__ = "users"
 organization_id = Column(Integer, ForeignKey("organizations.id"))
 # lazy属性を設定
 organization = relationship(
 "Organization",
 lazy="selectin" # または "immediate", "joined"
 )
lazy属性の選択肢:
 * select（デフォルト）: プロパティアクセス時に遅延ロード → エラーの原因
 * selectin: 親オブジェクトロード時に別SELECT文で取得
 * immediate: 親オブジェクトロード時に即座にロード
 * joined: LEFT OUTER JOINで取得
 * raise: 遅延ロードを完全に禁止（開発時の検出に有効）
# raiseを使用してN+1問題を防ぐ
organization = relationship("Organization", lazy="raise")
# アクセス時にエラー: InvalidRequestError: 'User.organization' is not available due to lazy='raise'
方法3: expire_on_commit=Falseの設定
セッション作成時にexpire_on_commit=Falseを設定することで、コミット後もオブジェクトを使用可能にします。
from sqlalchemy.ext.asyncio import async_sessionmaker, AsyncSession
async_session = async_sessionmaker(
 engine,
 class_=AsyncSession,
 expire_on_commit=False # コミット後もオブジェクトを使用可能に
)
注意すべきケース
on_update属性使用時の問題
on_update属性を持つカラムで、オブジェクト取得後にUPDATE文を実行すると、予期しないMissingGreenletエラーが発生することがあります。
# 問題が発生するパターン
user = await session.get(User, user_id) # オブジェクト取得
await session.execute(update(User).where(...)) # UPDATE実行
print(user.updated_at) # MissingGreenletエラー
同一セッション内での条件による挙動の違い
同一セッション内で既にロード済みのデータは問題なくアクセスできますが、未ロードのデータにアクセスするとエラーが発生します。
# A部署の組織（既にロード済み）
user_a = await session.execute(
 select(User).options(selectinload(User.organization))
)
print(user_a.organization_id) # OK
# B部署の組織（ロードしていない）
user_b = await session.execute(select(User))
print(user_b.organization_id) # MissingGreenletエラー
推奨される対策
 1. 一律でlazy="immediate"を設定することで、予期しないエラーを防ぐ
 2. 開発時はlazy="raise"を使用してN+1問題を早期発見
 3. クエリ実行時に必要な関連データを明示的にロードする習慣をつける
 4. awaitキーワードを必ず付与する
これらの対策を適切に組み合わせることで、MissingGreenletエラーを効果的に防ぐことができます。

---

# SQLAlchemy 非同期ORM ベストプラクティスとアンチパターン

## ベストプラクティス

### 1. セッション設定
```python
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

# expire_on_commit=False を設定してcommit後もオブジェクトを使用可能にする
async_session = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False  # これにより、commit後の属性アクセスでMissingGreenletエラーを防ぐ
)
```

**理由**: `expire_on_commit=True`（デフォルト）の場合、commit後にオブジェクトのすべての属性がexpireされ、次回のアクセス時に遅延ロードが発生してMissingGreenletエラーが発生する。

### 2. Eager Loadingの使用
```python
from sqlalchemy import select
from sqlalchemy.orm import selectinload

# ❌ 悪い例: リレーションシップを含まない取得
result = await db.execute(
    select(EmployeeActionRequest)
    .where(EmployeeActionRequest.id == request_id)
)
request = result.scalar_one()
# request.requester.full_name にアクセス → MissingGreenletエラー

# ✅ 良い例: selectinloadでリレーションシップを事前ロード
result = await db.execute(
    select(EmployeeActionRequest)
    .where(EmployeeActionRequest.id == request_id)
    .options(
        selectinload(EmployeeActionRequest.requester),
        selectinload(EmployeeActionRequest.approver),
        selectinload(EmployeeActionRequest.office)
    )
)
request = result.scalar_one()
# request.requester.full_name に安全にアクセス可能
```

**Eager Loadingの種類**:
- `selectinload()`: 別のSELECT文を発行（推奨、N+1問題を防ぐ）
- `joinedload()`: LEFT OUTER JOINで一度に取得（1対多の場合は重複行に注意）
- `lazy='selectin'`: relationshipに直接設定（モデル定義時）

### 3. トランザクション境界の明確化
```python
# ❌ アンチパターン: サービス層で複数回commit
async def create_request(db, ...):
    request = await crud.create(db, ...)
    await db.commit()  # 1回目
    await self._create_notification(db, request)  # この中で2回目のcommit
    return request  # オブジェクトが2回目のcommit後にexpireされる

# ✅ ベストプラクティス: 1つのトランザクションで完結
async def create_request(db, ...):
    request = await crud.create(db, ...)
    # 通知作成（commitはしない）
    await self._create_notification_without_commit(db, request)
    # 最後に1回だけcommit
    await db.commit()
    # commit後にリレーションシップを含めて再取得
    result = await db.execute(
        select(Request)
        .where(Request.id == request.id)
        .options(selectinload(Request.requester))
    )
    return result.scalar_one()
```

### 4. refresh()の正しい使用
```python
# ❌ 悪い例: refresh()はリレーションシップを再ロードしない
await db.commit()
await db.refresh(request)  # 基本属性のみrefresh
print(request.requester.full_name)  # MissingGreenletエラー

# ✅ 良い例: selectinloadで明示的にリレーションシップを再取得
await db.commit()
result = await db.execute(
    select(Request)
    .where(Request.id == request.id)
    .options(
        selectinload(Request.requester),
        selectinload(Request.office)
    )
)
request = result.scalar_one()
print(request.requester.full_name)  # OK
```

**重要**: `refresh()`は主キーベースの属性のみを再ロードし、リレーションシップは含まれない。リレーションシップが必要な場合は、selectinloadを使用して明示的に再取得する。

## アンチパターン（role_change/employee_actionにおける実例）

### アンチパターン1: 複数回のcommitによるオブジェクトのexpire
```python
# ❌ employee_action_service.py の create_request メソッド（修正前）
async def create_request(self, db, ...):
    request = await crud_employee_action_request.create(db, ...)
    await db.commit()  # 1回目のcommit
    await db.refresh(request)  # 基本属性のみrefresh

    # この中で再度 db.commit() が呼ばれる
    await self._create_request_notification(db, request)  # 2回目のcommit

    return request  # 2回目のcommit後にexpireされたオブジェクトを返す

# テストコード
request = await employee_action_service.create_request(...)
print(request.id)  # MissingGreenletエラー（2回目のcommitでexpireされたため）
```

**問題点**:
1. `create_request`内で1回目のcommit
2. `_create_request_notification`内で2回目のcommit
3. 返されたrequestオブジェクトは2回目のcommit後にexpireされる
4. 呼び出し側でrequest.idなどにアクセスすると、遅延ロードが発生してMissingGreenlet

### アンチパターン2: 通知作成メソッド内での不適切なcommit
```python
# ❌ employee_action_service.py の _create_request_notification メソッド
async def _create_request_notification(self, db, request):
    approvers = await self._get_approvers(db, request.office_id)

    for approver_id in approvers:
        notice_data = NoticeCreate(
            recipient_staff_id=approver_id,
            office_id=request.office_id,
            type=NoticeType.employee_action_request.value,
            title="アクションリクエストが作成されました",
            content=f"{request.requester.full_name}さんが...",  # MissingGreenletエラー
            link_url=f"/employee-action-requests/{request.id}"
        )
        await crud_notice.create(db, obj_in=notice_data)

    await db.commit()  # サブメソッドがcommitするのは不適切
```

**問題点**:
1. サブメソッド（`_create_request_notification`）が独自にcommitしている
2. 親メソッドから返されるオブジェクトが予期せずexpireされる
3. トランザクション境界が不明確になる
4. `request.requester.full_name`へのアクセス時にMissingGreenlet（リレーションシップが未ロード）

### アンチパターン3: refresh()の誤用
```python
# ❌ role_change_service.py の create_request メソッド（修正前）
async def create_request(self, db, ...):
    request = await crud_role_change_request.create(db, ...)
    await db.commit()

    # refresh()はリレーションシップを再ロードしない
    await db.refresh(request)

    # requester は再ロードされていないため、アクセス時にMissingGreenlet
    await self._create_request_notification(db, request)
    # この中で request.requester.full_name にアクセス → エラー

    return request
```

**問題点**:
1. `refresh()`は基本属性のみを再ロード
2. リレーションシップ（`request.requester`など）は再ロードされない
3. リレーションシップへのアクセス時に遅延ロードが発生してMissingGreenlet

## 正しい実装パターン

### パターン1: 単一トランザクション + 最終的な再取得
```python
# ✅ 推奨: 1つのトランザクションで完結し、最後に再取得
async def create_request(self, db, ...):
    # 1. リクエスト作成
    request = await crud.create(db, ...)
    request_id = request.id  # commitでexpireされるため、IDを保存

    # 2. 通知作成（commitしない）
    await self._create_notification_without_commit(db, request_id)

    # 3. 1回だけcommit
    await db.commit()

    # 4. リレーションシップを含めて再取得
    result = await db.execute(
        select(Request)
        .where(Request.id == request_id)
        .options(
            selectinload(Request.requester),
            selectinload(Request.office)
        )
    )
    return result.scalar_one()

# 通知作成メソッドはcommitしない
async def _create_notification_without_commit(self, db, request_id):
    # request_idを受け取り、必要ならクエリで再取得
    result = await db.execute(
        select(Request)
        .where(Request.id == request_id)
        .options(selectinload(Request.requester))
    )
    request = result.scalar_one()

    # 通知作成
    await crud_notice.create(db, obj_in=notice_data)
    # commitしない
```

### パターン2: expire_on_commit=False + 単一commit
```python
# セッション設定で expire_on_commit=False を使用
async_session = async_sessionmaker(engine, expire_on_commit=False)

async def create_request(self, db, ...):
    # リレーションシップを事前ロードして作成
    request = await crud.create_with_relationships(db, ...)

    # 通知作成（commitしない）
    await self._create_notification_without_commit(db, request)

    # 1回だけcommit（expire_on_commit=Falseなのでオブジェクトは有効）
    await db.commit()

    return request  # commit後も安全にアクセス可能
```

## まとめ: MissingGreenletエラーを防ぐチェックリスト

- [ ] セッション設定で`expire_on_commit=False`を使用する
- [ ] リレーションシップアクセス前に`selectinload()`で事前ロード
- [ ] サービスメソッド内では1回のみ`commit()`を実行
- [ ] サブメソッド（通知作成など）は`commit()`しない
- [ ] `refresh()`ではなく`selectinload()`を使用してリレーションシップを再取得
- [ ] commit後にオブジェクトを返す場合は、selectinloadで明示的に再取得
- [ ] トランザクション境界を明確にする
- [ ] 開発時は`lazy='raise'`を使用してN+1問題を早期発見

## 参考リソース
- [SQLAlchemy Async I/O Documentation](https://docs.sqlalchemy.org/en/20/orm/extensions/asyncio.html)
- [SQLAlchemy MissingGreenlet Discussion](https://github.com/sqlalchemy/sqlalchemy/discussions/6165)
- [Best Practices for Async Session Management](https://docs.sqlalchemy.org/en/20/orm/extensions/asyncio.html#preventing-implicit-io-when-using-asyncsession)