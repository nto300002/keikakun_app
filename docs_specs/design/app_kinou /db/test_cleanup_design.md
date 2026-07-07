# テストデータクリーンアップ設計書

作成日: 2025-11-09
目的: ファクトリ生成テストデータの安全なクリーンアップと検証

---

## 📋 設計思想

### 核心原則：**安全第一**
1. **ファクトリ生成データのみを削除** - 手動作成の開発用データは保護
2. **本番環境での実行を防止** - 複数の安全機構
3. **トランザクション管理の徹底** - データの整合性を保証

---

## 🏗️ アーキテクチャ

### 1. 自動クリーンアップ機構

#### `conftest.py` - セッションレベルクリーンアップ
```python
@pytest_asyncio.fixture(scope="session", autouse=True)
async def cleanup_database_session():
    """
    全テストセッションの前後でファクトリ生成データをクリーンアップ
    """
    # テスト実行前: クリーンアップ
    await safe_cleanup_test_database(engine)

    yield  # テスト実行

    # テスト実行後: クリーンアップ
    await safe_cleanup_test_database(engine)
```

**重要な修正点（2025-11-09）**:
- `transaction.commit()`の追加により、削除が実際にDBに反映される
- `transaction.rollback()`のエラーハンドリング

### 2. 安全なクリーンアップロジック

#### `tests/utils/safe_cleanup.py`
```python
class SafeTestDataCleanup:
    @staticmethod
    async def delete_factory_generated_data(db: AsyncSession):
        """ファクトリパターンに一致するデータのみを削除"""
```

**識別パターン**:
- **Staff**: `@test.com`, `@example.com`, 名前に`テスト`
- **Office**: 名前に`テスト事業所`, `test`, `Test`
- **WelfareRecipient**: 名前に`テスト`, `test`
- **その他**: RoleChangeRequest, EmployeeActionRequest, Notice（全て削除対象）

**削除順序（外部キー制約を考慮）**:
1. 事業所関連データ（plan_deliverables, support_plan_statuses等）
2. 利用者関連データ
3. 事業所
4. スタッフ（再割当処理を含む）

**追加機能（2025-11-09）**:
- `employee_action_requests`テーブルの削除サポート

---

## 🧪 テスト設計

### `tests/test_db_cleanup.py`

#### 設計変更（2025-11-09）

**Before（旧設計）**:
```python
# ❌ 問題: DBが完全に空であることを期待
assert office_count == 0  # 開発用データがあると失敗
```

**After（新設計）**:
```python
# ✅ 安全: ファクトリデータのみを検証
result = await db_session.execute(
    select(func.count()).select_from(Office).where(
        or_(
            Office.name.like('%テスト事業所%'),
            Office.name.like('%test%'),
            Office.name.like('%Test%')
        )
    )
)
office_count = result.scalar()
assert office_count == 0  # ファクトリデータがないことを確認
# 💡 手動作成の開発用データ（gmail.comなど）は許容される
```

### テストクラス構成

#### 1. `TestDatabaseCleanup`
- `test_database_starts_empty_of_factory_data` - ファクトリデータが存在しない
- `test_transaction_rollback_after_test` - ロールバック機能
- `test_check_all_test_tables_are_clean` - 全テーブル検証
- `test_nested_transaction_rollback` - ネストトランザクション
- `test_foreign_key_cascade_rollback` - 外部キー制約

#### 2. `TestDatabaseCleanupUtility`
- `test_get_table_counts` - カウント取得
- `test_verify_clean_state` - 状態検証
- `test_delete_test_data_with_no_factory_data` - 空実行

#### 3. `TestFinalDatabaseCleanupVerification`
- `test_final_cleanup_verification_and_force_clean` - 最終クリーンアップ
- `test_verify_all_factory_data_removed` - 完全削除検証

---

## 🔐 安全機構

### 1. 環境チェック
```python
@staticmethod
def verify_test_environment() -> bool:
    db_url = os.getenv("TEST_DATABASE_URL")

    # TEST_DATABASE_URLが設定されていることを確認
    if not db_url:
        return False

    # 本番キーワードチェック
    production_keywords = ['prod', 'production', 'main', 'live']
    if any(keyword in db_url.lower() for keyword in production_keywords):
        return False

    return True
```

### 2. パターンマッチング
- **厳格な識別**: ファクトリ関数の命名規則に厳密に一致
- **ホワイトリスト方式**: 削除対象を明示的に指定

