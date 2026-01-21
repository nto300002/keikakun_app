# 2次面接想定質問集 - けいかくんポートフォリオ

## 1. 技術選定・アーキテクチャ設計

### 基本設計
- **なぜFastAPIを選んだのですか？他のフレームワーク（Django, Flask等）と比較してどうですか？**
  - 非同期処理のパフォーマンス
  - 自動API ドキュメント生成（OpenAPI/Swagger）
  - Pydanticによる型安全なバリデーション
  - 現代的なPython 3.10+の型ヒント活用

- **Next.js 16（App Router）を採用した理由は？Pages Routerとの違いは？**
  - Server ComponentsとClient Componentsの使い分け
  - ファイルベースルーティング
  - ビルドイン最適化（画像、フォント、スクリプト）
  - Turbopackによる高速開発体験

- **4層アーキテクチャを採用した理由と、各層の責務をどう設計しましたか？**
  - API層 → Services層 → CRUD層 → Models層
  - 関心の分離（Separation of Concerns）
  - テスタビリティの向上
  - 保守性・拡張性の確保

### データベース設計
- **SQLAlchemyで非同期（AsyncSession）を採用した理由は？同期版との違いは？**
  - I/O待機時の効率化
  - 並行リクエスト処理能力の向上
  - FastAPIの非同期エンドポイントとの親和性

- **N+1問題をどう防いでいますか？具体的な実装例は？**
  - `selectinload()`による事前ロード
  - リレーション定義の適切な設計
  - クエリ最適化の意識

- **PostgreSQLを選んだ理由は？他のDB（MySQL, MongoDB等）と比較して？**
  - JSONB型のサポート（notification_preferences等）
  - トランザクション整合性
  - 豊富な拡張機能
  - GCPとの統合性

## 2. 認証・セキュリティ

### 認証設計
- **JWT認証を実装する上で、どのような点に気をつけましたか？**
  - トークンのライフタイム設定（Access Token: 30分、Refresh Token: 7日）
  - HttpOnly Cookieでの保管
  - トークンリフレッシュフロー
  - ログアウト時のトークン無効化

- **2要素認証（TOTP）を実装した経緯と、苦労した点は？**
  - pyotpライブラリの選定理由
  - QRコード生成（qrcode[pil]）
  - バックアップコードの管理
  - ユーザビリティとセキュリティのバランス

- **CSRF攻撃への対策はどう実装していますか？**
  - fastapi-csrf-protectの導入
  - CSRFトークンの生成・検証フロー
  - SameSite Cookie属性の設定

### セキュリティ対策
- **SQL Injection、XSS攻撃への対策を説明してください**
  - SQLAlchemyのパラメータ化クエリ
  - Pydanticによる入力検証
  - HTMLエスケープ
  - Content Security Policy（CSP）

- **個人情報（PII）をどう保護していますか？**
  - ログ出力時のマスキング（`mask_email()`）
  - データベース暗号化
  - アクセス制御（RBAC: Role-Based Access Control）
  - 監査ログ（audit_logs）による追跡

- **Stripe Webhookの署名検証はどう実装していますか？**
  - `stripe.Webhook.construct_event()`による検証
  - リプレイ攻撃への対策（タイムスタンプ検証）
  - 冪等性の確保（webhook_eventsテーブル）

## 3. Web Push通知の実装

### 技術的深掘り
- **Web Push通知を実装する上で、最も苦労した点は何ですか？**
  - **410 Goneエラーのハンドリングバグ発見と修正**
    - 問題: `requests.Response.__bool__()`がFalseを返す仕様
    - 解決: `is not None`チェックへの変更
    - タプルアンパック漏れの修正

- **VAPID認証の仕組みを説明してください**
  - Voluntary Application Server Identification
  - EC P-256鍵ペア生成（py-vapid）
  - JWT形式のVAPIDヘッダー
  - プッシュサービスプロバイダーへの認証

- **Service Workerのライフサイクルとpushイベントハンドリングを説明してください**
  - install → activate → push → notificationclick
  - `self.skipWaiting()`によるアクティベーション制御
  - バックグラウンドでの通知表示

### iOS対応
- **iOS SafariでのWeb Push対応における制約と対策は？**
  - PWA（ホーム画面追加）モードのみサポート
  - `navigator.standalone`による検出
  - ユーザーへの説明UI実装
  - フォールバックとしてのメール通知

