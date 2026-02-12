# I/O操作の管理と明示的なawaitの使用

## 概要

本ドキュメントでは、けいかくんアプリケーションにおけるI/O（Input/Output）操作の管理と、なぜすべてのI/O操作に対して`await`を使用する必要があるのかを、実際の実装例を交えて説明します。

---

## 1. I/O操作とは

### 1.1 I/O操作の定義

**I/O（Input/Output）操作**とは、プログラムが外部リソースとやり取りする処理のことです。

**外部リソースの例**:
- データベース（PostgreSQL）
- ファイルシステム（S3ストレージ）
- ネットワーク（Stripe API、Google Calendar API）
- メールサーバー（SMTP）

### 1.2 I/O操作の特徴

**時間がかかる**:
- データベースクエリ: 10ms〜数秒
- ファイルアップロード: 100ms〜数秒
- 外部API呼び出し: 100ms〜数秒
- メール送信: 数秒〜数十秒

**CPUは待機状態**:
- I/O操作中、CPUは結果を待つだけ
- 同期処理では、この間他の処理ができない
- 非同期処理では、待機中に他の処理を実行できる

---

## 2. けいかくんアプリケーションにおけるI/O操作の種類

### 2.1 データベース操作（最も頻繁）

#### 例1: CRUD操作

**ファイル**: `k_back/app/api/v1/endpoints/billing.py:76`

```python
# Billing情報を取得（DBからの読み込み = I/O操作）
billing = await crud.billing.get_by_office_id(db=db, office_id=office_id)
#         ↑ awaitが必要
```

**なぜI/O操作か**:
- PostgreSQLサーバーにネットワーク経由でクエリを送信
- サーバーがクエリを実行
- 結果をネットワーク経由で受信
- この間、CPUは待機状態

**実際に発行されるSQL**:
```sql
SELECT * FROM billings WHERE office_id = 'xxx-xxx-xxx';
```

#### 例2: トランザクション操作

**ファイル**: `k_back/app/api/v1/endpoints/support_plans.py:436-437`

```python
# データベースへの書き込み（I/O操作）
await db.commit()  # ← DBにデータを永続化
await db.refresh(cycle)  # ← DBから最新データを取得
```

**commit()の内部動作**:
1. トランザクションの変更をPostgreSQLに送信
2. データベースがディスクに書き込み
3. 完了確認を受信
4. この間、CPUは待機状態

**refresh()の内部動作**:
1. 最新データを取得するSQLクエリを送信
2. データベースがクエリを実行
3. 結果を受信してPythonオブジェクトを更新

#### 例3: クエリ実行

**ファイル**: `k_back/app/api/v1/endpoints/support_plans.py:416-417`

```python
# SQLクエリの実行（I/O操作）
result = await db.execute(stmt)
#        ↑ awaitが必要
cycle = result.scalar_one_or_none()
```

**内部動作**:
1. `stmt`（SELECT文）をPostgreSQLに送信
2. データベースがクエリを実行
3. 結果セットを受信
4. Pythonオブジェクトとして構築

---

### 2.2 ファイルストレージ操作（AWS S3）

#### 例4: ファイルアップロード

**ファイル**: `k_back/app/core/storage.py:10-49`

```python
async def upload_file(file: BinaryIO, object_name: str) -> str | None:
    """
    Upload a file to an S3 bucket.
    """
    # S3クライアントを作成（同期処理）
    s3_client = boto3.client(
        "s3",
        endpoint_url=settings.S3_ENDPOINT_URL,
        aws_access_key_id=settings.S3_ACCESS_KEY,
        aws_secret_access_key=secret_key,
        region_name=settings.S3_REGION
    )

    try:
        # ファイルをS3にアップロード（I/O操作）
        # ※ boto3は同期ライブラリなので、実際にはasync/awaitを使わない
        # しかし、関数自体はasyncで定義されているため、呼び出し側でawaitが必要
        s3_client.upload_fileobj(
            file,
            settings.S3_BUCKET_NAME,
            object_name,
            ExtraArgs={
                'ContentType': 'application/pdf',
                'ContentDisposition': 'inline'
            }
        )
        # ... 略
    except ClientError as e:
        logger.error(f"Failed to upload {object_name} to S3: {e}")
        return None
```

