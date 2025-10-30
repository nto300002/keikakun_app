# API Domain Migration Checklist (api.keikakun.com)

## 実施済み ✅

### Phase 2: サブドメイン設定
- [x] Cloud Runでカスタムドメインマッピングを作成
- [x] CNAMEレコードの値を取得（`ghs.googlehosted.com`）
- [x] ラッコドメインでCNAMEレコードを追加
  ```
  NAME  RECORD TYPE  CONTENTS
  api   CNAME        ghs.googlehosted.com.
  ```
- [x] DNS伝播を確認（`nslookup api.keikakun.com`）
- [x] SSL証明書が発行されたことを確認
- [x] ローカル環境変数を更新 (`k_front/.env`)

---

## 次のステップ（これから実施）

### 1. `https://api.keikakun.com`の動作確認

```bash
# バックエンドAPIが正常に動作するか確認
curl https://api.keikakun.com/docs

# または
curl https://api.keikakun.com/api/v1/health
```

**期待される結果:**
- ステータスコード: 200
- SSL証明書エラーがないこと
- FastAPI docsが表示されること

---

### 2. バックエンドのCORS設定を更新

**ファイル:** `k_back/app/main.py` (48-85行目)

**現在の設定:**
```python
if is_production:
    allowed_origins = [
        "https://keikakun-front.vercel.app",
        "https://www.keikakun.com"
    ]
```

**更新後:**
```python
if is_production:
    allowed_origins = [
        "https://keikakun-front.vercel.app",
        "https://www.keikakun.com",
        # サブドメイン構成のため追加（念のため）
        "https://api.keikakun.com",
    ]
```

**コミット:**
```bash
cd k_back
git add app/main.py
git commit -m "fix: Add api.keikakun.com to CORS allowed origins"
git push origin main
```

**注意:** サブドメイン構成では、`api.keikakun.com` からのリクエストではなく、`www.keikakun.com` からのリクエストを受け取るため、実際にはこの追加は不要かもしれません。動作確認後に調整してください。

---

### 3. Vercel環境変数を更新

**Vercel Dashboard:**
1. https://vercel.com/dashboard にアクセス
2. プロジェクト `keikakun-front` を選択
3. 「Settings」→「Environment Variables」
4. `NEXT_PUBLIC_API_URL` を探す
5. 値を更新:
   ```
   旧: https://k-back-655926128522.asia-northeast1.run.app
   新: https://api.keikakun.com
   ```
6. 「Save」をクリック

**再デプロイ:**
1. 「Deployments」タブ → 最新のデプロイメント
2. 「...」メニュー → 「Redeploy」
3. 環境変数の変更が反映されます

---

### 4. 本番環境での動作確認

#### 4-1: ログイン・ログアウトのテスト

1. https://www.keikakun.com/auth/login にアクセス
2. ログインフォームが正常に表示されることを確認
3. ログイン情報を入力してログイン
4. ダッシュボードにリダイレクトされることを確認
5. **開発者ツール → Network タブ:**
   - `/api/v1/staffs/me` のリクエストURLが `https://api.keikakun.com/api/v1/staffs/me` になっているか確認
   - ステータスが 200 OK か確認
   - Cookie (`access_token`) が送信されているか確認
6. ログアウトボタンをクリック
7. ログインページにリダイレクトされることを確認
8. 再度ログイン可能か確認

#### 4-2: Cookie設定の確認

**ブラウザの開発者ツール:**
1. `F12` → 「Application」タブ → 「Cookies」
2. `https://www.keikakun.com` を選択
3. `access_token` Cookieを確認:

| 属性 | 期待値 |
|------|--------|
| **Name** | `access_token` |
| **Domain** | `.keikakun.com` |
| **Path** | `/` |
| **Secure** | `Yes` (HTTPS) |
| **HttpOnly** | `Yes` |
| **SameSite** | `None` (現在) または `Lax` (最適化後) |

---

### 5. ローカル環境での動作確認

```bash
# バックエンド起動
cd k_back
uvicorn app.main:app --reload --port 8000

# フロントエンド起動（別ターミナル）
cd k_front
npm run dev
```