### エラーハンドリング
- **期限切れ購読の自動クリーンアップをどう実装しましたか？**
  - 410/404エラーの検出
  - `should_delete`フラグによる削除判定
  - DBからの購読削除（`delete_by_endpoint()`）
  - リトライロジック（一時的エラーとの区別）

## 4. 決済機能（Stripe）

### Stripe統合
- **Stripeのサブスクリプションモデルをどう設計しましたか？**
  - 無料トライアル → early_payment → active → past_due → canceled
  - Priceベースの料金プラン設計
  - メタデータによる事業所情報の紐付け

- **Webhookイベント処理の冪等性をどう担保していますか？**
  - `webhook_events`テーブルによる重複検出
  - `stripe_event_id`のユニーク制約
  - トランザクション境界の適切な設定

- **課金ステータスによる機能制限をどう実装していますか？**
  - `past_due`時の読み取り専用モード
  - ミドルウェアレベルでの制御
  - ユーザーへの適切なエラーメッセージ

### エッジケース対応
- **トライアル期間中の早期支払い対応はどうしていますか？**
  - `customer.subscription.created`イベントでのステータス更新
  - `trial_end`と`current_period_end`の正しい解釈
  - 請求サイクルの調整

- **支払い失敗時のリトライロジックは？**
  - Stripe側の自動リトライ設定
  - `invoice.payment_failed`イベントハンドリング
  - ユーザーへの通知（メール）

## 5. バッチ処理・非同期タスク

### スケジューラー設計
- **APSchedulerを採用した理由と、他の選択肢（Celery等）との比較は？**
  - シンプルな統合（FastAPI起動時に同期）
  - Cloud Runでの動作保証
  - 軽量な依存関係
  - （将来的にCelery検討の余地あり）

- **期限アラートバッチの処理フローを説明してください**
  - 毎日0:00 UTC（9:00 JST）実行
  - 平日・祝日判定（jpholiday）
  - 事業所ごとの閾値フィルタリング
  - メール + Web Push並列送信

- **バッチ処理のエラーハンドリングとリトライ戦略は？**
  - tenacityによる指数バックオフリトライ（最大3回）
  - タイムアウト設定（30秒）
  - Semaphoreによるレートリミット（同時5件）
  - エラーログの詳細記録

### パフォーマンス最適化
- **大量の通知送信時のパフォーマンス対策は？**
  - 非同期処理（asyncio）
  - バッチサイズの制御
  - データベースコネクションプール
  - 将来的な改善案（Celeryによる分散処理）

## 6. フロントエンド設計

### 状態管理
- **React 19の新機能を活用していますか？どのように？**
  - Server Actionsの検討
  - useOptimisticの活用
  - Suspenseによるローディング状態管理

- **フォーム管理にReact Hook Formを選んだ理由は？**
  - 再レンダリングの最小化
  - Zodとの統合による型安全なバリデーション
  - 非制御コンポーネントのパフォーマンス利点

### UI/UX設計
- **Radix UIを採用した理由は？他のUIライブラリとの比較は？**
  - アクセシビリティ標準（ARIA）への準拠
  - ヘッドレスコンポーネントの柔軟性
  - Tailwind CSSとの親和性
  - カスタマイズ性の高さ

- **ダークモード対応をどう実装していますか？**
  - next-themesによるテーマ管理
  - Tailwindの`dark:`クラス活用
  - システム設定との同期

### パフォーマンス
- **Next.js 16のTurbopackによる開発体験の改善点は？**
  - ホットリロード速度の向上
  - バンドルサイズの最適化
  - インクリメンタルビルド

- **画像最適化はどう実装していますか？**
  - Next.js Image コンポーネント
  - AWS S3への保存
  - レスポンシブ画像の自動生成

## 7. インフラ・DevOps

### Docker構成
- **マルチステージビルドを採用した理由と、各ステージの役割は？**
  - base: 共通依存関係
  - production: 本番環境（gunicorn）
  - development: 開発環境（uvicorn + reload）
  - イメージサイズの最適化
  - セキュリティ向上（非rootユーザー）

- **開発環境と本番環境の違いをどう管理していますか？**
  - .env ファイルによる環境変数分離
  - Docker Composeの環境別設定
  - Cloud Runの環境変数管理

### Cloud Run デプロイ
- **Cloud Runを選んだ理由は？他のサービス（ECS, App Engine等）との比較は？**
  - サーバーレス（自動スケーリング）
  - コンテナベースのデプロイ
  - 従量課金モデル
  - GCPエコシステムとの統合

