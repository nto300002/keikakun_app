# EDIT
## 優先度: hign
- editツールを用いた修正
## 優先度: Low
- sed -i

---

# Skill: バックエンドDocker実行ルール

**スキルID**: `backend-docker-execution`
**カテゴリ**: 実行環境 / テスト実行
**作成日**: 2026-06-15

---

## 目的

このリポジトリのバックエンドはホスト側 Python 直実行ではなく、Docker コンテナ上で実行する前提で扱う。

---

## 実行対象コンテナ

バックエンドは次の Docker コンテナで起動している。

```text
d14219916d99   keikakun_app-backend   "uvicorn app.main:ap..."   Up 13 hours   0.0.0.0:8000->8000/tcp   keikakun_app-backend-1
```

以後、backend の pytest、lint、管理コマンド、依存環境確認は、原則としてホスト側に `.venv` を作って実行せず、既存コンテナ内で実行する。

---

## コマンド例

### backend pytest

```bash
docker exec keikakun_app-backend-1 pytest tests/tasks/test_billing_check.py tests/utils/test_safe_cleanup_with_flag.py -m "not performance"
```

### backend shell

```bash
docker exec -it keikakun_app-backend-1 bash
```

### backend Python

```bash
docker exec keikakun_app-backend-1 python -m pytest
```

---

## 注意点

- ホスト側で `pytest` や `python -m pytest` が見つからなくても、まず Docker コンテナ内で実行する。
- Python 依存関係の追加・確認も、原則としてコンテナ内の環境を基準にする。
- Docker daemon への接続に権限が必要な場合は、`docker exec` の実行許可を取得してから進める。
- backend のテスト結果は、コンテナ内のアプリコード・依存関係・環境変数を基準に判断する。

### backend コンテナ起動前エラーの切り分け

backend コンテナが Python 起動前に次のようなエラーで落ちる場合がある。

```text
Fatal Python error: init_fs_encoding: failed to get the Python codec of the filesystem encoding
OSError: [Errno 24] Too many open files: '/app'
```

この場合は、DB接続、Alembic、pytest の失敗ではなく、Docker Desktop の bind mount `./k_back:/app` 参照時の問題として扱う。まず現在の状態を確認する。

```bash
docker compose ps
docker logs --tail=80 keikakun_app-backend-1
```

DB metadata の read-only 確認など、アプリ import が不要な診断だけであれば、`/app` を参照しないように `/tmp` へ移動し、`PYTHONPATH` を外して backend コンテナ内 Python を起動する。

```bash
docker compose run --rm --entrypoint sh backend -lc 'cd /tmp && unset PYTHONPATH && python - <<"..."
print("python_ok")
...
'
```

この回避は環境診断専用とし、pytest やアプリケーション挙動の検証には使わない。pytest や Alembic の通常確認は、backend コンテナが `/app` を正常に参照できる状態に戻してから実行する。

---

## DB migration / SQLファイル作成ルール

このアプリでは、DB定義変更や既存データ移行を行う場合、Alembic migration を正とする。

本番DBへの通常反映は、CDで `alembic upgrade head` を実行する形式に寄せる。手動SQLは確認用、調査用、緊急対応用に限定し、通常の反映手段として扱わない。

原則:

- Alembic migration は `k_back/migrations/versions/` に作成する。
- DB定義変更、enum値追加、check constraint変更、カラム追加、index追加、既存データ更新は、Alembic migration に実装する。
- 手動SQLファイルは必須ではない。必要な場合のみ、確認用SQL、影響範囲確認SQL、緊急rollback手順として作成する。
- 手動SQLを作成する場合も、migration と矛盾させない。手動SQLだけでDB変更を完了扱いにしない。
- 既存データを更新するmigrationでは、更新前後の対象件数を確認できるSQLまたは手順をタスクmdに記録する。
- 破壊的変更、enum値削除、カラム削除、NOT NULL化、制約強化は、通常CDに一括で混ぜず、前方互換を保つ段階的migrationに分ける。
- `CREATE INDEX CONCURRENTLY` のようにAlembicの通常トランザクションと相性が悪い処理は、migration設計時に明記し、必要に応じて専用migrationまたは個別手順として扱う。
- 既存DBのbaseline合わせで `alembic stamp` を使う場合は、通常CDではなく管理操作として扱い、実行環境・対象DB・revisionをmdに記録する。
- CI/CDやmigration関連の変更をpushする前に、GitHub Actions workflow と Cloud Build substitutions のDB接続先を必ず照合する。
- GitHub Actionsの `secrets.*` 名が実際に存在するか確認し、存在しないDB secretを参照しない。例えば `PROD_TEST_DATABASE_URL` が存在しない運用では、Cloud Buildの `_PROD_TEST_DATABASE_URL` へ渡す値を、実在する `TEST_DATABASE_URL` など意図した接続先に明示的に割り当てる。
- DB接続先の確認では、GitHub Actions側の `secrets.*`、Cloud Build側の `_SUBSTITUTION`、コンテナ内の `DATABASE_URL` / `TEST_DATABASE_URL` がどのDBを指すかを一続きで確認する。
- 現時点で確認済みの GitHub Actions secrets 名は次の通り。workflow 変更時はこの一覧にない `secrets.*` を追加参照しない。
  - `AWS_ACCESS_KEY_ID`
  - `AWS_REGION`
  - `AWS_SECRET_ACCESS_KEY`
  - `CALENDAR_ENCRYPTION_KEY`
  - `COOKIE_DOMAIN`
  - `COOKIE_SAMESITE`
  - `COOKIE_SECURE`
  - `E2E_API_URL`
  - `E2E_DATABASE_URL`
  - `E2E_OWNER_EMAIL`
  - `E2E_OWNER_PASSWORD`
  - `E2E_SECRET_KEY`
  - `E2E_STAFF_PASSWORD`
  - `E2E_STRIPE_PUBLISHABLE_KEY`
  - `E2E_VAPID_PUBLIC_KEY`
  - `ENVIRONMENT`
  - `FRONTEND_URL`
  - `GCP_PROJECT_ID`
  - `GCP_SA_KEY`
  - `MAIL_PASSWORD`
  - `MAIL_PORT`
  - `MAIL_SERVER`
  - `MAIL_USERNAME`
  - `PASSWORD_RESET_TOKEN_EXPIRE_MINUTES`
  - `PLAYWRIGHT_BASE_URL`
  - `PROD_DATABASE_URL`
  - `PROD_SECRET_KEY`
  - `RATE_LIMIT_FORGOT_PASSWORD`
  - `RATE_LIMIT_RESEND_EMAIL`
  - `S3_ACCESS_KEY`
  - `S3_BUCKET_NAME`
  - `S3_REGION`
  - `S3_SECRET_KEY`
  - `SENDER_EMAIL`
  - `STRIPE_PRICE_ID`
  - `STRIPE_PUBLISHABLE_KEY`
  - `STRIPE_SECRET_KEY`
  - `STRIPE_WEBHOOK_SECRET`
  - `TEST_DATABASE_URL`
  - `VAPID_PRIVATE_KEY`
  - `VAPID_PUBLIC_KEY`
