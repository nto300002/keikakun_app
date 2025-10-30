# Server Componentへの移行計画

## 背景・目的

### 現状の課題
1. **Client Componentでの認証チェック**
   - 現在、多くの保護されたページが`'use client'`ディレクティブを使用
   - クライアント側で`useEffect`を使って認証チェックとデータ取得を実行
   - 初回レンダリング時にローディング状態が表示され、UXが低下
   - SEO対策が不十分（検索エンジンがコンテンツをクロールできない）

2. **Cookie認証の利点を活かせていない**
   - Cookie認証を実装したが、Server Componentでの活用が不十分
   - SSR（Server Side Rendering）による初期データ取得が可能なのに、クライアント側でフェッチしている
   - ページ読み込み速度が遅い（クライアント側でのウォーターフォール問題）

3. **パフォーマンスの問題**
   - 認証チェック → データ取得の順次実行による遅延
   - クライアント側のJavaScriptバンドルサイズが大きい
   - Hydrationコストが高い

### 移行の目的
1. **パフォーマンス向上**
   - サーバー側での認証チェックとデータ取得により、初期表示を高速化
   - クライアント側のJavaScriptバンドルサイズを削減
   - ウォーターフォール問題の解消

2. **UX改善**
   - ローディング状態を最小限に抑える
   - ページ遷移時のちらつきを削減
   - エラー処理の一元化

3. **SEO対策**
   - サーバー側でレンダリングされたコンテンツを検索エンジンがクロール可能
   - メタデータの動的生成

4. **セキュリティ強化**
   - サーバー側での認証チェックにより、クライアント側での認証ロジックを削減
   - 環境変数やAPIエンドポイントの漏洩リスクを低減

---

## 対象ページの分類

### 優先度: 高（まず移行すべきページ）

#### 1. PDF一覧ページ (`app/(protected)/pdf-list/page.tsx`)
**現状:**
- `'use client'` ディレクティブを使用
- `useEffect`で認証チェック → office_id取得 → PDF一覧取得
- 初回レンダリング時にローディング状態を表示

**課題:**
- 3つのAPIリクエストが順次実行される（ウォーターフォール）
- ローディング時間が長い
- localStorage依存（`ReferenceError: localStorage is not defined`の原因）

**移行メリット:**
- サーバー側で並列データ取得が可能
- 初期表示が高速化
- Cookie認証の恩恵を最大限活用

**複雑度:** ★★★☆☆（中）
- 検索・フィルター機能あり
- ページネーション機能あり
- プレビュー機能はClient Componentとして残す

---

#### 2. 利用者一覧ページ (`app/(protected)/recipients/page.tsx`)
**現状:**
- `'use client'` ディレクティブを使用
- `useEffect`で利用者一覧を取得
- 検索・ページネーション機能あり

**課題:**
- クライアント側でのデータ取得による初期表示の遅延
- 検索クエリがURLに反映されていない

**移行メリット:**
- サーバー側での初期データ取得
- URLクエリパラメータによるSEO対策
- ページリロード時の状態維持

**複雑度:** ★★☆☆☆（低〜中）
- 検索・ページネーション機能あり
- 比較的シンプルな構造

---

#### 3. ダッシュボードページ (`app/(protected)/dashboard/page.tsx`)
**現状:**
- Server Componentとして実装されている（`'use client'`なし）
- `Dashboard`コンポーネントをインポート

**確認事項:**
- `Dashboard`コンポーネントの実装を確認
- Client Componentの場合、分割を検討

**複雑度:** ★☆☆☆☆（要確認）

---

### 優先度: 中（後で移行を検討）

#### 4. 利用者詳細ページ (`app/(protected)/recipients/[id]/page.tsx`)
#### 5. 利用者編集ページ (`app/(protected)/recipients/[id]/edit/page.tsx`)
#### 6. 利用者新規作成ページ (`app/(protected)/recipients/new/page.tsx`)
#### 7. サポート計画詳細ページ (`app/(protected)/support_plan/[id]/page.tsx`)
#### 8. 管理者ページ (`app/(protected)/admin/page.tsx`)

**移行判断基準:**
- 初回データ取得が必要か
- 複雑なインタラクションがあるか
- パフォーマンスのボトルネックとなっているか

---

