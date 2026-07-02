# GitHub Actions デプロイエラー調査報告

## エラー概要

**発生日時**: 2025-11-24
**エラー箇所**: GitHub Actions - サブモジュールのチェックアウト処理
**影響範囲**: mainブランチへのpush時のCD (Continuous Deployment)

## エラーログ

```
Run actions/checkout@v4
Syncing repository: nto***0002/keikakun_app
Getting Git version info
Temporarily overriding HOME='/home/runner/work/_temp/f84b192d-b4fc-4e11-81f3-fc94ef9892***' before making global git config changes
Adding repository directory to the temporary git global config as a safe directory
/usr/bin/git config --global --add safe.directory /home/runner/work/keikakun_app/keikakun_app
Deleting the contents of '/home/runner/work/keikakun_app/keikakun_app'
Initializing the repository
Disabling automatic garbage collection
Setting up auth
Fetching the repository
Determining the checkout info
/usr/bin/git sparse-checkout disable
/usr/bin/git config --local --unset-all extensions.worktreeConfig
Checking out the ref
Setting up auth for fetching submodules
Fetching submodules
  /usr/bin/git submodule sync --recursive
  /usr/bin/git -c protocol.version=2 submodule update --init --force --depth=1 --recursive
  Submodule 'k_back' (https://github.com/nto***0002/keikakun_back) registered for path 'k_back'
  Submodule 'k_front' (https://github.com/nto***0002/keikakun_front) registered for path 'k_front'
  Cloning into '/home/runner/work/keikakun_app/keikakun_app/k_back'...
  Cloning into '/home/runner/work/keikakun_app/keikakun_app/k_front'...
  From https://github.com/nto***0002/keikakun_back
   * branch            11bbb07ddaf35efa6244423a800eb1099b2661a2 -> FETCH_HEAD
  Submodule path 'k_back': checked out '11bbb07ddaf35efa6244423a800eb1099b2661a2'
  Error: fatal: remote error: upload-pack: not our ref b5b2e7a77a586d65c27bb365df1f8d3e083b3f1b
  Error: fatal: Fetched in submodule path 'k_front', but it did not contain b5b2e7a77a586d65c27bb365df1f8d3e083b3f1b. Direct fetching of that commit failed.
  Error: The process '/usr/bin/git' failed with exit code 128
```

## 原因分析

### 根本原因

**サブモジュールのコミットがリモートリポジトリに存在しない**

親リポジトリ（keikakun_app）のmainブランチが、`k_front`サブモジュールの特定のコミット`b5b2e7a77a586d65c27bb365df1f8d3e083b3f1b`を参照しているが、このコミットがGitHub上の`keikakun_front`リポジトリに存在しない。

### 詳細調査結果

#### 親リポジトリの状態
```bash
$ git ls-tree HEAD | grep -E "k_front|k_back"
160000 commit 11bbb07ddaf35efa6244423a800eb1099b2661a2	k_back
160000 commit b5b2e7a77a586d65c27bb365df1f8d3e083b3f1b	k_front  # ← 問題のコミット
```

#### k_frontサブモジュールのローカル状態
```bash
$ cd k_front && git status
On branch issue/feature-メッセージ_おしらせ機能
nothing to commit, working tree clean

$ git log --oneline -1
b5b2e7a feat: Update notice page with tabs and unread badge integration  # ← ローカルには存在

$ git rev-parse --abbrev-ref --symbolic-full-name @{u}
fatal: no upstream configured for branch 'issue/feature-メッセージ_おしらせ機能'
# ← アップストリームブランチが設定されていない
```

#### リモートブランチの確認
```bash
$ git branch -r | grep "issue/feature-メッセージ"
# ← 結果なし（リモートにブランチが存在しない）
```

### 発生メカニズム

1. **ローカル開発**: `k_front`サブモジュールで`issue/feature-メッセージ_おしらせ機能`ブランチを作成し、コミット`b5b2e7a`を作成
2. **親リポジトリの更新**: 親リポジトリでサブモジュールの参照を`b5b2e7a`に更新してコミット
3. **不完全なpush**: 親リポジトリのみをpushし、**k_frontサブモジュール自体をpushし忘れた**
4. **GitHub Actionsでのエラー**: CI/CDがサブモジュールをクローンしようとするが、コミット`b5b2e7a`がリモートに存在しないため失敗

## 影響範囲

- ✅ **k_back**: 正常にチェックアウト可能（コミット`11bbb07`はリモートに存在）
- ❌ **k_front**: チェックアウト失敗（コミット`b5b2e7a`がリモートに存在しない）
- ❌ **デプロイ処理**: サブモジュールのチェックアウト失敗により、全体のデプロイが中断

## 解決方法

### 方法1: サブモジュールのブランチをpush（推奨）

```bash
# k_frontサブモジュールに移動
cd k_front

# ブランチをリモートにpush
git push -u origin issue/feature-メッセージ_おしらせ機能

# 親リポジトリに戻る
cd ..

# GitHub Actionsを再実行
```

### 方法2: mainブランチにマージしてからpush

```bash
# k_frontサブモジュールに移動
cd k_front

# mainブランチに切り替え
git checkout main

# 機能ブランチをマージ
git merge issue/feature-メッセージ_おしらせ機能

# mainをpush
git push origin main

# 親リポジトリに戻る
cd ..

# 親リポジトリでサブモジュール参照を更新
git add k_front
git commit -m "Update k_front submodule reference to main"
git push origin main
```

### 方法3: k_backも同様に対応

k_backサブモジュールも同じブランチ名で開発している場合、同様に対応が必要:

```bash
# k_backの状態確認
cd k_back
git branch -r | grep "issue/feature-メッセージ"
# ← リモートに存在しない場合はpushが必要

# ブランチをpush（必要に応じて）
git push -u origin issue/feature-メッセージ_おしらせ機能
cd ..
```

## 再発防止策

### 1. サブモジュール更新時のチェックリスト

親リポジトリをpushする前に以下を確認:

```bash
# 各サブモジュールの状態を確認
git submodule foreach 'git status && git rev-parse --abbrev-ref --symbolic-full-name @{u}'

# サブモジュールのコミットがリモートに存在するか確認
git submodule foreach 'git fetch && git branch -r --contains HEAD'
```

### 2. GitHub Actionsでの事前チェック追加（将来的な改善案）

```yaml
- name: Validate submodules before checkout
  run: |
    git submodule status
    # サブモジュールのコミットがリモートに存在するか検証
```

### 3. Pre-push hookの設定

`.git/hooks/pre-push`に以下を追加:

```bash
#!/bin/bash
# サブモジュールのコミットがリモートにpush済みか確認
git submodule foreach '
  upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)
  if [ -z "$upstream" ]; then
    echo "Warning: Submodule $name has no upstream branch set"
    exit 1
  fi
'
```

## まとめ

- **原因**: k_frontサブモジュールのコミットをpushせずに、親リポジトリのみをpush
- **解決**: k_frontのブランチ`issue/feature-メッセージ_おしらせ機能`をリモートにpush
- **予防**: サブモジュール更新時は、サブモジュール→親リポジトリの順でpush