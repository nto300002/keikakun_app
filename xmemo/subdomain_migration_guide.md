# サブドメイン移行ガイド (api.keikakun.com)

## 📋 目次

1. [概要](#概要)
2. [現在の構成](#現在の構成)
3. [移行後の構成](#移行後の構成)
4. [Phase 1: DALパターンの実装](#phase-1-dalパターンの実装)
5. [Phase 2: サブドメイン設定](#phase-2-サブドメイン設定)
6. [Phase 3: 検証と最適化](#phase-3-検証と最適化)

---

## 概要

### 目的
- ローカル環境と本番環境での認証動作を統一
- Cookie認証を同一ドメイン内で実現（クロスドメイン問題の解消）
- CVE-2025-29927セキュリティ脆弱性への対策
- Next.js Middlewareの制限を回避

### メリット
✅ ローカルと本番の動作が統一される（テストが容易）
✅ MiddlewareでもCookieが正常に読み取れる
✅ `SameSite=Lax`が使用可能（セキュリティ向上）
✅ クロスドメインの遅延問題が解消
✅ CVE-2025-29927対策（DALパターン）

---

## 現在の構成

| コンポーネント | ドメイン | プラットフォーム |
|--------------|---------|---------------|
| フロントエンド | `https://www.keikakun.com` | Vercel |
| バックエンド | `https://k-back-655926128522.asia-northeast1.run.app` | Cloud Run |

**問題点:**
- 異なるドメイン → Next.js MiddlewareがCookieを読み取れない
- クロスドメイン → `SameSite=None`が必要（セキュリティリスク）
- ローカル（localhost）と本番で動作が異なる

---

## 移行後の構成

| コンポーネント | ドメイン | プラットフォーム |
|--------------|---------|---------------|
| フロントエンド | `https://www.keikakun.com` | Vercel |
| バックエンド | `https://api.keikakun.com` ⭐ | Cloud Run + カスタムドメイン |

**Cookie Domain:** `.keikakun.com` (サブドメイン間で共有可能)

---

## Phase 1: DALパターンの実装

**所要時間:** 1-2時間
**ダウンタイム:** なし
**目的:** CVE-2025-29927対策、ローカル環境の401エラー解消

### Step 1-1: DALファイルの作成

**ファイル:** `k_front/lib/dal.ts`

```typescript
/**
 * Data Access Layer (DAL)
 * CVE-2025-29927対策として、Middlewareに依存せずに認証を検証
 */
import 'server-only';
import { cookies } from 'next/headers';
import { cache } from 'react';

const API_BASE_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8000';

export interface Session {
  user: {
    id: string;
    email: string;
    username: string;
    role: string;
    office?: { id: string; name: string } | null;
  };
}

export const verifySession = cache(async (): Promise<Session | null> => {
  const cookieStore = await cookies();
  const accessToken = cookieStore.get('access_token');

  if (!accessToken) {
    return null;
  }

  try {
    const response = await fetch(`${API_BASE_URL}/api/v1/staffs/me`, {
      method: 'GET',
      headers: {
        'Content-Type': 'application/json',
        'Cookie': `access_token=${accessToken.value}`,
      },
      credentials: 'include',
      cache: 'no-store',
    });

    if (!response.ok) return null;

    const user = await response.json();
    return { user };
  } catch (error) {
    console.error('[DAL] Session verification failed:', error);
    return null;
  }
});

export async function requireAuth(): Promise<Session> {
  const session = await verifySession();
  if (!session) {
    throw new Error('Unauthorized: Authentication required');
  }
  return session;
}
```

**作成コマンド:**
```bash
cd k_front
touch lib/dal.ts
# 上記コードを貼り付け
```

### Step 1-2: Middlewareの簡素化

**ファイル:** `k_front/middleware.ts`

**変更内容:**
- Cookie存在チェックのみ実施（軽量なリダイレクト判定）
- 実際の認証検証はDALで実施

```typescript
import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;
  const accessToken = request.cookies.get('access_token');

  // 保護ルート
  const isProtectedPath = pathname.startsWith('/dashboard') ||
                          pathname.startsWith('/admin') ||
                          pathname.startsWith('/recipients') ||
                          pathname.startsWith('/pdf-list');

  // 公開ルート
  const isPublicPath = pathname.startsWith('/auth/login') ||
                       pathname.startsWith('/auth/signup') ||
                       pathname === '/';

  // 保護ルートでCookieがない場合のみリダイレクト
  if (isProtectedPath && !accessToken) {
    const loginUrl = new URL('/auth/login', request.url);
    loginUrl.searchParams.set('from', pathname);
    return NextResponse.redirect(loginUrl);
  }

  return NextResponse.next();
}

export const config = {
  matcher: [
    '/((?!api|_next/static|_next/image|favicon.ico|sitemap.xml|robots.txt).*)',
  ],
};
```

### Step 1-3: 保護ページでDALを使用

**ファイル:** `k_front/app/(protected)/dashboard/page.tsx`

```typescript
import { verifySession } from '@/lib/dal';
import { redirect } from 'next/navigation';

export default async function DashboardPage() {
  // DALで認証検証（実際のセキュリティチェック）
  const session = await verifySession();

  if (!session) {
    redirect('/auth/login?from=/dashboard');
  }

  // 認証済みユーザーのみがここに到達
  return (
    <div>
      <h1>Welcome {session.user.email}</h1>
      {/* ダッシュボードコンテンツ */}
    </div>
  );
}
```

### Step 1-4: LoginFormの修正

**ファイル:** `k_front/components/auth/LoginForm.tsx`

**変更内容:**
- useEffectの自動認証チェックを削除
- ログインページでの不要な401エラーを解消

```typescript
// 削除: useEffectによる自動認証チェック
// useEffect(() => {
//   const checkAuth = async () => {
//     await authApi.getCurrentUser(); // ← これが401エラーの原因
//     router.push('/dashboard');
//   };
//   checkAuth();
// }, [router]);

// middlewareとDALに任せる
```

### Step 1-5: テスト

```bash
cd k_front
npm run dev
```

**確認項目:**
1. ログインページで401エラーが出ないこと
2. ログイン後、ダッシュボードにアクセスできること
3. 未ログインでダッシュボードにアクセスするとログインページにリダイレクトされること

---

## Phase 2: サブドメイン設定

**所要時間:** 30分〜1時間
**ダウンタイム:** 約5分（DNS伝播時間による）
**目的:** 本番環境のドメインを統一

### Step 2-1: Cloud Runでカスタムドメインマッピングを作成

Cloud Runのカスタムドメインマッピングを設定すると、CNAMEレコードに設定すべき値が表示されます。

#### 方法1: Google Cloud Console（Web UI）

1. **Cloud Consoleにアクセス**
   - https://console.cloud.google.com/
   - プロジェクト選択: `keikakun_app`

2. **Cloud Runサービスに移動**
   - 左メニュー → Cloud Run
   - サービス `k-back` をクリック

3. **カスタムドメインを追加**
   - 画面上部の「カスタムドメインを管理」または「ドメインをマッピング」をクリック
   - 「ドメインをマッピング」ボタンをクリック

4. **ドメインを入力**
   - ドメイン: `api.keikakun.com`
   - サービス: `k-back`
   - リージョン: `asia-northeast1`
   - 「続行」をクリック

5. **DNSレコード情報を取得** ⭐
   - 画面に以下のような情報が表示されます:

   ```
   以下のDNSレコードをドメインプロバイダーに追加してください:

   タイプ: CNAME
   名前: api
   値: ghs.googlehosted.com.
   ```

   または

   ```
   タイプ: CNAME
   名前: api
   値: ghs.googlehosted.com
   ```

   **この値をメモしてください！** ← これがラッコドメインに設定する値です

#### 方法2: gcloud CLI

**重要:** `domain-mappings`コマンドは**betaリリース**です。`gcloud beta`を使用してください。

```bash
# 1. 正しいGCPプロジェクトに切り替え
gcloud config list project
# 現在のプロジェクトを確認

# もし違うプロジェクトの場合は切り替え
gcloud config set project YOUR_PROJECT_ID

# 2. Cloud Runサービスにカスタムドメインをマッピング
gcloud beta run domain-mappings create \
  --service=k-back \
  --domain=api.keikakun.com \
  --region=asia-northeast1 \
  --platform=managed

# 出力例:
# Waiting for certificate provisioning. You must configure your DNS records for certificate issuance to begin.
# DNS レコードを設定してください:
#
# タイプ: CNAME
# 名前: api
# 値: ghs.googlehosted.com.
```

**この出力に表示される「値」をメモしてください！**

**トラブルシューティング:**

エラー: `unrecognized arguments: --region`
```bash
# 解決策: gcloud beta を使用
gcloud beta run domain-mappings create ...
```

エラー: `API [run.googleapis.com] not enabled`
```bash
# 解決策: 正しいプロジェクトに切り替え
gcloud projects list
gcloud config set project YOUR_CORRECT_PROJECT_ID
```

#### CNAMEレコードの値について

Cloud Runのカスタムドメインマッピングでは、通常以下のいずれかの値が表示されます:

- `ghs.googlehosted.com.` （末尾にドット付き）
- `ghs.googlehosted.com` （末尾にドットなし）

ラッコドメインでは**末尾のドットは不要**です。`ghs.googlehosted.com` を入力してください。

### Step 2-2: ラッコドメインでCNAMEレコードを追加

1. **ラッコドメインにログイン**
   - https://domain.rakko.jp/

2. **ドメイン管理画面に移動**
   - `keikakun.com` を選択
   - 「DNS設定」または「DNSレコード編集」をクリック

3. **CNAMEレコードを追加**

   | 項目 | 値 |
   |------|-----|
   | **タイプ** | CNAME |
   | **ホスト名** | `api` |
   | **値（VALUE）** | `ghs.googlehosted.com` ⭐ |
   | **TTL** | 3600（デフォルト） |

   **重要:**
   - ホスト名は `api` のみ（`api.keikakun.com` ではない）
   - 値は Cloud Console/gcloud で表示された値を使用
   - 末尾のドット(`.`)は不要

4. **保存して反映を待つ**
   - DNS伝播には通常5分〜1時間かかります
   - 確認コマンド:
   ```bash
   # DNSレコードが正しく設定されているか確認
   nslookup api.keikakun.com

   # または
   dig api.keikakun.com

   # 期待される出力:
   # api.keikakun.com. 3600 IN CNAME ghs.googlehosted.com.
   ```

### Step 2-3: SSL証明書の自動発行を待つ

Cloud Runは自動的にSSL証明書を発行します。

**確認方法:**

```bash
# マッピングステータスを確認
gcloud run domain-mappings describe api.keikakun.com \
  --region=asia-northeast1 \
  --platform=managed

# 出力例:
# status:
#   conditions:
#   - status: "True"
#     type: Ready
#   - status: "True"
#     type: CertificateProvisioned  ← これがTrueになればOK
```

または Cloud Console で:
- Cloud Run → k-back → 「カスタムドメイン」タブ
- `api.keikakun.com` のステータスが「アクティブ」になることを確認

**所要時間:** 通常5〜15分

### Step 2-4: 動作確認

SSL証明書が発行されたら、新しいドメインでアクセスできるか確認します。

```bash
# バックエンドAPIが正常に動作するか確認
curl https://api.keikakun.com/api/v1/health

# または
curl https://api.keikakun.com/docs
```

**期待される結果:**
- ステータスコード: 200
- SSL証明書エラーがないこと
- レスポンスが正常に返ること

---

## Phase 2: サブドメイン設定（続き）

### Step 2-5: バックエンドのCORS設定を更新

**ファイル:** `k_back/app/main.py`

**変更箇所:** 48-85行目のCORS設定

```python
# 本番環境のallowed_originsに新しいドメインを追加
if settings.ENVIRONMENT == "production":
    allowed_origins = [
        "https://keikakun-front.vercel.app",
        "https://www.keikakun.com",
        # 新規追加（念のため、実際には同一ドメインなので不要になる可能性あり）
        "https://api.keikakun.com",
    ]
```

**注意:** サブドメイン構成では、`api.keikakun.com` からのリクエストではなく、`www.keikakun.com` からのリクエストを受け取るため、実際にはこの追加は不要かもしれません。動作確認後に調整してください。

### Step 2-6: フロントエンドのAPI URLを更新

#### 方法1: Vercelの環境変数を更新（推奨）

1. **Vercel Dashboardにアクセス**
   - https://vercel.com/dashboard
   - プロジェクト `keikakun-front` を選択

2. **環境変数を編集**
   - 「Settings」→「Environment Variables」
   - `NEXT_PUBLIC_API_URL` を探す
   - 値を更新:
     ```
     旧: https://k-back-655926128522.asia-northeast1.run.app
     新: https://api.keikakun.com
     ```
   - 「Save」をクリック

3. **再デプロイ**
   - 「Deployments」タブ → 最新のデプロイメント
   - 「...」メニュー → 「Redeploy」
   - 環境変数の変更が反映されます

#### 方法2: .env.productionを更新してコミット

**ファイル:** `k_front/.env.production`

```bash
# 旧
NEXT_PUBLIC_API_URL=https://k-back-655926128522.asia-northeast1.run.app

# 新
NEXT_PUBLIC_API_URL=https://api.keikakun.com
```

```bash
cd k_front
git add .env.production
git commit -m "fix: Update API URL to use api.keikakun.com subdomain"
git push origin main
```

Vercelが自動的に再デプロイします。

### Step 2-7: バックエンドのCookie設定を最適化（オプション）

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

**メリット:**
- `SameSite=Lax` は `None` よりも安全
- CSRF攻撃のリスクが低減
- クロスサイトトラッキングを防止

**注意:** 変更後は必ず動作確認を行ってください。

---

## Phase 3: 検証と最適化

**所要時間:** 30分〜1時間
**目的:** 移行後の動作確認と最適化

### Step 3-1: 本番環境での動作確認

#### 3-1-1: ログイン・ログアウトのテスト

```bash
# ブラウザで以下を確認:
1. https://www.keikakun.com/auth/login にアクセス
2. ログインフォームが正常に表示されることを確認
3. ログイン情報を入力してログイン
4. ダッシュボードにリダイレクトされることを確認
5. ログアウトボタンをクリック
6. ログインページにリダイレクトされることを確認
7. 再度ログイン可能か確認
```

#### 3-1-2: Cookie設定の確認

**ブラウザの開発者ツールで確認:**

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
| **SameSite** | `Lax` (または `None`) |

#### 3-1-3: ネットワークリクエストの確認

**開発者ツール → 「Network」タブ:**

1. ダッシュボードにアクセス
2. `/api/v1/staffs/me` リクエストを確認:
   - **リクエストURL:** `https://api.keikakun.com/api/v1/staffs/me`
   - **ステータス:** 200 OK
   - **Cookie送信:** `access_token` が自動送信されているか確認

#### 3-1-4: エラーログの確認

**フロントエンド（Vercel）:**
```bash
# Vercel CLIでログを確認
vercel logs

# または Vercel Dashboard → Logs
```

**バックエンド（Cloud Run）:**
```bash
# Cloud Runログを確認
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=k-back" \
  --limit=50 \
  --format=json

# または Cloud Console → Cloud Run → k-back → Logs
```

### Step 3-2: ローカル環境での動作確認

ローカル環境では引き続き `localhost` を使用します。

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

### Step 3-3: 旧ドメインのリダイレクト設定（オプション）

旧バックエンドURL (`https://k-back-655926128522.asia-northeast1.run.app`) へのアクセスを新ドメインにリダイレクトする場合:

**ファイル:** `k_back/app/main.py`

```python
from fastapi import Request
from fastapi.responses import RedirectResponse

@app.middleware("http")
async def redirect_old_domain(request: Request, call_next):
    # 旧ドメインからのアクセスを新ドメインにリダイレクト
    host = request.headers.get("host", "")
    if "run.app" in host and settings.ENVIRONMENT == "production":
        new_url = str(request.url).replace(host, "api.keikakun.com")
        return RedirectResponse(url=new_url, status_code=301)

    response = await call_next(request)
    return response
```

**注意:** この設定は、すべてのフロントエンドが新ドメインに移行した後に実装してください。

### Step 3-4: パフォーマンスとセキュリティの最適化

#### 3-4-1: HSTSヘッダーの追加

**ファイル:** `k_back/app/main.py`

```python
@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response = await call_next(request)

    if settings.ENVIRONMENT == "production":
        # HSTS: ブラウザに常にHTTPSを使用させる
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"

    return response
```

#### 3-4-2: DNS TTLの最適化

DNSレコードが安定したら、TTLを長くしてパフォーマンスを向上:

**ラッコドメイン:**
- `api.keikakun.com` のTTLを `3600` → `86400`（24時間）に変更

---

## トラブルシューティング

### 問題1: CNAMEレコードが反映されない

**症状:**
```bash
nslookup api.keikakun.com
# → Server can't find api.keikakun.com: NXDOMAIN
```

**解決策:**
1. ラッコドメインの設定を再確認:
   - ホスト名: `api`（`api.keikakun.com` ではない）
   - 値: `ghs.googlehosted.com`（末尾のドット不要）
2. DNS伝播を待つ（最大48時間、通常は1時間以内）
3. キャッシュをクリア:
   ```bash
   # macOS
   sudo dscacheutil -flushcache
   sudo killall -HUP mDNSResponder

   # Windows
   ipconfig /flushdns
   ```

### 問題2: SSL証明書が発行されない

**症状:**
Cloud Console で「証明書のプロビジョニング中」が長時間続く

**解決策:**
1. DNSレコードが正しく設定されているか確認:
   ```bash
   dig api.keikakun.com
   ```
2. Cloud Runのログを確認:
   ```bash
   gcloud run domain-mappings describe api.keikakun.com \
     --region=asia-northeast1 \
     --platform=managed
   ```
3. 最大24時間待つ（通常は15分以内）

### 問題3: Cookieが送信されない

**症状:**
`/api/v1/staffs/me` が401エラーを返す

**解決策:**
1. Cookie設定を確認:
   - `Domain`: `.keikakun.com`
   - `Secure`: `true`
   - `HttpOnly`: `true`
2. CORS設定を確認:
   - `credentials: 'include'` がフロントエンドに設定されているか
   - バックエンドのCORS設定で `allow_credentials=True` か
3. ブラウザの開発者ツールでCookieが存在するか確認

### 問題4: ローカル環境で401エラーが出る

**症状:**
ログインページで `GET http://localhost:8000/api/v1/staffs/me 401` エラー

**解決策:**
Phase 1のStep 1-4を実施してください:
- `LoginForm.tsx` の `useEffect` で自動認証チェックを削除
- DALパターンを使用して認証チェックを実施

---

## ロールバック手順

問題が発生した場合の緊急ロールバック:

### 1. フロントエンドのAPI URLを元に戻す

**Vercel Dashboard:**
- `NEXT_PUBLIC_API_URL` を `https://k-back-655926128522.asia-northeast1.run.app` に戻す
- 再デプロイ

### 2. ラッコドメインのCNAMEレコードを削除

- `api.keikakun.com` のCNAMEレコードを削除

### 3. Cloud Runのドメインマッピングを削除

```bash
gcloud run domain-mappings delete api.keikakun.com \
  --region=asia-northeast1 \
  --platform=managed
```

---

## チェックリスト

### Phase 1: DALパターンの実装

- [ ] `lib/dal.ts` を作成
- [ ] `middleware.ts` を簡素化
- [ ] 保護ページで `verifySession()` を使用
- [ ] `LoginForm.tsx` の `useEffect` を削除
- [ ] ローカル環境で401エラーが出ないことを確認

### Phase 2: サブドメイン設定

- [x] Cloud Runでカスタムドメインマッピングを作成
- [x] CNAMEレコードの値を取得（`ghs.googlehosted.com`）
- [x] ラッコドメインでCNAMEレコードを追加
NAME  RECORD TYPE  CONTENTS
api   CNAME        ghs.googlehosted.com.
- [ ] DNS伝播を確認（`nslookup api.keikakun.com`）
- [ ] SSL証明書が発行されたことを確認
- [ ] `https://api.keikakun.com/docs` にアクセスできることを確認
- [ ] バックエンドのCORS設定を更新
- [ ] フロントエンドのAPI URLを更新（Vercel環境変数）
- [ ] フロントエンドを再デプロイ



### Phase 3: 検証と最適化

- [ ] 本番環境でログイン・ログアウトをテスト
- [ ] Cookie設定を確認（Domain: `.keikakun.com`）
- [ ] ネットワークリクエストを確認（API URL: `api.keikakun.com`）
- [ ] エラーログを確認（フロントエンド・バックエンド）
- [ ] ローカル環境で動作確認
- [ ] パフォーマンス・セキュリティの最適化（HSTS等）

---

## 参考リンク

- [Next.js Data Access Layer](https://nextjs.org/docs/app/guides/authentication#data-access-layer)
- [CVE-2025-29927 解説](https://securitylabs.datadoghq.com/articles/nextjs-middleware-auth-bypass/)
- [Cloud Run カスタムドメイン](https://cloud.google.com/run/docs/mapping-custom-domains)
- [Cookie属性リファレンス](https://developer.mozilla.org/en-US/docs/Web/HTTP/Cookies)

---

**作成日:** 2025-10-30
**最終更新:** 2025-10-30
