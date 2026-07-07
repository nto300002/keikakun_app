# テストインフラ改善 実装計画（Option 2）

**計画策定日**: 2026-02-09
**実装期間**: 2週間（10営業日）
**目標**: パフォーマンステストの実行可能化（100事業所規模）

---

## 📋 実装概要

### 目的
1. テストデータ生成速度を12倍改善（60分 → 5分）
2. 100事業所規模のパフォーマンステストを実行可能に
3. CI/CDパイプラインに統合可能なテスト環境構築

### スコープ
- ✅ テストデータ生成の最適化（バルクインサート、スナップショット）
- ✅ テスト用DB環境の強化（専用インスタンス、接続プール拡大）
- ✅ 段階的テストの実装（small/medium/large）
- ❌ CI/CD統合（今回のスコープ外、将来検討）
- ❌ 監視ダッシュボード（今回のスコープ外、将来検討）

---

## 📅 実装スケジュール

### Week 1: テストデータ生成の最適化（5日間）

```
Day 1-2: バルクインサート実装
Day 3-4: スナップショット機能実装
Day 5:   Week 1 統合テスト・検証
```

### Week 2: テスト用DB環境の強化（5日間）

```
Day 6-7: 専用DBインスタンス構築
Day 8-9: 段階的テストの実装
Day 10:  Week 2 統合テスト・最終検証
```

---

## 🎯 Week 1: テストデータ生成の最適化

### Day 1-2: バルクインサート実装

#### タスク1.1: バルクインサート用ヘルパー関数の作成

**ファイル**: `tests/conftest.py`（または新規 `tests/performance/bulk_factories.py`）

**実装内容**:

