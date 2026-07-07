# 認証系CSRF影響修正レビュー

作成日: 2026-07-06

対象タスク:

- `md_files_design_note/task/todo/fix/auth/csrf_auth_flow_fix_task_20260702.md`
- GitHub issue: https://github.com/nto300002/keikakun_app/issues/166

## レビュー結論

認証系CSRFの主要リスクである logout、login、MFA 成功後の CSRF token 初期化失敗については、TDD で期待挙動が固定されており、実装方針は妥当。

特に logout は 401 復旧経路でも呼ばれるため、`POST /api/v1/auth/logout` を CSRF exempt として扱う判断は適切。`handleLogout()` 側で CSRF token 取得に依存させると、期限切れ・不整合 Cookie の後始末が CSRF 取得失敗に巻き込まれるため、復旧導線として脆くなる。

login / MFA 成功後の `initializeCsrfToken()` は best-effort とし、失敗しても認証成功レスポンスを維持し、その後の状態変更 API で `http.ts` の遅延取得に任せる方針でよい。認証完了と CSRF token 事前取得を強く結合しないため、UI と cookie 認証状態の不整合を避けられる。

## 確認済み事項

- `/api/v1/auth/logout` は CSRF exempt として扱う方針。
- Cookie 認証状態で CSRF token なしの logout が 403 にならないことをテストで固定済み。
- frontend の `authApi.logout()` は `http.post()` 依存から外し、CSRF token 取得失敗時でも logout endpoint を呼べる方針。
- frontend の `authApi.verifyMfa()` は CSRF exempt endpoint として、検証前の CSRF token 取得に依存しない方針。
- login / MFA 成功後の CSRF 初期化失敗は warning 扱いで、認証成功レスポンスを返す方針。
- 直接 `fetch()` の状態変更追加は auth exempt 経路に限定する方針。

## テスト確認

タスク md に記録された確認結果:

```bash
docker exec keikakun_app-backend-1 pytest tests/api/v1/test_csrf_protection.py -q
# 10 passed, 7 warnings

node --experimental-strip-types --test lib/authFlow.test.mjs
# 3 passed

npm run lint
# 0 errors, 16 warnings

npx tsc --noEmit --pretty false
# exit 0
```

## 残タスク

以下は主要リスクの修正とは分け、別タスクまたは追加 PR で扱う。

- `k_back/app/api/v1/endpoints/admin_announcements.py`、`offices.py`、`messages.py` に残る個別 `Depends(validate_csrf)` の段階的整理。
- メッセージ既読/全既読、管理者通知作成の CSRF 付き成功テスト追加。
- 手動確認項目:
  - 確認済み: 通常ログインが成功する。
  - 確認済み: 通常ログアウト後、Cookie が削除されログイン画面へ遷移する。
  - 確認済み: 期限切れ Cookie がある状態でも正常にログアウトできる。
  - 確認済み: ログイン直後のメッセージ送信が成功する。
  - 確認済み: ログイン直後の PDF アップロードが成功する。
  - 401 発生後もログアウト後処理が詰まらない。
  - stale access Cookie が残っていてもログインできる。
  - MFA 必須アカウントで MFA 完了後に通常画面へ遷移できる。
  - ログイン直後に通知既読など他の状態変更 API が成功する。

## デプロイ判断

現時点の自動テスト範囲では、認証系CSRFの主要な 403 リスクは緩和されている。

通常ログイン、通常ログアウト、ログイン直後のメッセージ送信、PDF アップロードは手動確認済み。

ただし、一部の手動確認項目が未完了であるため、完全な業務導線保証としては staging で期限切れ Cookie、stale access Cookie、MFA、通知既読などの状態変更 API を確認してから本番反映するのが望ましい。

個別 `Depends(validate_csrf)` の削除は今回のデプロイ必須条件ではない。既存の二重検証を残すことで多少の重複はあるが、主要な auth flow 修正とは独立して扱える。

## 推奨

- このタスクの主目的である logout / login / MFA の CSRF 影響修正は完了扱いでよい。
- `messages`、`offices`、`admin_announcements` の個別 CSRF dependency 整理は、回帰テストを追加したうえで別 issue 化する。
- issue #166 を閉じる場合は、手動確認結果または staging 確認結果をコメントとして残す。
