# Stripe Subscription ID 重複エラーの原因分析

## エラー概要

```
IntegrityError: (psycopg.errors.UniqueViolation) duplicate key value violates unique constraint "uq_billings_stripe_subscription_id"
DETAIL: Key (stripe_subscription_id)=(sub_test_active) already exists.
```

**発生環境**: GitHub Actions CI/CD（本番環境テスト）のみ
**発生テスト**: `tests/tasks/test_billing_check.py::test_early_payment_during_trial_not_updated`
**発生日時**: 2026-01-05

---

## 根本原因

### 1. 複数テストで同じハードコードされたSubscription IDを使用

**問題のコード箇所**:

#### テスト1: `tests/tasks/test_billing_check.py:362`
```python
async def test_early_payment_during_trial_not_updated(
    self, db_session, office_factory
):
    # ...
    billing.stripe_subscription_id = "sub_test_active"  # ← 問題
    await db_session.commit()
```

#### テスト2: `tests/services/test_billing_service.py`
```python
async def test_webhook_subscription_deleted_cancels_subscription(
    self, db, setup_office_with_billing, ...
):
    await crud.billing.update(
        db=db,
        db_obj=await crud.billing.get(db=db, id=billing_id),
        obj_in={
            "billing_status": BillingStatus.active,
            "stripe_customer_id": "cus_test_active",
            "stripe_subscription_id": "sub_test_active"  # ← 同じID
        }
    )
    await db.commit()
```

### 2. データベーススキーマの制約

**`app/models/billing.py:31`**:
```python
stripe_subscription_id: Mapped[Optional[str]] = mapped_column(
    String(255),
    unique=True  # ← UNIQUE制約あり
)
```

この制約により、複数の`billing`レコードが同じ`stripe_subscription_id`を持つことは**許可されない**。

---

## なぜCI/CD環境でのみ発生するのか

### 仮説1: テスト並列実行（最も可能性が高い）

**CI/CD環境の特徴**:
- GitHub Actionsでは複数のテストが並列実行される可能性がある
- pytest-xdistなどのプラグインが有効になっている場合

**発生メカニズム**:
```
時刻 | テスト1 (test_billing_check.py)    | テスト2 (test_billing_service.py)
-----|-----------------------------------|----------------------------------
T1   | billing1作成                      |
T2   | billing1.subscription_id =        |
     | "sub_test_active"                 |
T3   | COMMIT                            |
T4   |                                   | billing2作成
T5   |                                   | billing2.subscription_id =
     |                                   | "sub_test_active"
T6   |                                   | UPDATE実行 → ❌ IntegrityError!
```

### 仮説2: データベース状態の永続化

**CI/CD環境の特徴**:
- テスト実行前のデータベースクリーンアップが不完全
- 前回のテスト実行で残されたデータが存在

**発生メカニズム**:
```
前回のテスト実行:
  billing(id=UUID1, stripe_subscription_id="sub_test_active") ← 残存

今回のテスト実行:
  billing(id=UUID2, stripe_subscription_id="sub_test_active") ← ❌ 重複
```

### 仮説3: トランザクション分離の問題

**ネストされたトランザクションパターンの限界**:

`tests/conftest.py:202-247`では以下のパターンを使用:
```python
async with engine.connect() as connection:
    await connection.begin()          # 外側のトランザクション
    await connection.begin_nested()   # 内側のトランザクション（SAVEPOINT）

    # テスト実行
    yield session

    # 最後にロールバック
    await connection.rollback()  # 全ての変更を破棄
```

**問題点**:
- 並列実行時、異なるテストが異なる`connection`を使用
- 各connectionは独立したトランザクションを持つ
- ロールバックは各connection内でのみ有効
- **データベースレベルでの競合は検出される**

---

## 証拠

### 1. エラーログからの証拠

```python
[SQL: UPDATE billings SET stripe_subscription_id=%(stripe_subscription_id)s::VARCHAR, ...
WHERE billings.id = %(billings_id)s::UUID]
[parameters: ***'stripe_subscription_id': 'sub_test_active',
'billings_id': UUID('3323e751-3b5b-433c-8199-66ec817c55ca')***]
```

**重要な観察**:
- UPDATEしようとしているbilling_id: `3323e751-3b5b-433c-8199-66ec817c55ca`
- このUUIDは`test_early_payment_during_trial_not_updated`で生成されるもの
- しかし、**別のbillingレコード**が既に`sub_test_active`を保持している

### 2. コードからの証拠

**ハードコードされたSubscription IDの一覧**:

