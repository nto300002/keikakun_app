# APScheduler - ジョブ管理と replace_existing=True の役割

**作成日**: 2026-01-28
**対象**: 2次面接 - バッチ処理・スケジューラー管理
**関連技術**: APScheduler, AsyncIOScheduler, CronTrigger

---

## 概要

けいかくんアプリケーションでは、APScheduler（Advanced Python Scheduler）を使用して定期バッチ処理を実装しています。全てのスケジューラーで`replace_existing=True`を設定することで、**アプリケーション再起動時の安定性**と**ジョブ重複実行の防止**を実現しています。

---

## 1. replace_existing=True の設定場所

### 1.1 billing_scheduler.py（課金関連スケジューラー）

**ファイル**: `k_back/app/scheduler/billing_scheduler.py`

**実行内容**: トライアル期間終了チェック、スケジュールキャンセルチェック

```python
def start():
    """スケジューラーを開始"""
    # トライアル期間終了チェック - 毎日 0:00 UTC に実行
    billing_scheduler.add_job(
        scheduled_trial_check,
        trigger=CronTrigger(hour=0, minute=0, timezone='UTC'),
        id='check_trial_expiration',
        replace_existing=True,  # ← line 72
        name='トライアル期間終了チェック'
    )

    # スケジュールキャンセル期限チェック - 毎日 0:05 UTC に実行
    billing_scheduler.add_job(
        scheduled_cancellation_check,
        trigger=CronTrigger(hour=0, minute=5, timezone='UTC'),
        id='check_scheduled_cancellation',
        replace_existing=True,  # ← line 81
        name='スケジュールキャンセル期限チェック'
    )

    billing_scheduler.start()
    logger.info(
        "[BILLING_SCHEDULER] Started successfully\n"
        "  - check_trial_expiration: Daily at 0:00 UTC\n"
        "  - check_scheduled_cancellation: Daily at 0:05 UTC"
    )
```

**設定箇所**:
- Line 72: `check_trial_expiration` ジョブ
- Line 81: `check_scheduled_cancellation` ジョブ

---

### 1.2 deadline_notification_scheduler.py（期限アラートスケジューラー）

**ファイル**: `k_back/app/scheduler/deadline_notification_scheduler.py`

**実行内容**: 期限アラートメール + Web Push通知送信

```python
def start():
    """スケジューラーを開始"""
    deadline_notification_scheduler.add_job(
        scheduled_send_alerts,
        trigger=CronTrigger(hour=0, minute=0, timezone='UTC'),
        id='send_deadline_alert_emails',
        replace_existing=True,  # ← line 52
        name='期限アラートメール送信'
    )

    deadline_notification_scheduler.start()
    logger.info(
        "[DEADLINE_NOTIFICATION_SCHEDULER] Started successfully\n"
        "  - send_deadline_alert_emails: Daily at 0:00 UTC (JST 9:00)"
    )
```

**設定箇所**:
- Line 52: `send_deadline_alert_emails` ジョブ

---

### 1.3 calendar_sync_scheduler.py（カレンダー同期スケジューラー）

**ファイル**: `k_back/app/scheduler/calendar_sync_scheduler.py`

**実行内容**: Google Calendar との双方向同期

```python
def start(self) -> None:
    """スケジューラーを開始"""
    if self.enabled:
        self.scheduler.add_job(
            func=self._sync_wrapper,
            trigger=IntervalTrigger(minutes=self.sync_interval_minutes),
            id=self.job_id,
            name="カレンダー同期ジョブ",
            replace_existing=True  # ← line 95
        )
        logger.info(
            f"カレンダー同期ジョブを登録しました（間隔: {self.sync_interval_minutes}分）"
        )
```

**設定箇所**:
- Line 95: `calendar_sync_job` ジョブ

---

### 1.4 cleanup_scheduler.py（クリーンアップスケジューラー）

**ファイル**: `k_back/app/scheduler/cleanup_scheduler.py`