- `ENCRYPTION_KEY` は現在 GitHub Actions secrets に存在しない。明示的に secret を追加するまでは `secrets.ENCRYPTION_KEY` を参照しない。現行の本番 MFA 互換性では、Cloud Build の `_ENCRYPTION_KEY` は既存の `secrets.PROD_SECRET_KEY` から渡す。別鍵に切り替える場合は、既存 `mfa_secret` の復号・再暗号化を含む鍵ローテーション計画を先に作る。

レビュー時の確認項目:

- [ ] Alembic migration ファイルがあるか？
- [ ] DB変更が手動SQLだけで完了扱いになっていないか？
- [ ] migration の `upgrade()` が本番反映の正になっているか？
- [ ] rollback相当の手順があるか？
- [ ] 実行前・実行後の確認SQLまたは確認手順があるか？
- [ ] 既存データ更新の対象件数を確認できるか？
- [ ] CI/CD workflow が実在するDB secret名だけを参照しているか？
- [ ] Cloud Build substitutions と `DATABASE_URL` の対応が意図したDB接続先になっているか？
- [ ] CI/CD workflow が実在する全 secret 名だけを参照しているか？特に未作成の `ENCRYPTION_KEY` を参照していないか？

### local Alembic確認コマンド

backendのAlembic確認は、原則としてbackend Dockerコンテナ内で行う。

revision graphと現在revisionの確認:

```bash
docker exec keikakun_app-backend-1 sh -lc 'alembic heads && alembic current'
```

本番main DBを明示して、CD相当の `upgrade head` が成功するか確認する:

```bash
docker exec keikakun_app-backend-1 sh -lc 'DATABASE_URL="$PROD_DATABASE_URL" alembic upgrade head && DATABASE_URL="$PROD_DATABASE_URL" alembic current'
```

注意:

- `alembic upgrade head` はDBへ実変更を行う可能性がある。未確認DBに対して気軽に実行しない。
- head到達済みDBでは `upgrade head` はno-opになり、CD相当の接続・実行確認として使える。
- `alembic check` はSQLAlchemy metadataと実DB schemaの差分検出用であり、未適用revisionがなくてもschema差分が残っている場合は失敗する。
- `alembic upgrade head --sql` はoffline SQL生成用だが、既存migrationにDB問い合わせを前提にした処理がある場合は失敗するため、このプロジェクトではCD相当確認としては `upgrade head` を使う。
- baseline合わせの `alembic stamp` は通常のlocal確認コマンドでは実行しない。対象DBとrevisionを明確にした管理操作として扱う。

---

## Git管理方針メモ

2026-06-16 に `.codex/skills/SKILLS.md` をリモートへ push すべきか調査した。

結論:

- `.codex/skills/SKILLS.md` はローカル Codex 用の運用メモとして扱い、原則としてリモートへ push しない。
- このリポジトリでは `.gitignore` により `.codex` が ignore されているため、`.codex/` は共有リポジトリ管理対象ではなく、個人/ローカル環境の設定領域として扱う。
- チーム全体へ共有すべき agent instructions がある場合は、`.codex/` を `git add -f` するのではなく、`AGENTS.md` や `.github/copilot-instructions.md` など、リポジトリ共有前提の instruction file に最小限の内容として移す。

調査メモ:

- GitHub Docs では、repository-wide custom instructions は `.github/copilot-instructions.md`、path-specific instructions は `.github/instructions/*.instructions.md` として管理する形式が案内されている。
- AI agent 向けの repo-level instruction file は有用な一方、過剰な指示は探索量や誤誘導を増やす可能性があるため、共有する場合は短く明確な内容に限定する。
- 今回の backend Docker 実行ルールは、現時点ではこのローカル `SKILLS.md` と、調査ログ `md_files_design_note/task/done/log/backend_ci_billing_cleanup_failure_2026-06-15.md` に記録する。


# Skill: 4層アーキテクチャにおけるcommit/flush使い分けチェック

**スキルID**: `commit-flush-check`
**カテゴリ**: アーキテクチャレビュー / コード品質
**作成日**: 2026-02-18

---

## 目的

4層アーキテクチャの各層における責務に応じて、`commit()` と `flush()` が正しく使い分けられているかをチェックする。

---

## 4層アーキテクチャにおけるcommit/flushルール

### 📋 各層の責務とDB操作ルール

| 層 | ディレクトリ | commit() | flush() | 理由 |
|----|------------|----------|---------|------|
| **API層** | `app/api/v1/endpoints/` | ❌ **禁止** | ❌ **禁止** | HTTP処理のみ、ビジネスロジック/DB操作はService層に委譲 |
| **Services層** | `app/services/` | ✅ **必須** | ✅ **許可** | 複数CRUD操作のトランザクション境界を管理 |
| **CRUD層** | `app/crud/` | ✅ **許可** | ✅ **必須** | 単一モデルのCRUD操作後にcommit（単純な場合） |
| **Models層** | `app/models/` | ❌ **禁止** | ❌ **禁止** | データ定義のみ、DB操作なし |

---

## チェック項目

### 1. API層のcommit/flush禁止チェック

**❌ 悪い例**:
```python
# app/api/v1/endpoints/users.py
@router.post("/")
async def create_user(
    user_in: UserCreate,
    db: AsyncSession = Depends(get_db)
):
    user = User(**user_in.dict())
    db.add(user)
    await db.commit()  # ❌ API層でcommitしてはいけない
    await db.refresh(user)
    return user
```

**✅ 良い例**:
```python
# app/api/v1/endpoints/users.py
@router.post("/")
async def create_user(
    user_in: UserCreate,
    db: AsyncSession = Depends(get_db),
    current_user: Staff = Depends(deps.get_current_user)
):
    # ビジネスロジック/DB操作はService層に委譲
    user = await user_service.create_user(db=db, user_in=user_in, created_by=current_user.id)
    return user  # ✅ API層はService層を呼ぶだけ
```

---

### 2. Service層のcommit必須チェック

