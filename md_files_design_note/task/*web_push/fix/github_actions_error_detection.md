# GitHub Actions エラー検出ガイド

**作成日**: 2026-01-23
**対象**: 期限通知テスト（test_deadline_notification.py, test_deadline_notification_web_push.py）

## 概要

GitHub Actionsでのテスト実行時に発生するエラーを確実に検出するためのログパターンとキーワード集。

---

## 🔴 1. テスト失敗の検出

### A. アサーションエラー（最も一般的）

**ログ例**:
```
FAILED tests/tasks/test_deadline_notification.py::test_send_deadline_alert_emails_no_alerts
tests/tasks/test_deadline_notification.py:62: in test_send_deadline_alert_emails_no_alerts
    assert result["email_sent"] == 0
E   assert 6 == 0
```

**検出キーワード**:
- ✅ `FAILED`（pytestの失敗マーカー）
- ✅ `E   assert X == Y`（期待値と実際の値の不一致）
- ✅ `AssertionError`

**grep パターン**:
```bash
grep "FAILED"
grep "E   assert.*=="
grep "AssertionError"
```

---

### B. テスト結果サマリー

**ログ例（成功）**:
```
===== 13 passed, 15 warnings in 96.50s =====
```

**ログ例（失敗）**:
```
===== 5 failed, 8 passed, 15 warnings in 96.50s =====
```

**検出キーワード**:
- ✅ `X failed` (Xは1以上)
- ✅ `failed` という文字列の存在
- ❌ `0 failed` または `failed`が含まれない → 成功

**grep パターン**:
```bash
# 失敗件数を抽出
grep -oP "\d+ failed"

# 失敗があるか確認
if grep -q "[1-9][0-9]* failed"; then
    echo "テスト失敗"
fi
```

---

### C. pytest終了コード

**ログ例**:
```
Error: Process completed with exit code 1.
```

**検出キーワード**:
- ✅ `exit code 1`
- ✅ `Error: Process completed`

**grep パターン**:
```bash
grep "exit code 1"
grep "Error: Process completed"
```

---

## 🔴 2. クリーンアップエラー

### A. 環境チェック失敗

**ログ例**:
```
⚠️  Not in test environment - skipping cleanup
```

**検出キーワード**:
- ✅ `⚠️  Not in test environment`
- ✅ `skipping cleanup`

**意味**: TEST_DATABASE_URLが設定されていない、または本番環境キーワードが検出された

---

### B. クリーンアップ処理失敗

**ログ例**:
```
❌ Safe cleanup failed: [error details]
⚠️  Pre-test safe cleanup failed: [error details]
⚠️  Post-test safe cleanup failed: [error details]
```

**検出キーワード**:
- ✅ `❌ Safe cleanup failed`
- ✅ `⚠️  Pre-test safe cleanup failed`
- ✅ `⚠️  Post-test safe cleanup failed`

**grep パターン**:
```bash
grep "cleanup failed"
grep "❌ Safe cleanup"
grep "⚠️.*cleanup failed"
```

---

## 🔴 3. データベース接続エラー

### A. 環境変数未設定

**ログ例**:
```
ValueError: Neither TEST_DATABASE_URL nor DATABASE_URL environment variable is set for tests
```

**検出キーワード**:
- ✅ `Neither TEST_DATABASE_URL nor DATABASE_URL`
- ✅ `ValueError`

**原因**: GitHub Actions設定で環境変数が設定されていない

---

### B. データベース接続警告

**ログ例**:
```
🔍 DATABASE CONNECTION INFO (cleanup_database_session)
================================================================================
  TEST_DATABASE_URL set: No
  DATABASE_URL set: Yes
  Using: DATABASE_URL (FALLBACK)
  ⚠️  WARNING: TEST_DATABASE_URL not set, falling back to DATABASE_URL!
================================================================================
```

**検出キーワード**:
- ✅ `⚠️  WARNING: TEST_DATABASE_URL not set`
- ✅ `falling back to DATABASE_URL`
- ✅ `Using: DATABASE_URL (FALLBACK)`

**原因**: TEST_DATABASE_URLが未設定で、DATABASE_URLにフォールバック

---

### C. SQLAlchemyエラー

**ログ例**:
```
sqlalchemy.exc.OperationalError: (psycopg.OperationalError) connection failed
FATAL:  password authentication failed for user "postgres"
```

**検出キーワード**:
- ✅ `sqlalchemy.exc.OperationalError`
- ✅ `connection failed`
- ✅ `psycopg.OperationalError`
- ✅ `password authentication failed`

**grep パターン**:
```bash
grep "sqlalchemy.exc"
grep "OperationalError"
grep "connection failed"
```

---

## 🔴 4. テストデータ残留（期待値+6のエラー）

### 典型的なパターン

**ログ例**:
```
tests/tasks/test_deadline_notification.py:62: in test_send_deadline_alert_emails_no_alerts
    assert result["email_sent"] == 0
E   assert 6 == 0

tests/tasks/test_deadline_notification.py:127: in test_send_deadline_alert_emails_with_threshold_filtering
    assert result["email_sent"] == 1
E   assert 7 == 1
```

**検出ロジック**:
```python
# 期待値より6多い場合は古いデータ残留の可能性
if actual_value == expected_value + 6:
    print("⚠️ 警告: テストデータが残留している可能性があります")
```

**検出キーワード**:
- ✅ `assert X == Y` で `X = Y + 6` のパターン
- ✅ 連続する複数のテストで同じ差分（+6）が発生

**grep パターン**:
```bash
# 期待値+6のパターンを検出
grep "assert 6 == 0"
grep "assert 7 == 1"
grep "assert 8 == 2"
```

---

## 🟢 5. 成功時のログパターン

### A. クリーンアップ成功

**ログ例（データなし）**:
```
============================================================
🧪 Starting test session - safe cleanup...
============================================================
  ✓ No factory-generated data found
✅ Pre-test cleanup completed
============================================================
```

**ログ例（データあり）**:
```
============================================================
🧪 Starting test session - safe cleanup...
============================================================
  🧹 Deleted 12 factory-generated records:
    - offices: 2
    - staffs: 3
    - welfare_recipients: 4
    - support_plan_cycles: 3
✅ Pre-test cleanup completed
============================================================
```

**検出キーワード**:
- ✅ `✅ Pre-test cleanup completed`
- ✅ `✅ Post-test cleanup completed`
- ✅ `✓ No factory-generated data found`
- ✅ `🧹 Deleted X factory-generated records`

---

### B. テスト成功

**ログ例**:
```
===== 13 passed, 15 warnings in 96.50s =====
```

**検出キーワード**:
- ✅ `X passed` (失敗がない)
- ❌ `failed`という文字列が**含まれない**

**grep パターン**:
```bash
# 成功判定
if grep -q "passed" && ! grep -q "failed"; then
    echo "✅ 全テスト成功"
fi
```

---

### C. データベース接続成功

**ログ例**:
```
🔍 DATABASE CONNECTION INFO (cleanup_database_session)
================================================================================
  TEST_DATABASE_URL set: Yes
  DATABASE_URL set: Yes
  Using: TEST_DATABASE_URL
  Database branch: dev_test
  Connection string: postgresql+psycopg://keikakun_dev_test:npg_...
================================================================================
```

**検出キーワード**:
- ✅ `TEST_DATABASE_URL set: Yes`
- ✅ `Using: TEST_DATABASE_URL`
- ✅ `Database branch: dev_test` または `prod_test`

**grep パターン**:
```bash
grep "TEST_DATABASE_URL set: Yes"
grep "Using: TEST_DATABASE_URL"
```

---

## 🔍 統合エラー検出スクリプト

### Bash版

```bash
#!/bin/bash
# GitHub Actionsログから重要なエラーを検出

LOG_FILE="$1"

if [ -z "$LOG_FILE" ]; then
    echo "Usage: $0 <log_file>"
    exit 1
fi

echo "=== GitHub Actions Log Analysis ==="
echo "Log file: $LOG_FILE"
echo ""

# 1. テスト失敗
FAILED_COUNT=$(grep -c "FAILED" "$LOG_FILE" 2>/dev/null || echo "0")
if [ "$FAILED_COUNT" -gt 0 ]; then
    echo "❌ テスト失敗: ${FAILED_COUNT}件"
    grep "FAILED" "$LOG_FILE"
    echo ""
fi

# 2. クリーンアップエラー
if grep -q "cleanup failed" "$LOG_FILE" 2>/dev/null; then
    echo "⚠️  クリーンアップエラー検出"
    grep "cleanup failed" "$LOG_FILE"
    echo ""
fi

# 3. データベース接続エラー
if grep -q "OperationalError\|connection failed\|TEST_DATABASE_URL not set" "$LOG_FILE" 2>/dev/null; then
    echo "⚠️  データベース接続エラー"
    grep -E "OperationalError|connection failed|TEST_DATABASE_URL not set" "$LOG_FILE"
    echo ""
fi

# 4. テストデータ残留（+6パターン）
if grep -E "assert [67] == [01]|assert [89] == [23]" "$LOG_FILE" 2>/dev/null; then
    echo "⚠️  テストデータ残留の可能性（+6エラー）"
    grep -E "assert [67] == [01]|assert [89] == [23]" "$LOG_FILE"
    echo ""
fi

# 5. クリーンアップログ確認
if grep -q "🧪 Starting test session" "$LOG_FILE" 2>/dev/null; then
    echo "✅ クリーンアップログあり"
else
    echo "⚠️  クリーンアップログなし（-sフラグが不足している可能性）"
fi

# 6. 成功判定
if grep -q "✅ Pre-test cleanup completed" "$LOG_FILE" 2>/dev/null && \
   grep -q "passed" "$LOG_FILE" 2>/dev/null && \
   ! grep -q "[1-9][0-9]* failed" "$LOG_FILE" 2>/dev/null; then
    echo ""
    echo "✅ 全テスト成功"
else
    echo ""
    echo "❌ テストまたはセットアップに問題あり"
fi
```

**使用方法**:
```bash
./check_github_actions_log.sh github_actions_log.txt
```

---

### Python版

```python
#!/usr/bin/env python3
"""GitHub Actionsログ解析スクリプト"""

import re
import sys
from typing import Dict, List

def analyze_log(log_file: str) -> Dict[str, any]:
    """ログファイルを解析してエラーパターンを検出"""

    with open(log_file, 'r', encoding='utf-8') as f:
        log_content = f.read()

    results = {
        'test_failures': [],
        'cleanup_errors': [],
        'db_errors': [],
        'data_residue': [],
        'has_cleanup_logs': False,
        'success': False
    }

    # 1. テスト失敗
    failed_tests = re.findall(r'FAILED (tests/.*)', log_content)
    results['test_failures'] = failed_tests

    # 2. クリーンアップエラー
    cleanup_errors = re.findall(r'(.*cleanup failed.*)', log_content)
    results['cleanup_errors'] = cleanup_errors

    # 3. データベースエラー
    db_errors = re.findall(r'(OperationalError|connection failed|TEST_DATABASE_URL not set)', log_content)
    results['db_errors'] = db_errors

    # 4. テストデータ残留（+6パターン）
    data_residue = re.findall(r'assert ([67]) == ([01])|assert ([89]) == ([23])', log_content)
    results['data_residue'] = data_residue

    # 5. クリーンアップログ確認
    results['has_cleanup_logs'] = '🧪 Starting test session' in log_content

    # 6. 成功判定
    has_passed = 'passed' in log_content
    has_cleanup_success = '✅ Pre-test cleanup completed' in log_content
    no_failures = not re.search(r'[1-9][0-9]* failed', log_content)

    results['success'] = has_passed and has_cleanup_success and no_failures

    return results

def print_results(results: Dict[str, any]):
    """解析結果を表示"""

    print("=== GitHub Actions Log Analysis ===\n")

    # テスト失敗
    if results['test_failures']:
        print(f"❌ テスト失敗: {len(results['test_failures'])}件")
        for test in results['test_failures']:
            print(f"  - {test}")
        print()

    # クリーンアップエラー
    if results['cleanup_errors']:
        print("⚠️  クリーンアップエラー検出")
        for error in results['cleanup_errors']:
            print(f"  {error}")
        print()

    # データベースエラー
    if results['db_errors']:
        print("⚠️  データベース接続エラー")
        for error in results['db_errors']:
            print(f"  {error}")
        print()

    # テストデータ残留
    if results['data_residue']:
        print("⚠️  テストデータ残留の可能性（+6エラー）")
        print(f"  検出件数: {len(results['data_residue'])}")
        print()

    # クリーンアップログ
    if results['has_cleanup_logs']:
        print("✅ クリーンアップログあり")
    else:
        print("⚠️  クリーンアップログなし（-sフラグが不足している可能性）")

    print()

    # 総合判定
    if results['success']:
        print("✅ 全テスト成功")
        return 0
    else:
        print("❌ テストまたはセットアップに問題あり")
        return 1

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 analyze_log.py <log_file>")
        sys.exit(1)

    log_file = sys.argv[1]
    results = analyze_log(log_file)
    exit_code = print_results(results)
    sys.exit(exit_code)
```

**使用方法**:
```bash
python3 analyze_log.py github_actions_log.txt
```

---

## 📊 重要度マトリックス

| エラーパターン | 重要度 | 影響範囲 | 対処優先度 |
|---------------|--------|----------|-----------|
| テスト失敗（FAILED） | 🔴 高 | 全体 | 最優先 |
| exit code 1 | 🔴 高 | 全体 | 最優先 |
| データベース接続エラー | 🔴 高 | 全体 | 最優先 |
| テストデータ残留（+6） | 🟡 中 | テスト結果 | 高 |
| クリーンアップエラー | 🟡 中 | データ整合性 | 中 |
| クリーンアップログなし | 🟢 低 | 可視性 | 低 |

---

## 🛠️ トラブルシューティング

### エラーパターン別の対処法

#### 1. テスト失敗（+6エラー）
**症状**: `assert 6 == 0`, `assert 7 == 1`

**原因**:
- テストデータベースに古いデータが残留
- クリーンアップ処理が実行されていない

**対処法**:
1. pytest.iniに`-s`フラグを追加
2. conftest.pyのクリーンアップ処理を確認
3. TEST_DATABASE_URLが正しく設定されているか確認

---

#### 2. クリーンアップログが表示されない
**症状**: `🧪 Starting test session` が見つからない

**原因**:
- pytest.iniに`-s`フラグがない
- `print()`の出力がキャプチャされている

**対処法**:
```ini
# pytest.ini
addopts = -v --tb=short -s
```

---

#### 3. データベース接続エラー
**症状**: `OperationalError`, `connection failed`

**原因**:
- TEST_DATABASE_URLが未設定
- データベース認証情報が誤っている

**対処法**:
1. GitHub Secretsを確認
2. .github/workflows/cd-backend.yml の環境変数設定を確認

```yaml
env:
  TESTING: "1"
  TEST_DATABASE_URL: ${{ secrets.TEST_DATABASE_URL }}
  DATABASE_URL: ${{ secrets.TEST_DATABASE_URL }}
```

---

## 📝 チェックリスト

GitHub Actionsでテストが失敗した場合、以下を順番に確認：

- [ ] ログに`FAILED`が含まれているか
- [ ] `exit code 1`が表示されているか
- [ ] クリーンアップログ（`🧪 Starting test session`）が表示されているか
- [ ] `TEST_DATABASE_URL set: Yes`が表示されているか
- [ ] アサーションエラーで+6のパターンがあるか
- [ ] クリーンアップエラー（`cleanup failed`）があるか
- [ ] データベース接続エラーがあるか

---

## 🔗 関連ドキュメント

- [1Lerror.md](../../1Lerror.md) - 本番環境エラー修正履歴
- [pytest.ini](../../../k_back/pytest.ini) - pytest設定ファイル
- [conftest.py](../../../k_back/tests/conftest.py) - テストフィクスチャとクリーンアップ処理
- [safe_cleanup.py](../../../k_back/tests/utils/safe_cleanup.py) - 安全なデータクリーンアップ実装

---

**最終更新**: 2026-01-23
**作成者**: Claude Sonnet 4.5