**実行内容**: 論理削除されたレコードの物理削除

```python
def start(self) -> None:
    """スケジューラーを開始"""
    if self.enabled:
        self.scheduler.add_job(
            func=self._cleanup_wrapper,
            trigger=IntervalTrigger(hours=self.cleanup_interval_hours),
            id=self.job_id,
            name="物理削除クリーンアップジョブ",
            replace_existing=True  # ← line 109
        )
        logger.info(
            f"物理削除クリーンアップジョブを登録しました "
            f"（間隔: {self.cleanup_interval_hours}時間, 閾値: {self.days_threshold}日）"
        )
```

**設定箇所**:
- Line 109: `cleanup_job` ジョブ

---

## 2. replace_existing=True が必要な理由

### 2.1 問題：アプリケーション再起動時の ConflictingIdError

**シナリオ**:
1. FastAPIアプリケーションが起動し、スケジューラーが`start()`を実行
2. ジョブID `check_trial_expiration` が登録される
3. アプリケーションが再起動（コードデプロイ、サーバー再起動など）
4. 再度`start()`が実行され、同じジョブIDを登録しようとする

**replace_existing=False の場合**（デフォルト動作）:

```python
# 初回起動
billing_scheduler.add_job(
    scheduled_trial_check,
    id='check_trial_expiration',
    replace_existing=False  # デフォルト
)
# → ジョブ登録成功

# アプリ再起動後
billing_scheduler.add_job(
    scheduled_trial_check,
    id='check_trial_expiration',
    replace_existing=False
)
# → ConflictingIdError: Job identifier 'check_trial_expiration' already exists!
# → アプリケーション起動失敗 ❌
```

**エラーメッセージ**:
```
apscheduler.jobstores.base.ConflictingIdError: Job identifier ('check_trial_expiration') already exists!
```

**影響**:
- アプリケーションが起動できない
- サービスダウン
- 手動でジョブストアをクリアする必要がある

---

**replace_existing=True の場合**:

```python
# 初回起動
billing_scheduler.add_job(
    scheduled_trial_check,
    id='check_trial_expiration',
    replace_existing=True
)
# → ジョブ登録成功（新規登録）

# アプリ再起動後
billing_scheduler.add_job(
    scheduled_trial_check,
    id='check_trial_expiration',
    replace_existing=True
)
# → ジョブ登録成功（既存のジョブを上書き）✅
# → アプリケーション正常起動
```

**メリット**:
- アプリケーション再起動時もエラーが発生しない
- 既存のジョブ設定が新しい設定で上書きされる（スケジュール変更が反映される）
- 運用が安定する

---

### 2.2 問題：ジョブの重複実行

**replace_existing=False かつ異なるジョブIDを使用した場合**:

```python
# 初回起動
billing_scheduler.add_job(
    scheduled_trial_check,
    id='check_trial_expiration_v1',  # バージョン番号を付ける（誤った対処）
    replace_existing=False
)

# アプリ再起動後（ジョブIDを変更）
billing_scheduler.add_job(
    scheduled_trial_check,
    id='check_trial_expiration_v2',  # 新しいID
    replace_existing=False
)

# 結果: 2つのジョブが登録される
# → 同じバッチ処理が2回実行される ❌
```

**影響**:
- 毎日0:00に`scheduled_trial_check`が2回実行される
- データベース負荷が2倍
- ログが重複して出力され、デバッグが困難
- 潜在的なデータ不整合リスク（冪等性が完全でない場合）

**replace_existing=True の場合**:
```python
# 常に同じジョブIDを使用
billing_scheduler.add_job(
    scheduled_trial_check,
    id='check_trial_expiration',  # 固定ID
    replace_existing=True
)

# 再起動時: 既存のジョブが上書きされる
# → 常に1つのジョブのみ存在 ✅
```

---

## 3. 動作の仕組み

### 3.1 APSchedulerのジョブストア

