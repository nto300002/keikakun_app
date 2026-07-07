# Next.js / React 脆弱性修正レポート

**実施日**: 2026年1月24日
**対応者**: Claude Sonnet 4.5
**重要度**: 🔴 Critical

---

## エグゼクティブサマリー

Next.js および React に複数の**重大な脆弱性**（CVE-2025-55182 等）が発見され、緊急パッチを適用しました。最も深刻な脆弱性は CVSS 10.0 でリモートコード実行（RCE）が可能であり、すでに実際の攻撃が観測されています。

すべてのパッケージを最新の安全なバージョンに更新し、セキュリティ監査で**脆弱性0件**を確認しました。

---

## 更新されたバージョン

| Component | Before | After | 変更内容 |
|-----------|--------|-------|---------|
| **Next.js** | 16.0.10 | **16.1.4** | ✅ セキュリティパッチ適用 |
| **React** | 19.1.2 | **19.2.3** | ✅ セキュリティパッチ適用 |
| **React-dom** | 19.1.2 | **19.2.3** | ✅ セキュリティパッチ適用 |
| **eslint-config-next** | 16.0.10 | **16.1.4** | ✅ Next.js バージョンに合わせて更新 |
| **Node.js** | 22.15.0 | **22.22.0** | ✅ AsyncLocalStorage DoS 修正 |
| **npm** | - | 10.9.4 | ℹ️ Node.js 22.22.0 に付属 |

---

## 修正された脆弱性一覧

### 🔴 Critical: CVE-2025-55182 (React2Shell)

**CVSS スコア**: 10.0 (最高レベル)

- **影響**: React Server Components における認証不要のリモートコード実行（RCE）
- **原因**: 安全でない非シリアル化処理
- **影響範囲**: Next.js 15.x, 16.x の App Router を使用するアプリケーション
- **パッチバージョン**: React 19.2.3
- **発見日**: 2025年11月29日
- **公開日**: 2025年12月3日
- **攻撃観測**: あり（Wiz Research, Amazon Threat Intelligence, Datadog 等で確認）

**技術詳細**:
```
React Server Components のデフォルト設定で、攻撃者が細工したペイロードを
送信することでサーバー側で任意のコードを実行できる脆弱性。
```

### 🔴 Critical: CVE-2025-66478

**影響**: Next.js における RCE 脆弱性（CVE-2025-55182 の Next.js 側での識別子）
**パッチバージョン**: Next.js 16.1.4

### 🟠 High: CVE-2025-55184

**影響**: Denial of Service (DoS) 攻撃
**原因**: React Server Components における処理の問題
**パッチバージョン**: React 19.2.3

### 🟠 High: CVE-2025-67779

**影響**: CVE-2025-55182 の初期修正が不完全だった問題
**詳細**: 最初のパッチ（React 19.2.1）では脆弱性が完全に修正されておらず、追加のパッチが必要でした
**パッチバージョン**: React 19.2.3

### 🟠 High: CVE-2025-59466 (Node.js)

**影響**: AsyncLocalStorage および async_hooks における DoS 脆弱性
**原因**: "Maximum call stack size exceeded" エラーが uncatchable になる問題
**影響範囲**:
- React Server Components を使用するアプリケーション
- Next.js アプリケーション
- APM ツール（Datadog, New Relic, Dynatrace, Elastic APM, OpenTelemetry）を使用するアプリケーション
- AsyncLocalStorage または async_hooks.createHook() を使用する任意のアプリケーション

**パッチバージョン**: Node.js 22.22.0
**リリース日**: 2026年1月13日

### 🟡 Medium: CVE-2025-55183

**影響**: ソースコード露出
**パッチバージョン**: React 19.2.3

---

## 実施した作業

### 1. 環境調査

```bash
# 現在のバージョン確認
cd /Users/naotoyasuda/workspase/keikakun_app/k_front
npm outdated next react react-dom
node --version
```

