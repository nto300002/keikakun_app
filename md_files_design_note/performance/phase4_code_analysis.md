# Phase 4: 現在のコード詳細分析レポート

**分析日**: 2026-02-09
**対象**: `app/tasks/deadline_notification.py` Line 158-430
**目的**: 並列処理実装の影響範囲とリスクを特定

---

## 📊 現在の処理構造

### 処理フロー（直列実行）

```python
# Line 158-430: 事業所ループ（直列）
for office in offices:  # 500事業所 → 直列実行
    try:
        # 1. アラート取得（メモリ参照、クエリなし）
        alert_response = alerts_by_office.get(office.id)

        # 2. アラート分類（更新期限 / アセスメント未完了）
        for alert in alert_response.alerts:
            if alert.alert_type == "renewal_deadline":
                all_renewal_alerts.append(alert)
            elif alert.alert_type == "assessment_incomplete":
                all_assessment_alerts.append(alert)

        # 3. スタッフ取得（メモリ参照、クエリなし）
        staffs = staffs_by_office.get(office.id, [])

        # 4. 各スタッフに通知送信（直列）
        for staff in staffs:  # 10スタッフ → 直列実行

            # 4a. メール送信（既に並列制御あり）
            async with rate_limit_semaphore:  # Semaphore(5)
                await _send_email_with_retry(...)  # リトライ付き
                await crud.audit_log.create_log(db, ..., auto_commit=False)  # ⚠️ DB書き込み

            # 4b. Web Push通知送信
            if system_notification_enabled:
                subscriptions = await crud.push_subscription.get_by_staff_id(db, staff.id)  # ⚠️ DBクエリ

                for sub in subscriptions:
                    success, should_delete = await send_push_notification(...)

                    if should_delete:
                        await crud.push_subscription.delete_by_endpoint(db, ...)  # ⚠️ DB書き込み

                await crud.audit_log.create_log(db, ..., auto_commit=False)  # ⚠️ DB書き込み

            # カウンター更新（⚠️ 共有変数）
            email_count += 1
            push_sent_count += 1
            push_failed_count += 1

    except Exception as e:
        logger.error(...)  # エラーは記録するが処理は継続
```

---

## 🔍 並列化可能性の分析

### ✅ 並列化可能な部分

#### 1. **事業所単位の処理全体**
```python
# 各事業所の処理は独立している
for office in offices:  # ← これを並列化
    alert_response = alerts_by_office.get(office.id)  # メモリ参照のみ
    staffs = staffs_by_office.get(office.id, [])      # メモリ参照のみ
    # ... 処理 ...
```

**理由**:
- 事業所間のデータ依存がない
- アラートとスタッフはバッチクエリで事前取得済み
- 各事業所のデータはメモリから参照

**並列化効果**:
```
現在: 500事業所 × 3秒/事業所 = 1,500秒（25分）
並列化後: 500事業所 / 10並列 × 3秒 = 150秒（2.5分）

改善率: 10倍高速化
```

---

#### 2. **メール送信（既に並列制御あり）**
```python
async with rate_limit_semaphore:  # Semaphore(5)
    await _send_email_with_retry(...)
```

**現状**: 既に5並列で実行中
**並列化後**: 事業所並列化により実質的な並列度が上がる

---

### ⚠️ 並列化時の注意点

#### 1. **DB書き込み（監査ログ）**

**場所**: Line 269-286, 403-423

```python
await crud.audit_log.create_log(
    db=db,
    actor_id=None,
    actor_role="system",
    action="deadline_notification_sent",
    ...,
    auto_commit=False  # ⚠️ コミットしない
)
```

**リスク**:
- `auto_commit=False` のため、トランザクション管理が必要
- 複数事業所が同時にDB書き込み → トランザクション競合の可能性

**対策**:
- 各事業所処理で独立したトランザクション
- または、監査ログを最後にまとめてコミット

---

#### 2. **DBクエリ（push_subscription）**

**場所**: Line 319

```python
subscriptions = await crud.push_subscription.get_by_staff_id(
    db=db,
    staff_id=staff.id
)  # ⚠️ DBクエリ（N+1の可能性）
```