## 実装フロー（TDD形式）

### フェーズ1: PDF一覧ページの移行

#### Step 1: 現状分析（Analysis）
**ファイル:** `app/(protected)/pdf-list/page.tsx`

**現在のアーキテクチャ:**
```
Client Component (page.tsx)
  ↓
  useEffect
  ↓
  authApi.getCurrentUser() → office_id取得
  ↓
  pdfDeliverablesApi.getList() → PDF一覧取得
  ↓
  PdfViewContent (Client Component)
```

**データフロー:**
1. ページロード
2. クライアント側で認証チェック
3. office_id取得
4. PDF一覧取得
5. レンダリング

**依存関係:**
- `authApi.getCurrentUser()`: `/api/v1/staffs/me`
- `pdfDeliverablesApi.getList()`: `/api/v1/plan-deliverables/`
- Cookie認証（`credentials: 'include'`）

---

#### Step 2: Server Component化の設計（Design）

**新しいアーキテクチャ:**
```
Server Component (page.tsx)
  ↓
  サーバー側でCookieから認証情報取得
  ↓
  並列データ取得:
    - authApi.getCurrentUser()
    - pdfDeliverablesApi.getList()
  ↓
  初期データをPropsとして渡す
  ↓
  PdfViewContent (Client Component)
```

**変更箇所:**
1. **`app/(protected)/pdf-list/page.tsx`**
   - `'use client'`を削除
   - Server Componentとして実装
   - `searchParams`をPropsとして受け取る
   - サーバー側でデータ取得

2. **`components/protected/pdf-list/PdfViewContent.tsx`**
   - Client Componentとして保持（`'use client'`を維持）
   - インタラクティブな機能を担当：
     - 検索
     - フィルター
     - ページネーション
     - プレビュー表示

3. **`lib/http.ts`**
   - 既に実装済み（Cookie対応）
   - Server ComponentでCookieから自動的にトークン取得

**データフェッチ戦略:**
```typescript
// Server Component内で並列データ取得
const [currentUser, initialPdfs] = await Promise.all([
  authApi.getCurrentUser(),
  pdfDeliverablesApi.getList({ office_id, skip, limit, search, recipient_ids })
]);
```

---

#### Step 3: 実装（Implementation）

##### 3-1. Server Component化
**ファイル:** `app/(protected)/pdf-list/page.tsx`

```typescript
// 'use client' を削除

import { redirect } from 'next/navigation';
import { authApi } from '@/lib/auth';
import { pdfDeliverablesApi } from '@/lib/pdf-deliverables';
import PdfViewContent from '@/components/protected/pdf-list/PdfViewContent';

interface PageProps {
  searchParams: {
    page?: string;
    search?: string;
    recipient?: string;
  };
}

export default async function PdfViewPage({ searchParams }: PageProps) {
  // 1. URLパラメータの解析
  const page = Number(searchParams.page) || 1;
  const search = searchParams.search || '';
  const recipientId = searchParams.recipient || '';

  // 2. サーバー側で認証チェック
  let currentUser;
  try {
    currentUser = await authApi.getCurrentUser();
  } catch (error) {
    console.error('[Server] Authentication failed:', error);
    redirect('/auth/login');
  }

  // 3. office_idチェック
  if (!currentUser.office?.id) {
    console.error('[Server] User has no office associated');
    redirect('/auth/select-office');
  }

  // 4. 初期データ取得
  const skip = (page - 1) * 20;
  let pdfData;
  try {
    pdfData = await pdfDeliverablesApi.getList({
      office_id: currentUser.office.id,
      skip,
      limit: 20,
      search: search || undefined,
      recipient_ids: recipientId && recipientId !== 'all' ? recipientId : undefined,
    });
  } catch (error) {
    console.error('[Server] Failed to fetch PDFs:', error);
    // エラーページまたはフォールバック表示
    pdfData = { items: [], total: 0, skip: 0, limit: 20, has_more: false };
  }

  // 5. Client Componentにデータを渡す
  return (
    <PdfViewContent
      initialPdfs={pdfData.items}
      initialTotal={pdfData.total}
      currentPage={page}
      userRole={currentUser.role}
      officeId={currentUser.office.id}
      initialSearchQuery={search}
      initialFilterRecipient={recipientId || 'all'}
    />
  );
}
```

