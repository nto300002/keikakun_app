# Google Calendar エラー調査報告（解決済み）

## 問題の状況

**現象**: UIに「接続ステータス: エラー」と表示されるが、実際のカレンダー連携は成功している

## 原因分析

### 1. 最初のエラー（05:10:33）- 403 Forbidden

```
HTTPステータスコード: 403
エラーメッセージ: You need to have writer access to this calendar.
```

**原因**: サービスアカウント `google-calendar@airy-task-480604-k2.iam.gserviceaccount.com` がカレンダーに対して「書き込み権限」を持っていなかった

**対処**: カレンダーの共有設定でサービスアカウントに「予定の変更」権限を付与

### 2. 再テスト後（05:18:56）- 成功

```
2025-12-08 05:18:56,779 - イベント作成成功: event_id=9e9m58oc62hq1bqqbr94neoh4g
2025-12-08 05:18:56,779 - テストイベント作成成功: 9e9m58oc62hq1bqqbr94neoh4g
2025-12-08 05:18:56,779 - テストイベント削除開始...
2025-12-08 05:18:57,181 - テストイベント削除成功
2025-12-08 05:18:57,602 - カレンダー接続テスト成功
```

✅ **接続テストは正常に完了**
- テストイベントの作成: 成功
- テストイベントの削除: 成功
- データベースのステータス更新: `connected` に更新済み（推定）

### 3. UIにエラーが表示される理由

**根本原因**: UIが古い`last_error_message`を表示し続けている

#### データフロー分析

1. **最初のテスト（05:10:33）**:
   ```
   test_calendar_connection() 実行
   → 403エラー発生
   → update_connection_status(status=error, error_message="Failed to create event...")
   → last_error_message に403エラーが保存される
   ```

2. **2回目のテスト（05:18:56）**:
   ```
   test_calendar_connection() 実行
   → テスト成功
   → update_connection_status(status=connected, error_message=None)
   → connection_status は 'connected' に更新
   → しかし、UIには古い last_error_message が表示されている
   ```

## 問題の特定

### バックエンド側の確認事項

`k_back/app/services/calendar_service.py:320-326`:
```python
# 接続ステータスを更新
await crud_office_calendar_account.update_connection_status(
    db=db,
    account_id=account_id,
    status=CalendarConnectionStatus.connected,
    error_message=None  # ← Noneを渡しているか確認必要
)
```

### CRUDレイヤーの確認

`k_back/app/crud/crud_office_calendar_account.py` の `update_connection_status` メソッドが正しく動作しているか確認が必要

**想定される問題**:
1. `error_message=None` を渡しても、DBの `last_error_message` カラムが `NULL` に更新されていない
2. UIが古いキャッシュを参照している
3. APIレスポンスで最新の `last_error_message` が返されていない

## 解決方法

### 即座の対処（ユーザー側）

**方法1: ページをリロード**
- ブラウザをリロードしてUIの最新状態を取得

**方法2: カレンダー設定を再取得**
- 管理画面でカレンダー設定画面を再度開く

### 根本的な修正（開発側）

#### 1. CRUDレイヤーの確認 ✅ **原因特定**

`k_back/app/crud/crud_office_calendar_account.py:43-64` の `update_connection_status` メソッドに問題を発見:

**実際のコード** (`k_back/app/crud/crud_office_calendar_account.py:43-64`):
```python
async def update_connection_status(
    self,
    db: AsyncSession,
    account_id: UUID,
    status: CalendarConnectionStatus,
    error_message: Optional[str] = None
) -> Optional[OfficeCalendarAccount]:
    """連携状態を更新"""
    update_data = {"connection_status": status}
    if error_message is not None:  # ← ここが問題！
        update_data["last_error_message"] = error_message

    await db.execute(
        update(self.model)
        .where(self.model.id == account_id)
        .values(**update_data)
    )
    await db.flush()
    return await self.get(db, account_id)
```

**問題点**:
- **Line 52-53**: `if error_message is not None:` という条件により、`error_message=None`を渡しても`last_error_message`カラムが更新されない
- 接続成功時に`calendar_service.py:320-326`で`error_message=None`を渡しているが、この条件により古いエラーメッセージがデータベースに残り続ける
- 結果として、UIに古いエラーメッセージが表示され続ける