| ファイル | 行番号 | Subscription ID | 使用回数 |
|---------|-------|----------------|---------|
| `test_billing_check.py` | 119, 156 | `sub_test_xxxxx` | 2回 |
| `test_billing_check.py` | 321 | `sub_test_batch` | 1回 |
| `test_billing_check.py` | **362** | **`sub_test_active`** | **1回** |
| `test_billing_service.py` | 不明 | **`sub_test_active`** | **1回** |

→ **`sub_test_active`が2つのテストファイルで使用されている**

### 3. ローカル環境で再現しない理由

**ローカルでの実行特性**:
- テストは順次実行される（並列実行なし）
- 各テスト終了時にトランザクションが確実にロールバック
- データベース状態がクリーン

**CI/CDでの実行特性**:
- テストが並列実行される可能性
- 複数のワーカープロセスが同じデータベースを共有
- トランザクション分離レベルが異なる可能性

---

## 解決策

### 推奨解決策1: UUIDを使用した一意なSubscription ID（推奨）

**修正前**:
```python
billing.stripe_subscription_id = "sub_test_active"
```

**修正後**:
```python
from uuid import uuid4

billing.stripe_subscription_id = f"sub_test_{uuid4().hex[:12]}"
# 例: "sub_test_a1b2c3d4e5f6"
```

**メリット**:
- ✅ 確実に一意なIDを生成
- ✅ 並列実行に完全対応
- ✅ データベース永続化の影響を受けない

### 推奨解決策2: テスト名を含むプレフィックス

**修正後**:
```python
# test_early_payment_during_trial_not_updated内
billing.stripe_subscription_id = "sub_test_early_payment_trial"

# test_webhook_subscription_deleted内
billing.stripe_subscription_id = "sub_test_webhook_deleted"
```

**メリット**:
- ✅ デバッグが容易（テスト名から追跡可能）
- ✅ 可読性が高い

**デメリット**:
- ⚠️ 並列実行で同じテストが複数回実行される場合は不十分

### 推奨解決策3: Fixtureでの一意ID生成

**conftest.pyに追加**:
```python
@pytest.fixture
def unique_subscription_id():
    """一意なStripe Subscription IDを生成"""
    return f"sub_test_{uuid4().hex[:12]}"
```

**テストでの使用**:
```python
async def test_early_payment_during_trial_not_updated(
    self, db_session, office_factory, unique_subscription_id
):
    # ...
    billing.stripe_subscription_id = unique_subscription_id
```

**メリット**:
- ✅ 全テストで統一されたパターン
- ✅ メンテナンス性が高い

---

## 実装計画

### Phase 1: 緊急修正（即座に実施）

**対象**: `test_early_payment_during_trial_not_updated`のみ修正

```python
# tests/tasks/test_billing_check.py:362
- billing.stripe_subscription_id = "sub_test_active"
+ billing.stripe_subscription_id = f"sub_test_early_payment_{uuid4().hex[:8]}"
```

### Phase 2: 包括的修正（次回リリース）

**対象**: 全テストファイルのハードコードされたSubscription ID

1. `test_billing_check.py`の全ての`sub_test_*`をUUID化
2. `test_billing_service.py`の全ての`sub_test_*`をUUID化
3. Fixtureの導入を検討

### Phase 3: CI/CD環境の検証

- [ ] pytest-xdistの設定確認
- [ ] データベースクリーンアップの強化
- [ ] トランザクション分離レベルの確認

---

## 検証方法

### ローカルでの検証

```bash
# 並列実行をシミュレート
pytest tests/tasks/test_billing_check.py::test_early_payment_during_trial_not_updated \
      tests/services/test_billing_service.py::test_webhook_subscription_deleted_cancels_subscription \
      -v --tb=short -x
```

### CI/CDでの検証

GitHub Actionsで修正後のテストを実行し、IntegrityErrorが発生しないことを確認。

---

## まとめ

| 項目 | 内容 |
|-----|------|
| **根本原因** | 複数テストで同じハードコードされたSubscription ID使用 |
| **発生条件** | テスト並列実行 OR データベース状態の永続化 |
| **影響範囲** | CI/CD環境のみ（ローカルでは再現しない） |
| **優先度** | **高** - CI/CDのテストが失敗し続ける |
| **推奨解決策** | UUID化によるSubscription IDの一意性保証 |
| **実装工数** | 小（1-2時間） |

---

**作成日**: 2026-01-05
**作成者**: Claude Sonnet 4.5
**ステータス**: 分析完了、修正待ち
