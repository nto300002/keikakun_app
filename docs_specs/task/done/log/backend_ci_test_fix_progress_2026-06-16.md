# Backend CI test fix progress

作成日: 2026-06-16

## 現在の状態

現在は、backend CI 不具合修正をリモートへ push 済みで、GitHub Actions の CI テスト結果待ち。

push 済み commit:

- `k_back`: `2009303 test: stabilize billing cleanup checks`
- parent repo: `9a74433 chore: update backend ci test fixes`

## これまでの軌跡

1. GitHub Actions の backend CI で以下の失敗を確認した。
   - `tests/tasks/test_billing_check.py::TestTrialExpirationCheck::*` の更新件数 assertion 失敗
   - `tests/utils/test_safe_cleanup_with_flag.py::TestSafeTestDataCleanupWithFlag::test_delete_only_test_data` の deadlock

2. 失敗ログと実装を照合した。
   - `check_trial_expiration()` は DB 全体の期限切れ Billing を対象に更新する。
   - CI は `pytest -n auto` で同一 test DB を複数 worker が共有している。
   - billing テストは `expired_count == 0/1/2` のように件数を厳密比較していたため、他 worker や残存データが混ざると失敗する。
   - `SafeTestDataCleanup.delete_test_data()` は `DELETE FROM staffs WHERE is_test_data = true` を含む全体 cleanup を行うため、並列 worker の staff/office 操作と deadlock する可能性がある。

3. 調査内容を以下へ記録した。
   - `md_files_design_note/task/done/log/backend_ci_billing_cleanup_failure_2026-06-15.md`

4. backend の実行環境を確認した。
   - backend はホスト側 Python ではなく Docker コンテナ `keikakun_app-backend-1` 上で実行する運用。
   - この前提をローカルの `.codex/skills/SKILLS.md` に記録した。
   - `.codex/` は `.gitignore` 対象のため、リモートへ push しない方針も同ファイルに記録した。

5. 実装修正を行った。
   - `k_back/tests/tasks/test_billing_check.py`
     - 更新件数の厳密一致をやめ、作成した Billing 自体の状態遷移を主検証に変更。
     - 更新対象ありのケースは `assert_updated_at_least()` で「少なくとも自分が作成した件数以上」を確認する形に変更。
   - `k_back/tests/utils/safe_cleanup.py`
     - `SafeTestDataCleanup.delete_test_data()`
     - `SafeTestDataCleanup.delete_factory_generated_data()`
     - 上記 cleanup 処理の先頭に PostgreSQL advisory lock を追加し、cleanup 同士を直列化。

6. ローカルコンテナ上で検証した。
   - 構文チェック:
     - `docker exec keikakun_app-backend-1 python -m py_compile tests/tasks/test_billing_check.py tests/utils/safe_cleanup.py`
     - pass
   - 直列対象テスト:
     - `docker exec keikakun_app-backend-1 pytest tests/tasks/test_billing_check.py tests/utils/test_safe_cleanup_with_flag.py -m "not performance" --tb=short`
     - `22 passed, 15 warnings`
   - CI 相当の並列対象テスト:
     - `docker exec keikakun_app-backend-1 pytest -n auto tests/tasks/test_billing_check.py tests/utils/test_safe_cleanup_with_flag.py -m "not performance" --tb=short`
     - `22 passed, 165 warnings`

7. 変更を push した。
   - `k_back/main` に `2009303` を push。
   - parent repo `main` に `k_back` submodule 参照更新と調査ログ md を含む `9a74433` を push。

## 残作業

- GitHub Actions の backend CI 結果を確認する。
- CI が通れば、この backend CI テスト修正タスクは完了。
- CI が失敗した場合は、リモートログを再確認し、ローカルで再現範囲を絞って追加修正する。

## 注意事項

- parent repo には今回の作業対象外の未コミット差分が残っている。
  - `.gitignore`
  - `md_files_design_note/app_kinou /Backend/data_design.md`
  - `md_files_design_note/task/done/log/e2e_ci_fix_vercel_preview.md`
  - `md_files_design_note/task/fix_ui/user-centered_design_pr_summary.md`
- `k_back` 内にも今回の commit 対象外の未追跡ファイルが残っている。
  - `.coverage`
  - `tests/performance/snapshots/test_list_1.json`
