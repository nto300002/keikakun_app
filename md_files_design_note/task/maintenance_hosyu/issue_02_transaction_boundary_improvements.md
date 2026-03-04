# Issue #02: トランザクション境界の整備

**優先度**: 🟠 **High（高）**
**カテゴリ**: データ整合性 / トランザクション管理
**作成日**: 2026-02-18
**ステータス**: 未着手

---

## 問題の概要

Service層でのトランザクション境界が不明確で、以下の問題がある:
1. commit漏れ（トランザクションが完了しない）
2. rollback処理の欠如（エラー時にデータ不整合）
3. 複数commitによるトランザクション分断
4. 外部API呼び出しとトランザクション境界の不適切な関係

---

## 検出された問題

### 1. commit漏れの検出

```bash
# Service層でcrud呼び出しがあるがcommitがないファイルを検出
$ for file in k_back/app/services/*.py; do
  if grep -q "await crud\." "$file" && ! grep -q "await db.commit()" "$file"; then
    echo "⚠️  Commit missing: $file"
  fi
done
```

**結果**: 要確認（実行後に記載）

---

### 2. rollback処理の欠如検出

```bash
# commitがあるがrollbackがないファイルを検出
$ for file in k_back/app/services/*.py; do
  if grep -q "await db.commit()" "$file" && ! grep -q "await db.rollback()" "$file"; then
    echo "⚠️  Missing rollback in $file"
  fi
done
```

**結果**: 要確認（実行後に記載）

---

### 3. 複数commit検出

```bash
# 1つの関数内に複数のcommitがある箇所を検出
$ for file in k_back/app/services/*.py; do
  count=$(grep -c "await db.commit()" "$file" 2>/dev/null || echo 0)
  if [ "$count" -gt 1 ]; then
    echo "⚠️  Multiple commits in $file: $count commits"
  fi
done
```

**結果**: 要確認（実行後に記載）

---

## なぜこれが問題なのか

### 1. commit漏れの問題

**❌ 悪い例**:
```python
async def create_user_with_profile(db: AsyncSession, user_in: UserCreate, profile_in: ProfileCreate):
    user = await crud.user.create(db=db, obj_in=user_in)
    profile = await crud.profile.create(db=db, user_id=user.id, obj_in=profile_in)
    # ❌ commitがない → トランザクションが完了しない
    return user
```

**問題点**:
- データがDBに保存されない
- トランザクションが開きっぱなし（リソースリーク）
- 次のリクエストで不整合が発生

---

### 2. rollback処理欠如の問題

**❌ 悪い例**:
```python
async def create_order_with_payment(db: AsyncSession, order_in: OrderCreate):
    order = await crud.order.create(db=db, obj_in=order_in)
    await crud.stock.decrease(db=db, product_id=order.product_id, quantity=order.quantity)

    # 外部API呼び出し（失敗する可能性）
    payment = await stripe.charge(amount=order.total)

    await db.commit()  # ❌ 外部API失敗時のrollbackがない
```

**問題点**:
- Stripe決済が失敗 → 注文と在庫減少はDBに残る（データ不整合）
- 手動でロールバックが必要（複雑・エラーが起きやすい）

**✅ 正しい実装**:
```python
async def create_order_with_payment(db: AsyncSession, order_in: OrderCreate):
    try:
        order = await crud.order.create(db=db, obj_in=order_in)
        await crud.stock.decrease(db=db, product_id=order.product_id, quantity=order.quantity)

        # 外部API呼び出し（commit前）
        payment = await stripe.charge(amount=order.total)

        await db.commit()  # ✅ 全て成功したらcommit
        return order

    except Exception as e:
        await db.rollback()  # ✅ エラー時は自動ロールバック
        logger.error(f"Order creation failed: {e}")
        raise
```

---

### 3. 複数commitの問題

