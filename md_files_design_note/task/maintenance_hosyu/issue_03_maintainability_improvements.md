# Issue #03: 保守性改善（DRY違反・マジックナンバー・ネーミング）

**優先度**: 🟡 **Medium（中）**
**カテゴリ**: コード品質 / 保守性
**作成日**: 2026-02-18
**ステータス**: 未着手

---

## 問題の概要

コードベース全体で保守性を低下させる以下の問題が散見される:
1. DRY違反（Don't Repeat Yourself）: 重複コード
2. マジックナンバー: ハードコードされた数値・文字列
3. 英語エラーメッセージ: ユーザー向けメッセージが日本語でない
4. 不明瞭な変数名・関数名
5. 過度に長い関数（Single Responsibility Principle違反）

---

## 検出方法

### 1. DRY違反の検出

**重複コード検出**:
```bash
# 類似度の高いコードブロックを検出（PMD CPDツール使用推奨）
# Pythonの場合、以下のような簡易検出も可能

# 同一パターンの繰り返しを検出
grep -rn "if billing.status ==" k_back/app/api/v1/endpoints/ | wc -l
grep -rn "raise HTTPException" k_back/app/api/v1/endpoints/ | wc -l
```

**重複したバリデーションロジック**:
```bash
# メール形式チェックが複数箇所に存在しないか
grep -rn "@.*\..*" k_back/app/ | grep "if.*@" | wc -l
```

---

### 2. マジックナンバーの検出

```bash
# ハードコードされた数値を検出（0, 1, -1以外）
grep -rn "[^0-9][2-9][0-9]*[^0-9]" k_back/app/services/*.py | grep -v "def\|class\|#"

# ステータス文字列のハードコード検出
grep -rn '"active"\|"inactive"\|"pending"\|"completed"' k_back/app/ | wc -l
```

**例**:
```python
# ❌ 悪い例
if user.age >= 18:  # 18は何を意味する？
    ...

if retry_count > 3:  # 3回の根拠は？
    ...

# ✅ 良い例
ADULT_AGE_THRESHOLD = 18
MAX_RETRY_COUNT = 3

if user.age >= ADULT_AGE_THRESHOLD:
    ...

if retry_count > MAX_RETRY_COUNT:
    ...
```

---

### 3. 英語エラーメッセージの検出

```bash
# ユーザー向けエラーメッセージが英語のまま
grep -rn "detail=\"" k_back/app/api/v1/endpoints/ | grep -v "日本語\|の\|を\|が\|は"

# 例: "User not found" など
grep -rn 'HTTPException.*detail.*"[A-Z]' k_back/app/api/v1/endpoints/
```

**検出結果**: 要確認（実行後に記載）

---

### 4. 不明瞭な変数名の検出

```bash
# 1文字変数名の検出（ループ変数i, j, k以外）
grep -rn " [a-z] =" k_back/app/services/*.py | grep -v "for\|lambda"

# 省略形の検出（推奨されない命名）
grep -rn "usr\|btn\|msg\|err\|tmp\|val" k_back/app/
```

---

### 5. 過度に長い関数の検出

```bash
# 関数の行数を計測（50行以上は要リファクタリング）
for file in k_back/app/services/*.py; do
  awk '/^async def |^def / {name=$0; start=NR} /^async def |^def |^class / && NR>start {if(NR-start>50) print FILENAME":"start":"name; start=NR; name=$0} END {if(NR-start>50) print FILENAME":"start":"name}' "$file"
done
```

---

## なぜこれが問題なのか

### 1. DRY違反の問題

**❌ 悪い例**:
```python
# app/api/v1/endpoints/users.py
@router.get("/users/{user_id}")
async def get_user(user_id: UUID, db: AsyncSession = Depends(get_db)):
    # Billing status check (重複コード)
    billing = await crud.billing.get_by_office_id(db=db, office_id=current_user.office_id)
    if billing.status == "past_due":
        raise HTTPException(status_code=402, detail="支払いが必要です")
    # ...

# app/api/v1/endpoints/plans.py
@router.post("/plans/")
async def create_plan(plan_in: PlanCreate, db: AsyncSession = Depends(get_db)):
    # Billing status check (重複コード)
    billing = await crud.billing.get_by_office_id(db=db, office_id=current_user.office_id)
    if billing.status == "past_due":
        raise HTTPException(status_code=402, detail="支払いが必要です")
    # ...
```

