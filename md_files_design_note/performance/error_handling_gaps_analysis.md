# エラーハンドリング不足分析 - テストインフラ実装

**対象**: Day 1-2 完了実装（バルクインサート + スナップショット管理）
**作成日**: 2026-02-11
**ステータス**: 📋 Analysis Complete - Implementation Pending

---

## 📋 Executive Summary

Day 1-2で実装したテストインフラ（`bulk_factories.py` + `snapshot_manager.py`）は**ハッピーパス**は完全に動作するが、**エラーハンドリングが不足**している。

### 重大度別の不足分類

| 重大度 | 件数 | 影響範囲 |
|--------|------|----------|
| **Critical** 🔴 | 8 | データ破損、部分的な状態、復旧不可 |
| **High** 🟠 | 12 | 操作失敗、不明確なエラー、デバッグ困難 |
| **Medium** 🟡 | 6 | 利便性低下、手動介入必要 |
| **Total** | **26** | - |

---

## 🔴 Critical Priority (Priority 1)

### 1. Snapshot Creation - Partial Write Failure

**問題**: JSON書き込みが途中で失敗すると、**破損したスナップショットファイル**が残る

**現状コード** (`snapshot_manager.py:133-134`):
```python
with open(snapshot_path, "w", encoding="utf-8") as f:
    json.dump(snapshot_data, f, ensure_ascii=False, indent=2, default=str)
```

**シナリオ**:
1. JSON書き込み開始
2. **ディスク容量不足**でエラー発生
3. 部分的に書き込まれたファイルが残る
4. 次回の復元時に**破損したJSONを読み込んで失敗**

**影響**:
- ✅ `snapshot_exists("name")` → `True`（ファイルは存在）
- ❌ `restore_snapshot("name")` → **JSONDecodeError**（破損）
- 🚨 **テストが完全に停止**（復旧不可）

**推奨対応**:
```python
import tempfile
import shutil

# 一時ファイルに書き込み → 成功したらatomic move
temp_path = snapshot_path.with_suffix(".tmp")
try:
    with open(temp_path, "w", encoding="utf-8") as f:
        json.dump(snapshot_data, f, ensure_ascii=False, indent=2, default=str)

    # Atomic move（成功時のみファイルが作成される）
    shutil.move(temp_path, snapshot_path)
except Exception as e:
    # クリーンアップ
    if temp_path.exists():
        temp_path.unlink()
    logger.error(f"❌ Snapshot creation failed: {e}")
    raise
```

---

### 2. Snapshot Restoration - Partial Data Restoration

**問題**: テーブル復元が途中で失敗すると、**部分的にデータが復元された状態**が残る

**現状コード** (`snapshot_manager.py:200-228`):
```python
for table in tables_order:
    rows = snapshot_data["tables"].get(table, [])
    for row in rows:
        # ...
        await db.execute(query, processed_row)  # ❌ エラーでここで停止
    logger.info(f"  Restored {len(rows)} rows to {table}")

await db.commit()  # ← ここに到達しない場合、部分的な状態が残る
```

**シナリオ**:
```
staffs          → ✅ 挿入成功 (1,000件)
offices         → ✅ 挿入成功 (100件)
office_staffs   → ❌ 外部キー制約違反でエラー
welfare_recipients → ⚠️ 実行されない
...
```

**影響**:
- データベースに**不完全な状態**が残る
- 次回のテスト実行時に**予期しないデータが存在**
- `clean_existing=True`でも削除されない（一部のテーブルのみ残存）

**推奨対応**:
```python
try:
    for table in tables_order:
        rows = snapshot_data["tables"].get(table, [])
        for row in rows:
            # ... 挿入処理 ...
            await db.execute(query, processed_row)
        logger.info(f"  Restored {len(rows)} rows to {table}")

    await db.commit()  # ✅ All or nothing
    logger.info(f"✅ Snapshot restored: {name}")

except Exception as e:
    logger.error(f"❌ Snapshot restoration failed: {e}")
    await db.rollback()  # 全てロールバック
    raise RuntimeError(f"Snapshot restoration failed at table '{table}': {e}")
```

---

### 3. Bulk Insert - No Rollback on Failure

**問題**: バッチ挿入が途中で失敗すると、**部分的にデータが挿入された状態**が残る

**現状コード** (`bulk_factories.py:85-91`):
```python
for i in range(0, len(offices), batch_size):
    batch = offices[i:i + batch_size]
    db.add_all(batch)
    await db.flush()  # ❌ エラーが発生した場合、前のバッチは既にflush済み

await db.commit()  # ← ここに到達しない
```

