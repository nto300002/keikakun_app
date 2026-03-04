# AIコーディング時の注意点

**作成日**: 2026-03-01
**参照元**: `issue_01` / `issue_02` / `issue_03` / `architecture_violation_audit_2026-02-20.md`
**目的**: AIにコーディングさせる際に再現しやすいアンチパターンを、実際の違反実績をもとに整理する

---

## バックエンドディレクトリ構造

```
k_back/app/
├── api/
│   └── v1/
│       └── endpoints/          ← 【API層】HTTP処理のみ。commit/flush禁止
│           ├── auths.py             ← commit違反 7件（修正済）
│           ├── mfa.py               ← commit違反 7件（修正済）
│           ├── messages.py          ← commit違反 5件
│           ├── role_change_requests.py ← commit違反 4件
│           ├── calendar.py          ← commit違反 4件
│           ├── withdrawal_requests.py  ← commit違反 3件 / 直接import 2件
│           ├── admin_inquiries.py   ← commit違反 3件 / 直接import 1件
│           ├── welfare_recipients.py   ← commit違反 2件 / 直接import 1件
│           ├── staffs.py            ← commit違反 2件
│           ├── push_subscriptions.py   ← 英語エラーメッセージ 6件
│           ├── admin_audit_logs.py  ← 直接import 1件
│           ├── notices.py           ← 直接import 1件
│           ├── inquiries.py         ← 直接import 1件
│           ├── messages.py          ← 直接import 1件
│           ├── archived_staffs.py   ← 直接import 1件
│           ├── admin_announcements.py  ← 直接import 1件
│           └── ... (その他 terms / support_plans / offices / notices 等)
│
├── services/                   ← 【Service層】ビジネスロジック・トランザクション管理
│   ├── auth_service.py              ← auths.py のロジック移管先（新規作成済）
│   ├── mfa.py                       ← mfa.py のロジック移管先（拡張済）
│   ├── billing_service.py           ← commit 6件（分断トランザクション）
│   ├── support_plan_service.py      ← commit 4件・rollback欠如（修正済）
│   ├── staff_profile_service.py     ← commit 4件・rollback欠如（修正済）
│   ├── role_change_service.py       ← commit 3件・rollback/try-except欠如（修正済）
│   ├── employee_action_service.py   ← commit 3件 / 直接import 3件（修正済）
│   ├── welfare_recipient_service.py ← commit 2件 / 直接import 2件 / timedelta×2（修正済）
│   ├── withdrawal_service.py        ← commit漏れ / 直接import 5件（修正済）
│   ├── assessment_service.py        ← commit漏れ
│   ├── calendar_service.py          ← 直接import 2件（修正済）
│   ├── cleanup_service.py           ← 直接import 1件（修正済）
│   └── dashboard_service.py
│
├── crud/                       ← 【CRUD層】単一モデルのDB操作のみ
│   ├── __init__.py                  ← ここから `from app import crud` で参照する
│   ├── crud_welfare_recipient.py    ← timedelta(days=180) ハードコード
│   ├── crud_dashboard.py            ← timedelta(days=30) ハードコード×3
│   ├── crud_audit_log.py            ← timedelta(days=365) ハードコード
│   └── ... (その他 crud_billing / crud_staff / crud_notice 等)
│
├── models/                     ← 【Models層】SQLAlchemyモデル定義
├── schemas/                    ← Pydanticスキーマ定義
├── core/
│   ├── config.py                    ← 環境設定・定数の配置先（timedelta定数はここへ）
│   ├── exceptions.py
│   ├── security.py
│   └── ...
└── utils/
```

---

## 注意点 1: API層に `db.commit()` / `db.flush()` を書かせない

**実績**: `api/v1/endpoints/` 配下で **45件・17ファイル** に混入。
issue認識後も新機能追加のたびに増加し続けた（20件→45件）。

### なぜAIが再現するか

AIはエンドポイント関数単体でコードを完結させようとするため、Service層への委譲を省略してAPI層に直接DBコミットを書く。

### ルール

```
api/v1/endpoints/*.py  →  commit / flush / CRUD直接呼び出し  禁止
services/*.py          →  commit は最後に1回のみ、rollback必須
crud/*.py              →  単一モデルの操作のみ
```

### 確認コマンド

```bash
# API層のcommit/flush違反を検出
grep -rn "await db.commit()\|await db.flush()" k_back/app/api/v1/endpoints/
```

### AIへの指示例

> 「API層（endpoints/）にはcommit・flush・CRUD直接呼び出しを書かないこと。
> ビジネスロジックはすべてservices/に委譲し、エンドポイントはService呼び出しのみにする。」