**確認項目:**
1. ログインページで401エラーが出ないこと ⭐
2. ログイン・ログアウトが正常に動作すること
3. ダッシュボードにアクセスできること
4. APIリクエストが `http://localhost:8000` に向いているか確認

---

### 6. (オプション) バックエンドのCookie設定を最適化

サブドメイン構成が正常に動作したら、`SameSite=Lax` に変更してセキュリティを向上できます。

**ファイル:** `k_back/app/api/v1/endpoints/auths.py`

**変更箇所:** Cookie設定（SameSite属性）

```python
# 本番環境の場合
if settings.ENVIRONMENT == "production":
    # サブドメイン構成では SameSite=Lax が使用可能（より安全）
    response.set_cookie(
        key="access_token",
        value=access_token,
        httponly=True,
        secure=True,  # HTTPS必須
        samesite="lax",  # "none" から "lax" に変更 ⭐
        domain=".keikakun.com",  # サブドメイン間で共有
        path="/",
        max_age=expires_delta,
    )
```

**コミット:**
```bash
cd k_back
git add app/api/v1/endpoints/auths.py
git commit -m "feat: Optimize Cookie security with SameSite=Lax for subdomain setup"
git push origin main
```

**注意:** 変更後は必ず動作確認を行ってください。問題があれば `SameSite=None` に戻してください。

---

## GitHub Actions について

### ✅ 修正不要！

**理由:**
1. **フロントエンド**: VercelがGitHub経由で自動デプロイ（専用のワークフローなし）
2. **バックエンド**: GitHub Actions → Cloud Build → Cloud Runのパイプラインは、バックエンドのURLを変更しません
3. 新しいドメイン(`api.keikakun.com`)はCloud Runのカスタムドメインマッピングで実現されるため、デプロイプロセスは変更不要

**ワークフロー:** `.github/workflows/cd-backend.yml`
- このファイルは**変更不要**
- `FRONTEND_URL` 変数はバックエンドのCORS設定で使用されるだけ
- バックエンドのデプロイ先URLは変更されません（Cloud Runの内部URLは `k-back-*.run.app` のまま）

---

## トラブルシューティング

### 問題1: `https://api.keikakun.com` にアクセスできない

**症状:**
```bash
curl https://api.keikakun.com/docs
# → Connection refused / Timeout
```

**解決策:**
1. DNS伝播が完了しているか確認:
   ```bash
   nslookup api.keikakun.com
   # 期待される出力: ghs.googlehosted.com への CNAME
   ```
2. Cloud RunのSSL証明書が発行されているか確認:
   ```bash
   # Cloud Console → Cloud Run → k-back → カスタムドメインタブ
   # api.keikakun.com のステータスが「アクティブ」になっているか確認
   ```

### 問題2: 本番環境でログイン後に401エラーが出る

**症状:**
ログイン後、`/api/v1/staffs/me` が401を返す

**解決策:**
1. Cookie設定を確認:
   - `Domain`: `.keikakun.com` になっているか
   - `Secure`: `true` になっているか
   - `HttpOnly`: `true` になっているか
2. CORS設定を確認:
   - `www.keikakun.com` が `allowed_origins` に含まれているか
   - `credentials: 'include'` がフロントエンドに設定されているか
3. ブラウザの開発者ツールでCookieが存在するか確認

### 問題3: Vercel環境変数の変更が反映されない

**症状:**
再デプロイ後も、ネットワークタブで古いURL（`k-back-*.run.app`）が表示される

**解決策:**
1. Vercelの環境変数設定を再確認
2. 「Production」環境の変数を変更したか確認
3. 完全に新しいデプロイを実行:
   ```bash
   # ローカルから手動でトリガー
   cd k_front
   git commit --allow-empty -m "chore: Trigger redeployment for API URL update"
   git push origin main
   ```

---

## Phase 1: DALパターンの実装（まだ未実施）

ローカル環境の401エラーを解消するため、後日実装を推奨します。

詳細は `subdomain_migration_guide.md` の Phase 1 を参照。

---

**作成日:** 2025-10-30
**最終更新:** 2025-10-30
