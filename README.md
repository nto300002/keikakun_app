# けいかくん - 個別支援計画管理システム_

福祉サービス事業所における「個別支援計画」の作成・管理業務をDX化するWebアプリケーション。
計画の進捗管理を効率化し、更新漏れを防ぐことで、職員の業務負担を軽減し、利用者へのサービス品質向上に貢献します。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

---

## 目次

- [主要機能](#主要機能)
- [技術スタック](#技術スタック)
- [アーキテクチャ](#アーキテクチャ)
- [環境構築](#環境構築)
- [デプロイ](#デプロイ)
- [開発ガイドライン](#開発ガイドライン)
- [ドキュメント](#ドキュメント)

---

## 主要機能

### 1. 個別支援計画管理
- 利用者ごとの計画サイクル管理（アセスメント → 原案作成 → 担当者会議 → 署名）
- ステップの順序制御と自動進捗管理
- PDF成果物のアップロード・管理
- 計画サイクルの自動生成

### 2. 期限アラート通知
- **メール通知**: 毎日9:00 JST、平日・祝日除く
- **Web Push通知**: ブラウザ・デバイスへのプッシュ通知
- **通知閾値のカスタマイズ**: メール・Push通知の開始日数を個別設定可能（5/10/20/30日前）
- **Google Calendar連携**: 更新期限を自動登録

### 3. 認証・セキュリティ
- **JWT認証**: Access Token + Refresh Token
- **2要素認証（2FA）**: TOTP（Time-based One-Time Password）
- **ロールベースアクセス制御（RBAC）**: owner / manager / employee
- **承認フロー**: 重要な操作には上位権限者の承認が必要
- **監査ログ**: 全ての重要操作を記録

### 4. 決済機能（Stripe）
- **サブスクリプション課金**: 月額3,000円（最大10人の利用者）
- **無料トライアル**: 10人まで無料
- **Webhook統合**: リアルタイム課金ステータス更新
- **カスタマーポータル**: 支払い方法変更、請求書確認、解約

### 5. ユーザー管理
- **3つのロール**:
  - `owner`（サービス責任者）: 全機能の操作、事業所管理
  - `manager`（マネージャー）: 利用者・計画の作成・更新・削除
  - `employee`（一般職員）: 全情報の閲覧のみ
- **権限変更申請**: 承認フローによる安全な権限変更

---

## 技術スタック

### バックエンド
| 技術 | バージョン | 用途 |
|------|-----------|------|
| **Python** | 3.12 | プログラミング言語 |
| **FastAPI** | 0.115.0 | Webフレームワーク |
| **SQLAlchemy** | 2.0.41 | ORM（非同期対応） |
| **PostgreSQL** | latest | データベース |
| **Alembic** | 1.16.4 | マイグレーション |
| **Pydantic** | 2.11.7 | データ検証 |
| **Stripe** | 7.0.0+ | 決済処理 |
| **pywebpush** | 1.14.0+ | Web Push通知 |
| **fastapi-mail** | 1.4.1 | メール送信 |
| **APScheduler** | 3.10.4 | バッチジョブ |
| **boto3** | latest | AWS S3連携 |

### フロントエンド
| 技術 | バージョン | 用途 |
|------|-----------|------|
| **Next.js** | 16.0.10 | Reactフレームワーク（App Router） |
| **React** | 19.1.2 | UIライブラリ |
| **TypeScript** | 5.x | プログラミング言語 |
| **Tailwind CSS** | 4.x | CSSフレームワーク |
| **Radix UI** | latest | UIコンポーネント |
| **React Hook Form** | 7.62.0 | フォーム管理 |
| **Zod** | 4.1.4 | スキーマ検証 |
| **Turbopack** | latest | 高速バンドラー |

### インフラ
| サービス | 用途 |
|---------|------|
| **Google Cloud Run** | バックエンドホスティング |
| **Vercel / Cloud Run** | フロントエンドホスティング |
| **PostgreSQL** | データベース |
| **AWS S3** | ファイルストレージ（画像、PDF） |
| **Google Cloud Build** | CI/CDパイプライン |
| **GitHub Actions** | テスト自動化 |

---

## アーキテクチャ

### バックエンド4層アーキテクチャ

```
API層 (endpoints/)       # HTTPリクエスト・レスポンス処理
  ↓
Services層 (services/)   # ビジネスロジック、複数CRUD操作の組み合わせ
  ↓
CRUD層 (crud/)          # 単一モデルのデータベース操作
  ↓
Models層 (models/)      # SQLAlchemyモデル定義
```

**設計原則**:
- 各層の責務を明確に分離
- 一方向の依存関係（API → Services → CRUD → Models）
- テスタビリティの向上
- 保守性・拡張性の確保

### フロントエンド構成

```
app/
├── (auth-pages)/        # 認証関連ページ
├── dashboard/           # ダッシュボード
├── recipients/          # 利用者管理
├── admin/              # 事業所管理（owner専用）
└── components/         # 共通コンポーネント
```

---

## 環境構築

### 前提条件

- Docker & Docker Compose
- Node.js 20+
- Python 3.12+

### バックエンドセットアップ

1. **リポジトリクローン**:
   ```bash
   git clone --recursive https://github.com/yourusername/keikakun_app.git
   cd keikakun_app
   ```

2. **環境変数設定**:
   ```bash
   cp .env.example .env
   # .env ファイルを編集して必要な環境変数を設定
   ```

   必要な環境変数（例）:
   ```
   DATABASE_URL=postgresql+psycopg://user:pass@localhost:5432/keikakun
   SECRET_KEY=your-secret-key
   STRIPE_SECRET_KEY=sk_test_...
   VAPID_PRIVATE_KEY=...
   VAPID_PUBLIC_KEY=...
   AWS_ACCESS_KEY_ID=...
   ```

3. **Dockerコンテナ起動**:
   ```bash
   docker-compose up -d backend
   ```

4. **マイグレーション実行**:
   ```bash
   docker exec keikakun_app-backend-1 alembic upgrade head
   ```

5. **テスト実行**:
   ```bash
   docker exec keikakun_app-backend-1 pytest tests/ -v
   ```

6. **バックエンドアクセス**:
   ```
   http://localhost:8000
   API ドキュメント: http://localhost:8000/docs
   ```

### フロントエンドセットアップ

1. **依存関係インストール**:
   ```bash
   cd k_front
   npm install
   ```

2. **環境変数設定**:
   ```bash
   cp .env.local.example .env.local
   # .env.local を編集
   ```

   必要な環境変数:
   ```
   NEXT_PUBLIC_API_URL=http://localhost:8000
   NEXT_PUBLIC_VAPID_PUBLIC_KEY=...
   ```

3. **開発サーバー起動**:
   ```bash
   npm run dev
   ```

4. **フロントエンドアクセス**:
   ```
   http://localhost:3000
   ```

---

## デプロイ

### CI/CDパイプライン

```
GitHub (main ブランチ push)
    ↓
GitHub Actions (cd-backend.yml)
    ↓ pytest実行
    ↓
Cloud Build (cloudbuild.yml)
    ↓ Dockerイメージビルド
    ↓
Artifact Registry
    ↓
Cloud Run デプロイ
```

### 環境変数の追加方法

新しい環境変数を追加する際は、以下の3ステップが必要です:

1. **GitHub Secrets に追加**
2. **`.github/workflows/cd-backend.yml` の `--substitutions` に追加**
3. **`k_back/cloudbuild.yml` の `--update-env-vars` に追加**

詳細は `md_files_design_note/environment_variables_setup.md` を参照してください。

### デプロイコマンド

```bash
# mainブランチにpush
git push origin main

# GitHub Actionsで自動デプロイ
# https://github.com/yourusername/keikakun_app/actions
```

---

## 開発ガイドライン

### コーディング規約

#### バックエンド（Python）

**インポートルール**:
```python
# ✅ 正しい
from app import crud
billing = await crud.billing.get_by_office_id(db=db, office_id=office_id)

# ❌ 誤り（循環参照の原因）
from app.crud.crud_billing import crud_billing
```

**非同期処理**:
```python
# 全てのI/O処理は非同期で実装
async def get_user(db: AsyncSession, user_id: UUID) -> User:
    result = await db.execute(select(User).where(User.id == user_id))
    return result.scalars().first()
```

**N+1問題の回避**:
```python
# selectinload を使用
stmt = select(Billing).options(selectinload(Billing.office))
```

**コメント・エラーメッセージ**: 日本語で記述
```python
# 課金ステータスを確認
if billing.billing_status == BillingStatus.past_due:
    raise HTTPException(
        status_code=403,
        detail="支払いが延滞しています。請求ページから更新してください"
    )
```

#### フロントエンド（TypeScript）

**型定義の徹底**:
```typescript
interface User {
  id: string;
  email: string;
  role: 'owner' | 'manager' | 'employee';
}
```

**エラーハンドリング**:
```typescript
try {
  await api.createRecipient(data);
} catch (error) {
  if (error instanceof ApiError && error.status === 402) {
    router.push('/admin/billing');
  }
}
```

### Git運用

**ブランチ戦略**:
- `main`: 本番環境
- `feature/*`: 機能開発
- `fix/*`: バグ修正

**コミットメッセージ**:
```
feat: 新機能追加
fix: バグ修正
docs: ドキュメント更新
refactor: リファクタリング
test: テスト追加・修正
chore: ビルド・設定変更

例: feat: VAPID環境変数をCI/CDパイプラインに追加
```

---

## ドキュメント

### 技術ドキュメント

- **[技術スタック詳細](./md_files_design_note/tech_stack.md)**: 全技術の詳細説明
- **[環境変数設定ガイド](./md_files_design_note/environment_variables_setup.md)**: CI/CD環境変数設定手順
- **[アーキテクチャガイド](./.claude/CLAUDE.md)**: 4層アーキテクチャ、設計原則
- **[面接想定質問集](./md_files_design_note/interview_questions.md)**: 技術面接対策

### タスク管理

- **[Web Push TODO](./md_files_design_note/task/*web_push/TODO.md)**: Web Push実装進捗
- **[実装状況レポート](./md_files_design_note/task/*web_push/implementation_status_report.md)**: 各フェーズの完了状況
- **[パフォーマンス・セキュリティレビュー](./md_files_design_note/task/*web_push/performance_security_review.md)**

---

## プロジェクト構成

```
keikakun_app/
├── .github/
│   └── workflows/
│       ├── cd-backend.yml          # バックエンドCI/CD
│       ├── ci-frontend.yml         # フロントエンドCI
│       └── security-check.yml      # セキュリティチェック
├── k_back/                         # バックエンド（サブモジュール）
│   ├── app/
│   │   ├── api/v1/endpoints/      # APIエンドポイント
│   │   ├── services/              # ビジネスロジック
│   │   ├── crud/                  # データベース操作
│   │   ├── models/                # SQLAlchemyモデル
│   │   ├── schemas/               # Pydanticスキーマ
│   │   └── core/                  # 設定、認証、メール、Push通知
│   ├── scripts/                   # 管理スクリプト
│   ├── tests/                     # テストコード
│   ├── cloudbuild.yml            # Cloud Build設定
│   └── requirements.txt          # Python依存関係
├── k_front/                       # フロントエンド（サブモジュール）
│   ├── app/
│   │   ├── dashboard/            # ダッシュボード
│   │   ├── recipients/           # 利用者管理
│   │   ├── admin/                # 事業所管理
│   │   └── components/           # 共通コンポーネント
│   ├── hooks/                    # カスタムフック
│   ├── types/                    # 型定義
│   └── package.json              # Node依存関係
├── md_files_design_note/         # ドキュメント
│   ├── tech_stack.md
│   ├── environment_variables_setup.md
│   └── interview_questions.md
├── .env.example                  # 環境変数テンプレート
├── docker-compose.yml            # Docker設定
└── README.md                     # このファイル
```

---

## 主要なバッチ処理

### 期限アラート通知バッチ

**実行頻度**: 毎日0:00 UTC（9:00 JST）、平日・祝日除く

**処理内容**:
1. 全事業所の利用者を取得
2. 更新期限が閾値以内の利用者を抽出
3. スタッフの通知設定に基づいてフィルタリング
4. メール + Web Push通知を送信

**手動実行**:
```bash
# ドライラン（送信せず確認のみ）
docker exec keikakun_app-backend-1 python3 scripts/run_deadline_notification.py --dry-run

# 本番実行
docker exec keikakun_app-backend-1 python3 scripts/run_deadline_notification.py
```

---

## トラブルシューティング

### バックエンド

**MissingGreenletエラー**:
- 原因: 非同期コンテキスト外でのリレーション属性アクセス
- 解決: `selectinload()` を使用してリレーションを事前ロード

**VAPID認証エラー（403 Forbidden）**:
- 原因: フロントエンドとバックエンドのVAPID公開鍵が不一致
- 解決: 両方の環境変数を確認し、同じ鍵を使用

**Web Push通知が届かない**:
- 410 Goneエラー: 購読期限切れ → 自動的にDBから削除される
- Service Worker未登録: ブラウザのキャッシュクリア後、再登録が必要

### フロントエンド

**ビルドエラー**:
```bash
# node_modulesを削除して再インストール
rm -rf node_modules package-lock.json
npm install
```

**Lintエラー**:
```bash
npm run lint
```

---

## セキュリティ

- **HTTPS強制**: 本番環境では必須
- **CSRF保護**: fastapi-csrf-protect
- **SQL Injection防止**: SQLAlchemyのパラメータ化クエリ
- **XSS防止**: Pydanticバリデーション、Reactデフォルトエスケープ
- **認証トークン**: HttpOnly Cookie
- **監査ログ**: 全ての重要操作を記録

---

## ライセンス

MIT License

---

## 貢献

プルリクエスト歓迎です。大きな変更の場合は、まずissueを開いて変更内容を議論してください。

---

## サポート

質問やバグ報告は、GitHubのIssuesまでお願いします。

---

**最終更新**: 2026-01-20
**バージョン**: 1.0.0
