# メール通知機能 - 技術仕様書

## 目次
1. [ファイル構成](#ファイル構成)
2. [データフロー](#データフロー)
3. [詳細実装](#詳細実装)
4. [エンドポイント（オプション）](#エンドポイントオプション)
5. [テスト](#テスト)

---

## ファイル構成

```
k_back/
├── app/
│   ├── core/
│   │   └── mail.py                              # 既存ファイル修正
│   ├── utils/
│   │   └── holiday_utils.py                     # 新規作成
│   ├── tasks/
│   │   └── deadline_notification.py             # 新規作成
│   ├── scheduler/
│   │   └── deadline_notification_scheduler.py   # 新規作成
│   ├── templates/
│   │   └── email/
│   │       └── deadline_alert.html              # 新規作成
│   └── main.py                                  # 既存ファイル修正
├── tests/
│   ├── utils/
│   │   └── test_holiday_utils.py                # 新規作成
│   ├── tasks/
│   │   └── test_deadline_notification.py        # 新規作成
│   └── scheduler/
│       └── test_deadline_notification_scheduler.py  # 新規作成
└── requirements.txt                              # 既存ファイル修正
```

---

## データフロー

```
┌─────────────────────────────────────────────────────────────┐
│ 1. スケジューラー起動 (main.py)                              │
│    - アプリケーション起動時にスケジューラー登録               │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. 定期実行 (deadline_notification_scheduler.py)             │
│    - 毎日 0:00 UTC (9:00 JST) に scheduled_send_alerts() 実行│
│    - 祝日・土日チェック (holiday_utils.py)                   │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. バッチ処理 (deadline_notification.py)                     │
│    - 全事業所を取得                                          │
│    - 各事業所ごとに期限アラートを取得                         │
│    - 該当事業所の全スタッフにメール送信                       │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. メール送信 (mail.py)                                      │
│    - HTMLテンプレートをレンダリング                           │
│    - FastMailでメール送信                                    │
└─────────────────────────────────────────────────────────────┘
```

### データの流れ（詳細）

```python
# 1. スケジューラー → バッチ処理
deadline_notification_scheduler.scheduled_send_alerts()
    ↓
send_deadline_alert_emails(db: AsyncSession, dry_run: bool = False) -> int

# 2. バッチ処理 → WelfareRecipientService
from app.services.welfare_recipient_service import WelfareRecipientService
result: DeadlineAlertResponse = await WelfareRecipientService.get_deadline_alerts(
    db=db,
    office_id=office.id,
    threshold_days=30,
    limit=None,
    offset=0
)

# 3. バッチ処理 → メール送信
from app.core.mail import send_deadline_alert_email
await send_deadline_alert_email(
    staff_email=staff.email,
    staff_name=f"{staff.last_name} {staff.first_name}",
    office_name=office.name,
    renewal_alerts=renewal_alerts,
    assessment_alerts=assessment_alerts,
    dashboard_url=f"{settings.FRONTEND_URL}/protected/dashboard"
)
```

---

## 詳細実装

### 1. 祝日判定ユーティリティ

**ファイル**: `app/utils/holiday_utils.py`

```python
"""
日本の祝日判定ユーティリティ
"""
import jpholiday
from datetime import date, datetime


def is_japanese_holiday(target_date: date) -> bool:
    """
    指定された日付が日本の祝日かどうかを判定

    Args:
        target_date: 判定対象の日付

    Returns:
        bool: 祝日の場合True、祝日でない場合False

    Examples:
        >>> is_japanese_holiday(date(2026, 1, 1))  # 元日
        True
        >>> is_japanese_holiday(date(2026, 1, 2))  # 平日
        False
    """
    return jpholiday.is_holiday(target_date)


def is_japanese_weekday_and_not_holiday(target_date: date) -> bool:
    """
    指定された日付が平日かつ祝日でないことを判定

    Args:
        target_date: 判定対象の日付

    Returns:
        bool: 平日かつ祝日でない場合True、それ以外False

    Examples:
        >>> is_japanese_weekday_and_not_holiday(date(2026, 1, 5))  # 月曜日
        True
        >>> is_japanese_weekday_and_not_holiday(date(2026, 1, 10))  # 土曜日
        False
        >>> is_japanese_weekday_and_not_holiday(date(2026, 1, 1))  # 元日（木曜日）
        False
    """
    # 土曜日=5, 日曜日=6
    is_weekend = target_date.weekday() >= 5
    is_holiday = is_japanese_holiday(target_date)

    return not is_weekend and not is_holiday


def get_holiday_name(target_date: date) -> str | None:
    """
    指定された日付の祝日名を取得

    Args:
        target_date: 判定対象の日付

    Returns:
        str | None: 祝日名（祝日でない場合はNone）

    Examples:
        >>> get_holiday_name(date(2026, 1, 1))
        '元日'
        >>> get_holiday_name(date(2026, 1, 2))
        None
    """
    return jpholiday.is_holiday_name(target_date)
```

**インポート方法**:
```python
from app.utils.holiday_utils import (
    is_japanese_holiday,
    is_japanese_weekday_and_not_holiday,
    get_holiday_name
)
```

---

### 2. メール通知バッチ処理

**ファイル**: `app/tasks/deadline_notification.py`

```python
"""
期限アラートのメール通知バッチ処理

実行頻度: 毎日 0:00 UTC (9:00 JST)
実行条件: 平日かつ祝日でない場合のみ
"""
import logging
from datetime import datetime, timezone, date
from typing import List
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app import crud
from app.models.office import Office
from app.models.staff import Staff
from app.models.office import OfficeStaff
from app.services.welfare_recipient_service import WelfareRecipientService
from app.schemas.deadline_alert import DeadlineAlertItem
from app.core.mail import send_deadline_alert_email
from app.core.config import settings
from app.utils.holiday_utils import is_japanese_weekday_and_not_holiday

logger = logging.getLogger(__name__)


async def send_deadline_alert_emails(
    db: AsyncSession,
    dry_run: bool = False
) -> int:
    """
    全事業所の期限アラートメールを送信

    処理内容:
    1. 全事業所を取得
    2. 各事業所ごとに期限アラートを取得
    3. アラートがある場合、該当事業所の全スタッフにメール送信

    Args:
        db: データベースセッション
        dry_run: Trueの場合は送信せず、送信予定件数のみ返す

    Returns:
        int: 送信したメール件数

    Examples:
        >>> # 本番実行
        >>> count = await send_deadline_alert_emails(db=db)
        >>> logger.info(f"Sent {count} deadline alert emails")

        >>> # ドライラン（テスト実行）
        >>> count = await send_deadline_alert_emails(db=db, dry_run=True)
        >>> print(f"Would send {count} deadline alert emails")
    """
    # 平日かつ祝日でない場合のみ実行
    today = date.today()
    if not is_japanese_weekday_and_not_holiday(today):
        logger.info(
            f"[DEADLINE_NOTIFICATION] Skipping email notification: "
            f"today is weekend or holiday ({today})"
        )
        return 0

    logger.info(
        f"[DEADLINE_NOTIFICATION] Starting deadline alert email notification"
    )

    # 全事業所を取得
    stmt = select(Office).where(Office.deleted_at.is_(None))
    result = await db.execute(stmt)
    offices = result.scalars().all()

    logger.info(f"[DEADLINE_NOTIFICATION] Found {len(offices)} active offices")

    email_count = 0

    for office in offices:
        try:
            # 期限アラートを取得
            alert_response = await WelfareRecipientService.get_deadline_alerts(
                db=db,
                office_id=office.id,
                threshold_days=30,
                limit=None,
                offset=0
            )

            # アラートがない場合はスキップ
            if alert_response.total == 0:
                logger.debug(
                    f"[DEADLINE_NOTIFICATION] Office {office.name} "
                    f"(ID: {office.id}): No alerts, skipping"
                )
                continue

            # アラートをタイプ別に分類
            renewal_alerts: List[DeadlineAlertItem] = []
            assessment_alerts: List[DeadlineAlertItem] = []

            for alert in alert_response.alerts:
                if alert.alert_type == "renewal_deadline":
                    renewal_alerts.append(alert)
                elif alert.alert_type == "assessment_incomplete":
                    assessment_alerts.append(alert)

            logger.info(
                f"[DEADLINE_NOTIFICATION] Office {office.name} "
                f"(ID: {office.id}): {len(renewal_alerts)} renewal alerts, "
                f"{len(assessment_alerts)} assessment alerts"
            )

            # 該当事業所の全スタッフを取得
            staff_stmt = (
                select(Staff)
                .join(OfficeStaff, OfficeStaff.staff_id == Staff.id)
                .where(
                    OfficeStaff.office_id == office.id,
                    Staff.deleted_at.is_(None),
                    Staff.email.isnot(None)  # メールアドレスが設定されているスタッフのみ
                )
            )
            staff_result = await db.execute(staff_stmt)
            staffs = staff_result.scalars().all()

            if not staffs:
                logger.warning(
                    f"[DEADLINE_NOTIFICATION] Office {office.name} "
                    f"(ID: {office.id}): No staff with email address, skipping"
                )
                continue

            logger.info(
                f"[DEADLINE_NOTIFICATION] Office {office.name} "
                f"(ID: {office.id}): Sending to {len(staffs)} staff members"
            )

            # 各スタッフにメール送信
            for staff in staffs:
                if dry_run:
                    logger.info(
                        f"[DRY RUN] Would send email to {staff.email} "
                        f"({staff.last_name} {staff.first_name})"
                    )
                    email_count += 1
                else:
                    try:
                        await send_deadline_alert_email(
                            staff_email=staff.email,
                            staff_name=f"{staff.last_name} {staff.first_name}",
                            office_name=office.name,
                            renewal_alerts=renewal_alerts,
                            assessment_alerts=assessment_alerts,
                            dashboard_url=f"{settings.FRONTEND_URL}/protected/dashboard"
                        )
                        logger.info(
                            f"[DEADLINE_NOTIFICATION] Email sent to {staff.email} "
                            f"({staff.last_name} {staff.first_name})"
                        )
                        email_count += 1
                    except Exception as e:
                        logger.error(
                            f"[DEADLINE_NOTIFICATION] Failed to send email to {staff.email}: {e}",
                            exc_info=True
                        )

        except Exception as e:
            logger.error(
                f"[DEADLINE_NOTIFICATION] Error processing office {office.name} "
                f"(ID: {office.id}): {e}",
                exc_info=True
            )

    logger.info(
        f"[DEADLINE_NOTIFICATION] Completed: "
        f"{'Would send' if dry_run else 'Sent'} {email_count} emails"
    )

    return email_count
```

**インポート方法**:
```python
from app.tasks.deadline_notification import send_deadline_alert_emails
```

---

### 3. メール通知スケジューラー

**ファイル**: `app/scheduler/deadline_notification_scheduler.py`

```python
"""
期限アラートメール通知スケジューラー

定期実行スケジュール:
- 期限アラートメール送信: 毎日 0:00 UTC (9:00 JST)
- 実行条件: 平日かつ祝日でない場合のみ
"""
import logging
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger

from app.tasks.deadline_notification import send_deadline_alert_emails
from app.db.session import AsyncSessionLocal

logger = logging.getLogger(__name__)

# スケジューラーインスタンス作成
deadline_notification_scheduler = AsyncIOScheduler()


async def scheduled_send_alerts():
    """
    期限アラートメール送信のスケジュール実行

    実行頻度: 毎日 0:00 UTC (9:00 JST)
    実行条件: 平日かつ祝日でない場合のみ（バッチ処理内で判定）
    処理内容:
    - 全事業所の期限アラートを取得
    - 該当事業所の全スタッフにメール送信
    """
    async with AsyncSessionLocal() as db:
        try:
            count = await send_deadline_alert_emails(db=db)
            logger.info(
                f"[DEADLINE_NOTIFICATION_SCHEDULER] Email notification completed: "
                f"{count} email(s) sent"
            )
        except Exception as e:
            logger.error(
                f"[DEADLINE_NOTIFICATION_SCHEDULER] Email notification failed: {e}",
                exc_info=True
            )


def start():
    """スケジューラーを開始"""
    # 期限アラートメール送信 - 毎日 0:00 UTC (9:00 JST) に実行
    deadline_notification_scheduler.add_job(
        scheduled_send_alerts,
        trigger=CronTrigger(hour=0, minute=0, timezone='UTC'),
        id='send_deadline_alert_emails',
        replace_existing=True,
        name='期限アラートメール送信'
    )

    deadline_notification_scheduler.start()
    logger.info(
        "[DEADLINE_NOTIFICATION_SCHEDULER] Started successfully\n"
        "  - send_deadline_alert_emails: Daily at 0:00 UTC (9:00 JST)"
    )


def shutdown():
    """スケジューラーをシャットダウン"""
    deadline_notification_scheduler.shutdown(wait=True)
    logger.info("[DEADLINE_NOTIFICATION_SCHEDULER] Shutdown completed")
```

**インポート方法**:
```python
from app.scheduler.deadline_notification_scheduler import deadline_notification_scheduler
```

---

### 4. メール送信関数（mail.py に追加）

**ファイル**: `app/core/mail.py`

**追加する関数**:

```python
async def send_deadline_alert_email(
    staff_email: str,
    staff_name: str,
    office_name: str,
    renewal_alerts: List[Any],  # List[DeadlineAlertItem]
    assessment_alerts: List[Any],  # List[DeadlineAlertItem]
    dashboard_url: str
) -> None:
    """
    期限アラートメールを送信します。

    Args:
        staff_email: スタッフのメールアドレス
        staff_name: スタッフの氏名
        office_name: 事業所名
        renewal_alerts: 更新期限が近い利用者のリスト
        assessment_alerts: アセスメント未完了の利用者のリスト
        dashboard_url: ダッシュボードURL

    Examples:
        >>> await send_deadline_alert_email(
        ...     staff_email="staff@example.com",
        ...     staff_name="山田 太郎",
        ...     office_name="○○事業所",
        ...     renewal_alerts=[...],
        ...     assessment_alerts=[...],
        ...     dashboard_url="https://keikakun.com/protected/dashboard"
        ... )
    """
    subject = "【ケイカくん】更新期限が近い利用者がいます"

    # テンプレート用のコンテキスト
    context = {
        "title": subject,
        "staff_name": staff_name,
        "office_name": office_name,
        "renewal_alerts": [
            {
                "full_name": alert.full_name,
                "days_remaining": alert.days_remaining,
                "current_cycle_number": alert.current_cycle_number,
            }
            for alert in renewal_alerts
        ],
        "assessment_alerts": [
            {
                "full_name": alert.full_name,
                "current_cycle_number": alert.current_cycle_number,
            }
            for alert in assessment_alerts
        ],
        "dashboard_url": dashboard_url,
        "has_renewal_alerts": len(renewal_alerts) > 0,
        "has_assessment_alerts": len(assessment_alerts) > 0,
    }

    await send_email(
        recipient_email=staff_email,
        subject=subject,
        template_name="deadline_alert.html",
        context=context,
    )
```

**インポート方法**:
```python
from app.core.mail import send_deadline_alert_email
```

**追加するインポート** (mail.py の冒頭に追加):
```python
from typing import List, Any
```

---

### 5. HTMLメールテンプレート

**ファイル**: `app/templates/email/deadline_alert.html`

```html
<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{{ title }}</title>
    <style>
        body {
            font-family: 'Helvetica Neue', Arial, 'Hiragino Kaku Gothic ProN', 'Hiragino Sans', Meiryo, sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 600px;
            margin: 0 auto;
            padding: 20px;
        }
        .header {
            background-color: #4CAF50;
            color: white;
            padding: 20px;
            text-align: center;
            border-radius: 5px 5px 0 0;
        }
        .content {
            background-color: #f9f9f9;
            padding: 20px;
            border-radius: 0 0 5px 5px;
        }
        .greeting {
            margin-bottom: 20px;
        }
        .alert-section {
            margin-bottom: 30px;
        }
        .alert-title {
            font-weight: bold;
            font-size: 16px;
            margin-bottom: 10px;
            color: #d32f2f;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 20px;
            background-color: white;
        }
        th, td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }
        th {
            background-color: #f5f5f5;
            font-weight: bold;
        }
        .days-remaining {
            font-weight: bold;
            color: #d32f2f;
        }
        .button {
            display: inline-block;
            padding: 12px 24px;
            background-color: #4CAF50;
            color: white;
            text-decoration: none;
            border-radius: 5px;
            margin-top: 20px;
        }
        .footer {
            margin-top: 30px;
            padding-top: 20px;
            border-top: 1px solid #ddd;
            font-size: 12px;
            color: #666;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>{{ title }}</h1>
    </div>
    <div class="content">
        <div class="greeting">
            <p>{{ staff_name }} 様</p>
            <p>{{ office_name }} にて、更新期限が近い利用者がいますのでお知らせいたします。</p>
        </div>

        {% if has_renewal_alerts %}
        <div class="alert-section">
            <div class="alert-title">📅 更新期限が30日以内の利用者</div>
            <table>
                <thead>
                    <tr>
                        <th>利用者名</th>
                        <th>残り日数</th>
                        <th>サイクル番号</th>
                    </tr>
                </thead>
                <tbody>
                    {% for alert in renewal_alerts %}
                    <tr>
                        <td>{{ alert.full_name }}</td>
                        <td class="days-remaining">残り {{ alert.days_remaining }} 日</td>
                        <td>第 {{ alert.current_cycle_number }} サイクル</td>
                    </tr>
                    {% endfor %}
                </tbody>
            </table>
        </div>
        {% endif %}

        {% if has_assessment_alerts %}
        <div class="alert-section">
            <div class="alert-title">⚠️ アセスメント未完了の利用者</div>
            <table>
                <thead>
                    <tr>
                        <th>利用者名</th>
                        <th>サイクル番号</th>
                    </tr>
                </thead>
                <tbody>
                    {% for alert in assessment_alerts %}
                    <tr>
                        <td>{{ alert.full_name }}</td>
                        <td>第 {{ alert.current_cycle_number }} サイクル</td>
                    </tr>
                    {% endfor %}
                </tbody>
            </table>
        </div>
        {% endif %}

        <p>詳細はダッシュボードでご確認ください。</p>
        <a href="{{ dashboard_url }}" class="button">ダッシュボードを開く</a>

        <div class="footer">
            <p>このメールは【ケイカくん】から自動送信されています。</p>
            <p>心当たりがない場合は、このメールを破棄してください。</p>
        </div>
    </div>
</body>
</html>
```

---

### 6. main.py の修正

**ファイル**: `app/main.py`

**追加するインポート** (既存のスケジューラーインポートの下):
```python
from app.scheduler.deadline_notification_scheduler import deadline_notification_scheduler
```

**startup_event 関数の修正** (既存のスケジューラー起動の後に追加):
```python
@app.on_event("startup")
async def startup_event():
    """アプリケーション起動時の処理"""
    # テスト環境ではスケジューラーを起動しない
    if os.getenv("TESTING") != "1":
        logger.info("Starting calendar sync scheduler...")
        calendar_sync_scheduler.start()
        logger.info("Calendar sync scheduler started successfully")

        logger.info("Starting cleanup scheduler...")
        cleanup_scheduler.start()
        logger.info("Cleanup scheduler started successfully")

        logger.info("Starting billing scheduler...")
        billing_scheduler.start()
        logger.info("Billing scheduler started successfully")

        # 期限アラートメール通知スケジューラーを追加
        logger.info("Starting deadline notification scheduler...")
        deadline_notification_scheduler.start()
        logger.info("Deadline notification scheduler started successfully")
    else:
        logger.info("Test environment detected - skipping scheduler startup")
```

**shutdown_event 関数の修正** (既存のスケジューラー停止の後に追加):
```python
@app.on_event("shutdown")
async def shutdown_event():
    """アプリケーション終了時の処理"""
    logger.info("Shutting down calendar sync scheduler...")
    calendar_sync_scheduler.shutdown()
    logger.info("Calendar sync scheduler stopped successfully")

    logger.info("Shutting down cleanup scheduler...")
    cleanup_scheduler.shutdown()
    logger.info("Cleanup scheduler stopped successfully")

    logger.info("Shutting down billing scheduler...")
    billing_scheduler.shutdown()
    logger.info("Billing scheduler stopped successfully")

    # 期限アラートメール通知スケジューラーを追加
    logger.info("Shutting down deadline notification scheduler...")
    deadline_notification_scheduler.shutdown()
    logger.info("Deadline notification scheduler stopped successfully")
```

---

### 7. requirements.txt の修正

**ファイル**: `requirements.txt` または `pyproject.toml`

**追加する依存関係**:
```txt
jpholiday>=0.1.8
```

---

## エンドポイント（オプション）

手動実行やテスト用のエンドポイントを作成する場合:

**ファイル**: `app/api/v1/endpoints/tasks.py` (新規作成)

```python
"""
バッチ処理の手動実行エンドポイント
"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.api import deps
from app.models.staff import Staff
from app.tasks.deadline_notification import send_deadline_alert_emails

router = APIRouter()


@router.post("/send-deadline-alerts")
async def manual_send_deadline_alerts(
    *,
    db: AsyncSession = Depends(deps.get_db),
    current_staff: Staff = Depends(deps.get_current_user),
    dry_run: bool = False
) -> dict:
    """
    期限アラートメールを手動送信

    Args:
        dry_run: Trueの場合は送信せず、送信予定件数のみ返す

    Returns:
        dict: 送信件数

    Note:
        - このエンドポイントは管理者のみアクセス可能（要実装）
        - テスト・デバッグ用途
    """
    # 管理者チェック（必要に応じて実装）
    # if current_staff.role != StaffRole.owner:
    #     raise HTTPException(status_code=403, detail="管理者のみアクセス可能です")

    count = await send_deadline_alert_emails(db=db, dry_run=dry_run)

    return {
        "success": True,
        "message": f"{'Would send' if dry_run else 'Sent'} {count} emails",
        "count": count
    }
```

**api_router に追加** (`app/api/v1/api.py`):
```python
from app.api.v1.endpoints import tasks

api_router.include_router(tasks.router, prefix="/tasks", tags=["tasks"])
```

---

## テスト

### 1. 祝日判定ユーティリティのテスト

**ファイル**: `tests/utils/test_holiday_utils.py`

```python
import pytest
from datetime import date

from app.utils.holiday_utils import (
    is_japanese_holiday,
    is_japanese_weekday_and_not_holiday,
    get_holiday_name
)


class TestHolidayUtils:
    """祝日判定ユーティリティのテスト"""

    def test_is_japanese_holiday_new_year(self):
        """元日は祝日として判定される"""
        assert is_japanese_holiday(date(2026, 1, 1)) is True

    def test_is_japanese_holiday_regular_day(self):
        """平日は祝日でないと判定される"""
        assert is_japanese_holiday(date(2026, 1, 2)) is False

    def test_is_japanese_holiday_coming_of_age_day(self):
        """成人の日は祝日として判定される"""
        # 2026年の成人の日は1月12日（第2月曜日）
        assert is_japanese_holiday(date(2026, 1, 12)) is True

    def test_is_japanese_weekday_and_not_holiday_monday(self):
        """通常の月曜日は平日かつ祝日でないと判定される"""
        # 2026年1月5日（月曜日）
        assert is_japanese_weekday_and_not_holiday(date(2026, 1, 5)) is True

    def test_is_japanese_weekday_and_not_holiday_saturday(self):
        """土曜日は平日でないと判定される"""
        # 2026年1月10日（土曜日）
        assert is_japanese_weekday_and_not_holiday(date(2026, 1, 10)) is False

    def test_is_japanese_weekday_and_not_holiday_sunday(self):
        """日曜日は平日でないと判定される"""
        # 2026年1月11日（日曜日）
        assert is_japanese_weekday_and_not_holiday(date(2026, 1, 11)) is False

    def test_is_japanese_weekday_and_not_holiday_holiday(self):
        """祝日（平日）は平日かつ祝日でないの判定でFalse"""
        # 2026年1月1日（元日、木曜日）
        assert is_japanese_weekday_and_not_holiday(date(2026, 1, 1)) is False

    def test_get_holiday_name_new_year(self):
        """元日の祝日名を取得できる"""
        assert get_holiday_name(date(2026, 1, 1)) == "元日"

    def test_get_holiday_name_regular_day(self):
        """平日は祝日名がNone"""
        assert get_holiday_name(date(2026, 1, 2)) is None
```

### 2. バッチ処理のテスト

**ファイル**: `tests/tasks/test_deadline_notification.py`

```python
import pytest
from datetime import date, timedelta
from sqlalchemy.ext.asyncio import AsyncSession

from app.tasks.deadline_notification import send_deadline_alert_emails
from app.models.office import Office, OfficeStaff
from app.models.staff import Staff
from app.models.welfare_recipient import WelfareRecipient
from app.models.support_plan_cycle import SupportPlanCycle


@pytest.mark.asyncio
async def test_send_deadline_alert_emails_dry_run(
    db_session: AsyncSession,
    office_factory,
    welfare_recipient_factory,
    test_admin_user: Staff
):
    """
    dry_runモードで正しく送信予定件数を返すことを確認
    """
    # 1. テストデータの準備
    office = await office_factory(creator=test_admin_user)
    db_session.add(OfficeStaff(staff_id=test_admin_user.id, office_id=office.id, is_primary=True))
    await db_session.flush()

    # 2. 期限が近い利用者を作成
    recipient = await welfare_recipient_factory(office_id=office.id)
    cycle = SupportPlanCycle(
        welfare_recipient_id=recipient.id,
        office_id=office.id,
        next_renewal_deadline=date.today() + timedelta(days=15),
        is_latest_cycle=True,
        cycle_number=1,
        next_plan_start_date=7
    )
    db_session.add(cycle)
    await db_session.commit()

    # 3. dry_runモードで実行
    count = await send_deadline_alert_emails(db=db_session, dry_run=True)

    # 4. 送信予定件数を確認
    # スタッフ1名に送信予定
    assert count == 1


@pytest.mark.asyncio
async def test_send_deadline_alert_emails_no_alerts(
    db_session: AsyncSession,
    office_factory,
    test_admin_user: Staff
):
    """
    アラートがない場合、メールを送信しないことを確認
    """
    # 1. テストデータの準備（利用者なし）
    office = await office_factory(creator=test_admin_user)
    db_session.add(OfficeStaff(staff_id=test_admin_user.id, office_id=office.id, is_primary=True))
    await db_session.commit()

    # 2. dry_runモードで実行
    count = await send_deadline_alert_emails(db=db_session, dry_run=True)

    # 3. 送信件数0を確認
    assert count == 0
```

---

## 実装チェックリスト

### Phase 1: 祝日判定機能
- [ ] `app/utils/holiday_utils.py` 作成
- [ ] `tests/utils/test_holiday_utils.py` 作成
- [ ] テスト実行: `pytest tests/utils/test_holiday_utils.py -v`
- [ ] requirements.txt に `jpholiday>=0.1.8` 追加

### Phase 2: メールテンプレート
- [ ] `app/templates/email/deadline_alert.html` 作成
- [ ] `app/core/mail.py` に `send_deadline_alert_email()` 関数追加
- [ ] HTMLメールの表示確認（ブラウザで開く）

### Phase 3: バッチ処理
- [ ] `app/tasks/deadline_notification.py` 作成
- [ ] `tests/tasks/test_deadline_notification.py` 作成
- [ ] テスト実行: `pytest tests/tasks/test_deadline_notification.py -v`
- [ ] dry_runモードで動作確認

### Phase 4: スケジューラー
- [ ] `app/scheduler/deadline_notification_scheduler.py` 作成
- [ ] `app/main.py` の startup/shutdown イベント修正
- [ ] ログでスケジューラー起動確認

### Phase 5: 統合テスト
- [ ] 開発環境でメール送信確認
- [ ] 本番環境でdry_run実行確認
- [ ] 本番環境でメール送信確認

---

## トラブルシューティング

### メールが送信されない

1. **スケジューラーが起動しているか確認**
```bash
docker logs keikakun_app-backend-1 | grep "DEADLINE_NOTIFICATION_SCHEDULER"
```

2. **平日・祝日判定の確認**
```python
from datetime import date
from app.utils.holiday_utils import is_japanese_weekday_and_not_holiday

print(is_japanese_weekday_and_not_holiday(date.today()))
```

3. **dry_runモードで送信予定件数を確認**
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

### タイムゾーンの確認

スケジューラーは UTC で動作するため、9:00 JST = 0:00 UTC であることを確認:

```python
from datetime import datetime, timezone
import pytz

utc_now = datetime.now(timezone.utc)
jst_now = utc_now.astimezone(pytz.timezone('Asia/Tokyo'))

print(f"UTC: {utc_now}")
print(f"JST: {jst_now}")
```