**呼び出し例**（実際の使用箇所）:

```python
# PDFファイルをS3にアップロード
s3_url = await upload_file(file=pdf_file, object_name=unique_filename)
#        ↑ awaitが必要
```

**なぜI/O操作か**:
- ファイルデータをネットワーク経由でS3サーバーに送信
- S3がファイルをストレージに保存
- 完了確認を受信
- ファイルサイズによっては数秒〜数十秒かかる

#### 例5: 署名付きURL生成

**ファイル**: `k_back/app/core/storage.py:51-98`

```python
async def create_presigned_url(object_name: str, expiration: int = 3600, inline: bool = True) -> str | None:
    """
    Generate a presigned URL to share an S3 object.
    """
    # ... S3クライアント作成 ...

    try:
        # 署名付きURLを生成（I/O操作ではないが、関数がasyncなので呼び出し側でawait必要）
        response = s3_client.generate_presigned_url(
            'get_object',
            Params=params,
            ExpiresIn=expiration
        )
        return response
    except ClientError as e:
        logger.error(f"Failed to generate presigned URL for {object_name}: {e}")
        return None
```

**呼び出し例**:

```python
# S3オブジェクトの署名付きURLを生成
presigned_url = await create_presigned_url(object_name=s3_key, expiration=3600)
#               ↑ awaitが必要
```

---

### 2.3 外部API呼び出し

#### 例6: Stripe API（決済処理）

**ファイル**: `k_back/app/services/billing_service.py:76-84`

```python
# Stripe APIでCustomerを作成（外部API呼び出し = I/O操作）
stripe.api_key = stripe_secret_key

# ※ stripeライブラリは同期処理だが、Service関数全体はasyncで定義
customer = stripe.Customer.create(
    email=user_email,
    name=office_name,
    metadata={
        "office_id": str(office_id),
        "staff_id": str(user_id)
    }
)
customer_id = customer.id
```

**なぜI/O操作か**:
- Stripe APIサーバーにHTTPSリクエストを送信
- Stripeが顧客情報を作成
- レスポンスを受信
- 通常100ms〜数秒かかる

**呼び出し側**:

```python
# サービス層の関数を呼び出し
result = await billing_service.create_checkout_session_with_customer(
    #    ↑ awaitが必要（関数内でI/O操作を行うため）
    db=db,
    billing_id=billing_id,
    office_id=office_id,
    # ... その他のパラメータ
)
```

#### 例7: Google Calendar API

**ファイル**: `k_back/app/services/calendar_service.py:96-99`

```python
# CRUDレイヤーで暗号化して保存（DB I/O操作）
account = await crud_office_calendar_account.create_with_encryption(
    #     ↑ awaitが必要
    db=db,
    obj_in=create_data
)
```

---

### 2.4 メール送信

#### 例8: メールアドレス確認メール

**ファイル**: `k_back/app/core/mail.py:52-69`

```python
async def send_verification_email(recipient_email: str, token: str) -> None:
    """
    メールアドレス確認用のメールを送信します。
    """
    subject = "【ケイカくん】メールアドレスの確認をお願いします"
    verification_url = f"{settings.FRONTEND_URL}/auth/verify-email?token={token}"

    context = {
        "title": subject,
        "verification_url": verification_url,
    }

    # メール送信（I/O操作）
    await send_email(
        #  ↑ awaitが必要
        recipient_email=recipient_email,
        subject=subject,
        template_name="verify_email.html",
        context=context,
    )
```

**send_email関数の実装** (`k_back/app/core/mail.py:25-48`):

```python
async def send_email(
    recipient_email: str,
    subject: str,
    template_name: str,
    context: Dict[str, Any],
) -> None:
    """
    メールを非同期で送信します。
    """
    message = MessageSchema(
        subject=subject,
        recipients=[recipient_email],
        template_body=context,
        subtype=MessageType.html,
    )

    fm = FastMail(conf)
    # FastMailの非同期メソッドを呼び出し（I/O操作）
    await fm.send_message(message, template_name=template_name)
    #  ↑ awaitが必要
```