```python
"""
バルクインサート用のファクトリヘルパー
"""
from typing import List, Dict
from uuid import UUID
from sqlalchemy.ext.asyncio import AsyncSession
from app.models import Office, Staff, WelfareRecipient, IndividualSupportPlan, SupportPlanCycle


async def bulk_create_offices(
    db: AsyncSession,
    count: int,
    batch_size: int = 100
) -> List[Office]:
    """
    事業所を一括作成

    Args:
        db: データベースセッション
        count: 作成する事業所数
        batch_size: バッチサイズ

    Returns:
        List[Office]: 作成した事業所のリスト
    """
    offices = []
    for i in range(count):
        office = Office(
            name=f"テスト事業所{i:04d}",
            address=f"東京都テスト区{i}",
            phone_number=f"03-0000-{i:04d}",
            is_test_data=True
        )
        offices.append(office)

    # バルクインサート（batch_sizeずつ）
    for i in range(0, len(offices), batch_size):
        batch = offices[i:i + batch_size]
        db.add_all(batch)
        await db.flush()

    await db.commit()

    # IDを取得するためにrefresh
    for office in offices:
        await db.refresh(office)

    return offices


async def bulk_create_staffs(
    db: AsyncSession,
    offices: List[Office],
    count_per_office: int,
    batch_size: int = 100
) -> Dict[UUID, List[Staff]]:
    """
    スタッフを一括作成

    Args:
        db: データベースセッション
        offices: 事業所リスト
        count_per_office: 事業所あたりのスタッフ数
        batch_size: バッチサイズ

    Returns:
        Dict[UUID, List[Staff]]: {office_id: [staff, ...]}
    """
    staffs = []
    staffs_by_office = {office.id: [] for office in offices}

    for office in offices:
        for i in range(count_per_office):
            staff = Staff(
                office_id=office.id,
                first_name=f"スタッフ{i:03d}",
                last_name=f"事業所{offices.index(office):04d}",
                full_name=f"事業所{offices.index(office):04d} スタッフ{i:03d}",
                email=f"staff_{office.id}_{i}@example.com",
                hashed_password="$2b$12$dummy_hash_for_testing",
                role="employee",
                is_test_data=True,
                notification_preferences={
                    "in_app_notification": True,
                    "email_notification": True,
                    "system_notification": False,
                    "email_threshold_days": 30,
                    "push_threshold_days": 10
                }
            )
            staffs.append(staff)
            staffs_by_office[office.id].append(staff)

    # バルクインサート
    for i in range(0, len(staffs), batch_size):
        batch = staffs[i:i + batch_size]
        db.add_all(batch)
        await db.flush()

    await db.commit()

    # IDを取得するためにrefresh
    for staff in staffs:
        await db.refresh(staff)

    return staffs_by_office


async def bulk_create_welfare_recipients(
    db: AsyncSession,
    offices: List[Office],
    count_per_office: int,
    batch_size: int = 100
) -> Dict[UUID, List[WelfareRecipient]]:
    """
    利用者を一括作成

    Args:
        db: データベースセッション
        offices: 事業所リスト
        count_per_office: 事業所あたりの利用者数
        batch_size: バッチサイズ

    Returns:
        Dict[UUID, List[WelfareRecipient]]: {office_id: [recipient, ...]}
    """
    recipients = []
    recipients_by_office = {office.id: [] for office in offices}

    for office in offices:
        for i in range(count_per_office):
            recipient = WelfareRecipient(
                office_id=office.id,
                first_name=f"利用者{i:03d}",
                last_name=f"事業所{offices.index(office):04d}",
                full_name=f"事業所{offices.index(office):04d} 利用者{i:03d}",
                date_of_birth="1990-01-01",
                is_test_data=True
            )
            recipients.append(recipient)
            recipients_by_office[office.id].append(recipient)

    # バルクインサート
    for i in range(0, len(recipients), batch_size):
        batch = recipients[i:i + batch_size]
        db.add_all(batch)
        await db.flush()

    await db.commit()

    # IDを取得するためにrefresh
    for recipient in recipients:
        await db.refresh(recipient)

    return recipients_by_office


async def bulk_create_support_plans_and_cycles(
    db: AsyncSession,
    recipients_by_office: Dict[UUID, List[WelfareRecipient]],
    staffs_by_office: Dict[UUID, List[Staff]],
    batch_size: int = 100
) -> tuple[List[IndividualSupportPlan], List[SupportPlanCycle]]:
    """
    個別支援計画とサイクルを一括作成

    Args:
        db: データベースセッション
        recipients_by_office: {office_id: [recipient, ...]}
        staffs_by_office: {office_id: [staff, ...]}
        batch_size: バッチサイズ

    Returns:
        tuple: (plans, cycles)
    """
    from datetime import date, timedelta

    plans = []
    cycles = []

    for office_id, recipients in recipients_by_office.items():
        staffs = staffs_by_office[office_id]
        if not staffs:
            continue

        for recipient in recipients:
            # 個別支援計画作成
            plan = IndividualSupportPlan(
                office_id=office_id,
                welfare_recipient_id=recipient.id,
                responsible_staff_id=staffs[0].id,  # 最初のスタッフ
                is_test_data=True
            )
            plans.append(plan)

    # 計画をバルクインサート
    for i in range(0, len(plans), batch_size):
        batch = plans[i:i + batch_size]
        db.add_all(batch)
        await db.flush()

    # IDを取得
    for plan in plans:
        await db.refresh(plan)

    # サイクル作成
    today = date.today()
    for plan in plans:
        # 期限が近いサイクルを作成（30日以内）
        cycle = SupportPlanCycle(
            individual_support_plan_id=plan.id,
            start_date=today - timedelta(days=335),  # 11ヶ月前開始
            end_date=today + timedelta(days=25),     # 25日後終了
            status="active",
            is_test_data=True
        )
        cycles.append(cycle)

    # サイクルをバルクインサート
    for i in range(0, len(cycles), batch_size):
        batch = cycles[i:i + batch_size]
        db.add_all(batch)
        await db.flush()

    await db.commit()

    return plans, cycles
```

**期待される改善**:
```
Before: 5,000スタッフ × 0.2秒 = 1,000秒（16分）
After:  5,000スタッフ ÷ 100バッチ × 0.5秒 = 25秒

改善率: 40倍高速化
```

---

#### タスク1.2: パフォーマンステストフィクスチャの更新

**ファイル**: `tests/performance/test_deadline_notification_performance.py`

**実装内容**:

```python
import pytest_asyncio
from tests.performance.bulk_factories import (
    bulk_create_offices,
    bulk_create_staffs,
    bulk_create_welfare_recipients,
    bulk_create_support_plans_and_cycles
)


@pytest_asyncio.fixture
async def performance_test_data_medium(db_session: AsyncSession):
    """
    中規模パフォーマンステスト用データ（100事業所）

    データ構成:
    - 100事業所
    - 1,000スタッフ（各事業所10名）
    - 10,000利用者（各事業所100名）
    - 10,000個別支援計画
    - 10,000サイクル（期限30日以内）

    期待生成時間: 5分以内
    """
    print("\n⏳ 中規模テストデータ生成開始（100事業所、1,000スタッフ）...")

    # Step 1: 事業所作成（バルクインサート）
    offices = await bulk_create_offices(db_session, count=100)
    print(f"✅ 事業所作成完了: {len(offices)}件")

    # Step 2: スタッフ作成（バルクインサート）
    staffs_by_office = await bulk_create_staffs(
        db_session,
        offices=offices,
        count_per_office=10
    )
    total_staffs = sum(len(staffs) for staffs in staffs_by_office.values())
    print(f"✅ スタッフ作成完了: {total_staffs}件")

    # Step 3: 利用者作成（バルクインサート）
    recipients_by_office = await bulk_create_welfare_recipients(
        db_session,
        offices=offices,
        count_per_office=100
    )
    total_recipients = sum(len(recs) for recs in recipients_by_office.values())
    print(f"✅ 利用者作成完了: {total_recipients}件")

    # Step 4: 個別支援計画とサイクル作成（バルクインサート）
    plans, cycles = await bulk_create_support_plans_and_cycles(
        db_session,
        recipients_by_office=recipients_by_office,
        staffs_by_office=staffs_by_office
    )
    print(f"✅ 個別支援計画作成完了: {len(plans)}件")
    print(f"✅ サイクル作成完了: {len(cycles)}件")

    print("✅ 中規模テストデータ生成完了")

    return {
        "offices": offices,
        "staffs_by_office": staffs_by_office,
        "recipients_by_office": recipients_by_office,
        "plans": plans,
        "cycles": cycles,
        "expected_emails": total_staffs  # 全スタッフにメール送信
    }
```

---

### Day 3-4: スナップショット機能実装

#### タスク2.1: スナップショット管理ユーティリティの作成

**ファイル**: `tests/performance/snapshot_manager.py`（新規作成）

**実装内容**:

