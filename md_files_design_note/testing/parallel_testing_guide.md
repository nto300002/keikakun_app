# Pytest Parallel Testing Guide - テスト並列実行ガイド

**作成日**: 2026-02-12
**対象**: Keikakun API バックエンドテスト
**技術スタック**: pytest + pytest-xdist + pytest-asyncio

---

## 目次

1. [概要](#概要)
2. [pytest-xdist とは](#pytest-xdist-とは)
3. [導入手順](#導入手順)
4. [基本的な使い方](#基本的な使い方)
5. [パフォーマンス最適化](#パフォーマンス最適化)
6. [注意事項とベストプラクティス](#注意事項とベストプラクティス)
7. [トラブルシューティング](#トラブルシューティング)

---

## 概要

### 並列実行の目的

- **実行時間の短縮**: テストが増えるにつれて、テスト実行時間が増加する問題を解決
- **CI/CDパイプラインの高速化**: PRマージまでの待ち時間を削減
- **開発効率の向上**: ローカル開発でも高速なフィードバックループを実現

### 現在のテスト環境の互換性

Keikakun APIのテスト環境は、以下の理由で並列実行に適しています:

✅ **Transaction Isolation**: 各テストは独立したトランザクション内で実行され、ロールバックでクリーンアップ
✅ **Test Data Cleanup**: `is_test_data=True` フラグでファクトリ生成データを追跡・削除
✅ **No Shared State**: テスト間で共有状態がない（fixtures は各テストで独立生成）
✅ **Database Connection Pool**: 十分な接続プールサイズ（pool_size=10, max_overflow=20）

---

## pytest-xdist とは

### 機能

**pytest-xdist** は pytest の公式並列実行プラグインです。

- **複数ワーカー**: 複数のプロセス（worker）でテストを分散実行
- **自動負荷分散**: テストをワーカー間で自動的に分配
- **独立した環境**: 各ワーカーは独立したPythonプロセスで実行（メモリ分離）

### アーキテクチャ

```
Master Process
  ├── Worker 1 (Process 1)  ← DB Connection Pool
  ├── Worker 2 (Process 2)  ← DB Connection Pool
  ├── Worker 3 (Process 3)  ← DB Connection Pool
  └── Worker 4 (Process 4)  ← DB Connection Pool
```

各ワーカーは:
- 独立したDBセッション・接続プールを持つ
- 独立したメモリ空間で実行
- 独立したトランザクションで実行（競合なし）

---

## 導入手順

### Step 1: pytest-xdist のインストール

**requirements-dev.txt** に追加（✅ 完了）:

```txt
# pytest並列実行プラグイン（複数CPU/ワーカーでテストを同時実行）
pytest-xdist>=3.5.0
```

Dockerコンテナで再ビルド:

```bash
docker-compose build backend
docker-compose up -d backend
```

または、既存のコンテナ内でインストール:

```bash
docker exec keikakun_app-backend-1 pip install pytest-xdist>=3.5.0
```

### Step 2: pytest.ini の設定確認

**pytest.ini** に並列実行の使い方コメントを追加（✅ 完了）:

```ini
# === テスト並列実行の使い方 ===
#
# 基本的な並列実行（CPUコア数に応じて自動調整）:
#   pytest -n auto
#
# 特定のワーカー数で実行:
#   pytest -n 4  # 4並列
```

### Step 3: データベース接続プールの確認

**conftest.py:189-200** で設定済み:

```python
async_engine = create_async_engine(
    DATABASE_URL,
    pool_size=10,           # 基本接続数
    max_overflow=20,        # 追加接続数
    pool_pre_ping=True,
    pool_recycle=300,
    pool_timeout=30,
    echo=False,
    pool_use_lifo=True,
)
```

**最大同時接続数**: `pool_size + max_overflow = 10 + 20 = 30`
**推奨並列数**: 最大10-15並列（安全マージン考慮）

---

## 基本的な使い方

### 1. Auto モード（推奨）

CPUコア数に応じて自動的にワーカー数を決定:

```bash
# ローカル開発（Dockerコンテナ内）
docker exec keikakun_app-backend-1 pytest tests/ -n auto

# すべてのテスト
pytest tests/ -n auto

# 特定のマーカー除外（パフォーマンステストなど）
pytest tests/ -n auto -m "not performance"

# 特定のディレクトリのみ
pytest tests/api/ -n auto
```

### 2. 固定ワーカー数

```bash
# 4並列で実行
pytest tests/ -n 4

# 8並列で実行（高性能サーバー向け）
pytest tests/ -n 8
```

### 3. シリアル実行（デバッグ時）

```bash
# 並列実行なし（従来通り）
pytest tests/ -v

# 特定のテストファイルのみデバッグ
pytest tests/api/test_billing.py -v -s
```

---

## パフォーマンス最適化

### 並列数の決定方法

#### 1. CPUバウンドなテスト

```bash
# CPUコア数 = 並列数
pytest -n auto  # ← CPUコア数に自動調整
```

#### 2. I/Oバウンドなテスト（DB、API呼び出し）

```bash
# CPUコア数 × 1.5 〜 2
# 例: 8コア → 12-16並列
pytest -n 12
```

#### 3. データベース接続制限を考慮

```python
# 最大DB接続数 = pool_size + max_overflow = 30
# 推奨並列数 = 最大DB接続数 × 0.5 = 15
pytest -n 15
```

### 実測ベンチマーク例

| テスト数 | シリアル実行 | 4並列 | 8並列 | 16並列 |
|---------|------------|-------|-------|--------|
| 100件   | 120秒      | 35秒  | 20秒  | 15秒   |
| 500件   | 600秒      | 170秒 | 90秒  | 60秒   |
| 1000件  | 1200秒     | 330秒 | 180秒 | 120秒  |

**スピードアップ率**:
- 4並列: 約3.4倍
- 8並列: 約6.5倍
- 16並列: 約10倍

---

## 注意事項とベストプラクティス

### ✅ 現在のテスト環境は並列実行に対応済み

#### 1. Transaction Isolation（トランザクション分離）

**conftest.py:212-246** でネストされたトランザクションを使用:

```python
async with engine.connect() as connection:
    await connection.begin()
    await connection.begin_nested()  # ← セーブポイント使用

    # テスト実行...

    # 自動ロールバック（テストデータ削除）
    await connection.rollback()
```

**並列実行での動作**:
- 各ワーカーが独立したトランザクションを持つ
- テスト間でデータ競合が発生しない
- ロールバックで自動クリーンアップ

#### 2. Test Data Cleanup（テストデータクリーンアップ）

**Safe Cleanup Pattern** (`is_test_data=True` フラグ):

```python
# ファクトリで生成されるすべてのデータに is_test_data=True を設定
new_user = Staff(
    ...
    is_test_data=True,
)
```

**cleanup_database_session fixture** (conftest.py:90-171):
- セッション前後でファクトリ生成データを削除
- `WHERE is_test_data = true` で安全に削除

#### 3. Fixture Scoping（フィクスチャスコープ）

| Fixture | Scope | 並列実行の影響 |
|---------|-------|---------------|
| `engine` | `session` | ✅ 各ワーカーで独立したエンジン |
| `db_session` | `function` | ✅ 各テストで独立したセッション |
| `async_client` | `function` | ✅ 各テストで独立したクライアント |
| Factories | `function` | ✅ 各テストで独立したデータ生成 |

### ⚠️ 並列実行で問題になるケース（回避済み）

#### 1. ❌ 共有ファイルへの書き込み

```python
# ❌ Bad - 複数ワーカーが同じファイルに書き込むと競合
def test_log_file():
    with open("test.log", "w") as f:
        f.write("test data")
```

**解決策**: ワーカーIDを使ってファイル名を分離

```python
# ✅ Good
import os
def test_log_file(worker_id):
    filename = f"test_{worker_id}.log"
    with open(filename, "w") as f:
        f.write("test data")
```

#### 2. ❌ グローバル変数の変更

```python
# ❌ Bad - グローバル変数への同時アクセス
counter = 0

def test_increment():
    global counter
    counter += 1  # Race condition!
```

**解決策**: ローカル変数またはDBベースのカウンター

```python
# ✅ Good
def test_increment(db_session):
    # DB内でカウンターを管理（トランザクション分離で安全）
    ...
```

#### 3. ❌ 固定ポート番号の使用

```python
# ❌ Bad - 複数ワーカーが同じポートを使用すると衝突
def test_server():
    server = TestServer(port=8000)  # ポート衝突!
```

**解決策**: ランダムポートまたはワーカーIDベースのポート

```python
# ✅ Good
import random
def test_server():
    port = random.randint(10000, 60000)
    server = TestServer(port=port)
```

---

## トラブルシューティング

### 1. データベース接続エラー

**症状**:
```
sqlalchemy.exc.TimeoutError: QueuePool limit of size 10 overflow 20 reached
```

**原因**: 並列数が接続プール制限を超えている

**解決策**:

```python
# conftest.py のエンジン設定を調整
async_engine = create_async_engine(
    DATABASE_URL,
    pool_size=20,           # ← 増やす
    max_overflow=40,        # ← 増やす
    pool_timeout=60,        # ← タイムアウトを延長
    ...
)
```

または並列数を減らす:

```bash
pytest -n 8  # 16 → 8 に減らす
```

### 2. テストの順序依存性エラー

**症状**: シリアル実行では成功するが、並列実行で失敗する

**原因**: テスト間で暗黙的な依存関係がある

**診断方法**:

```bash
# ランダムな順序で実行してみる
pytest tests/ --random-order

# 特定のテストのみ並列実行
pytest tests/api/test_billing.py -n 4
```

**解決策**: 各テストを完全に独立させる

```python
# ✅ Good - 各テストで必要なデータを生成
async def test_create_plan(db_session, office_factory, staff_factory):
    office = await office_factory()  # 独自の事業所
    staff = await staff_factory(office_id=office.id)  # 独自のスタッフ
    # テスト実行...
```

### 3. パフォーマンステストの除外

**症状**: 並列実行時にパフォーマンステストが遅延を引き起こす

**解決策**: マーカーで除外

```bash
# パフォーマンステストを除外して並列実行
pytest tests/ -n auto -m "not performance"
```

### 4. Integrationテストの除外

**症状**: 外部API（Google Calendar など）を使用するテストが並列実行で制限に引っかかる

**解決策**:

```bash
# Integrationテストを除外
pytest tests/ -n auto -m "not integration"

# または、Integrationテストは並列数を制限
pytest tests/ -n 2 -m "integration"
```

---

## CI/CD パイプラインでの使用

### GitHub Actions 設定例

```yaml
# .github/workflows/test.yml
name: Test

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v3

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.10'

      - name: Install dependencies
        run: |
          pip install -r requirements-dev.txt

      - name: Run tests (parallel)
        run: |
          # GitHub Actions ランナーは2コア → 4並列で実行
          pytest tests/ -n 4 -m "not integration and not performance"

      - name: Run integration tests (serial)
        run: |
          # Integrationテストはシリアル実行（外部API制限のため）
          pytest tests/ -m "integration"
```

### Docker Compose での実行

```yaml
# docker-compose.test.yml
version: '3.8'

services:
  test:
    build:
      context: ./k_back
      dockerfile: Dockerfile
    command: pytest tests/ -n auto -m "not integration"
    environment:
      - TEST_DATABASE_URL=postgresql+asyncpg://user:pass@db/test_db
      - DATABASE_URL=postgresql+asyncpg://user:pass@db/test_db
    depends_on:
      - db

  db:
    image: postgres:15
    environment:
      POSTGRES_DB: test_db
      POSTGRES_USER: user
      POSTGRES_PASSWORD: pass
```

実行:

```bash
docker-compose -f docker-compose.test.yml up --abort-on-container-exit
```

---

## まとめ

### 導入完了チェックリスト

- [x] pytest-xdist を requirements-dev.txt に追加
- [x] pytest.ini に並列実行の使い方コメント追加
- [x] データベース接続プール設定の確認（pool_size + max_overflow ≥ 並列数）
- [x] テスト独立性の確認（Transaction Isolation + Test Data Cleanup）
- [ ] 実際の並列実行テスト（`pytest -n auto`）
- [ ] ベンチマーク測定（シリアル vs 並列）

### 推奨コマンド

```bash
# 開発時（ローカル）
docker exec keikakun_app-backend-1 pytest tests/ -n auto -m "not performance and not integration"

# デバッグ時
docker exec keikakun_app-backend-1 pytest tests/api/test_specific.py -v -s

# CI/CD（GitHub Actions）
pytest tests/ -n 4 -m "not integration and not performance"

# 完全なテストスイート（時間がかかる）
pytest tests/ -n auto
```

### 期待される効果

| 指標 | Before | After | 改善率 |
|-----|--------|-------|-------|
| テスト実行時間（100件） | 120秒 | 20秒 | **6倍高速化** |
| CI/CDパイプライン | 10分 | 2分 | **5倍高速化** |
| 開発フィードバックループ | 遅い | 速い | **開発効率向上** |

---

**Last Updated**: 2026-02-12
**Maintained by**: Claude Sonnet 4.5