- **コールドスタート問題への対策は？**
  - 最小インスタンス数の設定
  - アプリケーション起動時間の最適化
  - ヘルスチェックエンドポイント

### CI/CD
- **現在のデプロイフローと、今後の改善案は？**
  - 現状: 手動デプロイ
  - 改善案: GitHub Actionsによる自動デプロイ
    - Lintチェック
    - テスト実行
    - ビルド・デプロイ
    - ロールバック戦略

## 8. テスト戦略

### バックエンドテスト
- **pytest-asyncioを使った非同期テストで工夫した点は？**
  - フィクスチャーのライフサイクル管理
  - トランザクションロールバックによるデータ分離
  - モックの適切な活用

- **テストカバレッジはどの程度ですか？重点的にテストしている箇所は？**
  - 認証・認可ロジック
  - 決済処理（Stripe Webhook）
  - セキュリティ（SQL Injection, XSS）
  - ビジネスロジック（Services層）

### フロントエンドテスト
- **E2Eテストの実装計画は？**
  - Playwright検討中
  - クリティカルパスの優先テスト
    - ログインフロー
    - 個別支援計画作成
    - 決済フロー

## 9. 問題解決・トラブルシューティング

### 具体的なバグ修正事例
- **Web Push通知が2回目以降届かなかった問題をどう解決しましたか？**
  1. **問題の特定**:
     - ログ分析: 410エラーは出ているがDB削除されていない
     - デバッグスクリプト作成: `test_webpush_exception.py`

  2. **根本原因の発見**:
     - **バグ1**: タプルアンパック漏れ
       - `success = await send_push_notification()`
       - タプルは常にTruthyなので`if success:`が常にTrue
     - **バグ2**: `requests.Response.__bool__()`の挙動
       - 410エラーでも`bool(e.response)`がFalseを返す

  3. **修正内容**:
     - タプルを適切にアンパック: `success, should_delete = ...`
     - `is not None`チェックに変更

  4. **検証**:
     - クリーンアップスクリプトで期限切れ購読を削除
     - バッチ処理で正常動作を確認

- **MissingGreenletエラーが発生した時、どう対処しましたか？**
  - 原因: 非同期コンテキスト外でのリレーション属性アクセス
  - 解決: `selectinload()`による事前ロード
  - 学び: SQLAlchemyの遅延ロードの仕組み理解

### デバッグ手法
- **本番環境でのデバッグはどう行いますか？**
  - 構造化ログ（JSON形式）
  - ログレベルの適切な設定
  - PII（個人情報）のマスキング
  - 監査ログによる操作追跡
  - Cloud Loggingでの集約・分析

## 10. ビジネス理解・要件定義

### ドメイン知識
- **福祉サービス事業所の業務フローをどう理解しましたか？**
  - 個別支援計画の作成・更新サイクル
  - アセスメントの実施タイミング
  - 更新期限管理の重要性
  - 多職種連携の必要性

- **なぜ「期限アラート」機能が重要なのですか？**
  - 法令遵守（障害者総合支援法）
  - サービス継続性の担保
  - 業務効率化（手動管理からの脱却）
  - 利用者への適切なサービス提供

### 要件定義
- **閾値カスタマイズ機能を追加した背景は？**
  - 事業所ごとの業務フローの違い
  - 通知疲れの防止
  - ユーザーの柔軟性要求への対応
  - メールとPush通知の使い分けニーズ

- **マルチテナント設計をどう実装していますか？**
  - 事業所（Office）によるデータ分離
  - office_id による絞り込み
  - RLS（Row Level Security）の検討余地

## 11. チーム開発・協働

### コード品質
- **コードレビューで重視していることは？**
  - アーキテクチャ違反のチェック（4層構造遵守）
  - セキュリティ脆弱性の確認
  - パフォーマンスへの影響
  - テストの網羅性
  - コメントの適切性（日本語）

- **技術的負債をどう管理していますか？**
  - TODOコメントによる追跡
  - 優先度付け（セキュリティ > パフォーマンス > リファクタリング）
  - スプリント計画への組み込み

### ドキュメント
- **なぜコメントやエラーメッセージを日本語にしていますか？**
  - ターゲットユーザーが日本の福祉事業所
  - 保守性の向上（日本人開発者向け）
  - ユーザーサポートの効率化
  - （英語でのロジック説明とのバランス）

- **アーキテクチャドキュメント（.claude/CLAUDE.md）の目的は？**
  - 新規参画メンバーのオンボーディング
  - 設計原則の共有
  - アンチパターンの防止
  - AI（Claude）との協働開発指針