**なぜI/O操作か**:
- SMTPサーバー（AWS SES）に接続
- メールデータを送信
- 送信完了確認を受信
- 通常数秒〜数十秒かかる

---

## 3. なぜawaitが必要なのか

### 3.1 同期処理の問題点

**同期処理の動作**:

```python
# 同期処理（Pythonの通常の関数）
def synchronous_operation():
    # データベースクエリ（1秒かかる）
    result = db.query("SELECT * FROM users")  # ← ここで1秒待機

    # この間、プログラムは完全に停止
    # 他のリクエストは処理できない

    return result
```

**問題**:
- I/O操作中、CPUは何もしていないのに待機
- 他のリクエストを処理できない
- 同時に100リクエストが来たら、1秒 × 100 = 100秒かかる

### 3.2 非同期処理の利点

**非同期処理の動作**:

```python
# 非同期処理（asyncとawaitを使用）
async def asynchronous_operation():
    # データベースクエリ（1秒かかる）
    result = await db.execute("SELECT * FROM users")  # ← awaitで待機

    # await中、イベントループが他のリクエストを処理できる
    # 100リクエストが同時に来ても、並行処理で約1秒で完了

    return result
```

**利点**:
- I/O待機中に他の処理を実行
- 同時に多数のリクエストを処理可能
- サーバーリソースを効率的に活用

### 3.3 awaitの役割

**awaitキーワードの意味**:
1. **「この処理は時間がかかるので、待機中に他の処理をしていいよ」**という指示
2. イベントループに制御を返す
3. I/O操作が完了したら、処理を再開

**具体例**（けいかくんアプリ）:

```python
# ファイル: k_back/app/api/v1/endpoints/billing.py:134-142

# ① Billing情報を取得（I/O操作1）
billing = await crud.billing.get_by_office_id(db=db, office_id=office_id)
#         ↑ awaitでI/O待機中に他のリクエストを処理

# ② Office情報を取得（I/O操作2）
office = await crud.office.get(db=db, id=office_id)
#        ↑ awaitでI/O待機中に他のリクエストを処理
```

**内部動作の流れ**:

```
1. await crud.billing.get_by_office_id() を実行
   ↓
2. PostgreSQLにクエリを送信
   ↓
3. await で制御をイベントループに返す
   ↓
4. イベントループが他のリクエストを処理（例: リクエストB、リクエストC）
   ↓
5. PostgreSQLからレスポンスが返ってくる
   ↓
6. イベントループが処理を再開
   ↓
7. billingに結果を代入
   ↓
8. 次の行（await crud.office.get()）を実行
```

---

## 4. awaitを忘れた場合の問題

### 4.1 コルーチンが返される

**間違った例**:

```python
# ❌ Wrong: awaitを忘れた
async def get_billing_status(db: AsyncSession, office_id: UUID):
    # awaitを忘れる
    billing = crud.billing.get_by_office_id(db=db, office_id=office_id)
    #         ↑ awaitがない！

    # billingには何が入る？
    print(type(billing))  # <class 'coroutine'>

    # ❌ エラー: 'coroutine' object has no attribute 'billing_status'
    return billing.billing_status
```

**問題**:
- `billing`には実際のBillingオブジェクトではなく、**コルーチンオブジェクト**が入る
- コルーチンオブジェクトは「実行されていない非同期関数」を表す
- `billing.billing_status`にアクセスしようとするとAttributeErrorが発生

### 4.2 実際のエラー例

```python
# ❌ Wrong
billing = crud.billing.get_by_office_id(db=db, office_id=office_id)
status = billing.billing_status  # AttributeError

# エラーメッセージ:
# AttributeError: 'coroutine' object has no attribute 'billing_status'
```

**修正**:

```python
# ✅ Correct
billing = await crud.billing.get_by_office_id(db=db, office_id=office_id)
#         ↑ awaitを追加
status = billing.billing_status  # OK!
```

---

## 5. けいかくんアプリケーションでの実装パターン

### 5.1 API層（エンドポイント）

**ファイル**: `k_back/app/api/v1/endpoints/billing.py:49-95`

