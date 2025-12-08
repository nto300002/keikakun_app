# メール送信機能 テスト要件

## 目的

問い合わせ機能のメール送信機能（リトライポリシー、delivery_log記録、エラーハンドリング）が正しく動作することを確認する。

---

## テスト対象

### 1. メール送信ラッパー関数（`app/core/mail.py`）
- `send_inquiry_received_email()` - 問い合わせ受信通知
- `send_inquiry_reply_email()` - 返信通知
- `send_withdrawal_rejected_email()` - 退会申請却下通知

### 2. リトライユーティリティ（`app/utils/email_utils.py`）
- `send_email_with_retry()` - Exponential backoff リトライ
- `create_delivery_log_entry()` - ログエントリ作成
- `send_and_log_email()` - メール送信とログ記録

### 3. CRUD操作（`app/crud/crud_inquiry.py`）
- `append_delivery_log()` - delivery_log追加

---

## テストケース

### A. メール送信ラッパー関数のテスト

#### A-1. send_inquiry_received_email - 正常系
**目的**: 問い合わせ受信通知が正しく送信されることを確認

**前提条件**:
- 有効な管理者メールアドレス
- 問い合わせデータ（送信者名、メールアドレス、種別、件名、内容）

**テスト手順**:
1. `send_inquiry_received_email()` を呼び出す
2. メール送信関数（FastMail）がモックされていることを確認
3. 正しいパラメータでメールが送信されることを確認

**期待結果**:
- メール送信が成功する
- 件名が「【ケイカくん】新しい問い合わせが届きました」
- テンプレート名が「inquiry_received.html」
- コンテキストに必要な情報が含まれる

#### A-2. send_inquiry_reply_email - 正常系
**目的**: 返信通知が正しく送信されることを確認

**前提条件**:
- 有効な受信者メールアドレス
- 返信データ（受信者名、問い合わせ件名、返信内容）

**テスト手順**:
1. `send_inquiry_reply_email()` を呼び出す
2. メール送信が正しく行われることを確認

**期待結果**:
- メール送信が成功する
- 件名が「【ケイカくん】お問い合わせへの返信」
- テンプレート名が「inquiry_reply.html」

#### A-3. send_withdrawal_rejected_email - 正常系
**目的**: 退会申請却下通知が正しく送信されることを確認

**前提条件**:
- 有効なスタッフメールアドレス
- 却下データ（スタッフ名、事務所名、却下理由、申請日時）

**テスト手順**:
1. `send_withdrawal_rejected_email()` を呼び出す
2. メール送信が正しく行われることを確認

**期待結果**:
- メール送信が成功する
- 件名が「【ケイカくん】事務所退会申請が却下されました」
- テンプレート名が「withdrawal_rejected.html」

---

### B. リトライポリシーのテスト

#### B-1. send_email_with_retry - 1回目で成功
**目的**: 1回目の送信で成功する場合の動作確認

**前提条件**:
- メール送信関数が正常に動作する

**テスト手順**:
1. `send_email_with_retry()` を呼び出す
2. メール送信関数が1回だけ呼ばれることを確認

**期待結果**:
```python
{
    "success": True,
    "error": None,
    "retry_count": 0,
    "sent_at": "2025-01-01T00:00:00"  # タイムスタンプ
}
```

#### B-2. send_email_with_retry - 2回目で成功
**目的**: リトライ後に成功する場合の動作確認

**前提条件**:
- 1回目の送信が失敗
- 2回目の送信が成功

**テスト手順**:
1. メール送信関数をモックして1回目は例外、2回目は成功するように設定
2. `send_email_with_retry()` を呼び出す
3. リトライが行われることを確認

**期待結果**:
```python
{
    "success": True,
    "error": None,
    "retry_count": 1,
    "sent_at": "2025-01-01T00:00:01"
}
```
- メール送信関数が2回呼ばれる
- 1回目と2回目の間に待機時間がある（約1秒）