**修正案**:
```python
async def update_connection_status(
    self,
    db: AsyncSession,
    account_id: UUID,
    status: CalendarConnectionStatus,
    error_message: Optional[str] = None
) -> Optional[OfficeCalendarAccount]:
    """連携状態を更新"""
    update_data = {
        "connection_status": status,
        "last_error_message": error_message  # Noneの場合はNULLに更新される
    }

    await db.execute(
        update(self.model)
        .where(self.model.id == account_id)
        .values(**update_data)
    )
    await db.flush()
    return await self.get(db, account_id)
```

この修正により、`error_message=None`を渡すと`last_error_message`カラムが`NULL`に更新されるようになります。

#### 2. データベースの確認

```sql
-- 現在の状態を確認
SELECT
    id,
    connection_status,
    last_error_message,
    updated_at
FROM office_calendar_accounts
WHERE id = 'fbfb4cdc-5424-4d3d-a5a5-90afee1028e2';

-- もし last_error_message がまだ残っている場合は手動でクリア
UPDATE office_calendar_accounts
SET last_error_message = NULL
WHERE id = 'fbfb4cdc-5424-4d3d-a5a5-90afee1028e2'
AND connection_status = 'connected';
```

#### 3. フロントエンドの確認

`k_front/components/ui/google/CalendarLinkButton.tsx:131-136`:
```typescript
{/* エラー詳細 */}
{calendarAccount.last_error_message && (
  <div className="bg-[#ef4444]/10 border border-[#ef4444] rounded-lg p-4">
    <p className="text-xs text-gray-400 mb-1">エラー詳細</p>
    <p className="text-[#ef4444] text-sm">{calendarAccount.last_error_message}</p>
  </div>
)}
```

**確認ポイント**:
- APIから返される `last_error_message` の値
- `connection_status === 'connected'` の場合、エラーメッセージを表示しないロジックの追加を検討

## 推奨される改善

### UIロジックの改善

接続成功時はエラーメッセージを表示しないように修正:

```typescript
{/* エラー詳細 - 接続エラー時のみ表示 */}
{calendarAccount.connection_status === CalendarConnectionStatus.ERROR &&
 calendarAccount.last_error_message && (
  <div className="bg-[#ef4444]/10 border border-[#ef4444] rounded-lg p-4">
    <p className="text-xs text-gray-400 mb-1">エラー詳細</p>
    <p className="text-[#ef4444] text-sm">{calendarAccount.last_error_message}</p>
  </div>
)}
```

## 検証ログ

### カレンダーID
```
4cdd840db6e37344656ffe7791e50175b8d5946e77e8a85a7aa54a768001e29f@group.calendar.google.com
型: <class 'str'>
長さ: 90文字
```
✅ **正しい形式**（64文字の16進数 + @group.calendar.google.com）

### サービスアカウント
```
google-calendar@airy-task-480604-k2.iam.gserviceaccount.com
プロジェクトID: airy-task-480604-k2
クライアントID: 101286570503403516034
```
✅ **正常に認証されている**

### API呼び出し
```
リクエストURL: https://www.googleapis.com/calendar/v3/calendars/4cdd840db6e37344656ffe7791e50175b8d5946e77e8a85a7aa54a768001e29f%40group.calendar.google.com/events
```
✅ **正しいURL**（カレンダーIDは正しくURLエンコードされている）

## 結論

**問題**: UIに古いエラーメッセージが表示され続けている

**原因**: `k_back/app/crud/crud_office_calendar_account.py:52-53` の条件分岐
```python
if error_message is not None:
    update_data["last_error_message"] = error_message
```
この条件により、`error_message=None`を渡しても`last_error_message`カラムがデータベースで更新されず、古いエラーメッセージが残り続ける。

**状態**: カレンダー連携は正常に動作している（バックエンドのログで確認済み）

**対処**:
1. **ユーザー側（一時的な回避策）**:
   - ページリロードで最新状態を確認
   - または、SQLで手動クリア: `UPDATE office_calendar_accounts SET last_error_message = NULL WHERE id = 'fbfb4cdc-5424-4d3d-a5a5-90afee1028e2';`

2. **開発側（根本的な修正）**:
   - **必須修正**: `k_back/app/crud/crud_office_calendar_account.py:51-53` の条件を削除し、常に`last_error_message`を更新する
   - **推奨修正**: `k_front/components/ui/google/CalendarLinkButton.tsx:167-168` のUIロジックを修正し、`connection_status === 'ERROR'`の場合のみエラーメッセージを表示

## 追加調査: "Hour must be in 0..23" エラー

### エラー発生条件の特定

**問題箇所**: `k_back/app/services/calendar_service.py:315-316`

```python
test_start = datetime.now()
test_end = test_start.replace(hour=test_start.hour + 1)  # ← ここが問題！
```