**問題点**:
- 同じロジックが複数箇所にコピペされている
- 修正時に全箇所を更新する必要がある（修正漏れのリスク）
- テストも重複する

**✅ 正しい実装**:
```python
# app/api/deps.py
async def verify_billing_status(
    db: AsyncSession = Depends(get_db),
    current_user: Staff = Depends(get_current_user)
):
    """課金ステータスを確認する依存関数"""
    billing = await crud.billing.get_by_office_id(db=db, office_id=current_user.office_id)
    if billing.status == "past_due":
        raise HTTPException(status_code=402, detail="支払いが必要です")
    return billing

# app/api/v1/endpoints/users.py
@router.get("/users/{user_id}")
async def get_user(
    user_id: UUID,
    db: AsyncSession = Depends(get_db),
    billing: Billing = Depends(verify_billing_status)  # ✅ 依存関数で共通化
):
    # ビジネスロジック
    ...

# app/api/v1/endpoints/plans.py
@router.post("/plans/")
async def create_plan(
    plan_in: PlanCreate,
    db: AsyncSession = Depends(get_db),
    billing: Billing = Depends(verify_billing_status)  # ✅ 依存関数で共通化
):
    # ビジネスロジック
    ...
```

---

### 2. マジックナンバーの問題

**❌ 悪い例**:
```python
async def check_trial_expiration(db: AsyncSession):
    # 14日間の無料期間
    trial_end = billing.created_at + timedelta(days=14)  # ❌ 14の意味が不明確

    # リトライ処理
    for i in range(3):  # ❌ 3回の根拠が不明
        try:
            result = await external_api.call()
            break
        except Exception:
            await asyncio.sleep(5)  # ❌ 5秒の根拠が不明
```

**問題点**:
- コードを読む人が数値の意味を理解できない
- 仕様変更時に全箇所を検索して修正する必要がある
- ビジネスルールがコードに埋もれる

**✅ 正しい実装**:
```python
# app/core/constants.py
TRIAL_PERIOD_DAYS = 14
MAX_API_RETRY_COUNT = 3
API_RETRY_DELAY_SECONDS = 5

async def check_trial_expiration(db: AsyncSession):
    # 無料期間の終了日を計算
    trial_end = billing.created_at + timedelta(days=TRIAL_PERIOD_DAYS)  # ✅ 定数で明示

    # リトライ処理
    for i in range(MAX_API_RETRY_COUNT):  # ✅ 定数で明示
        try:
            result = await external_api.call()
            break
        except Exception:
            await asyncio.sleep(API_RETRY_DELAY_SECONDS)  # ✅ 定数で明示
```

---

### 3. 英語エラーメッセージの問題

**❌ 悪い例**:
```python
@router.get("/users/{user_id}")
async def get_user(user_id: UUID, db: AsyncSession = Depends(get_db)):
    user = await crud.user.get(db=db, id=user_id)
    if not user:
        raise HTTPException(
            status_code=404,
            detail="User not found"  # ❌ 英語メッセージ
        )
    return user
```

**問題点**:
- エンドユーザーは日本の福祉事業所スタッフ（英語が読めない可能性）
- ユーザビリティの低下
- `.claude/CLAUDE.md` のLanguage Rulesに違反

**✅ 正しい実装**:
```python
@router.get("/users/{user_id}")
async def get_user(user_id: UUID, db: AsyncSession = Depends(get_db)):
    user = await crud.user.get(db=db, id=user_id)
    if not user:
        raise HTTPException(
            status_code=404,
            detail="利用者が見つかりません"  # ✅ 日本語メッセージ
        )
    return user
```

---

### 4. 不明瞭な変数名の問題

