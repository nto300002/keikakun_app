# 残り期限が少ない利用者の通知

## 1. メール通知（新規実装）

### 実行条件
- 平日の午前9:00（日本時間 = 0:00 UTC）にバッチ処理として自動実行
- 日本の祝日は除外（土日祝日は実行しない）
- 各事業所ごとに、更新期限が30日以内の利用者が1人以上存在する場合

### 送信対象
- 該当事業所に所属する全Staffのメールアドレスに送信
- メールアドレスが未設定のStaffはスキップ（ログに記録）

### メール内容
- 件名: 「【ケイカくん】更新期限が近い利用者がいます」
- 本文:
  - Staff名
  - 更新期限が近い利用者のリスト（氏名、残り日数、サイクル番号）
  - アセスメント未完了の利用者のリスト（氏名、サイクル番号）
  - ダッシュボードへのリンク

### 技術仕様
- スケジューラー: APScheduler (CronTrigger)
- メール送信: FastMail
- 祝日判定: jpholiday ライブラリ
- バッチ処理: `app/tasks/deadline_notification.py`

## 2. システム通知（既存実装・修正済み）

### 実行条件
- Staffがダッシュボードにログインした時
- 所属事業所に更新期限が30日以内の利用者が1人以上存在する場合

### 表示方法
- トースト通知（画面右上に5秒間表示）
- 1回のログインで1回のみ表示（重複表示防止済み）

### 通知内容
- 更新期限アラート: 「{氏名} 更新期限まで残り{X}日」
- アセスメント未完了アラート: 「{氏名}のアセスメントが完了していません」

### 技術仕様
- 実装場所: `k_front/components/protected/LayoutClient.tsx`
- ライブラリ: sonner (toast.warning)
- API: `/api/v1/welfare-recipients/deadline-alerts`

**注**: Web Push通知は実装しない

---

## 実装における影響範囲

### バックエンド（k_back）

#### 新規作成ファイル
1. **祝日判定ユーティリティ** (`app/utils/holiday_utils.py`)
   - 日本の祝日を判定する関数
   - jpholidayライブラリを使用
   - 平日かつ祝日でないことを判定する関数

2. **メール通知バッチ処理** (`app/tasks/deadline_notification.py`)
   - 全事業所の期限アラートを取得
   - 各事業所の全スタッフにメール送信
   - dry_runモード対応（テスト用）

3. **メール通知スケジューラー** (`app/scheduler/deadline_notification_scheduler.py`)
   - 毎日0:00 UTC（9:00 JST）に実行
   - 平日かつ祝日でない場合のみ処理実行

4. **メールテンプレート** (`app/templates/email/deadline_alert.html`)
   - HTMLメールテンプレート
   - 更新期限が近い利用者のテーブル表示
   - アセスメント未完了利用者のテーブル表示
   - ダッシュボードへのリンク

5. **テストファイル**
   - `tests/utils/test_holiday_utils.py`: 祝日判定のテスト
   - `tests/tasks/test_deadline_notification.py`: バッチ処理のテスト
   - `tests/scheduler/test_deadline_notification_scheduler.py`: スケジューラーのテスト

#### 既存ファイル修正
1. **メール送信モジュール** (`app/core/mail.py`)
   - `send_deadline_alert_email()` 関数を追加
   - 既存のメール送信パターンを踏襲

2. **アプリケーション起動** (`app/main.py`)
   - deadline_notification_schedulerのimportを追加
   - startupイベントでスケジューラー起動
   - shutdownイベントでスケジューラー停止

3. **依存関係** (`requirements.txt` or `pyproject.toml`)
   - jpholiday ライブラリを追加

#### データベース
- **変更なし**: 既存のテーブル構造で対応可能
- 使用するテーブル:
  - `offices`: 事業所情報
  - `staffs`: スタッフ情報（メールアドレス）
  - `office_staffs`: スタッフと事業所の関連
  - `welfare_recipients`: 利用者情報
  - `support_plan_cycles`: サイクル情報（期限）
  - `plan_deliverables`: アセスメントPDF

#### 環境変数
- **変更なし**: 既存のメール設定を使用
- 使用する環境変数:
  - `MAIL_USERNAME`: メールサーバーのユーザー名
  - `MAIL_PASSWORD`: メールサーバーのパスワード
  - `MAIL_FROM`: 送信元メールアドレス
  - `MAIL_SERVER`: SMTPサーバー
  - `MAIL_PORT`: SMTPポート
  - `FRONTEND_URL`: フロントエンドのURL（ダッシュボードリンク用）

---

### フロントエンド（k_front）