**❌ 悪い例**:
```python
# app/services/user_service.py
async def create_user_with_profile(
    db: AsyncSession,
    user_in: UserCreate,
    profile_in: ProfileCreate
):
    # 複数のCRUD操作を呼ぶが、commitしていない
    user = await crud.user.create(db=db, obj_in=user_in)
    profile = await crud.profile.create(db=db, user_id=user.id, obj_in=profile_in)
    # ❌ commitがないため、トランザクションが完了しない
    return user
```

**✅ 良い例**:
```python
# app/services/user_service.py
async def create_user_with_profile(
    db: AsyncSession,
    user_in: UserCreate,
    profile_in: ProfileCreate
):
    # 複数CRUD操作のトランザクション境界を管理
    user = await crud.user.create(db=db, obj_in=user_in)
    await db.flush()  # ✅ user.idを取得するためflush

    profile = await crud.profile.create(db=db, user_id=user.id, obj_in=profile_in)

    await db.commit()  # ✅ Service層でトランザクションをcommit
    await db.refresh(user)
    await db.refresh(profile)
    return user, profile
```

---

### 3. CRUD層のflush必須チェック（ID取得が必要な場合）

**❌ 悪い例**:
```python
# app/crud/crud_user.py
async def create(
    db: AsyncSession,
    obj_in: UserCreate
) -> User:
    user = User(**obj_in.dict())
    db.add(user)
    # ❌ user.idが必要な場合、flushしないとIDが取得できない
    return user  # user.id is None!
```

**✅ 良い例**:
```python
# app/crud/crud_user.py
async def create(
    db: AsyncSession,
    obj_in: UserCreate
) -> User:
    user = User(**obj_in.dict())
    db.add(user)
    await db.flush()  # ✅ IDを取得するためflush
    return user  # user.id is available
```

---

### 4. CRUD層のcommit判断チェック

**単純なCRUD操作の場合**:
```python
# ✅ 良い例: 単一モデルの単純なCRUD操作
async def create(db: AsyncSession, obj_in: UserCreate) -> User:
    user = User(**obj_in.dict())
    db.add(user)
    await db.commit()  # ✅ 単純な操作はCRUD層でcommit可
    await db.refresh(user)
    return user
```

**複雑なビジネスロジックが絡む場合**:
```python
# ✅ 良い例: Service層でトランザクション管理
# CRUD層
async def create(db: AsyncSession, obj_in: UserCreate) -> User:
    user = User(**obj_in.dict())
    db.add(user)
    await db.flush()  # ✅ commitはService層に任せる
    return user

# Service層
async def create_user_with_billing(db: AsyncSession, user_in: UserCreate):
    user = await crud.user.create(db=db, obj_in=user_in)
    billing = await crud.billing.create_for_user(db=db, user_id=user.id)
    await db.commit()  # ✅ 複数操作のトランザクションをService層で管理
    return user
```

---

## チェックコマンド

### API層でのcommit/flush検出

```bash
# API層でcommit/flushを使っている箇所を検出（禁止）
grep -rn "await db.commit()\|await db.flush()" k_back/app/api/v1/endpoints/
```

**期待結果**: 0件（見つかったら修正が必要）

---

### Service層でのcommit漏れ検出

```bash
# Service層でcrud呼び出しがあるがcommitがないファイルを検出
for file in k_back/app/services/*.py; do
  if grep -q "await crud\." "$file" && ! grep -q "await db.commit()" "$file"; then
    echo "⚠️  Commit missing: $file"
  fi
done
```

---

### CRUD層のflush/commit使用状況確認

```bash
# CRUD層でのcommit/flush使用状況を確認
grep -rn "await db.commit()\|await db.flush()" k_back/app/crud/ | \
  grep -v "__pycache__" | \
  awk -F: '{print $1}' | sort | uniq -c
```

---

## よくある違反パターン

### パターン1: API層でのcommit（最も重大）

```python
# ❌ 違反例
@router.post("/users/")
async def create_user(user_in: UserCreate, db: AsyncSession = Depends(get_db)):
    user = User(**user_in.dict())
    db.add(user)
    await db.commit()  # ❌ API層でcommit
    return user
```

**問題点**:
- ビジネスロジックがAPI層に漏れる
- テストが困難
- トランザクション管理が分散

**修正方法**:
1. Service層に `create_user()` メソッドを作成
2. API層はService層を呼ぶだけに変更

---

### パターン2: Service層でのcommit漏れ

```python
# ❌ 違反例
async def create_user_and_send_email(db: AsyncSession, user_in: UserCreate):
    user = await crud.user.create(db=db, obj_in=user_in)
    await send_welcome_email(user.email)
    # ❌ commitがない → userがDBに保存されない
    return user
```

**問題点**:
- トランザクションが完了しない
- ロールバックができない
- データ整合性が保証されない

**修正方法**:
```python
# ✅ 修正後
async def create_user_and_send_email(db: AsyncSession, user_in: UserCreate):
    user = await crud.user.create(db=db, obj_in=user_in)
    await db.commit()  # ✅ commitを追加
    await db.refresh(user)
    await send_welcome_email(user.email)
    return user
```

---

### パターン3: flush()せずにIDを参照

```python
# ❌ 違反例
async def create_with_relation(db: AsyncSession, obj_in: UserCreate):
    user = User(**obj_in.dict())
    db.add(user)
    # ❌ flushしないとuser.idが取得できない
    profile = Profile(user_id=user.id)  # user.id is None!
    db.add(profile)
    await db.commit()
```

**修正方法**:
```python
# ✅ 修正後
async def create_with_relation(db: AsyncSession, obj_in: UserCreate):
    user = User(**obj_in.dict())
    db.add(user)
    await db.flush()  # ✅ IDを取得

    profile = Profile(user_id=user.id)  # ✅ user.idが利用可能
    db.add(profile)
    await db.commit()
```

---

## チェックリスト

- [ ] API層に `await db.commit()` または `await db.flush()` が存在しないか？
- [ ] Service層で複数のCRUD操作後に `await db.commit()` があるか？
- [ ] CRUD層で生成されたIDを使う場合、`await db.flush()` があるか？
- [ ] エラー発生時に適切にロールバックされるか？
- [ ] トランザクション境界が明確か？

---

## 修正優先度

| 優先度 | 違反パターン | 影響度 | 修正難易度 |
|-------|------------|-------|----------|
| 🔴 **最高** | API層でのcommit | データ整合性・アーキテクチャ崩壊 | 中 |
| 🟠 **高** | Service層でのcommit漏れ | データ未保存・トランザクション不完全 | 低 |
| 🟡 **中** | flush()せずにID参照 | NoneTypeエラー | 低 |
| 🟢 **低** | 不要なflush() | パフォーマンス低下（軽微） | 低 |

---

## 参考資料

