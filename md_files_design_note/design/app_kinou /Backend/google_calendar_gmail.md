# Google Calendar連携・Gmail送信機能 実装ドキュメント

## 概要

本ドキュメントでは、計画くんバックエンドにおける以下の2機能の実装フローと設計の仕組みを解説する。

1. **Google Calendar連携** — 事業所カレンダーへの支援計画期限イベントの自動登録
2. **Gmail送信機能** — 各種通知メールの送信と信頼性確保の仕組み

---

## 1. Google Calendar連携

### 1.1 アーキテクチャ概要

```
[事業所 Owner]
    ↓ Service Account JSON アップロード
[API: POST /calendar/setup]
    ↓
[CalendarService.setup_office_calendar()]
    ↓ Fernet暗号化して保存
[DB: office_calendar_accounts]
    ↓ (別トリガー: 利用者登録・プランサイクル作成時)
[CalendarService.create_renewal_deadline_events()]
    ↓ sync_status=pending で DB保存
[DB: calendar_events]
    ↓ (API: POST /calendar/sync-pending)
[CalendarService.sync_pending_events()]
    ↓ GoogleCalendarClient.create_event()
[Google Calendar API]
    ↓ google_event_id を返す
[DB: calendar_events.google_event_id, sync_status=synced]
```

**設計上の重要な決定: 2フェーズ同期（pending → synced）**

Google Calendar APIの呼び出しはネットワーク障害などで失敗する可能性がある。そのため、まずDBに `sync_status=pending` でイベントを保存し、後から別処理で一括同期する設計を採用している。これにより：
- Google側が落ちていても利用者登録処理は完了できる
- `sync_pending_events()` を再実行することで未同期イベントをリカバリできる

### 1.2 認証方式: Service Account

OAuth（ユーザー承認フロー）ではなく **Service Account** 認証を採用している。

**理由**: 事業所のGoogleカレンダーを代理操作するためにオーナーが毎回承認する必要をなくし、バックエンドが自律的にカレンダーを操作できるようにするため。

```python
# k_back/app/services/google_calendar_client.py:25-50
SCOPES = ['https://www.googleapis.com/auth/calendar']

def authenticate(self, service_account_info: dict) -> None:
    """Service Account JSONでGoogle Calendar APIに認証する"""
    credentials = service_account.Credentials.from_service_account_info(
        service_account_info,
        scopes=self.SCOPES
    )
    self.service = build('calendar', 'v3', credentials=credentials)
```

Service Account JSON（Google Cloud Consoleからダウンロードするファイル）を事業所オーナーがアップロードし、そのJSONをFernet暗号化してDBに保存する。

### 1.3 暗号化保存: OfficeCalendarAccount

サービスアカウントJSONはそのままDBに保存せず、Fernet対称暗号で暗号化する。

```python
# k_back/app/models/calendar_account.py
class OfficeCalendarAccount(Base):
    encrypted_service_account_key = Column(Text, nullable=False)  # Fernet暗号化済み
    service_account_email = Column(String(255))                   # 表示用メール（平文）
    google_calendar_id = Column(String(255))                      # カレンダーID
    connection_status = Column(String(50), default="unknown")     # unknown/connected/failed
```

暗号化・復号はモデルメソッドで実装:

```python
# OfficeCalendarAccount モデルのメソッド
def encrypt_service_account_key(self, key_dict: dict) -> None:
    fernet = Fernet(settings.CALENDAR_ENCRYPTION_KEY)
    json_str = json.dumps(key_dict)
    self.encrypted_service_account_key = fernet.encrypt(json_str.encode()).decode()

def decrypt_service_account_key(self) -> dict:
    fernet = Fernet(settings.CALENDAR_ENCRYPTION_KEY)
    decrypted = fernet.decrypt(self.encrypted_service_account_key.encode())
    return json.loads(decrypted)
```