**結果**:
- Next.js 16.0.10 → 16.1.4 available
- React 19.1.2 → 19.2.3 available ⚠️ **脆弱性あり**
- Node.js 22.15.0 → 22.22.0 available ⚠️ **脆弱性あり**

### 2. Next.js / React アップデート

```bash
npm install next@16.1.4 react@19.2.3 react-dom@19.2.3
npm install eslint-config-next@16.1.4
```

**結果**: changed 9 packages, found 0 vulnerabilities ✅

### 3. Node.js アップデート

```bash
# nodebrew を使用して Node.js をアップデート
nodebrew install v22.22.0
nodebrew use v22.22.0
node --version  # v22.22.0 確認
```

### 4. ビルドテスト

```bash
npm run build
```

**結果**: ✅ Compiled successfully in 2.2s

**警告**:
- metadata の `themeColor` と `viewport` を `generateViewport()` に移行する必要がある（deprecation warning）
- middleware.ts を proxy.ts にリネームする必要がある（Next.js 16.1 の変更）

### 5. セキュリティ監査

```bash
npm audit
```

**結果**:
```
found 0 vulnerabilities ✅
```

---

## package.json の変更内容

```diff
diff --git a/package.json b/package.json
index 6ecc03e..7fa9ab3 100644
--- a/package.json
+++ b/package.json
@@ -23,11 +23,11 @@
     "class-variance-authority": "^0.7.1",
     "clsx": "^2.1.1",
     "lucide-react": "^0.544.0",
-    "next": "^16.0.10",
+    "next": "^16.1.4",
     "next-themes": "^0.4.6",
     "qrcode.react": "^4.2.0",
-    "react": "19.1.2",
-    "react-dom": "19.1.2",
+    "react": "^19.2.3",
+    "react-dom": "^19.2.3",
     "react-dropzone": "^14.3.8",
     "react-hook-form": "^7.62.0",
     "react-icons": "^5.5.0",
@@ -42,7 +42,7 @@
     "@types/react": "^19",
     "@types/react-dom": "^19",
     "eslint": "9.34.0",
-    "eslint-config-next": "^16.0.10",
+    "eslint-config-next": "^16.1.4",
     "tailwindcss": "^4",
     "typescript": "^5"
   },
```

---

## 🔒 重要: デプロイ後の必須作業

公式セキュリティガイドラインに従い、**アプリケーションを本番環境に再デプロイした後、必ず以下を実行してください**：

### シークレットのローテーション（必須）

CVE-2025-55182（React2Shell）により、攻撃者がサーバー上で任意のコードを実行できる可能性があったため、**既存のシークレットが漏洩している可能性**があります。

#### ローテーションが必要なもの

- [ ] **環境変数** (.env, .env.local, .env.production)
- [ ] **API キー**
  - [ ] Stripe API キー (STRIPE_SECRET_KEY, STRIPE_PUBLISHABLE_KEY)
  - [ ] その他の外部 API キー
- [ ] **データベース接続情報**
  - [ ] DATABASE_URL
  - [ ] データベースユーザーのパスワード
- [ ] **JWT シークレット**
  - [ ] ACCESS_TOKEN_SECRET
  - [ ] REFRESH_TOKEN_SECRET
- [ ] **セッション関連**
  - [ ] SESSION_SECRET
  - [ ] NEXTAUTH_SECRET
- [ ] **その他すべての機密情報**
  - [ ] SMTP パスワード
  - [ ] OAuth クライアントシークレット
  - [ ] 暗号化キー

#### ローテーション手順

1. **バックエンド (k_back)**:
   ```bash
   # .env ファイルのすべてのシークレットを新しい値に変更
   vim .env

   # 新しい環境変数で再起動
   docker-compose down
   docker-compose up -d
   ```

2. **フロントエンド (k_front)**:
   ```bash
   # .env.local の API キー等を更新
   vim .env.local

   # 再ビルド・再デプロイ
   npm run build
   ```

