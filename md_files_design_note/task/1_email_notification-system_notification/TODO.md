# メール通知機能 実装タスクリスト（TDD形式）

## 進捗状況
- 開始日: 2026-01-13
- 最終更新: 2026-01-13
- 進捗: 30/73 タスク完了 (Phase 1-4完了 ✅)

---

## Phase 1: 祝日判定機能（TDD）

### 1.1 テスト作成
- [x] `tests/utils/test_holiday_utils.py` を作成
  - [x] `test_is_japanese_holiday_new_year` - 元日は祝日
  - [x] `test_is_japanese_holiday_regular_day` - 平日は祝日でない
  - [x] `test_is_japanese_holiday_coming_of_age_day` - 成人の日は祝日
  - [x] `test_is_japanese_weekday_and_not_holiday_monday` - 通常の月曜日は平日
  - [x] `test_is_japanese_weekday_and_not_holiday_saturday` - 土曜日は平日でない
  - [x] `test_is_japanese_weekday_and_not_holiday_sunday` - 日曜日は平日でない
  - [x] `test_is_japanese_weekday_and_not_holiday_holiday` - 祝日（平日）は判定でFalse
  - [x] `test_get_holiday_name_new_year` - 元日の祝日名取得
  - [x] `test_get_holiday_name_regular_day` - 平日は祝日名がNone

### 1.2 テスト実行（Red）
- [x] テストを実行してすべて失敗することを確認 ✅ ModuleNotFoundError
  ```bash
  pytest tests/utils/test_holiday_utils.py -v
  ```

### 1.3 実装
- [x] `app/utils/holiday_utils.py` を作成
  - [x] `is_japanese_holiday()` 関数実装
  - [x] `is_japanese_weekday_and_not_holiday()` 関数実装
  - [x] `get_holiday_name()` 関数実装

### 1.4 テスト実行（Green）
- [x] テストを実行してすべてパスすることを確認 ✅ 9 passed
  ```bash
  pytest tests/utils/test_holiday_utils.py -v
  ```

### 1.5 依存関係追加
- [x] `requirements.txt` に `jpholiday>=0.1.8` を追加
- [x] ローカル環境で `pip install jpholiday` を実行

---

## Phase 2: メールテンプレート作成

### 2.1 HTMLテンプレート作成
- [x] `app/templates/email/deadline_alert.html` を作成
  - [x] ヘッダー部分
  - [x] 挨拶文
  - [x] 更新期限アラートテーブル
  - [x] アセスメント未完了アラートテーブル
  - [x] ダッシュボードリンクボタン
  - [x] フッター部分

### 2.2 HTMLテンプレートの表示確認
- [x] ブラウザで直接HTMLファイルを開いて表示確認
- [x] テーブルのスタイルが正しく適用されているか確認
- [x] レスポンシブデザインの確認（モバイル表示）

---

## Phase 3: メール送信関数（TDD）

### 3.1 既存コードの確認
- [x] `app/core/mail.py` の既存関数を確認
- [x] `app/schemas/deadline_alert.py` のスキーマを確認

### 3.2 実装
- [x] `app/core/mail.py` に `send_deadline_alert_email()` 関数を追加
  - [x] 関数シグネチャとdocstring
  - [x] コンテキスト変数の作成
  - [x] `send_email()` の呼び出し
- [x] 必要なインポートを追加 (`from typing import List, Any`)

### 3.3 手動テスト（開発環境）
- [ ] dry_runモードでメールテンプレートのレンダリング確認
- [ ] MAIL_DEBUG=1 でメール内容をログ出力

---

## Phase 4: バッチ処理（TDD）

### 4.1 テスト作成
- [x] `tests/tasks/test_deadline_notification.py` を作成
  - [x] `test_send_deadline_alert_emails_dry_run` - dry_runモードでの動作確認
  - [x] `test_send_deadline_alert_emails_no_alerts` - アラートがない場合の動作確認

### 4.2 テスト実行（Red）
- [x] テストを実行して失敗することを確認
  ```bash
  pytest tests/tasks/test_deadline_notification.py -v
  ```

### 4.3 実装
- [x] `app/tasks/deadline_notification.py` を作成
  - [x] インポート文
  - [x] `send_deadline_alert_emails()` 関数実装
    - [x] 平日・祝日チェック
    - [x] 全事業所を取得
    - [x] 各事業所ごとにアラート取得
    - [x] 各スタッフへのメール送信
    - [x] エラーハンドリング
    - [x] ログ出力

### 4.4 テスト実行（Green）
- [x] テストを実行してすべてパスすることを確認
  ```bash
  pytest tests/tasks/test_deadline_notification.py -v
  ```

---

## Phase 5: スケジューラー実装

