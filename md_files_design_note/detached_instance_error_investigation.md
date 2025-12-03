# DetachedInstanceError調査レポート

## 調査日時
2025-11-28

## エラー概要

### 対象エラー
```
sqlalchemy.orm.exc.DetachedInstanceError: Instance <Staff at 0xffff8dbdc7d0> is not bound to a Session; attribute refresh operation cannot proceed
```

**発生件数**: 5件
**影響範囲**: `tests/api/v1/test_role_change_requests.py` (#28-32)

---

## 調査結果

### 1. 根本原因

**DetachedInstanceError自体は現在発生していない**

エラーログ分析の結果、これらのテストは実際には以下のエラーで失敗しています：

```
sqlalchemy.exc.ProgrammingError: (psycopg.errors.UndefinedTable) relation "role_change_requests" does not exist
```

**理由**:
- withdrawal.mdのPhase 5.2で、`role_change_requests`テーブルを`approval_requests`に統合する計画
- `approval_requests`テーブルは作成済み
- 旧テーブル`role_change_requests`は削除済み
- テストが新しい統合テーブルに対応していない

したがって、DetachedInstanceErrorに到達する前に、テーブル不存在エラーで失敗しています。

---

### 2. セッション管理問題の分析

#### ✅ withdrawal_requests.py - 修正済み

**問題箇所**: `create_withdrawal_request` エンドポイント（Line 142）

```python
# ❌ 修正前
await db.commit()
loaded_request = await crud_approval_request.get_by_id_with_relations(db, approval_req.id)
```

**修正内容**:
```python
# ✅ 修正後
request_id = approval_req.id  # commitの前にIDをキャッシュ
await db.commit()
loaded_request = await crud_approval_request.get_by_id_with_relations(db, request_id)
```

**対応日**: 2025-11-28
**ステータス**: ✅ 完了

---

#### ✅ role_change_requests.py - 問題なし

**確認結果**:
`create_role_change_request`エンドポイント（Line 66-67）は既に適切に実装されています：

```python
# ✅ 適切な実装
await db.commit()
await db.refresh(request)  # refreshでリレーションシップも再ロード
return request
```

**ステータス**: ✅ 問題なし

---

### 3. 統合テーブル移行の未完了問題

#### ❌ employee_action_service.py - 修正必要

**問題箇所**: Line 164, 178, 197, 227, 240

```python
# ❌ 旧モデルを参照
) -> EmployeeActionRequest:  # Line 164

request = await crud_employee_action_request.get(db, id=request_id)  # Line 178

approved_request = await crud_employee_action_request.approve(...)  # Line 197, 227

select(EmployeeActionRequest)  # Line 240
```

**修正が必要**:
```python
# ✅ 修正後
) -> ApprovalRequest:

request = await approval_request.get(db, id=request_id)

approved_request = await approval_request.approve(...)

select(ApprovalRequest)
```

**インポート修正**:
```python
# ❌ 削除
from app.models.employee_action_request import EmployeeActionRequest
from app.crud.crud_employee_action_request import crud_employee_action_request

# ✅ 既に存在（確認）
from app.models.approval_request import ApprovalRequest
from app.crud.crud_approval_request import approval_request
```

---

### 4. ResourceClosedError問題

**影響範囲**: `tests/api/v1/test_withdrawal_requests.py` (#49-65)

**エラーメッセージ**:
```
sqlalchemy.exc.ResourceClosedError: This Connection is closed
```

**原因**: `employee_action_service.py`のインポートエラー

```
NameError: name 'EmployeeActionRequest' is not defined
```

このエラーにより、テストの初期化時にモジュールのインポートに失敗し、データベース接続が閉じられています。

**修正により解決予定**: `employee_action_service.py`の統合テーブル移行を完了することで解決

---

## 修正優先度

| 優先度 | 項目 | 件数 | ステータス |
|--------|------|------|-----------|
| **完了** | withdrawal_requests.py (MissingGreenlet対策) | 1件 | ✅ 修正済み |
| **完了** | role_change_requests.py | 0件 | ✅ 問題なし |
| **高** | employee_action_service.py (統合テーブル移行) | 多数 | ❌ 修正必要 |
| **高** | role_change_service.py (統合テーブル移行) | 多数 | ❌ 未確認 |
| **中** | テストファイル (統合テーブル対応) | 112件 | ❌ 未対応 |

---

## 次のアクション

### 1. ✅ 完了: withdrawal_requests.py修正

commitの前にIDをキャッシュする修正を実施済み。

---

### 2. ❌ 必須: employee_action_service.py修正

**修正内容**:
1. `EmployeeActionRequest` → `ApprovalRequest`
2. `crud_employee_action_request` → `approval_request`
3. ヘルパー関数の更新（`_get_resource_type`, `_get_action_type`など）

**ファイル**: `k_back/app/services/employee_action_service.py`

**影響範囲**:
- Line 164: 返り値の型
- Line 178: CRUDメソッド呼び出し
- Line 197, 227: 承認メソッド呼び出し
- Line 240: SQLAlchemy select文
- その他多数の箇所

---

### 3. ❌ 必須: role_change_service.py修正

**確認が必要**:
- `RoleChangeRequest` → `ApprovalRequest`
- `crud_role_change_request` → `approval_request`

**ファイル**: `k_back/app/services/role_change_service.py`

---

### 4. ❌ テストファイルの更新（統合テーブル対応）

**対象**:
- `tests/api/v1/test_employee_action_requests.py`
- `tests/api/v1/test_role_change_requests.py`
- `tests/crud/test_crud_employee_action_request.py`
- `tests/crud/test_crud_role_change_request.py`
- その他多数

**修正内容**:
- 旧モデル（`EmployeeActionRequest`, `RoleChangeRequest`）から`ApprovalRequest`への移行
- 旧CRUD（`crud_employee_action_request`, `crud_role_change_request`）から`approval_request`への移行

---

## セッション管理のベストプラクティス（再確認）

### ✅ DO（推奨）

```python
# 1. commitの前にIDをキャッシュ
obj_id = db_obj.id
await db.commit()
loaded_obj = await crud.get_by_id(db, obj_id)

# 2. commitの後にrefresh
await db.commit()
await db.refresh(db_obj)

# 3. リレーションシップを明示的にロード
query = select(Model).options(
    selectinload(Model.relation)
)
```

### ❌ DON'T（避ける）

```python
# commitの後にデタッチされたオブジェクトの属性にアクセス
await db.commit()
obj.relation.name  # ← DetachedInstanceError / MissingGreenlet
```

---

## まとめ

### DetachedInstanceError問題

- **直接的な原因**: セッション管理の問題ではない
- **根本原因**: 統合テーブルへの移行が未完了
- **現状**: テーブル不存在エラーで失敗、DetachedInstanceErrorには到達していない

### セッション管理の修正状況

| エンドポイント | ステータス | 備考 |
|---------------|-----------|------|
| `withdrawal_requests.py` | ✅ 修正済み | IDキャッシュ実装 |
| `role_change_requests.py` | ✅ 問題なし | refresh使用 |
| `employee_action_service.py` | ❌ 修正必要 | 統合テーブル移行が必要 |
| `role_change_service.py` | ❌ 未確認 | 統合テーブル移行が必要 |

### 推奨される次のステップ

1. **即時対応**: `employee_action_service.py`の統合テーブル移行
2. **即時対応**: `role_change_service.py`の統合テーブル移行
3. **中期対応**: テストファイルの統合テーブル対応（112件）
4. **長期対応**: マイグレーションスクリプトの整備

---

**関連ドキュメント**:
- `md_files_design_note/withdrawal_api_review.md` - セッション管理のベストプラクティス
- `md_files_design_note/task/1_withdrawal/withdrawal.md` - 統合テーブル移行計画
- `md_files_design_note/2Rerror.md` - エラーログ詳細
