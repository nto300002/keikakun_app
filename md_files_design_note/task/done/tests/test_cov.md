# テストカバレッジ計測

## 使用ライブラリ

| ライブラリ | バージョン | 用途 |
|-----------|-----------|------|
| `pytest-cov` | `>=4.1.0` | pytest実行時のカバレッジ計測 |
| `coverage.py` | (`pytest-cov` の依存) | カバレッジデータの収集・レポート生成 |

`k_back/requirements-dev.txt` に定義済み。

---

## 計測コマンド

### 全体カバレッジ（ターミナル出力）

```bash
docker exec keikakun_app-backend-1 pytest tests/ --cov=app --cov-report=term
```

### HTMLレポート付き（ブラウザ確認）

```bash
docker exec keikakun_app-backend-1 pytest tests/ --cov=app --cov-report=html --cov-report=term
```

生成先: `/app/htmlcov/index.html`（コンテナ内）

### ローカルでHTMLレポートを開く

```bash
docker cp keikakun_app-backend-1:/app/htmlcov ./htmlcov
open htmlcov/index.html
```

### 特定モジュールのみ計測

```bash
docker exec keikakun_app-backend-1 pytest tests/crud/test_crud_dashboard*.py \
  --cov=app.crud.crud_dashboard \
  --cov=app.api.v1.endpoints.dashboard \
  --cov-report=html --cov-report=term
```

### カバレッジ閾値チェック（CI向け）

```bash
# 80%未満の場合にテスト失敗
docker exec keikakun_app-backend-1 pytest tests/ --cov=app --cov-fail-under=80
```

### 並列実行 + カバレッジ

```bash
docker exec keikakun_app-backend-1 pytest tests/ -n auto --cov=app --cov-report=term
```

---

## カバレッジ目標

- **目標値**: 80%以上
- `pytest.ini` の `# カバレッジ目標: 80%以上` に記載

---

## 設定ファイル

`k_back/pytest.ini` にカバレッジ関連のコメントが記載されている。
`addopts` にはデフォルトでカバレッジオプションを含めず、必要時に手動で指定する運用。