**シナリオ**:
```
Batch 1 (offices 0-499)    → ✅ flush成功
Batch 2 (offices 500-999)  → ❌ unique制約違反でエラー
Batch 3 (offices 1000-...) → ⚠️ 実行されない
```

**影響**:
- データベースに**500件の事業所**が残存（部分的）
- 次回実行時にunique制約違反が発生
- テストの独立性が破壊される

**推奨対応**:
```python
try:
    for i in range(0, len(offices), batch_size):
        batch = offices[i:i + batch_size]
        db.add_all(batch)
        await db.flush()

    await db.commit()  # ✅ All or nothing
    return offices

except Exception as e:
    logger.error(f"❌ Bulk insert failed at batch {i // batch_size}: {e}")
    await db.rollback()  # 全てロールバック
    raise RuntimeError(f"Failed to create offices: {e}")
```

---

### 4. Foreign Key Constraint Violation - Unclear Error

**問題**: 外部キー制約違反時のエラーメッセージが**DB内部エラー**のまま（デバッグ困難）

**現状**: エラーが発生すると、PostgreSQLの生エラーがそのまま出力される
```
sqlalchemy.exc.IntegrityError: (asyncpg.exceptions.ForeignKeyViolationError)
insert or update on table "offices" violates foreign key constraint "offices_created_by_fkey"
DETAIL: Key (created_by)=(uuid) is not present in table "staffs".
```

**シナリオ**: `bulk_create_offices()`で`created_by`のシステムスタッフが存在しない

**影響**:
- テストエンジニアが**原因を理解できない**
- デバッグに時間がかかる
- エラー原因がコードから追跡困難

**推奨対応**:
```python
from sqlalchemy.exc import IntegrityError

try:
    await db.commit()
except IntegrityError as e:
    await db.rollback()

    # 分かりやすいエラーメッセージ
    if "foreign key constraint" in str(e).lower():
        raise RuntimeError(
            f"外部キー制約違反: 参照先のデータが存在しません。"
            f"システムスタッフが作成されているか確認してください。\n"
            f"詳細: {e}"
        )
    elif "unique constraint" in str(e).lower():
        raise RuntimeError(
            f"一意制約違反: 重複するデータが既に存在します。\n"
            f"詳細: {e}"
        )
    else:
        raise
```

---

### 5. Snapshot Restoration - Corrupted JSON

**問題**: JSONファイルが破損している場合、**明確なエラーメッセージなし**

**現状コード** (`snapshot_manager.py:179-180`):
```python
with open(snapshot_path, "r", encoding="utf-8") as f:
    snapshot_data = json.load(f)  # ❌ JSONDecodeErrorが生で出る
```

**シナリオ**:
1. ディスク障害でJSONファイルが破損
2. `restore_snapshot()`実行
3. **JSONDecodeError**: `Expecting value: line 1 column 1 (char 0)`

**影響**:
- エラーメッセージから**原因が不明**
- 手動でファイルを削除する必要がある
- テストが停止する

**推奨対応**:
```python
try:
    with open(snapshot_path, "r", encoding="utf-8") as f:
        snapshot_data = json.load(f)
except json.JSONDecodeError as e:
    raise RuntimeError(
        f"スナップショット '{name}' のJSONファイルが破損しています。\n"
        f"ファイルパス: {snapshot_path}\n"
        f"削除してから再作成してください。\n"
        f"詳細: {e}"
    )
except Exception as e:
    raise RuntimeError(f"スナップショット読み込みエラー: {e}")
```

---

### 6. Schema Mismatch - No Validation

**問題**: スナップショット作成時とDB再スキーマが異なる場合、**復元時にエラー**

**シナリオ**:
1. 2026-01-01: スナップショット作成（`offices`に`region`列なし）
2. 2026-01-15: DBマイグレーション実行（`offices.region NOT NULL`を追加）
3. 2026-01-16: スナップショット復元 → **NOT NULL制約違反**

**現状**: エラーが発生するが、原因が不明確

**影響**:
- 古いスナップショットが**使用不可能**になる
- エラーメッセージから原因が分からない

**推奨対応**:
```python
# スナップショットにスキーマバージョンを保存
snapshot_data = {
    "schema_version": "1.0.0",  # Alembicマイグレーションバージョン
    "name": name,
    "created_at": datetime.now().isoformat(),
    ...
}

# 復元時にバージョンチェック
current_version = await get_current_schema_version(db)
snapshot_version = snapshot_data.get("schema_version", "unknown")

if snapshot_version != current_version:
    logger.warning(
        f"⚠️ スキーマバージョンが一致しません: "
        f"スナップショット={snapshot_version}, 現在={current_version}"
    )
    # Continue with caution or raise error
```