```python
"""
テストデータスナップショット管理

目的: テストデータを事前生成してスナップショット化し、テスト実行時に高速リストア
"""
import subprocess
import os
from pathlib import Path
from datetime import datetime
from typing import Optional
import logging

logger = logging.getLogger(__name__)

SNAPSHOT_DIR = Path(__file__).parent / "snapshots"
SNAPSHOT_DIR.mkdir(exist_ok=True)


class SnapshotManager:
    """テストデータスナップショット管理クラス"""

    def __init__(self, db_url: str):
        """
        Args:
            db_url: データベース接続URL（例: postgresql://user:pass@host:port/dbname）
        """
        self.db_url = db_url
        self._parse_db_url()

    def _parse_db_url(self):
        """DB URLをパース"""
        # postgresql://user:pass@host:port/dbname
        from urllib.parse import urlparse
        parsed = urlparse(self.db_url)

        self.db_host = parsed.hostname
        self.db_port = parsed.port or 5432
        self.db_name = parsed.path.lstrip('/')
        self.db_user = parsed.username
        self.db_password = parsed.password

    def create_snapshot(self, snapshot_name: str) -> Path:
        """
        現在のテストデータのスナップショットを作成

        Args:
            snapshot_name: スナップショット名（例: "medium_100_offices"）

        Returns:
            Path: 作成されたスナップショットファイルのパス
        """
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        snapshot_file = SNAPSHOT_DIR / f"{snapshot_name}_{timestamp}.sql"

        logger.info(f"Creating snapshot: {snapshot_file}")

        # pg_dumpでスナップショット作成
        env = os.environ.copy()
        env['PGPASSWORD'] = self.db_password

        cmd = [
            "pg_dump",
            "-h", self.db_host,
            "-p", str(self.db_port),
            "-U", self.db_user,
            "-d", self.db_name,
            "-f", str(snapshot_file),
            "--clean",  # DROP文を含める
            "--if-exists",  # IF EXISTSを追加
            "--no-owner",  # オーナー情報を含めない
            "--no-privileges"  # 権限情報を含めない
        ]

        result = subprocess.run(cmd, env=env, capture_output=True, text=True)

        if result.returncode != 0:
            logger.error(f"Snapshot creation failed: {result.stderr}")
            raise RuntimeError(f"Failed to create snapshot: {result.stderr}")

        logger.info(f"✅ Snapshot created: {snapshot_file} ({snapshot_file.stat().st_size / 1024 / 1024:.2f} MB)")

        # 最新スナップショットへのシンボリックリンクを作成
        latest_link = SNAPSHOT_DIR / f"{snapshot_name}_latest.sql"
        if latest_link.exists() or latest_link.is_symlink():
            latest_link.unlink()
        latest_link.symlink_to(snapshot_file.name)

        return snapshot_file

    def restore_snapshot(self, snapshot_name: str, use_latest: bool = True) -> None:
        """
        スナップショットからテストデータをリストア

        Args:
            snapshot_name: スナップショット名
            use_latest: Trueの場合、最新のスナップショットを使用

        Raises:
            FileNotFoundError: スナップショットが見つからない場合
        """
        if use_latest:
            snapshot_file = SNAPSHOT_DIR / f"{snapshot_name}_latest.sql"
            if not snapshot_file.exists():
                raise FileNotFoundError(f"Snapshot not found: {snapshot_file}")
        else:
            # 特定のスナップショットファイルを探す
            snapshots = list(SNAPSHOT_DIR.glob(f"{snapshot_name}_*.sql"))
            if not snapshots:
                raise FileNotFoundError(f"No snapshots found for: {snapshot_name}")
            snapshot_file = max(snapshots, key=lambda p: p.stat().st_mtime)

        logger.info(f"Restoring snapshot: {snapshot_file}")

        # psqlでリストア
        env = os.environ.copy()
        env['PGPASSWORD'] = self.db_password

        cmd = [
            "psql",
            "-h", self.db_host,
            "-p", str(self.db_port),
            "-U", self.db_user,
            "-d", self.db_name,
            "-f", str(snapshot_file),
            "-q"  # 静かに実行
        ]

        result = subprocess.run(cmd, env=env, capture_output=True, text=True)

        if result.returncode != 0:
            logger.error(f"Snapshot restore failed: {result.stderr}")
            raise RuntimeError(f"Failed to restore snapshot: {result.stderr}")

        logger.info(f"✅ Snapshot restored: {snapshot_file}")

    def list_snapshots(self) -> list[Path]:
        """
        利用可能なスナップショットのリストを取得

        Returns:
            list[Path]: スナップショットファイルのリスト
        """
        snapshots = list(SNAPSHOT_DIR.glob("*.sql"))
        # シンボリックリンクを除外
        snapshots = [s for s in snapshots if not s.is_symlink()]
        snapshots.sort(key=lambda p: p.stat().st_mtime, reverse=True)
        return snapshots

    def delete_old_snapshots(self, snapshot_name: str, keep_count: int = 3) -> None:
        """
        古いスナップショットを削除

        Args:
            snapshot_name: スナップショット名
            keep_count: 保持するスナップショット数
        """
        snapshots = list(SNAPSHOT_DIR.glob(f"{snapshot_name}_*.sql"))
        snapshots = [s for s in snapshots if not s.is_symlink()]
        snapshots.sort(key=lambda p: p.stat().st_mtime, reverse=True)

        # keep_count以降のファイルを削除
        for snapshot in snapshots[keep_count:]:
            logger.info(f"Deleting old snapshot: {snapshot}")
            snapshot.unlink()
```

---

#### タスク2.2: スナップショット生成スクリプトの作成

**ファイル**: `tests/performance/generate_snapshots.py`（新規作成）

**実装内容**:

```python
"""
テストデータスナップショット生成スクリプト

実行方法:
    docker exec keikakun_app-backend-1 python -m tests.performance.generate_snapshots
"""
import asyncio
import os
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

from tests.performance.snapshot_manager import SnapshotManager
from tests.performance.bulk_factories import (
    bulk_create_offices,
    bulk_create_staffs,
    bulk_create_welfare_recipients,
    bulk_create_support_plans_and_cycles
)


async def generate_medium_snapshot(db_url: str):
    """
    中規模テストデータのスナップショットを生成

    データ構成:
    - 100事業所
    - 1,000スタッフ
    - 10,000利用者
    - 10,000計画・サイクル
    """
    print("\n" + "=" * 80)
    print("📸 中規模スナップショット生成開始（100事業所）")
    print("=" * 80)

    # DBセッション作成
    engine = create_async_engine(db_url, echo=False)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    async with async_session() as db:
        # データ生成
        print("\n⏳ テストデータ生成中...")

        offices = await bulk_create_offices(db, count=100)
        print(f"✅ 事業所: {len(offices)}件")

        staffs_by_office = await bulk_create_staffs(db, offices, count_per_office=10)
        total_staffs = sum(len(s) for s in staffs_by_office.values())
        print(f"✅ スタッフ: {total_staffs}件")

        recipients_by_office = await bulk_create_welfare_recipients(db, offices, count_per_office=100)
        total_recipients = sum(len(r) for r in recipients_by_office.values())
        print(f"✅ 利用者: {total_recipients}件")

        plans, cycles = await bulk_create_support_plans_and_cycles(
            db, recipients_by_office, staffs_by_office
        )
        print(f"✅ 計画: {len(plans)}件、サイクル: {len(cycles)}件")

    await engine.dispose()

    # スナップショット作成
    print("\n⏳ スナップショット作成中...")
    snapshot_manager = SnapshotManager(db_url)
    snapshot_file = snapshot_manager.create_snapshot("medium_100_offices")

    print("\n" + "=" * 80)
    print(f"✅ スナップショット生成完了: {snapshot_file.name}")
    print("=" * 80)


async def main():
    """メイン処理"""
    db_url = os.getenv("TEST_DATABASE_URL")
    if not db_url:
        print("❌ ERROR: TEST_DATABASE_URL environment variable not set")
        return

    await generate_medium_snapshot(db_url)


if __name__ == "__main__":
    asyncio.run(main())
```