- `/.claude/CLAUDE.md` - 4層アーキテクチャガイドライン
- `/.claude/rules/architecture.md` - アーキテクチャルール詳細
- `/.claude/rules/sqlalchemy-best-practices.md` - SQLAlchemy使用ガイド

---

**更新日**: 2026-02-18
**メンテナー**: Claude Sonnet 4.5

---
---

# Skill: トランザクション境界管理ルール

**スキルID**: `transaction-boundary`
**カテゴリ**: データ整合性 / トランザクション管理
**作成日**: 2026-02-18

---

## 目的

トランザクション境界を適切に設定し、データ整合性を保証するための原則とパターンを定義する。

---

## トランザクション境界の基本原則

### 1. アトミック性（Atomicity）の保証

**原則**: 関連する複数の操作は、**全て成功** or **全て失敗** であるべき

**❌ 悪い例: トランザクション境界が分散**

```python
# ❌ 注文作成と在庫減少が別トランザクション
async def create_order(db: AsyncSession, order_in: OrderCreate):
    # トランザクション1: 注文作成
    order = Order(**order_in.dict())
    db.add(order)
    await db.commit()  # ❌ ここでcommit

    # トランザクション2: 在庫減少
    stock = await crud.stock.get(db=db, product_id=order.product_id)
    stock.quantity -= order.quantity
    await db.commit()  # ❌ 別のcommit

    # 問題: 2つ目のcommitが失敗 → 注文だけ作成され、在庫は減らない
```

**✅ 良い例: 1つのトランザクション**

```python
async def create_order(db: AsyncSession, order_in: OrderCreate):
    try:
        # 全ての操作を1つのトランザクション内で実行
        order = Order(**order_in.dict())
        db.add(order)

        stock = await crud.stock.get(db=db, product_id=order.product_id)
        if stock.quantity < order.quantity:
            raise InsufficientStockError()
        stock.quantity -= order.quantity

        # 全て成功したらcommit
        await db.commit()

    except Exception as e:
        # エラー時は全てロールバック
        await db.rollback()
        raise
```

---

### 2. 外部API呼び出しとトランザクション境界

**原則**: 外部API呼び出しは、**commitの前** または **commitの後** に行う

#### パターンA: 外部API呼び出し前にcommit（推奨）

```python
async def create_order_with_payment(db: AsyncSession, order_in: OrderCreate):
    try:
        # 1. DB操作を全て実行
        order = await crud.order.create(db=db, obj_in=order_in)
        await crud.stock.decrease(db=db, product_id=order.product_id, quantity=order.quantity)

        # 2. commitする前に外部API呼び出し
        payment_result = await stripe_client.charge(
            amount=order.total,
            idempotency_key=f"order_{order.id}"
        )

        # 3. 外部APIが成功したらcommit
        await crud.payment.create(db=db, order_id=order.id, payment_id=payment_result.id)
        await db.commit()

    except StripeError as e:
        # 外部API失敗 → DB操作は自動ロールバック
        await db.rollback()
        raise PaymentFailedError()
```

**メリット**:
- 外部API失敗 → DB操作も自動ロールバック
- データ整合性が保証される

---

#### パターンB: commit後に外部API呼び出し（非推奨）

```python
async def create_order_with_notification(db: AsyncSession, order_in: OrderCreate):
    # 1. DB操作をcommit
    order = await crud.order.create(db=db, obj_in=order_in)
    await db.commit()

    # 2. commit後にメール送信（外部API）
    try:
        await send_order_confirmation_email(order.email)
    except EmailError as e:
        # ⚠️ 注意: 既にcommit済みなので、ロールバック不可
        # 代替手段: エラーログ記録、リトライキューに追加
        logger.error(f"Email failed for order {order.id}: {e}")
        await retry_queue.add(task="send_email", order_id=order.id)
```

**使い分け**:
- 決済処理など**失敗したらDB操作も取り消したい** → パターンA
- メール送信など**失敗してもDB操作は残したい** → パターンB

---

### 3. ネストしたトランザクションの禁止

**原則**: トランザクションをネストさせない（savepoint使用は例外）

**❌ 悪い例: ネストしたcommit**

```python
async def outer_transaction(db: AsyncSession):
    user = User(name="John")
    db.add(user)
    await db.commit()  # ❌ 外側のcommit

    # 内側の関数を呼ぶ
    await inner_transaction(db, user.id)

async def inner_transaction(db: AsyncSession, user_id: UUID):
    profile = Profile(user_id=user_id)
    db.add(profile)
    await db.commit()  # ❌ 内側のcommit
```

**問題点**:
- トランザクション境界が不明確
- inner_transactionが失敗 → userは既にcommit済み（ロールバック不可）

**✅ 良い例: 1つのトランザクション**

```python
async def create_user_with_profile(db: AsyncSession):
    try:
        user = await crud.user.create(db=db, obj_in=user_data)
        profile = await crud.profile.create(db=db, user_id=user.id, obj_in=profile_data)

        # 全ての操作が成功したら1回だけcommit
        await db.commit()

    except Exception as e:
        await db.rollback()
        raise
```

---

### 4. トランザクション境界のスコープ

**原則**: トランザクション境界は**ビジネスロジックの単位**で設定

| ビジネスロジック | トランザクション境界 | 例 |
|---------------|------------------|-----|
| **単一CRUD操作** | CRUD層でcommit可 | `crud.user.create()` |
| **複数モデルの作成** | Service層でcommit | User + Billing + AuditLog |
| **外部API + DB操作** | Service層でcommit | Stripe決済 + Payment記録 |
| **バッチ処理** | バッチ単位でcommit | 1000件ごとにcommit |

---

### 5. エラーハンドリングとロールバック

**原則**: 例外発生時は必ず `rollback()` を実行

**✅ 基本パターン**

```python
async def service_method(db: AsyncSession, data_in: DataCreate):
    try:
        # ビジネスロジック
        result = await crud.some_model.create(db=db, obj_in=data_in)
        await db.commit()
        return result

    except Exception as e:
        # エラー時は必ずロールバック
        await db.rollback()
        logger.error(f"Transaction failed: {e}")
        raise
```

---

### 6. 長時間トランザクションの回避

**原則**: トランザクション時間は**最小限**に抑える

**❌ 悪い例: 長時間トランザクション**

```python
async def process_orders(db: AsyncSession):
    # トランザクション開始
    orders = await crud.order.get_pending(db=db)

    for order in orders:  # 1000件のループ
        # 外部API呼び出し（1件あたり1秒）
        await external_api.process(order.id)  # ❌ トランザクション中に外部API

        order.status = "processed"

    await db.commit()  # ❌ 1000秒後にcommit（ロック時間が長すぎる）
```