APSchedulerは、登録されたジョブを**ジョブストア**に保存します。

**デフォルトジョブストア**: `MemoryJobStore`（メモリ内保存）

```python
from apscheduler.schedulers.asyncio import AsyncIOScheduler

# スケジューラー作成（デフォルトでMemoryJobStoreを使用）
billing_scheduler = AsyncIOScheduler()
```

**ジョブストアの動作**:
- ジョブはメモリ内の辞書（`dict`）に保存される
- キー: ジョブID（`id='check_trial_expiration'`）
- 値: ジョブオブジェクト（実行関数、トリガー、次回実行時刻など）

---

### 3.2 replace_existing の内部処理

**APScheduler内部の擬似コード**:

```python
def add_job(self, func, trigger, id, replace_existing=False, **kwargs):
    # 既存のジョブを確認
    existing_job = self.job_store.get(id)

    if existing_job:
        if replace_existing:
            # 既存のジョブを削除
            self.job_store.remove(id)
            logger.info(f"Replaced existing job: {id}")
        else:
            # エラーを発生させる
            raise ConflictingIdError(f"Job identifier '{id}' already exists!")

    # 新しいジョブを登録
    new_job = Job(func=func, trigger=trigger, id=id, **kwargs)
    self.job_store.add(new_job)
```

**処理フロー**:

```
[add_job 呼び出し]
      ↓
[ジョブストアでID検索]
      ↓
┌─────────────────┐
│ ID存在する？    │
└────┬────────┬───┘
     Yes      No
      ↓        ↓
[replace_existing?]  [新規登録]
      ↓              ↓
┌─────┴─────┐   [ジョブ追加]
│ True│False│       ↓
└──┬──┴──┬──┘   [完了]
   ↓     ↓
[削除] [Error]
   ↓     ↓
[追加] ConflictingIdError
   ↓
[完了]
```

---

### 3.3 実際の動作例

**初回起動時**:

```python
# ジョブストアの状態: {}（空）

billing_scheduler.add_job(
    scheduled_trial_check,
    id='check_trial_expiration',
    replace_existing=True
)

# ジョブストアの状態:
# {
#   'check_trial_expiration': Job(
#       func=scheduled_trial_check,
#       trigger=CronTrigger(hour=0, minute=0),
#       next_run_time=datetime(2026, 01, 29, 0, 0, 0, tzinfo=UTC)
#   )
# }
```

**再起動時**:

```python
# ジョブストアの状態:
# {
#   'check_trial_expiration': Job(...)  # 既存ジョブ
# }

billing_scheduler.add_job(
    scheduled_trial_check,
    id='check_trial_expiration',
    replace_existing=True  # ← 重要
)

# 内部処理:
# 1. 既存ジョブを削除
# 2. 新しいジョブを追加

# ジョブストアの状態:
# {
#   'check_trial_expiration': Job(
#       func=scheduled_trial_check,
#       trigger=CronTrigger(hour=0, minute=0),  # 新しい設定
#       next_run_time=datetime(2026, 01, 29, 0, 0, 0, tzinfo=UTC)
#   )
# }
```

---

## 4. 全ジョブ一覧

けいかくんアプリケーションで登録されている全ジョブと`replace_existing=True`の設定箇所:

| ジョブID | 実行頻度 | 実行時刻（UTC） | 処理内容 | ファイル | 行番号 |
|---------|---------|---------------|---------|---------|-------|
| `check_trial_expiration` | 毎日 | 0:00 | トライアル期間終了チェック（free→past_due, early_payment→active） | `billing_scheduler.py` | 72 |
| `check_scheduled_cancellation` | 毎日 | 0:05 | スケジュールキャンセル実行（canceling→canceled） | `billing_scheduler.py` | 81 |
| `send_deadline_alert_emails` | 毎日 | 0:00 | 期限アラートメール + Web Push通知送信 | `deadline_notification_scheduler.py` | 52 |
| `calendar_sync_job` | 30分ごと | - | Google Calendar 双方向同期 | `calendar_sync_scheduler.py` | 95 |
| `cleanup_job` | 24時間ごと | - | 論理削除レコードの物理削除 | `cleanup_scheduler.py` | 109 |