`CALENDAR_ENCRYPTION_KEY` は環境変数で管理し、Fernet鍵（32バイト base64）を設定する。

### 1.4 カレンダー設定フロー（初回セットアップ）

```
POST /api/v1/calendar/setup
  ↓ 権限チェック: role == owner のみ
  ↓
CalendarService.setup_office_calendar(db, request)
  ├── 重複チェック: 既にアカウントが存在しないか確認
  ├── service_account_info からclient_emailを抽出
  ├── OfficeCalendarAccount を生成
  ├── .encrypt_service_account_key() で暗号化
  ├── db.add() → await db.flush()
  └── account を返す
  ↓
CalendarService.test_calendar_connection(db, account_id)
  ├── account.decrypt_service_account_key() で復号
  ├── GoogleCalendarClient.authenticate(service_account_info)
  ├── テストイベント作成 → 成功確認 → テストイベント削除
  ├── account.connection_status = "connected" (成功) or "failed" (失敗)
  └── await db.flush()
  ↓
await db.commit()  ← APIエンドポイント層でコミット
```

コード参照:
- API: `k_back/app/api/v1/endpoints/calendar.py:22-113`
- Service setup: `k_back/app/services/calendar_service.py`

### 1.5 イベント種別と登録ロジック

#### CalendarEventType (Enum)

```python
# k_back/app/models/enums.py
class CalendarEventType(str, Enum):
    renewal_deadline = "renewal_deadline"        # 更新期限（150〜180日後）
    next_plan_start_date = "next_plan_start_date"  # 次プラン開始日（1〜7日間）
```

#### renewal_deadline イベント

支援計画サイクルの更新期限を表すイベント。計画開始から150日後〜180日後の期間をカレンダーブロックとして登録する。

```python
# k_back/app/services/calendar_service.py
async def create_renewal_deadline_events(self, db, welfare_recipient_id, plan_cycle_id):
    # 150日後が開始、180日後が終了
    start_date = cycle.plan_cycle_start_date + timedelta(days=150)
    end_date   = cycle.plan_cycle_start_date + timedelta(days=180)

    # 時間: 9:00〜18:00 JST
    start_dt = datetime.combine(start_date, time(9, 0), tzinfo=JST)
    end_dt   = datetime.combine(end_date,   time(18, 0), tzinfo=JST)

    event = CalendarEvent(
        welfare_recipient_id=welfare_recipient_id,
        office_id=office_id,
        event_type=CalendarEventType.renewal_deadline,
        title=f"{recipient.last_name} {recipient.first_name} 計画更新期限",
        start_datetime=start_dt,
        end_datetime=end_dt,
        sync_status="pending",   # ← まずpendingで保存
        google_event_id=None
    )
    db.add(event)
    await db.flush()
```

#### next_plan_start_date イベント

次の支援計画サイクル開始日から7日間のイベント。

```python
# 開始日〜開始日+7日 の期間
start_dt = datetime.combine(cycle.plan_cycle_start_date, time(9, 0), tzinfo=JST)
end_dt   = datetime.combine(cycle.plan_cycle_start_date + timedelta(days=7), time(18, 0), tzinfo=JST)
```

### 1.6 Google Calendar APIへの同期

`sync_pending_events()` が `sync_status=pending` のイベントを一括でGoogle Calendarに登録する。

```python
# k_back/app/services/calendar_service.py
async def sync_pending_events(self, db: AsyncSession) -> dict:
    # pending イベントを全件取得
    pending_events = await crud.calendar_event.get_pending_events(db)

    # 事業所ごとにグルーピング（復号コストを最小化）
    events_by_office = {}
    for event in pending_events:
        events_by_office.setdefault(event.office_id, []).append(event)

    synced = 0
    failed = 0

    for office_id, events in events_by_office.items():
        # 事業所ごとに1回だけ復号・認証
        account = await crud.calendar_account.get_by_office_id(db, office_id)
        service_account_info = account.decrypt_service_account_key()

        client = GoogleCalendarClient()
        client.authenticate(service_account_info)

        for event in events:
            try:
                google_event_id = client.create_event(
                    calendar_id=account.google_calendar_id,
                    title=event.title,
                    start_datetime=event.start_datetime,
                    end_datetime=event.end_datetime,
                )
                event.google_event_id = google_event_id
                event.sync_status = "synced"
                synced += 1
            except Exception:
                event.sync_status = "failed"
                failed += 1

    return {"synced": synced, "failed": failed}
```

