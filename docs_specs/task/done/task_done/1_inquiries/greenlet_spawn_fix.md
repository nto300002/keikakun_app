# 問い合わせ機能 - greenlet_spawn エラー修正報告

## 修正完了日
2025-12-04

## エラー概要

### 発生したエラー
```
greenlet_spawn has not been called; can't call await_only() here.
Was IO attempted in an unexpected place?
```

### エラーの詳細ログ
```
2025-12-04 05:39:45,526 - app.api.v1.endpoints.inquiries - ERROR -
管理者への通知メール送信に失敗: greenlet_spawn has not been called;
can't call await_only() here. Was IO attempted in an unexpected place?
(Background on this error at: https://sqlalche.me/e/20/xd2s)
```

---

## 根本原因分析

### 問題のコード（修正前）

**ファイル**: `app/api/v1/endpoints/inquiries.py:181-220`

```python
# 問い合わせ作成
inquiry_detail = await crud_inquiry.create_inquiry(...)

# ① ここでコミット
await db.commit()

# ② コミット後にメール送信
try:
    for admin_id in admin_recipient_ids:
        admin_stmt = select(Staff).where(Staff.id == admin_id)
        admin_result = await db.execute(admin_stmt)
        admin_staff = admin_result.scalar_one_or_none()

        if admin_staff and admin_staff.email:
            await send_inquiry_received_email(
                # ... 略 ...
                # ③ セッションから切り離されたオブジェクトの属性にアクセス
                created_at=inquiry_detail.created_at.astimezone(timezone.utc).isoformat(),
                inquiry_id=str(inquiry_detail.id)
            )
except Exception as email_error:
    logger.error(f"管理者への通知メール送信に失敗: {str(email_error)}")
```

### なぜエラーが発生したか

#### SQLAlchemy のセッション管理

1. **`await db.commit()` でセッションがコミット**
   - トランザクションが完了
   - セッション内のオブジェクトがデタッチ（detached）状態になる

2. **デタッチ状態のオブジェクトにアクセス**
   - `inquiry_detail.created_at` にアクセス試行
   - `created_at` はリレーションシップではないが、内部的に lazy loading が発生
   - セッションから切り離されているため、greenlet_spawn エラー

#### SQLAlchemy AsyncIO の制約

- **非同期セッション**: greenlet を使用して async/await を実装
- **デタッチ状態**: セッションから切り離されたオブジェクトは遅延ロード不可
- **greenlet_spawn エラー**: セッション外でのデータベースアクセス試行時に発生

---

## 修正内容

### 修正後のコード

**ファイル**: `app/api/v1/endpoints/inquiries.py:181-232`

```python
# 問い合わせ作成
inquiry_detail = await crud_inquiry.create_inquiry(...)

# ① コミット前に必要な値を取得（重要！）
from datetime import timezone
inquiry_id = inquiry_detail.id
inquiry_created_at = inquiry_detail.created_at.astimezone(timezone.utc).isoformat()

# ② 問い合わせをコミット
await db.commit()

# ③ コミット後にメール送信（変数を使用）
try:
    from app.core.mail import send_inquiry_received_email

    for admin_id in admin_recipient_ids:
        admin_stmt = select(Staff).where(Staff.id == admin_id)
        admin_result = await db.execute(admin_stmt)
        admin_staff = admin_result.scalar_one_or_none()

        if admin_staff and admin_staff.email:
            await send_inquiry_received_email(
                admin_email=admin_staff.email,
                sender_name=sanitized.get("sender_name") or "未設定",
                sender_email=sanitized.get("sender_email") or "未設定",
                category=inquiry_in.category or "その他",
                inquiry_title=sanitized["title"],
                inquiry_content=sanitized["content"],
                # ④ 事前に取得した変数を使用
                created_at=inquiry_created_at,
                inquiry_id=str(inquiry_id)
            )
except Exception as email_error:
    logger.error(f"管理者への通知メール送信に失敗: {str(email_error)}")

# ... 一時事務所削除ロジック ...

# ⑤ レスポンス返却時も変数を使用
return InquiryCreateResponse(
    id=inquiry_id,
    message="問い合わせを受け付けました"
)
```

### 変更点サマリー