```python
@router.get("/status", response_model=BillingStatusResponse)
async def get_billing_status(
    #   ↑ async: この関数は非同期処理を行う
    db: Annotated[AsyncSession, Depends(deps.get_db)],
    current_user: Annotated[Staff, Depends(deps.get_current_user)]
) -> BillingStatusResponse:
    """課金ステータス取得API"""

    # プライマリの事務所を取得（メモリ内処理 = I/Oではない）
    primary_association = next(
        (assoc for assoc in current_user.office_associations if assoc.is_primary),
        current_user.office_associations[0]
    )
    office_id = primary_association.office_id

    # ① Billing情報を取得（I/O操作）
    billing = await crud.billing.get_by_office_id(db=db, office_id=office_id)
    #         ↑ awaitが必要

    # ② Billing情報が存在しない場合、作成（I/O操作）
    if not billing:
        billing = await crud.billing.create_for_office(
            #     ↑ awaitが必要
            db=db,
            office_id=office_id,
            trial_days=180
        )

    # ③ レスポンスを返す（I/Oではない）
    return BillingStatusResponse(
        billing_status=billing.billing_status,
        trial_end_date=billing.trial_end_date,
        # ... その他のフィールド
    )
```

**ポイント**:
- 関数定義に`async`キーワード
- すべてのI/O操作（CRUD呼び出し）に`await`キーワード
- メモリ内処理（リスト操作、オブジェクト生成）には`await`不要

### 5.2 Service層（ビジネスロジック）

**ファイル**: `k_back/app/services/billing_service.py:37-146`

```python
class BillingService:
    """課金サービス層"""

    async def create_checkout_session_with_customer(
        #   ↑ async: この関数は非同期処理を行う
        self,
        db: AsyncSession,
        *,
        billing_id: UUID,
        office_id: UUID,
        # ... その他のパラメータ
    ) -> Dict[str, str]:
        """Stripe Checkout Sessionを作成"""

        try:
            # ① Stripe APIでCustomerを作成（外部API = I/O操作）
            stripe.api_key = stripe_secret_key
            customer = stripe.Customer.create(
                email=user_email,
                name=office_name,
                metadata={"office_id": str(office_id), "staff_id": str(user_id)}
            )
            # ※ stripeライブラリは同期処理なのでawaitなし
            # しかし、関数全体はasyncなので、呼び出し側でawaitが必要

            # ② DB更新（I/O操作）
            await crud.billing.update_stripe_customer(
                #  ↑ awaitが必要
                db=db,
                billing_id=billing_id,
                stripe_customer_id=customer.id,
                auto_commit=False
            )

            # ③ Checkout Sessionを作成（外部API = I/O操作）
            checkout_session = stripe.checkout.Session.create(
                mode='subscription',
                customer=customer.id,
                # ... その他のパラメータ
            )

            # ④ トランザクションをコミット（I/O操作）
            await db.commit()
            #  ↑ awaitが必要

            return {
                "session_id": checkout_session.id,
                "url": checkout_session.url
            }

        except stripe.error.StripeError as e:
            # エラー時はロールバック（I/O操作）
            await db.rollback()
            #  ↑ awaitが必要
            raise HTTPException(...)
```

**ポイント**:
- 複数のI/O操作を組み合わせる
- 各I/O操作に`await`を使用
- エラーハンドリングでも`await db.rollback()`を使用

### 5.3 CRUD層（データベース操作）

**ファイル**: `k_back/app/crud/crud_billing.py:21-32`

```python
class CRUDBilling(CRUDBase[Billing, BillingCreate, BillingUpdate]):
    """Billing CRUD操作クラス"""

    async def get_by_office_id(
        #   ↑ async: この関数は非同期処理を行う
        self,
        db: AsyncSession,
        office_id: UUID
    ) -> Optional[Billing]:
        """事業所IDでBilling情報を取得"""

        # SQLクエリを実行（I/O操作）
        result = await db.execute(
            #      ↑ awaitが必要
            select(self.model)
            .where(self.model.office_id == office_id)
            .options(selectinload(self.model.office))
        )

        # 結果を取得（メモリ内処理 = I/Oではない）
        return result.scalars().first()
```