---

#### タスク2.3: スナップショット利用のフィクスチャ実装

**ファイル**: `tests/performance/test_deadline_notification_performance.py`

**実装内容**:

```python
@pytest_asyncio.fixture
async def performance_test_data_medium_snapshot(db_session: AsyncSession):
    """
    中規模パフォーマンステスト用データ（スナップショット利用）

    スナップショットが存在する場合はリストアし、存在しない場合は生成
    """
    from tests.performance.snapshot_manager import SnapshotManager

    db_url = os.getenv("TEST_DATABASE_URL")
    snapshot_manager = SnapshotManager(db_url)

    snapshot_name = "medium_100_offices"

    try:
        # スナップショットが存在すればリストア
        print(f"\n⏳ スナップショットからリストア中: {snapshot_name}")
        snapshot_manager.restore_snapshot(snapshot_name, use_latest=True)
        print("✅ スナップショットリストア完了（約30秒）")

        # データの検証（事業所数を確認）
        from app.models import Office
        stmt = select(Office).where(Office.is_test_data == True)
        result = await db_session.execute(stmt)
        offices = result.scalars().all()

        if len(offices) < 100:
            raise ValueError(f"Insufficient offices in snapshot: {len(offices)} < 100")

    except (FileNotFoundError, ValueError) as e:
        # スナップショットがない、または不正な場合は生成
        print(f"\n⚠️  スナップショットが利用できません: {e}")
        print("⏳ 新規テストデータ生成中...")

        # 既存のmediumフィクスチャを使用
        data = await performance_test_data_medium(db_session)
        return data

    # 生成済みデータの情報を返す
    return {
        "snapshot_restored": True,
        "expected_emails": 1000  # 100事業所 × 10スタッフ
    }
```

**期待される改善**:
```
Before: 100事業所生成 = 60分
After:  スナップショットリストア = 30秒

改善率: 120倍高速化
```

---

### Day 5: Week 1 統合テスト・検証

#### タスク3.1: バルクインサートのパフォーマンステスト

**テスト内容**:
```python
@pytest.mark.asyncio
@pytest.mark.performance
async def test_bulk_insert_performance(db_session):
    """
    バルクインサートのパフォーマンステスト

    検証項目:
    - 100事業所を5分以内で生成
    - データの整合性確認
    """
    import time
    start_time = time.time()

    # バルクインサートで生成
    offices = await bulk_create_offices(db_session, count=100)
    staffs_by_office = await bulk_create_staffs(db_session, offices, count_per_office=10)

    elapsed = time.time() - start_time

    # 検証
    assert len(offices) == 100
    assert sum(len(s) for s in staffs_by_office.values()) == 1000
    assert elapsed < 300, f"Generation took too long: {elapsed}s > 300s"

    print(f"✅ 100事業所生成時間: {elapsed:.1f}秒")
```

#### タスク3.2: スナップショット機能のテスト

**テスト内容**:
```python
@pytest.mark.asyncio
@pytest.mark.performance
async def test_snapshot_restore_performance(db_session):
    """
    スナップショットリストアのパフォーマンステスト

    検証項目:
    - リストアが30秒以内に完了
    - データの整合性確認
    """
    import time
    from tests.performance.snapshot_manager import SnapshotManager

    db_url = os.getenv("TEST_DATABASE_URL")
    snapshot_manager = SnapshotManager(db_url)

    start_time = time.time()

    # リストア
    snapshot_manager.restore_snapshot("medium_100_offices", use_latest=True)

    elapsed = time.time() - start_time

    # 検証
    assert elapsed < 30, f"Restore took too long: {elapsed}s > 30s"

    print(f"✅ スナップショットリストア時間: {elapsed:.1f}秒")
```

