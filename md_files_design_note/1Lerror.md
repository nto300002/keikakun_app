=========================== short test summary info ============================
FAILED tests/crud/test_crud_audit_log.py::TestAuditLogAdminImportantActions::test_get_admin_important_logs_pagination - AssertionError: assert False
 +  where False = <built-in method isdisjoint of set object at 0x7fbff92f82e0>(***UUID('1eda879b-94fd-4616-a6ac-fe24db8510a7'), UUID('26e1f589-ad90-419a-9d5b-6a51891573c0'), UUID('2989d7c8-b1c5-49c5-9046-a24d31526708'), UUID('3ba68915-0d03-43cd-9118-d5c1042c7763'), UUID('8426d971-ace8-49d1-859c-1b8ab61fd5bb')***)
 +    where <built-in method isdisjoint of set object at 0x7fbff92f82e0> = ***UUID('3ba68915-0d03-43cd-9118-d5c1042c7763'), UUID('53704ba1-366c-4623-b3a5-bf4bd49a264b'), UUID('b3c888fb-2a89-4d17-a801-1f6615a23e26'), UUID('c01dd977-f50f-4137-b6f8-541755b04205'), UUID('c1db63***-e7fb-4e23-aaef-4fe1ea0c00af')***.isdisjoint
===== 1 failed, 1572 passed, 71 skipped, 165 warnings in 594.79s (0:09:54) =====


=================================== FAILURES ===================================
__ TestAuditLogAdminImportantActions.test_get_admin_important_logs_pagination __
tests/crud/test_crud_audit_log.py:574: in test_get_admin_important_logs_pagination
    assert log_ids_page1.isdisjoint(log_ids_page2)
E   AssertionError: assert False
E    +  where False = <built-in method isdisjoint of set object at 0x7fbff92f82e0>(***UUID('1eda879b-94fd-4616-a6ac-fe24db8510a7'), UUID('26e1f589-ad90-419a-9d5b-6a51891573c0'), UUID('2989d7c8-b1c5-49c5-9046-a24d31526708'), UUID('3ba68915-0d03-43cd-9118-d5c1042c7763'), UUID('8426d971-ace8-49d1-859c-1b8ab61fd5bb')***)
E    +    where <built-in method isdisjoint of set object at 0x7fbff92f82e0> = ***UUID('3ba68915-0d03-43cd-9118-d5c1042c7763'), UUID('53704ba1-366c-4623-b3a5-bf4bd49a264b'), UUID('b3c888fb-2a89-4d17-a801-1f6615a23e26'), UUID('c01dd977-f50f-4137-b6f8-541755b04205'), UUID('c1db63***-e7fb-4e23-aaef-4fe1ea0c00af')***.isdisjoint

---

## 原因分析

### 問題: ページネーション時にレコードが重複

**エラー箇所**: `tests/crud/test_crud_audit_log.py:574`
- Page1とPage2で同じUUID (`3ba68915-0d03-43cd-9118-d5c1042c7763`) が含まれている
- `log_ids_page1.isdisjoint(log_ids_page2)` が `False` になり、テストが失敗

**根本原因**: `k_back/app/crud/crud_audit_log.py:371`
```python
.order_by(AuditLog.timestamp.desc())
```

**問題の詳細**:
- ソート条件が `timestamp` のみで、同じタイムスタンプのレコードが複数存在する場合、ソート順が**非決定的**になる
- PostgreSQLは同じタイムスタンプのレコードを任意の順序で返す可能性がある
- `skip=0, limit=5` と `skip=5, limit=5` で取得した結果に重複が発生

**発生条件**:
- 複数のテストが並列または連続実行され、同じミリ秒内に複数のAuditLogレコードが作成される
- 単独テスト実行では再現しないが、フルテストスイート実行時に発生（他のテストで作成されたログが影響）

**修正方法**:
```python
# 修正前（非決定的）
.order_by(AuditLog.timestamp.desc())

# 修正後（決定的）
.order_by(AuditLog.timestamp.desc(), AuditLog.id.desc())
```

**影響範囲**:
- `get_admin_important_logs` メソッド
- 本番環境でも同様の問題が発生する可能性あり（ページネーションで同じレコードが複数ページに表示される、またはレコードが抜ける）

**優先度**: 高（本番環境のデータ整合性に影響）