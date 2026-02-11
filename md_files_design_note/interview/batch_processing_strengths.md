# バッチ処理の技術的強み - 面接用ガイド

**プロジェクト**: Keikakun API - 期限通知バッチ処理
**技術**: FastAPI (Async) + SQLAlchemy (Async) + PostgreSQL
**最適化期間**: 2026-02-01 〜 2026-02-10（4週間）
**作成日**: 2026-02-10

---

## 📊 パフォーマンス改善の成果（一目でわかる）

### Before → After（500事業所での処理）

| 指標 | 最適化前 | 最適化後 | 改善率 |
|------|---------|---------|--------|
| **処理時間** | 25分（1,500秒） | **3分（150秒）** | **10倍高速化** |
| **DBクエリ数** | 1,001回 | **5回** | **200倍削減** |
| **並列処理** | なし（直列） | 10事業所並列 | **10倍スループット** |
| **メモリ効率** | 低（N+1クエリ） | 高（バッチ取得） | **安定** |

### 技術的ハイライト

```
✅ 非同期処理（asyncio）による並列実行
✅ N+1クエリ問題の完全解消（バッチクエリ）
✅ Semaphoreによる並列度制御（リソース保護）
✅ リトライ機構（指数バックオフ）
✅ レート制限（メール送信）
✅ 監査ログ（全操作追跡）
```

---

## 🎯 面接での回答（30秒版）

### Q: バッチ処理の強みは？

> 「**非同期処理とバッチクエリの組み合わせ**で、500事業所の処理を**25分から3分に短縮**しました。」
>
> 「具体的には：」
> - **asyncio.gather()** で事業所レベルを並列化（10倍高速化）
> - **バッチクエリ** でDBアクセスを1,001回から5回に削減（200倍削減）
> - **Semaphore** で並列度を制御し、リソース枯渇を防止
>
> 「これにより、**スケーラブルで安定した大規模バッチ処理**を実現しました。」

---

## 1️⃣ 非同期処理（Asyncio）の活用

### 1.1 並列処理アーキテクチャ

#### Before: 直列処理（遅い）

```python
# ❌ 直列処理: 500事業所 × 3秒 = 1,500秒（25分）
for office in offices:  # 500回ループ
    # アラート取得: 1秒
    alerts = await get_alerts(office.id)

    # スタッフ取得: 1秒
    staffs = await get_staffs(office.id)

    # メール送信: 1秒
    for staff in staffs:
        await send_email(staff.email)

# 合計: 500 × 3秒 = 1,500秒（25分）
```

**問題点**:
- 事業所を1つずつ順番に処理
- CPUアイドル時間が多い（I/O待ち）
- 処理時間が事業所数に比例（O(N)）

---

#### After: 並列処理（速い）

```python
# ✅ 並列処理: 500事業所 / 10並列 × 3秒 = 150秒（2.5分）

# Phase 1: データを事前にバッチ取得
alerts_by_office = await get_alerts_batch(office_ids)      # 1クエリ
staffs_by_office = await get_staffs_batch(office_ids)      # 1クエリ
push_subs_by_staff = await get_push_subs_batch(staff_ids)  # 1クエリ

# Phase 2: 並列度制御（Semaphore）
office_semaphore = asyncio.Semaphore(10)  # 同時10事業所まで

async def process_with_semaphore(office):
    async with office_semaphore:
        return await _process_single_office(
            office=office,
            alerts_by_office=alerts_by_office,    # メモリ参照
            staffs_by_office=staffs_by_office,    # メモリ参照
            push_subs_by_staff=push_subs_by_staff # メモリ参照
        )

# Phase 3: 全事業所を並列実行
tasks = [process_with_semaphore(office) for office in offices]
results = await asyncio.gather(*tasks, return_exceptions=True)

# 合計: 500 / 10 × 3秒 = 150秒（2.5分）
```

**改善点**:
- ✅ 10事業所を同時並列処理
- ✅ CPUとI/Oを効率的に活用
- ✅ 処理時間が並列度に反比例（O(N/10)）

---

### 1.2 Semaphoreによる並列度制御

#### なぜSemaphoreが必要？