---

## 🎯 Week 2: テスト用DB環境の強化

### Day 6-7: 専用DBインスタンス構築

#### タスク4.1: Docker Compose設定の作成

**ファイル**: `docker-compose.test.yml`（新規作成）

**実装内容**:

```yaml
version: '3.8'

services:
  # パフォーマンステスト専用DBインスタンス
  test-performance-db:
    image: postgres:15-alpine
    container_name: keikakun_test_performance_db
    environment:
      POSTGRES_DB: keikakun_test_performance
      POSTGRES_USER: test_user
      POSTGRES_PASSWORD: test_password
      # パフォーマンス最適化設定
      POSTGRES_INITDB_ARGS: "-E UTF8 --locale=C"
    command:
      - "postgres"
      # 接続設定
      - "-c" "max_connections=200"                # 通常: 100
      - "-c" "superuser_reserved_connections=3"

      # メモリ設定
      - "-c" "shared_buffers=2GB"                 # 通常: 128MB
      - "-c" "effective_cache_size=6GB"           # 通常: 4GB
      - "-c" "work_mem=50MB"                      # 通常: 4MB
      - "-c" "maintenance_work_mem=512MB"         # 通常: 64MB

      # WAL設定
      - "-c" "wal_buffers=16MB"                   # 通常: -1 (自動)
      - "-c" "checkpoint_completion_target=0.9"   # 通常: 0.5
      - "-c" "max_wal_size=2GB"                   # 通常: 1GB

      # クエリプランナー設定
      - "-c" "random_page_cost=1.1"               # 通常: 4.0 (SSD想定)
      - "-c" "effective_io_concurrency=200"       # 通常: 1

      # タイムアウト設定
      - "-c" "statement_timeout=600000"           # 10分
      - "-c" "idle_in_transaction_session_timeout=3600000"  # 1時間

      # ロギング設定
      - "-c" "log_min_duration_statement=1000"    # 1秒以上のクエリをログ
      - "-c" "log_line_prefix=%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h "

    ports:
      - "5433:5432"  # ホストの5433ポートにマッピング

    volumes:
      - test_performance_db_data:/var/lib/postgresql/data
      # スナップショットディレクトリをマウント
      - ./tests/performance/snapshots:/snapshots:ro

    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U test_user -d keikakun_test_performance"]
      interval: 10s
      timeout: 5s
      retries: 5

    # リソース制限
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 4G
        reservations:
          cpus: '1.0'
          memory: 2G

volumes:
  test_performance_db_data:
    driver: local
```

#### タスク4.2: テスト用DB接続設定の作成

**ファイル**: `tests/performance/config.py`（新規作成）

**実装内容**:

```python
"""
パフォーマンステスト用DB設定
"""
import os
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker


def get_performance_test_db_url() -> str:
    """
    パフォーマンステスト用DB URLを取得

    環境変数の優先順位:
    1. PERFORMANCE_TEST_DATABASE_URL（専用DB）
    2. TEST_DATABASE_URL（通常テストDB）
    """
    db_url = os.getenv(
        "PERFORMANCE_TEST_DATABASE_URL",
        os.getenv("TEST_DATABASE_URL")
    )

    if not db_url:
        raise ValueError("Database URL not configured for performance tests")

    return db_url


def create_performance_test_engine():
    """
    パフォーマンステスト用のDBエンジンを作成

    設定:
    - 接続プールサイズ: 20（通常: 10）
    - オーバーフロー: 30（通常: 10）
    - プールタイムアウト: 60秒（通常: 30秒）
    """
    db_url = get_performance_test_db_url()

    engine = create_async_engine(
        db_url,
        echo=False,  # パフォーマンステストではログ無効化
        pool_size=20,
        max_overflow=30,
        pool_timeout=60,
        pool_recycle=3600,  # 1時間
        pool_pre_ping=True,  # 接続チェック
        connect_args={
            "server_settings": {
                "application_name": "performance_test",
                "statement_timeout": "600000"  # 10分
            }
        }
    )

    return engine


def create_performance_test_session():
    """
    パフォーマンステスト用のセッションファクトリを作成
    """
    engine = create_performance_test_engine()
    async_session = sessionmaker(
        engine,
        class_=AsyncSession,
        expire_on_commit=False,
        autoflush=False  # パフォーマンステストでは手動flush
    )
    return async_session
```

---

### Day 8-9: 段階的テストの実装