#### 既存ファイル修正
1. **アセスメント就労関係フォーム**
   - 利用者個別ページの就労関係モーダル
   - フィールドの順序を変更:
     - 「asoBeで希望する作業」と「施設外就労の希望」の順序を入れ替え
   - 影響範囲: UIのみ（ロジック変更なし）

#### 新規作成ファイル
- **なし**: アセスメントUIの修正のみ

---

### インフラ・デプロイ

#### Cloud Run
- **変更なし**: 既存のCloud Runサービスで動作
- スケジューラーはアプリケーション内で起動（APScheduler）

#### Cloud Scheduler（オプション）
- 現在の実装ではAPScheduler（アプリ内蔵）を使用
- 将来的にCloud Schedulerに移行する場合:
  - HTTP エンドポイント `/api/v1/tasks/send-deadline-alerts` を作成
  - Cloud Schedulerから毎日9:00 JSTにリクエスト

#### ログ監視
- バッチ処理のログを監視
- メール送信成功/失敗のログ確認
- エラー時のアラート設定（推奨）

---

### テスト戦略

#### ユニットテスト
1. 祝日判定ロジック
   - 2026年の祝日で正しく判定されるか
   - 土日が正しく判定されるか
   - 平日が正しく判定されるか

2. バッチ処理
   - 期限アラートの取得
   - メール送信対象の抽出
   - dry_runモードの動作確認

3. メール送信
   - テンプレートのレンダリング
   - 送信先アドレスの正確性

#### 統合テスト
1. スケジューラーの起動/停止
2. バッチ処理の実行（dry_runモード）
3. メール送信のエンドツーエンド（開発環境）

#### 手動テスト
1. 本番環境でのメール受信確認
2. HTMLメールの表示確認（各メールクライアント）
3. リンクの動作確認

---

### デプロイ手順

#### 1. バックエンドのデプロイ
```bash
# 依存関係のインストール
pip install jpholiday

# マイグレーション（不要）
# alembic upgrade head

# テスト実行
pytest tests/utils/test_holiday_utils.py -v
pytest tests/tasks/test_deadline_notification.py -v

# デプロイ
git push origin main
# Cloud Runに自動デプロイ
```

#### 2. フロントエンドのデプロイ
```bash
# アセスメントUI修正後
npm run build
git push origin main
# Cloud Runに自動デプロイ
```

#### 3. 動作確認
```bash
# スケジューラーが起動しているか確認
docker logs keikakun_app-backend-1 | grep "DEADLINE_NOTIFICATION_SCHEDULER"

# dry_runモードで実行テスト
docker exec keikakun_app-backend-1 python3 -c "
import asyncio
from app.db.session import AsyncSessionLocal
from app.tasks.deadline_notification import send_deadline_alert_emails

async def test():
    async with AsyncSessionLocal() as db:
        count = await send_deadline_alert_emails(db=db, dry_run=True)
        print(f'Would send {count} emails')

asyncio.run(test())
"
```

---

### ロールバック手順

#### メール送信を停止する場合
1. スケジューラーを無効化:
   ```python
   # app/main.py の startup イベントでコメントアウト
   # deadline_notification_scheduler.start()
   ```

2. 再デプロイ

#### 完全にロールバックする場合
1. 追加したファイルを削除
2. 修正したファイルを元に戻す
3. requirements.txt から jpholiday を削除
4. 再デプロイ

---

### リスクと対策

#### リスク1: メール送信失敗
- **原因**: SMTPサーバーのエラー、ネットワーク障害
- **対策**:
  - リトライロジックの実装
  - エラーログの監視
  - 管理者へのアラート通知

#### リスク2: 大量メール送信
- **原因**: 複数の事業所で多数のスタッフが登録されている
- **対策**:
  - レート制限の実装（1秒あたりX件）
  - バッチ処理のタイムアウト設定

#### リスク3: 祝日判定の誤り
- **原因**: jpholidayライブラリの更新遅延
- **対策**:
  - 年初に祝日データの確認
  - 手動で祝日リストを管理するオプション

#### リスク4: タイムゾーンの誤り
- **原因**: UTC/JSTの変換ミス
- **対策**:
  - テストで確認
  - ログに実行時刻を記録

---

# アセスメントUI微修正
- アセスメント - 就労関係についての修正
利用者個別ページ
https://www.keikakun.com/recipients/[recipients_id]

就労関係タブ -> 就労関係について -> 追加ボタン -> 就労関係の編集モーダル

> 修正点
過去の就労経験
免許、資格、検定
.
.
.
asoBeで希望する作業
施設外就労の希望 *
施設外就労の特記事項

このように項目が並んでいるが

asoBeで希望する作業
施設外就労の希望 *

上記の順序を逆にしたい

> 修正後

過去の就労経験
免許、資格、検定
.
.
.
施設外就労の希望 *
asoBeで希望する作業
施設外就労の特記事項