**変更点:**
- `'use client'`を削除
- `async`関数として実装
- `searchParams`をPropsとして受け取る
- サーバー側でデータ取得（`await`）
- `redirect()`を使用してリダイレクト
- `useEffect`, `useState`, `useRouter`を削除

---

##### 3-2. Client Componentの調整
**ファイル:** `components/protected/pdf-list/PdfViewContent.tsx`

**Props追加:**
```typescript
interface PdfViewContentProps {
  initialPdfs: PlanDeliverableListItem[];
  initialTotal: number;
  currentPage: number;
  userRole: 'owner' | 'manager' | 'employee';
  officeId: string;
  initialSearchQuery?: string;      // 追加
  initialFilterRecipient?: string;  // 追加
}
```

**初期化の修正:**
```typescript
const [searchQuery, setSearchQuery] = useState(initialSearchQuery || '');
const [filterRecipient, setFilterRecipient] = useState(initialFilterRecipient || 'all');
```

**変更点:**
- 初期検索クエリ・フィルターをPropsとして受け取る
- `useEffect`での認証チェックを削除
- サーバー側で取得したデータを初期値として使用

---

##### 3-3. エラーハンドリングの改善
**ファイル:** `app/(protected)/pdf-list/page.tsx`

**エラーバウンダリの追加（オプション）:**
```typescript
// app/(protected)/pdf-list/error.tsx
'use client';

export default function Error({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <div className="flex flex-col items-center justify-center min-h-screen">
      <h2 className="text-2xl font-bold mb-4">エラーが発生しました</h2>
      <p className="text-muted-foreground mb-4">{error.message}</p>
      <button onClick={() => reset()} className="btn btn-primary">
        再試行
      </button>
    </div>
  );
}
```

---

#### Step 4: テスト（Testing）

##### 4-1. 動作確認項目
1. **基本動作**
   - [ ] ページが正常にレンダリングされる
   - [ ] 初期データが表示される
   - [ ] ローディング状態が表示されない（サーバー側で取得済み）

2. **認証チェック**
   - [ ] 未認証ユーザーがログインページにリダイレクトされる
   - [ ] office未設定ユーザーが選択ページにリダイレクトされる

3. **検索・フィルター機能**
   - [ ] 検索ボックスに入力してフィルタリングできる
   - [ ] 利用者絞り込みが機能する
   - [ ] URLパラメータが正しく更新される

4. **ページネーション**
   - [ ] ページ遷移が正常に動作する
   - [ ] URLパラメータが正しく更新される

5. **パフォーマンス**
   - [ ] 初期表示が高速化される
   - [ ] Hydrationエラーが発生しない

##### 4-2. テストコマンド
```bash
# 開発サーバー起動
cd k_front
npm run dev

# ブラウザで確認
# http://localhost:3000/pdf-list
```

---

#### Step 5: 最適化（Optimization）

##### 5-1. キャッシング戦略
```typescript
// app/(protected)/pdf-list/page.tsx

// Next.js 14のキャッシュ設定
export const revalidate = 60; // 60秒ごとに再検証
export const dynamic = 'force-dynamic'; // 常に動的レンダリング（認証が必要なため）
```

##### 5-2. ストリーミング（オプション）
```typescript
// Suspenseを使った段階的レンダリング
import { Suspense } from 'react';

export default async function PdfViewPage({ searchParams }: PageProps) {
  return (
    <Suspense fallback={<LoadingSpinner />}>
      <PdfDataFetcher searchParams={searchParams} />
    </Suspense>
  );
}
```

---

### フェーズ2: 利用者一覧ページの移行

#### Step 1: 現状分析
**ファイル:** `app/(protected)/recipients/page.tsx`

**現在のアーキテクチャ:**
```
Client Component (page.tsx)
  ↓
  useEffect
  ↓
  welfareRecipientsApi.list()
  ↓
  レンダリング
```

#### Step 2-5: PDF一覧ページと同様の手順で実装

**主な変更点:**
- `'use client'`を削除
- Server Componentとして実装
- `searchParams`から検索クエリとページ番号を取得
- サーバー側でデータ取得

---

### フェーズ3: ダッシュボードページの確認

