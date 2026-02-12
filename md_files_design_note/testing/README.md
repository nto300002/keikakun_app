# Testing Documentation - テストドキュメント

**最終更新**: 2026-02-12

このディレクトリには、Keikakun API バックエンドのテストに関するドキュメントが含まれています。

---

## 📚 ドキュメント一覧

### 1. [Parallel Testing Guide](./parallel_testing_guide.md) - テスト並列実行ガイド

**対象**: pytest-xdist を使用したテスト並列実行の完全ガイド

**内容**:
- pytest-xdist の概要と導入手順
- 基本的な使い方（`pytest -n auto`）
- CI/CD パイプラインでの使用例
- トラブルシューティング

**こんな人におすすめ**:
- テスト実行時間を短縮したい
- CI/CD パイプラインを高速化したい
- pytest-xdist を初めて使う

---

### 2. [Parallel Testing Optimization](./parallel_testing_optimization.md) - 並列テスト最適化

**対象**: pytest-xdist のパフォーマンス最適化と詳細設定

**内容**:
- データベース接続プールの最適化
- 並列数の最適な決定方法
- テストの独立性保証
- パフォーマンス測定ツール

**こんな人におすすめ**:
- 並列実行のパフォーマンスを最大化したい
- データベース接続エラーが発生している
- 詳細な設定方法を知りたい

---

## 🚀 クイックスタート

### 1. pytest-xdist のインストール

#### Docker コンテナで再ビルド

```bash
cd /Users/naotoyasuda/workspase/keikakun_app
docker-compose build backend
docker-compose up -d backend
```

#### または、既存のコンテナ内でインストール

```bash
docker exec keikakun_app-backend-1 pip install pytest-xdist>=3.5.0
```

### 2. 並列実行を試す

#### Auto モード（推奨）

```bash
# CPUコア数に応じて自動調整
docker exec keikakun_app-backend-1 pytest tests/ -n auto
```

#### パフォーマンステスト・Integrationテストを除外

```bash
# 高速なユニットテストのみ並列実行
docker exec keikakun_app-backend-1 pytest tests/ -n auto -m "not performance and not integration"
```

#### 固定ワーカー数

```bash
# 8並列で実行
docker exec keikakun_app-backend-1 pytest tests/ -n 8
```

### 3. ベンチマーク測定

```bash
# ベンチマークスクリプトを実行可能にする
chmod +x k_back/benchmark_parallel_tests.sh

# ベンチマーク実行
./k_back/benchmark_parallel_tests.sh
```

**結果は** `k_back/benchmark_results/` に保存されます。

---

## 📊 期待される効果

| テスト数 | シリアル実行 | 並列実行（8ワーカー） | スピードアップ |
|---------|------------|---------------------|---------------|
| 100件   | 120秒      | 20秒                | **6倍**       |
| 500件   | 600秒      | 90秒                | **6.7倍**     |
| 1000件  | 1200秒     | 180秒               | **6.7倍**     |

---

## 🛠️ トラブルシューティング

### 1. データベース接続エラー

**症状**:
```
sqlalchemy.exc.TimeoutError: QueuePool limit of size 10 overflow 20 reached
```

**解決策**:
- 並列数を減らす: `pytest -n 8` → `pytest -n 4`
- 接続プールサイズを増やす: [Optimization Guide](./parallel_testing_optimization.md#データベース接続プール最適化) 参照

### 2. テストが並列実行で失敗する

**症状**: シリアル実行では成功するが、並列実行で失敗する

**解決策**:
- テストの独立性を確認: [Optimization Guide](./parallel_testing_optimization.md#テストの独立性保証) 参照
- ランダム実行でテスト: `pytest tests/ --random-order`

### 3. パフォーマンステストが遅い

**症状**: 並列実行時にパフォーマンステストが全体を遅延させる

**解決策**:
```bash
# パフォーマンステストを除外
pytest tests/ -n auto -m "not performance"
```

---

## 📝 推奨コマンド集

```bash
# ローカル開発（並列実行、高速フィードバック）
docker exec keikakun_app-backend-1 pytest tests/ -n auto -m "not performance and not integration"

# デバッグ時（シリアル実行、詳細出力）
docker exec keikakun_app-backend-1 pytest tests/api/test_billing.py -v -s

# CI/CD（GitHub Actions）
pytest tests/ -n 4 -m "not integration and not performance"

# 完全なテストスイート（時間がかかる）
pytest tests/ -n auto

# テスト実行時間のトップ10を表示
pytest tests/ -n auto --durations=10

# ベンチマーク測定
./k_back/benchmark_parallel_tests.sh
```

---

## 🔗 関連リソース

### 公式ドキュメント

- [pytest-xdist Documentation](https://pytest-xdist.readthedocs.io/)
- [pytest Documentation](https://docs.pytest.org/)
- [SQLAlchemy Async Documentation](https://docs.sqlalchemy.org/en/20/orm/extensions/asyncio.html)

### プロジェクト内ドキュメント

- [Architecture Guide](../.claude/CLAUDE.md)
- [SQLAlchemy Best Practices](../.claude/rules/sqlalchemy-best-practices.md)
- [Testing Standards](../.claude/rules/testing.md)

---

## 📂 ディレクトリ構成

```
md_files_design_note/testing/
├── README.md                           # このファイル
├── parallel_testing_guide.md           # 並列実行ガイド（入門編）
└── parallel_testing_optimization.md    # 並列実行最適化（詳細編）

k_back/
├── pytest.ini                          # pytest設定（並列実行コメント追加済み）
├── requirements-dev.txt                # pytest-xdist追加済み
├── conftest.py                         # テストフィクスチャ（並列実行対応済み）
├── conftest_optimized_example.py       # 最適化版サンプルコード
└── benchmark_parallel_tests.sh         # ベンチマークスクリプト
```

---

## ✅ 導入チェックリスト

- [x] pytest-xdist を requirements-dev.txt に追加
- [x] pytest.ini に並列実行の使い方コメント追加
- [x] ベンチマークスクリプト作成
- [x] ドキュメント作成
- [ ] pytest-xdist のインストール（Docker ビルド）
- [ ] 並列実行テスト（`pytest -n auto`）
- [ ] ベンチマーク測定
- [ ] CI/CD パイプラインへの統合

---

## 📞 サポート

質問や問題があれば、以下を参照してください:

1. [Parallel Testing Guide](./parallel_testing_guide.md) - 基本的な使い方
2. [Parallel Testing Optimization](./parallel_testing_optimization.md) - 詳細設定
3. [GitHub Issues](https://github.com/anthropics/claude-code/issues) - バグ報告

---

**Last Updated**: 2026-02-12
**Maintained by**: Claude Sonnet 4.5