**❌ 悪い例**:
```python
async def complex_operation(db: AsyncSession):
    # トランザクション1
    user = User(...)
    db.add(user)
    await db.commit()  # ❌ Commit 1

    # トランザクション2
    billing = Billing(user_id=user.id)
    db.add(billing)
    await db.commit()  # ❌ Commit 2

    # 外部API呼び出し
    await send_welcome_email(user.email)  # これが失敗したら？

    # トランザクション3
    audit_log = AuditLog(user_id=user.id)
    db.add(audit_log)
    await db.commit()  # ❌ Commit 3
```

**問題点**:
- メール送信が失敗 → UserとBillingは既に作成済み（ロールバック不可）
- 監査ログのcommitが失敗 → ログが残らない
- **アトミック性が失われる**

**✅ 正しい実装**:
```python
async def complex_operation(db: AsyncSession):
    try:
        # 全ての操作を1つのトランザクションで
        user = User(...)
        db.add(user)

        billing = Billing(user_id=user.id)
        db.add(billing)

        audit_log = AuditLog(user_id=user.id)
        db.add(audit_log)

        # 全て成功したら1回だけcommit
        await db.commit()

        # commit後に外部API呼び出し
        await send_welcome_email(user.email)

    except Exception as e:
        await db.rollback()
        raise
```

---

## 修正方針

### 原則1: 1つのビジネスロジック = 1つのトランザクション

**ルール**:
- 関連する複数の操作は1つのトランザクション内で実行
- commitは最後に1回だけ
- エラー時は全てrollback

---

### 原則2: 外部API呼び出しのタイミング

**パターンA: commit前に外部API呼び出し（推奨）**

```python
async def process_with_external_api(db: AsyncSession, data_in: DataCreate):
    try:
        # 1. DB操作
        record = await crud.model.create(db=db, obj_in=data_in)

        # 2. 外部API呼び出し（commit前）
        result = await external_api.call(record.id)

        # 3. 外部APIが成功したらcommit
        await db.commit()

    except ExternalAPIError as e:
        # 外部API失敗 → DB操作も自動ロールバック
        await db.rollback()
        raise
```

**使用ケース**: 決済処理、在庫確保など、**失敗したらDB操作も取り消したい**場合

---

**パターンB: commit後に外部API呼び出し**

```python
async def process_with_notification(db: AsyncSession, data_in: DataCreate):
    # 1. DB操作をcommit
    record = await crud.model.create(db=db, obj_in=data_in)
    await db.commit()

    # 2. commit後に外部API呼び出し
    try:
        await send_notification(record.email)
    except NotificationError as e:
        # ⚠️ 既にcommit済みなので、ロールバック不可
        # 代替手段: エラーログ、リトライキュー
        logger.error(f"Notification failed: {e}")
        await retry_queue.add(task="send_notification", record_id=record.id)
```

**使用ケース**: メール送信、通知など、**失敗してもDB操作は残したい**場合

---

### 原則3: try-except-rollbackパターン必須

**テンプレート**:
```python
async def service_method(db: AsyncSession, data_in: DataCreate):
    try:
        # ビジネスロジック
        result = await crud.model.create(db=db, obj_in=data_in)

        # 全て成功したらcommit
        await db.commit()
        return result

    except Exception as e:
        # エラー時は必ずrollback
        await db.rollback()
        logger.error(f"Transaction failed: {e}")
        raise
```

---

## 修正手順

### Step 1: 現状調査

```bash
# 1. commit漏れを検出
for file in k_back/app/services/*.py; do
  if grep -q "await crud\." "$file" && ! grep -q "await db.commit()" "$file"; then
    echo "⚠️  Commit missing: $file"
  fi
done

# 2. rollback欠如を検出
for file in k_back/app/services/*.py; do
  if grep -q "await db.commit()" "$file" && ! grep -q "await db.rollback()" "$file"; then
    echo "⚠️  Missing rollback: $file"
  fi
done

# 3. 複数commitを検出
for file in k_back/app/services/*.py; do
  count=$(grep -c "await db.commit()" "$file" 2>/dev/null || echo 0)
  if [ "$count" -gt 1 ]; then
    echo "⚠️  Multiple commits in $file: $count"
  fi
done
```