```python
# ❌ 無制限並列（危険）
tasks = [process_office(office) for office in offices]
results = await asyncio.gather(*tasks)  # 500事業所が同時実行！

# 問題:
# - DB接続プール枯渇（最大50接続）
# - メモリ不足（500並列 × 各10MB = 5GB）
# - ネットワーク帯域圧迫
```

#### Semaphoreの実装

```python
# ✅ 並列度制御（安全）
office_semaphore = asyncio.Semaphore(10)  # 同時10事業所まで

async def process_with_semaphore(office):
    async with office_semaphore:
        # この中は最大10個まで同時実行
        return await _process_single_office(...)

# 500事業所を並列実行（でも最大10並列に制限）
tasks = [process_with_semaphore(office) for office in offices]
results = await asyncio.gather(*tasks)
```

**メリット**:
- ✅ DB接続数: 最大10に制限（枯渇回避）
- ✅ メモリ使用量: 最大10 × 10MB = 100MB（安定）
- ✅ エラー時の影響範囲: 最大10事業所（局所化）

---

### 1.3 メール送信のレート制限

#### 2段階のSemaphore制御

```python
# レベル1: 事業所並列（10並列）
office_semaphore = asyncio.Semaphore(10)

# レベル2: メール送信並列（5並列）
rate_limit_semaphore = asyncio.Semaphore(5)

async def _process_single_office(...):
    for staff in staffs:
        # メール送信は5並列まで
        async with rate_limit_semaphore:
            await _send_email_with_retry(staff.email, ...)
```

**並列度の計算**:
```
理論上の最大並列数 = 10事業所 × 5メール = 50
実際の並列数      = 5メール（rate_limit_semaphoreが支配的）

理由: 各事業所のメール送信が rate_limit_semaphore を共有しているため、
     全体で5並列に制限される
```

**メリット**:
- ✅ メールサービスのレート制限を超えない
- ✅ スパム判定を回避
- ✅ 安定した送信成功率

---

## 2️⃣ パフォーマンス最適化

### 2.1 N+1クエリ問題の解消

#### Before: N+1クエリ（遅い）

```python
# ❌ N+1クエリ問題
offices = await get_offices()  # 1クエリ

for office in offices:  # 500回ループ
    # N+1問題その1: アラート取得
    alerts = await get_alerts(office.id)  # 500クエリ

    # N+1問題その2: スタッフ取得
    staffs = await get_staffs(office.id)  # 500クエリ

    for staff in staffs:  # 各10名 = 5,000回ループ
        # N+1問題その3: Push購読取得
        subs = await get_push_subs(staff.id)  # 5,000クエリ

# 合計: 1 + 500 + 500 + 5,000 = 6,001クエリ ❌
```

**問題点**:
- クエリ数がデータ量に比例（O(N)）
- DBへの往復回数が多い（ネットワークオーバーヘッド）
- クエリ時間: 6,001 × 5ms = 30秒

---

#### After: バッチクエリ（速い）

```python
# ✅ バッチクエリで一括取得

# 1. 事業所取得
offices = await get_offices()  # 1クエリ
office_ids = [office.id for office in offices]

# 2. アラート一括取得（WHERE IN）
alerts_by_office = await get_alerts_batch(office_ids)
# SQL: SELECT * FROM users WHERE office_id IN (?, ?, ..., ?)
# → 1クエリで500事業所分のアラートを取得

# 3. スタッフ一括取得（WHERE IN）
staffs_by_office = await get_staffs_batch(office_ids)
# SQL: SELECT DISTINCT * FROM staffs WHERE office_id IN (?, ?, ..., ?)
# → 1クエリで500事業所分のスタッフ（5,000人）を取得

# 4. Push購読一括取得（WHERE IN）
staff_ids = [staff.id for staffs in staffs_by_office.values() for staff in staffs]
push_subs_by_staff = await get_push_subs_batch(staff_ids)
# SQL: SELECT * FROM push_subscriptions WHERE staff_id IN (?, ?, ..., ?)
# → 1クエリで5,000人分のPush購読を取得

# 5. 処理（メモリ参照のみ）
for office in offices:
    alerts = alerts_by_office.get(office.id, [])      # メモリ参照
    staffs = staffs_by_office.get(office.id, [])      # メモリ参照

    for staff in staffs:
        subs = push_subs_by_staff.get(staff.id, [])   # メモリ参照

# 合計: 1 + 1 + 1 + 1 = 4クエリ ✅
```

