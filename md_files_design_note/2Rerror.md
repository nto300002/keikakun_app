# CSRF エラー - メッセージ API テスト失敗調査

## 概要

テストの一つが以下のエラーで失敗しました。

```
CSRF validation failed: Missing Cookie: `fastapi-csrf-token`.
FAILED tests/api/v1/test_messages_api.py::TestPersonalMessageAPI::test_send_personal_message_success - assert 403 == 201
```

発生日時: 2025-11-25
対象テストファイル: `tests/api/v1/test_messages_api.py`
失敗 HTTP ステータス: 403 Forbidden（期待: 201 Created）

---

## 該当エンドポイント

ファイル: `k_back/app/api/v1/endpoints/messages.py` の該当ハンドラ

```python
@router.post("/personal", response_model=MessageDetailResponse, status_code=status.HTTP_201_CREATED)
async def send_personal_message(
    *,
    request: Request,
    db: AsyncSession = Depends(deps.get_db),
    current_user: Staff = Depends(deps.get_current_user),
    message_in: MessagePersonalCreate,
    _: None = Depends(deps.validate_csrf)  # CSRF 検証
):
```

このエンドポイントは `deps.validate_csrf` によって CSRF 検証を行う設計になっています。

---

## テストの状況（問題の再現）

テスト側では、Cookie ベースでの認証を使って access_token をクッキーにセットしてから POST リクエストを行っていますが、CSRF 用の Cookie / ヘッダをセットしていませんでした。該当部分（テストの抜粋）は次のような振る舞いです。

- access_token を Cookie にセットして認証は通しているつもり
- ただし CSRF 用 Cookie (`fastapi-csrf-token`) とヘッダ (`X-CSRF-Token`) を送っていないため、CSRF 検証で 403 が返る

一方、他テスト（例: staff 削除テスト）は Authorization ヘッダに Bearer トークンを付与しており、その場合 `validate_csrf` が CSRF チェックをスキップするロジックになっているため成功しています。

---

## validate_csrf の動作（重要点）

`deps.validate_csrf` の実装は概ね次の方針です:

- Authorization ヘッダに "Bearer " が含まれる場合は CSRF チェックをスキップ（API クライアントが Bearer トークンを用いる想定）
- そうでない場合は Cookie ベースの認証を想定し、CSRF 用の Cookie (`fastapi-csrf-token`) とリクエストヘッダ (`X-CSRF-Token`) を検証する

このため、テストが Cookie ベースで access_token を送る場合は CSRF 用の Cookie とヘッダをセットする必要があります。

---

## 修正案（テスト側）


B) Cookie + CSRF モードを正しく使う（実装と振る舞いを確認したい場合）
- テストで事前に CSRF トークンを取得するエンドポイント（例: `GET /api/v1/csrf-token`）を叩いて、返却される CSRF トークンと CSRF Cookie (`fastapi-csrf-token`) をセットする。
- リクエスト時にヘッダ `X-CSRF-Token` と Cookie `fastapi-csrf-token` を付与して POST を行う。
- テスト用ヘルパー（fixture）を用意してこの手順を再利用すると良い。

どちらを選ぶかはテスト方針次第です。フロントエンド実運用では Cookie+CSRF を使う想定であれば B を選び、単純に API 動作確認が目的なら A を採るのが手早いです。

---

## 修正案（バックエンド）

- 現状の `validate_csrf` のロジックは妥当（Bearer でスキップ、Cookie モードで検証）なので、バックエンド側の変更は必須ではありません。
- ただしテストやドキュメントの整合性のために、テストで使用する認証方式を明示するか、テストヘルパーを追加して Cookie+CSRF のセット手順を簡単に行えるようにすることを推奨します。

---

## テスト修正サンプル（手順、擬似コード）

- Cookie+CSRF を使う場合（フロント寄せの検証）
  - csrf_resp = await async_client.get('/api/v1/csrf-token')
  - csrf_token = csrf_resp.json()['csrf_token']
  - csrf_cookie = csrf_resp.cookies.get('fastapi-csrf-token')
  - async_client.cookies.set('access_token', access_token)
  - async_client.cookies.set('fastapi-csrf-token', csrf_cookie)
  - headers = {'X-CSRF-Token': csrf_token}
  - async_client.post(..., headers=headers, json=payload)

テストヘルパーを作成しておくと重複を避けられます。

---

## チェックリスト

- [ ] テストで使用する認証方式Cookie+CSRFを統一したか
- [ ] Cookie+CSRF を使うテストは CSRF トークンと Cookie を事前に取得してセットしているか
- [ ] Authorization: Bearer を使うテストはヘッダが正しく付与されているか
- [ ] `deps.validate_csrf` のロジックに合わないテストが他にないか検索して修正する（`fastapi-csrf-token` を期待している箇所）

---

## 補足

- テスト中に CSRF トークンを取得する API の存在や挙動が不明な場合は、`k_back/app/api/v1/endpoints/csrf.py` 相当の実装や `deps` にその取得処理があるか確認してください。
- 本調査は文字化けを解消して内容を読みやすく整理したものです。実際のテスト修正を行う際は、該当テストファイルを編集して動作確認を行ってください。