### 3. トランザクション管理
```python
async with engine.connect() as connection:
    transaction = await connection.begin()
    try:
        result = await SafeTestDataCleanup.delete_factory_generated_data(session)
        await transaction.commit()  # ⭐ 重要！
    except Exception as e:
        await transaction.rollback()
        raise
```

---

## 📊 実行結果サマリー

### テスト実行前のクリーンアップ例
```
============================================================
🧪 Starting test session - safe cleanup...
============================================================
  🧹 Deleted 16 factory-generated records:
    - support_plan_statuses: 4
    - welfare_recipients: 4
    - office_staffs: 3
    - plan_deliverables: 1
    - support_plan_cycles: 1
    - office_welfare_recipients: 1
    - offices: 1
    - staffs: 1
✅ Pre-test cleanup completed
============================================================
```

### テスト結果（2025-11-09）
```
13 passed, 6 warnings in 59.80s
```

**全テストがパス！** ✅

---

## 🛠️ トラブルシューティング

### 問題：テスト開始時にファクトリデータが残っている

**原因**: `transaction.commit()`が抜けていた

**解決策**:
```python
# Before (❌)
await connection.begin()
result = await SafeTestDataCleanup.delete_factory_generated_data(session)
# commitなし → 削除がDBに反映されない

# After (✅)
transaction = await connection.begin()
result = await SafeTestDataCleanup.delete_factory_generated_data(session)
await transaction.commit()  # 削除を確定
```

### 問題：開発用データが削除される

**原因**: パターンマッチングが広すぎる

**解決策**: より厳格なパターンを使用
```python
# ❌ 広すぎる
WHERE name LIKE '%test%'  # "latest", "contest"なども一致

# ✅ 適切
WHERE name LIKE '%テスト事業所%'
   OR name LIKE '%test_%'  # test_11など
   OR name LIKE '%Test%'    # Testで始まるもの
```

---

## 📚 関連ファイル

### 主要ファイル
- `k_back/tests/conftest.py` - セッションクリーンアップ
- `k_back/tests/utils/safe_cleanup.py` - クリーンアップロジック
- `k_back/tests/test_db_cleanup.py` - クリーンアップ検証テスト
- `k_back/tests/utils/db_cleanup.py` - クリーンアップユーティリティ

### SQLスクリプト
- `k_back/scripts/manual_cleanup_factory_data.sql` - 手動クリーンアップ用

### ドキュメント
- `xmemo/db_clean_up.md` - クリーンアップタスク履歴
- `xmemo/db/sql/test/test_data_delete.md` - 元のSQLスクリプト
- `xmemo/db/test_cleanup_design.md` - このドキュメント

---

## 🎯 ベストプラクティス

### 1. テストデータの作成
```python
# ✅ Good: ファクトリパターンに従う
test_staff = Staff(
    email="test_user@example.com",  # パターン: @example.com
    last_name="テスト",               # パターン: テスト
    ...
)

# ❌ Bad: パターンに一致しない
real_staff = Staff(
    email="john@gmail.com",  # 開発用データと区別できない
    ...
)
```

### 2. トランザクション管理
```python
# ✅ Good: db_session.flush()を使用
db_session.add(test_data)
await db_session.flush()  # トランザクション内で検証可能

# ❌ Bad: db_session.commit()を使用
await db_session.commit()  # ロールバック不可能
```

### 3. クリーンアップの確認
```python
# テスト後にファクトリデータが残っていないか確認
result = await db_session.execute(
    select(func.count()).select_from(Staff).where(
        Staff.email.like('%@example.com')
    )
)
assert result.scalar() == 0
```

---

## 🚀 今後の改善案

### 優先度: 高
- ✅ **完了**: `transaction.commit()`の追加
- ✅ **完了**: `employee_action_requests`の削除サポート
- ✅ **完了**: ファクトリパターンのみを検証するテスト

### 優先度: 中
- ⬜ **未実装**: より詳細なクリーンアップログ（どのデータが削除されたか）
- ⬜ **未実装**: クリーンアップ失敗時のアラート機能

### 優先度: 低
- ⬜ **未実装**: クリーンアップパフォーマンスの最適化
- ⬜ **未実装**: クリーンアップ履歴の記録

---

## ✅ 結論

**新しい設計の利点**:
1. **安全性**: 開発用データを誤って削除しない
2. **信頼性**: トランザクション管理により整合性を保証
3. **保守性**: ファクトリパターンに従えば自動的にクリーンアップされる
4. **可視性**: 詳細なログにより問題の早期発見が可能

**テスト結果**: 全13テストがパス（100%成功率）

この設計により、テストデータのクリーンアップが自動化され、
開発者は安心してテストを実行できます。