**❌ 悪い例**:
```python
async def process_data(db: AsyncSession, d: dict):
    # 変数名が短すぎて意味不明
    u = await crud.user.get(db=db, id=d["user_id"])
    p = await crud.plan.get(db=db, id=d["plan_id"])

    # 省略形が不明瞭
    usr_cnt = len(u.plans)  # user_count?
    msg = "完了"  # message?

    return {"usr_cnt": usr_cnt, "msg": msg}
```

**問題点**:
- コードの可読性が著しく低い
- 他の開発者が理解するのに時間がかかる
- バグの温床

**✅ 正しい実装**:
```python
async def process_support_plan_data(
    db: AsyncSession,
    plan_data: dict
) -> dict:
    # 明確な変数名
    user = await crud.user.get(db=db, id=plan_data["user_id"])
    support_plan = await crud.plan.get(db=db, id=plan_data["plan_id"])

    # 完全な単語を使用
    user_plan_count = len(user.plans)
    completion_message = "処理が完了しました"

    return {
        "plan_count": user_plan_count,
        "message": completion_message
    }
```

---

### 5. 過度に長い関数の問題

**❌ 悪い例**:
```python
async def create_user_with_everything(
    db: AsyncSession,
    user_in: UserCreate,
    profile_in: ProfileCreate,
    plan_in: PlanCreate
):
    # 100行以上の処理...
    # ユーザー作成
    user = User(**user_in.dict())
    db.add(user)
    await db.flush()

    # プロフィール作成
    profile = Profile(**profile_in.dict(), user_id=user.id)
    db.add(profile)

    # プラン作成
    plan = Plan(**plan_in.dict(), user_id=user.id)
    db.add(plan)

    # メール送信
    await send_welcome_email(user.email)

    # Slack通知
    await notify_slack(f"新規ユーザー: {user.name}")

    # 監査ログ
    audit = AuditLog(action="user_created", user_id=user.id)
    db.add(audit)

    await db.commit()
    # ... さらに50行
```

**問題点**:
- 1つの関数が複数の責務を持っている（SRP違反）
- テストが困難
- デバッグが困難
- 再利用ができない

**✅ 正しい実装**:
```python
# 責務ごとに関数を分割
async def create_user(db: AsyncSession, user_in: UserCreate) -> User:
    """ユーザーを作成する"""
    user = User(**user_in.dict())
    db.add(user)
    await db.flush()
    return user

async def create_user_profile(
    db: AsyncSession,
    user_id: UUID,
    profile_in: ProfileCreate
) -> Profile:
    """ユーザープロフィールを作成する"""
    profile = Profile(**profile_in.dict(), user_id=user_id)
    db.add(profile)
    await db.flush()
    return profile

async def send_user_notifications(user: User):
    """ユーザー登録通知を送信する"""
    await send_welcome_email(user.email)
    await notify_slack(f"新規ユーザー: {user.name}")

# メインのサービス関数は各関数を組み合わせる
async def create_user_with_profile(
    db: AsyncSession,
    user_in: UserCreate,
    profile_in: ProfileCreate
) -> User:
    """ユーザーとプロフィールを作成する"""
    try:
        user = await create_user(db=db, user_in=user_in)
        profile = await create_user_profile(db=db, user_id=user.id, profile_in=profile_in)

        await db.commit()
        await db.refresh(user)

        # commit後に通知送信
        await send_user_notifications(user)

        return user
    except Exception as e:
        await db.rollback()
        raise
```

---

## 修正方針

### 原則1: DRYの徹底

**ルール**:
- 同じロジックが2回以上出現したら共通化を検討
- 共通化の方法:
  - 依存関数（FastAPI Depends）
  - ユーティリティ関数（`app/utils/`）
  - 定数ファイル（`app/core/constants.py`）

---

### 原則2: マジックナンバーの排除

**ルール**:
- 数値・文字列リテラルは定数化
- 定数の配置:
  - ビジネスルール: `app/core/constants.py`
  - 環境設定: `app/core/config.py`
  - モデル固有: モデルクラスの定数

