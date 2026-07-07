# テスト仕様書: Gmail期限通知バッチ処理の最適化

**パフォーマンステスト・負荷テスト・回帰テストの詳細仕様**

---

## 📋 テスト概要

### テストの目的

1. **パフォーマンス検証**: 500事業所規模で5分以内に処理完了
2. **品質保証**: 既存機能が破壊されていないことを確認
3. **スケーラビリティ検証**: 1,000事業所以上でも動作可能
4. **回帰防止**: 将来の変更で性能が劣化しないことを保証

### テストカテゴリ

| カテゴリ | 目的 | 実行頻度 |
|---------|------|---------|
| **パフォーマンステスト** | 処理時間・メモリ・クエリ数の測定 | PR作成時 |
| **負荷テスト** | 500事業所規模での動作確認 | リリース前 |
| **回帰テスト** | 既存機能の互換性確認 | 毎回のCI |
| **統合テスト** | エンドツーエンドの動作確認 | 毎回のCI |

---

## 🧪 パフォーマンステスト

### テストファイル構成

```
tests/
└── performance/
    ├── __init__.py
    ├── test_deadline_notification_performance.py  # メインテスト
    ├── conftest.py                                # 共通フィクスチャ
    └── README.md                                  # 実行手順
```

---

### Test 1: 基本パフォーマンステスト

**ファイル**: `tests/performance/test_deadline_notification_performance.py`

**テスト関数**: `test_deadline_notification_performance_500_offices`

**目的**: 500事業所での基本性能を測定

**テストデータ**:
```python
- 事業所数: 500
- スタッフ数: 5,000（各事業所10人）
- 利用者数: 5,000（各事業所10人、全員に更新期限アラート）
- アラート数: 5,000（各利用者1件、残り15日）
```

**測定項目**:

1. **処理時間**: `time.time()` で測定
2. **メモリ使用量**: `psutil.Process().memory_info().rss` で測定
3. **DBクエリ数**: SQLAlchemy event listener でカウント
4. **送信メール数**: 返り値の `email_sent` フィールド

**受け入れ基準**:

```python
assert elapsed_time < 300, "処理時間が5分を超える"
assert memory_increase < 50, "メモリ増加が50MBを超える"
assert query_count < 100, "DBクエリ数が100を超える"
assert result['email_sent'] == 5000, "送信メール数が期待値と異なる"
```

**実装例**:

```python
@pytest.mark.asyncio
@pytest.mark.performance
@pytest.mark.timeout(600)  # 10分タイムアウト
async def test_deadline_notification_performance_500_offices(
    db_session: AsyncSession,
    performance_test_data: dict,
    query_counter: QueryCounter
):
    """500事業所での基本パフォーマンス測定"""

    # 初期メモリ測定
    process = psutil.Process(os.getpid())
    memory_before = process.memory_info().rss / 1024 / 1024

    # 処理時間測定
    start_time = time.time()
    result = await send_deadline_alert_emails(db=db_session, dry_run=True)
    elapsed_time = time.time() - start_time

    # メモリ測定
    memory_after = process.memory_info().rss / 1024 / 1024
    memory_increase = memory_after - memory_before

    # 検証
    assert elapsed_time < 300
    assert memory_increase < 50
    assert query_counter.count < 100
    assert result['email_sent'] == 5000
```

---

### Test 2: クエリ効率テスト（N+1検出）

**テスト関数**: `test_query_efficiency_no_n_plus_1`

**目的**: N+1クエリ問題が解消されているか検証

**検証方法**:

クエリ数が事業所数に比例しない（O(1)）ことを確認

```python
# クエリ数の理論値
# 事業所取得: 1クエリ
# アラート取得: 2クエリ（更新期限 + アセスメント）
# スタッフ取得: 1クエリ
# 合計: 4クエリ（定数）

assert query_count < office_count * 0.2, "クエリ数が事業所数に比例している"
```

**受け入れ基準**:

```python
# 500事業所の場合
office_count = 500
query_count = 4  # 目標

# 許容範囲: 事業所数の20%以下
max_allowed = office_count * 0.2  # 100クエリ

assert query_count < max_allowed
```

---

### Test 3: メモリ効率テスト（リーク検出）

**テスト関数**: `test_memory_efficiency_chunk_processing`

**目的**: メモリリークがないことを確認

**検証方法**:

1. 処理前のメモリ測定
2. 処理実行
3. ピークメモリ測定
4. GC実行
5. GC後のメモリ測定

```python
import gc

# 処理前
gc.collect()
memory_baseline = get_memory()

# 処理実行
await send_deadline_alert_emails(db=db_session)
memory_peak = get_memory()

# GC実行
gc.collect()
await asyncio.sleep(0.1)
memory_after_gc = get_memory()

# メモリリーク判定（GC後に80%以上回収される）
memory_leak_ratio = (memory_after_gc - memory_baseline) / (memory_peak - memory_baseline)
assert memory_leak_ratio < 0.2, "メモリリークの可能性"
```