**トリガー**: `POST /api/v1/calendar/sync-pending` またはバッチ処理から呼び出し可能。

### 1.7 GoogleCalendarClient の実装

```python
# k_back/app/services/google_calendar_client.py
class GoogleCalendarClient:

    def create_event(self, calendar_id, title, start_datetime, end_datetime) -> str:
        """イベントを作成してgoogle_event_idを返す"""
        event_body = {
            "summary": title,
            "start": {"dateTime": start_datetime.isoformat(), "timeZone": "Asia/Tokyo"},
            "end":   {"dateTime": end_datetime.isoformat(),   "timeZone": "Asia/Tokyo"},
            "reminders": {
                "useDefault": False,
                "overrides": [{"method": "popup", "minutes": 0}]  # イベント開始時にポップアップ
            }
        }
        result = self.service.events().insert(
            calendarId=calendar_id,
            body=event_body
        ).execute()
        return result["id"]  # google_event_id

    def update_event(self, calendar_id, google_event_id, **kwargs) -> None:
        """既存イベントをGETしてから差分をPATCH"""
        existing = self.service.events().get(
            calendarId=calendar_id, eventId=google_event_id
        ).execute()
        existing.update(kwargs)
        self.service.events().update(
            calendarId=calendar_id, eventId=google_event_id, body=existing
        ).execute()

    def delete_event(self, calendar_id, google_event_id) -> None:
        self.service.events().delete(
            calendarId=calendar_id, eventId=google_event_id
        ).execute()
```

カスタム例外:
- `GoogleCalendarAuthenticationError` — 認証失敗時
- `GoogleCalendarAPIError` — API呼び出し失敗時

### 1.8 カレンダーイベントの削除

利用者削除やサイクル削除時はDBのイベントレコードを削除し、Google Calendar側も連動削除する。

```python
# k_back/app/services/calendar_service.py
async def delete_event_by_cycle(self, db, plan_cycle_id):
    events = await crud.calendar_event.get_by_cycle_id(db, plan_cycle_id)
    for event in events:
        if event.google_event_id and event.sync_status == "synced":
            # Google Calendarから削除（失敗してもDBは削除続行）
            try:
                account = await crud.calendar_account.get_by_office_id(db, event.office_id)
                key = account.decrypt_service_account_key()
                client = GoogleCalendarClient()
                client.authenticate(key)
                client.delete_event(account.google_calendar_id, event.google_event_id)
            except Exception:
                pass  # Google側削除失敗はログのみ
        await crud.calendar_event.remove(db, id=event.id)
```

### 1.9 APIエンドポイント一覧

| Method | Path | 説明 | 権限 |
|--------|------|------|------|
| POST | `/calendar/setup` | カレンダー連携初期設定 | owner |
| GET | `/calendar/office/{office_id}` | 事業所のカレンダー設定取得 | 認証済み |
| GET | `/calendar/{account_id}` | ID指定でカレンダー設定取得 | 認証済み |
| PUT | `/calendar/{account_id}` | カレンダー設定更新（JSON再アップ） | owner |
| DELETE | `/calendar/{account_id}` | カレンダー連携解除 | owner |
| POST | `/calendar/sync-pending` | 未同期イベントを一括同期 | 認証済み |

コード: `k_back/app/api/v1/endpoints/calendar.py`

---

