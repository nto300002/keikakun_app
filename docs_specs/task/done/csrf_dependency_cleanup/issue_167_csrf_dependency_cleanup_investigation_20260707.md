# Issue #167 CSRF個別dependency整理 調査記録

作成日: 2026-07-07

対象 issue:

- https://github.com/nto300002/keikakun_app/issues/167

関連資料:

- `md_files_design_note/task/todo/fix/auth/csrf_auth_flow_fix_task_20260702.md`
- `md_files_design_note/task/todo/fix/auth/csrf_auth_flow_fix_review_20260706.md`

## Issue 内容の確認

Issue #167 は閲覧可能。状態は OPEN。

タイトル:

- `CSRF個別dependency整理と残手動確認`

背景:

- `fix/csrf-auth-flow-20260702` で logout / login / MFA の主要な CSRF 影響修正は完了済み。
- 残っている `Depends(validate_csrf)` の整理と、未完了の手動確認を auth flow 本体とは独立した追加改善として扱う。

## 現状のCSRF構成

### グローバルmiddleware

`k_back/app/main.py` に `csrf_cookie_auth_middleware` が存在する。

方針:

- `POST` / `PUT` / `PATCH` / `DELETE`
- `CSRF_EXEMPT_PATHS` 以外
- `access_token` cookie がある
- `Authorization: Bearer ...` ではない

この条件に該当するリクエストでは `CsrfProtect().validate_csrf(request)` が実行され、失敗時は `403` と `{"detail": "CSRF token validation failed"}` を返す。

つまり、Cookie 認証の状態変更 API は原則として global middleware だけで CSRF 保護される設計になっている。

### CSRF exempt

`CSRF_EXEMPT_PATHS` には以下の auth / webhook 系が含まれている。

- `/api/v1/csrf-token`
- `/api/v1/auth/token`
- `/api/v1/auth/token/verify-mfa`
- `/api/v1/auth/mfa/first-time-verify`
- `/api/v1/auth/logout`
- `/api/v1/auth/refresh-token`
- `/api/v1/billing/webhook`

Issue #167 の対象 API は exempt ではないため、global middleware の対象になる。

## 個別 `Depends(validate_csrf)` が残る対象

調査時点で issue #167 の対象として確認した個別 dependency は以下。

### `k_back/app/api/v1/endpoints/messages.py`

残存箇所:

- `POST /api/v1/messages/personal`
- `POST /api/v1/messages/announcement`
- `POST /api/v1/messages/{message_id}/read`
- `POST /api/v1/messages/mark-all-read`

影響:

- global middleware と endpoint dependency の二重検証になっている。
- CSRF token が正しければ成功するが、二重検証のため将来の token 取得・cookie 名・例外処理変更時に認証系とは別の 403 要因になり得る。

優先度:

- 高。Issue #167 の受け入れ条件に「メッセージ既読」「全既読」の成功テストが明記されているため、先にテストで固定してから dependency を削除する。

### `k_back/app/api/v1/endpoints/offices.py`

残存箇所:

- `PUT /api/v1/offices/me`

現状テスト:

- `tests/api/v1/test_csrf_protection.py` に、CSRF なし拒否、有効 CSRF 成功、無効 CSRF 拒否、Bearer 認証では CSRF 不要のテストがある。

影響:

- 既に代表的な成功/拒否ケースはあるため、削除リスクは比較的低い。
- ただし office 更新は監査ログ作成も含むため、dependency 削除後も `200` と更新結果を確認する既存テストを維持する。

優先度:

- 中。既存テストがあるため、messages / admin announcements のテスト追加後に削除するのが安全。

### `k_back/app/api/v1/endpoints/admin_announcements.py`

残存箇所:

- `POST /api/v1/admin/announcements`

影響:

- app_admin 専用の全体お知らせ作成 API。
- Issue #167 の受け入れ条件に「管理者通知作成 API が CSRF 付きで成功するテスト」が明記されている。

優先度:

- 高。対象 API の成功テストを追加してから dependency を削除する。

## 既存テストの確認

`k_back/tests/api/v1/test_csrf_protection.py` に以下が存在する。