**✅ 良い例: トランザクション時間を最小化**

```python
async def process_orders(db: AsyncSession):
    orders = await crud.order.get_pending(db=db)

    for order in orders:
        # 外部API呼び出し（トランザクション外）
        result = await external_api.process(order.id)

        # 短いトランザクションでステータス更新
        try:
            order.status = "processed"
            await db.commit()  # ✅ 各注文ごとにcommit（短時間）
        except Exception as e:
            await db.rollback()
            logger.error(f"Failed to update order {order.id}")
```

---

## チェックコマンド

### 複数commitの検出

```bash
# 1つの関数内に複数のcommitがある箇所を検出
for file in k_back/app/services/*.py k_back/app/api/v1/endpoints/*.py; do
  count=$(grep -c "await db.commit()" "$file" 2>/dev/null || echo 0)
  if [ "$count" -gt 1 ]; then
    echo "⚠️  Multiple commits in $file: $count commits"
  fi
done
```

### try-except-rollbackパターンの欠如検出

```bash
# commitがあるがrollbackがないファイルを検出
for file in k_back/app/services/*.py; do
  if grep -q "await db.commit()" "$file" && ! grep -q "await db.rollback()" "$file"; then
    echo "⚠️  Missing rollback in $file"
  fi
done
```

---

## トランザクション境界の判断フローチャート

```
操作は1つのモデルのみ？
  ├─ Yes → CRUD層でcommit可
  └─ No → Service層でcommit

外部API呼び出しがある？
  ├─ Yes → 外部API失敗時にロールバックしたい？
  │         ├─ Yes → commit前に外部API呼び出し
  │         └─ No  → commit後に外部API呼び出し
  └─ No → 通常のcommit

エラー発生の可能性がある？
  ├─ Yes → try-except-rollbackパターン必須
  └─ No → 単純なcommit
```

---

**更新日**: 2026-02-18
**メンテナー**: Claude Sonnet 4.5

---
---

# Skill: 保守性担保ルール

**スキルID**: `maintainability-rules`
**カテゴリ**: コード品質 / 保守性
**作成日**: 2026-02-18

---

## 目的

長期的な保守性を担保するためのコーディングルールとベストプラクティスを定義する。

---

## 1. DRY原則（Don't Repeat Yourself）

### 原則: ロジックの重複を排除する

**❌ 悪い例: ロジックが3箇所に重複**

```python
# app/api/v1/endpoints/users.py
@router.post("/users/")
async def create_user(...):
    user = User(...)
    db.add(user)
    await db.flush()

    # Billing作成ロジック（重複1）
    billing = Billing(user_id=user.id, plan="free", trial_days=180)
    db.add(billing)
    await db.commit()

# app/api/v1/endpoints/oauth.py
@router.post("/oauth/signup")
async def oauth_signup(...):
    user = User(...)
    db.add(user)
    await db.flush()

    # Billing作成ロジック（重複2）
    billing = Billing(user_id=user.id, plan="free", trial_days=180)
    db.add(billing)
    await db.commit()

# app/api/v1/endpoints/admin.py
@router.post("/admin/users/bulk")
async def bulk_create(...):
    for user_data in users:
        user = User(...)
        db.add(user)
        await db.flush()

        # Billing作成ロジック（重複3）
        billing = Billing(user_id=user.id, plan="free", trial_days=180)
        db.add(billing)
    await db.commit()
```

**問題点**:
- trial_daysを変更したい → 3箇所修正が必要
- 修正漏れのリスク
- テストも3箇所必要

---

**✅ 良い例: ロジックを1箇所に集約**

```python
# app/services/user_service.py
async def create_user_with_billing(
    db: AsyncSession,
    user_in: UserCreate,
    trial_days: int = 180
) -> User:
    """ユーザー + Billingを作成する（DRY原則）"""
    user = await crud.user.create(db=db, obj_in=user_in)
    billing = await crud.billing.create_for_user(
        db=db,
        user_id=user.id,
        plan="free",
        trial_days=trial_days
    )
    await db.commit()
    return user

# 各エンドポイントはService層を呼ぶだけ
@router.post("/users/")
async def create_user(...):
    return await user_service.create_user_with_billing(db=db, user_in=user_in)

@router.post("/oauth/signup")
async def oauth_signup(...):
    return await user_service.create_user_with_billing(db=db, user_in=user_in)

@router.post("/admin/users/bulk")
async def bulk_create(...):
    for user_data in users:
        await user_service.create_user_with_billing(db=db, user_in=user_data)
```

**メリット**:
- ロジックが1箇所に集約
- 修正は1箇所だけ
- テストも1箇所だけ

---

## 2. 単一責任原則（SRP）

### 原則: 1つの関数/クラスは1つの責務のみ

**❌ 悪い例: 複数の責務を持つ関数**

```python
async def create_order(db: AsyncSession, order_in: OrderCreate):
    # 責務1: バリデーション
    if order_in.quantity <= 0:
        raise ValueError("数量は1以上")

    # 責務2: 在庫チェック
    stock = await crud.stock.get(db=db, product_id=order_in.product_id)
    if stock.quantity < order_in.quantity:
        raise InsufficientStockError()

    # 責務3: 注文作成
    order = Order(**order_in.dict())
    db.add(order)

    # 責務4: 在庫減少
    stock.quantity -= order_in.quantity

    # 責務5: 決済処理
    payment = await stripe.charge(amount=order.total)

    # 責務6: メール送信
    await send_order_email(order.customer_email)

    # 責務7: DB commit
    await db.commit()
```

**問題点**:
- 1つの関数が7つの責務を持つ
- テストが困難
- 修正時の影響範囲が不明確

---

**✅ 良い例: 責務を分離**

```python
# Service層: 各責務を別関数に分離
async def validate_order(order_in: OrderCreate):
    """バリデーション"""
    if order_in.quantity <= 0:
        raise ValueError("数量は1以上")

async def check_stock(db: AsyncSession, product_id: UUID, quantity: int):
    """在庫チェック"""
    stock = await crud.stock.get(db=db, product_id=product_id)
    if stock.quantity < quantity:
        raise InsufficientStockError()

async def create_order_with_payment(db: AsyncSession, order_in: OrderCreate):
    """注文作成（メイン処理）"""
    # 1. バリデーション
    await validate_order(order_in)

    # 2. 在庫チェック
    await check_stock(db, order_in.product_id, order_in.quantity)

    # 3. 注文作成
    order = await crud.order.create(db=db, obj_in=order_in)

    # 4. 在庫減少
    await crud.stock.decrease(db=db, product_id=order_in.product_id, quantity=order_in.quantity)

    # 5. 決済処理
    payment = await process_payment(order.total)

    # 6. commit
    await db.commit()

    # 7. メール送信（commit後）
    await send_order_email(order.customer_email)

    return order
```