**ポイント**:
- `db.execute()`はI/O操作なので`await`が必要
- `result.scalars().first()`はメモリ内処理なので`await`不要

---

## 6. 複数のI/O操作の組み合わせパターン

### 6.1 順次実行（Sequential Execution）

**各I/O操作を順番に実行する**:

```python
async def sequential_operations(db: AsyncSession, office_id: UUID):
    # ① Billing取得（I/O操作1）
    billing = await crud.billing.get_by_office_id(db=db, office_id=office_id)
    #         ↑ 完了を待つ

    # ② Office取得（I/O操作2）
    office = await crud.office.get(db=db, id=office_id)
    #        ↑ 完了を待つ

    # ③ Staff取得（I/O操作3）
    staff = await crud.staff.get(db=db, id=billing.created_by)
    #       ↑ 完了を待つ

    return billing, office, staff

# 実行時間: I/O1 + I/O2 + I/O3（例: 30ms + 30ms + 30ms = 90ms）
```

**特徴**:
- 依存関係がある場合に使用（③は①の結果が必要）
- 各操作が完了してから次の操作を開始

### 6.2 並行実行（Concurrent Execution）

**複数のI/O操作を同時に実行する**:

```python
import asyncio

async def concurrent_operations(db: AsyncSession, office_id: UUID, staff_id: UUID):
    # 3つのI/O操作を同時に開始
    billing_task = crud.billing.get_by_office_id(db=db, office_id=office_id)
    office_task = crud.office.get(db=db, id=office_id)
    staff_task = crud.staff.get(db=db, id=staff_id)

    # すべての操作の完了を待つ
    billing, office, staff = await asyncio.gather(
        #                        ↑ awaitで全ての完了を待つ
        billing_task,
        office_task,
        staff_task
    )

    return billing, office, staff

# 実行時間: max(I/O1, I/O2, I/O3)（例: max(30ms, 30ms, 30ms) = 30ms）
```

**特徴**:
- 依存関係がない場合に使用
- 並行実行により大幅な高速化
- 実行時間が最も遅いI/O操作と同じになる

### 6.3 エラーハンドリング付きトランザクション

**ファイル**: `k_back/app/services/employee_action_service.py:123-140`

```python
async def approve_request(self, db: AsyncSession, request_id: int):
    """承認リクエストを処理"""

    try:
        # ① リクエストを取得（I/O操作）
        result = await db.execute(
            select(EmployeeActionRequest)
            .where(EmployeeActionRequest.id == request_id)
        )
        request = result.scalar_one_or_none()

        if not request:
            raise HTTPException(...)

        # ② 承認処理（ビジネスロジック）
        request.status = "approved"

        # ③ 通知を作成（I/O操作）
        await crud_notice.create(db, obj_in=notice_data)

        # ④ コミット（I/O操作）
        await db.commit()

        # ⑤ リフレッシュ（I/O操作）
        result = await db.execute(
            select(EmployeeActionRequest)
            .where(EmployeeActionRequest.id == request_id)
        )
        return result.scalar_one()

    except Exception as e:
        # エラー時はロールバック（I/O操作）
        await db.rollback()
        #  ↑ awaitが必要
        logger.error(f"Error: {e}")
        raise
```

**ポイント**:
- すべてのI/O操作に`await`
- エラー時の`rollback()`も`await`が必要
- トランザクションの一貫性を保証

---

## 7. 非同期処理のベストプラクティス

### 7.1 すべてのI/O操作にawaitを使用

**チェックリスト**:

- [ ] データベースクエリ: `await db.execute()`
- [ ] トランザクション操作: `await db.commit()`, `await db.rollback()`
- [ ] リフレッシュ: `await db.refresh(obj)`
- [ ] CRUD操作: `await crud.model.get()`, `await crud.model.create()`
- [ ] ファイル操作: `await upload_file()`, `await create_presigned_url()`
- [ ] メール送信: `await send_email()`
- [ ] 外部API呼び出しを含む関数: `await service.method()`

### 7.2 async関数の定義

**ルール**: I/O操作を含む関数は必ず`async`で定義する

