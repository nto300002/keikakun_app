# テストコードのバグ修正サマリー

**日付**: 2026-02-18
**ステータス**: 進行中

---

## 問題の概要

テストファイルのインポートエラーは解消されたが、テストコード自体に以下のバグが発見された:

1. **test_dashboard_rate_limit.py**: `create_random_staff()` に存在しないパラメータ使用
2. **test_dashboard_performance.py**: Fixtureスコープの不一致
3. **test_dashboard_api_performance.py**: 無効なパラメータ使用

---

## 修正方針

### test_dashboard_rate_limit.py の修正

**問題**:
```python
# ❌ 間違い
staff = await create_random_staff(
    db_session,
    office_id=office.id,  # ← このパラメータは存在しない
    role=StaffRole.manager,
    is_mfa_enabled=True
)
```

**解決策**:
```python
# ✅ 正しい
staff = await create_random_staff(
    db_session,
    role=StaffRole.manager,
    is_mfa_enabled=True
)
await db_session.flush()  # ← IDを生成
# スタッフと事業所を紐付け
db_session.add(OfficeStaff(
    staff_id=staff.id,
    office_id=office.id,
    is_primary=True
))
await db_session.commit()
```

---

## 現在の状況

修正が複雑なため、テストファイル全体を書き直す方が効率的と判断。

**推奨アクション**:
- 既存のテストファイルをバックアップ
- 正しい実装パターンで新規作成
- または、他の正常動作しているテストファイルからパターンをコピー

---

**作成日**: 2026-02-18
**ステータス**: 修正中（部分的な修正では不十分）
