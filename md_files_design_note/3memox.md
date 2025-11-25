# メッセージ詳細ページへのリンクが404になる問題

## 現象

MessageCardコンポーネントのリンクをクリックすると404エラーが発生。

```tsx
<Link
  href={`/notice/messages/${message.message_id}`}
  className="text-white font-bold text-lg hover:text-blue-400 transition-colors cursor-pointer"
>
  {message.title}
</Link>
```

**ファイル**: `k_front/components/notice/MessageCard.tsx` (line 130)

---

## 調査結果

### 1. ファイル構造は正しい ✅

```
k_front/app/(protected)/notice/
├── [id]
│   └── page.tsx          # 通知詳細（承認リクエスト等）
├── messages
│   └── [id]
│       └── page.tsx      # メッセージ詳細
└── page.tsx              # 通知一覧
```

- メッセージ詳細ページ: `/notice/messages/[id]/page.tsx` ✅
- ルーティングパス: `/notice/messages/{message_id}` ✅

### 2. コンポーネントコードは正しい ✅

- MessageCard のリンク: `/notice/messages/${message.message_id}` ✅
- page.tsx の実装: params.id を正しく取得 ✅
- 自動既読機能: 実装済み ✅

### 3. 考えられる原因

#### A. Next.js開発サーバーのキャッシュ問題
Next.jsの開発サーバーが古いルーティング情報をキャッシュしている可能性。

#### B. TypeScriptビルドエラー
ページにTypeScriptエラーがあり、正しくビルドされていない可能性。

#### C. message_idが不正な値
MessageInboxItemの`message_id`フィールドが正しく設定されていない可能性。

---

## 解決方法

### ステップ1: フロントエンド開発サーバーを再起動

```bash
# k_frontディレクトリで実行
cd k_front
npm run dev

# または、Dockerを使用している場合
docker-compose restart frontend
```

### ステップ2: TypeScriptエラーをチェック

```bash
cd k_front
npm run type-check

# または
npx tsc --noEmit
```

### ステップ3: ブラウザのキャッシュをクリア

- ブラウザのデベロッパーツールを開く (F12)
- Network タブで「Disable cache」を有効化
- ページをリロード (Ctrl+Shift+R / Cmd+Shift+R)

### ステップ4: message_idの値を確認

ブラウザのコンソールで、MessageCardが受け取っているデータを確認：

```javascript
// MessagesTab.tsx または Noticeのページで
console.log('Messages:', messages.map(m => ({
  id: m.message_id,
  title: m.title
})));
```

### ステップ5: APIレスポンスを確認

メッセージ取得APIが正しいデータを返しているか確認：

```bash
# curlでテスト（要：認証トークン）
curl -X GET "http://localhost:8000/api/v1/messages/inbox" \
  -H "Cookie: access_token=YOUR_TOKEN" \
  -H "X-CSRF-Token: YOUR_CSRF_TOKEN"
```

レスポンスの`messages[].message_id`フィールドが存在し、UUID形式であることを確認。

---

## Next.jsルーティングの確認

### 正しいルーティング

| URL | ファイルパス | 説明 |
|-----|-------------|------|
| `/notice` | `app/(protected)/notice/page.tsx` | 通知一覧 |
| `/notice/messages/{uuid}` | `app/(protected)/notice/messages/[id]/page.tsx` | メッセージ詳細 |
| `/notice/{uuid}` | `app/(protected)/notice/[id]/page.tsx` | 通知詳細（承認等） |

### パラメータの取得方法

```tsx
// app/(protected)/notice/messages/[id]/page.tsx
import { useParams } from 'next/navigation';

export default function MessageDetailPage() {
  const params = useParams();
  const messageId = params.id as string;  // ✅ 正しい
  // ...
}
```

---

## デバッグ手順

### 1. リンクが正しく生成されているか確認

ブラウザのデベロッパーツールでリンク要素を検査：

```html
<!-- 期待される出力 -->
<a href="/notice/messages/12345678-1234-1234-1234-123456789abc">
  メッセージタイトル
</a>
```

### 2. クリック時のURLを確認

リンクをクリックしたときにブラウザのURLバーが正しく変わるか確認：

```
期待: http://localhost:3000/notice/messages/12345678-1234-1234-1234-123456789abc
```

### 3. 404ページのソースを確認

404ページが表示されたら、以下を確認：
- Next.jsの404ページか？ → ルーティング問題
- カスタム404ページか？ → API応答問題
- 真っ白なページか？ → JavaScriptエラー

---

## よくある問題と解決策

### 問題1: Dynamic Routeが認識されない

**原因**: Next.jsの開発サーバーが新しいページを認識していない

**解決**:
```bash
# 開発サーバーを再起動
npm run dev
```

### 問題2: ビルドエラーで404

**原因**: TypeScriptエラーやインポートエラーでページがビルドされていない

**解決**:
```bash
# エラーを確認
npm run type-check

# ビルドを試行
npm run build
```

### 問題3: 認証エラーで404

**原因**: (protected)グループ内のページなので認証が必要

**解決**:
- ログイン状態を確認
- Cookieに`access_token`が存在するか確認
- 認証ミドルウェアのログを確認

---

## 修正が完了したら

以下を確認：
- [ ] フロントエンド開発サーバーを再起動した
- [ ] TypeScriptエラーがない（`npm run type-check`）
- [ ] ブラウザキャッシュをクリアした
- [ ] メッセージ一覧からリンクをクリックして詳細ページが表示される
- [ ] メッセージが未読の場合、自動的に既読になる
- [ ] 404エラーが発生しない

---

## 追加調査が必要な場合

もし上記の手順で解決しない場合：

1. **Next.jsのルーティングログを有効化**:
   ```bash
   # next.config.jsに追加
   module.exports = {
     logging: {
       fetches: {
         fullUrl: true,
       },
     },
   }
   ```

2. **ブラウザコンソールのエラーを確認**:
   - F12 → Console タブ
   - エラーメッセージをコピー

3. **Network タブでAPIリクエストを確認**:
   - F12 → Network タブ
   - メッセージ詳細取得のリクエストを確認
   - ステータスコード、レスポンスボディを確認

---

## 参考情報

- [Next.js App Router - Dynamic Routes](https://nextjs.org/docs/app/building-your-application/routing/dynamic-routes)
- [Next.js App Router - Route Groups](https://nextjs.org/docs/app/building-your-application/routing/route-groups)
- MessageCard実装: `k_front/components/notice/MessageCard.tsx`
- メッセージ詳細ページ: `k_front/app/(protected)/notice/messages/[id]/page.tsx`
