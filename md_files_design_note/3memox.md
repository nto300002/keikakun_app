# 全体テスト実行時の ResourceClosedError 調査と解決

## 問題の概要

全体テスト実行時のみ、`test_withdrawal_requests.py`で`sqlalchemy.exc.ResourceClosedError: This Connection is closed`エラーが発生。
単独実行時や小規模なテストグループでは発生しない。

## エラーログ分析

```
tests/api/v1/test_withdrawal_requests.py:251: in test_get_withdrawal_requests_as_owner
    response = await async_client.get("/api/v1/withdrawal-requests")
...
tests/api/v1/test_welfare_recipients_employee_restriction.py:88: in _override
    result = await db_session.execute(stmt)
...
sqlalchemy.exc.ResourceClosedError: This Connection is closed
```

**重要な発見**: エラーは`test_withdrawal_requests.py`で発生しているが、実際のエラー発生箇所は`test_welfare_recipients_employee_restriction.py:88`の`_override`関数内。

## 根本原因

### テスト隔離の問題

`test_welfare_recipients_employee_restriction.py`の`override_current_user`関数が問題：

```python
async def override_current_user(db_session: AsyncSession, staff: Staff):
    """get_current_user を上書きしてスタッフを返す"""
    async def _override():
        stmt = select(Staff).where(Staff.id == staff.id).options(
            selectinload(Staff.office_associations).selectinload(OfficeStaff.office)
        ).execution_options(populate_existing=True)
        result = await db_session.execute(stmt)  # ← 閉じられたdb_sessionを使用
        return result.scalars().first()

    app.dependency_overrides[get_current_user] = _override  # ← クリーンアップされない
```

### 問題の流れ

1. `test_welfare_recipients_employee_restriction.py`のテストが実行される
2. 各テストで`override_current_user`を呼び出し、`app.dependency_overrides[get_current_user]`を設定
3. `_override`関数がクロージャで`db_session`をキャプチャ
4. テスト完了後、`db_session`がクローズされる
5. **`app.dependency_overrides`がクリアされない** ← 問題
6. 次のテスト（`test_withdrawal_requests.py`）実行時、古いオーバーライドが残っている
7. `get_current_user`が呼ばれると、クローズされた`db_session`を使おうとする
8. `ResourceClosedError`が発生

## 解決策

### 修正内容

`test_welfare_recipients_employee_restriction.py`に`autouse=True`のfixtureを追加して、各テスト後に自動的に`app.dependency_overrides`をクリアする：

```python
@pytest.fixture(autouse=True)
def cleanup_dependency_overrides():
    """各テスト後にdependency_overridesをクリーンアップ"""
    yield
    # テスト完了後にクリーンアップ
    app.dependency_overrides.clear()
```

### 修正箇所

- ファイル: `tests/api/v1/test_welfare_recipients_employee_restriction.py`
- 行: 30-35（新規追加）

## 検証結果

### 修正前

全体テスト実行時に17個の`test_withdrawal_requests.py`テストが`ResourceClosedError`で失敗。

### 修正後

```bash
docker compose exec backend pytest tests/api/v1/test_welfare_recipients_employee_restriction.py tests/api/v1/test_withdrawal_requests.py -v
```

**結果: 25 passed in 187.90s (0:03:07) - 全テスト成功**

内訳：
- `test_welfare_recipients_employee_restriction.py`: 8 tests PASSED
- `test_withdrawal_requests.py`: 17 tests PASSED

## 教訓

1. **テスト隔離の重要性**: FastAPIの`app.dependency_overrides`は明示的にクリアしないとテスト間で漏れる
2. **autouse fixtureの活用**: pytestの`autouse=True`で自動クリーンアップを実装
3. **クロージャとセッションライフサイクル**: クロージャでキャプチャされたデータベースセッションのライフサイクルに注意
4. **エラーログの深読み**: スタックトレースを丁寧に読むことで、真の原因が別のファイルにあることが判明

## 今後の推奨事項

1. 他のテストファイルで`app.dependency_overrides`を使用している箇所がないか確認
2. 同様のクリーンアップfixtureが必要な箇所を特定
3. テスト全体の実行順序に依存しない堅牢なテスト設計を維持

---

**修正日**: 2025-11-29
**対応者**: Claude Code
**ステータス**: 解決済み
