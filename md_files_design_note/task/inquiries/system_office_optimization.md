# システム事務所の最適化実装

## 問題

非ログインユーザーからの問い合わせが受信側で表示されない問題が発生していました。

### 原因

1. 問い合わせ送信時に一時的なシステム事務所を作成
2. 送信成功後、一時事務所を削除
3. `Message.office_id` が `ondelete="CASCADE"` のため、事務所削除時に関連する Message と InquiryDetail も CASCADE 削除
4. 結果として、送信は成功するが受信側では問い合わせが見つからない

## 解決策

### 1. システム事務所の再利用

一時事務所を毎回作成・削除するのではなく、1つのシステム事務所を作成して再利用する方式に変更。

### 2. 効率的な検索クエリ

**実装**: `app/utils/temp_office.py` の `get_or_create_system_office()`

```python
async def get_or_create_system_office(
    db: AsyncSession,
    admin_staff_id: uuid.UUID
) -> uuid.UUID:
    """
    既存のシステム事務所を取得、なければ作成します。

    計算量: O(1) - インデックスを使用した効率的な検索
    """
    # LIMIT 1 で最初の1件のみ取得
    # is_deleted インデックスと name フィルタで高速検索
    stmt = select(Office.id).where(
        Office.name == "__TEMP_SYSTEM__",
        Office.is_deleted == False
    ).limit(1)

    result = await db.execute(stmt)
    existing_office_id = result.scalar_one_or_none()

    if existing_office_id:
        logger.info(f"既存のシステム事務所を再利用: {existing_office_id}")
        return existing_office_id

    # なければ新規作成
    new_office = await create_temporary_system_office(db, admin_staff_id)
    await db.flush()
    return new_office.id
```

### 3. データベースインデックスの追加

**ファイル**: `app/models/office.py`

```python
class Office(Base):
    __tablename__ = 'offices'

    __table_args__ = (
        # システム事務所検索用の複合インデックス
        Index('ix_offices_name_is_deleted', 'name', 'is_deleted'),
    )
```

**効果**:
- `name = '__TEMP_SYSTEM__' AND is_deleted = false` のクエリが高速化
- 複合インデックスにより、WHERE 句の両条件を効率的に評価

### 4. 問い合わせエンドポイントの修正

**ファイル**: `app/api/v1/endpoints/inquiries.py`

**変更前**:
```python
# 一時事務所を作成
temp_office = await create_temporary_system_office(db, admin_id)
office_id = temp_office.id

# 問い合わせ送信後に削除
await delete_temporary_system_office(db, temp_office.id)
```

**変更後**:
```python
# システム事務所を取得または作成（削除しない）
office_id = await get_or_create_system_office(db, admin_staff_id)

# 削除処理なし（再利用のため）
```

## パフォーマンス

### 計算量

- **検索クエリ**: O(1)
  - 複合インデックス `(name, is_deleted)` を使用
  - `LIMIT 1` により最初の1件で検索終了

- **挿入クエリ**: O(log n)
  - 初回のみ実行
  - 通常の INSERT + インデックス更新

### メモリ使用量

- システム事務所レコード: 1件のみ
- 以前の実装: 問い合わせごとに作成・削除で断片化の可能性

## データベースマイグレーション

**ファイル**: `md_files_design_note/task/inquiries/migration_add_office_name_index.sql`

```sql
-- UPGRADE
CREATE INDEX IF NOT EXISTS ix_offices_name_is_deleted
ON offices (name, is_deleted);

-- DOWNGRADE
-- DROP INDEX IF EXISTS ix_offices_name_is_deleted;
```

## テスト確認項目

1. **非ログインユーザーからの問い合わせ**
   - ✓ 送信成功（200 OK）
   - ✓ 受信側で問い合わせが表示される
   - ✓ システム事務所が再利用される（2回目以降）

2. **ログイン済みユーザーからの問い合わせ**
   - ✓ 自分の事務所を使用
   - ✓ システム事務所は作成されない

3. **パフォーマンス**
   - ✓ クエリ実行時間が一定（O(1)）
   - ✓ インデックスが使用されることを EXPLAIN で確認

## 注意事項

### システム事務所のクリーンアップ

現在の実装では、システム事務所 `__TEMP_SYSTEM__` は削除されません。
これは意図的な設計であり、以下の理由があります：

1. **データ整合性**: 問い合わせレコードが参照するため
2. **パフォーマンス**: 再利用により新規作成のコストを削減
3. **シンプルさ**: 削除タイミングの管理が不要

**将来的な拡張**:
- 古い問い合わせが削除された場合、不要になったシステム事務所を検出して削除するバッチ処理
- ただし、優先度は低い（1レコードのみなので影響は軽微）

## 変更ファイル一覧

1. `k_back/app/utils/temp_office.py`
   - `get_or_create_system_office()` 関数を最適化

2. `k_back/app/models/office.py`
   - `Index('ix_offices_name_is_deleted', 'name', 'is_deleted')` を追加

3. `k_back/app/api/v1/endpoints/inquiries.py`
   - `create_temporary_system_office()` → `get_or_create_system_office()` に変更
   - 事務所削除処理を削除

4. `md_files_design_note/task/inquiries/migration_add_office_name_index.sql`
   - マイグレーションSQL

5. `md_files_design_note/task/inquiries/system_office_optimization.md`
   - 本ドキュメント

## 関連Issue

- 問題: 非ログインユーザーからの問い合わせが受信側で表示されない
- 原因: CASCADE削除による問い合わせデータの消失
- 解決: システム事務所の再利用による削除処理の排除