**受け入れ基準**:

- ピークメモリ増加: < 50MB
- GC後のメモリ増加: < 10MB（ピークの20%以下）

---

### Test 4: 並列処理効率テスト

**テスト関数**: `test_parallel_processing_speedup`

**目的**: 並列化により処理速度が向上しているか確認

**検証方法**:

1事業所あたりの処理時間から並列度を推定

```python
total_time = elapsed_time
office_count = 500
time_per_office = total_time / office_count

# 1事業所あたり0.1秒以下なら10並列以上相当
estimated_parallelism = 1 / time_per_office

assert time_per_office < 0.1, "並列化が不十分"
assert estimated_parallelism >= 10, "並列度が目標未満"
```

**受け入れ基準**:

- 1事業所あたりの処理時間: < 0.1秒
- 推定並列度: >= 10倍

---

## 🏋️ 負荷テスト

### Test 5: スケーラビリティテスト

**テスト関数**: `test_scalability_1000_offices`

**目的**: 1,000事業所以上でも動作することを確認

**テストデータ**:
```python
- 事業所数: 1,000
- スタッフ数: 10,000
- 利用者数: 10,000
```

**受け入れ基準**:

```python
assert elapsed_time < 600, "処理時間が10分を超える"
assert memory_increase < 100, "メモリ増加が100MBを超える"
```

**実行頻度**: リリース前のみ（時間がかかるため）

---

### Test 6: エラー耐性テスト

**テスト関数**: `test_error_resilience`

**目的**: 一部の事業所でエラーが発生しても全体が継続

**テストシナリオ**:

1. 500事業所を作成
2. 10事業所のメールアドレスを不正な形式に設定
3. バッチ処理実行
4. 490事業所は正常処理、10事業所はエラー

**受け入れ基準**:

```python
result = await send_deadline_alert_emails(db=db_session, dry_run=False)

# 490事業所 × 10スタッフ = 4,900件送信成功
assert result['email_sent'] == 4900

# エラーログに10件の失敗記録
# （監査ログをチェック）
```

---

## 🔄 回帰テスト

### Test 7: 後方互換性テスト

**ファイル**: `tests/tasks/test_deadline_notification_backward_compat.py`

**目的**: 最適化により既存機能が破壊されていないことを確認

**テストケース**:

#### 7.1: dry_runモード

```python
@pytest.mark.asyncio
async def test_backward_compatibility_dry_run(db_session):
    """dry_runモードが正しく動作するか"""
    result = await send_deadline_alert_emails(db=db_session, dry_run=True)

    # メール送信はされない
    assert result['email_sent'] > 0  # カウントはされる

    # 監査ログは作成されない
    audit_logs = await get_audit_logs(db_session)
    assert len(audit_logs) == 0
```

#### 7.2: 閾値フィルタリング

```python
@pytest.mark.asyncio
async def test_backward_compatibility_threshold_filtering(db_session):
    """閾値フィルタリングが正しく動作するか"""
    # Staff A: email_threshold_days=10
    # Staff B: email_threshold_days=20
    # 利用者: 残り15日のアラート

    result = await send_deadline_alert_emails(db=db_session, dry_run=True)

    # Staff Aは受信しない（15日 > 10日）
    # Staff Bは受信する（15日 <= 20日）
    assert result['email_sent'] == 1
```

#### 7.3: 監査ログ

```python
@pytest.mark.asyncio
async def test_backward_compatibility_audit_logs(db_session):
    """監査ログが正確に記録されるか"""
    await send_deadline_alert_emails(db=db_session, dry_run=False)

    audit_logs = await get_audit_logs(db_session)

    # 各送信に対して監査ログが作成される
    assert len(audit_logs) > 0

    for log in audit_logs:
        assert log.action == "deadline_notification_sent"
        assert log.target_type == "email_notification"
        assert "renewal_alert_count" in log.details
```

---

## 🧩 統合テスト

### Test 8: エンドツーエンドテスト

**ファイル**: `tests/integration/test_deadline_notification_e2e.py`

**目的**: 実際の運用フローを再現

**テストシナリオ**:

1. スケジューラーが0:00に起動
2. 平日判定（週末・祝日はスキップ）
3. 事業所データ取得
4. アラート取得
5. メール送信
6. 監査ログ記録
7. 結果返却

**実装例**:

```python
@pytest.mark.asyncio
async def test_e2e_scheduled_execution(db_session):
    """スケジューラー経由での実行"""
    # スケジューラーをモック
    with patch('app.scheduler.deadline_notification_scheduler.scheduled_send_alerts') as mock_scheduler:
        # 実際の関数を呼び出す
        mock_scheduler.side_effect = lambda: send_deadline_alert_emails(db=db_session)

        # スケジューラー実行
        await mock_scheduler()

        # 結果確認
        assert mock_scheduler.called
```

---

## 🔧 テストフィクスチャ

### フィクスチャ1: QueryCounter

**目的**: SQLクエリをカウント

```python
class QueryCounter:
    def __init__(self):
        self.count = 0
        self.queries = []

    def __call__(self, conn, cursor, statement, parameters, context, executemany):
        self.count += 1
        self.queries.append({
            'statement': statement,
            'parameters': parameters
        })

@pytest.fixture
def query_counter(db_session):
    counter = QueryCounter()
    event.listen(db_session.sync_session.bind, "before_cursor_execute", counter)
    yield counter
    event.remove(db_session.sync_session.bind, "before_cursor_execute", counter)
```

---

### フィクスチャ2: performance_test_data

**目的**: 大量テストデータを効率的に生成

```python
@pytest.fixture
async def performance_test_data(db_session: AsyncSession):
    """500事業所、5,000スタッフ、5,000利用者を作成"""

    # 管理者作成
    admin = Staff(...)
    db_session.add(admin)
    await db_session.flush()

    # 500事業所をループで作成
    for i in range(500):
        office = Office(...)
        db_session.add(office)
        await db_session.flush()

        # 各事業所に10人のスタッフ
        for j in range(10):
            staff = Staff(...)
            db_session.add(staff)
            db_session.add(OfficeStaff(...))

        # 各事業所に10人の利用者 + アラート
        for k in range(10):
            recipient = WelfareRecipient(...)
            db_session.add(recipient)
            await db_session.flush()

            cycle = SupportPlanCycle(
                welfare_recipient_id=recipient.id,
                next_renewal_deadline=date.today() + timedelta(days=15),
                is_latest_cycle=True,
                ...
            )
            db_session.add(cycle)

        # 100事業所ごとにコミット（メモリ節約）
        if (i + 1) % 100 == 0:
            await db_session.commit()

    await db_session.commit()

    return {
        "office_count": 500,
        "staff_count": 5000,
        "recipient_count": 5000
    }
```

---

## 🚀 テスト実行方法

### 基本コマンド

```bash
# 全パフォーマンステスト実行
docker exec keikakun_app-backend-1 pytest tests/performance/ -v -m performance

# 特定のテストのみ実行
docker exec keikakun_app-backend-1 pytest tests/performance/test_deadline_notification_performance.py::test_deadline_notification_performance_500_offices -v

# 詳細ログ付き実行
docker exec keikakun_app-backend-1 pytest tests/performance/ -v -s --log-cli-level=INFO
```

### カバレッジ付き実行

```bash
# カバレッジ測定
docker exec keikakun_app-backend-1 pytest tests/ --cov=app.tasks.deadline_notification --cov-report=html

# カバレッジレポート確認
open htmlcov/index.html
```

### CI/CD統合

```yaml
# .github/workflows/test.yml
- name: Run performance tests
  run: |
    docker exec keikakun_app-backend-1 pytest tests/performance/ -v -m performance --json-report --json-report-file=performance_report.json

- name: Check performance thresholds
  run: |
    python scripts/check_performance_thresholds.py performance_report.json
```

---

## 📊 テスト結果フォーマット

### JSON出力

```json
{
  "test_name": "test_deadline_notification_performance_500_offices",
  "status": "passed",
  "duration": 180.5,
  "metrics": {
    "processing_time": 180.5,
    "memory_increase_mb": 35.2,
    "query_count": 4,
    "emails_sent": 5000
  },
  "thresholds": {
    "processing_time": 300,
    "memory_increase_mb": 50,
    "query_count": 100
  }
}
```

---

## 🎯 テスト成功基準

### 全テストパス

- [ ] test_deadline_notification_performance_500_offices ✅
- [ ] test_query_efficiency_no_n_plus_1 ✅
- [ ] test_memory_efficiency_chunk_processing ✅
- [ ] test_parallel_processing_speedup ✅
- [ ] test_scalability_1000_offices ✅
- [ ] test_error_resilience ✅
- [ ] test_backward_compatibility_* (全て) ✅
- [ ] test_e2e_scheduled_execution ✅

### カバレッジ

- **全体**: 85%以上
- **deadline_notification.py**: 90%以上

### パフォーマンス目標達成

- **処理時間**: < 5分（500事業所）
- **DBクエリ数**: < 10回
- **メモリ使用量**: < 50MB

---

**最終更新日**: 2026-02-08
**作成者**: Claude Sonnet 4.5