**定数ファイルの例**:
```python
# app/core/constants.py

# 課金関連
TRIAL_PERIOD_DAYS = 14
PAYMENT_RETRY_LIMIT = 3

# ステータス
class BillingStatus:
    FREE = "free"
    EARLY_PAYMENT = "early_payment"
    ACTIVE = "active"
    PAST_DUE = "past_due"
    CANCELED = "canceled"

# レート制限
RATE_LIMIT_LOGIN = "5/minute"
RATE_LIMIT_DASHBOARD = "60/minute"
```

---

### 原則3: ユーザー向けメッセージの日本語化

**ルール**:
- HTTPException の detail は必ず日本語
- ログメッセージも日本語（開発者が日本人）
- エラーメッセージ集の作成を検討

**エラーメッセージ集の例**:
```python
# app/core/messages.py

class ErrorMessages:
    # 認証・認可
    UNAUTHORIZED = "認証が必要です"
    FORBIDDEN = "この操作を行う権限がありません"

    # リソース
    USER_NOT_FOUND = "利用者が見つかりません"
    OFFICE_NOT_FOUND = "事業所が見つかりません"

    # 課金
    PAYMENT_REQUIRED = "支払いが必要です"
    BILLING_STATUS_PAST_DUE = "お支払いが滞っています。プランをご確認ください"
```

---

### 原則4: 明確な命名規則

**ルール**:
- 省略形を避ける（例外: ID, URL, API など一般的な略語）
- 意図を表す名前にする
- Pythonの命名規則に従う:
  - 関数/変数: `snake_case`
  - クラス: `PascalCase`
  - 定数: `UPPER_SNAKE_CASE`

**良い命名例**:
```python
# ✅ Good
user_count = len(users)
support_plan_data = get_plan_data()
is_billing_active = billing.status == "active"

# ❌ Bad
cnt = len(users)
data = get_plan_data()
flag = billing.status == "active"
```

---

### 原則5: Single Responsibility Principle（単一責任原則）

**ルール**:
- 1つの関数は1つの責務のみ
- 目安: 関数は50行以内
- 複雑な処理は小さな関数に分割
- Early Returnパターンで可読性向上

**Early Returnパターンの例**:
```python
# ✅ Good: Early Return
async def get_user_plan(db: AsyncSession, user_id: UUID) -> Plan:
    user = await crud.user.get(db=db, id=user_id)
    if not user:
        raise HTTPException(status_code=404, detail="利用者が見つかりません")

    plan = await crud.plan.get_by_user_id(db=db, user_id=user_id)
    if not plan:
        raise HTTPException(status_code=404, detail="個別支援計画が見つかりません")

    return plan

# ❌ Bad: Nested if
async def get_user_plan(db: AsyncSession, user_id: UUID) -> Plan:
    user = await crud.user.get(db=db, id=user_id)
    if user:
        plan = await crud.plan.get_by_user_id(db=db, user_id=user_id)
        if plan:
            return plan
        else:
            raise HTTPException(status_code=404, detail="個別支援計画が見つかりません")
    else:
        raise HTTPException(status_code=404, detail="利用者が見つかりません")
```

---

## 修正手順

### Step 1: 現状調査

```bash
# 1. DRY違反の検出
grep -rn "if billing.status ==" k_back/app/ | wc -l
grep -rn "HTTPException.*402.*detail" k_back/app/ | wc -l

# 2. マジックナンバーの検出
grep -rn "timedelta(days=" k_back/app/ | grep -v "TRIAL\|PERIOD"
grep -rn '"active"\|"inactive"\|"pending"' k_back/app/ | grep -v "constants.py"

# 3. 英語エラーメッセージの検出
grep -rn 'HTTPException.*detail.*"[A-Z]' k_back/app/api/v1/endpoints/

# 4. 長い関数の検出（50行以上）
# （上記の検出コマンド参照）
```

**結果を記録**: `検出結果.md` に記載

---

### Step 2: 優先度付け