---

### 7. DB Connection Loss - No Retry

**問題**: DB接続が切れた場合、**即座に失敗**（一時的なエラーに対応できない）

**現状**: DBエラーが発生すると即座にエラー終了

**シナリオ**:
- ネットワーク一時断
- DBサーバーの再起動
- 接続プールの枯渇

**影響**:
- **9分間のデータ生成**が最後の1秒で失敗
- 全てやり直し

**推奨対応**:
```python
from tenacity import retry, stop_after_attempt, wait_exponential

@retry(
    stop=stop_after_attempt(3),           # 最大3回
    wait=wait_exponential(multiplier=2),  # 2秒 → 4秒 → 8秒
    reraise=True
)
async def bulk_create_offices_with_retry(db: AsyncSession, count: int):
    return await bulk_create_offices(db, count)
```

---

### 8. Disk Space Check - No Validation

**問題**: スナップショット作成前に**ディスク容量をチェックしない**

**シナリオ**:
1. 100事業所のスナップショット作成開始（予想サイズ: 500MB）
2. ディスク残容量: 100MB
3. **途中で容量不足**エラー → 破損したファイルが残る

**影響**:
- データ生成に9分かけた後で失敗
- 破損ファイルのクリーンアップ必要

**推奨対応**:
```python
import shutil

def check_disk_space(path: Path, required_mb: int = 1000):
    """ディスク容量チェック（最低1GB必要）"""
    stat = shutil.disk_usage(path)
    free_mb = stat.free / (1024 * 1024)

    if free_mb < required_mb:
        raise RuntimeError(
            f"ディスク容量不足: 空き容量 {free_mb:.0f}MB < 必要容量 {required_mb}MB"
        )

# スナップショット作成前にチェック
check_disk_space(SNAPSHOT_DIR, required_mb=1000)
```

---

## 🟠 High Priority (Priority 2)

### 9. Bulk Insert - Invalid Parameters

**問題**: 不正なパラメータ（負の数、0）を渡しても**チェックなし**

**現状コード**:
```python
async def bulk_create_offices(db: AsyncSession, count: int, batch_size: int = 500):
    # count=-100 でも実行される！
```

**影響**:
- `count=-100` → 空のリストが返る（エラーなし）
- `batch_size=0` → **ZeroDivisionError**
- テストが失敗した原因が分からない

**推奨対応**:
```python
if count <= 0:
    raise ValueError(f"count must be positive: {count}")
if batch_size <= 0:
    raise ValueError(f"batch_size must be positive: {batch_size}")
if batch_size > 1000:
    logger.warning(f"Large batch_size may cause memory issues: {batch_size}")
```

---

### 10. Progress Tracking - Long Operations

**問題**: 9分間のデータ生成中、**進捗が不明**（処理が止まったのか判断できない）

**現状**: 最後にのみログ出力
```python
# 9分間沈黙...
logger.info(f"✅ Snapshot created: {snapshot_path}")
```

**影響**:
- テストエンジニアが**処理中か停止中か判断できない**
- CI/CDでタイムアウトする可能性

**推奨対応**:
```python
from tqdm import tqdm

# プログレスバー
for i in tqdm(range(0, len(offices), batch_size), desc="Creating offices"):
    batch = offices[i:i + batch_size]
    db.add_all(batch)
    await db.flush()

# またはログベース
total_batches = (count + batch_size - 1) // batch_size
for batch_idx, i in enumerate(range(0, len(offices), batch_size)):
    batch = offices[i:i + batch_size]
    db.add_all(batch)
    await db.flush()
    logger.info(f"Progress: {batch_idx + 1}/{total_batches} batches completed")
```

---

### 11. Snapshot List - JSON Parse Error

**問題**: `list_snapshots()`で破損したJSONファイルがあると**全体が失敗**

**現状コード** (`snapshot_manager.py:276-285`):
```python
for snapshot_file in SNAPSHOT_DIR.glob("*.json"):
    with open(snapshot_file, "r", encoding="utf-8") as f:
        data = json.load(f)  # ❌ 1つでも破損していると全体が失敗
```

**影響**:
- 1つの破損ファイルで**全スナップショットが表示できない**
- テストが完全に停止

