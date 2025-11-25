# test_message_limit.py エラー分析レポート

**作成日**: 2025-11-25
**対象ファイル**: `tests/crud/test_message_limit.py`

## エラー概要

```
FAILED tests/crud/test_message_limit.py::TestMessageLimit::test_message_count_under_limit
FAILED tests/crud/test_message_limit.py::TestMessageLimit::test_message_count_at_limit
FAILED tests/crud/test_message_limit.py::TestMessageLimit::test_message_count_over_limit
FAILED tests/crud/test_message_limit.py::TestMessageLimit::test_test_data_messages_not_counted_in_limit
```

## 根本原因

### 問題1: メソッドシグネチャの不一致

**エラーメッセージ**:
```
TypeError: CRUDMessage.create_personal_message() got an unexpected keyword argument 's...
```

**原因**:

`crud_message.create_personal_message()` のシグネチャ:
```python
# app/crud/crud_message.py:22
async def create_personal_message(
    self,
    db: AsyncSession,
    *,
    obj_in: Dict[str, Any]  # ← 辞書を期待
) -> Message:
```

テストコード (誤):
```python
# tests/crud/test_message_limit.py:35-43
await crud_message.create_personal_message(
    db=db_session,
    sender_staff_id=owner.id,        # ← 個別の引数として渡している
    recipient_staff_ids=[manager.id],
    office_id=office_id,
    title=f"Test Message {i}",
    body="Test Body",
    priority="normal"
)
```

**正しい呼び出し方法**:

オプション1: `obj_in` として辞書を渡す
```python
await crud_message.create_personal_message(
    db=db_session,
    obj_in={
        "sender_staff_id": owner.id,
        "recipient_ids": [manager.id],
        "office_id": office_id,
        "title": f"Test Message {i}",
        "content": "Test Body",  # ← bodyではなくcontent
        "priority": "normal"
    }
)
```

オプション2: `create_personal_message_with_limit` を使用
```python
# こちらは個別引数を受け付ける
await crud_message.create_personal_message_with_limit(
    db=db_session,
    sender_staff_id=owner.id,
    recipient_staff_ids=[manager.id],
    office_id=office_id,
    title=f"Test Message {i}",
    body="Test Body",
    priority="normal",
    limit=999  # 制限なしの場合は大きな値
)
```

### 問題2: フィールド名の不一致

**エラーメッセージ**:
```
TypeError: 'body' is an invalid keyword argument for Message
```

**原因**:

Messageモデルのフィールド名:
```python
# app/models/message.py:58, 62
title: Mapped[str] = mapped_column(...)
content: Mapped[str] = mapped_column(...)  # ← contentフィールド
```

テストコード (誤):
```python
# tests/crud/test_message_limit.py:268-277
msg = Message(
    office_id=office_id,
    sender_staff_id=owner.id,
    title=f"Test Data Message {i}",
    body="Test Body",  # ← bodyは存在しない
    message_type="personal",
    priority="normal",
    is_test_data=True
)
```

**正しいコード**:
```python
msg = Message(
    office_id=office_id,
    sender_staff_id=owner.id,
    title=f"Test Data Message {i}",
    content="Test Body",  # ← contentを使用
    message_type="personal",
    priority="normal",
    is_test_data=True
)
```

## 影響範囲

### 修正が必要なテストメソッド

1. `test_message_count_under_limit` (行34-43)
2. `test_message_count_at_limit` (行74-83)
3. `test_message_count_over_limit` (行139-148)
4. `test_test_data_messages_not_counted_in_limit` (行268-277)

## 修正方針

### 推奨アプローチ

すべての箇所で `create_personal_message_with_limit` を使用する:
- 個別引数を渡せるため、テストコードが読みやすい
- `limit` パラメータで上限制御が可能
- 上限チェック不要の場合は `limit=999` など大きな値を設定

### 修正例

#### Before (エラー):
```python
await crud_message.create_personal_message(
    db=db_session,
    sender_staff_id=owner.id,
    recipient_staff_ids=[manager.id],
    office_id=office_id,
    title=f"Test Message {i}",
    body="Test Body",
    priority="normal"
)
```

#### After (修正後):
```python
await crud_message.create_personal_message_with_limit(
    db=db_session,
    sender_staff_id=owner.id,
    recipient_staff_ids=[manager.id],
    office_id=office_id,
    title=f"Test Message {i}",
    body="Test Body",
    priority="normal",
    limit=999  # 上限チェック不要の場合
)
```

## CRUDメソッドのインターフェース仕様

### create_personal_message

```python
async def create_personal_message(
    self,
    db: AsyncSession,
    *,
    obj_in: Dict[str, Any]
) -> Message:
```

**必須フィールド** (obj_in内):
- `sender_staff_id`: UUID
- `recipient_ids`: List[UUID]
- `office_id`: UUID
- `title`: str
- `content`: str (注: `body`ではない)
- `priority`: str (default: "normal")

### create_personal_message_with_limit

```python
async def create_personal_message_with_limit(
    self,
    db: AsyncSession,
    *,
    sender_staff_id: UUID,
    recipient_staff_ids: List[UUID],
    office_id: UUID,
    title: str,
    body: str,
    priority: str = "normal",
    limit: int = 50
) -> Message:
```

**特徴**:
- 個別引数を直接受け取る
- 自動的にメッセージ数上限をチェック
- 上限を超えた場合、古いメッセージを削除

## まとめ

テストが失敗している原因は以下の2点:

1. **メソッドシグネチャの不一致**: `create_personal_message` は辞書を期待するが、個別引数を渡している
2. **フィールド名の誤り**: Messageモデルは `content` フィールドを持つが、テストで `body` を使用している

**推奨される修正**:
- すべての箇所で `create_personal_message_with_limit` を使用
- Messageオブジェクトの直接作成時は `content` を使用
- 上限チェック不要の場合は `limit=999` などを設定