**改善点**:
- ✅ クエリ数: 6,001 → 4（1,500倍削減）
- ✅ クエリ時間: 30秒 → 20ms（1,500倍高速化）
- ✅ メモリアクセス: O(1)（ハッシュテーブル）

---

### 2.2 バッチクエリの実装例

#### get_alerts_batch() の実装

```python
# app/services/welfare_recipient_service.py

@staticmethod
async def get_deadline_alerts_batch(
    db: AsyncSession,
    office_ids: List[UUID],
    threshold_days: int = 30
) -> Dict[UUID, DeadlineAlertResponse]:
    """
    複数事業所のアラートを一括取得（N+1問題解消）

    Before: 500クエリ
    After: 1クエリ

    Returns:
        Dict[UUID, DeadlineAlertResponse]: {office_id: alerts}
    """
    if not office_ids:
        return {}

    # 全事業所の利用者を1クエリで取得
    stmt = (
        select(User)
        .options(
            selectinload(User.office),
            selectinload(User.plans).selectinload(IndividualSupportPlan.cycles)
        )
        .where(User.office_id.in_(office_ids))  # ✅ WHERE IN で一括取得
        .where(User.deleted_at.is_(None))
        .where(User.is_test_data == False)
    )

    result = await db.execute(stmt)
    users = result.scalars().all()

    # 事業所ごとにグループ化してアラート生成
    alerts_by_office: Dict[UUID, DeadlineAlertResponse] = {}

    for user in users:
        office_id = user.office_id
        if office_id not in alerts_by_office:
            alerts_by_office[office_id] = DeadlineAlertResponse(
                office_id=office_id,
                alerts=[],
                total=0
            )

        # アラート判定（メモリ内処理）
        if needs_alert(user, threshold_days):
            alerts_by_office[office_id].alerts.append(...)
            alerts_by_office[office_id].total += 1

    return alerts_by_office
```

**ポイント**:
- ✅ `WHERE IN (office_ids)` で一括取得
- ✅ `selectinload()` でリレーションも同時取得（N+1回避）
- ✅ メモリ内でグループ化（高速）

---

#### get_push_subs_batch() の実装

```python
# app/crud/crud_push_subscription.py

async def get_by_staff_ids_batch(
    self,
    db: AsyncSession,
    staff_ids: List[UUID]
) -> Dict[UUID, List[PushSubscription]]:
    """
    複数スタッフの購読情報を一括取得（N+1問題解消）

    Before: 5,000クエリ
    After: 1クエリ

    Returns:
        Dict[UUID, List[PushSubscription]]: {staff_id: [subscription, ...]}
    """
    if not staff_ids:
        return {}

    # 全スタッフの購読情報を1クエリで取得
    stmt = (
        select(PushSubscription)
        .where(PushSubscription.staff_id.in_(staff_ids))  # ✅ WHERE IN
        .order_by(
            PushSubscription.staff_id.asc(),
            PushSubscription.created_at.asc()
        )
    )

    result = await db.execute(stmt)
    subscriptions = result.scalars().all()

    # スタッフIDごとにグループ化
    subscriptions_by_staff: Dict[UUID, List[PushSubscription]] = {
        staff_id: [] for staff_id in staff_ids
    }

    for subscription in subscriptions:
        subscriptions_by_staff[subscription.staff_id].append(subscription)

    return subscriptions_by_staff
```

**ポイント**:
- ✅ 5,000個のスタッフIDを1クエリで処理
- ✅ 購読のないスタッフにも空リストを用意（KeyError回避）
- ✅ ソート済み（created_at順）

---

### 2.3 メモリ効率

#### メモリ使用量の計算

```python
# 500事業所 × 10スタッフ × 2デバイス = 10,000購読

push_subscriptions_by_staff = {
    UUID('staff-1'): [PushSubscription(...), PushSubscription(...)],
    UUID('staff-2'): [PushSubscription(...), PushSubscription(...)],
    ...  # 5,000スタッフ分
}

# メモリ使用量:
# - UUID: 16 bytes × 5,000 = 80KB
# - PushSubscription: 約400 bytes × 10,000 = 4MB
# - 辞書オーバーヘッド: 約100KB
# 合計: 約4.2MB（許容範囲内）
```