## 12. スケーラビリティ・パフォーマンス

### 将来の拡張性
- **ユーザー数が10倍になった場合、どこがボトルネックになりますか？**
  - データベース接続数
  - バッチ処理の実行時間
  - Web Push通知の送信数
  - Cloud Runのインスタンス数制限

- **その対策は？**
  - Redisによるキャッシング
  - 読み取りレプリカの導入
  - Celeryによる分散タスクキュー
  - CDN導入（静的コンテンツ）
  - データベースシャーディング検討

### 監視・運用
- **システム監視はどう実装していますか？**
  - Cloud Loggingによるログ集約
  - エラー率の追跡
  - レスポンスタイムの監視
  - （改善案: Datadogなどの導入）

- **アラート設定の基準は？**
  - エラー率 > 5%
  - レスポンスタイム > 2秒
  - バッチ処理失敗
  - Stripe Webhook処理失敗

## 13. 技術的挑戦・学び

### 新技術の習得
- **このプロジェクトで新たに学んだ技術は？**
  - Web Push API（VAPID認証、Service Worker）
  - Stripe Subscriptions API
  - Google Calendar API
  - SQLAlchemyの非同期処理
  - Next.js App Router

- **最も苦労した技術と、それをどう克服しましたか？**
  - （具体的なエピソードを語る）
  - 学習アプローチ
  - 情報源（公式ドキュメント、Stack Overflow等）
  - 試行錯誤の過程

### 技術的判断
- **技術選定で間違えたと思う点はありますか？**
  - 正直な反省と学び
  - 代替案の検討
  - 次回への活かし方

## 14. 個人の貢献と成長

### プロジェクトでの役割
- **このプロジェクトであなたが最も貢献した部分は？**
  - 具体的な機能実装
  - アーキテクチャ設計
  - 問題解決
  - ドキュメント整備

- **失敗から学んだことは？**
  - 具体的な失敗事例
  - 原因分析
  - 改善策
  - 成長のきっかけ

### キャリアビジョン
- **このプロジェクトで培ったスキルを、どう活かしたいですか？**
  - バックエンド開発力
  - インフラ設計能力
  - 問題解決力
  - セキュリティ意識

---

## 面接対策のポイント

### 技術的な深掘りに備える
1. **「なぜ」を説明できるように**
   - 技術選定の理由
   - 設計判断の根拠
   - トレードオフの考慮

2. **具体的な数値を示す**
   - パフォーマンス改善（処理時間、レスポンスタイム）
   - テストカバレッジ
   - ユーザー数、データ量

3. **失敗談も準備**
   - 誠実な態度
   - 学びのプロセス
   - 改善への取り組み

### STAR法で回答を構造化
- **S (Situation)**: 状況説明
- **T (Task)**: 課題・タスク
- **A (Action)**: 取った行動
- **R (Result)**: 結果・学び

### デモ準備
- 実際の画面を見せながら説明
- コードの重要部分をハイライト
- アーキテクチャ図を用意

---

## 15. 受託開発を想定した質問

### クライアントコミュニケーション
- **要件が曖昧なクライアントにどう対応しますか？**
  - ヒアリングシートの準備
  - 5W1Hでの質問
  - モックアップやプロトタイプでの認識合わせ
  - 定期的な進捗共有とフィードバック収集

- **仕様変更の依頼が頻繁に来る場合、どう対処しますか？**
  - 変更管理プロセスの確立
  - 影響範囲の分析と見積もり
  - 優先度の協議
  - 追加工数の明確化
  - アジャイル開発での柔軟な対応

- **技術的に実現困難な要望を受けた時、どう説明しますか？**
  - 技術的制約を分かりやすく説明
  - 代替案の提示（3つ程度の選択肢）
  - メリット・デメリットの比較表
  - コスト・期間・品質のトレードオフ説明

### プロジェクト管理
- **スケジュール遅延が発生した場合、どう対応しますか？**
  - 早期のエスカレーション
  - 遅延原因の特定と分析
  - リカバリープランの提示（スコープ調整、リソース追加等）
  - クライアントへの透明性のある報告
  - 再発防止策の検討

- **複数案件を並行で進める場合、どう優先順位をつけますか？**
  - 期限の近さ
  - ビジネスインパクト
  - 依存関係
  - クライアントの重要度
  - タイムボックス管理

