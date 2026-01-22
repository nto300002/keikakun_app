# GitHub Actions テスト失敗の修正 - サブモジュール同期問題

**作成日**: 2026-01-22
**ステータス**: ✅ 修正完了

## 問題の概要

GitHub Actionsでテストが失敗し続けていたが、ローカルでは全テストがパスしていた。

### エラーパターン
```
FAILED tests/tasks/test_deadline_notification.py::test_send_deadline_alert_emails_dry_run - assert 7 == 1
FAILED tests/tasks/test_deadline_notification.py::test_send_deadline_alert_emails_no_alerts - assert 6 == 0
...（全13テスト失敗）
```

## 根本原因

**k_backサブモジュールの同期問題**

1. **修正コミットの場所**
   - コミット `c7833ca` (本番環境テストデータ除外機能)
   - `feature/issue-email_notification-system_notification` ブランチにのみ存在
   - k_back の `main` ブランチにマージされていなかった

2. **サブモジュール参照の不一致**
   - mainリポジトリ(keikakun_app)は k_back の古いコミットを参照
   - GitHub Actionsは mainリポジトリが参照するコミットをチェックアウト
   - 修正が含まれていないコードでテストが実行されていた

3. **ローカル環境との違い**
   - ローカルでは feature ブランチで開発・テスト実行
   - GitHub Actions は main ブランチから submodule をチェックアウト
   - → 環境の違いによりテスト結果が異なっていた

## 修正手順

### 1. k_back feature ブランチを main にマージ

```bash
cd k_back
git checkout main
git pull origin main
git merge feature/issue-email_notification-system_notification --no-ff \
  -m "Merge feature/issue-email_notification-system_notification - 本番環境でテストデータを除外する機能を追加"
git push origin main
```

**マージ結果**:
- コミット: `ac3c736`
- 変更ファイル:
  - `app/services/welfare_recipient_service.py` (34行追加/10行削除)
  - `app/tasks/deadline_notification.py` (26行追加/6行削除)

### 2. mainリポジトリのサブモジュール参照を更新

```bash
cd /Users/naotoyasuda/workspase/keikakun_app
git submodule update --remote k_back
git add k_back
git commit -m "chore: k_backサブモジュール更新 - 本番環境テストデータ除外機能追加"
git push origin main
```

**更新内容**:
- k_back 参照: `c7833ca` → `ac3c736`
- コミット: `f5dce41`

## 修正内容の確認

### 環境別フィルタリングの実装

**app/services/welfare_recipient_service.py:687**
```python
is_testing = os.getenv("TESTING") == "1"

# 更新期限アラート
renewal_conditions = [
    SupportPlanCycle.office_id == office_id,
    SupportPlanCycle.is_latest_cycle == True,
    SupportPlanCycle.next_renewal_deadline.isnot(None),
    SupportPlanCycle.next_renewal_deadline <= threshold_date
]
if not is_testing:
    renewal_conditions.append(WelfareRecipient.is_test_data == False)

# アセスメント未完了アラート
assessment_conditions = [
    SupportPlanCycle.office_id == office_id,
    SupportPlanCycle.is_latest_cycle == True
]
if not is_testing:
    assessment_conditions.append(WelfareRecipient.is_test_data == False)
```

**app/tasks/deadline_notification.py:118**
```python
is_testing = os.getenv("TESTING") == "1"

# Office取得
office_conditions = [Office.deleted_at.is_(None)]
if not is_testing:
    office_conditions.append(Office.is_test_data == False)

# Staff取得
staff_conditions = [
    OfficeStaff.office_id == office.id,
    Staff.deleted_at.is_(None),
    Staff.email.isnot(None)
]
if not is_testing:
    staff_conditions.append(Staff.is_test_data == False)
```

## テスト結果

### ローカルテスト (k_back main ブランチ)
```bash
$ docker exec keikakun_app-backend-1 pytest tests/tasks/test_deadline_notification.py tests/tasks/test_deadline_notification_web_push.py -v

================= 13 passed, 15 warnings in 118.17s (0:01:58) ==================
```

**全テストPASS ✅**

### GitHub Actions
次回のpush時にGitHub Actionsで自動テスト実行される。
修正後のコードが含まれているため、テストがパスする見込み。

## 環境別動作

| 環境 | TESTING | is_test_dataフィルタ | 使用DB | テストデータ |
|------|---------|---------------------|--------|------------|
| 本番 | 未設定 | 有効 (False のみ) | DATABASE_URL | 除外 |
| テスト (ローカル) | "1" | 無効 (全て含む) | TEST_DATABASE_URL | 含む |
| GitHub Actions | "1" | 無効 (全て含む) | TEST_DATABASE_URL | 含む |

## 学んだこと

### 1. サブモジュールの同期管理
- サブモジュールのブランチ管理に注意
- 親リポジトリの参照を更新する必要がある
- `git submodule update --remote` で最新を取得

### 2. CI/CD環境とローカル環境の違い
- ローカル: 開発ブランチで作業
- CI/CD: mainブランチのサブモジュール参照をチェックアウト
- 環境の違いによるテスト結果の差異に注意

### 3. デバッグアプローチ
1. ローカルとCI/CDの環境差異を確認
2. サブモジュールのコミット参照を確認 (`git ls-tree HEAD k_back`)
3. ブランチ間のコミット差分を確認 (`git log main..feature`)

### 4. GitHub Actions のサブモジュールチェックアウト
```yaml
- name: Checkout repository and submodules
  uses: actions/checkout@v4
  with:
    submodules: 'recursive'
```
このステップは親リポジトリが参照している特定のコミットをチェックアウトする。
サブモジュールのmainブランチとは限らない。

## 関連ドキュメント

- @md_files_design_note/1Lerror.md - 本番環境エラーの根本原因分析
- @md_files_design_note/testing_environment_variable_design.md - TESTING=1とDATABASE_URLの設計
- @.github/workflows/cd-backend.yml - GitHub Actions設定

## コミット履歴

### k_back リポジトリ
```
ac3c736 Merge feature/issue-email_notification-system_notification - 本番環境でテストデータを除外する機能を追加
c7833ca fix: 本番環境でテストデータを除外し、テスト環境では含める
```

### keikakun_app (main) リポジトリ
```
f5dce41 chore: k_backサブモジュール更新 - 本番環境テストデータ除外機能追加
```

**最終更新**: 2026-01-22
**修正完了**: ✅
**次のアクション**: GitHub Actionsの実行結果を確認
