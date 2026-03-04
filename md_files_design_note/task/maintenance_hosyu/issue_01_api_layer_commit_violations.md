# Issue #01: API層のcommit違反修正

**優先度**: 🔴 **Critical（最高）**
**カテゴリ**: アーキテクチャ違反 / データ整合性
**作成日**: 2026-02-18
**ステータス**: 未着手

---

## 問題の概要

API層で `await db.commit()` および `await db.flush()` が使用されており、4層アーキテクチャの原則に違反している。

### 検出された違反件数

**20件以上の違反** が検出されました。

```bash
$ grep -rn "await db.commit()\|await db.flush()" k_back/app/api/v1/endpoints/

app/api/v1/endpoints/admin_inquiries.py:187:    await db.commit()
app/api/v1/endpoints/admin_inquiries.py:254:    await db.commit()
app/api/v1/endpoints/admin_inquiries.py:321:    await db.commit()
app/api/v1/endpoints/terms.py:80:              await db.commit()
app/api/v1/endpoints/mfa.py:59:                await db.commit()
app/api/v1/endpoints/mfa.py:117:               await db.commit()
app/api/v1/endpoints/mfa.py:159:               await db.commit()
app/api/v1/endpoints/mfa.py:222:               await db.commit()
app/api/v1/endpoints/mfa.py:276:               await db.commit()
app/api/v1/endpoints/mfa.py:348:               await db.commit()
app/api/v1/endpoints/mfa.py:454:               await db.commit()
app/api/v1/endpoints/support_plan_statuses.py:130: await db.commit()
app/api/v1/endpoints/employee_action_requests.py:282: await db.commit()
app/api/v1/endpoints/auths.py:74:              await db.commit()
app/api/v1/endpoints/auths.py:117:             await db.commit()
app/api/v1/endpoints/auths.py:162:             await db.commit()
app/api/v1/endpoints/auths.py:538:             await db.commit()
app/api/v1/endpoints/auths.py:701:             await db.commit()
app/api/v1/endpoints/auths.py:843:             await db.commit()
app/api/v1/endpoints/auths.py:988:             await db.commit()
...（さらに多数）
```

---

## なぜこれが重大な問題なのか

### 1. アーキテクチャ原則の崩壊
- API層の責務: HTTP処理のみ
- ビジネスロジック/トランザクション管理はService層の責務
- **単一責任原則（SRP）違反**

### 2. データ整合性のリスク
- トランザクション境界が不明確
- 複数操作のアトミック性が保証されない
- エラー時のロールバックが困難

### 3. テストの困難さ
- 単体テストができない（DB操作と密結合）
- テスト時にDB汚染が発生
- モック化が不可能

### 4. 保守性・拡張性の低下
- ビジネスロジックが複数箇所に分散
- コード再利用ができない（バッチ処理等で呼べない）
- 修正時の影響範囲が不明確

---

## 影響範囲の分析

### 影響を受けるファイル（主要）

| ファイル | 違反箇所数 | 影響度 | 推定修正時間 |
|---------|----------|-------|------------|
| `auths.py` | 6箇所 | 🔴 High | 2時間 |
| `mfa.py` | 7箇所 | 🔴 High | 2.5時間 |
| `admin_inquiries.py` | 3箇所 | 🟠 Medium | 1時間 |
| `support_plan_statuses.py` | 1箇所 | 🟡 Low | 30分 |
| `employee_action_requests.py` | 1箇所 | 🟡 Low | 30分 |
| `terms.py` | 1箇所 | 🟡 Low | 30分 |

**合計推定工数**: 約7時間

---

## 修正方針

### Step 1: Service層の作成

各エンドポイントのビジネスロジックをService層に抽出

**修正前（API層）**:
```python
# app/api/v1/endpoints/users.py
@router.post("/users/")
async def create_user(user_in: UserCreate, db: AsyncSession = Depends(get_db)):
    # ❌ API層にビジネスロジック
    user = User(**user_in.dict())
    db.add(user)
    await db.flush()

    billing = Billing(user_id=user.id, plan="free")
    db.add(billing)

    await db.commit()  # ❌ API層でcommit
    await db.refresh(user)
    return user
```

**修正後（API層 + Service層）**:
```python
# app/services/user_service.py
async def create_user_with_billing(db: AsyncSession, user_in: UserCreate) -> User:
    """ユーザーとBillingを作成する"""
    try:
        user = await crud.user.create(db=db, obj_in=user_in)
        billing = await crud.billing.create_for_user(db=db, user_id=user.id)

        await db.commit()  # ✅ Service層でcommit
        await db.refresh(user)
        return user
    except Exception as e:
        await db.rollback()
        raise

# app/api/v1/endpoints/users.py
@router.post("/users/")
async def create_user(
    user_in: UserCreate,
    db: AsyncSession = Depends(get_db)
):
    # ✅ API層はService層を呼ぶだけ
    return await user_service.create_user_with_billing(db=db, user_in=user_in)
```