- **品質とスピードのバランスをどう取りますか？**
  - MVP（Minimum Viable Product）の定義
  - 段階的リリース（Phase 1, 2, 3...）
  - 自動テストによる品質担保
  - コードレビューの効率化
  - 技術的負債の計画的な返済

### 見積もり・コスト管理
- **工数見積もりはどう行いますか？**
  - WBS（Work Breakdown Structure）による分解
  - 類似案件の実績参照
  - バッファの確保（リスク管理）
  - 楽観値・悲観値・最頻値の3点見積もり
  - チームメンバーへのヒアリング

- **想定外のコスト増加が発生した場合、どう対処しますか？**
  - 原因の特定（仕様変更、技術的課題、見積もりミス）
  - クライアントへの早期報告
  - コスト削減案の提示
  - スコープ調整の提案
  - 今後の見積もり精度向上策

### ドキュメント・納品
- **納品物として何を用意しますか？**
  - ソースコード（GitHubリポジトリ）
  - 設計書（アーキテクチャ図、ER図、API仕様書）
  - 操作マニュアル（管理者用、エンドユーザー用）
  - 環境構築手順書
  - テスト仕様書・結果報告書
  - 保守運用マニュアル

- **保守運用を想定した設計をどう行いますか？**
  - ログの充実（エラー追跡、監査証跡）
  - 監視・アラート設定
  - バックアップ・リストア手順
  - ロールバック戦略
  - ドキュメントの保守性

### トラブル対応
- **本番環境で重大なバグが発見された場合、どう対処しますか？**
  1. **初動対応**:
     - 影響範囲の特定（ユーザー数、データ）
     - 緊急度の判断（即座にロールバックすべきか）
     - ステークホルダーへの報告

  2. **対応実施**:
     - ホットフィックス or ロールバック
     - テスト環境での動作確認
     - 段階的なデプロイ（カナリアリリース）

  3. **事後対応**:
     - 根本原因分析（RCA: Root Cause Analysis）
     - 再発防止策の策定
     - ポストモーテムドキュメント作成

- **クライアントからクレームが来た場合、どう対応しますか？**
  - まず謝罪と傾聴
  - 事実確認と原因調査
  - 対応方針の提示
  - 迅速な対応と進捗報告
  - 再発防止策の共有

### チーム協働
- **チームメンバーのスキルにばらつきがある場合、どうしますか？**
  - タスク割り当ての工夫（スキルレベルに応じた難易度）
  - ペアプログラミング・モブプログラミング
  - コードレビューでの知識共有
  - 勉強会の開催
  - ドキュメント・ナレッジベースの整備

- **意見が対立した場合、どう解決しますか？**
  - データに基づく議論（パフォーマンス、保守性、コスト）
  - PoC（Proof of Concept）での検証
  - 第三者（リードエンジニア、アーキテクト）への相談
  - 期限を決めて決断
  - 決定後はチーム全体でコミット

## 16. Python基礎知識を問う質問

### 言語仕様・文法
- **Pythonのデコレータとは何ですか？実装例を説明してください**
  ```python
  # けいかくんでの使用例: FastAPIのルーティング
  @router.get("/api/v1/users/me")
  async def get_current_user(
      current_user: User = Depends(get_current_user)
  ):
      return current_user

  # 認証デコレータの実装例
  def require_permission(permission: str):
      def decorator(func):
          @wraps(func)
          async def wrapper(*args, **kwargs):
              # 権限チェックロジック
              if not has_permission(permission):
                  raise HTTPException(status_code=403)
              return await func(*args, **kwargs)
          return wrapper
      return decorator
  ```

- **`*args`と`**kwargs`の違いは？どういう時に使いますか？**
  - `*args`: 可変長位置引数（タプル）
  - `**kwargs`: 可変長キーワード引数（辞書）
  - 用途: ラッパー関数、柔軟な関数設計

- **リスト内包表記とジェネレータ式の違いは？**
  ```python
  # リスト内包表記（メモリに全て展開）
  squares = [x**2 for x in range(1000)]

  # ジェネレータ式（遅延評価）
  squares = (x**2 for x in range(1000))

  # けいかくんでの使用例: 大量データの処理
  alerts = (create_alert(user) for user in users if user.needs_alert)
  ```

- **`__init__`と`__new__`の違いは？**
  - `__new__`: インスタンス生成（クラスメソッド）
  - `__init__`: インスタンス初期化（インスタンスメソッド）
  - シングルトンパターンでの`__new__`活用