**エラー発生条件**:
- カレンダー接続テスト (`test_calendar_connection`) を**23時台**に実行した場合
- 例: 現在時刻が `23:30` の場合、`test_start.hour + 1 = 24` となり、`datetime.replace(hour=24)` が失敗
- エラー: `ValueError: hour must be in 0..23`

**発生する可能性のあるシナリオ**:
1. **カレンダー連携の初期設定時** (`setup_office_calendar` → `test_calendar_connection`)
2. **カレンダー設定の更新時** (再接続テスト実行時)
3. **手動でのテスト実行時** (管理画面からのテストボタン押下時)

**UTC時間との関係**:
- `datetime.now()` は**ローカル時間**（サーバーのタイムゾーン）を取得
- サーバーがUTCの場合、JST 08:00 = UTC 23:00 となり、早朝ではなく**UTC深夜**にエラーが発生
- サーバーがJSTの場合、23時台に直接エラーが発生

**修正案**:
```python
# 方法1: timedelta を使用（推奨）
test_start = datetime.now()
test_end = test_start + timedelta(hours=1)

# 方法2: タイムゾーン対応
jst = ZoneInfo("Asia/Tokyo")
test_start = datetime.now(jst)
test_end = test_start + timedelta(hours=1)
```

**他の箇所の確認**:
- ✅ `calendar_service.py:466`: `time(9, 0)` - 固定時刻、問題なし
- ✅ `calendar_service.py:469`: `time(18, 0)` - 固定時刻、問題なし
- ✅ `calendar_service.py:589`: `time(9, 0)` - 固定時刻、問題なし
- ✅ `calendar_service.py:593`: `time(18, 0)` - 固定時刻、問題なし
- ✅ `calendar_service.py:717`: `time(9, 0)` - 固定時刻、問題なし
- ✅ `calendar_service.py:720`: `time(18, 0)` - 固定時刻、問題なし

**結論**: `calendar_service.py:316` のみが問題。23時台にカレンダー接続テストを実行すると必ず失敗する。

## 関連ファイル

### バックエンド
- `k_back/app/services/calendar_service.py:316` - ⚠️ "Hour must be in 0..23" エラー発生箇所
- `k_back/app/services/calendar_service.py:320-326` - 接続ステータス更新処理
- `k_back/app/crud/crud_office_calendar_account.py:52-53` - ⚠️ `last_error_message`クリア失敗箇所
- `k_back/app/models/calendar_account.py` - カレンダーアカウントモデル

### フロントエンド
- `k_front/components/ui/google/CalendarLinkButton.tsx:131-136` - エラーメッセージ表示部分
- `k_front/types/calendar.ts` - カレンダー型定義

### データベース
- テーブル: `office_calendar_accounts`
- 問題のレコード: `id = fbfb4cdc-5424-4d3d-a5a5-90afee1028e2`

-----------

✅ **解決済み (2025-12-08)**

Request URL
http://localhost:8000/api/v1/admin/inquiries/d74df5d5-de4a-4d85-b64d-56816db222fe/reply
Request Method
POST
Status Code
500 Internal Server Error


"返信の送信に失敗しました: greenlet_spawn has not been called; can't call await_only() here. Was IO attempted in an unexpected place? (Background on this error at: https://sqlalche.me/e/20/xd2s)"

## 解決内容

### 問題1: リレーションシップの遅延ロード
- **原因**: データベース操作（flush）前後でリレーションシップにアクセス
- **修正**: データベース操作前にすべてのリレーションシップデータをローカル変数に保存

### 問題2: トランザクション中のオブジェクト二重取得
- **原因**: `append_delivery_log` が内部で同じInquiryDetailを再取得
- **修正**: 既存の `inquiry` オブジェクトのdelivery_logを直接更新

### 問題3: エンドポイントでのcommit後のオブジェクトアクセス
- **原因**: `await db.commit()` 後に `reply_message.id` にアクセス
- **修正**: commit前に `reply_message_id = reply_message.id` で値を取得

### テスト結果
すべてのテストがパス (5 passed):
- ✅ ログイン済みユーザーへの返信
- ✅ 未ログインユーザーへの返信（メール送信）
- ✅ 存在しない問い合わせ（404）
- ✅ バリデーションエラー（422）
- ✅ 権限エラー（403）

### 関連ドキュメント
- `md_files_design_note/task/1_inquiries/greenlet_spawn_fix.md`
- `md_files_design_note/task/1_inquiries/reply_endpoint_implementation.md`
- `md_files_design_note/task/1_inquiries/test_implementation_complete.md`