**推奨対応**:
```python
snapshots = []
errors = []

for snapshot_file in SNAPSHOT_DIR.glob("*.json"):
    try:
        with open(snapshot_file, "r", encoding="utf-8") as f:
            data = json.load(f)
        snapshots.append(SnapshotMetadata.from_dict({...}))
    except Exception as e:
        errors.append(f"{snapshot_file.name}: {e}")
        logger.warning(f"⚠️ Skipping corrupted snapshot: {snapshot_file.name}")

if errors:
    logger.warning(f"⚠️ {len(errors)} snapshots could not be loaded:\n" + "\n".join(errors))

return snapshots
```

---

### 12. Snapshot Delete - File Lock

**問題**: ファイルがロックされている場合、**削除失敗**するが明確なエラーなし

**現状コード** (`snapshot_manager.py:308`):
```python
snapshot_path.unlink()  # ❌ PermissionErrorが生で出る
```

**推奨対応**:
```python
try:
    snapshot_path.unlink()
    logger.info(f"🗑️ Snapshot deleted: {name}")
    return True
except PermissionError:
    raise RuntimeError(
        f"スナップショット '{name}' は使用中のため削除できません。\n"
        f"他のプロセスで使用していないか確認してください。"
    )
except Exception as e:
    raise RuntimeError(f"スナップショット削除エラー: {e}")
```

---

### 13. Concurrent Snapshot Creation

**問題**: 複数プロセスで同時に同じスナップショットを作成すると**競合**

**シナリオ**:
1. プロセスA: `create_snapshot("test")` 開始
2. プロセスB: `create_snapshot("test")` 開始
3. プロセスA: ファイル存在チェック → Not found → 書き込み開始
4. プロセスB: ファイル存在チェック → Not found → 書き込み開始
5. **両方が同じファイルに書き込み** → 破損

**推奨対応**:
```python
import fcntl

# ファイルロック
lock_path = SNAPSHOT_DIR / f"{name}.lock"
try:
    with open(lock_path, "w") as lock_file:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)

        # スナップショット作成
        # ...

finally:
    if lock_path.exists():
        lock_path.unlink()
```

---

### 14-20. Additional High Priority Issues

**14. JSONB Serialization Error**:
- `notification_preferences`の一部フィールドが不正な型 → JSON化失敗
- 推奨: `default=str`でフォールバック + ログ警告

**15. Memory Overflow - Large Datasets**:
- 1,000事業所 × 100スタッフ = 100,000件を一度にメモリ展開 → OutOfMemory
- 推奨: メモリ使用量チェック + チャンク処理

**16. Flush Timeout**:
- 大量データのflushが**長時間かかる**場合のタイムアウト未設定
- 推奨: `asyncio.wait_for(db.flush(), timeout=60)`

**17. Snapshot Restoration - Missing Tables**:
- スナップショットに含まれるテーブルがDBに存在しない → 復元失敗
- 推奨: テーブル存在チェック

**18. Audit Log Failure**:
- スナップショット作成/復元の監査ログが失敗しても**処理が継続**
- 推奨: 監査ログ失敗時の明示的なエラーまたは警告

**19. Unique Constraint Violation - Retry**:
- 偶発的なユニーク制約違反（UUIDの衝突など）に対するリトライなし
- 推奨: tenacityでリトライ（最大3回）

**20. Session Expiration**:
- 長時間の処理中にDBセッションが期限切れ → 接続エラー
- 推奨: セッションのkeepalive設定

---

## 🟡 Medium Priority (Priority 3)

### 21. Snapshot Overwrite Protection

**問題**: 誤って既存スナップショットを上書きする危険性

**現状**: `ValueError`を出すが、**force=True**オプションがない

**推奨対応**:
```python
async def create_snapshot(
    db: AsyncSession,
    name: str,
    description: str = "",
    overwrite: bool = False  # 明示的な上書き許可
):
    if snapshot_path.exists() and not overwrite:
        raise ValueError(
            f"Snapshot '{name}' already exists. "
            f"Use overwrite=True to replace it."
        )
```

---

### 22-26. Additional Medium Priority Issues

**22. Snapshot Versioning**:
- スナップショットのバージョン管理なし（古いスナップショットの識別困難）
- 推奨: `name_v1.json`, `name_v2.json`のようなバージョニング

**23. Cleanup Strategy**:
- 古いスナップショットの自動削除機能なし（ディスク容量浪費）
- 推奨: 古いスナップショット（30日以上）の自動削除

**24. Snapshot Comparison**:
- 2つのスナップショットの差分比較機能なし
- 推奨: `compare_snapshots(name1, name2)` 機能

**25. Incremental Snapshot**:
- 差分スナップショット機能なし（毎回フルバックアップ）
- 推奨: 増分スナップショット対応