| 項目 | 修正前 | 修正後 |
|------|--------|--------|
| **値の取得タイミング** | コミット後 | コミット前 |
| **created_at アクセス** | `inquiry_detail.created_at` | `inquiry_created_at` 変数 |
| **id アクセス** | `inquiry_detail.id` | `inquiry_id` 変数 |
| **セッション状態** | デタッチ（エラー） | アタッチ（正常） |

---

## トランザクション処理の見直し

### 修正後のトランザクションフロー

```
1. 入力サニタイズ
   ↓
2. office_id 決定（一時事務所作成の可能性あり）
   ↓
3. 問い合わせ作成（CRUD）
   - Message 作成
   - InquiryDetail 作成
   - MessageRecipient 作成
   - リレーションシップロード
   ↓
4. コミット前に値を取得 ← NEW!
   - inquiry_id = inquiry_detail.id
   - inquiry_created_at = inquiry_detail.created_at.astimezone(timezone.utc).isoformat()
   ↓
5. 問い合わせコミット
   ↓
6. メール送信（ベストエフォート）
   - 取得済みの変数を使用
   - エラー時もログのみ
   ↓
7. 一時事務所削除（該当する場合）
   - 別コミット
   ↓
8. レスポンス返却
   - 取得済みの変数を使用
```

### コミット戦略

#### 問い合わせ作成（メインコミット）
```python
inquiry_detail = await crud_inquiry.create_inquiry(...)
# 必要な値を事前取得
inquiry_id = inquiry_detail.id
inquiry_created_at = inquiry_detail.created_at.astimezone(timezone.utc).isoformat()
# コミット
await db.commit()
```

**目的**: 問い合わせデータを確実に永続化

#### 一時事務所削除（別コミット）
```python
if temp_office_created and temp_office_id:
    try:
        await delete_temporary_system_office(db, temp_office_id)
        await db.commit()  # 別トランザクション
    except Exception as delete_error:
        logger.error(f"削除失敗: {str(delete_error)}")
```

**目的**: 削除失敗しても問い合わせデータは保護

---

## リレーションシップの読み込み確認

### CRUD 層のリレーションシップロード

**ファイル**: `app/crud/crud_inquiry.py:116-119`

```python
# 4. リレーションシップをロード
await db.refresh(inquiry_detail, ["message"])
await db.refresh(message, ["recipients"])

return inquiry_detail
```

#### ロード戦略

| リレーション | ロード方法 | タイミング |
|--------------|------------|------------|
| `inquiry_detail.message` | `refresh()` | flush 後 |
| `message.recipients` | `refresh()` | flush 後 |
| `inquiry_detail.created_at` | 自動ロード | オブジェクト作成時 |

### モデル定義の確認

**ファイル**: `app/models/inquiry.py:90-95`

```python
created_at: Mapped[datetime.datetime] = mapped_column(
    DateTime(timezone=True),
    server_default=func.now(),  # ← サーバー側でデフォルト値設定
    nullable=False,
    index=True
)
```

**ファイル**: `app/models/inquiry.py:110-114`

```python
# Relationships
message: Mapped["Message"] = relationship(
    "Message",
    foreign_keys=[message_id],
    lazy="selectin"  # ← Eager loading
)
```

#### リレーションシップロード戦略

- **`lazy="selectin"`**: Eager loading（最初のクエリで一緒にロード）
- **`await db.refresh()`**: 明示的な再ロード
- **`created_at`**: 通常の列なので lazy loading 不要（のはずだが...）

---

## エラーの詳細解析

### なぜ `created_at` でもエラーが出たのか？

#### 仮説1: タイムゾーン変換での遅延評価
```python
inquiry_detail.created_at.astimezone(timezone.utc)
```

- `created_at` は `DateTime(timezone=True)` として定義
- PostgreSQL の TIMESTAMP WITH TIME ZONE 型
- セッションから切り離されると、タイムゾーン情報の取得時に問題が発生した可能性

#### 仮説2: server_default による遅延評価
```python
server_default=func.now()
```

- サーバー側でデフォルト値を設定
- flush 後に値を取得する際、内部的に lazy loading が発生
- セッション外でのアクセス時に greenlet_spawn エラー

#### 実際の原因（推測）
- **コミット後のセッション切り離し**
- **タイムゾーン変換時の属性アクセス**
- **SQLAlchemy の内部的な遅延評価メカニズム**

---

## テスト結果

### 修正後のテスト