---

## 注意点 2: `from app.crud.xxx import crud_xxx` を書かせない

**実績**: API層で **11件・10ファイル**、Service層で **16件・6ファイル** に混入。

### なぜAIが再現するか

AIはファイルを個別に生成するため、既存の `from app import crud` パターンに気づかず、
IDE補完的に `from app.crud.crud_xxx import crud_xxx` を直接importする。

### ルール

```python
# ✅ 正しい（循環依存を防ぐ）
from app import crud
billing = await crud.billing.get_by_office_id(db=db, office_id=office_id)

# ❌ 禁止（循環依存のリスク）
from app.crud.crud_billing import crud_billing
billing = await crud_billing.get_by_office_id(db=db, office_id=office_id)
```

### 確認コマンド

```bash
# 直接import違反を検出
grep -rn "from app.crud\." k_back/app/api/ k_back/app/services/
```

### AIへの指示例

> 「CRUDモジュールは必ず `from app import crud` でimportし、
> `from app.crud.crud_xxx import xxx` の形式は絶対に使わないこと。」

---

## 注意点 3: rollback なしの commit を書かせない

**実績**: Service層の3ファイルで `commit × 3〜4` にもかかわらず `try-except` も `rollback` もゼロで本番混入。

- `role_change_service.py`: commit×3・try-except欠如・rollbackなし
- `staff_profile_service.py`: commit×4・rollbackなし
- `support_plan_service.py`: commit×4・rollbackなし

### なぜAIが再現するか

AIはハッピーパスのコードしか書かない傾向がある。エラーハンドリング（特にDB rollback）は明示的に指示しないと省略される。

### 必須テンプレート（Service層）

```python
# services/xxx_service.py
async def some_service_method(db: AsyncSession, ...) -> SomeModel:
    """処理の説明"""
    try:
        # ビジネスロジック
        result = await crud.xxx.create(db=db, obj_in=data_in)

        await db.commit()          # ← 最後に1回だけ
        await db.refresh(result)   # ← commit後に必ずrefresh
        return result

    except Exception as e:
        await db.rollback()        # ← エラー時は必ずrollback
        logger.error(f"処理に失敗しました: {e}")
        raise
```

### 確認コマンド

```bash
# commitがあるがrollbackがないService層ファイルを検出
for file in k_back/app/services/*.py; do
  if grep -q "await db.commit()" "$file" && ! grep -q "await db.rollback()" "$file"; then
    echo "⚠️  rollback欠如: $file"
  fi
done
```

### AIへの指示例

> 「Service層のメソッドは必ずtry-except-rollbackパターンで実装すること。
> commitは関数の最後に1回のみ。例外時は必ず `await db.rollback()` を実行してraiseする。」

---

## 注意点 4: 1関数に複数の commit を書かせない

**実績**: `billing_service.py`（6件）など複数箇所に分断されたcommitが存在。

### なぜ問題か

複数commitによりアトミック性が失われる。途中でエラーが発生しても前のcommitはロールバックできない。

```python
# ❌ 悪い例：複数commit（billing_service.pyで実際に発生）
user = User(...)
db.add(user)
await db.commit()  # ← commit 1

billing = Billing(user_id=user.id)
db.add(billing)
await db.commit()  # ← commit 2

# ここでエラー → user と billing は残ったまま（ロールバック不可）
await send_welcome_email(user.email)
```

```python
# ✅ 正しい例：1トランザクション1commit
user = User(...)
db.add(user)
billing = Billing(user_id=user.id)
db.add(billing)

await db.commit()  # ← まとめて1回
await send_welcome_email(user.email)  # ← commit後に外部API
```

### AIへの指示例

> 「1つのService関数内でcommitは最後に1回のみにすること。
> 途中でflushが必要な場合はflushを使い、commitはすべての処理が成功してから1回だけ実行する。」

---

## 注意点 5: 英語エラーメッセージを書かせない

**実績**: `push_subscriptions.py` で6件の英語エラーメッセージが混入。

```python
# ❌ 実際に混入したコード（push_subscriptions.py）
detail="Failed to subscribe push notifications"
detail="Subscription not found"
detail="Not authorized to delete this subscription"
```

```python
# ✅ 正しい実装
detail="プッシュ通知の登録に失敗しました"
detail="サブスクリプションが見つかりません"
detail="このサブスクリプションを削除する権限がありません"
```

### 確認コマンド

```bash
# 英語エラーメッセージを検出（大文字始まりのdetail）
grep -rn 'detail="[A-Z]' k_back/app/api/v1/endpoints/
```

### AIへの指示例