```python
# ✅ Correct: I/O操作を含むので async
async def get_user_data(db: AsyncSession, user_id: UUID):
    user = await crud.user.get(db=db, id=user_id)
    return user

# ❌ Wrong: I/O操作を含むのに async がない
def get_user_data(db: AsyncSession, user_id: UUID):
    user = await crud.user.get(db=db, id=user_id)  # SyntaxError!
    return user
```

### 7.3 同期処理と非同期処理の混在

**原則**: 非同期関数内で同期ライブラリを使う場合の注意

```python
async def upload_and_save(db: AsyncSession, file: BinaryIO):
    # ① boto3は同期ライブラリ（awaitなし）
    s3_client = boto3.client("s3", ...)
    s3_client.upload_fileobj(file, bucket, key)
    # ↑ awaitなし（boto3が同期処理のため）

    # ② データベース保存は非同期（awaitあり）
    record = await crud.file.create(db=db, obj_in=file_data)
    #        ↑ awaitが必要

    return record
```

**注意点**:
- boto3、stripe などの同期ライブラリは`await`なしで使用
- しかし、関数全体を`async`で定義することで、呼び出し側で`await`可能
- I/O操作を含む関数は`async`で定義するのがベストプラクティス

---

## 8. パフォーマンスへの影響

### 8.1 同期処理 vs 非同期処理

**同期処理の場合**:

```python
# 同期処理（100リクエスト）
# 各リクエストに1秒かかる場合

def sync_handler():
    result = db.query("SELECT ...")  # 1秒
    return result

# 総実行時間: 1秒 × 100 = 100秒
```

**非同期処理の場合**:

```python
# 非同期処理（100リクエスト）
# 各リクエストに1秒かかる場合

async def async_handler():
    result = await db.execute("SELECT ...")  # 1秒
    return result

# 総実行時間: 約1〜2秒（並行実行）
# 約50倍の高速化！
```

### 8.2 けいかくんアプリでの実測例

**エンドポイント**: `/api/v1/billing/status`

**処理内容**:
1. Billing取得（DB I/O: 約30ms）
2. Office取得（DB I/O: 約30ms）

**同期処理の場合**:
- 実行時間: 30ms + 30ms = 60ms
- 同時100リクエスト: 60ms × 100 = 6000ms（6秒）

**非同期処理の場合（現在の実装）**:
- 実行時間: 約60ms（順次実行）
- 同時100リクエスト: 約100〜200ms（並行実行）
- **約30倍の高速化**

---

## 9. まとめ

### I/O操作とは

1. **外部リソースとのやり取り**:
   - データベース（PostgreSQL）
   - ファイルストレージ（S3）
   - 外部API（Stripe, Google Calendar）
   - メールサーバー（SMTP）

2. **特徴**:
   - 時間がかかる（数ミリ秒〜数秒）
   - CPU待機状態が発生
   - ネットワークやディスクアクセスを伴う

### なぜawaitが必要か

1. **非同期処理の仕組み**:
   - `await`でI/O待機中に他の処理を実行
   - イベントループが複数のリクエストを並行処理
   - サーバーリソースを効率的に活用

2. **awaitを忘れると**:
   - コルーチンオブジェクトが返される
   - 実際のデータが取得できない
   - AttributeErrorが発生

### けいかくんアプリでの実装パターン

1. **API層**: すべてのCRUD呼び出しに`await`
2. **Service層**: 複数のI/O操作を組み合わせ、各操作に`await`
3. **CRUD層**: `db.execute()`, `db.commit()`, `db.refresh()`に`await`

### パフォーマンス効果

- **同期処理**: 100リクエストで100秒
- **非同期処理**: 100リクエストで1〜2秒
- **約50倍の高速化**

### ベストプラクティス

- [ ] I/O操作を含む関数は必ず`async`で定義
- [ ] すべてのI/O操作に`await`を使用
- [ ] エラーハンドリングでも`await db.rollback()`
- [ ] 依存関係がない場合は`asyncio.gather()`で並行実行
- [ ] 同期ライブラリは`await`なしで使用可能（関数自体は`async`で定義）

---

**最終更新日**: 2026-01-26
**文書管理者**: 開発チーム