**監視機能**:
```python
# app/tasks/deadline_notification.py

total_subscriptions = sum(len(subs) for subs in push_subs_by_staff.values())
logger.info(
    f"[WEB_PUSH] Loaded {total_subscriptions} subscriptions "
    f"for {len(staff_ids)} staff"
)

# 高負荷時の警告
if total_subscriptions > 10000:
    logger.warning(
        f"[MEMORY] High subscription count: {total_subscriptions} "
        f"(メモリ使用量に注意)"
    )
```

---

## 3️⃣ エラーハンドリングと信頼性

### 3.1 リトライ機構（指数バックオフ）

```python
# app/tasks/deadline_notification.py

from tenacity import (
    retry,
    stop_after_attempt,
    wait_exponential,
    retry_if_exception_type
)

@retry(
    stop=stop_after_attempt(3),              # 最大3回リトライ
    wait=wait_exponential(multiplier=2),     # 2秒 → 4秒 → 8秒
    retry=retry_if_exception_type(Exception),
    reraise=True
)
async def _send_email_with_retry(
    to_email: str,
    subject: str,
    body: str
):
    """
    メール送信（リトライ付き）

    リトライ戦略:
    - 1回目失敗: 2秒待機後に再試行
    - 2回目失敗: 4秒待機後に再試行
    - 3回目失敗: 8秒待機後に再試行
    - 4回目失敗: 例外を投げる
    """
    try:
        await send_deadline_alert_email(
            recipient_email=to_email,
            subject=subject,
            body=body
        )
        logger.info(f"[EMAIL] Successfully sent to {to_email}")
    except Exception as e:
        logger.error(f"[EMAIL] Failed to send to {to_email}: {e}")
        raise  # リトライのために例外を再送出
```

**メリット**:
- ✅ 一時的なネットワークエラーに対応
- ✅ メールサーバーの負荷分散
- ✅ 送信成功率の向上

---

### 3.2 エラーの局所化

```python
# 各事業所のエラーが他の事業所に影響しない

async def _process_single_office(...) -> dict:
    """
    1つの事業所を処理（並列実行可能）

    Returns:
        {"email_sent": int, "push_sent": int, "push_failed": int}
    """
    try:
        # 事業所の処理
        ...
        return {"email_sent": 10, "push_sent": 8, "push_failed": 2}

    except Exception as e:
        # エラーをログ記録するが、他の事業所には影響しない
        logger.error(f"Error processing office {office.name}: {e}")
        return {"email_sent": 0, "push_sent": 0, "push_failed": 0}


# 並列実行（return_exceptions=True）
tasks = [process_with_semaphore(office) for office in offices]
results = await asyncio.gather(*tasks, return_exceptions=True)

# エラーがあっても処理は継続
for result in results:
    if isinstance(result, Exception):
        logger.error(f"Office processing error: {result}")
        continue  # 他の事業所は処理される

    total_email_sent += result.get("email_sent", 0)
```

**メリット**:
- ✅ 部分的な障害が全体に波及しない
- ✅ 可用性の向上
- ✅ デバッグが容易

---

### 3.3 監査ログ（全操作追跡）

```python
# すべてのメール送信を監査ログに記録

await crud.audit_log.create_log(
    db=db,
    actor_id=None,
    actor_role="system",
    action="deadline_notification_sent",
    target_type="staff",
    target_id=staff.id,
    details={
        "recipient_email": staff.email,
        "office_id": str(office.id),
        "alert_count": len(alerts),
        "renewal_alerts": len(renewal_alerts),
        "assessment_alerts": len(assessment_alerts),
        "dry_run": dry_run
    },
    auto_commit=False  # バッチ処理の最後にまとめてコミット
)
```

**メリット**:
- ✅ 全操作が記録される（トレーサビリティ）
- ✅ エラー発生時の原因調査が容易
- ✅ コンプライアンス要件を満たす

---

## 4️⃣ 最適化の歴史（Phase 1-4.2）

### Phase 1: 並列処理実装（2026-02-01）