#### タスク5.1: テスト規模定義の実装

**ファイル**: `tests/performance/test_scales.py`（新規作成）

**実装内容**:

```python
"""
パフォーマンステストの規模定義
"""
from dataclasses import dataclass
from typing import Literal


@dataclass
class TestScale:
    """テスト規模の定義"""
    name: str
    offices: int
    staff_per_office: int
    users_per_office: int
    frequency: Literal["every_commit", "daily", "weekly"]
    timeout: int  # 秒
    description: str


# テスト規模の定義
TEST_SCALES = {
    "small": TestScale(
        name="small",
        offices=10,
        staff_per_office=10,
        users_per_office=100,
        frequency="every_commit",
        timeout=600,  # 10分
        description="小規模テスト（毎commit実行）"
    ),
    "medium": TestScale(
        name="medium",
        offices=100,
        staff_per_office=10,
        users_per_office=100,
        frequency="daily",
        timeout=1800,  # 30分
        description="中規模テスト（毎日実行）"
    ),
    "large": TestScale(
        name="large",
        offices=500,
        staff_per_office=10,
        users_per_office=100,
        frequency="weekly",
        timeout=3600,  # 60分
        description="大規模テスト（毎週実行）"
    )
}


def get_test_scale(scale_name: str) -> TestScale:
    """
    テスト規模を取得

    Args:
        scale_name: 規模名（small/medium/large）

    Returns:
        TestScale: テスト規模定義

    Raises:
        ValueError: 不正な規模名
    """
    if scale_name not in TEST_SCALES:
        raise ValueError(f"Invalid test scale: {scale_name}. Must be one of {list(TEST_SCALES.keys())}")

    return TEST_SCALES[scale_name]
```

#### タスク5.2: スケーラビリティテストの実装

**ファイル**: `tests/performance/test_deadline_notification_performance.py`

**実装内容**:

```python
import pytest
import os
from tests.performance.test_scales import get_test_scale, TEST_SCALES


@pytest.mark.asyncio
@pytest.mark.performance
@pytest.mark.parametrize("scale_name", ["small", "medium", "large"])
async def test_deadline_notification_scalability(
    db_session: AsyncSession,
    scale_name: str
):
    """
    期限通知バッチのスケーラビリティテスト

    テスト規模:
    - small: 10事業所（毎commit）
    - medium: 100事業所（毎日）
    - large: 500事業所（毎週）

    環境変数でテスト規模を制御:
    - PERF_TEST_SCALE=small: 小規模のみ実行（デフォルト）
    - PERF_TEST_SCALE=medium: 中規模まで実行
    - PERF_TEST_SCALE=large: 全規模実行
    """
    # 環境変数から許可された規模を取得
    allowed_scale = os.getenv("PERF_TEST_SCALE", "small")

    # スキップ判定
    if scale_name == "large" and allowed_scale != "large":
        pytest.skip(f"Large scale test skipped (PERF_TEST_SCALE={allowed_scale})")

    if scale_name == "medium" and allowed_scale == "small":
        pytest.skip(f"Medium scale test skipped (PERF_TEST_SCALE={allowed_scale})")

    # テスト規模を取得
    scale = get_test_scale(scale_name)

    print("\n" + "=" * 80)
    print(f"📊 スケーラビリティテスト: {scale.description}")
    print(f"   事業所数: {scale.offices}")
    print(f"   タイムアウト: {scale.timeout}秒")
    print("=" * 80)

    # テストデータ準備
    if scale_name == "small":
        # 既存のsmallフィクスチャを使用
        test_data = await performance_test_data_small(db_session)
    elif scale_name == "medium":
        # スナップショット利用
        test_data = await performance_test_data_medium_snapshot(db_session)
    else:
        # largeは手動生成（時間がかかる）
        pytest.skip("Large scale test requires manual setup")

    # パフォーマンステスト実行
    import time
    from app.tasks.deadline_notification import send_deadline_alert_emails

    start_time = time.time()

    result = await send_deadline_alert_emails(db=db_session, dry_run=True)

    elapsed = time.time() - start_time

    # 結果検証
    print(f"\n📈 テスト結果:")
    print(f"   処理時間: {elapsed:.1f}秒")
    print(f"   送信メール数: {result['email_sent']}件")
    print(f"   1事業所あたり: {elapsed / scale.offices:.2f}秒")

    # タイムアウトチェック
    assert elapsed < scale.timeout, (
        f"Processing time exceeded timeout: {elapsed:.1f}s > {scale.timeout}s"
    )

    # パフォーマンス目標チェック
    if scale_name == "medium":
        # 中規模: 5分以内
        assert elapsed < 300, f"Medium scale should complete in 5 minutes, took {elapsed:.1f}s"
```