```bash
$ docker exec keikakun_app-backend-1 pytest \
  tests/utils/test_sanitization.py \
  tests/security/test_rate_limiting.py \
  tests/schemas/test_inquiry.py \
  tests/api/v1/test_inquiries_integration.py \
  tests/utils/test_temp_office.py \
  -v --tb=no

================= 119 passed, 6 warnings in 102.13s ==================
```

### テストカバレッジ

- ✅ サニタイズ: 35テスト
- ✅ レート制限: 15テスト
- ✅ スキーマ: 48テスト
- ✅ 統合テスト: 12テスト
- ✅ 一時事務所: 9テスト

**全119テストがパス**

---

## ベストプラクティス

### 1. コミット前に値を取得

**悪い例**:
```python
await db.commit()
# ❌ セッションから切り離された後にアクセス
response_id = inquiry_detail.id
```

**良い例**:
```python
# ✅ コミット前に取得
response_id = inquiry_detail.id
await db.commit()
```

### 2. タイムゾーン変換はコミット前

**悪い例**:
```python
await db.commit()
# ❌ タイムゾーン変換でエラー
created_at = inquiry_detail.created_at.astimezone(timezone.utc)
```

**良い例**:
```python
# ✅ コミット前に変換
created_at = inquiry_detail.created_at.astimezone(timezone.utc).isoformat()
await db.commit()
```

### 3. リレーションシップの事前ロード

```python
# CRUD 層で明示的にロード
await db.refresh(inquiry_detail, ["message"])
await db.refresh(message, ["recipients"])

# または lazy="selectin" を使用
message: Mapped["Message"] = relationship(
    "Message",
    foreign_keys=[message_id],
    lazy="selectin"
)
```

### 4. トランザクション分離

```python
# メイントランザクション
await db.commit()

# ベストエフォート処理（別トランザクション）
try:
    await send_email(...)  # 失敗してもメイントランザクションに影響なし
except Exception as e:
    logger.error(f"メール送信失敗: {e}")
```

---

## 学んだ教訓

### SQLAlchemy AsyncIO の制約

1. **セッション外でのアクセス禁止**
   - コミット後はデタッチ状態
   - 属性アクセスで greenlet_spawn エラー

2. **必要な値は事前取得**
   - コミット前に全ての必要な値を変数に保存
   - タイムゾーン変換も事前に実施

3. **リレーションシップの明示的ロード**
   - `lazy="selectin"` または `await db.refresh()`
   - N+1 問題の回避

### トランザクション設計

1. **メインデータは最優先**
   - 問い合わせデータは必ずコミット
   - 付属処理（メール、クリーンアップ）は失敗しても許容

2. **トランザクション分離**
   - 独立した処理は別トランザクション
   - エラーの波及を防ぐ

---

## 修正ファイル一覧

### 変更
- ✅ `app/api/v1/endpoints/inquiries.py` - トランザクション処理修正
  - Line 198-201: コミット前の値取得追加
  - Line 225-226: 変数使用に変更
  - Line 250: レスポンス返却時の変数使用

### ドキュメント
- ✅ `md_files_design_note/1Lerror.md` - エラーログに解決済みマーク追加
- ✅ `md_files_design_note/task/1_inquiries/greenlet_spawn_fix.md` - 修正報告（本ファイル）

---

## まとめ

✅ **修正完了項目**
1. greenlet_spawn エラーの原因特定
2. コミット前の値取得への変更
3. トランザクション処理の見直し
4. 全119テストがパス

✅ **根本原因**
- コミット後のセッション切り離し状態でのオブジェクト属性アクセス
- タイムゾーン変換時の遅延評価

✅ **解決策**
- コミット前に必要な値を変数に保存
- タイムゾーン変換もコミット前に実施

✅ **品質保証**
- 全テストがパス
- トランザクション分離によるエラーハンドリング改善

🎉 **未ログインユーザーからの問い合わせが正常に動作するようになりました！**

---

## 参考リンク