3. **Google Cloud Run / Vercel 等の環境変数を更新**

4. **すべてのアクティブなセッションを無効化**
   - データベースの sessions テーブルをクリア
   - Redis キャッシュをフラッシュ

---

## タイムライン

| 日時 | イベント |
|------|---------|
| 2025年11月29日 | Lachlan Davidson が Meta Bug Bounty 経由で脆弱性を報告 |
| 2025年11月30日 | Meta セキュリティチームが脆弱性を確認 |
| 2025年12月1日 | React チームが修正を作成開始 |
| 2025年12月3日 | CVE-2025-55182 公開、初期パッチリリース（React 19.2.1） |
| 2025年12月11日 | 追加の脆弱性発見（CVE-2025-55183, CVE-2025-55184） |
| 2025年12月11日 | 完全なパッチリリース（React 19.2.3） |
| 2025年12月15日 | CVE-2025-67779 公開（初期修正の不完全性を指摘） |
| 2026年1月13日 | Node.js セキュリティリリース（CVE-2025-59466） |
| **2026年1月24日** | **本プロジェクトでパッチ適用** |

---

## 攻撃の観測状況

以下の組織が実際の攻撃を観測・報告しています：

- **Wiz Research**
- **Amazon Threat Intelligence**
- **Datadog Security Research**
- **Google Cloud Threat Intelligence**
- **Microsoft Security**
- **Unit42 (Palo Alto Networks)**

**攻撃者**: 中国に関連するサイバー脅威グループによる攻撃が報告されています。

---

## 技術的な背景

### React Server Components の脆弱性

React Server Components (RSC) は、Next.js 15+ の App Router で使用されている新しいレンダリングアーキテクチャです。この仕組みでは、サーバー側でコンポーネントをシリアル化してクライアントに送信しますが、その逆方向（クライアント→サーバー）の非シリアル化処理に脆弱性がありました。

```
攻撃フロー:
1. 攻撃者が細工した RSC ペイロードを送信
2. サーバー側で安全でない非シリアル化が発生
3. 任意のコードが実行される (RCE)
```

### AsyncLocalStorage の脆弱性

Node.js の `AsyncLocalStorage` や `async_hooks.createHook()` を使用している場合、深い再帰呼び出しで "Maximum call stack size exceeded" エラーが発生すると、通常の `process.on('uncaughtException')` ハンドラーに到達せず、プロセスが即座に終了してしまう問題がありました。

これは Next.js、APM ツール、その他多くのライブラリに影響します。

---

## 検証結果

### ビルド成功

```
▲ Next.js 16.1.4 (Turbopack)
✓ Compiled successfully in 2.2s
✓ Generating static pages using 9 workers (32/32) in 168.2ms
```

### セキュリティ監査

```bash
npm audit
# found 0 vulnerabilities ✅
```

### 機能テスト

- [ ] ローカル開発サーバー起動 (`npm run dev`)
- [ ] 本番ビルド (`npm run build`)
- [ ] 各種ページの表示確認
- [ ] API エンドポイントの動作確認
- [ ] 認証フローの確認

---

## 今後の対応

### 即座に実施

1. ✅ パッケージのアップデート（完了）
2. ✅ ビルドテスト（完了）
3. ✅ セキュリティ監査（完了）
4. ⏳ Git コミット・プッシュ
5. ⏳ 本番環境へのデプロイ
6. ⏳ **すべてのシークレットのローテーション（最重要）**
7. ⏳ アクティブセッションの無効化
8. ⏳ 本番環境の動作確認

### 短期（1週間以内）

- [ ] Next.js 16.1 の新しい警告に対応
  - [ ] `middleware.ts` を `proxy.ts` にリネーム
  - [ ] metadata の `themeColor` / `viewport` を `generateViewport()` に移行
