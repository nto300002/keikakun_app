# テストエラー解決進捗レポート

**日付**: 2026-02-12
**対象**: 本番環境 & ローカル環境のテストエラー修正

---

## 📋 エラー概要

### 本番環境
```
FAILED tests/crud/test_crud_archived_staff.py::TestCRUDArchivedStaff::test_anonymization
AssertionError: assert False
  where False = '693668366'.isupper()
```
- **ステータス**: ✅ **修正完了**

### ローカル環境
1. `tests/performance/test_snapshot_manager.py` (3件)
   - `test_snapshot_create_and_restore`
   - `test_snapshot_list`
   - `test_snapshot_performance_comparison`
   - **ステータス**: 🔧 **修正中**

2. `tests/services/test_withdrawal_service.py` (1件)
   - `test_office_withdrawal_cancels_billing_without_subscription`
   - **ステータス**: ⏳ **未着手**

3. `tests/performance/test_bulk_factories.py` (1件)
   - `test_bulk_create_performance_100_offices`
   - **ステータス**: ⏳ **未着手**

4. `tests/performance/test_deadline_notification_performance.py` (4件ERROR + 2件FAILED)
   - `test_deadline_notification_performance_500_offices` (ERROR)
   - `test_query_efficiency_no_n_plus_1` (ERROR)
   - `test_memory_efficiency_chunk_processing` (ERROR)
   - `test_parallel_processing_speedup` (ERROR)
   - `test_error_resilience` (FAILED)
   - `test_performance_test_data_generation_speed` (FAILED)
   - **ステータス**: ⏳ **未着手**

---

## ✅ 完了タスク

### 1. 本番環境エラー修正: `test_anonymization`

**問題**:
- 匿名化IDが数字のみ（例: `'693668366'`）の場合、`isupper()` が `False` を返す
- Pythonの `isupper()` は、cased character（大文字・小文字を持つ文字）が存在しない場合 `False` を返す
- 数字には大文字・小文字の概念がないため失敗

**根本原因**:
```python
# crud_archived_staff.py:32-33
hash_hex = hashlib.sha256(str(staff_id).encode()).hexdigest()
return hash_hex[:9].upper()  # SHA-256の16進数 → 0-9, A-F
```
- SHA-256ハッシュは16進数（0-9, a-f）
- 先頭9文字を取ると、偶然すべて数字になる可能性がある

**修正内容**:
```diff
# tests/crud/test_crud_archived_staff.py:120-124

- # 匿名化IDが9文字の英数字（SHA-256の先頭9文字）
+ # 匿名化IDが9文字の16進数大文字表記（SHA-256の先頭9文字）
  anon_id = archive.anonymized_full_name.replace("スタッフ-", "")
  assert len(anon_id) == 9
  assert anon_id.isalnum()
- assert anon_id.isupper()
+ # 16進数の大文字表記であることを確認（0-9, A-F のみ）
+ assert all(c in '0123456789ABCDEF' for c in anon_id)
```

**結果**: ✅ テストの期待値を修正し、16進数であることを明示的にチェック

---

## 🔧 進行中タスク

### 2. ローカル環境エラー修正: `test_snapshot_manager.py`

**推定原因**: 外部キー制約エラー - テーブル削除順序の問題

#### 外部キー依存関係
```
offices.created_by → staffs.id (参照制約)
office_staffs.office_id → offices.id
office_staffs.staff_id → staffs.id
```

**正しい削除順序**:
```
1. office_staffs (関連テーブル)
2. offices (staffs.id を参照)
3. staffs (参照される側、最後に削除)
```

#### 修正1: `snapshot_manager.py:_clean_test_data()`

**Before**:
```python
tables = [
    "support_plan_cycles",
    "office_welfare_recipients",
    "welfare_recipients",
    "office_staffs",
    "staffs",    # ← 先に削除すると offices.created_by が参照エラー
    "offices",
]
```

**After**:
```python
tables = [
    "support_plan_cycles",
    "office_welfare_recipients",
    "welfare_recipients",
    "office_staffs",
    "offices",   # ← staffs より先に削除（created_by 外部キー制約）
    "staffs",
]
```

**ステータス**: ✅ **修正完了**

#### 修正2: `test_snapshot_manager.py:205-206`

**問題箇所**:
```python
# Line 203-207
# データ削除
from sqlalchemy import delete as sql_delete
await db_session.execute(sql_delete(Staff).where(Staff.is_test_data == True))  # ← 先に削除すると offices.created_by が参照エラー
await db_session.execute(sql_delete(Office).where(Office.is_test_data == True))
await db_session.commit()
```