#### Step 1: `Dashboard`コンポーネントの確認
**ファイル:** `components/protected/dashboard/Dashboard.tsx`

**確認事項:**
- `'use client'`の有無
- データ取得方法（`useEffect`か、Propsか）
- インタラクティブな機能の有無

#### Step 2: 必要に応じて分割
- Server Componentとして実装可能な部分
- Client Componentとして残す必要がある部分

---

## 技術的な考慮事項

### 1. Cookie認証との連携
- **Server Component**: `cookies()`を使ってCookieから認証情報を取得
- **`lib/http.ts`**: 既に実装済み（`getToken()`がサーバー側でCookieから取得）
- **認証エラー**: `redirect('/auth/login')`でリダイレクト

### 2. URLパラメータの扱い
```typescript
// Server Component
interface PageProps {
  searchParams: {
    page?: string;
    search?: string;
    // ...
  };
}

export default async function Page({ searchParams }: PageProps) {
  const page = Number(searchParams.page) || 1;
  // ...
}
```

### 3. Client Componentとの境界
**Server Componentで行うこと:**
- 認証チェック
- 初期データ取得
- リダイレクト

**Client Componentで行うこと:**
- ユーザーインタラクション（検索、フィルター、ページネーション）
- 動的なデータ更新
- ダイアログ・モーダル表示

### 4. エラーハンドリング
```typescript
// Server Component
try {
  const data = await fetchData();
} catch (error) {
  // エラーページまたはフォールバック表示
  redirect('/auth/login');
}
```

### 5. リダイレクト
```typescript
import { redirect } from 'next/navigation';

// 認証エラー
redirect('/auth/login');

// office未設定
redirect('/auth/select-office');
```

---

## 移行チェックリスト

### PDF一覧ページ (`app/(protected)/pdf-list/page.tsx`)
- [ ] `'use client'`を削除
- [ ] `async`関数として実装
- [ ] `searchParams`をPropsとして受け取る
- [ ] サーバー側で認証チェック
- [ ] サーバー側でデータ取得
- [ ] `redirect()`でリダイレクト
- [ ] `PdfViewContent`にPropsを追加
- [ ] 動作確認
- [ ] パフォーマンス測定

### 利用者一覧ページ (`app/(protected)/recipients/page.tsx`)
- [ ] 同上

### ダッシュボードページ (`app/(protected)/dashboard/page.tsx`)
- [ ] `Dashboard`コンポーネントの確認
- [ ] 必要に応じて分割

---

## 期待される効果

### パフォーマンス
- **初期表示時間**: 30-50%削減（予想）
- **JavaScriptバンドルサイズ**: 10-20%削減
- **Time to Interactive (TTI)**: 改善

### UX
- **ローディング状態**: 最小限に抑える
- **ちらつき**: 削減
- **SEO**: 検索エンジンがコンテンツをクロール可能

### 開発体験
- **コードの簡潔化**: `useEffect`の削除
- **エラーハンドリング**: 一元化
- **型安全性**: Server ComponentでのTypeScript活用

---

## リスクと対策

### リスク1: Hydrationエラー
**原因:** Server ComponentとClient Componentの状態不一致

**対策:**
- 初期データをPropsとして正しく渡す
- クライアント側での状態管理を最小限に抑える

### リスク2: パフォーマンス低下（逆効果）
**原因:** サーバー側でのデータ取得が遅い

**対策:**
- 並列データ取得（`Promise.all()`）
- キャッシング戦略の見直し
- バックエンドAPIのパフォーマンス改善

### リスク3: Cookie認証の問題
**原因:** サーバー側でCookieが取得できない

**対策:**
- `lib/http.ts`の実装確認
- `credentials: 'include'`の設定確認
- CORS設定の確認

---

## 参考資料

### Next.js公式ドキュメント
- [Server Components](https://nextjs.org/docs/app/building-your-application/rendering/server-components)
- [Client Components](https://nextjs.org/docs/app/building-your-application/rendering/client-components)
- [Data Fetching](https://nextjs.org/docs/app/building-your-application/data-fetching)
- [Cookies](https://nextjs.org/docs/app/api-reference/functions/cookies)

### React公式ドキュメント
- [Server Components](https://react.dev/reference/react/use-server)
- [Client Components](https://react.dev/reference/react/use-client)