- [ ] セキュリティログの確認（不審なアクセスがないか）
- [ ] アクセスログの分析（RCE 攻撃の痕跡確認）

### 中期（1ヶ月以内）

- [ ] 定期的なセキュリティ監査の自動化
  - [ ] GitHub Actions に `npm audit` を追加
  - [ ] Dependabot / Renovate の設定見直し
- [ ] セキュリティ監視の強化
  - [ ] WAF ルールの見直し
  - [ ] 異常なトラフィックの検知
- [ ] インシデント対応手順の見直し

### 長期（継続的に）

- [ ] Next.js / React の最新バージョンへの追従
- [ ] Node.js LTS バージョンの定期的なアップデート
- [ ] セキュリティアドバイザリの監視
- [ ] チーム内でのセキュリティ意識向上

---

## 参考資料

### 公式ドキュメント

- [Next.js Security Advisory: CVE-2025-66478](https://nextjs.org/blog/CVE-2025-66478)
- [Next.js Security Update: December 11, 2025](https://nextjs.org/blog/security-update-2025-12-11)
- [React: Critical Security Vulnerability in React Server Components](https://react.dev/blog/2025/12/03/critical-security-vulnerability-in-react-server-components)
- [React: Denial of Service and Source Code Exposure](https://react.dev/blog/2025/12/11/denial-of-service-and-source-code-exposure-in-react-server-components)
- [Node.js Security Releases: January 13, 2026](https://nodejs.org/en/blog/vulnerability/december-2025-security-releases)
- [Node.js: Mitigating DoS Vulnerability in AsyncLocalStorage](https://nodejs.org/en/blog/vulnerability/january-2026-dos-mitigation-async-hooks)

### セキュリティ分析

- [Vercel: React2Shell Security Bulletin](https://vercel.com/react2shell)
- [Vercel: Summary of CVE-2025-55182](https://vercel.com/changelog/cve-2025-55182)
- [Wiz Research: React2Shell (CVE-2025-55182) Critical Vulnerability](https://www.wiz.io/blog/critical-vulnerability-in-react-cve-2025-55182)
- [Unit42: Exploitation of Critical Vulnerability in React Server Components](https://unit42.paloaltonetworks.com/cve-2025-55182-react-and-cve-2025-66478-next/)
- [Microsoft Security: Defending against CVE-2025-55182](https://www.microsoft.com/en-us/security/blog/2025/12/15/defending-against-the-cve-2025-55182-react2shell-vulnerability-in-react-server-components/)
- [Google Cloud: Multiple Threat Actors Exploit React2Shell](https://cloud.google.com/blog/topics/threat-intelligence/threat-actors-exploit-react2shell-cve-2025-55182)
- [AWS Security: China-nexus cyber threat groups exploit React2Shell](https://aws.amazon.com/blogs/security/china-nexus-cyber-threat-groups-rapidly-exploit-react2shell-vulnerability-cve-2025-55182/)

### CVE データベース

- [NVD: CVE-2025-55182](https://nvd.nist.gov/vuln/detail/CVE-2025-55182)
- [CVE Details: CVE-2025-55182](https://www.cvedetails.com/cve/CVE-2025-55182/)
- [Snyk: CVE-2025-55182](https://security.snyk.io/vuln/SNYK-UPSTREAM-NODE-14975915)
- [Tenable: CVE-2025-59466](https://www.tenable.com/cve/CVE-2025-59466)

---

## まとめ

今回発見された脆弱性は**極めて深刻**で、すでに実際の攻撃が観測されています。迅速にパッチを適用し、セキュリティ監査で脆弱性が解消されたことを確認しました。

**次のステップは、本番環境へのデプロイとすべてのシークレットのローテーションです。これは必須作業であり、スキップできません。**

---

**作成日**: 2026年1月24日
**最終更新**: 2026年1月24日
**作成者**: Claude Sonnet 4.5
**レビュー**: 未実施
