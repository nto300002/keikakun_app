# テスト設計・CI自動化 手順書

**作成日**: 2026-03-04
**対象**: `k_back/` (FastAPI バックエンド)
**インフラ**: Docker (ローカル) / Google Cloud Build (CI)

---

## 目次

1. [テストディレクトリ構造](#1-テストディレクトリ構造)
2. [テスト種別とマーカー](#2-テスト種別とマーカー)
3. [ローカルでのテスト実行](#3-ローカルでのテスト実行)
4. [カバレッジ管理](#4-カバレッジ管理)
5. [CI自動化の現状と課題](#5-ci自動化の現状と課題)
6. [CI自動化の実装方法](#6-ci自動化の実装方法)
7. [新規テスト追加の手順](#7-新規テスト追加の手順)
8. [CI失敗時の対応](#8-ci失敗時の対応)

---

## 1. テストディレクトリ構造

```
k_back/
├── pytest.ini                    ← テスト設定（asyncio_mode / マーカー / 並列設定）
├── .coveragerc                   ← カバレッジ設定（目標80%・除外パターン）
├── run_coverage.sh               ← カバレッジ計測スクリプト
├── Dockerfile                    ← development ステージでテスト実行
├── requirements-dev.txt          ← pytest / pytest-asyncio / pytest-cov / pytest-xdist 等
│
└── tests/
    ├── conftest.py               ← 共通フィクスチャ（DB・HTTPクライアント・ユーザー生成）
    ├── utils.py                  ← テストユーティリティ関数
    │
    ├── api/v1/                   ← 【APIテスト】エンドポイントの結合テスト
    │   ├── test_auth.py
    │   ├── test_mfa_api.py
    │   ├── test_role_change_requests.py
    │   ├── test_withdrawal_requests.py
    │   ├── test_recipients.py
    │   └── ... (その他エンドポイント)
    │
    ├── services/                 ← 【Serviceテスト】ビジネスロジック・rollback検証
    │   ├── test_role_change_service.py   ← TDD修正済み（rollbackテスト含む）
    │   ├── test_staff_profile_service.py ← TDD修正済み（rollbackテスト含む）
    │   ├── test_support_plan_service.py  ← TDD修正済み（rollbackテスト含む）
    │   ├── test_auth_service.py
    │   └── test_mfa_service.py
    │
    ├── crud/                     ← 【CRUDテスト】DB操作の単体テスト
    │   ├── test_crud_billing.py
    │   ├── test_crud_recipient.py
    │   ├── test_crud_audit_log.py
    │   └── ... (各CRUDモジュール対応)
    │
    ├── models/                   ← 【Modelテスト】DBスキーマ・制約テスト
    ├── schemas/                  ← 【Schemaテスト】Pydantic バリデーションテスト
    ├── security/                 ← 【セキュリティテスト】レートリミット・認証
    ├── integration/              ← 【統合テスト】複数レイヤーにまたがるフロー
    ├── error_handling/           ← 【エラーテスト】日本語エラーメッセージ検証
    ├── tasks/                    ← 【バッチテスト】APSchedulerタスク
    ├── scheduler/                ← 【スケジューラテスト】カレンダー同期
    ├── core/                     ← 【コアテスト】セキュリティ・ストレージ
    └── utils/                    ← テスト用ユーティリティ（DBクリーンアップ等）
        ├── db_cleanup.py
        └── safe_cleanup_with_flag.py
```

---

## 2. テスト種別とマーカー

`pytest.ini` で定義されているマーカー:

| マーカー | 用途 | 実行コスト |
|---------|------|----------|
| (なし) | 通常テスト（全体の大半） | 低 |
| `@pytest.mark.integration` | Google Calendar API 等の外部サービスが必要なテスト | 高（API Key 必要）|
| `@pytest.mark.performance` | 大量データの性能テスト | 高（時間がかかる）|
| `@pytest.mark.slow` | 大規模データセットのセットアップが必要なテスト | 中〜高 |

### マーカーによる実行制御

```bash
# 通常テストのみ（CIで推奨）
pytest -m "not performance and not integration and not slow"

# 全テスト（ローカル確認用）
pytest tests/

# パフォーマンステストのみ
pytest -m performance
```

---

## 3. ローカルでのテスト実行

### 前提条件

```bash
# Docker コンテナが起動していること
docker compose up -d

# コンテナ名の確認
docker ps | grep backend
# → keikakun_app-backend-1
```

### 基本実行

```bash
# 全テスト実行
docker exec keikakun_app-backend-1 pytest tests/ -v

# 特定ディレクトリのみ
docker exec keikakun_app-backend-1 pytest tests/api/ -v
docker exec keikakun_app-backend-1 pytest tests/services/ -v
docker exec keikakun_app-backend-1 pytest tests/crud/ -v

# 特定ファイルのみ
docker exec keikakun_app-backend-1 pytest tests/services/test_role_change_service.py -v

# 特定テスト関数のみ
docker exec keikakun_app-backend-1 pytest tests/services/test_role_change_service.py::test_create_request_rollback_on_error -v
```

### 並列実行（高速化）

```bash
# CPU自動調整（推奨）
docker exec keikakun_app-backend-1 pytest tests/ -n auto

# 並列 + パフォーマンステスト除外（CI向け）
docker exec keikakun_app-backend-1 pytest tests/ -n auto -m "not performance"

# ワーカー数を指定
docker exec keikakun_app-backend-1 pytest tests/ -n 4
```

> **注意**: DB接続プールの設定（pool_size=10, max_overflow=20）が最大30並列まで対応。
> ワーカー数はこれ以下にすること。

### カバレッジ付き実行

```bash
# ターミナルに結果表示
docker exec keikakun_app-backend-1 pytest tests/ --cov=app --cov-report=term

# HTMLレポート生成
docker exec keikakun_app-backend-1 pytest tests/ --cov=app --cov-report=html --cov-report=term

# HTMLをローカルで確認
docker cp keikakun_app-backend-1:/app/htmlcov ./k_back/htmlcov
open k_back/htmlcov/index.html
```

---

## 4. カバレッジ管理

### 設定ファイル（`k_back/.coveragerc`）

| 項目 | 設定値 | 意味 |
|------|-------|------|
| `source` | `app` | `app/` 配下が計測対象 |
| `fail_under` | `80` | 80%未満は CI失敗 |
| `branch` | `True` | 分岐カバレッジも計測 |
| HTML出力 | `htmlcov/` | ブラウザで詳細確認 |
| XML出力 | `coverage.xml` | CI/CD のアーティファクト用 |

### 計測対象外（`omit`）

```
*/tests/*           ← テストコード自体
*/__init__.py       ← 空の初期化ファイル
*/migrations/*      ← DBマイグレーション
app/core/config.py  ← 環境設定
app/main.py         ← エントリポイント
```

### カバレッジ目標

- **全体目標**: 80%以上（`.coveragerc` の `fail_under = 80`）
- **重点カバレッジ対象**:
  - `app/services/` — ビジネスロジック（rollbackテスト含む）
  - `app/api/v1/endpoints/` — エンドポイント認証・レスポンス
  - `app/crud/` — DB操作

---

## 5. CI自動化の現状と課題

### 現状の `cloudbuild.yml` フロー

```
[Cloud Build トリガー（main ブランチへの push）]
          ↓
Step 1: Docker イメージ ビルド（--target=production）
          ↓
Step 2: Artifact Registry へ push（$SHORT_SHA タグ）
          ↓
Step 3: Cloud Run へデプロイ
```

### 課題: テストステップが存在しない

現状の CI は **ビルド → デプロイのみ** でテストを実行していない。
つまり、テストが失敗するコードでも Cloud Run にデプロイされてしまう。

```
❌ 現状
  push → ビルド → デプロイ（テストなし）

✅ 目標
  push → テスト → ビルド → デプロイ（テスト失敗でブロック）
```

---

## 6. CI自動化の実装方法

### 全体フロー設計

```
[main ブランチへの push / PR マージ]
          ↓
Step 1: テスト用 Docker イメージをビルド（--target=development）
          ↓
Step 2: pytest 実行（DB は Cloud Build 内のサービスコンテナで起動）
          ↓（失敗したらここで停止。デプロイされない）
Step 3: カバレッジチェック（80%未満は失敗）
          ↓
Step 4: 本番用 Docker イメージをビルド（--target=production）
          ↓
Step 5: Artifact Registry へ push
          ↓
Step 6: Cloud Run へデプロイ
```

### `cloudbuild.yml` への追加実装

現在の `cloudbuild.yml` の先頭に以下を追加する:

```yaml
steps:
# =============================================
# Step 0: テスト用イメージのビルド
# =============================================
- name: 'gcr.io/cloud-builders/docker'
  id: 'build-test-image'
  args:
    - 'build'
    - '--target=development'       # Dockerfile の development ステージ
    - '-t'
    - 'k-back-test:$SHORT_SHA'
    - '.'

# =============================================
# Step 1: pytest 実行
# =============================================
- name: 'k-back-test:$SHORT_SHA'
  id: 'run-tests'
  waitFor: ['build-test-image']
  entrypoint: 'pytest'
  args:
    - 'tests/'
    - '-n'
    - 'auto'                         # 並列実行
    - '-m'
    - 'not performance and not integration'  # 外部API不要なテストのみ
    - '--tb=short'
    - '-v'
    - '--cov=app'
    - '--cov-report=term'
    - '--cov-report=xml'             # アーティファクト保存用
    - '--cov-fail-under=80'          # 80%未満は失敗
  env:
    # CI環境用の環境変数（Secret Manager から取得）
    - 'DATABASE_URL=${_TEST_DATABASE_URL}'
    - 'SECRET_KEY=${_SECRET_KEY}'
    - 'TESTING=1'
    - 'ENVIRONMENT=test'

# =============================================
# Step 2: 本番イメージのビルド（テスト成功後）
# =============================================
- name: 'gcr.io/cloud-builders/docker'
  id: 'build-production-image'
  waitFor: ['run-tests']             # テスト成功後のみ実行
  args:
    - 'build'
    - '--target=production'
    # ... 以下は現在の cloudbuild.yml の内容と同じ
```

### CI用データベースの準備

Cloud Build 内でテスト専用 PostgreSQL を起動する方法:

```yaml
# cloudbuild.yml に追加（テストDBのセットアップ）
- name: 'postgres:15'
  id: 'start-test-db'
  entrypoint: 'bash'
  args:
    - '-c'
    - |
      docker run -d \
        --name test-postgres \
        --network cloudbuild \
        -e POSTGRES_USER=test \
        -e POSTGRES_PASSWORD=test \
        -e POSTGRES_DB=keikakun_test \
        -p 5432:5432 \
        postgres:15
      # DB起動待機
      sleep 5
```

> **現実的な選択肢**: Cloud SQL の専用テストインスタンスを用意するか、
> Cloud Build のサービスコンテナ機能（`services` ブロック）を使う。

### Secret Manager 連携（テスト用環境変数）

```bash
# CI用シークレットを登録
gcloud secrets create TEST_DATABASE_URL --data-file=- <<< "postgresql+psycopg://test:test@localhost:5432/keikakun_test"
gcloud secrets create TEST_SECRET_KEY --data-file=- <<< "test-secret-key-32chars-minimum"

# Cloud Build サービスアカウントに権限付与
gcloud secrets add-iam-policy-binding TEST_DATABASE_URL \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

### Cloud Build トリガーの設定

```yaml
# Cloud Build トリガー設定（コンソールまたは CLI）

# 1. main ブランチ push 時：テスト → デプロイ
トリガー名: deploy-main
ブランチパターン: ^main$
設定ファイル: k_back/cloudbuild.yml
代入変数:
  _TEST_DATABASE_URL: projects/${PROJECT_ID}/secrets/TEST_DATABASE_URL/versions/latest
  _PROD_DATABASE_URL: projects/${PROJECT_ID}/secrets/PROD_DATABASE_URL/versions/latest

# 2. PR 時：テストのみ（デプロイなし）
トリガー名: test-on-pr
ブランチパターン: ^feature/.*|^fix/.*
設定ファイル: k_back/cloudbuild-test-only.yml
```

---

## 7. 新規テスト追加の手順

### 手順1: 対応するファイルに配置する

```
追加したいテストの種類          →  配置先
─────────────────────────────────────────────────────
API エンドポイントのテスト      →  tests/api/v1/test_xxx.py
Service 層のロジックテスト      →  tests/services/test_xxx_service.py
CRUD 層のテスト                →  tests/crud/test_crud_xxx.py
Model の制約テスト             →  tests/models/test_xxx_model.py
Schema バリデーション          →  tests/schemas/test_xxx_schema.py
セキュリティテスト             →  tests/security/test_xxx_security.py
エラーメッセージテスト         →  tests/error_handling/test_xxx_errors.py
複数レイヤーの統合テスト        →  tests/integration/test_xxx_flow.py
```

### 手順2: テスト基本構造

```python
# tests/services/test_xxx_service.py

import pytest
import pytest_asyncio
from unittest.mock import AsyncMock, patch
from sqlalchemy.ext.asyncio import AsyncSession

# Serviceのimport
from app.services import xxx_service

# =============================================
# 正常系テスト
# =============================================
async def test_create_xxx_success(db_session: AsyncSession, test_staff, test_office):
    """正常系: xxxが作成されることを確認"""
    # Arrange
    data_in = XxxCreate(...)

    # Act
    result = await xxx_service.create_xxx(db=db_session, data_in=data_in)

    # Assert
    assert result.id is not None
    assert result.field == expected_value

# =============================================
# 異常系テスト（rollback確認）
# =============================================
async def test_create_xxx_rollback_on_error(db_session: AsyncSession):
    """異常系: エラー発生時にrollbackされることを確認"""
    # Arrange: DB操作でエラーを発生させるモック
    with patch("app.crud.xxx.create", side_effect=Exception("DB Error")):
        # Act & Assert: 例外が伝播すること
        with pytest.raises(Exception):
            await xxx_service.create_xxx(db=db_session, data_in=XxxCreate(...))

    # Verify: DBにデータが残っていないことを確認
    from sqlalchemy import select
    from app.models.xxx import Xxx
    result = await db_session.execute(select(Xxx))
    assert result.scalars().all() == []
```

### 手順3: conftest.py のフィクスチャを活用する

主要なフィクスチャ（`tests/conftest.py` で定義済み）:

| フィクスチャ名 | 内容 |
|--------------|------|
| `db_session` | テスト用非同期 DB セッション（テスト後 rollback）|
| `client` | FastAPI テスト用 AsyncClient |
| `test_staff` | 認証済みスタッフオブジェクト |
| `test_office` | テスト用事業所オブジェクト |
| `auth_headers` | Authorization ヘッダー付き辞書 |

```python
# フィクスチャの使い方
async def test_example(
    db_session: AsyncSession,   # DB セッション
    client: AsyncClient,         # HTTPクライアント
    auth_headers: dict,          # {"Authorization": "Bearer xxx"}
    test_office,                 # 事業所オブジェクト
):
    response = await client.get("/api/v1/xxx", headers=auth_headers)
    assert response.status_code == 200
```

### 手順4: 実行して確認

```bash
# 追加したテストのみを実行
docker exec keikakun_app-backend-1 pytest tests/services/test_xxx_service.py -v

# 全テストが壊れていないことを確認
docker exec keikakun_app-backend-1 pytest tests/ -n auto -m "not performance" -v
```

### 手順5: TDD を推奨する場合の手順（アーキテクチャ違反修正時）

`tdd_fix_checklist.md` に従い、Red → Green → Refactor で進める:

```
1. [ ] Red:   失敗するテストを書く（修正前のコードでテストが失敗することを確認）
2. [ ] Green: テストが通る最小限の実装をする
3. [ ] ✅:    pytest -n auto -m "not performance" 全体を確認してチェック
```

---

## 8. CI失敗時の対応

### Cloud Build でのログ確認

```bash
# 最新のビルドログを確認
gcloud builds list --limit=5

# 特定ビルドの詳細ログ
gcloud builds log <BUILD_ID>

# ストリーミングで確認（実行中）
gcloud builds log <BUILD_ID> --stream
```

### よくある失敗パターンと対処法

| 失敗パターン | 原因 | 対処法 |
|------------|------|-------|
| `MissingGreenletError` | `selectinload()` なしで関連モデルにアクセス | `.options(selectinload(...))` を追加 |
| `pytest.PytestUnraisableExceptionWarning` | 非同期セッションのクリーンアップ漏れ | `await session.close()` をfinallyで実行 |
| `IntegrityError` | テストデータの重複・外部キー違反 | `is_test_data=True` フラグを使った安全クリーンアップ |
| カバレッジ80%未満 | 新規コードにテストがない | 対応するテストを追加 |
| `asyncio.TimeoutError` | 並列テストのDB接続プール枯渇 | `-n` のワーカー数を減らす（最大30） |
| `patch` のパスが違う | モックのパスが実際のimportパスと不一致 | `from app import crud` 準拠のパスを使う |

### パッチパスの正しい書き方（重要）

```python
# ❌ 間違い（直接importのパスでモック）
with patch("app.services.role_change_service.crud_notice.create", ...):

# ✅ 正しい（from app import crud 準拠のパスでモック）
with patch("app.crud.crud_notice.crud_notice.create", ...):
```

> 詳細: `tdd_fix_checklist.md` の「完了した 1-1 の内容（参考）」を参照

### ローカルでの再現確認

CI が失敗した場合、同じコマンドをローカルで実行して再現させる:

```bash
# CI と同じ条件でテスト実行（マーカー指定）
docker exec keikakun_app-backend-1 pytest tests/ \
  -n auto \
  -m "not performance and not integration" \
  --tb=short \
  -v \
  --cov=app \
  --cov-report=term \
  --cov-fail-under=80
```

---

## 関連ファイル

| ファイル | 説明 |
|---------|------|
| `k_back/pytest.ini` | pytest の基本設定・マーカー定義 |
| `k_back/.coveragerc` | カバレッジ測定設定 |
| `k_back/run_coverage.sh` | カバレッジ計測スクリプト |
| `k_back/cloudbuild.yml` | Cloud Build CI 設定（現状: テストなし）|
| `k_back/tests/conftest.py` | テスト共通フィクスチャ |
| `k_back/Dockerfile` | `development` ステージでテスト実行 |
| `md_files_design_note/tests/test_cov.md` | カバレッジ計測コマンド集 |
| `md_files_design_note/task/maintenance_hosyu/tdd_fix_checklist.md` | TDD修正チェックリスト |

---

**作成日**: 2026-03-04
**参照**: `k_back/cloudbuild.yml` / `k_back/pytest.ini` / `k_back/.coveragerc` / `k_back/tests/conftest.py`