**共通設定**:
- 全てのジョブで`replace_existing=True`を設定
- ジョブIDは固定値を使用（バージョン番号などを付けない）
- スケジューラーは`AsyncIOScheduler`を使用（非同期処理）

---

## 5. 問題シナリオと解決策

### 5.1 問題シナリオ1: アプリケーション再起動時のエラー

**状況**:
- 本番環境でコードをデプロイ
- Cloud Runがアプリケーションを再起動
- スケジューラーが`start()`を実行

**replace_existing=False の場合**:
```
[ERROR] ConflictingIdError: Job identifier 'check_trial_expiration' already exists!
[ERROR] Application startup failed
→ サービスダウン ❌
```

**replace_existing=True の場合**:
```
[INFO] Replaced existing job: check_trial_expiration
[INFO] [BILLING_SCHEDULER] Started successfully
→ 正常起動 ✅
```

---

### 5.2 問題シナリオ2: スケジュール変更の反映

**状況**:
- トライアルチェックの実行時刻を0:00から1:00に変更
- アプリケーションをデプロイ

**replace_existing=False の場合**:
```python
# 既存ジョブ: 0:00に実行
# 新しいコード: 1:00に実行したい

billing_scheduler.add_job(
    scheduled_trial_check,
    trigger=CronTrigger(hour=1, minute=0, timezone='UTC'),  # 変更
    id='check_trial_expiration',
    replace_existing=False
)

# → ConflictingIdError
# → スケジュール変更が反映されない ❌
```

**replace_existing=True の場合**:
```python
billing_scheduler.add_job(
    scheduled_trial_check,
    trigger=CronTrigger(hour=1, minute=0, timezone='UTC'),  # 変更
    id='check_trial_expiration',
    replace_existing=True
)

# → 既存ジョブが削除され、新しいスケジュールで再登録
# → 1:00に実行されるように変更される ✅
```

---

### 5.3 問題シナリオ3: ジョブの重複実行

**状況**:
- 開発者がジョブIDを誤って変更
- 2つの同じ処理が登録される

**replace_existing=False の場合**:
```python
# 初回起動
billing_scheduler.add_job(
    scheduled_trial_check,
    id='check_trial_expiration',  # 元のID
    replace_existing=False
)

# 誤って変更
billing_scheduler.add_job(
    scheduled_trial_check,
    id='trial_expiration_check',  # 新しいID（typo）
    replace_existing=False
)

# → 2つのジョブが登録される
# → 同じ処理が2回実行される ❌
```

**replace_existing=True の場合**:
```python
# ジョブIDを固定して常に同じIDを使用
# → 1つのジョブのみ存在することを保証 ✅
```

---

## 6. ベストプラクティス

### 6.1 常に replace_existing=True を使用

**推奨**:
```python
billing_scheduler.add_job(
    scheduled_trial_check,
    trigger=CronTrigger(hour=0, minute=0, timezone='UTC'),
    id='check_trial_expiration',
    replace_existing=True,  # ← 必須
    name='トライアル期間終了チェック'
)
```

**理由**:
- アプリケーション再起動時の安定性
- スケジュール変更の即座の反映
- ジョブ重複実行の防止

---

### 6.2 固定のジョブIDを使用

**推奨**:
```python
id='check_trial_expiration'  # 固定値
```

**非推奨**:
```python
id=f'check_trial_expiration_{datetime.now().timestamp()}'  # 動的生成
id='check_trial_expiration_v2'  # バージョン番号
```

**理由**:
- `replace_existing=True`が正しく機能するには固定IDが必要
- 動的IDは毎回新しいジョブを作成してしまう

---

### 6.3 わかりやすいジョブ名を設定