---

### Step 2: トランザクション境界の明確化

**原則**:
- 1つのビジネスロジック = 1つのトランザクション
- 外部API呼び出しはcommit前またはcommit後
- エラー時は必ずrollback

---

### Step 3: テストの追加

Service層のロジックに対して単体テストを追加

```python
# tests/services/test_user_service.py
async def test_create_user_with_billing(db_session):
    # Arrange
    user_in = UserCreate(email="test@example.com", ...)

    # Act
    user = await user_service.create_user_with_billing(db=db_session, user_in=user_in)

    # Assert
    assert user.id is not None
    assert user.email == "test@example.com"

    # Billingも作成されていることを確認
    billing = await crud.billing.get_by_user_id(db=db_session, user_id=user.id)
    assert billing is not None
    assert billing.plan == "free"
```

---

## 修正手順（ファイル別）

### 1. `auths.py` の修正

**対象エンドポイント**:
- `/login` (Line 74)
- `/verify-email` (Line 117)
- `/resend-verification-email` (Line 162)
- `/forgot-password` (Line 538)
- `/reset-password` (Line 701)
- `/verify-mfa` (Line 843, 988)

**修正方針**:
1. `app/services/auth_service.py` を作成
2. 各エンドポイントのロジックをServiceに移行
3. API層は認証チェック + Service呼び出しのみに

**推定工数**: 2時間

---

### 2. `mfa.py` の修正

**対象エンドポイント**:
- `/enroll` (Line 59)
- `/verify` (Line 117)
- `/disable` (Line 159)
- 他4箇所

**修正方針**:
1. `app/services/mfa_service.py` を作成（既にある場合は拡張）
2. MFA登録/検証/無効化ロジックをServiceに集約
3. トランザクション境界を明確化

**推定工数**: 2.5時間

---

### 3. `admin_inquiries.py` の修正

**対象エンドポイント**:
- `/inquiries/{id}/status` (Line 187, 254, 321)

**修正方針**:
1. `app/services/inquiry_service.py` を作成
2. ステータス更新ロジックをServiceに移行

**推定工数**: 1時間

---

### 4. その他ファイルの修正

- `support_plan_statuses.py`: 30分
- `employee_action_requests.py`: 30分
- `terms.py`: 30分

---

## チェックリスト

### 修正前チェック
- [ ] 対象ファイルのバックアップ作成
- [ ] 既存テストが全てPASSすることを確認
- [ ] ブランチ作成: `refactor/api-layer-commit-violations`

### 修正中チェック（各ファイル）
- [ ] Service層の作成
- [ ] ビジネスロジックの移行
- [ ] API層の簡素化
- [ ] トランザクション境界の明確化（try-except-rollback）
- [ ] 単体テストの追加
- [ ] 既存テストのPASS確認

### 修正後チェック
- [ ] 全テストがPASSすることを確認
- [ ] API層に `await db.commit()` が0件になることを確認
  ```bash
  grep -rn "await db.commit()" k_back/app/api/v1/endpoints/
  ```
- [ ] コードレビュー依頼
- [ ] PR作成

---

## 期待される効果

### 定量的効果
- ✅ アーキテクチャ違反: 20件 → 0件
- ✅ テストカバレッジ: +15%（Service層の単体テスト追加）
- ✅ コード行数: -10%（重複ロジックの削減）

### 定性的効果
- ✅ データ整合性の向上（トランザクション境界が明確）
- ✅ テスト容易性の向上（ビジネスロジックの単体テスト可能）
- ✅ 保守性の向上（ロジックの一元化）
- ✅ 拡張性の向上（Service層の再利用）

---

## リスク分析

| リスク | 影響度 | 発生確率 | 対策 |
|-------|-------|---------|-----|
| 既存機能の破壊 | 🔴 High | 🟡 Medium | テストの充実、段階的リリース |
| トランザクション境界の誤設定 | 🔴 High | 🟢 Low | レビュー強化、テストでの検証 |
| 修正漏れ | 🟠 Medium | 🟡 Medium | grepでの全数チェック |
| パフォーマンス劣化 | 🟡 Low | 🟢 Low | パフォーマンステスト実施 |

---

## 関連Issue

- Issue #02: トランザクション境界の整備
- Issue #03: 保守性改善（DRY違反・マジックナンバー）

---

## 参考資料

- `.claude/skills/SKILLS.md` - commit-flush-check スキル
- `.claude/CLAUDE.md` - 4層アーキテクチャガイドライン
- `.claude/rules/architecture.md` - アーキテクチャルール

---

**作成日**: 2026-02-18
**担当者**: 未割当
**レビュアー**: 未割当
**期限**: 未設定
