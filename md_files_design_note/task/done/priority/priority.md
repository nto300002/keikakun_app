# タスク　優先度順
- 利用規約実装　: #issue/feature-利用規約、プライバシーポリシー作成
todo/task/1_terms_of_use&_privacy_policy.md
- パスワードを忘れた際の処理 : #issue/feature-パスワードを忘れた際の処理追加
todo/task/2_forgot_password.md
- MFA機能のリファクタリング : #issue/fix-MFA機能のリファクタリング
todo/task/3_MFA_Refactoring.md
- お問い合わせ UI/UX : #issue/fix-お問い合わせページ_機能のリファクタリング















<!-- 実装しない　この部分は無視 ここから -->
# メモ
- todo
- 並び順 ソート, あいうえお順, サポートプランサイクル: 次回更新日時順, サポートプランステータス: 最新のステータスの日時
- フィルター: 期限切れ　更新間近 サポートプランステータス
- 検索: フリーワード(名前)
- 
- stripe: メンテナンス性 支払い方法の説明 通知(アプリ内、メールアドレス)
- アプリのインフォメーション
- メール再送
- パスワード忘れ
- 退会時の処理: 論理削除 物理削除(30日)　課金時の処理　退会方法の通知(メール、UI/UX: 退会の入り口)
- ダッシュボード: デフォ,あいうえお　>  次回更新期限の昇順
- > UIのわかりにくさ　フォントカラー(グレー > ホワイト)　フィルター 次回更新日時(大きいボタン)  現在のソート,フィルタリング結果をわかりやすく
- staff削除
- 通知機能: 課金、employee、Google Calendar
- 問い合わせ窓口(不具合、退会)
- Google Calendar 設定チュートリアル(動画)
- UI css モバイル

## 機能
### 管理者設定ページ
- admin -> office_owner
- app_administrator

下記 +α 通知機能
- MFA ON/OFF: xmemo/kaizen/MFA_Refactoring.md
- 退会処理
- スタッフ削除
- 課金処理
### その他
- エラーメッセージフロントエンドに表示(各種ページ): done
- 利用規約
- モバイルcss修正


- サインアップ　バリデーション 記号のわかりにくさ
- Google Authenticatorをダウンロードしなければいけない　> わかりにくい 
> Google Authenticatorの使い方(動画)
> Google Calendar 設定チュートリアル(動画)
- 利用者作成 手帳年金情報　なしカテゴリ
## UI/UX
期限間近、期限切れ　- なにを指しているかわかりにくい
hotbar追加
エラーハンドリング
エラーメッセージ: 認証　*記号*が何を指すか分かりにくい

## 11/14
### 認証
ログイン時間の保持: 1,2時間
### ダッシュボード
- ダッシュボードの名前 期限を一番左: 期限が迫っている順に並べる
- 期限切れなど　高さ調整
- 氏名並び替え
- 事務所: {事務所名: office_name} <事務所名の隣に 事務所名: という言葉をつける>
### 通知
- "すべて" 一番左へ
- 作成した利用者名の氏名が見えるように
- 既読/未読を中身を見れば自動で既読になるように -> 通知の詳細ページ実装
### プロフィール
- 2段階認証解除
### 管理者(オーナー)
- 2段階認証(MFA) ON/OFF


## チェック
- plan_cycle_start_date + 180 = next_renewal_deadline v
- cycle final_plan_signed再アップロード: 重複 v
- 次サイクルを作成する条件 final_plan_signed アップロード v
- 最新＝created_at が最新 -> support_plan_statusはcompleted=falseであっても作成日時は必ず保存 v
- support_plan_cycle -> 利用者登録時トリガー関数で作成: statusはどうする?まとめて作成(配列)or個別 トリガー関数が発動しなかった場合: UI, 未登録です　作成ボタン, トリガー関数に依存しないやり方 v
- アセスメントページ: ダッシュボード利用者から v

---テスト
期限切れの時の個別支援計画ページの表記
<!-- 実装しない　この部分は無視　ここまで -->

# Google Calender　自動登録マニュアル
## 1. Google Cloud Platform プロジェクトの設定

### Step 1: GCPプロジェクト作成