### データ構造・アルゴリズム
- **リスト、タプル、セット、辞書の使い分けは？**
  - **リスト**: 順序あり、可変、重複可
  - **タプル**: 順序あり、不変、重複可（関数の返り値等）
  - **セット**: 順序なし、可変、重複不可（ユニーク要素）
  - **辞書**: キー・バリュー、順序保持（Python 3.7+）

- **浅いコピーと深いコピーの違いは？**
  ```python
  import copy

  # 浅いコピー（ネストされたオブジェクトは参照）
  shallow = original.copy()

  # 深いコピー（全ての階層をコピー）
  deep = copy.deepcopy(original)

  # けいかくんでの使用例: 設定オブジェクトの複製
  default_prefs = {"email": True, "push": False}
  user_prefs = copy.deepcopy(default_prefs)
  ```

- **計算量（Big O記法）を意識したコーディングをしていますか？**
  - O(1): 辞書のキーアクセス
  - O(n): リストの線形探索
  - O(n log n): ソート処理
  - O(n²): ネストループ（避けるべき）
  - けいかくんでの最適化例: リスト探索を辞書化

### 非同期処理
- **`async`/`await`の仕組みを説明してください**
  ```python
  # 同期処理（ブロッキング）
  def send_email(email):
      time.sleep(1)  # メール送信待機
      return "sent"

  # 非同期処理（ノンブロッキング）
  async def send_email_async(email):
      await asyncio.sleep(1)  # 他のタスクに制御を渡す
      return "sent"

  # けいかくんでの使用例
  async def send_notifications(users):
      tasks = [send_push_notification(user) for user in users]
      results = await asyncio.gather(*tasks)  # 並行実行
  ```

- **`asyncio.gather`と`asyncio.wait`の違いは？**
  - `gather`: 全タスク完了を待つ、順序保持、例外伝播
  - `wait`: 柔軟な完了条件（FIRST_COMPLETED, ALL_COMPLETED）

- **非同期処理でのエラーハンドリングはどうしますか？**
  ```python
  async def safe_send_notification(user):
      try:
          await send_notification(user)
      except Exception as e:
          logger.error(f"Failed to send to {user.id}: {e}")
          return None
      return user.id

  # 複数タスクでの個別エラーハンドリング
  results = await asyncio.gather(
      *[safe_send_notification(u) for u in users],
      return_exceptions=True  # 例外を結果リストに含める
  )
  ```

### オブジェクト指向
- **クラスの継承と合成（コンポジション）の使い分けは？**
  - **継承**: is-a関係（Car is a Vehicle）
  - **合成**: has-a関係（Car has an Engine）
  - けいかくんでの例: CRUDBaseクラスの継承

- **ABCクラス（抽象基底クラス）を使ったことはありますか？**
  ```python
  from abc import ABC, abstractmethod

  class NotificationSender(ABC):
      @abstractmethod
      async def send(self, message: str) -> bool:
          pass

  class EmailSender(NotificationSender):
      async def send(self, message: str) -> bool:
          # メール送信実装
          pass
  ```

- **`@property`デコレータの使い方と利点は？**
  ```python
  class User:
      def __init__(self, first_name, last_name):
          self._first_name = first_name
          self._last_name = last_name

      @property
      def full_name(self):
          return f"{self._first_name} {self._last_name}"

      @full_name.setter
      def full_name(self, value):
          self._first_name, self._last_name = value.split(" ", 1)
  ```

### 標準ライブラリ
- **`collections`モジュールの便利なクラスは？**
  - `defaultdict`: デフォルト値付き辞書
  - `Counter`: 要素のカウント
  - `deque`: 両端キュー（高速な追加・削除）
  - `namedtuple`: 名前付きタプル

- **`datetime`の`timezone.utc`と`utcnow()`の違いは？**
  ```python
  # 非推奨（タイムゾーン情報なし）
  now = datetime.utcnow()

  # 推奨（タイムゾーン情報あり）
  now = datetime.now(timezone.utc)

  # けいかくんでの統一: 常にtimezone.utcを使用
  ```

- **`contextlib`の`contextmanager`を使ったことはありますか？**
  ```python
  from contextlib import asynccontextmanager

  @asynccontextmanager
  async def get_db_session():
      session = AsyncSessionLocal()
      try:
          yield session
          await session.commit()
      except Exception:
          await session.rollback()
          raise
      finally:
          await session.close()
  ```

### パフォーマンス・メモリ管理
- **`__slots__`を使ったことはありますか？用途は？**
  - メモリ使用量削減（`__dict__`を作らない）
  - 属性の固定化
  - 大量のインスタンス生成時に有効

