# Performance & SQL Optimization（パフォーマンス・SQL最適化）

## 非同期DB（AsyncSession）設定

**ファイル**: `app/db/session.py`

```python
async_engine = create_async_engine(
    ASYNC_DATABASE_URL,
    pool_size=20,         # 常時維持する接続数
    max_overflow=30,      # プール超過時に追加で許可する接続数（最大50並列）
    pool_pre_ping=True,   # リクエスト前に接続の生存確認
    pool_recycle=300,     # 5分で接続を再作成（Neon auto-suspend 対応）
    echo=False,           # 本番ではSQLログ無効
)

AsyncSessionLocal = async_sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=async_engine,
    expire_on_commit=False,  # コミット後のオブジェクトアクセスで MissingGreenlet を防止
)
```

### ポイント
- `expire_on_commit=False`: コミット後にオブジェクトの属性にアクセスしても再クエリが走らない
- `pool_recycle=300`: Neon DB の自動サスペンドによる切断を防ぐ
- Cloud Run の `concurrency=80` に合わせて `pool_size + max_overflow = 50` に設定

---

## リレーション読み込み戦略

### `selectinload` の使用（N+1防止）

SQLAlchemy 2.0 では遅延ロード（lazy load）を使用しない。すべてのリレーションは `selectinload` で明示的にEAGERロードする。

**禁止パターン（N+1が発生する）**:
```python
# ❌ 遅延ロード: officeアクセスのたびに追加クエリが走る
staff = await db.get(Staff, staff_id)
office_name = staff.office.name  # MissingGreenlet エラー or N+1
```

**正しいパターン**:
```python
# ✅ selectinload: 1クエリでリレーション一括取得
stmt = select(Staff).where(Staff.id == staff_id).options(
    selectinload(Staff.office_associations).selectinload(OfficeStaff.office)
)
result = await db.execute(stmt)
staff = result.scalar_one()
```

### チェーンされた selectinload
**ファイル**: `app/api/deps.py`, `app/crud/crud_staff.py`

```python
# 中間テーブル（OfficeStaff）を経由した読み込み
selectinload(Staff.office_associations).selectinload(OfficeStaff.office)

# 複数リレーションの同時読み込み
.options(
    selectinload(Staff.office_associations).selectinload(OfficeStaff.office),
    selectinload(Staff.mfa_backup_codes),
)
```

### SQLAlchemy 2.0: フィルタリング付き selectinload
```python
# ❌ 間違い（SQLAlchemy 2.0では使用不可）
selectinload(Model.relationship).where(condition)

# ✅ 正しい
selectinload(Model.relationship.and_(condition))
```

---

## N+1問題の対策（バッチクエリ）

### office_ids パターン

**問題**: 500事業所 × 各2クエリ = 1,000クエリ

**解決**: office_ids を一括取得してから `WHERE IN` で一括クエリ

```python
# Step 1: IDリストを取得
office_ids = [office.id for office in offices]

# Step 2: 一括クエリ（O(1) クエリ数）
alerts_by_office = await get_deadline_alerts_batch(
    db=db, office_ids=office_ids
)
# 戻り値: {office_id_1: [alerts], office_id_2: [alerts], ...}

# Step 3: ループ内はメモリ参照のみ（クエリなし）
for office in offices:
    alerts = alerts_by_office.get(office.id, [])
```

**効果**: 1,000クエリ → 3クエリ（333倍削減）

---

## インデックス設計

### Billing モデル（`app/models/billing.py`）
```python
__table_args__ = (
    Index('idx_billings_billing_status', 'billing_status'),
)
```

### Staff モデル（`app/models/staff.py`）
```python
email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
is_test_data: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
```

### AuditLog モデル（`app/models/staff_profile.py`）
```python
# 検索パターンに合わせた複数インデックス
staff_id:    index=True  # 操作者検索
action:      index=True  # アクション種別検索
target_type: index=True  # リソースタイプ検索
office_id:   index=True  # 事業所別検索
timestamp:   index=True  # 時系列検索
is_test_data: index=True # テストデータ除外フィルタ
```

---

## 並列処理（asyncio.gather）

**ファイル**: `app/tasks/deadline_notification.py`

### Semaphore による並行数制御
```python
office_semaphore = asyncio.Semaphore(10)  # 最大10事業所を並列処理

async def process_with_semaphore(office):
    async with office_semaphore:
        return await _process_single_office(office)

tasks = [process_with_semaphore(office) for office in offices]
results = await asyncio.gather(*tasks, return_exceptions=True)
```

### 並列処理の注意点
```python
# ❌ 共有変数は競合が発生する
counter = 0
async def process():
    global counter
    counter += 1  # レースコンディション

# ✅ ローカル変数で返して集計する
async def process():
    return {"count": 1}

results = await asyncio.gather(*tasks)
total = sum(r["count"] for r in results if isinstance(r, dict))
```

**効果**: 処理時間 1,500秒 → 150秒（10倍高速化）

---

## パフォーマンス最適化の成果まとめ

| フェーズ | 対策 | クエリ数（500事業所） | 処理時間 |
|---------|------|-------------------|---------|
| Phase 1（ベースライン） | なし | 1,001 | 1,500秒（25分） |
| Phase 2（バッチクエリ） | office_ids + WHERE IN | 6 | 1,500秒 |
| Phase 4.1（並列処理） | asyncio.gather + Semaphore | 6 | 150秒（2.5分） |
| **合計改善** | | **167倍削減** | **10倍高速化** |

---

## コミットパターン

```python
# ✅ コミット後は必ずrefreshして最新状態を取得
await db.commit()
await db.refresh(obj)

# ✅ エラー時は必ずrollback
try:
    await db.commit()
except Exception:
    await db.rollback()
    raise
```

### 外部キーへのアクセス
```python
# ✅ 外部キーカラムを直接参照（クエリ不要）
office_id = billing.office_id

# ❌ リレーション経由（MissingGreenlet エラーの原因）
office_id = billing.office.id
```