> 「HTTPExceptionのdetailは必ず日本語で記述すること。英語メッセージは禁止。」

---

## 注意点 6: マジックナンバーをハードコードさせない

**実績**: `timedelta(days=180)` が5箇所、`timedelta(days=30)` が3箇所にバラバラに存在。

| 数値 | 意味 | 散在箇所 |
|------|------|---------|
| `timedelta(days=180)` | 個別支援計画の更新期限 | `crud_welfare_recipient.py` / `welfare_recipient_service.py`(×2) / `support_plan_service.py`(×2) |
| `timedelta(days=30)` | 期限切れ間近の閾値 | `crud_dashboard.py`(×3) |
| `timedelta(days=365)` | 監査ログ保持期間 | `crud_audit_log.py` |

### ルール

```python
# core/config.py に集約する
SUPPORT_PLAN_RENEWAL_DAYS: int = 180       # 個別支援計画の次回更新期限
DASHBOARD_DEADLINE_WARNING_DAYS: int = 30  # 期限切れ間近の警告閾値
AUDIT_LOG_RETENTION_DAYS: int = 365        # 監査ログ保持期間

# 使用側
from app.core.config import settings
trial_end = created_at + timedelta(days=settings.SUPPORT_PLAN_RENEWAL_DAYS)
```

### AIへの指示例

> 「ビジネスルールの数値（日数・件数・閾値等）は直接書かず、
> `app/core/config.py` に定数として定義してから参照すること。」

---

## 注意点 7: DRY違反（同一ロジックのコピペ）

**実績**: 課金ステータスチェック・HTTPException等が複数エンドポイントに重複。

### なぜAIが再現するか

AIは指定されたファイルしか参照しないため、既存の共通ロジックを知らずコピペを生成する。

### ルール（共通化の方法）

| 場所 | 共通化手段 |
|------|----------|
| `api/v1/endpoints/` | FastAPI `Depends()` 依存関数（`api/deps.py`） |
| `services/` | 共通 Service メソッド |
| 定数・文字列 | `app/core/constants.py` または `app/core/config.py` |

### AIへの指示例

> 「同様のバリデーションや処理が既存コードにある場合は、
> FastAPI Depends や共通関数として切り出し、コピペせずに再利用すること。」

---

## 実践チェックリスト（AIコード生成後に実施）

### 自動検出（grepで即確認）

```bash
# 1. API層のcommit/flush違反
grep -rn "await db.commit()\|await db.flush()" k_back/app/api/v1/endpoints/

# 2. 直接import違反（API層・Service層）
grep -rn "from app.crud\." k_back/app/api/ k_back/app/services/

# 3. rollback欠如（commitがあるService層ファイル）
for file in k_back/app/services/*.py; do
  if grep -q "await db.commit()" "$file" && ! grep -q "await db.rollback()" "$file"; then
    echo "⚠️  rollback欠如: $file"
  fi
done

# 4. 英語エラーメッセージ
grep -rn 'detail="[A-Z]' k_back/app/api/v1/endpoints/

# 5. timedelta ハードコード
grep -rn "timedelta(days=" k_back/app/ | grep -v "constants\|config"
```

### 目視確認

- [ ] API層のエンドポイントがService層を1回呼ぶだけになっているか
- [ ] Service層がtry-except-rollbackパターンを使っているか
- [ ] commitが1関数内で1回のみか
- [ ] `from app import crud` のみを使っているか
- [ ] エラーメッセージが日本語か
- [ ] 数値リテラルが直接コード内に書かれていないか

---

## AIへの指示テンプレート（コピペして使う）

```
以下のルールを厳守してコードを生成してください:

1. API層（endpoints/）: commit・flush・CRUD直接呼び出し禁止。Service層への委譲のみ。
2. Service層: try-except-rollbackパターン必須。commitは最後に1回のみ。
3. CRUDのimport: 必ず `from app import crud` を使う。`from app.crud.crud_xxx` は禁止。
4. エラーメッセージ: HTTPExceptionのdetailは必ず日本語。
5. 数値定数: ハードコードせず `app/core/config.py` の定数を参照。
6. 重複コード: 共通ロジックはDepsや共通関数として切り出す。

生成後、以下コマンドで自己確認すること:
  grep -rn "await db.commit()" app/api/v1/endpoints/
  grep -rn "from app.crud\." app/api/ app/services/
```

---

**作成日**: 2026-03-01
**参照元**: `issue_01_api_layer_commit_violations.md` / `issue_02_transaction_boundary_improvements.md` / `issue_03_maintainability_improvements.md` / `architecture_violation_audit_2026-02-20.md`