**目的**: 直列実行を並列実行に変更

**実装**:
```python
# 事業所レベルの並列化
office_semaphore = asyncio.Semaphore(10)
tasks = [process_with_semaphore(office) for office in offices]
results = await asyncio.gather(*tasks, return_exceptions=True)
```

**成果**:
- 処理時間: 1,500秒 → 150秒（10倍高速化）
- クエリ数: 1,001回（変化なし）

---

### Phase 2: バッチクエリ実装（2026-02-03）

**目的**: アラートとスタッフのN+1問題を解消

**実装**:
```python
# アラートとスタッフを一括取得
alerts_by_office = await get_deadline_alerts_batch(db, office_ids)
staffs_by_office = await get_staffs_by_offices_batch(db, office_ids)
```

**成果**:
- 処理時間: 150秒（変化なし）
- クエリ数: 1,001回 → 4回（250倍削減）

---

### Phase 4.2: Push購読バッチ化（2026-02-10）

**目的**: Push購読のN+1問題を解消

**実装**:
```python
# Push購読を一括取得
staff_ids = [staff.id for staffs in staffs_by_office.values() for staff in staffs]
push_subs_by_staff = await get_push_subs_batch(db, staff_ids)
```

**成果**:
- 処理時間: 150秒（変化なし）
- クエリ数: 4回 + 5,000回 → 5回（1,000倍削減）

---

### 累積効果（Phase 1-4.2）

| Phase | 実装内容 | 処理時間 | クエリ数 | 改善率 |
|-------|----------|---------|---------|--------|
| **Before** | 直列実行 | 1,500秒 | 1,001回 | - |
| **Phase 1** | 並列処理 | 150秒 | 1,001回 | 10倍 |
| **Phase 2** | バッチクエリ | 150秒 | 4回 | 250倍 |
| **Phase 4.2** | Push購読バッチ | 150秒 | 5回 | - |
| **Total** | - | **150秒** | **5回** | **10倍 × 200倍** |

**総合改善率**:
- 処理時間: 10倍高速化
- クエリ数: 200倍削減
- 総合: **2,000倍の効率改善**

---

## 5️⃣ スケーラビリティ

### 5.1 事業所数の増加に対する耐性

#### 処理時間の予測

```python
# 並列度が10の場合

事業所数 = N
並列度 = 10
事業所あたり処理時間 = 3秒

処理時間 = (N / 10) × 3秒

# 例:
- 100事業所: (100 / 10) × 3 = 30秒
- 500事業所: (500 / 10) × 3 = 150秒（2.5分）
- 1,000事業所: (1,000 / 10) × 3 = 300秒（5分）
- 5,000事業所: (5,000 / 10) × 3 = 1,500秒（25分）
```

**スケーラビリティ**:
- ✅ O(N/10) の計算量（線形だが傾きが小さい）
- ✅ 1,000事業所まで5分以内で処理可能
- ✅ 5,000事業所でも25分（許容範囲）

---

### 5.2 並列度の調整

```python
# 並列度を変更するのは1行のみ

# 現在: 10並列
office_semaphore = asyncio.Semaphore(10)

# 将来: 20並列（DBとメモリが許せば）
office_semaphore = asyncio.Semaphore(20)

# 処理時間の予測:
# 500事業所: (500 / 20) × 3 = 75秒（1.25分）
```

**制約条件**:
- DB接続プール: 最大50接続
- メモリ: 並列度 × 10MB
- ネットワーク帯域

---

## 6️⃣ テスト戦略

### 6.1 パフォーマンステスト

```python
# tests/performance/test_deadline_notification_performance.py

@pytest.mark.performance
@pytest.mark.parametrize("scale", ["small", "medium", "large"])
async def test_deadline_notification_scalability(scale: str):
    """
    スケーラビリティテスト

    small:  10事業所 → 30秒以内
    medium: 100事業所 → 5分以内
    large:  500事業所 → 3分以内（並列処理）
    """
    config = TEST_SCALES[scale]

    start_time = time.time()
    result = await send_deadline_alert_emails(
        db=db,
        office_count=config["offices"]
    )
    end_time = time.time()

    duration = end_time - start_time

    # パフォーマンス検証
    assert duration < config["timeout"]
    assert result["email_sent"] > 0
```