## 2. Gmail送信機能

### 2.1 アーキテクチャ概要

```
[各種トリガー（会員登録、パスワードリセット、期限アラートバッチ等）]
    ↓
[core/mail.py: send_xxx_email() 関数群]
    ↓ FastMail + MessageSchema
[fastapi-mail ライブラリ]
    ↓ SMTP (Gmail)
[受信者のメールボックス]
```

信頼性確保のレイヤー:

```
send_xxx_email()            ← 送信関数（テンプレート指定）
    ↓
send_email_with_retry()     ← Exponential backoffリトライ
    ↓
send_and_log_email()        ← delivery_log記録 + 失敗時audit_log
```

### 2.2 fastapi-mail 設定

```python
# k_back/app/core/mail.py
from fastapi_mail import FastMail, MessageSchema, ConnectionConfig

conf = ConnectionConfig(
    MAIL_USERNAME   = settings.MAIL_USERNAME,
    MAIL_PASSWORD   = settings.MAIL_PASSWORD,
    MAIL_FROM       = settings.MAIL_FROM,
    MAIL_PORT       = settings.MAIL_PORT,
    MAIL_SERVER     = settings.MAIL_SERVER,
    MAIL_SSL_TLS    = True,
    MAIL_STARTTLS   = False,
    USE_CREDENTIALS = True,
    TEMPLATE_FOLDER = Path(__file__).parent.parent / "templates" / "email",
    SUPPRESS_SEND   = settings.MAIL_DEBUG,  # ← 開発環境では実送信を抑制
)
```

**SUPPRESS_SEND フラグ**: `settings.MAIL_DEBUG = True` の環境（ローカル開発・テスト）では、メールが実際には送信されずログ出力のみとなる。本番環境では `MAIL_DEBUG=False` に設定する。

### 2.3 基底送信関数

```python
# k_back/app/core/mail.py
async def send_email(
    recipient: str,
    subject: str,
    template_name: str,
    template_body: dict
) -> None:
    """汎用メール送信関数（Jinja2 HTMLテンプレート使用）"""
    message = MessageSchema(
        subject=subject,
        recipients=[recipient],
        template_body=template_body,
        subtype="html",
    )
    fm = FastMail(conf)
    await fm.send_message(message, template_name=template_name)
```

テンプレートは `k_back/app/templates/email/` 配下の `.html` ファイル（Jinja2形式）。

### 2.4 送信関数一覧

| 関数名 | 用途 | テンプレート |
|--------|------|-------------|
| `send_verification_email()` | メールアドレス確認 | `verification.html` |
| `send_password_reset_email()` | パスワードリセット | `password_reset.html` |
| `send_email_change_verification()` | メール変更確認（新アドレスへ） | `email_change_verification.html` |
| `send_email_change_notification()` | メール変更通知（旧アドレスへ） | `email_change_notification.html` |
| `send_email_change_completed()` | メール変更完了通知 | `email_change_completed.html` |
| `send_password_changed_notification()` | パスワード変更通知 | `password_changed.html` |
| `send_inquiry_received_email()` | 問い合わせ受信通知（管理者向け） | `inquiry_received.html` |
| `send_inquiry_reply_email()` | 問い合わせ回答通知（ユーザー向け） | `inquiry_reply.html` |
| `send_withdrawal_rejected_email()` | 退会申請却下通知 | `withdrawal_rejected.html` |
| `send_deadline_alert_email()` | 期限アラート一括通知（バッチ） | `deadline_alert.html` |

### 2.5 セキュリティ設計: パスワードリセットURLのフラグメント方式

```python
# k_back/app/core/mail.py
async def send_password_reset_email(recipient: str, token: str, name: str) -> None:
    reset_url = f"{settings.FRONTEND_URL}/reset-password#token={token}"
    #                                                    ↑ フラグメント (#)
    await send_email(
        recipient=recipient,
        subject="パスワードリセット",
        template_name="password_reset.html",
        template_body={"name": name, "reset_url": reset_url}
    )
```

