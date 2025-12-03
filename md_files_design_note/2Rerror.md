# 退会処理承認時の MissingGreenlet エラー調査報告

## エラー内容

```
sqlalchemy.exc.MissingGreenlet: greenlet_spawn has not been called; can't call await_only() here.
Was IO attempted in an unexpected place?
```

**発生箇所**: `app/api/v1/endpoints/withdrawal_requests.py:304` (approve endpoint)
**トリガー**: 退会リクエストの承認処理時

## エラーログ分析

```python
File "/app/app/api/v1/endpoints/withdrawal_requests.py", line 304, in approve_withdrawal_request
    return _to_withdrawal_response(loaded_request)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
File "/app/app/api/v1/endpoints/withdrawal_requests.py", line 38, in _to_withdrawal_response
    request_data = request.request_data or {}
                   ^^^^^^^^^^^^^^^^^^^^
```

## 根本原因

### SQLAlchemyの非同期セッションライフサイクル問題

**問題の流れ:**

1. `crud_approval_request.get_by_id_with_relations(db, request_id)` でリクエストを取得
2. この関数は**関連オブジェクト**（`requester`, `reviewer`, `office`）のみをeager load
3. **カラム属性**（`request_data`など）は遅延読み込みのまま
4. `await db.commit()` を実行すると、SQLAlchemyは全オブジェクトを**expired状態**にする
5. commit後、`_to_withdrawal_response()`で`request.request_data`にアクセス
6. SQLAlchemyが遅延読み込みを試みるが、非同期セッションコンテキストは既に終了
7. `MissingGreenlet`エラー発生

### get_by_id_with_relations の実装（問題箇所）

**ファイル**: `k_back/app/crud/crud_approval_request.py:207-224`

```python
async def get_by_id_with_relations(
    self,
    db: AsyncSession,
    request_id: uuid.UUID
) -> Optional[ApprovalRequest]:
    """IDでリクエストを取得（関連データ含む）"""
    result = await db.execute(
        select(self.model)
        .where(self.model.id == request_id)
        .options(
            selectinload(self.model.requester),  # ← 関連オブジェクトのみロード
            selectinload(self.model.reviewer),
            selectinload(self.model.office)
        )
        # request_data などのカラム属性は遅延読み込みのまま
    )
    return result.scalar_one_or_none()
```

### エンドポイントの実装（問題箇所）

**ファイル**: `k_back/app/api/v1/endpoints/withdrawal_requests.py:299-304`

```python
# commit前にリレーションをロード（ResourceClosedError対策）
loaded_request = await crud_approval_request.get_by_id_with_relations(db, request_id)

await db.commit()  # ← ここでオブジェクトがexpiredになる

return _to_withdrawal_response(loaded_request)  # ← request_dataアクセス時にエラー
```

## 解決策

### commit前に必要な属性をメモリにロード

**修正内容**: 3つのエンドポイント（create, approve, reject）で同じ修正を適用

**ファイル**: `k_back/app/api/v1/endpoints/withdrawal_requests.py`
- Lines 142-149 (create endpoint)
- Lines 299-306 (approve endpoint)
- Lines 374-381 (reject endpoint)

**修正前**:
```python
# commit前にリレーションをロード（ResourceClosedError対策）
loaded_request = await crud_approval_request.get_by_id_with_relations(db, request_id)

await db.commit()

return _to_withdrawal_response(loaded_request)
```

**修正後（ベストプラクティス版）**:
```python
# commit前にリレーションをロード
loaded_request = await crud_approval_request.get_by_id_with_relations(db, request_id)

# commit前にレスポンスデータを生成（MissingGreenletエラー対策）
response_data = _to_withdrawal_response(loaded_request)

# commitはレスポンス生成後に実行
await db.commit()

return response_data
```

**アプローチの選択理由**:
- SQLAlchemyベストプラクティス: commit前にシリアライズ
- 保守性が高い: 明示的でわかりやすい
- FastAPI標準パターン: Pydanticモデル化してからcommit

### なぜこの修正が有効か

1. **属性アクセスによる強制ロード**: `_ = loaded_request.request_data` により、commit前に属性がメモリに読み込まれる
2. **メモリ内データの保持**: commit後もオブジェクトはメモリ内のデータを保持しているため、アクセス可能
3. **非同期コンテキスト不要**: メモリ内のデータにアクセスするだけなので、非同期セッションは不要

## 検証結果

### テスト実行

```bash
docker compose exec backend pytest tests/api/v1/test_withdrawal_requests.py -v
```

**結果**: ✅ **17 passed in 108.72s**

全テスト成功:
- test_create_withdrawal_request_as_owner
- test_approve_withdrawal_request_as_app_admin ← このテストで以前エラーが発生
- test_reject_withdrawal_request_as_app_admin
- その他14テスト

## SQLAlchemyベストプラクティス

### 非同期セッションでの注意点

1. **commit後のアクセスは危険**: commit後にオブジェクトの属性にアクセスすると、遅延読み込みが発生する可能性がある
2. **必要な属性は事前ロード**: commit前に必要な全ての属性・関連オブジェクトをロードする
3. **Eager Loading推奨**: `selectinload()`, `joinedload()` などで関連データを明示的にロード
4. **属性の事前アクセス**: 遅延読み込みされる属性は、commit前に明示的にアクセスしてメモリにロード

### 代替案（今回は採用せず）

1. **expire_on_commit=False**: セッション作成時に設定（グローバルな影響があるため非推奨）
2. **db.expunge()**: オブジェクトをセッションから切り離す（管理が複雑になる）
3. **全属性のEager Loading**: `.options(load_only(...))` で全属性を明示的にロード（冗長）

## 類似エラーとの比較

### ResourceClosedError vs MissingGreenlet

| エラー | 原因 | 発生タイミング |
|--------|------|--------------|
| **ResourceClosedError** | トランザクション/接続が閉じた後にクエリ実行 | commit後の新規クエリ |
| **MissingGreenlet** | 非同期コンテキスト外で非同期操作を試行 | commit後の遅延読み込み |

両者とも**「commit後のデータアクセス」**が根本原因だが、エラーの種類が異なる。

## 影響範囲

- **修正箇所**: `withdrawal_requests.py` の3つのエンドポイント
- **影響なし**: 他のファイルは修正不要
- **下位互換性**: 完全に保たれている

## 優先度

**高**: 退会処理の承認・却下機能が完全に動作不能だった

---

**調査日**: 2025-11-30
**調査者**: Claude Code
**ステータス**: 解決済み
**関連**: 1Lerror.md (フロントエンドAPI契約), 3memox.md (テスト隔離問題)