- [SQLAlchemy Error: MissingGreenlet](https://sqlalche.me/e/20/xd2s)
- [SQLAlchemy Asynchronous I/O (asyncio)](https://docs.sqlalchemy.org/en/20/orm/extensions/asyncio.html)
- [Session State Management](https://docs.sqlalchemy.org/en/20/orm/session_state_management.html)

---

# 問い合わせ返信機能 - greenlet_spawn エラー修正 (2025-12-08)

## エラー概要

### 発生したエラー
```
返信の送信に失敗しました: greenlet_spawn has not been called; can't call await_only() here.
Was IO attempted in an unexpected place?
```

### エラー発生箇所
- **ファイル**: `app/crud/crud_inquiry.py`
- **メソッド**: `create_reply` (Line 341-438)
- **エンドポイント**: `POST /api/v1/admin/inquiries/{id}/reply`

---

## 根本原因分析

### 問題のコード（修正前）

```python
async def create_reply(self, db: AsyncSession, ...):
    inquiry = await self.get_inquiry_by_id(db=db, inquiry_id=inquiry_id)
    if not inquiry:
        raise ValueError("問い合わせが見つかりません")

    # ❌ データベース操作の後にリレーションシップにアクセス
    reply_message = Message(
        sender_staff_id=reply_staff_id,
        office_id=inquiry.message.office_id,  # 遅延ロードをトリガー
        message_type=MessageType.inquiry_reply,
        priority=MessagePriority.normal,
        title=f"Re: {inquiry.message.title}",  # 遅延ロードをトリガー
        content=reply_content,
        is_test_data=inquiry.is_test_data
    )
    db.add(reply_message)
    await db.flush()  # この後のリレーションアクセスでさらにエラー
```

### なぜエラーが発生したか

1. **リレーションシップへの遅延アクセス**
   - `inquiry.message.office_id` のようなリレーションシップアクセスが遅延ロードをトリガー
   - flush 操作の前後でリレーションシップにアクセスすると greenlet エラー

2. **SQLAlchemy 非同期の制約**
   - 非同期セッションでは遅延ロード（lazy loading）が禁止
   - リレーションシップデータは事前にロードする必要がある

---

## 修正内容

### 修正後のコード

**ファイル**: `app/crud/crud_inquiry.py:341-438`

```python
async def create_reply(
    self,
    db: AsyncSession,
    *,
    inquiry_id: UUID,
    reply_staff_id: UUID,
    reply_content: str,
    send_email: bool = False
) -> Message:
    # 1. リレーションシップを事前ロード（get_inquiry_by_id は selectinload を使用）
    inquiry = await self.get_inquiry_by_id(db=db, inquiry_id=inquiry_id)
    if not inquiry:
        raise ValueError("問い合わせが見つかりません")

    # 2. ✅ データベース操作の前に、すべてのリレーションシップにアクセス
    # これによりデータがメモリに読み込まれる
    original_message = inquiry.message
    if not original_message:
        raise ValueError("問い合わせに紐づくメッセージが見つかりません")

    # 3. ✅ 必要な値をローカル変数に保存
    # 以降のDB操作でリレーションシップに直接アクセスしない
    office_id = original_message.office_id
    original_title = original_message.title
    sender_staff_id = original_message.sender_staff_id
    sender_email = inquiry.sender_email
    is_test_data = inquiry.is_test_data

    # 4. ✅ ローカル変数を使用してMessageを作成
    reply_message = Message(
        sender_staff_id=reply_staff_id,
        office_id=office_id,  # リレーションシップではなくローカル変数
        message_type=MessageType.inquiry_reply,
        priority=MessagePriority.normal,
        title=f"Re: {original_title}",  # リレーションシップではなくローカル変数
        content=reply_content,
        is_test_data=is_test_data
    )
    db.add(reply_message)
    await db.flush()

    # 5. ログイン済み送信者への内部通知作成（ローカル変数を使用）
    if sender_staff_id:
        recipient = MessageRecipient(
            message_id=reply_message.id,
            recipient_staff_id=sender_staff_id,
            is_read=False,
            is_archived=False,
            is_test_data=is_test_data
        )
        db.add(recipient)
        await db.flush()

    # 6. ステータス更新
    inquiry.status = InquiryStatus.answered
    inquiry.updated_at = datetime.now(timezone.utc)
    db.add(inquiry)
    await db.flush()

    # 7. メール送信ログ記録（ローカル変数を使用）
    if send_email and sender_email:
        log_entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "action": "reply_email_queued",
            "recipient": sender_email,
            "message_id": str(reply_message.id),
            "staff_id": str(reply_staff_id)
        }
        await self.append_delivery_log(
            db=db,
            inquiry_detail_id=inquiry_id,
            log_entry=log_entry
        )

    await db.refresh(reply_message)
    return reply_message
```

### 修正のポイント

1. **リレーションシップへのアクセスを最初にまとめる**
   - データベース操作（`flush`）の前にすべてのリレーションシップデータにアクセス
   - これにより必要なデータがすべてメモリに読み込まれる

2. **ローカル変数に保存**
   - リレーションシップの値を個別の変数に保存
   - 以降の処理ではリレーションシップに直接アクセスしない

3. **遅延ロードの完全回避**
   - `get_inquiry_by_id()` が `selectinload` で事前ロード済み
   - 変数に保存することで遅延ロードのトリガーを防ぐ

---

## SQLAlchemy 非同期ベストプラクティス

### ✅ 良い例: 事前ロードとローカル変数

```python
# 1. Eager loading で取得
inquiry = await session.get(
    InquiryDetail,
    id,
    options=[selectinload(InquiryDetail.message)]
)

# 2. データベース操作の前にリレーションシップにアクセス
message = inquiry.message
office_id = message.office_id
title = message.title

# 3. データベース操作（ローカル変数を使用）
await session.flush()

# 4. flush後もローカル変数を安全に使用可能
new_message = Message(office_id=office_id, title=f"Re: {title}")
```

### ❌ 悪い例: flush後のリレーションアクセス

```python
# 1. Eager loading で取得
inquiry = await session.get(
    InquiryDetail,
    id,
    options=[selectinload(InquiryDetail.message)]
)

# 2. データベース操作
await session.flush()

# 3. ❌ flush後にリレーションシップにアクセス
office_id = inquiry.message.office_id  # greenlet_spawn エラー！
title = inquiry.message.title  # greenlet_spawn エラー！
```

---

## テスト確認

### テスト実行コマンド

```bash
docker-compose exec backend pytest tests/api/v1/test_inquiry_endpoints.py::TestAdminInquiryReplyEndpoint -v
```

### 期待されるテスト結果

- ✅ `test_reply_to_inquiry_from_logged_in_sender` - ログイン済み送信者への返信
- ✅ `test_reply_to_inquiry_with_email` - メール送信フラグ付き返信
- ✅ `test_reply_to_inquiry_not_found` - 存在しない問い合わせ（404）
- ✅ `test_reply_to_inquiry_empty_body_fails` - 空の返信内容（422）
- ✅ `test_reply_as_non_admin_fails` - 非管理者の返信試行（403）

---

## 関連ファイル

### 修正ファイル
- ✅ `k_back/app/crud/crud_inquiry.py` - `create_reply` メソッド修正
- ✅ `k_back/app/api/v1/endpoints/admin_inquiries.py` - トランザクション管理確認
- ✅ `k_back/tests/api/v1/test_inquiry_endpoints.py` - テストケース追加

### ドキュメント
- ✅ `md_files_design_note/task/1_inquiries/greenlet_spawn_fix.md` - 本ファイル
- ✅ `md_files_design_note/task/1_inquiries/reply_endpoint_implementation.md` - 実装報告
- ✅ `md_files_design_note/task/1_inquiries/test_implementation_complete.md` - テスト実装報告

---

## 修正日時

2025-12-08

## 追加修正: 未ログインユーザーへの返信時のエラー (2025-12-08)

### 問題の発見

未ログインユーザーに対する返信時に、同じgreenlet_spawnエラーが発生していました。

### 根本原因

`create_reply` メソッド内で `append_delivery_log` を呼び出していましたが、このメソッドは内部で `get_inquiry_by_id` を再度実行し、同じInquiryDetailオブジェクトを再取得していました。

**問題のコード**:
```python
# create_reply内
if send_email and sender_email:
    log_entry = {...}
    await self.append_delivery_log(
        db=db,
        inquiry_detail_id=inquiry_id,  # ❌ 内部で再度DBから取得
        log_entry=log_entry
    )
```

**append_delivery_log内部**:
```python
async def append_delivery_log(self, db, *, inquiry_detail_id, log_entry):
    inquiry = await self.get_inquiry_by_id(db=db, inquiry_id=inquiry_detail_id)  # ❌ 二重取得
    # ... delivery_log更新
```

### なぜ問題だったのか

1. **トランザクション中の二重取得**: 同じトランザクション内で同じオブジェクトを再度クエリ
2. **セッション状態の競合**: 既存のinquiryオブジェクトとの状態不整合
3. **遅延ロードのトリガー**: 再取得したオブジェクトでのリレーションシップアクセス

### 修正内容

**ファイル**: `k_back/app/crud/crud_inquiry.py:421-441`

`append_delivery_log` を呼び出す代わりに、既に取得済みの `inquiry` オブジェクトのdelivery_logを直接更新するように変更：

```python
# メール送信フラグがTrueの場合はdelivery_logに記録
if send_email and sender_email:
    log_entry = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "action": "reply_email_queued",
        "recipient": sender_email,
        "message_id": str(reply_message.id),
        "staff_id": str(reply_staff_id)
    }

    # ✅ delivery_logを直接更新（既存のinquiryオブジェクトを使用）
    current_log = list(inquiry.delivery_log) if inquiry.delivery_log else []
    current_log.append(log_entry)
    inquiry.delivery_log = current_log

    # SQLAlchemyにJSONフィールドの変更を明示的に通知
    from sqlalchemy.orm.attributes import flag_modified
    flag_modified(inquiry, "delivery_log")

    db.add(inquiry)
    await db.flush()
```

### 修正のポイント

1. **オブジェクトの再利用**: 既に取得済みの `inquiry` オブジェクトを直接使用
2. **二重取得の回避**: `get_inquiry_by_id` の再実行を排除
3. **トランザクションの一貫性**: 同じオブジェクトインスタンスを使い続ける
4. **flag_modified**: JSONフィールドの変更をSQLAlchemyに明示的に通知

### テスト結果

修正後、すべてのテストがパス:

```
====== 5 passed, 11 warnings in 49.48s ======
```

## 追加修正2: エンドポイントでのcommit後のオブジェクトアクセス (2025-12-08)

### 問題の発見

接続プールレベルでMissingGreenletエラーが発生していました：

```
sqlalchemy.exc.MissingGreenlet: greenlet_spawn has not been called;
can't call await_only() here. Was IO attempted in an unexpected place?
```

### 根本原因

エンドポイントで `commit()` 後に `reply_message.id` にアクセスしていました。

**問題のコード**: `k_back/app/api/v1/endpoints/admin_inquiries.py:227-247`

```python
reply_message = await crud_inquiry.create_reply(...)

await db.commit()  # ← セッションが閉じられる

return InquiryReplyResponse(
    id=reply_message.id,  # ❌ デタッチ状態のオブジェクトにアクセス
    message=message_text
)
```

### なぜ問題だったのか

1. **セッションのクローズ**: `commit()` でセッションが閉じられる
2. **オブジェクトのデタッチ**: `reply_message` がセッションから切り離される
3. **属性アクセスでエラー**: デタッチ状態での属性アクセスが接続プールエラーをトリガー

### 修正内容

**ファイル**: `k_back/app/api/v1/endpoints/admin_inquiries.py:227-250`

commit前にIDを取得するように変更：

```python
reply_message = await crud_inquiry.create_reply(...)

# ✅ コミット前に必要な値を取得（重要！）
reply_message_id = reply_message.id

await db.commit()

return InquiryReplyResponse(
    id=reply_message_id,  # ✅ ローカル変数を使用
    message=message_text
)
```

### テスト結果

修正後、すべてのテストがパス:

```
====== 5 passed, 11 warnings in 49.87s ======
```

## まとめ: 3つの修正

### 1. CRUD層: リレーションシップの遅延ロード回避
- データベース操作前にすべてのリレーションシップデータをローカル変数に保存

### 2. CRUD層: オブジェクト二重取得の回避
- `append_delivery_log` 呼び出しを削除し、既存オブジェクトのdelivery_logを直接更新

### 3. エンドポイント層: commit後のオブジェクトアクセス回避
- commit前に必要な値（ID）をローカル変数に保存

## SQLAlchemyベストプラクティス

### ✅ 適用したベストプラクティス

1. **Eager Loading**: `selectinload` でリレーションシップを事前ロード
2. **リレーションアクセスの分離**: DB操作前にすべてのリレーションデータを取得
3. **オブジェクトの再利用**: 同じトランザクション内で同じオブジェクトを再取得しない
4. **commit前の値取得**: commitでセッションが閉じる前に必要な値を全て取得
5. **トランザクション管理**: CRUD層は `flush`、エンドポイント層は `commit`/`rollback`

## ステータス

✅ 修正完了 - すべてのテストがパス（3つのgreenletエラー修正完了）
