# テストモジュールインポートエラー調査レポート

**調査日**: 2026-02-17
**エラー**: `ModuleNotFoundError: No module named 'tests.utils.utils'`
**影響範囲**: テスト実行の失敗

---

## 📋 目次

1. [エラー概要](#エラー概要)
2. [根本原因](#根本原因)
3. [解決策](#解決策)
4. [実装手順](#実装手順)
5. [検証方法](#検証方法)

---

## エラー概要

### エラー1: ModuleNotFoundError

```
ImportError while importing test module
'/app/tests/api/v1/endpoints/test_dashboard_rate_limit.py'.

tests/api/v1/endpoints/test_dashboard_rate_limit.py:16: in <module>
    from tests.utils.utils import create_random_staff, create_random_office
E   ModuleNotFoundError: No module named 'tests.utils.utils'
```

### エラー2: Import File Mismatch

```
ERROR collecting tests/integration/test_dashboard_performance.py
import file mismatch:
imported module 'test_dashboard_performance' has this __file__ attribute:
  /app/tests/api/v1/test_dashboard_performance.py
which is not the same as the test file we want to collect:
  /app/tests/integration/test_dashboard_performance.py
HINT: remove __pycache__ / .pyc files and/or use a unique basename
for your test file modules
```

---

## 根本原因

### 問題1: 不正なインポートパス

**エラー箇所**: `tests/api/v1/endpoints/test_dashboard_rate_limit.py:16`

```python
# ❌ 間違い
from tests.utils.utils import create_random_staff, create_random_office
```

**原因**:
- `tests/utils/utils.py` というファイルは存在しない
- 実際のファイル構造:
  ```
  tests/
  ├── utils.py                    # レガシーファイル（後方互換性のため残存）
  └── utils/
      ├── __init__.py             # ✅ 正しいインポート元
      ├── helpers.py              # create_random_staff の実装
      └── dashboard_helpers.py    # create_test_office の実装
  ```

**正しいインポート**:

```python
# ✅ 正しい（方法1: utils/__init__.pyから）
from tests.utils import create_random_staff

# ✅ 正しい（方法2: 直接helpers.pyから）
from tests.utils.helpers import create_random_staff

# ⚠️ create_random_office は存在しない
# 代わりに create_test_office を使用
from tests.utils.dashboard_helpers import create_test_office
```

---

### 問題2: 存在しない関数 `create_random_office`

**調査結果**:
- `create_random_office` という関数は定義されていない
- 代わりに `create_test_office` が `tests/utils/dashboard_helpers.py` に実装されている

**定義箇所**:

```python
# tests/utils/dashboard_helpers.py:40
async def create_test_office(
    db: AsyncSession,
    *,
    name: str = None,
    office_type: OfficeType = OfficeType.MULTI_FUNCTIONAL,
    billing_status: BillingStatus = BillingStatus.ACTIVE,
    max_user_count: int = 100,
) -> Office:
    """テスト用事業所を作成"""
    ...
```

**エクスポート状況**:

```python
# tests/utils/__init__.py
__all__ = [
    ...
    "create_test_office",  # ✅ エクスポートされている
    ...
]
```

---

### 問題3: テストファイル名の重複

**重複ファイル**:
1. `/app/tests/api/v1/test_dashboard_performance.py`
2. `/app/tests/integration/test_dashboard_performance.py`

**原因**:
- 同じモジュール名 `test_dashboard_performance` が2箇所に存在
- Pytestがモジュールをインポートする際に競合が発生

**影響**:
- Pytestが正しいテストファイルを特定できない
- `__pycache__` に古いモジュールがキャッシュされている可能性

---

## 解決策

### 解決策1: インポートパスの修正

**対象ファイル**: `tests/api/v1/endpoints/test_dashboard_rate_limit.py`

**変更前**:
```python
from tests.utils.utils import create_random_staff, create_random_office
```

**変更後**:
```python
# create_random_staff はヘルパーから、create_test_office はダッシュボードヘルパーから
from tests.utils import create_random_staff
from tests.utils.dashboard_helpers import create_test_office
```

または、より明示的に:
```python
from tests.utils.helpers import create_random_staff
from tests.utils.dashboard_helpers import create_test_office
```

---

### 解決策2: 関数名の修正

**対象ファイル**: `tests/api/v1/endpoints/test_dashboard_rate_limit.py`

**変更前**:
```python
office = await create_random_office(db_session, ...)
```

**変更後**:
```python
office = await create_test_office(
    db_session,
    name="テスト事業所",
    office_type=OfficeType.MULTI_FUNCTIONAL,
    billing_status=BillingStatus.ACTIVE
)
```

---

### 解決策3: テストファイル名の変更

**選択肢A**: `test_dashboard_performance.py` をリネーム（推奨）

```bash
# api/v1 のファイルをリネーム（より具体的な名前に）
mv tests/api/v1/test_dashboard_performance.py \
   tests/api/v1/test_dashboard_api_performance.py
```

**選択肢B**: `test_dashboard_performance.py` を削除（重複している場合）

```bash
# どちらか一方が不要な場合
rm tests/api/v1/test_dashboard_performance.py
# または
rm tests/integration/test_dashboard_performance.py
```

**推奨**: 両方のテストが必要な場合は選択肢Aを採用

---

### 解決策4: `__pycache__` のクリーンアップ

```bash
# 全ての __pycache__ と .pyc ファイルを削除
find /Users/naotoyasuda/workspase/keikakun_app/k_back/tests -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null
find /Users/naotoyasuda/workspase/keikakun_app/k_back/tests -type f -name "*.pyc" -delete
```

---

## 実装手順

### ステップ1: `test_dashboard_rate_limit.py` の修正

```bash
cd /Users/naotoyasuda/workspase/keikakun_app/k_back
```

**ファイル**: `tests/api/v1/endpoints/test_dashboard_rate_limit.py`

**修正内容**:

```python
"""
ダッシュボードAPIのレート制限テスト

レート制限:
- 60リクエスト/分
- 超過時: 429 Too Many Requests
"""

import pytest
import asyncio
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app import crud
from app.models.enums import StaffRole, BillingStatus, OfficeType
# ✅ 修正: 正しいインポートパス
from tests.utils import create_random_staff
from tests.utils.dashboard_helpers import create_test_office


@pytest.mark.asyncio
class TestDashboardRateLimit:
    """ダッシュボードAPIのレート制限テスト"""

    async def test_rate_limit_allows_normal_requests(
        self,
        client: AsyncClient,
        db_session: AsyncSession
    ):
        """通常のリクエスト数ではレート制限に引っかからない"""
        # Arrange: テストスタッフと事業所を作成
        # ✅ 修正: create_random_office → create_test_office
        office = await create_test_office(
            db_session,
            name="レート制限テスト事業所",
            office_type=OfficeType.MULTI_FUNCTIONAL,
            billing_status=BillingStatus.ACTIVE
        )

        staff = await create_random_staff(
            db_session,
            email="ratelimit_test@example.com",
            office_id=office.id,
            role=StaffRole.ADMIN
        )

        # ... 以下のテストコード ...
```

---

### ステップ2: テストファイル名の変更

```bash
# api/v1 のテストファイルをリネーム
cd /Users/naotoyasuda/workspase/keikakun_app/k_back/tests
mv api/v1/test_dashboard_performance.py \
   api/v1/test_dashboard_api_performance.py
```

**理由**:
- `test_dashboard_performance.py` と `test_dashboard_api_performance.py` で明確に区別
- `integration/test_dashboard_performance.py` は統合テスト
- `api/v1/test_dashboard_api_performance.py` はAPIエンドポイントテスト

---

### ステップ3: `__pycache__` のクリーンアップ

```bash
# k_back ディレクトリで実行
cd /Users/naotoyasuda/workspase/keikakun_app/k_back

# 全ての __pycache__ を削除
find tests -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null

# .pyc ファイルを削除
find tests -type f -name "*.pyc" -delete

# 確認
find tests -type d -name "__pycache__" | wc -l
# → 0 になればOK
```

---

### ステップ4: 他のテストファイルも確認

**潜在的な問題がある可能性があるファイルを検索**:

```bash
# 間違ったインポートパターンを検索
grep -rn "from tests.utils.utils import" tests/ --include="*.py"

# 結果があれば、同様に修正が必要
```

**修正が必要な場合の例**:

```python
# ❌ 修正前
from tests.utils.utils import create_random_staff, create_random_office

# ✅ 修正後
from tests.utils import create_random_staff
from tests.utils.dashboard_helpers import create_test_office
```

---

## 検証方法

### テスト1: インポートエラーの解消確認

```bash
cd /Users/naotoyasuda/workspase/keikakun_app/k_back

# 特定のテストファイルのみ実行
docker exec keikakun_app-backend-1 pytest \
  tests/api/v1/endpoints/test_dashboard_rate_limit.py \
  -v

# 期待結果: ModuleNotFoundError が発生しない
```

### テスト2: ファイル名重複エラーの解消確認

```bash
# 全テストを収集（実行はしない）
docker exec keikakun_app-backend-1 pytest --collect-only

# 期待結果:
# - "import file mismatch" エラーが出ない
# - test_dashboard_performance と test_dashboard_api_performance が両方表示される
```

### テスト3: 全テストの実行

```bash
# 全テストを実行
docker exec keikakun_app-backend-1 pytest tests/ -v

# 期待結果: 全テストが正常に実行される（PASS/FAILは別として）
```

### テスト4: カバレッジ測定

```bash
# カバレッジ付きでテスト実行
docker exec keikakun_app-backend-1 pytest tests/ \
  --cov=app.api.v1.endpoints.dashboard \
  --cov=app.crud.crud_dashboard \
  --cov=app.schemas.dashboard \
  --cov-report=html \
  -v

# 結果確認
# htmlcov/index.html をブラウザで開く
```

---

## まとめ

### 発見された問題

1. ✅ **インポートパス誤り**: `tests.utils.utils` は存在しない
2. ✅ **存在しない関数**: `create_random_office` は未定義
3. ✅ **ファイル名重複**: `test_dashboard_performance.py` が2箇所に存在
4. ✅ **キャッシュ問題**: `__pycache__` に古いモジュールが残存

### 解決策

1. ✅ インポートパスを `tests.utils` または `tests.utils.helpers` に修正
2. ✅ `create_random_office` → `create_test_office` に変更
3. ✅ テストファイル名を `test_dashboard_api_performance.py` にリネーム
4. ✅ `__pycache__` と `.pyc` ファイルを削除

### 次のステップ

1. **即座に実施**: 上記の修正を適用
2. **検証**: 全テストが正常に収集・実行されることを確認
3. **カバレッジ測定**: テストカバレッジ80%以上を確認
4. **CI/CD確認**: GitHub Actionsで自動テストが成功することを確認

---

**作成日**: 2026-02-17
**ステータス**: ✅ 調査完了（修正待ち）
**影響度**: 高（全テスト実行がブロックされている）
**優先度**: 🔴 最高（即座に修正が必要）