- CSRF token 取得 endpoint のテスト。
- CSRF token cookie 設定のテスト。
- `PUT /api/v1/offices/me` が CSRF なしで `403` になるテスト。
- `PUT /api/v1/offices/me` が有効 CSRF 付きで `200` になるテスト。
- `PUT /api/v1/offices/me` が無効 CSRF で `403` になるテスト。
- Bearer 認証では `PUT /api/v1/offices/me` が CSRF なしで成功するテスト。
- `POST /api/v1/messages/personal` が Cookie 認証かつ CSRF なしで `403` になるテスト。
- stale access cookie があっても login 本体のエラーが返るテスト。
- logout が Cookie 認証でも CSRF で止まらないテスト。
- GET は CSRF 不要であることのテスト。

不足しているテスト:

- `POST /api/v1/messages/{message_id}/read` の CSRF 付き成功。
- `POST /api/v1/messages/mark-all-read` の CSRF 付き成功。
- `POST /api/v1/admin/announcements` の CSRF 付き成功。
- 個別 dependency 削除後も Cookie 認証の CSRF なしリクエストが global middleware で拒否されることの対象 API 別確認。

## 推奨実装順

### 1. テスト helper を整理

`test_csrf_protection.py` 内で以下を共通化する。

- CSRF token 取得。
- `access_token` cookie 生成。
- `fastapi-csrf-token` cookie と `X-CSRF-Token` header の組み立て。

既存の `csrf_headers` fixture が他テストにある場合は再利用を検討する。ただし、このファイル内だけの局所 helper でもよい。

### 2. Red: 対象 API の CSRF 付き成功テスト追加

追加候補:

- `test_message_mark_as_read_with_valid_csrf_token`
- `test_message_mark_all_read_with_valid_csrf_token`
- `test_admin_announcement_create_with_valid_csrf_token`

期待:

- 個別 dependency が残っている現状でも成功する可能性が高い。
- その場合、Red/Green としては「dependency 削除前の回帰固定テスト」と位置付ける。

### 3. 個別 `Depends(validate_csrf)` を削除

削除候補:

- `messages.py`
  - `send_personal_message`
  - `send_announcement`
  - `mark_message_as_read`
  - `mark_all_as_read`
- `offices.py`
  - `update_office_info`
- `admin_announcements.py`
  - `send_announcement_to_all`

あわせて不要 import を削除する。

### 4. Green: 既存拒否テストと追加成功テストを通す

最低限実行:

```bash
docker compose exec -T backend pytest tests/api/v1/test_csrf_protection.py
```

必要に応じて:

```bash
docker compose exec -T backend pytest tests/api/v1/test_admin_announcements.py tests/api/v1/test_messages.py
```

該当テストファイル名が存在しない場合は `test_csrf_protection.py` に集約する。

## 手動確認項目

Issue #167 に残る手動確認:

- stale access Cookie が残っていてもログインできること。
- MFA 必須アカウントで MFA 完了後に通常画面へ遷移できること。
- ログイン直後に通知既読など他の状態変更 API が成功すること。

既に確認済みとして issue に記録されているもの:

- 期限切れ Cookie 状態での logout。
- 通常ログイン。
- 通常ログアウト。
- ログイン直後のメッセージ送信。
- PDF アップロード。

## 受け入れ基準

- 対象 API の CSRF 付き成功テストが追加されている。
- 個別 `Depends(validate_csrf)` を削除しても、Cookie 認証の状態変更 API で CSRF なしリクエストが `403` になる。
- Bearer 認証は従来通り CSRF なしで成功する。
- logout / login / MFA の auth flow 修正に回帰がない。
- 手動確認結果が issue コメントまたは review md に追記されている。

## リスク

- 二重検証を削除すると、endpoint dependency の `CsrfProtectError` 経由で返っていた挙動が global middleware の `403` に統一される。現状は同じ detail を返すため影響は小さい見込み。
- `messages.py` は `archive_message` のように state change だが個別 dependency がない endpoint もある。global middleware が正であることを前提にするなら、この状態は方針と整合する。
- admin announcements は app_admin 認証 setup が必要なため、テストデータ作成に既存 factory の仕様確認が必要。

## 結論

Issue #167 は実装可能。方針は「global middleware を正とし、個別 `Depends(validate_csrf)` をテスト追加後に削除」でよい。

最初の実装 PR では、対象 API の CSRF 付き成功テスト追加と個別 dependency 削除に限定する。手動確認項目は staging またはローカル E2E で確認し、issue コメントまたは本ディレクトリの review md に追記する。