**26. Snapshot Compression**:
- JSONファイルが非圧縮（500MB → 50MBに圧縮可能）
- 推奨: gzip圧縮対応

---

## 📊 Summary Table

| カテゴリ | Critical | High | Medium | Total |
|---------|----------|------|--------|-------|
| Snapshot Creation | 3 | 4 | 3 | 10 |
| Snapshot Restoration | 3 | 2 | 0 | 5 |
| Bulk Insert | 2 | 4 | 0 | 6 |
| General | 0 | 2 | 3 | 5 |
| **Total** | **8** | **12** | **6** | **26** |

---

## 🎯 Recommended Implementation Order

### Phase 1: Critical Fixes (1-2 days)
1. ✅ Atomic snapshot write (Issue #1)
2. ✅ Rollback on restoration failure (Issue #2)
3. ✅ Rollback on bulk insert failure (Issue #3)
4. ✅ Friendly error messages (Issue #4)
5. ✅ Corrupted JSON handling (Issue #5)
6. ✅ Schema version check (Issue #6)
7. ✅ DB retry mechanism (Issue #7)
8. ✅ Disk space check (Issue #8)

### Phase 2: High Priority (2-3 days)
9. Parameter validation (Issue #9)
10. Progress tracking (Issue #10)
11. Robust snapshot listing (Issue #11)
12. File lock handling (Issue #12)
13. Concurrent creation protection (Issue #13)
14-20. Other high priority issues

### Phase 3: Medium Priority (Optional)
21-26. Nice-to-have features

---

## 🔍 Testing Strategy

### Critical Error Scenarios (Must Test)

**Test 1: Disk Full During Snapshot Creation**
```python
async def test_snapshot_creation_disk_full(monkeypatch):
    """ディスク容量不足時の動作確認"""
    def mock_disk_usage(path):
        return type('obj', (object,), {'free': 100})()  # 100 bytes only

    monkeypatch.setattr(shutil, 'disk_usage', mock_disk_usage)

    with pytest.raises(RuntimeError, match="ディスク容量不足"):
        await create_snapshot(db, "test")

    # ファイルが作成されていないことを確認
    assert not (SNAPSHOT_DIR / "test.json").exists()
```

**Test 2: DB Connection Loss During Bulk Insert**
```python
async def test_bulk_insert_connection_loss(db_session, monkeypatch):
    """DB接続断時のロールバック確認"""
    call_count = 0

    async def mock_flush_with_failure():
        nonlocal call_count
        call_count += 1
        if call_count == 2:
            raise asyncpg.exceptions.ConnectionDoesNotExistError()
        await original_flush()

    monkeypatch.setattr(db_session, 'flush', mock_flush_with_failure)

    with pytest.raises(RuntimeError):
        await bulk_create_offices(db_session, count=1000, batch_size=500)

    # 部分的なデータが残っていないことを確認
    result = await db_session.execute(
        select(func.count()).select_from(Office).where(Office.is_test_data == True)
    )
    assert result.scalar() == 0  # ✅ Rollback成功
```

**Test 3: Corrupted JSON Restoration**
```python
async def test_restore_corrupted_json(db_session):
    """破損JSONからの復元エラーハンドリング"""
    snapshot_path = SNAPSHOT_DIR / "corrupted.json"
    snapshot_path.write_text("{ invalid json }")

    with pytest.raises(RuntimeError, match="JSONファイルが破損"):
        await restore_snapshot(db_session, "corrupted")
```

---

## 📚 Related Documents

- [Day 1-2 Completion Report](./day1_2_completion_report.md)
- [Test Infrastructure Plan](./test_infrastructure_implementation_plan.md)
- [Performance Review](./review/comprehensive_review.md)

---

## 🏆 Expected Outcome

### Before (Current State)
- ✅ ハッピーパスは完全動作
- ❌ エラー時の動作が不明確
- ❌ 部分的な状態が残る可能性
- ❌ デバッグが困難

### After (With Error Handling)
- ✅ ハッピーパスは完全動作
- ✅ エラー時に明確なメッセージ
- ✅ All-or-nothing（原子性保証）
- ✅ 復旧可能なエラーハンドリング
- ✅ 進捗追跡とデバッグ容易性

---

**作成日**: 2026-02-11
**作成者**: Claude Sonnet 4.5
**ステータス**: 📋 Analysis Complete - Ready for Implementation

---

**Note**: この分析は、実装の**優先順位付け**と**工数見積もり**のための資料です。全ての項目を実装する必要はありません。Critical（Priority 1）の8項目を実装すれば、実用上十分な信頼性が得られます。