**メリット**:
- 各関数の責務が明確
- テストが容易
- 再利用性が高い

---

## 3. 命名規則の一貫性

### 原則: 一貫性のある命名で可読性を向上

**✅ 命名パターン**

| 用途 | パターン | 例 |
|-----|---------|-----|
| CRUD操作 | `create_*`, `get_*`, `update_*`, `delete_*` | `create_user()`, `get_by_id()` |
| Service層 | `動詞_名詞` | `create_user_with_billing()` |
| バリデーション | `validate_*` | `validate_email()` |
| チェック関数 | `check_*` | `check_permission()` |
| 真偽値 | `is_*`, `has_*`, `can_*` | `is_active`, `has_permission` |
| 非同期関数 | `async def` | `async def get_user()` |

---

**❌ 悪い例: 一貫性のない命名**

```python
async def make_user(...)        # ❌ makeは非標準
async def fetch_user(...)       # ❌ fetchとgetが混在
async def user_update(...)      # ❌ 名詞_動詞の順序
async def validateEmail(...)    # ❌ camelCase（Pythonではsnake_case）
async def activeUser(...)       # ❌ 真偽値なのにis_がない
```

**✅ 良い例: 一貫性のある命名**

```python
async def create_user(...)      # ✅ CRUD標準パターン
async def get_user(...)         # ✅ CRUD標準パターン
async def update_user(...)      # ✅ 動詞_名詞
async def validate_email(...)   # ✅ snake_case
async def is_active_user(...)   # ✅ 真偽値にis_
```

---

## 4. マジックナンバーの排除

### 原則: 定数は名前付き定数として定義

**❌ 悪い例: マジックナンバー**

```python
async def check_trial_expired(billing: Billing) -> bool:
    return (datetime.now(timezone.utc) - billing.created_at).days > 180  # ❌ 180は何？

async def get_max_users(plan: str) -> int:
    if plan == "free":
        return 5  # ❌ 5は何？
    elif plan == "active":
        return 100  # ❌ 100は何？
```

---

**✅ 良い例: 名前付き定数**

```python
# app/core/constants.py
TRIAL_DAYS = 180
MAX_USERS_FREE = 5
MAX_USERS_ACTIVE = 100

# app/services/billing_service.py
async def check_trial_expired(billing: Billing) -> bool:
    return (datetime.now(timezone.utc) - billing.created_at).days > TRIAL_DAYS

async def get_max_users(plan: str) -> int:
    if plan == "free":
        return MAX_USERS_FREE
    elif plan == "active":
        return MAX_USERS_ACTIVE
```

**メリット**:
- 定数の意味が明確
- 変更時は1箇所だけ修正
- テストで定数を上書き可能

---

## 5. エラーメッセージの日本語化

### 原則: ユーザー向けメッセージは日本語

**❌ 悪い例: 英語エラーメッセージ**

```python
if not user:
    raise HTTPException(status_code=404, detail="User not found")  # ❌ 英語

if billing.billing_status == "past_due":
    raise HTTPException(status_code=403, detail="Payment overdue")  # ❌ 英語
```

---

**✅ 良い例: 日本語エラーメッセージ**

```python
# app/messages/ja.py
USER_NOT_FOUND = "ユーザーが見つかりません"
PAYMENT_OVERDUE = "お支払いが滞っています。課金情報を更新してください。"

# app/api/v1/endpoints/users.py
from app.messages import ja

if not user:
    raise HTTPException(status_code=404, detail=ja.USER_NOT_FOUND)

if billing.billing_status == "past_due":
    raise HTTPException(status_code=403, detail=ja.PAYMENT_OVERDUE)
```

**メリット**:
- エンドユーザーが理解できる
- メッセージを一元管理
- 多言語対応が容易

---

## 6. コメントとDocstring

### 原則: コメントは「なぜ」を説明、Docstringは「何を」を説明

**❌ 悪い例: 不要なコメント**

```python
# ユーザーIDを取得  ← ❌ コードを読めば分かる
user_id = current_user.id

# iを1増やす  ← ❌ 自明
i += 1
```

---

**✅ 良い例: 意味のあるコメント**

```python
# Stripe APIは冪等性キーとして order_id を使用（重複決済防止のため）
payment = await stripe.charge(
    amount=order.total,
    idempotency_key=f"order_{order.id}"
)

# Phase 4.1実装: N+1問題解決のためバッチクエリを使用
alerts_by_office = await get_deadline_alerts_batch(db=db, office_ids=office_ids)
```

---

**✅ Docstring（関数の仕様を記述）**

```python
async def create_user_with_billing(
    db: AsyncSession,
    user_in: UserCreate,
    trial_days: int = 180
) -> User:
    """
    ユーザーとBillingレコードを作成する

    Args:
        db: データベースセッション
        user_in: ユーザー作成データ
        trial_days: トライアル期間（日数）

    Returns:
        作成されたユーザー

    Raises:
        EmailAlreadyExistsError: メールアドレスが既に使用されている場合
    """
```

---

## 7. 早期リターン（Early Return）

### 原則: ネストを減らすため、早期リターンを使う

**❌ 悪い例: 深いネスト**

```python
async def get_user_data(db: AsyncSession, user_id: UUID):
    user = await crud.user.get(db=db, id=user_id)
    if user:
        if user.is_active:
            if user.billing:
                if user.billing.billing_status == "active":
                    return user.data
                else:
                    raise PaymentRequiredError()
            else:
                raise BillingNotFoundError()
        else:
            raise UserInactiveError()
    else:
        raise UserNotFoundError()
```

---

**✅ 良い例: 早期リターン**

```python
async def get_user_data(db: AsyncSession, user_id: UUID):
    # エラーケースを先にチェック
    user = await crud.user.get(db=db, id=user_id)
    if not user:
        raise UserNotFoundError()

    if not user.is_active:
        raise UserInactiveError()

    if not user.billing:
        raise BillingNotFoundError()

    if user.billing.billing_status != "active":
        raise PaymentRequiredError()

    # 正常系は最後
    return user.data
```

**メリット**:
- ネストが浅い
- 可読性が高い
- エラーケースが明確

---

## 8. このアプリ固有の保守性リファクタリング方針

### 原則: 既存挙動を固定してから、小さな責務単位で分離する

このリポジトリでは、認証、利用者/支援計画、申請/通知、Google Calendar、課金の変更頻度が高い。大規模な一括置換ではなく、TDDで現行挙動を固定し、公開API・画面表示・DBスキーマを変えない範囲から小さく分離する。