**推奨**:
```python
name='トライアル期間終了チェック'  # 日本語でわかりやすく
```

**理由**:
- ログ出力時に識別しやすい
- デバッグ時に役立つ

---

### 6.4 スケジューラーの起動ログを記録

**推奨**:
```python
def start():
    billing_scheduler.add_job(...)
    billing_scheduler.start()

    logger.info(
        "[BILLING_SCHEDULER] Started successfully\n"
        "  - check_trial_expiration: Daily at 0:00 UTC\n"
        "  - check_scheduled_cancellation: Daily at 0:05 UTC"
    )
```

**理由**:
- どのジョブが登録されたか確認できる
- 起動時の問題を早期発見

---

## 7. 面接での回答例

### 質問: 「APSchedulerで `replace_existing=True` を設定している理由は何ですか？」

**回答例**:

「`replace_existing=True`は、アプリケーション再起動時の安定性を確保するために設定しています。

APSchedulerは、ジョブをメモリ内のジョブストアに保存しており、各ジョブは一意のIDで管理されています。`replace_existing=False`（デフォルト）の場合、アプリケーション再起動時に同じIDのジョブを再登録しようとすると`ConflictingIdError`が発生し、アプリケーションが起動できなくなります。

`replace_existing=True`を設定することで、既存のジョブを削除してから新しいジョブを登録するため、再起動時もエラーが発生しません。また、スケジュール設定を変更した場合も、再デプロイ時に自動的に新しい設定が反映されるメリットがあります。

けいかくんアプリケーションでは、5つのスケジューラー（課金チェック、期限アラート、カレンダー同期、クリーンアップ）で合計5つのジョブを登録しており、全てのジョブで`replace_existing=True`を設定しています。これにより、Cloud Runでのデプロイ時やサーバー再起動時も、安定してスケジューラーが動作することを保証しています。」

---

### 質問: 「ジョブの重複実行を防ぐために、どのような対策をしていますか？」

**回答例**:

「ジョブの重複実行を防ぐため、2つの対策を実施しています。

1つ目は、ジョブIDを固定値にすることです。例えば、トライアルチェックのジョブIDは常に`check_trial_expiration`という固定値を使用し、バージョン番号や動的な値を付けないようにしています。これにより、`replace_existing=True`と組み合わせることで、常に1つのジョブのみが存在することを保証します。

2つ目は、バッチ処理自体に冪等性を持たせることです。例えば、トライアルチェックでは、`billing_status = 'free' AND trial_end_date < now()`という条件クエリを使用しており、既に`past_due`に更新されたレコードは再処理されません。仮にジョブが2回実行されても、データの不整合は発生しない設計になっています。

この2層の防御により、確実に重複実行を防止しています。」

---

## 8. まとめ

### replace_existing=True の重要性

| 項目 | replace_existing=False | replace_existing=True |
|------|----------------------|---------------------|
| **再起動時の動作** | ConflictingIdError発生 | 正常起動 ✅ |
| **スケジュール変更** | 反映されない | 即座に反映 ✅ |
| **ジョブ重複** | 可能性あり | 防止 ✅ |
| **運用安定性** | 低い | 高い ✅ |

### 実装ファイル一覧

- `k_back/app/scheduler/billing_scheduler.py` (line 72, 81)
- `k_back/app/scheduler/deadline_notification_scheduler.py` (line 52)
- `k_back/app/scheduler/calendar_sync_scheduler.py` (line 95)
- `k_back/app/scheduler/cleanup_scheduler.py` (line 109)

### ベストプラクティス

1. ✅ 常に`replace_existing=True`を使用
2. ✅ ジョブIDは固定値を使用
3. ✅ わかりやすいジョブ名を設定
4. ✅ 起動ログを記録
5. ✅ バッチ処理自体に冪等性を持たせる

---

**Last Updated**: 2026-01-28
**Maintained by**: Claude Sonnet 4.5