**結果を記録**: `検出結果.md` に記載

---

### Step 2: 優先度付け

| 問題タイプ | 影響度 | 優先度 |
|----------|-------|--------|
| commit漏れ | 🔴 Critical | 1 |
| rollback欠如 | 🔴 Critical | 1 |
| 複数commit | 🟠 High | 2 |
| 外部API前後のcommit | 🟡 Medium | 3 |

---

### Step 3: 修正実施

**修正テンプレート**:

```python
# Before: commit漏れ
async def create_something(db: AsyncSession, data_in: DataCreate):
    result = await crud.model.create(db=db, obj_in=data_in)
    # ❌ commitがない
    return result

# After: try-except-rollbackパターン
async def create_something(db: AsyncSession, data_in: DataCreate):
    try:
        result = await crud.model.create(db=db, obj_in=data_in)
        await db.commit()  # ✅ commitを追加
        await db.refresh(result)
        return result
    except Exception as e:
        await db.rollback()  # ✅ rollbackを追加
        logger.error(f"Failed to create: {e}")
        raise
```

---

### Step 4: テストの追加

**トランザクション境界のテスト**:

```python
# tests/services/test_transaction_boundaries.py

async def test_commit_on_success(db_session):
    """成功時にcommitされることを確認"""
    data_in = DataCreate(...)
    result = await service.create_something(db=db_session, data_in=data_in)

    # DBにデータが保存されていることを確認
    saved = await crud.model.get(db=db_session, id=result.id)
    assert saved is not None

async def test_rollback_on_error(db_session):
    """エラー時にrollbackされることを確認"""
    data_in = DataCreate(...)

    with pytest.raises(SomeError):
        await service.create_something(db=db_session, data_in=data_in)

    # DBにデータが保存されていないことを確認
    all_records = await crud.model.get_all(db=db_session)
    assert len(all_records) == 0
```

---

## チェックリスト

### 修正前チェック
- [ ] 現状調査スクリプト実行
- [ ] 検出結果をドキュメント化
- [ ] 優先度付け
- [ ] ブランチ作成: `refactor/transaction-boundaries`

### 修正中チェック
- [ ] commit漏れの修正
- [ ] rollback処理の追加
- [ ] 複数commitの統合
- [ ] 外部API呼び出しタイミングの見直し
- [ ] try-except-rollbackパターンの適用
- [ ] トランザクション境界テストの追加

### 修正後チェック
- [ ] 全テストがPASSすることを確認
- [ ] commit漏れが0件になることを確認
- [ ] rollback欠如が0件になることを確認
- [ ] コードレビュー依頼
- [ ] PR作成

---

## 期待される効果

### 定量的効果
- ✅ commit漏れ: 検出数 → 0件
- ✅ rollback欠如: 検出数 → 0件
- ✅ 複数commit: 検出数 → 0件
- ✅ テストカバレッジ: +10%

### 定性的効果
- ✅ データ整合性の保証
- ✅ エラー発生時の確実なロールバック
- ✅ トランザクション境界の明確化
- ✅ デバッグ容易性の向上

---

## リスク分析

| リスク | 影響度 | 発生確率 | 対策 |
|-------|-------|---------|-----|
| 既存機能の破壊 | 🔴 High | 🟡 Medium | テストの充実 |
| トランザクション分断 | 🔴 High | 🟢 Low | レビュー強化 |
| パフォーマンス劣化 | 🟡 Low | 🟢 Low | パフォーマンステスト |

---

## 関連Issue

- Issue #01: API層のcommit違反修正
- Issue #03: 保守性改善（DRY違反・マジックナンバー）

---

## 参考資料

- `.claude/skills/SKILLS.md` - transaction-boundary スキル
- `.claude/CLAUDE.md` - 4層アーキテクチャガイドライン

---

**作成日**: 2026-02-18
**担当者**: 未割当
**レビュアー**: 未割当
**期限**: 未設定
