# 例外処理
## エラーのraise
- エンドポイントではHTTPExceptionを利用して例外をraiseする
意図したHTTPレスポンスを返したい場合
- サービス層、ビジネスロジックではValueErrorをraiseする
テストの再利用性が下がる

## エラーメッセージの表記方法
- i18n 日本語化 
- k_back/app/messages/ja.py

# MissingGreenlet
## commit
- commitする場合、次のメソッドで再度commitが呼ばれていないか確認する
- サブメソッド(_create..)ではcommitしない :複数回commitする原因

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

## リレーションシップ読み込み
- リレーションシップがある時は**Eager Loading**
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

- 悪い例❌
コミット後にリフレッシュしてもリレーションシップはリフレッシュされない(主キーベースのみ)
```py
await db.commit()
await db.refresh(request)  # 基本属性のみrefresh
print(request.requester.full_name)  # MissingGreenletエラー
```

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

### パターン2: expire_on_commit=False(コミットあとも属性にアクセスできる設定) + 単一commit
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

-------------
------------
-----------