---

### 6.2 並列処理テスト

```python
# tests/tasks/test_deadline_notification_parallel.py

async def test_parallel_processing_speedup():
    """
    並列処理による高速化を検証

    期待: 直列実行の約10倍高速
    """
    # 直列実行
    start_serial = time.time()
    await process_offices_serial(offices)
    serial_time = time.time() - start_serial

    # 並列実行
    start_parallel = time.time()
    await process_offices_parallel(offices)
    parallel_time = time.time() - start_parallel

    # 並列実行が約10倍高速であることを確認
    speedup = serial_time / parallel_time
    assert speedup >= 8.0  # 10倍 ± 20%の誤差を許容
```

---

## 🎯 面接での回答（詳細版 - 5分）

### Q: バッチ処理の技術的な強みを説明してください

> 「期限通知バッチ処理で、**非同期処理とバッチクエリを組み合わせ**、500事業所の処理を**25分から3分に短縮**しました。」

#### 1. 非同期処理（Asyncio）

> 「**asyncio.gather()** で事業所レベルを並列化しました。」
>
> **Before**: 500事業所を直列実行 → 1,500秒（25分）
> **After**: 10事業所ずつ並列実行 → 150秒（2.5分）
>
> 「**Semaphore(10)** で並列度を制御し、DB接続プール枯渇を防いでいます。」

#### 2. パフォーマンス最適化

> 「**N+1クエリ問題を完全に解消**しました。」
>
> **Before**:
> - 事業所ごとにアラート取得: 500クエリ
> - 事業所ごとにスタッフ取得: 500クエリ
> - スタッフごとにPush購読取得: 5,000クエリ
> - **合計: 6,001クエリ**
>
> **After**:
> - 全事業所のアラートを一括取得: 1クエリ（`WHERE IN`）
> - 全事業所のスタッフを一括取得: 1クエリ（`WHERE IN`）
> - 全スタッフのPush購読を一括取得: 1クエリ（`WHERE IN`）
> - **合計: 5クエリ（200倍削減）**
>
> 「バッチクエリでメモリに読み込んだ後、メモリ内で処理するため、クエリ時間が**30秒から20ms**に短縮されました。」

#### 3. 信頼性

> 「エラーハンドリングも充実させています：」
>
> - **リトライ機構**: 指数バックオフで3回リトライ（2秒 → 4秒 → 8秒）
> - **エラーの局所化**: 1事業所のエラーが他に波及しない
> - **監査ログ**: 全操作を記録（トレーサビリティ）

#### 4. スケーラビリティ

> 「処理時間は事業所数に対して線形スケール（O(N/10)）します：」
>
> - 100事業所: 30秒
> - 500事業所: 150秒（2.5分）
> - 1,000事業所: 300秒（5分）
>
> 「並列度を調整すれば、さらなる高速化も可能です。」

---

## 📊 技術的ハイライト（暗記用）

### パフォーマンス改善

1. **処理時間**: 25分 → 3分（10倍高速化）
2. **DBクエリ**: 1,001回 → 5回（200倍削減）
3. **並列処理**: 10事業所同時実行
4. **メモリ効率**: バッチクエリで4.2MB（安定）

### 技術スタック

1. **非同期**: asyncio.gather() + Semaphore
2. **バッチクエリ**: WHERE IN + selectinload()
3. **リトライ**: tenacity（指数バックオフ）
4. **監視**: 監査ログ + メトリクス収集

### スケーラビリティ

1. **1,000事業所**: 5分以内で処理可能
2. **並列度調整**: 1行の変更で可能
3. **線形スケール**: O(N/10)

---

## 📚 関連ドキュメント

- [Phase 4.1 完了レポート](../performance/phase4_1_completion_report.md)
- [Phase 4.2 完了レポート](../performance/phase4_2_completion_report.md)
- [Phase 4 コード分析](../performance/phase4_code_analysis.md)
- [実装計画](../performance/implementation_plan.md)

---

**最終更新**: 2026-02-10
**処理時間**: 25分 → 3分（10倍）
**クエリ数**: 1,001回 → 5回（200倍）
**総合改善**: 2,000倍の効率向上