**問題**:
- 各スタッフごとにDBクエリ発行
- 500事業所 × 10スタッフ = 5,000クエリの可能性

**影響**:
- Phase 2で削減したクエリ数が増加
- DB接続プール枯渇のリスク

**対策**:
- `get_push_subscriptions_batch()` を実装してバッチクエリ化
- または、Push通知を別バッチ処理に分離

---

#### 3. **共有カウンター**

**場所**: Line 248, 267, 342, 372, 383, 390, 398

```python
email_count += 1        # ⚠️ 共有変数
push_sent_count += 1    # ⚠️ 共有変数
push_failed_count += 1  # ⚠️ 共有変数
```

**リスク**:
- 複数事業所が同時にカウンター更新
- Pythonの`+=`は原子的操作ではない → データ競合

**対策**:
```python
# Option 1: 各事業所で結果を返す
result = await process_office(...)
email_count += result["email_sent"]

# Option 2: asyncio.Lock使用
async with counter_lock:
    email_count += 1

# Option 3: threading.local使用（推奨しない）
```

---

#### 4. **rate_limit_semaphore（メール送信制限）**

**場所**: Line 156, 250

```python
rate_limit_semaphore = asyncio.Semaphore(5)  # 同時5件まで

async with rate_limit_semaphore:
    await _send_email_with_retry(...)
```

**現状**: 5並列
**並列化後**: 事業所10並列 × スタッフ並列 → 最大50並列の可能性

**調整が必要**:
- 事業所並列: Semaphore(10)
- メール並列: Semaphore(5)
- **合計並列度**: 50（10×5）

**リスク**:
- メールサービスのレート制限超過
- DB接続プール枯渇

---

## 🏗️ 並列化アーキテクチャ設計

### Option 1: 事業所レベルの並列化（推奨）

```python
async def _process_single_office(
    db: AsyncSession,
    office: Office,
    alerts_by_office: Dict,
    staffs_by_office: Dict,
    dry_run: bool,
    rate_limit_semaphore: asyncio.Semaphore
) -> dict:
    """
    1つの事業所を処理（並列実行可能）

    Returns:
        {"email_sent": int, "push_sent": int, "push_failed": int}
    """
    email_count = 0
    push_sent_count = 0
    push_failed_count = 0

    try:
        alert_response = alerts_by_office.get(office.id)
        if not alert_response or alert_response.total == 0:
            return {"email_sent": 0, "push_sent": 0, "push_failed": 0}

        staffs = staffs_by_office.get(office.id, [])
        if not staffs:
            return {"email_sent": 0, "push_sent": 0, "push_failed": 0}

        for staff in staffs:
            # メール送信処理
            async with rate_limit_semaphore:
                # ... 既存のメール送信ロジック ...
                email_count += 1

            # Push送信処理
            # ... 既存のPush送信ロジック ...
            push_sent_count += 1

        return {
            "email_sent": email_count,
            "push_sent": push_sent_count,
            "push_failed": push_failed_count
        }

    except Exception as e:
        logger.error(f"Error processing office {office.name}: {e}")
        return {"email_sent": 0, "push_sent": 0, "push_failed": 0}


async def send_deadline_alert_emails(...):
    # ... バッチクエリ取得 ...

    # 事業所並列処理
    office_semaphore = asyncio.Semaphore(10)  # 同時10事業所まで

    async def process_with_semaphore(office):
        async with office_semaphore:
            return await _process_single_office(
                db=db,
                office=office,
                alerts_by_office=alerts_by_office,
                staffs_by_office=staffs_by_office,
                dry_run=dry_run,
                rate_limit_semaphore=rate_limit_semaphore
            )

    # 全事業所を並列実行
    tasks = [process_with_semaphore(office) for office in offices]
    results = await asyncio.gather(*tasks, return_exceptions=True)

    # 結果集計
    total_email_sent = 0
    total_push_sent = 0
    total_push_failed = 0

    for result in results:
        if isinstance(result, Exception):
            logger.error(f"Office processing error: {result}")
            continue
        total_email_sent += result.get("email_sent", 0)
        total_push_sent += result.get("push_sent", 0)
        total_push_failed += result.get("push_failed", 0)

    return {
        "email_sent": total_email_sent,
        "push_sent": total_push_sent,
        "push_failed": total_push_failed
    }
```