- **GIL（Global Interpreter Lock）とは？その影響は？**
  - CPythonの実装制約（一度に1つのスレッドのみPythonコード実行）
  - マルチスレッドでのCPUバウンド処理は並列化されない
  - I/Oバウンド処理には影響少ない
  - 対策: multiprocessing、asyncio、C拡張

- **メモリリークを防ぐために意識していることは？**
  - 循環参照の回避
  - ファイル・DB接続の確実なクローズ（`with`文）
  - 大きなオブジェクトの明示的な削除（`del`）
  - メモリプロファイリング（memory_profiler）

## 17. Web基礎知識を問う質問

### HTTP/HTTPS
- **HTTPメソッドの使い分けを説明してください**
  - **GET**: リソース取得（冪等、キャッシュ可能）
  - **POST**: リソース作成（非冪等）
  - **PUT**: リソース更新（冪等、全体更新）
  - **PATCH**: リソース部分更新（非冪等）
  - **DELETE**: リソース削除（冪等）
  - けいかくんでの設計: RESTful API原則に従う

- **ステータスコードの使い分けは？**
  - **200 OK**: 成功
  - **201 Created**: リソース作成成功
  - **204 No Content**: 成功（レスポンスボディなし）
  - **400 Bad Request**: クライアントエラー（バリデーションエラー）
  - **401 Unauthorized**: 認証エラー
  - **403 Forbidden**: 認可エラー（権限不足）
  - **404 Not Found**: リソース不在
  - **409 Conflict**: リソース競合
  - **422 Unprocessable Entity**: バリデーションエラー（詳細）
  - **500 Internal Server Error**: サーバーエラー

- **HTTPSの仕組みを簡単に説明してください**
  1. クライアントがサーバーにリクエスト
  2. サーバーがSSL証明書を送信
  3. クライアントが証明書を検証
  4. 共通鍵を生成・交換（公開鍵暗号方式）
  5. 共通鍵で暗号化通信
  - けいかくんでの実装: Cloud Runの自動HTTPS

### Cookie・セッション
- **Cookieの属性（Secure, HttpOnly, SameSite）の意味は？**
  - **Secure**: HTTPS接続でのみ送信
  - **HttpOnly**: JavaScriptからアクセス不可（XSS対策）
  - **SameSite**: CSRF対策
    - `Strict`: 同一サイトのみ
    - `Lax`: 一部のクロスサイトリクエストで送信
    - `None`: 全てのリクエストで送信（Secure必須）

- **セッション管理の方法を説明してください**
  - **Cookie-based**: セッションIDをCookieに保存
  - **Token-based（JWT）**: ステートレス、スケーラブル
  - **Database-based**: セッション情報をDBに保存
  - けいかくんの実装: JWT + HttpOnly Cookie

- **JWTのペイロードに機密情報を入れてはいけない理由は？**
  - Base64エンコードのみ（暗号化ではない）
  - 誰でもデコード可能
  - 署名は改ざん検知のみ（内容の秘匿ではない）

### REST API設計
- **RESTful APIの設計原則は？**
  - リソース指向（名詞でURL設計）
  - 適切なHTTPメソッド使用
  - ステートレス
  - 階層構造（`/offices/123/staffs/456`）
  - クエリパラメータ（フィルタ、ソート、ページング）

- **API バージョニングの方法は？**
  - URLパス: `/api/v1/users`（けいかくんの採用方式）
  - クエリパラメータ: `/api/users?version=1`
  - ヘッダー: `Accept: application/vnd.api.v1+json`

- **ページネーションの実装方法は？**
  ```python
  # オフセットベース
  GET /api/v1/users?limit=20&offset=40

  # カーソルベース（大規模データに適している）
  GET /api/v1/users?limit=20&cursor=eyJpZCI6MTIzfQ==

  # けいかくんの実装例
  @router.get("/welfare-recipients")
  async def get_recipients(
      limit: int = Query(20, ge=1, le=100),
      offset: int = Query(0, ge=0),
      db: AsyncSession = Depends(get_db)
  ):
      # ...
  ```

### CORS（Cross-Origin Resource Sharing）
- **CORSとは何ですか？なぜ必要ですか？**
  - ブラウザのセキュリティ機能
  - 異なるオリジンからのリクエスト制御
  - プリフライトリクエスト（OPTIONS）