優先順:

1. 認証Cookie設定の共通化
2. debugログ/print/console.logの整理
3. 申請系通知/承認フローの共通化
4. 課金状態遷移ロジックの集約
5. Google Calendar自動同期の縮退方針整理と代替機能の境界分離
6. 巨大frontendコンポーネントのhook/表示分割
7. `get_current_user()` の用途別依存分割
8. DB変更運用ルールの明文化

---

### 8.1 認証Cookie設定は共通関数へ寄せる

対象:

- `k_back/app/api/v1/endpoints/auths.py`
- `login_for_access_token`
- `refresh_access_token`
- `verify_mfa_for_login`
- `verify_mfa_first_time`
- `logout`

ルール:

- `COOKIE_DOMAIN` / `COOKIE_SAMESITE` / `secure` / `samesite` / `path` / `max_age` の組み立てをendpoint内に重複させない。
- `app/core/auth_cookie.py` などに `build_access_cookie_options()` / `build_delete_access_cookie_options()` を作る。
- endpointは `response.set_cookie(**options)` / `response.delete_cookie(**options)` に寄せる。
- 通常ログイン、MFA、初回MFA、refresh、logoutで同じ生成ロジックを使う。

TDD候補:

- [ ] local環境の通常ログインCookie optionが現行通りである。
- [ ] production環境の通常ログインCookie optionが現行通りである。
- [ ] MFAログインCookie optionが通常ログインと同じ共通関数を使う。
- [ ] logoutのdelete cookie optionがset cookieと同じdomain/path/samesiteを使う。

---

### 8.2 巨大Service/Componentは行数削減目的ではなく責務境界で分割する

対象例:

- `k_back/app/services/billing_service.py`
- `k_back/app/services/employee_action_service.py`
- `k_back/app/services/welfare_recipient_service.py`
- `k_back/app/services/calendar_service.py`
- `k_front/components/protected/admin/AdminMenu.tsx`
- `k_front/components/protected/dashboard/Dashboard.tsx`
- `k_front/components/protected/recipients/RecipientRegistrationForm.tsx`
- `k_front/components/protected/recipients/RecipientEditForm.tsx`

ルール:

- backendは「判定」「DB更新」「通知作成」「外部API呼び出し」「監査ログ」を分ける。
- frontendは「コンテナ」「表示コンポーネント」「フォーム状態」「API adapter」「権限判定」を分ける。
- ファイル分割だけを目的にしない。テスト可能な責務単位で抽出する。
- 抽出後も既存の公開API、レスポンス、画面文言、UI表示を変えない。

受け入れ要件:

- [ ] 1000行超のファイルについて、分割単位と優先順位が決まっている。
- [ ] 抽出後も既存の公開API/画面表示は変わらない。
- [ ] 主要分岐に単体テストまたはコンポーネントテストがある。

---

### 8.3 申請系通知/承認フローは共通化する

対象:

- `k_back/app/services/role_change_service.py`
- `k_back/app/services/employee_action_service.py`
- `k_back/app/crud/crud_notice.py`

ルール:

- 通知作成、保持上限削除、監査ログ作成の共通処理を1箇所に集約する。
- role change / employee action の業務差分は無理に継承で隠さず、明示的な差分として残す。
- 承認/却下フローは共通helperまたはユースケース関数へ寄せる。
- 既存通知文言、通知タイプ、既読/保持上限挙動はテストで固定してから変更する。

TDD候補:

- [ ] role change承認時の通知作成が共通helper経由で行われる。
- [ ] employee action承認時の通知作成が共通helper経由で行われる。
- [ ] 既存通知文言と通知タイプは変わらない。

---

### 8.4 ログ出力は運用可能な形に整理する

対象例:

- backend endpoint内の `print()`
- backendの過剰な `logger.info()`
- frontend production対象コードの無条件 `console.log`

ルール:

- backend本番コードでは `print()` を使わない。`logger.debug/info/warning/error` に統一する。
- 成功パスの詳細ログは原則 `debug` に落とす。
- frontendは必要に応じて `debugLog()` のようなwrapperに寄せ、productionでは業務データを出さない。
- トークン、メールアドレス、個人名、内部ID、支援計画本文、ファイル名、Stripe key、Google credential はログに出さない。
- 調査に必要な失敗イベントは、個人情報を含めず `warning` / `error` で残す。

TDD/確認候補:

- [ ] backend endpoint内に `print(` が残っていない。
- [ ] frontend production対象コードに無条件の `console.log` が残っていない。
- [ ] トークン、メール、個人名、支援計画本文、ファイル名をログ出力しない。

---

### 8.5 Google Calendar連携は縮退・代替機能化を前提に境界分離する

対象:

- `k_back/app/services/calendar_service.py`
- `k_back/app/services/welfare_recipient_service.py`
- `md_files_design_note/task/todo/refactor/google_calendar/google_calendar.md`

ルール:

- Google Calendar自動同期の恒久維持を前提にしない。
- 支援計画作成/削除の成功条件をGoogle Calendar API成功に依存させない。
- 「期限イベント生成」と「Googleへ同期する副作用」を分ける。
- `calendar_events` はGoogle同期専用ではなく、アプリ内カレンダー/`.ics` 用の期限イベント台帳として扱える設計に寄せる。
- Google自動同期は既存利用者向け互換機能として分離し、新規導線はアプリ内カレンダーまたは `.ics` を優先する。
- Google同期失敗は本体処理失敗ではなく、再試行可能な副作用として扱う。

受け入れ要件:

- [ ] 支援計画作成/削除の成功条件がGoogle Calendar API成功に依存しない。
- [ ] Google未接続でもアプリ内カレンダー/`.ics` 用の期限イベントを生成できる。
- [ ] Google自動同期は既存利用者向けの互換機能として分離される。
- [ ] 新規導線はサービスアカウント方式ではなく、アプリ内カレンダーまたは `.ics` を優先する。

---

### 8.6 課金状態遷移はWebhook/バッチ/APIから分離する

対象:

- `k_back/app/services/billing_service.py`
- `k_back/app/tasks/billing_check.py`
- `k_back/app/api/v1/endpoints/billing.py`
- `k_front/components/billing`

ルール:

- `trial_expired` / `payment_failed` / `canceling` / `canceled` の状態遷移条件を複数箇所に散らさない。
- `BillingStatusTransitionService` のような小さな単位に状態決定ロジックを集約する。
- Webhook/バッチ/APIは「イベント入力」として扱い、同じ遷移関数を呼ぶ。
- frontend表示とbackend制限の対応表をテストまたはドキュメントで固定する。
- Stripe Webhook順序、Test Clock、バッチ補正はテストで現行挙動を固定してから変更する。