**メリット**:
- シンプルな実装
- 共有変数の競合を回避（結果を返す）
- エラーハンドリングが容易

**デメリット**:
- push_subscription取得のN+1問題は残る

---

### Option 2: バッチクエリ + 事業所並列化（最適）

```python
# 事前にpush_subscriptionsもバッチ取得
staff_ids = [staff.id for staffs in staffs_by_office.values() for staff in staffs]
push_subscriptions_by_staff = await crud.push_subscription.get_by_staff_ids_batch(
    db=db,
    staff_ids=staff_ids
)

# 事業所並列処理（push_subscriptionsも渡す）
async def _process_single_office(
    ...,
    push_subscriptions_by_staff: Dict
):
    ...
    subscriptions = push_subscriptions_by_staff.get(staff.id, [])
    ...
```

**メリット**:
- push_subscriptionのN+1問題も解消
- 最大のパフォーマンス改善

**デメリット**:
- 実装量が増加（新たなバッチクエリメソッド必要）

---

## 📊 リスク評価

| リスク項目 | 深刻度 | 発生確率 | 対策 |
|-----------|--------|---------|------|
| **トランザクション競合** | 🟡 Medium | 🟡 Medium | 各事業所で独立トランザクション |
| **カウンター競合** | 🟢 Low | 🟢 Low | 結果を返して集計 |
| **DB接続プール枯渇** | 🔴 High | 🟡 Medium | Semaphore(10)で並列度制限 |
| **push_subscription N+1** | 🟡 Medium | 🔴 High | バッチクエリ化（Option 2） |
| **メールレート制限超過** | 🟢 Low | 🟢 Low | rate_limit_semaphore維持 |

---

## 🎯 推奨実装戦略

### Phase 4.1: 事業所並列化（Option 1）

**実装内容**:
1. `_process_single_office()` 関数を作成
2. `asyncio.gather()` で並列実行
3. `Semaphore(10)` で並列度制御
4. 結果を返して集計（共有変数を回避）

**期待効果**:
- 処理時間: 1,500秒 → 150秒（10倍高速化）
- クエリ数: 4回（Phase 2と同じ）
- メモリ: 微増（並列実行分）

**所要時間**: 0.5日

---

### Phase 4.2: push_subscriptionバッチ化（Option 2）

**実装内容**:
1. `get_push_subscriptions_batch()` 実装
2. Phase 4.1に統合

**期待効果**:
- クエリ数: 4回 + 1回（push_subscription） = 5回
- push_subscription: 5,000回 → 1回（5,000倍削減）

**所要時間**: 0.5日

---

## 📝 実装チェックリスト

### Phase 4.1: 事業所並列化

- [ ] `_process_single_office()` 関数作成
- [ ] 共有変数を関数内ローカル変数に変更
- [ ] 結果を辞書で返す
- [ ] `asyncio.Semaphore(10)` 追加
- [ ] `asyncio.gather()` で並列実行
- [ ] エラーハンドリング（`return_exceptions=True`）
- [ ] 結果集計ロジック追加
- [ ] 並列処理テスト実行
- [ ] パフォーマンステスト実行

### Phase 4.2: push_subscriptionバッチ化（オプション）

- [ ] `get_push_subscriptions_batch()` 実装
- [ ] 単体テスト作成
- [ ] メインバッチ処理に統合
- [ ] パフォーマンステスト実行

---

## 🔗 関連ドキュメント

- [Phase 1 完了レポート](./phase1_completion_report.md)
- [Phase 2 実装レビュー](./phase2_implementation_review.md)
- [実装計画](./implementation_plan.md)
- [パフォーマンス要件](./performance_requirements.md)

---

**分析完了日**: 2026-02-09
**分析者**: Claude Sonnet 4.5
**推奨**: Phase 4.1（事業所並列化）から実装開始