**なぜURLフラグメント（`#token=xxx`）か？**

- URLクエリパラメータ（`?token=xxx`）はサーバーのアクセスログに記録される
- フラグメント（`#token=xxx`）はブラウザからサーバーへ送信されないため、ログに残らない
- これによりトークンがサーバーログに露出するリスクを排除できる

対照的に、メール確認トークンはクエリパラメータ方式:

```python
async def send_verification_email(recipient: str, token: str) -> None:
    verify_url = f"{settings.FRONTEND_URL}/verify-email?token={token}"
    #                                                   ↑ クエリパラメータ
```

メール確認はサーバー側で処理が必要なため（DBへの確認済みフラグ書き込み）、クエリパラメータを使用する。

### 2.6 メール本文のプライバシー保護

```python
# k_back/app/core/mail.py
def _mask_email(email: str) -> str:
    """メールアドレスをマスクして返す（例: t***r@example.com）"""
    local, domain = email.rsplit("@", 1)
    if len(local) <= 2:
        masked = local[0] + "***"
    else:
        masked = local[0] + "***" + local[-1]
    return f"{masked}@{domain}"
```

メール変更通知など、メールアドレスを本文に含む場合は必ずマスク処理を適用する。

### 2.7 期限アラートバッチメール

```python
# k_back/app/core/mail.py
async def send_deadline_alert_email(
    staff_email: str,
    staff_name: str,
    office_name: str,
    renewal_alerts: List[DeadlineAlertItem],   # 計画更新期限アラート一覧
    assessment_alerts: List[DeadlineAlertItem], # アセスメント期限アラート一覧
    dashboard_url: str
) -> None:
    """バッチ: スタッフ1名に対して複数利用者の期限アラートを1通のメールで送信"""
    await send_email(
        recipient=staff_email,
        subject=f"【計画くん】{office_name} 支援計画期限アラート",
        template_name="deadline_alert.html",
        template_body={
            "staff_name": staff_name,
            "office_name": office_name,
            "renewal_alerts": renewal_alerts,
            "assessment_alerts": assessment_alerts,
            "dashboard_url": dashboard_url,
        }
    )
```

### 2.8 バッチ処理: 期限アラート通知

```python
# k_back/app/tasks/deadline_notification.py
# 実行: 毎日 0:00 UTC (9:00 JST) / 平日かつ日本の祝日でない日のみ

@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=1, min=2, max=10),
    retry=retry_if_exception_type(Exception),
)
async def _send_email_with_retry(staff_email, staff_name, office_name, ...):
    """tenacityライブラリによるリトライ: 2秒→4秒→8秒のExponential backoff"""
    await send_deadline_alert_email(...)

async def _process_single_office(db, office, alerts_by_office, staffs_by_office, ...):
    """1事業所の処理（asyncio.gather()で並列実行される）"""
    # Semaphoreによる同時実行数制御（最大10事業所並列）
    async with rate_limit_semaphore:
        alerts = alerts_by_office.get(office.id, [])
        staffs = staffs_by_office.get(office.id, [])
        for staff in staffs:
            await _send_email_with_retry(staff.email, ...)
```

バッチの並列化については `memory/MEMORY.md` の「Phase 4.1: Parallel Processing Implementation」を参照。

### 2.9 Exponential Backoff リトライ