#### B-3. send_email_with_retry - すべて失敗
**目的**: すべてのリトライが失敗した場合の動作確認

**前提条件**:
- すべての送信が失敗する（max_retries=3）

**テスト手順**:
1. メール送信関数をモックして常に例外を発生させる
2. `send_email_with_retry()` を呼び出す
3. 最大リトライ回数まで試行されることを確認

**期待結果**:
```python
{
    "success": False,
    "error": "メール送信エラー",
    "retry_count": 3,
    "sent_at": None
}
```
- メール送信関数が4回呼ばれる（初回 + 3回リトライ）
- 待機時間が exponential backoff に従う（1秒、2秒、4秒）

#### B-4. send_email_with_retry - Exponential backoff 検証
**目的**: 待機時間が正しく増加することを確認

**前提条件**:
- 3回すべて失敗
- initial_delay=1.0, backoff_factor=2.0

**テスト手順**:
1. メール送信関数をモックして常に失敗させる
2. 各リトライ間の待機時間を計測

**期待結果**:
- 1回目のリトライ前: 約1秒待機
- 2回目のリトライ前: 約2秒待機
- 3回目のリトライ前: 約4秒待機

#### B-5. send_email_with_retry - 最大待機時間の制限
**目的**: max_delay が機能することを確認

**前提条件**:
- max_delay=2.0
- backoff_factor=2.0

**テスト手順**:
1. メール送信関数をモックして常に失敗させる
2. 待機時間が max_delay を超えないことを確認

**期待結果**:
- すべてのリトライの待機時間が2秒以下

---

### C. delivery_log記録のテスト

#### C-1. create_delivery_log_entry - 成功時
**目的**: 成功時のログエントリが正しく作成されることを確認

**前提条件**:
- メール送信が成功した結果

**テスト手順**:
1. `create_delivery_log_entry()` を呼び出す
2. 返されたログエントリを検証

**期待結果**:
```python
{
    "timestamp": "2025-01-01T00:00:00",
    "recipient": "user@example.com",
    "subject": "【ケイカくん】新しい問い合わせが届きました",
    "email_type": "inquiry_received",
    "success": True,
    "error": None,
    "retry_count": 0,
    "sent_at": "2025-01-01T00:00:00"
}
```

#### C-2. create_delivery_log_entry - 失敗時
**目的**: 失敗時のログエントリが正しく作成されることを確認

**前提条件**:
- メール送信が失敗した結果

**テスト手順**:
1. `create_delivery_log_entry()` を呼び出す
2. 返されたログエントリを検証

**期待結果**:
```python
{
    "timestamp": "2025-01-01T00:00:00",
    "recipient": "user@example.com",
    "subject": "【ケイカくん】返信通知",
    "email_type": "inquiry_reply",
    "success": False,
    "error": "Connection timeout",
    "retry_count": 3,
    "sent_at": None
}
```

---

### D. 統合テスト（send_and_log_email）

#### D-1. send_and_log_email - 正常系
**目的**: メール送信とログ記録が正しく連携することを確認

**前提条件**:
- データベースに InquiryDetail が存在
- メール送信が成功する

**テスト手順**:
1. テスト用 InquiryDetail を作成
2. `send_and_log_email()` を呼び出す
3. delivery_log が更新されることを確認
4. 監査ログが作成されないことを確認（成功時）

**期待結果**:
- 関数が True を返す
- InquiryDetail の delivery_log に新しいエントリが追加される
- エントリの success が True
- 監査ログは作成されない

#### D-2. send_and_log_email - 失敗時
**目的**: メール送信失敗時に監査ログが記録されることを確認

**前提条件**:
- データベースに InquiryDetail が存在
- メール送信がすべて失敗する

**テスト手順**:
1. テスト用 InquiryDetail を作成
2. メール送信関数をモックして常に失敗させる
3. `send_and_log_email()` を呼び出す
4. delivery_log と監査ログが作成されることを確認

