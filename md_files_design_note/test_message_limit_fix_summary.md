# test_message_limit.py 修正完了レポート

**作成日**: 2025-11-25
**対象ファイル**:
- `k_back/tests/crud/test_message_limit.py`
- `k_back/app/crud/crud_message.py`

## テスト結果

✅ **全テスト合格**

```
test_message_count_under_limit: PASSED
test_message_count_at_limit: PASSED
test_message_count_over_limit: PASSED
test_message_limit_does_not_affect_other_offices: PASSED
test_test_data_messages_not_counted_in_limit: PASSED
```

## 根本原因

### 問題1: 非決定的なソート順序

**症状**:
- `test_message_count_over_limit` が断続的に失敗
- ある実行では成功し、別の実行では失敗する

**原因**:
メッセージが高速に作成されると、複数のメッセージが同じマイクロ秒の`created_at`タイムスタンプを持つ可能性があります。`ORDER BY created_at ASC`だけでは、同じタイムスタンプを持つメッセージの順序が非決定的になります。

```python
# 問題のあったクエリ（crud_message.py:133）
.order_by(Message.created_at.asc())  # ← タイムスタンプが同じ場合、順序が不定
```

**影響**:
- テストは作成順序に基づいてメッセージIDを保存: `oldest_6_ids = message_ids[:6]`
- しかし、DBクエリはタイムスタンプでソートし、同じタイムスタンプの場合はランダムな順序
- UUIDはランダムなので、UUID順序 ≠ 作成順序
- 結果として、テストが期待するメッセージとCRUDメソッドが削除するメッセージが一致しない

### 問題2: テスト側の誤った仮定

**症状**:
テストが作成順序に基づいてメッセージIDを保存していたが、これはDB側のソート順序と一致しない

**原因**:
```python
# 問題のあったテストコード
message_ids.append(msg.id)
oldest_6_ids = message_ids[:6]  # ← 作成順序に基づく仮定
```

このアプローチは、最初の6件のメッセージが常にDBクエリで選ばれる最も古い6件と一致すると仮定していますが、タイムスタンプの衝突時にはこれが成り立ちません。

## 実装した修正

### 修正1: CRUD側の決定的なソート順序

**ファイル**: `k_back/app/crud/crud_message.py:133`

```python
# 修正前
.order_by(Message.created_at.asc())

# 修正後
.order_by(Message.created_at.asc(), Message.id.asc())
```

**効果**:
- 第1ソートキー: `created_at` (時系列順)
- 第2ソートキー: `id` (UUID順、タイブレーカー)
- 完全に決定的な順序が保証される

### 修正2: テスト側でDB順序を正確に取得

**ファイル**: `k_back/tests/crud/test_message_limit.py`

#### test_message_count_at_limit (行91-102)

```python
# 修正前
oldest_message_id = message_ids[0]  # ← 作成順序の仮定

# 修正後
oldest_stmt = (
    select(Message.id)
    .where(
        Message.office_id == office_id,
        Message.is_test_data == False
    )
    .order_by(Message.created_at.asc(), Message.id.asc())  # ← CRUDと同じ順序
    .limit(1)
)
oldest_result = await db_session.execute(oldest_stmt)
oldest_message_id = oldest_result.scalar_one()
```

#### test_message_count_over_limit (行158-169)

```python
# 修正前
oldest_6_ids = message_ids[:6]  # ← 作成順序の仮定

# 修正後
oldest_stmt = (
    select(Message.id)
    .where(
        Message.office_id == office_id,
        Message.is_test_data == False
    )
    .order_by(Message.created_at.asc(), Message.id.asc())  # ← CRUDと同じ順序
    .limit(6)
)
oldest_result = await db_session.execute(oldest_stmt)
oldest_6_ids = [row[0] for row in oldest_result.all()]
```

**効果**:
- テストはCRUDメソッドと全く同じクエリロジックを使用
- 削除されるべき正確なメッセージIDを取得
- タイムスタンプ衝突の有無に関わらず、テストが正しく検証

## なぜこの修正が必要だったか

### タイミングの問題

```python
# テストループ内での高速作成
for i in range(55):
    msg = await crud_message.create_personal_message(...)
    message_ids.append(msg.id)  # ← i=0,1,2,3,4,5
```

PostgreSQLの`TIMESTAMP`精度はマイクロ秒ですが、Pythonの高速ループでは複数のメッセージが同じマイクロ秒で作成される可能性があります:

```
message[0]: 2025-11-25 08:00:00.123456 (UUID: aaa...)
message[1]: 2025-11-25 08:00:00.123456 (UUID: bbb...)
message[2]: 2025-11-25 08:00:00.123456 (UUID: ccc...)
message[3]: 2025-11-25 08:00:00.123457 (UUID: ddd...)
message[4]: 2025-11-25 08:00:00.123457 (UUID: eee...)
message[5]: 2025-11-25 08:00:00.123457 (UUID: fff...)
```

`ORDER BY created_at ASC`だけでは:
- message[0]、[1]、[2]の順序が不定（すべて .123456）
- message[3]、[4]、[5]の順序が不定（すべて .123457）

`ORDER BY created_at ASC, id ASC`の場合:
- まず`created_at`でソート
- 同じタイムスタンプ内では`id`（UUID）の辞書順でソート
- 完全に決定的

### なぜUUIDは作成順序と一致しないか

UUID v4はランダム生成なので:
```
作成順序: message[0] → message[1] → message[2]
UUID順序: message[1] (UUID: aaa) < message[0] (UUID: bbb) < message[2] (UUID: ccc)
```

これがテスト失敗の原因でした。

## ベストプラクティス

### 1. 常に決定的なソート順序を使用

```python
# Good: 決定的なソート
.order_by(Message.created_at.asc(), Message.id.asc())

# Bad: 非決定的なソート
.order_by(Message.created_at.asc())  # タイムスタンプ衝突時に問題
```

### 2. テストはDBの実際の挙動を検証

```python
# Good: DBクエリで実際のIDを取得
oldest_ids = await db.execute(
    select(Message.id)
    .order_by(Message.created_at.asc(), Message.id.asc())
    .limit(6)
).all()

# Bad: 仮定に基づくID
oldest_ids = message_ids[:6]  # 作成順序 ≠ DB順序の可能性
```

### 3. CRUDとテストでクエリロジックを統一

CRUDメソッドのクエリロジックをテストでも使用することで、実際の動作を正確に検証します。

## まとめ

この修正により、メッセージ数上限機能のテストは以下を保証します:

1. ✅ **決定的な削除順序**: タイムスタンプが同じ場合もUUIDでソート
2. ✅ **正確なテスト検証**: DBの実際のソート順序に基づいてテスト
3. ✅ **一貫性のあるテスト結果**: 実行のたびに同じ結果
4. ✅ **本番環境での信頼性**: 実装とテストが完全に一致

すべてのテストが一貫して合格し、メッセージ数上限機能が正しく動作することが確認されました。