```python
# k_back/app/utils/email_utils.py
async def send_email_with_retry(
    send_func,
    *args,
    max_retries: int = 3,
    initial_delay: float = 1.0,
    backoff_factor: float = 2.0,
    max_delay: float = 60.0,
    **kwargs
) -> dict:
    """
    指数バックオフによるリトライ付きメール送信

    リトライ間隔: 1秒 → 2秒 → 4秒 → ... (max: 60秒)

    Returns:
        {
            "success": bool,
            "error": str | None,
            "retry_count": int,
            "sent_at": datetime | None
        }
    """
    delay = initial_delay
    for attempt in range(max_retries + 1):
        try:
            await send_func(*args, **kwargs)
            return {"success": True, "error": None, "retry_count": attempt, "sent_at": datetime.now(timezone.utc)}
        except Exception as e:
            if attempt == max_retries:
                return {"success": False, "error": str(e), "retry_count": attempt, "sent_at": None}
            await asyncio.sleep(min(delay, max_delay))
            delay *= backoff_factor
```

### 2.10 Delivery Log と Audit Log

問い合わせ回答メールなど重要な送信は `inquiry_details.delivery_log` フィールドに送信履歴をJSON記録する。

```python
# k_back/app/utils/email_utils.py
def create_delivery_log_entry(recipient: str, status: str, error: str | None = None) -> dict:
    """delivery_log に追記するJSONエントリを生成"""
    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "recipient": _mask_email(recipient),  # プライバシー保護
        "status": status,                      # "sent" or "failed"
        "error": error
    }

async def send_and_log_email(db, send_func, recipient, inquiry_id, ...):
    """送信 + delivery_log記録 + 失敗時audit_log記録"""
    result = await send_email_with_retry(send_func, ...)

    log_entry = create_delivery_log_entry(recipient,
                                          "sent" if result["success"] else "failed",
                                          result.get("error"))

    # inquiry_details.delivery_log (JSON配列) に追記
    await crud.inquiry.append_delivery_log(db, inquiry_id, log_entry)

    if not result["success"]:
        # 送信失敗は audit_log にも記録
        await crud.audit_log.create_log(db, action="email.send_failed", ...)
```

---

## 3. 関連ファイル一覧

| ファイル | 役割 |
|----------|------|
| `k_back/app/services/google_calendar_client.py` | Google Calendar API 直接操作クラス |
| `k_back/app/services/calendar_service.py` | カレンダー連携ビジネスロジック（Service層） |
| `k_back/app/api/v1/endpoints/calendar.py` | カレンダー設定API エンドポイント |
| `k_back/app/models/calendar_account.py` | OfficeCalendarAccount, StaffCalendarAccount モデル |
| `k_back/app/models/calendar_events.py` | CalendarEvent, CalendarEventSeries 等 |
| `k_back/app/core/mail.py` | メール送信関数群 + fastapi-mail設定 |
| `k_back/app/utils/email_utils.py` | Exponential backoffリトライ + delivery_log記録 |
| `k_back/app/tasks/deadline_notification.py` | 期限アラートバッチ（並列処理） |
| `k_back/app/templates/email/` | Jinja2 HTMLメールテンプレート群 |

---

## 4. 設計上の重要な決定事項まとめ

| 決定事項 | 選択肢 | 理由 |
|----------|--------|------|
| 認証方式 | Service Account (not OAuth) | バックエンドが自律的に操作するため。ユーザー承認フロー不要 |
| 鍵の保存 | Fernet暗号化 (not 平文) | Service Account JSONは高権限。DBに平文で置くのはリスクが高い |
| イベント同期 | 2フェーズ (pending→synced) | Google APIの障害で利用者登録処理をブロックさせないため |
| リトライ方式 | Exponential backoff | SMTPサーバー過負荷時の連続失敗を防ぐため |
| リセットURL | URLフラグメント `#token=xxx` | サーバーログへのトークン漏洩を防ぐセキュリティ設計 |
| 開発環境抑制 | `SUPPRESS_SEND=MAIL_DEBUG` | テスト中に誤送信が発生しないよう環境変数でスイッチ |
| バッチ並列化 | asyncio.gather() + Semaphore | 500事業所の直列処理25分 → 並列処理2.5分 (10倍高速化) |

---

**作成日**: 2026-03-11
**対象コミット**: main ブランチ