---

### Day 10: Week 2 統合テスト・最終検証

#### タスク6.1: 全体統合テストの実行

**テスト内容**:
```bash
# 小規模テスト（毎回実行）
PERF_TEST_SCALE=small pytest tests/performance/ -v -m performance

# 中規模テスト（スナップショット利用）
PERF_TEST_SCALE=medium pytest tests/performance/ -v -m performance

# スナップショット生成
docker exec keikakun_app-backend-1 python -m tests.performance.generate_snapshots
```

#### タスク6.2: パフォーマンス測定レポート作成

**測定項目**:
- [ ] バルクインサート速度（100事業所生成時間）
- [ ] スナップショットリストア速度
- [ ] 小規模テスト実行時間（10事業所）
- [ ] 中規模テスト実行時間（100事業所）
- [ ] DBクエリ数の確認
- [ ] メモリ使用量の確認

---

## 📊 成功基準

### 必須基準（Must Have）

| 項目 | 目標 | 現状 | 達成 |
|------|------|------|------|
| 100事業所データ生成 | < 5分 | 60分 | ⏳ |
| スナップショットリストア | < 30秒 | N/A | ⏳ |
| 100事業所テスト実行 | < 5分 | N/A | ⏳ |
| DBタイムアウトエラー | 0件 | 発生中 | ⏳ |

### 推奨基準（Should Have）

| 項目 | 目標 | 備考 |
|------|------|------|
| 10事業所テスト実行 | < 30秒 | CI/CD統合用 |
| スナップショット管理 | 自動化 | 古いスナップショット削除 |
| ドキュメント | 完備 | 使用方法、トラブルシューティング |

---

## 🎯 リスク管理

### 識別されたリスク

| リスク | 影響 | 確率 | 対策 |
|--------|------|------|------|
| バルクインサートの複雑性 | 🟡 中 | 🟡 中 | 段階的実装、単体テスト |
| DB設定の互換性問題 | 🟠 高 | 🟢 低 | 専用インスタンス使用 |
| スナップショットの容量 | 🟡 中 | 🟡 中 | 圧縮、古いファイル削除 |
| 実装遅延 | 🟠 高 | 🟡 中 | 優先度付け、スコープ調整 |

### 対策詳細

1. **実装遅延リスク**
   - Week 1 Day 3でマイルストーン確認
   - 遅延時はスナップショット機能を後回し
   - 最低限バルクインサートは完了させる

2. **DB設定問題**
   - 専用インスタンスで影響範囲を限定
   - 既存テストに影響を与えない
   - ロールバック可能な設定

---

## 📚 ドキュメント作成

### 作成するドキュメント

1. **実装ガイド**（本ドキュメント）
   - ✅ 完了

2. **使用方法ドキュメント**
   - スナップショット生成方法
   - テスト実行方法
   - トラブルシューティング

3. **パフォーマンステストレポート**
   - 測定結果
   - 改善効果
   - 推奨事項

---

## 🚀 次のステップ

### 実装後の展開

1. **CI/CD統合**（将来）
   - GitHub Actions対応
   - 自動パフォーマンステスト
   - 性能劣化検知

2. **監視ダッシュボード**（将来）
   - Grafana統合
   - リアルタイム監視
   - アラート設定

3. **さらなる最適化**（将来）
   - 並列生成
   - 増分スナップショット
   - テストデータテンプレート

---

## ✅ 実装開始チェックリスト

### 事前準備
- [ ] Docker環境の確認
- [ ] PostgreSQL 15の確認
- [ ] テストDB接続の確認
- [ ] ディスク容量の確認（スナップショット用: 最低10GB）

### Week 1 準備
- [ ] `tests/performance/bulk_factories.py` 作成
- [ ] `tests/performance/snapshot_manager.py` 作成
- [ ] `tests/performance/generate_snapshots.py` 作成

### Week 2 準備
- [ ] `docker-compose.test.yml` 作成
- [ ] `tests/performance/config.py` 作成
- [ ] `tests/performance/test_scales.py` 作成

---

**計画策定完了日**: 2026-02-09
**実装開始予定**: 即座
**完了予定**: 2週間後（2026-02-23）
**期待効果**: テストデータ生成12倍高速化、100事業所テスト実行可能化