- **CORSの設定をどう実装しますか？**
  ```python
  from fastapi.middleware.cors import CORSMiddleware

  app.add_middleware(
      CORSMiddleware,
      allow_origins=[settings.FRONTEND_URL],  # 特定オリジンのみ許可
      allow_credentials=True,  # Cookie送信を許可
      allow_methods=["GET", "POST", "PUT", "DELETE"],
      allow_headers=["*"],
  )
  ```

### WebSocket
- **WebSocketとHTTPの違いは？**
  - HTTP: リクエスト・レスポンス型（単方向）
  - WebSocket: 双方向通信、リアルタイム
  - 用途: チャット、通知、ライブアップデート

- **けいかくんでリアルタイム機能を追加するなら、どう実装しますか？**
  - FastAPIのWebSocketサポート活用
  - または SSE（Server-Sent Events）
  - または ポーリング（シンプルだが非効率）

### キャッシュ戦略
- **HTTP キャッシュヘッダーの種類は？**
  - **Cache-Control**: キャッシュ制御（max-age, no-cache, no-store）
  - **ETag**: リソース識別子（変更検知）
  - **Last-Modified**: 最終更新日時
  - **Expires**: 有効期限

- **サーバーサイドキャッシュの実装例は？**
  - Redis（けいかくんの今後の導入予定）
  - メモリキャッシュ（functools.lru_cache）
  - データベースクエリ結果のキャッシュ

### セキュリティ
- **OWASP Top 10を知っていますか？対策は？**
  1. **Broken Access Control**: RBAC実装、認可チェック
  2. **Cryptographic Failures**: HTTPS、パスワードハッシュ化
  3. **Injection**: パラメータ化クエリ、入力検証
  4. **Insecure Design**: セキュアな設計原則
  5. **Security Misconfiguration**: デフォルト設定の変更
  6. **Vulnerable Components**: 依存関係の更新
  7. **Authentication Failures**: 2FA、レートリミット
  8. **Software and Data Integrity**: 署名検証、CI/CDセキュリティ
  9. **Security Logging Failures**: 監査ログ、異常検知
  10. **SSRF**: URL検証、内部ネットワーク分離

- **XSS（Cross-Site Scripting）対策は？**
  - 入力サニタイゼーション
  - 出力エスケープ
  - Content Security Policy（CSP）
  - HttpOnly Cookie
  - けいかくんの実装: Pydanticバリデーション、Reactのデフォルトエスケープ

- **SQL Injectionの防ぎ方は？**
  - ORMの使用（SQLAlchemy）
  - パラメータ化クエリ
  - プレースホルダーの使用
  - 生SQLの回避
  ```python
  # ❌ 危険（SQL Injection脆弱性）
  query = f"SELECT * FROM users WHERE id = {user_id}"

  # ✅ 安全（パラメータ化）
  query = select(User).where(User.id == user_id)
  ```

### パフォーマンス最適化
- **Webアプリケーションのパフォーマンスボトルネックは？**
  - データベースクエリ（N+1問題）
  - ネットワークレイテンシ
  - 画像・アセットのサイズ
  - JavaScriptバンドルサイズ
  - サーバー処理時間

- **具体的な最適化手法は？**
  - **データベース**: インデックス、クエリ最適化、コネクションプール
  - **ネットワーク**: CDN、HTTP/2、圧縮（gzip, brotli）
  - **フロントエンド**: コード分割、遅延ロード、画像最適化
  - **サーバー**: 非同期処理、キャッシュ、水平スケーリング

### ブラウザAPI
- **Service Workerとは何ですか？用途は？**
  - バックグラウンドで動作するJavaScriptワーカー
  - プロキシサーバーのような役割
  - 用途:
    - Web Push通知（けいかくんで実装）
    - オフライン対応（PWA）
    - キャッシュ戦略
    - バックグラウンド同期

- **Web Push通知の仕組みを簡単に説明してください**
  1. Service Worker登録
  2. Push購読（ブラウザ → プッシュサービス）
  3. 購読情報をサーバーに保存
  4. サーバー → プッシュサービス → ブラウザ
  5. Service Workerがpushイベント受信
  6. 通知表示

- **LocalStorageとSessionStorageの違いは？**
  - **LocalStorage**: 永続的、タブ間共有
  - **SessionStorage**: セッション限定、タブ個別
  - **Cookie**: サーバー送信、有効期限設定可能
  - 用途: LocalStorageはトークン保存に不適（XSSリスク）

---

**最終更新**: 2026-01-20
**対象**: 2次面接（技術面接）