### 5.1 スケジューラー作成
- [ ] `app/scheduler/deadline_notification_scheduler.py` を作成
  - [ ] インポート文
  - [ ] スケジューラーインスタンス作成
  - [ ] `scheduled_send_alerts()` 関数実装
  - [ ] `start()` 関数実装
  - [ ] `shutdown()` 関数実装

### 5.2 main.py 修正
- [ ] `app/main.py` にインポート追加
  ```python
  from app.scheduler.deadline_notification_scheduler import deadline_notification_scheduler
  ```
- [ ] `startup_event()` にスケジューラー起動処理を追加
- [ ] `shutdown_event()` にスケジューラー停止処理を追加

### 5.3 スケジューラーテスト作成
- [ ] `tests/scheduler/test_deadline_notification_scheduler.py` を作成
  - [ ] `test_scheduler_start_and_shutdown` - 起動・停止のテスト

---

## Phase 6: 統合テスト

### 6.1 ローカル環境での動作確認
- [ ] Dockerコンテナを起動
  ```bash
  docker-compose up -d
  ```
- [ ] スケジューラーが起動しているか確認
  ```bash
  docker logs keikakun_app-backend-1 | grep "DEADLINE_NOTIFICATION_SCHEDULER"
  ```

### 6.2 dry_runモードでのテスト
- [ ] dry_runモードでバッチ処理を手動実行
  ```bash
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
- [ ] ログ出力を確認

### 6.3 実際のメール送信テスト（開発環境）
- [ ] テスト用の事業所・スタッフ・利用者データを作成
- [ ] バッチ処理を手動実行（dry_run=False）
- [ ] メールが正しく送信されることを確認
- [ ] メールのHTML表示を確認（Gmail, Outlook等）

---

## Phase 7: コミット＆デプロイ

### 7.1 全テスト実行
- [ ] すべてのテストを実行して成功を確認
  ```bash
  pytest tests/utils/test_holiday_utils.py -v
  pytest tests/tasks/test_deadline_notification.py -v
  pytest tests/scheduler/test_deadline_notification_scheduler.py -v
  ```

### 7.2 Lint チェック
- [ ] Pythonコードのlintを実行
  ```bash
  # flake8やblackがあれば実行
  ```

### 7.3 Git コミット
- [ ] 変更をステージング
  ```bash
  git add app/utils/holiday_utils.py
  git add app/tasks/deadline_notification.py
  git add app/scheduler/deadline_notification_scheduler.py
  git add app/core/mail.py
  git add app/templates/email/deadline_alert.html
  git add app/main.py
  git add requirements.txt
  git add tests/
  ```
- [ ] コミット
  ```bash
  git commit -m "feat: メール通知機能を実装（TDD）

  ## 実装内容
  - 祝日判定ユーティリティ (jpholiday使用)
  - 期限アラートメール送信バッチ処理
  - スケジューラー（毎日9:00 JST実行）
  - HTMLメールテンプレート

  ## テスト
  - 祝日判定のユニットテスト
  - バッチ処理のユニットテスト
  - スケジューラーの統合テスト

  Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
  ```

### 7.4 プッシュ
- [ ] リモートリポジトリにプッシュ
  ```bash
  git push origin fix/issue-asobe_feedback
  ```

---

## Phase 8: 本番環境テスト

### 8.1 デプロイ確認
- [ ] Cloud Runにデプロイされたことを確認
- [ ] ログでスケジューラー起動を確認

### 8.2 dry_runテスト（本番環境）
- [ ] 本番環境でdry_runモードでテスト実行
- [ ] 送信予定件数が正しいか確認

### 8.3 本番メール送信
- [ ] 少数のスタッフで先行テスト
- [ ] メール受信を確認
- [ ] 全スタッフに対して本番運用開始

---

## オプション: 手動実行エンドポイント

### O.1 エンドポイント作成（オプション）
- [ ] `app/api/v1/endpoints/tasks.py` を作成
  - [ ] `POST /api/v1/tasks/send-deadline-alerts` エンドポイント
  - [ ] 管理者権限チェック
- [ ] `app/api/v1/api.py` にルーター追加

### O.2 エンドポイントのテスト
- [ ] Postmanでエンドポイントをテスト
- [ ] dry_runパラメータの動作確認

---

## 完了チェック

すべてのタスクが完了したら、以下を確認:

- [ ] すべてのテストがパスしている
- [ ] スケジューラーが正常に起動している
- [ ] 平日9:00（JST）にメールが送信されている
- [ ] 祝日・土日はメールが送信されない
- [ ] HTMLメールが正しく表示される
- [ ] エラー時のログが正しく出力される
- [ ] ドキュメントが最新である

---

## 備考

- 各Phaseは順番に実施すること（TDDの原則に従う）
- テストが先、実装が後
- 各タスク完了時にこのファイルを更新すること
- 問題が発生した場合は、このファイルに記録すること
