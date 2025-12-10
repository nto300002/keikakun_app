# npmセキュリティ脆弱性調査

## 1. npmサプライチェーン攻撃 (2025年9月8日)

**参考**: [Vercel Blog - Critical npm Supply Chain Attack Response](https://vercel.com/blog/critical-npm-supply-chain-attack-response-september-8-2025)

### 攻撃の概要
2025年9月8日、重大なnpmサプライチェーン攻撃が発生。18の人気パッケージが侵害され、暗号資産取引を標的とした悪意のあるコードが注入されました。

### 影響を受けたパッケージ
- `chalk` - ターミナル文字列スタイリングライブラリ
- `debug` - デバッグユーティリティ
- `ansi-styles` - ANSI色スタイル
- その他15パッケージ

### 攻撃メカニズム
注入されたコードは以下の動作を実行：
- **クライアント側ブラウザで実行**
- **暗号化およびWeb3ウォレット操作を傍受**
- **支払い先を攻撃者管理のアドレスにリダイレクト**

### 影響範囲
- Vercelの調査: **70チームにまたがる76の固有プロジェクト**がマルウェアを含むパッケージバージョンでビルド
- Vercelの顧客への被害は報告なし（早期発見・対応により）

### 根本原因
**フィッシングキャンペーン**:
- npmメンテナーを標的にしたフィッシング攻撃
- 偽ドメイン `npmjs.help` を使用した2要素認証偽造メール
- メンテナーの認証情報を収集し、パッケージを侵害

### 対応タイムライン
- **17:39 UTC**: 初期報告後、Vercelの緊急対応チーム稼働
- **22:19 UTC**: 全影響プロジェクトのビルドキャッシュを削除

### 推奨される対策

#### 影響を受けたプロジェクト向け
1. **即座にプロジェクトを再ビルド**
2. **依存関係更新プラクティスの見直し**
3. **パッケージバージョンのピン留め検討**

#### 全プロジェクト向け
1. **脆弱性チェック**: `npm audit` を定期実行
2. **CI/CDパイプラインに依存関係スキャンを実装**
3. **`npm ci` とロックファイル (`package-lock.json`) を活用**
4. **npm provenance機能を有効化** (パッケージの出所を検証)

#### セキュリティベストプラクティス
```bash
# 脆弱性スキャン
npm audit

# 自動修正（可能な場合）
npm audit fix

# ロックファイルを使用した確定的インストール
npm ci

# 依存関係の更新確認
npm outdated
```

---

## 2. Next.js脆弱性 CVE-2025-66478

**参考**: [Next.js Security Advisory - CVE-2025-66478](https://nextjs.org/blog/CVE-2025-66478)

### CVE情報
- **CVE番号**: CVE-2025-66478
- **CVSS スコア**: 10.0（最高レベル）
- **上流CVE**: CVE-2025-55182（React Server Components プロトコルの脆弱性）

### 脆弱性の内容
**Remote Code Execution (RCE) の可能性**:
- 信頼できない入力がサーバー側の実行動作に影響を与える
- 攻撃者が細工されたリクエストを送信すると、意図しないサーバー実行パスがトリガーされる
- **パッチ未適用環境でのリモートコード実行が可能**

### 影響を受けるバージョン
✅ **影響あり**:
- Next.js **15.x** 全バージョン
- Next.js **16.x** 全バージョン
- Next.js **14.3.0-canary.77 以降**のカナリア版

❌ **影響なし**:
- Next.js **13.x**
- Next.js **14.x** 安定版
- **Pages Router** アプリケーション
- **Edge Runtime**

### 修正バージョン
パッチが適用されたバージョン:
- **15.0.5**, **15.1.9**, **15.2.6**, **15.3.6**, **15.4.8**, **15.5.7**
- **16.0.7**
- 対応するカナリア版

### 推奨される対策

#### 1. 即座にアップグレード（必須）
```bash
# 自動更新コマンド
npx fix-react2shell-next
```

または手動で所属するリリースラインの最新パッチ版にアップグレード。

#### 2. 環境変数とシークレットのローテーション
パッチ適用後、以下を実施：
- **全ての環境変数をローテーション**
- **APIキー、データベース認証情報をローテーション**
- **シークレット（JWT秘密鍵など）を再生成**

#### 3. 重要な注意事項
⚠️ **回避策は存在しない** - パッチ版へのアップグレードが**必須**

---

## 本プロジェクトへの影響と対応

### 現在のNext.jsバージョン確認
```bash
cd k_front
npm list next
```

### 対応チェックリスト
- [ ] Next.jsバージョンを確認
- [ ] 影響を受けるバージョンの場合、即座にパッチ版にアップグレード
- [ ] `npm audit` で他の脆弱性も確認
- [ ] 依存関係の最新化
- [ ] 環境変数・シークレットのローテーション（必要に応じて）
- [ ] CI/CDパイプラインに `npm audit` を追加
- [ ] `package-lock.json` をgit管理に含める
- [ ] `npm install` ではなく `npm ci` を使用（本番・CI環境）

### セキュリティ強化策
1. **Dependabot/Renovate導入**: 依存関係の自動更新PR
2. **定期的なセキュリティ監査**: 週次で `npm audit` 実行
3. **ロックファイルの活用**: 確定的なビルド環境を保証
4. **最小権限の原則**: 環境変数やAPIキーの適切な管理

---

## 3. サプライチェーン攻撃への多層防御対策

**参考**: [Zenn - npm サプライチェーン攻撃への対策](https://zenn.dev/hand_dot/articles/04542a91bc432e)

### 被害確認チェック

#### GitHubアカウントの確認
1. **不審なリポジトリのチェック**
   - "Sha1-Hulud: The Second Coming" という説明文のリポジトリがないか確認
   - 検索: `github.com/search?q=owner:[ユーザー名]+path:.github/workflows/discussion.yaml`

2. **セルフホストランナーの確認**
   - 各リポジトリで "SHA1HULUD" という名前のランナーがないかチェック

#### ローカル環境の確認
2025-11-20以降に更新された `node_modules` 内で以下のファイルを検索:

```bash
find . -type d -name "node_modules" -newermt "2025-11-20" -prune 2>/dev/null \
 | xargs -I {} find $(dirname {}) -name "setup_bun.js" -o -name "bun_environment.js" \
 -o -name "cloud.json" -o -name "actionsSecrets.json" 2>/dev/null | uniq
```

**検索対象ファイル**:
- `setup_bun.js` (ドロッパー)
- `bun_environment.js` (メインペイロード)
- `cloud.json` (クラウド認証情報)
- `environment.json` (環境変数)
- `actionsSecrets.json` (GitHub Actionsシークレット)

---

### 多層防御アプローチ

#### 層1: 改ざんパッケージ拡散の抑制

##### pnpmユーザー向け
`pnpm-workspace.yaml` に設定:
```yaml
minimumReleaseAge: 2880  # 公開から2880分（2日）経過していないパッケージをブロック
```

##### npm/yarn/bunユーザー向け - Aikido Safe Chain
```bash
# インストール
npm install -g @aikidosec/safe-chain

# セットアップ
safe-chain setup

# パッケージインストール時に自動チェック
npm install express
```

**機能**:
- 24時間ルール（デフォルト）: 公開後24時間以内のパッケージをブロック
- マルウェア検知機能

---

#### 層2: インストールスクリプト実行の無効化

##### npmユーザー向け
`.npmrc` ファイルに追加:
```ini
ignore-scripts=true
```

**ホワイトリスト方式での許可**:
```bash
npm install @lavamoat/allow-scripts
```

`package.json` で許可するパッケージを指定:
```json
{
  "lavamoat": {
    "allowScripts": {
      "sharp": true,
      "bcrypt": true,
      "esbuild": true
    }
  }
}
```

##### pnpm v10ユーザー向け
デフォルトで依存パッケージのスクリプトが無効化されている。必要な場合のみ:
```json
{
  "pnpm": {
    "onlyBuiltDependencies": ["esbuild", "sharp"]
  }
}
```

**推奨**: 最小限のパッケージのみ許可し、定期的に見直す

---

#### 層3: 既知の脆弱性検知

##### OSV-Scannerの使用
**インストール**:
```bash
# macOS
brew install osv-scanner

# 実行
osv-scanner --lockfile package-lock.json
```

**CI/CD統合**:
```yaml
# .github/workflows/security.yml
name: Security Scan
on: [push, pull_request]

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run OSV-Scanner
        uses: google/osv-scanner-action@v1
        with:
          scan-args: --lockfile package-lock.json
```

**メリット**:
- Google提供の脆弱性データベースを使用
- 高速スキャン
- 既知の脆弱性を即座に検出

---

### 被害が確認された場合の対応手順

1. **全トークンのローテーション**
   - npm認証トークン
   - GitHub Personal Access Token
   - AWS/GCP/Azureの認証情報
   - データベース接続情報
   - APIキー

2. **不審なリソースの削除**
   - 不審なリポジトリを削除
   - セルフホストランナーを削除
   - ワークフローファイル（`.github/workflows/discussion.yaml`）を削除

3. **リポジトリの状態確認**
   - プライベートリポジトリが強制的に公開化されていないか確認
   - リポジトリ設定の変更履歴を確認

4. **監査ログの確認**
   - GitHubの監査ログで不審なアクティビティを確認
   - npm publishの履歴を確認
   - CI/CDの実行履歴を確認

---

### 本プロジェクトへの実装推奨事項

#### 即座に実施すべき対策
```bash
# 1. .npmrc設定
echo "ignore-scripts=true" >> .npmrc

# 2. OSV-Scannerのインストールと実行
brew install osv-scanner
cd k_front
osv-scanner --lockfile package-lock.json

# 3. 脆弱性監査
npm audit
```

#### package.jsonに追加すべき設定
```json
{
  "scripts": {
    "preinstall": "npx @aikidosec/safe-chain",
    "security-check": "npm audit && osv-scanner --lockfile package-lock.json"
  },
  "lavamoat": {
    "allowScripts": {
      "sharp": true,
      "esbuild": true
    }
  }
}
```

#### CI/CDパイプラインに追加
```yaml
# .github/workflows/security-check.yml
name: Security Check
on:
  push:
    branches: [main, develop]
  pull_request:
  schedule:
    - cron: '0 9 * * 1'  # 毎週月曜日9時に実行

jobs:
  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Run npm audit
        run: npm audit --audit-level=high

      - name: Run OSV-Scanner
        uses: google/osv-scanner-action@v1
        with:
          scan-args: --lockfile k_front/package-lock.json
```

---

### 定期的なメンテナンス

#### 週次タスク
- [ ] `npm audit` の実行と結果確認
- [ ] `osv-scanner` での脆弱性スキャン
- [ ] 依存関係の更新確認（`npm outdated`）

#### 月次タスク
- [ ] `allowScripts` の見直し（不要なパッケージの削除）
- [ ] セキュリティパッチの適用
- [ ] GitHub監査ログの確認

#### 年次タスク
- [ ] 全シークレット・APIキーのローテーション
- [ ] セキュリティポリシーの見直し
- [ ] 依存関係の大幅な見直しと最新化