| 問題タイプ | 影響度 | 優先度 | 修正難易度 |
|----------|-------|--------|-----------|
| 英語エラーメッセージ | 🔴 High | 1 | 低 |
| DRY違反（重複ロジック） | 🟠 Medium | 2 | 中 |
| マジックナンバー | 🟡 Low | 3 | 低 |
| 不明瞭な変数名 | 🟢 Low | 4 | 低 |
| 長い関数 | 🟡 Low | 3 | 高 |

---

### Step 3: 修正実施

#### 3-1. 英語エラーメッセージの日本語化

```python
# Before
raise HTTPException(status_code=404, detail="User not found")

# After
raise HTTPException(status_code=404, detail="利用者が見つかりません")
```

#### 3-2. DRY違反の解消

```python
# Before: 重複したバリデーション
# File 1
if billing.status == "past_due":
    raise HTTPException(...)

# File 2
if billing.status == "past_due":
    raise HTTPException(...)

# After: 依存関数で共通化
# app/api/deps.py
async def verify_billing_status(...):
    ...

# File 1, File 2
async def endpoint(..., billing: Billing = Depends(verify_billing_status)):
    ...
```

#### 3-3. マジックナンバーの定数化

```python
# Before
trial_end = created_at + timedelta(days=14)

# After
# app/core/constants.py
TRIAL_PERIOD_DAYS = 14

# Service
from app.core.constants import TRIAL_PERIOD_DAYS
trial_end = created_at + timedelta(days=TRIAL_PERIOD_DAYS)
```

---

### Step 4: テストの追加

保守性改善後も既存機能が動作することを確認:

```python
# tests/api/test_error_messages.py
async def test_error_messages_in_japanese(client):
    """エラーメッセージが日本語であることを確認"""
    response = await client.get("/api/v1/users/invalid-uuid")
    assert response.status_code == 404
    assert "見つかりません" in response.json()["detail"]
    assert response.json()["detail"] != response.json()["detail"].encode('ascii', 'ignore').decode()
```

---

## チェックリスト

### 修正前チェック
- [ ] 現状調査スクリプト実行
- [ ] 検出結果をドキュメント化
- [ ] 優先度付け
- [ ] ブランチ作成: `refactor/maintainability-improvements`

### 修正中チェック
- [ ] 英語エラーメッセージの日本語化
- [ ] DRY違反の解消（依存関数・ユーティリティ化）
- [ ] マジックナンバーの定数化
- [ ] 不明瞭な変数名の改善
- [ ] 長い関数の分割（50行以上 → 複数関数に分割）
- [ ] テストの追加

### 修正後チェック
- [ ] 全テストがPASSすることを確認
- [ ] 英語エラーメッセージが0件になることを確認
- [ ] マジックナンバーが削減されたことを確認
- [ ] コードレビュー依頼
- [ ] PR作成

---

## 期待される効果

### 定量的効果
- ✅ 英語エラーメッセージ: 検出数 → 0件
- ✅ DRY違反: 重複コード -30%
- ✅ マジックナンバー: -50%
- ✅ 平均関数行数: 80行 → 40行

### 定性的効果
- ✅ コード可読性の向上
- ✅ 保守性の向上（修正箇所の局所化）
- ✅ ユーザビリティの向上（日本語エラーメッセージ）
- ✅ バグ混入リスクの低減

---

## リスク分析

| リスク | 影響度 | 発生確率 | 対策 |
|-------|-------|---------|-----|
| 既存機能の破壊 | 🟠 Medium | 🟢 Low | テストの充実 |
| 定数名の不一致 | 🟡 Low | 🟡 Medium | 命名規則の統一 |
| 過度なリファクタリング | 🟡 Low | 🟡 Medium | 優先度に従って段階的実施 |

---

## 関連Issue

- Issue #01: API層のcommit違反修正
- Issue #02: トランザクション境界の整備

---

## 参考資料

- `.claude/skills/SKILLS.md` - maintainability-rules スキル
- `.claude/CLAUDE.md` - Language Rules、Code Standards
- PEP 8: Python Style Guide

---

**作成日**: 2026-02-18
**担当者**: 未割当
**レビュアー**: 未割当
**期限**: 未設定