**期待結果**:
- 関数が False を返す
- InquiryDetail の delivery_log に失敗エントリが追加される
- エントリの success が False
- 監査ログが作成される:
  - action: "email_send_failed"
  - target_type: "inquiry_detail"
  - details に recipient, subject, email_type, error, retry_count が含まれる

---

### E. CRUD操作のテスト

#### E-1. append_delivery_log - 初回追加
**目的**: delivery_log が空の状態で追加できることを確認

**前提条件**:
- InquiryDetail の delivery_log が None または空

**テスト手順**:
1. テスト用 InquiryDetail を作成（delivery_log=None）
2. `append_delivery_log()` を呼び出す
3. delivery_log を確認

**期待結果**:
- delivery_log が配列になる
- 1つのエントリが含まれる
- updated_at が更新される

#### E-2. append_delivery_log - 追加
**目的**: 既存の delivery_log にエントリを追加できることを確認

**前提条件**:
- InquiryDetail の delivery_log に既に1つエントリがある

**テスト手順**:
1. 既存エントリを持つ InquiryDetail を作成
2. `append_delivery_log()` を呼び出す
3. delivery_log を確認

**期待結果**:
- delivery_log に2つのエントリが含まれる
- 古いエントリが保持される
- 新しいエントリが末尾に追加される
- updated_at が更新される

#### E-3. append_delivery_log - 存在しない inquiry_id
**目的**: 存在しない inquiry_id でエラーが発生することを確認

**前提条件**:
- 存在しない UUID

**テスト手順**:
1. 存在しない inquiry_id で `append_delivery_log()` を呼び出す

**期待結果**:
- ValueError が発生する
- エラーメッセージ: "問い合わせが見つかりません"

---

## テスト環境

### モック対象
- `FastMail.send_message()` - メール送信関数
- `asyncio.sleep()` - 待機時間（テスト高速化のため）

### データベース
- テスト用データベース（SQLite in-memory または PostgreSQL テストDB）
- 各テスト前に初期化
- トランザクションロールバック

### ログ
- ログ出力を capture して検証
- WARNING, ERROR レベルのログを確認

---

## 非機能要件

### パフォーマンス
- リトライテストは高速化のため sleep をモック
- 各テストケースは5秒以内に完了

### カバレッジ
- 目標: 90%以上
- 重要な分岐（成功/失敗、リトライ有無）をすべてカバー

### メンテナンス性
- テストケースは独立して実行可能
- フィクスチャを活用してセットアップを共通化
- モックは明示的で理解しやすい形式

---

## テスト実行方法

```bash
# すべてのメール送信テストを実行
pytest tests/utils/test_email_utils.py -v

# 特定のテストクラスのみ実行
pytest tests/utils/test_email_utils.py::TestSendEmailWithRetry -v

# カバレッジ付きで実行
pytest tests/utils/test_email_utils.py --cov=app.utils.email_utils --cov-report=html
pytest tests/core/test_mail.py --cov=app.core.mail --cov-report=html
pytest tests/crud/test_crud_inquiry.py::TestAppendDeliveryLog --cov=app.crud.crud_inquiry
```

---

## 成功基準

- すべてのテストケースが PASSED
- コードカバレッジ 90%以上
- テスト実行時間 30秒以内
- CI/CDで自動実行可能

---

## 次のアクション

1. テストファイル作成
   - `tests/utils/test_email_utils.py`
   - `tests/core/test_mail.py`
   - `tests/crud/test_crud_inquiry.py` (delivery_log部分)

2. フィクスチャ作成
   - `tests/conftest.py` にメール関連のフィクスチャを追加

3. テスト実装
   - 上記のテストケースを実装

4. カバレッジ確認
   - 不足している部分を追加テスト

5. ドキュメント更新
   - テスト結果をドキュメント化