**修正案**:
```python
# データ削除（外部キー制約を考慮した順序）
from sqlalchemy import delete as sql_delete
from app.models import OfficeStaff
await db_session.execute(sql_delete(OfficeStaff).where(OfficeStaff.is_test_data == True))
await db_session.execute(sql_delete(Office).where(Office.is_test_data == True))
await db_session.execute(sql_delete(Staff).where(Staff.is_test_data == True))
await db_session.commit()
```

**ステータス**: ⏸️ **修正中断（ユーザーブロック）**

---

## ⏳ 未着手タスク

### 3. `test_withdrawal_service.py` エラー調査

**失敗テスト**:
- `TestOfficeWithdrawalBillingCancellation::test_office_withdrawal_cancels_billing_without_subscription`

**推定原因**:
- 事務所退会時の課金キャンセル処理に問題がある可能性
- Billing レコードの状態遷移やStripe ID のnull化処理のエラー

**次のステップ**:
1. テストの詳細エラーメッセージを確認
2. `withdrawal_service.py` の `approve_withdrawal()` 実装を確認
3. Billing キャンセル処理のロジックを検証

---

### 4. `test_bulk_factories.py` エラー調査

**失敗テスト**:
- `test_bulk_create_performance_100_offices`

**推定原因**:
- パフォーマンステストのタイムアウト（目標: 5分以内）
- データ生成速度が遅い可能性
- DB接続エラーやトランザクション処理の問題

**次のステップ**:
1. 実際の処理時間を測定
2. bulk_create_offices/staffs/welfare_recipients のパフォーマンスを確認
3. バッチサイズやcommit頻度の調整

---

### 5. `test_deadline_notification_performance.py` エラー調査

**失敗テスト（ERROR）**:
- `test_deadline_notification_performance_500_offices`
- `test_query_efficiency_no_n_plus_1`
- `test_memory_efficiency_chunk_processing`
- `test_parallel_processing_speedup`

**推定原因**:
- テストデータ生成フィクスチャ（`performance_test_data_large`）の失敗
- 500事業所 × 10スタッフ × 10利用者 = 55,000レコード生成でエラー
- メモリ不足、DB接続タイムアウト、外部キー制約エラーの可能性

**失敗テスト（FAILED）**:
- `test_error_resilience`
- `test_performance_test_data_generation_speed`

**推定原因**:
- dry_runモードでのメール送信カウントロジック
- 不正なメールアドレスのハンドリング

**次のステップ**:
1. フィクスチャのエラーログを確認
2. テストデータ生成を段階的に実行してボトルネックを特定
3. バッチ処理のcommit/flush戦略を見直し

---

## 📊 進捗サマリー

| カテゴリ | 総数 | 完了 | 進行中 | 未着手 |
|---------|------|------|--------|--------|
| 本番環境 | 1 | 1 | 0 | 0 |
| ローカル環境 | 11 | 1 | 3 | 7 |
| **合計** | **12** | **2** | **3** | **7** |

**完了率**: 16.7% (2/12)

---

## 🎯 次のアクション

### 優先度1: snapshot_manager修正の完了
- [ ] `test_snapshot_manager.py:205-206` の削除順序修正を適用
- [ ] テスト実行して外部キー制約エラーが解消されたか確認

### 優先度2: 詳細エラーログの収集
- [ ] Docker環境でローカルテストを実行
- [ ] 各テストの詳細なスタックトレースとエラーメッセージを取得
- [ ] エラーの根本原因を特定

### 優先度3: 段階的な修正
1. `test_snapshot_manager.py` 修正完了 → テスト実行
2. `test_withdrawal_service.py` エラー調査 → 修正 → テスト実行
3. `test_bulk_factories.py` エラー調査 → 修正 → テスト実行
4. `test_deadline_notification_performance.py` エラー調査 → 修正 → テスト実行

---

## 📝 メモ

### 外部キー制約の原則
- **参照する側（child）を先に削除**
- **参照される側（parent）を後に削除**
- `offices.created_by → staffs.id` の場合:
  - Office（child）を先に削除
  - Staff（parent）を後に削除

### テスト環境の制約
- Docker環境が動いていない状態では実際のテスト実行ができない
- エラーログの詳細が不明なため、推測ベースでの修正となる
- 修正後の検証が必要

---

**最終更新**: 2026-02-12 (作業中断時点)
**次回タスク**: snapshot_manager修正の完了とテスト実行