```bash
# Google Cloud Console にアクセス
# https://console.cloud.google.com/

# 1. 新しいプロジェクトを作成
#    プロジェクト名: "keikakun-calendar-integration"
#    プロジェクトID: "keikakun-calendar-2024" (一意である必要がある)

# 2. プロジェクトを選択
```

### Step 2: Calendar API の有効化

```bash
# Google Cloud Console で以下の手順:
# 1. 「APIとサービス」→「ライブラリ」
# 2. 「Google Calendar API」を検索
# 3. 「有効にする」をクリック
```

---

## 2. 認証方法の選択と設定

### 事業所共有カレンダー用：サービスアカウント方式（推奨）

```bash
# Google Cloud Console での設定手順:

# 1. 「APIとサービス」→「認証情報」
# 2. 「認証情報を作成」→「サービスアカウント」
# 3. サービスアカウント情報入力:
#    名前: "keikakun-calendar-service"
#    ID: "keikakun-calendar-service"
#    説明: "ケイカくんカレンダー連携用サービスアカウント"

# 4. ロール設定（なし・後でカレンダー個別に権限付与）
# 5. 「完了」クリック
```

### Step 3: サービスアカウントキーの生成

```bash
# 1. 作成したサービスアカウントをクリック
# 2. 「キー」タブ
# 3. 「鍵を追加」→「新しい鍵を作成」
# 4. キーのタイプ: JSON
# 5. 「作成」→ JSONファイルがダウンロードされる

# ⚠️ 重要: このJSONファイルは秘密情報！安全に保管
```

**生成されるJSONファイルの例:**
```json
{
  "type": "service_account",
  "project_id": "keikakun-calendar-2024",
  "private_key_id": "1234567890abcdef",
  "private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC...\n-----END PRIVATE KEY-----\n",
  "client_email": "keikakun-calendar-service@keikakun-calendar-2024.iam.gserviceaccount.com",
  "client_id": "123456789012345678901",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/keikakun-calendar-service%40keikakun-calendar-2024.iam.gserviceaccount.com"
}
```

---

## 3. 事業所共有カレンダーの作成・設定

### Step 1: Google Workspaceでの共有カレンダー作成

```bash
# Google Calendar (https://calendar.google.com) にて:

# 1. 左側の「他のカレンダー」→「+」→「新しいカレンダーを作成」
# 2. カレンダー情報入力:
#    名前: "○○事業所 - 個別支援計画期限管理"
#    説明: "ケイカくんによる個別支援計画の期限自動管理用カレンダー"
#    タイムゾーン: "東京"

# 3. 「カレンダーを作成」
```

### Step 2: サービスアカウントに権限付与

```bash
# 作成したカレンダーの設定:

# 1. カレンダー名の横の「︙」→「設定と共有」
# 2. 「特定のユーザーと共有」セクション
# 3. 「ユーザーを追加」
# 4. メールアドレス: "keikakun-calendar-service@keikakun-calendar-2024.iam.gserviceaccount.com"
# 5. 権限: "予定の変更および共有の管理権限"
# 6. 「送信」

# ⚠️ 重要: この権限設定により、サービスアカウントがイベント作成・編集可能になる
```

### Step 3: カレンダーIDの取得

```bash
# カレンダーの設定画面にて:
# 1. 「カレンダーの統合」セクション
# 2. 「カレンダーID」をコピー
# 例: "abcd1234567890@group.calendar.google.com"

# このIDを後でアプリケーションで使用
```

### now

# S3 Integration Test Command

## Prerequisites

`k_back/.env` ファイルに以下の環境変数が正しく設定されていることを確認してください。

- `S3_ACCESS_KEY`: AWSアクセスキーID
- `S3_SECRET_KEY`: AWSシークレットアクセスキー
- `S3_REGION`: S3バケットのリージョン (例: `ap-northeast-1`)
- `S3_BUCKET_NAME`: テスト用のS3バケット名

## Command

以下のコマンドは、コンテナ内のアプリケーションが `.env` ファイルから設定を読み込むことを前提としています。

```sh
docker-compose exec \
  -e RUN_S3_INTEGRATION_TESTS=true \
  -e PYTHONPATH=/app \
  -e SECRET_KEY="test_secret_key_for_pytest" \
  backend pytest tests/core/test_storage_integration.py -v
```