受け入れ要件:

- [ ] 状態遷移の判定ロジックが1箇所に集約される。
- [ ] Webhook/バッチ/APIで同じ遷移関数を使う。
- [ ] frontend表示とbackend制限の対応表がテストまたはドキュメント化される。

---

### 8.7 frontendのAPI呼び出しと画面状態管理を分離する

対象例:

- `k_front/components/protected/dashboard/Dashboard.tsx`
- `k_front/components/protected/recipients/RecipientRegistrationForm.tsx`
- `k_front/components/protected/recipients/RecipientEditForm.tsx`
- `k_front/components/protected/support_plan/SupportPlan.tsx`
- `k_front/app/(protected)/pdf-list/page.tsx`

ルール:

- APIレスポンス変換、バリデーション、表示状態、権限判定を同じコンポーネントに混在させない。
- `hooks/useDashboardData`、`hooks/useRecipientForm` など画面単位のhookへAPI/状態管理を分離する。
- 表示コンポーネントはpropsを受けて描画に集中させる。
- 権限判定は `lib/permissions` などの共通関数へ寄せる。

受け入れ要件:

- [ ] 主要画面でAPI取得と表示コンポーネントが分離される。
- [ ] 権限判定が画面内のインライン条件から共通関数へ移る。
- [ ] hook単位のテストが追加できる。

---

### 8.8 `get_current_user()` は用途別依存へ分ける

対象:

- `k_back/app/api/deps.py`
- `k_back/app/api/v1/endpoints/*.py`

ルール:

- 軽量な認証確認だけでよいAPIと、Office/role/associationまで必要なAPIで同じ依存を使い続けない。
- `get_current_user_minimal`、`get_current_user_with_office`、`require_owner_or_manager` のように用途別に分ける。
- endpointの権限要件が依存名から読めるようにする。
- 既存APIのレスポンスは変えない。

受け入れ要件:

- [ ] 軽量依存とOffice必須依存が分かれる。
- [ ] endpointの権限要件が依存名から読める。
- [ ] 既存APIのレスポンスは変えない。

---

### 8.9 TODO/仮実装は分類し、利用者導線から放置しない

ルール:

- TODOを「仕様未確定」「未実装」「削除予定」に分類する。
- 利用者に見える導線の仮実装はissueまたはタスクに紐づける。
- 仮データ、仮待機、未接続UIは利用者向け画面に残す前にタスク化する。

受け入れ要件:

- [ ] TODO一覧がmd化される。
- [ ] ユーザー導線にある仮実装はissueまたはタスクに紐づく。

---

### 8.10 DB変更はAlembic migrationを正とし、手動SQLは確認用・緊急用に限定する

このプロジェクトでは、DB変更の本番反映はAlembic migrationを正とする。通常CDでは `alembic upgrade head` により未適用revisionを反映する。手動SQLは確認用、調査用、緊急対応用として扱い、通常の本番反映手段にしない。

ルール:

- DB定義変更では、Alembic migrationを `k_back/migrations/versions/` に作成する。
- 手動SQLだけでDB変更を完了扱いにしない。
- 手動SQLを使う場合は、確認用SQL、影響範囲確認、緊急rollback手順として位置づける。
- enum値追加、check constraint変更、カラム追加、index追加、既存データ更新では、migrationと実DB schemaの整合性を確認する。
- `CREATE INDEX CONCURRENTLY` はトランザクション内で実行できないため、Alembicで扱う場合は専用設計にする。
- baseline合わせの `alembic stamp` は通常CDでは実行せず、対象DB・revision・確認結果をmdに記録した管理操作として扱う。

受け入れ要件:

- [ ] DB変更方針のmdがある。
- [ ] Alembic migrationが本番反映の正になっている。
- [ ] 手動SQLが確認用・緊急用に限定されている。
- [ ] PR説明またはタスクリストにmigration適用と確認項目がある。

---

## チェックコマンド

### DRY違反検出（重複コード）

```bash
# 同じ文字列が複数ファイルに出現する箇所を検出
rg "Billing\(user_id=" k_back/app/ -l | wc -l
```

### マジックナンバー検出

```bash
# 数値リテラルを検出（0, 1を除く）
rg '\b[2-9]\d*\b' k_back/app/services/ --type py | grep -v "^#"
```

### 英語エラーメッセージ検出

```bash
# HTTPExceptionに英語メッセージがある箇所を検出
rg 'HTTPException.*detail="[A-Za-z]' k_back/app/api/ --type py
```

### backend print検出

```bash
rg 'print\(' k_back/app --type py
```

### frontend console.log検出

```bash
rg 'console\.log' k_front/app k_front/components k_front/lib --glob '*.ts' --glob '*.tsx'
```

### 認証Cookie重複検出

```bash
rg 'set_cookie|delete_cookie|COOKIE_DOMAIN|COOKIE_SAMESITE|samesite|secure' k_back/app/api/v1/endpoints/auths.py
```

### 巨大ファイル候補確認

```bash
rg --files k_back/app/services k_front/components k_front/app | xargs wc -l | sort -nr | head -30
```

---

## 保守性チェックリスト

- [ ] ロジックの重複がないか？（DRY原則）
- [ ] 各関数の責務は単一か？（SRP原則）
- [ ] 命名規則は一貫しているか？
- [ ] マジックナンバーは定数化されているか？
- [ ] エラーメッセージは日本語か？
- [ ] Docstringは記述されているか？
- [ ] 深いネストはないか？（早期リターン）
- [ ] 既存挙動を固定するテストを先に追加しているか？
- [ ] 認証Cookie option生成がendpoint内に重複していないか？
- [ ] 1000行超ファイルは責務境界と分割優先度が整理されているか？
- [ ] backend endpoint内に `print()` が残っていないか？
- [ ] frontend production対象コードに業務データの無条件 `console.log` が残っていないか？
- [ ] 個人情報、トークン、ファイル名、Stripe/Google credentialをログに出していないか？
- [ ] 申請系の通知作成、保持上限削除、監査ログ作成が重複していないか？
- [ ] Google Calendar API失敗が支援計画作成/削除の成功条件を壊していないか？
- [ ] Billing状態遷移がWebhook/バッチ/APIに分散していないか？
- [ ] frontendのAPI取得、状態管理、表示コンポーネント、権限判定が分離されているか？
- [ ] `get_current_user()` 依存はAPI用途に対して過剰ではないか？
- [ ] DB変更ではAlembic migrationが正となり、確認SQL・緊急手順の役割が明確か？

---

**更新日**: 2026-07-01
**メンテナー**: Claude Sonnet 4.5 / Codex
