# Pull Request Best Practices - けいかくん

## 面接想定質問

> **「PRを出すときに気をつけていることは？」**

PRを出す際は、コードレビュアーの負担を減らし、品質を担保し、チーム全体の開発効率を高めるために、以下の点に特に注意しています。

---

## 1. PR前の必須チェックリスト

### 1.1 テスト実行とカバレッジ確認

**けいかくん**では、**155個のテストファイル**に**1,787個のテスト関数**が存在します。PRを出す前に必ず全テストを実行し、パスすることを確認します。

```bash
# バックエンドテスト実行（全1,787テスト）
docker exec keikakun_app-backend-1 pytest tests/ -v

# テスト結果の確認ポイント
# ✅ All tests passed
# ✅ No deprecation warnings
# ✅ No security warnings
# ✅ Database cleanup logs displayed correctly (-s flag)
```

**テスト実行時の注意点**:
- `pytest.ini`の設定により、`-v --tb=short -s`フラグが自動適用されます
- `-s`フラグでデータベースクリーンアップログが表示され、テスト後のDB状態を確認できます
- `log_cli_level = WARNING`により、重要なログのみが表示されます
- GitHub Actionsでも同じテストが実行されるため、ローカルで全テストがパスすることが必須です

**なぜ重要か**:
- テストファイル数: 155ファイル
- テスト関数数: 1,787関数
- 既存機能のリグレッション（退行）を防ぐため、全テストのパスは必須条件です
- 特にセキュリティテスト（SQL injection、XSS、認可チェック）の失敗は本番環境で重大な脆弱性を引き起こします

### 1.2 Import規則の遵守

**CRITICAL**: 循環importを防ぐため、CRUD層のimportルールを厳守します。

**✅ 正しいimport**:
```python
from app import crud

# Usage
billing = await crud.billing.get_by_office_id(db=db, office_id=office_id)
staff = await crud.staff.get(db=db, id=staff_id)
```

**❌ 絶対にやってはいけないimport**:
```python
# ❌ Wrong - causes circular imports
from app.crud.crud_billing import crud_billing
from app.crud.crud_staff import CRUDStaff
```

**確認方法**:
```bash
# 禁止されたimportパターンが存在しないか確認
grep -r "from app.crud.crud_" k_back/app --include="*.py" | grep -v "__init__.py"

# 結果が空であることを確認（何も表示されなければOK）
```

**なぜ重要か**:
- 循環importは実行時エラーを引き起こし、アプリケーション全体が起動しなくなります
- `from app import crud`パターンは`app/crud/__init__.py`で集約されており、依存関係を一方向に保ちます

### 1.3 MissingGreenlet エラーの確認

SQLAlchemyの非同期処理で最も頻発するエラーがMissingGreenletエラーです。

**❌ エラーを引き起こすコード**:
```python
# Relationship経由でIDにアクセス（NG）
office_id = billing.office.id  # ❌ MissingGreenlet error!
```

**✅ 正しいコード**:
```python
# Foreign keyカラムに直接アクセス（OK）
office_id = billing.office_id  # ✅ Good
```

**確認方法**:
```bash
# Relationshipを経由したID参照がないか確認
grep -r "\.office\.id\|\.billing\.id\|\.staff\.id" k_back/app --include="*.py"

# 疑わしい箇所があれば、selectinload()の使用を確認
grep -B5 -A5 "\.office\.id" k_back/app/services/*.py
```

**なぜ重要か**:
- 非同期セッションではrelationshipのlazy loadingがデフォルトで禁止されています
- `selectinload()`を使わずにrelationshipにアクセスすると、本番環境で500エラーが発生します

### 1.4 監査ログの実装確認

**全ての状態変更操作**には監査ログ（Audit Log）の記録が必須です。

**必須のログ対象**:
- ✅ 利用者の作成・更新・削除
- ✅ 個別支援計画の作成・更新
- ✅ スタッフ権限の変更
- ✅ 課金ステータスの変更
- ✅ 事業所情報の更新

**実装例**:
```python
# services/support_plan_service.py
async def create_support_plan(
    db: AsyncSession,
    user_id: UUID,
    plan_data: PlanCreate,
    current_staff: Staff
) -> IndividualSupportPlan:
    # 計画を作成
    plan = await crud.individual_support_plan.create(db, obj_in=plan_data)

    # ✅ 監査ログを記録
    await crud.audit_log.create(
        db,
        obj_in=AuditLogCreate(
            staff_id=current_staff.id,
            office_id=current_staff.office_id,
            action="create_support_plan",
            resource_type="individual_support_plan",
            resource_id=plan.id,
            details={"user_id": str(user_id)}
        )
    )

    await db.commit()
    await db.refresh(plan)
    return plan
```

**確認方法**:
```bash
# 新規作成したservice関数で監査ログが記録されているか確認
grep -A20 "async def create_\|async def update_\|async def delete_" k_back/app/services/*.py | grep "audit_log"
```

**なぜ重要か**:
- 福祉事業所では個人情報を扱うため、誰がいつ何を変更したかの記録が法的要件です
- セキュリティインシデント発生時の原因調査に不可欠です
- 監査ログがない変更は、コンプライアンス違反となる可能性があります

### 1.5 言語ルールの確認（日本語コメント・メッセージ）

**CRITICAL**: けいかくんでは、エンドユーザーが日本語話者のため、以下の言語ルールを厳守します。

**日本語で書くべきもの**:
- ✅ コメント: `# 課金ステータスを確認`
- ✅ Docstring: `"""利用者の個別支援計画を取得する"""`
- ✅ エラーメッセージ（user-facing）: `"この操作を行う権限がありません"`
- ✅ ログメッセージ: `logger.info("課金処理が完了しました")`

**英語で書くべきもの**:
- ✅ 変数名・関数名: `get_billing_status()`, `office_id`
- ✅ クラス名: `BillingService`, `UserSchema`

**確認方法**:
```bash
# 英語のエラーメッセージが含まれていないか確認
grep -r "HTTPException" k_back/app --include="*.py" -A2 | grep "detail=" | grep -v "日本語"

# 英語のコメントが含まれていないか確認（一部のファイルを除外）
grep -r "^[[:space:]]*#[[:space:]]*[A-Z]" k_back/app --include="*.py" | grep -v "TODO\|FIXME\|NOTE\|Copyright"
```

**❌ NG例**:
```python
# Get billing status
raise HTTPException(
    status_code=403,
    detail="You don't have permission to access this office's data"
)
```

**✅ OK例**:
```python
# 課金ステータスを確認
raise HTTPException(
    status_code=403,
    detail="この事業所のデータにアクセスする権限がありません"
)
```

**なぜ重要か**:
- エンドユーザー（福祉サービス提供者）は日本語話者です
- 英語のエラーメッセージは、ユーザーが問題を理解できず、サポートコストが増大します
- コードの保守性：日本人開発者がコメントを読んで即座に理解できることが重要です

---

## 2. Migration ファイルの取り扱い

### 2.1 Migration ファイルの基本ルール

**けいかくん**では、**69個のマイグレーションファイル**が存在し、本番環境のデータベーススキーマを管理しています。

```bash
# Migrationファイル数の確認
ls -1 k_back/migrations/versions/*.py | wc -l
# 出力: 69
```

**PRでMigrationを含む場合の必須チェック**:

#### ✅ 1. Migrationファイル名の命名規則

Alembicの自動生成は**タイムスタンプベース**のファイル名を生成します：

```
<revision_id>_<description>.py

例:
a9b0c1d2e3f4_add_notification_preferences_to_staffs.py
b0c1d2e3f4g5_add_threshold_fields_to_notification_preferences.py
```

**確認ポイント**:
- ファイル名に機能の説明が含まれているか
- 英語のスネークケースで記述されているか
- 複数の変更を1つのマイグレーションにまとめすぎていないか

#### ✅ 2. upgrade() と downgrade() の両方を実装

**必須**: 全てのマイグレーションには`upgrade()`と`downgrade()`の両方が必要です。

```python
def upgrade() -> None:
    """Add notification_preferences column to staffs table"""
    op.add_column(
        'staffs',
        sa.Column(
            'notification_preferences',
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=True,
            server_default=sa.text("'{}'::jsonb")
        )
    )

def downgrade() -> None:
    """Remove notification_preferences column from staffs table

    WARNING: This will permanently delete all notification preferences data.
    """
    op.drop_column('staffs', 'notification_preferences')
```

**確認方法**:
```bash
# 新規作成したマイグレーションファイルでupgrade/downgradeを確認
grep -A5 "def upgrade\|def downgrade" k_back/migrations/versions/<your_migration_file>.py
```

**なぜ重要か**:
- `upgrade()`のみでは、デプロイ失敗時にロールバックできません
- 本番環境で問題が発生した際、`downgrade()`で迅速に前の状態に戻せる必要があります

#### ✅ 3. データ損失の警告コメント

データを削除する可能性のある`downgrade()`には、**必ず警告コメント**を記述します。

```python
def downgrade() -> None:
    """Remove push_subscriptions table

    WARNING: This will permanently delete all push subscription data.
    Do NOT run this in production without backing up the data first.
    """
    op.drop_table('push_subscriptions')
```

#### ✅ 4. ENUMタイプの変更には手動マイグレーション

PostgreSQLの`ENUM`型は`ALTER TYPE`の制約があるため、**手動SQLマイグレーション**が必要です。

**例**: `billing_status`に新しい値を追加する場合

```sql
-- manual_migration_add_enum_value.sql
BEGIN;

-- 1. ENUMに新しい値を追加
ALTER TYPE billing_status ADD VALUE 'canceling' AFTER 'past_due';

-- 2. 変更をコミット
COMMIT;
```

**確認方法**:
```bash
# ENUMの変更を含む場合、手動マイグレーションかどうか確認
grep -r "CREATE TYPE\|ALTER TYPE" k_back/migrations/versions/*.py
```

**なぜ重要か**:
- Alembicの`autogenerate`はENUMの変更を正しく検出できません
- 手動で`ALTER TYPE`を実行しないと、アプリケーションコードとDB定義の不整合が発生します

### 2.2 Migration テストの実施

**PRを出す前に、必ずマイグレーションのupgrade/downgradeをテスト環境で実行します。**

```bash
# 1. 現在のリビジョンを確認
docker exec keikakun_app-backend-1 alembic current

# 2. 新しいマイグレーションを適用
docker exec keikakun_app-backend-1 alembic upgrade head

# 3. 正常に適用されたことを確認
docker exec keikakun_app-backend-1 alembic current

# 4. ロールバックテスト（1つ前に戻す）
docker exec keikakun_app-backend-1 alembic downgrade -1

# 5. 再度適用して、冪等性を確認
docker exec keikakun_app-backend-1 alembic upgrade head
```

**確認ポイント**:
- ✅ `upgrade`が正常に完了するか
- ✅ `downgrade`でエラーが発生しないか
- ✅ 再度`upgrade`を実行しても問題ないか（冪等性）
- ✅ テーブルのインデックスが正しく作成されているか
- ✅ Foreign key制約が正しく設定されているか

**なぜ重要か**:
- 本番環境で初めてマイグレーションエラーが発生すると、サービス停止につながります
- ロールバックが失敗すると、データベースが不整合な状態になります

---

## 3. アーキテクチャ遵守の確認

### 3.1 4層アーキテクチャの厳守

**けいかくん**では、以下の4層アーキテクチャを厳守しています：

```
API層 (endpoints/)
  ↓ calls
Services層 (services/)
  ↓ calls
CRUD層 (crud/)
  ↓ accesses
Models層 (models/)
```

**各層の責務違反チェック**:

#### ❌ API層でビジネスロジックを実装していないか

```python
# ❌ NG: API層でビジネスロジック
@router.post("/plans")
async def create_plan(
    db: AsyncSession = Depends(get_db),
    current_staff: Staff = Depends(get_current_staff)
):
    # ❌ API層でビジネスロジックを書いている
    plan = IndividualSupportPlan(...)
    db.add(plan)
    await db.commit()
    return plan
```

```python
# ✅ OK: Services層を呼び出す
@router.post("/plans")
async def create_plan(
    plan_data: PlanCreate,
    db: AsyncSession = Depends(get_db),
    current_staff: Staff = Depends(get_current_staff)
):
    # ✅ Services層に委譲
    plan = await support_plan_service.create_support_plan(
        db=db,
        plan_data=plan_data,
        current_staff=current_staff
    )
    return plan
```

#### ❌ Services層でCRUDを直接書いていないか

```python
# ❌ NG: Services層でSQLを直接書く
async def get_active_plans(db: AsyncSession, office_id: UUID):
    # ❌ CRUD層を経由せずにSQLを書いている
    result = await db.execute(
        select(IndividualSupportPlan).where(
            IndividualSupportPlan.office_id == office_id,
            IndividualSupportPlan.is_active == True
        )
    )
    return result.scalars().all()
```

```python
# ✅ OK: CRUD層を呼び出す
async def get_active_plans(db: AsyncSession, office_id: UUID):
    # ✅ CRUD層に委譲
    return await crud.individual_support_plan.get_active_by_office(
        db=db,
        office_id=office_id
    )
```

**確認方法**:
```bash
# API層でdb.commit()を呼び出していないか確認（禁止）
grep -r "await db.commit()" k_back/app/api --include="*.py"

# Services層でselectやinsertを直接書いていないか確認
grep -r "select(\|insert(\|update(\|delete(" k_back/app/services --include="*.py"
```

**なぜ重要か**:
- 層の責務が混在すると、テストが困難になります
- ビジネスロジックがAPI層に散らばると、再利用性が失われます
- CRUD層を経由せずにDBアクセスすると、N+1問題が発生しやすくなります

### 3.2 selectinload() の使用確認

**一覧取得APIでは必ず`selectinload()`を使用し、N+1問題を防ぎます。**

**❌ Lazy Loadingの罠**:
```python
# ❌ NG: N+1問題を引き起こす
async def get_dashboard_summary(db: AsyncSession):
    recipients = await crud.welfare_recipient.get_multi(db)

    summaries = []
    for r in recipients:
        # ❌ ループ内でrelationshipにアクセス → N+1問題
        latest_cycle = r.support_plan_cycles[0]
        summaries.append({"name": r.full_name, "cycle": latest_cycle})
    return summaries
```

**✅ selectinload()で解決**:
```python
# ✅ OK: selectinload()でEager Loading
async def get_dashboard_summary(db: AsyncSession):
    # ✅ relationshipを明示的にロード
    recipients = await db.execute(
        select(WelfareRecipient)
        .options(selectinload(WelfareRecipient.support_plan_cycles))
    )
    recipients = recipients.scalars().all()

    summaries = []
    for r in recipients:
        # ✅ 既にロード済みなので追加クエリは発生しない
        latest_cycle = r.support_plan_cycles[0]
        summaries.append({"name": r.full_name, "cycle": latest_cycle})
    return summaries
```

**確認方法**:
```bash
# 一覧取得関数でselectinload()を使っているか確認
grep -A10 "get_multi\|get_all" k_back/app/crud/*.py | grep "selectinload"
```

**なぜ重要か**:
- 50人の利用者がいる場合、N+1問題では51回のクエリが発行されます
- `selectinload()`を使えば、常に2回のクエリで済みます
- パフォーマンスの差は最大**25倍**にもなります

---

## 4. セキュリティチェック

### 4.1 SQL Injection 対策

**けいかくん**では、全てのクエリでSQLAlchemyのパラメータ化クエリを使用し、SQL injectionを防いでいます。

**❌ 危険なコード（絶対に書かない）**:
```python
# ❌ NG: 文字列結合でSQLを生成（SQL injection の脆弱性）
async def search_users(db: AsyncSession, name: str):
    query = f"SELECT * FROM users WHERE name = '{name}'"  # ❌ 危険！
    result = await db.execute(text(query))
    return result.fetchall()
```

**✅ 安全なコード**:
```python
# ✅ OK: SQLAlchemyのwhere句でパラメータ化
async def search_users(db: AsyncSession, name: str):
    result = await db.execute(
        select(User).where(User.name == name)  # ✅ 自動的にエスケープされる
    )
    return result.scalars().all()
```

**確認方法**:
```bash
# 文字列結合でSQLを構築していないか確認
grep -r "f\"SELECT\|f'SELECT\|\"SELECT.*{" k_back/app --include="*.py"

# text()を使っている箇所を確認（必要な場合のみOK）
grep -r "text(" k_back/app --include="*.py"
```

### 4.2 XSS 対策

エラーメッセージにユーザー入力を含める場合、必ずエスケープします。

**❌ 危険なコード**:
```python
# ❌ NG: ユーザー入力をそのままエラーメッセージに含める
raise HTTPException(
    status_code=400,
    detail=f"Invalid name: {user_input}"  # ❌ XSSの可能性
)
```

**✅ 安全なコード**:
```python
# ✅ OK: FastAPIのHTTPExceptionは自動的にエスケープする
raise HTTPException(
    status_code=400,
    detail="入力された名前が不正です"  # ✅ ユーザー入力を含めない
)

# または、Pydanticでバリデーションエラーを返す
```

### 4.3 認可チェックの確認

**全ての変更操作**には、適切な権限チェックが必要です。

**必須の認可パターン**:

```python
# ✅ パターン1: 依存関数で認可チェック
@router.post("/plans")
async def create_plan(
    current_staff: Staff = Depends(get_current_manager_or_above)  # ✅ manager以上のみ
):
    ...

# ✅ パターン2: 事業所の所属チェック
@router.get("/offices/{office_id}/plans")
async def get_plans(
    office_id: UUID,
    current_staff: Staff = Depends(get_current_staff)
):
    # ✅ 自分の事業所のデータのみ取得可能
    if current_staff.office_id != office_id:
        raise HTTPException(
            status_code=403,
            detail="この事業所のデータにアクセスする権限がありません"
        )
    ...
```

**確認方法**:
```bash
# 変更系エンドポイント（POST/PUT/PATCH/DELETE）で権限チェックがあるか確認
grep -B5 "@router.post\|@router.put\|@router.patch\|@router.delete" k_back/app/api --include="*.py" | grep "Depends"
```

**なぜ重要か**:
- 認可チェックがないと、他の事業所のデータを変更される可能性があります
- 福祉事業所のデータは個人情報を含むため、認可の漏れは重大なセキュリティインシデントです

---

## 5. Commit Message 規約

### 5.1 けいかくんのCommit Message フォーマット

**過去20件のcommit履歴**から、以下のフォーマットを使用していることが確認できます：

```
<type>: <subject>

例:
feat: 本番環境ログ削減とテスト環境にENVIRONMENT設定
fix: pytest.iniに-sフラグ追加 - GitHub Actionsでクリーンアップログ表示
chore: k_backサブモジュール更新 - filter logic修正
docs: GitHub Actionsテスト失敗修正ドキュメント追加
security: サブモジュール更新 - tarパッケージ脆弱性修正
```

### 5.2 Type の種類

| Type | 用途 | 例 |
|------|------|-----|
| **feat** | 新機能の追加 | `feat: Web Push通知機能を追加` |
| **fix** | バグ修正 | `fix: TypeScript 5.9対応でVercelビルドエラーを修正` |
| **chore** | ビルドプロセスやツールの変更、サブモジュール更新など | `chore: k_backサブモジュール更新` |
| **docs** | ドキュメントのみの変更 | `docs: README.mdを現在の実装に合わせて全面改訂` |
| **security** | セキュリティ関連の修正 | `security: tarパッケージ脆弱性修正` |
| **refactor** | リファクタリング（機能変更なし） | `refactor: billing_service層の責務を再定義` |
| **test** | テストの追加・修正 | `test: support_plan CRUDの統合テストを追加` |

### 5.3 Good Commit Message の例

**✅ Good**:
```
feat: 個別支援計画のPDFエクスポート機能を追加

- wkhtmltopdfを使用してHTML→PDF変換を実装
- 署名欄、事業所ロゴを含むテンプレートを作成
- S3への自動アップロード機能を追加

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

**✅ Good（簡潔な場合）**:
```
fix: billing_statusのENUM値に'canceling'を追加

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

**❌ Bad**:
```
update code
```

**❌ Bad（英語メッセージで日本語の詳細がない）**:
```
feat: Add PDF export

Added PDF export feature.
```

### 5.4 Commit Message のベストプラクティス

1. **件名は日本語で簡潔に**（50文字以内）
2. **詳細が必要な場合は本文を追加**（72文字で改行）
3. **"なぜ"を重視**（"何を"変更したかではなく、"なぜ"変更したか）
4. **Claude Code使用時は`Co-Authored-By`を追加**

**HEREDOCを使った正しいcommit方法**:
```bash
git commit -m "$(cat <<'EOF'
feat: Stripe Webhook署名検証機能を追加

- 不正なWebhook requestを防ぐため、HMAC-SHA256署名検証を実装
- webhook_eventsテーブルで冪等性を担保
- 署名検証失敗時は400を返し、audit_logに記録

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## 6. PR Description のベストプラクティス

### 6.1 PRタイトル

コミットメッセージと同じフォーマットを使用します：

```
<type>: <subject>

例:
feat: Web Push通知機能を追加
fix: GitHub ActionsでTESTING=1を設定し本番DBを使用しないように修正
```

### 6.2 PR Description テンプレート

```markdown
## Summary
<!変更内容を1-3つの箇条書きで説明 -->

## Changes
- ✅ 追加した機能・ファイル
- ✅ 修正したバグ・問題
- ✅ 変更したアーキテクチャ

## Migration
<!-- マイグレーションファイルが含まれる場合 -->
- [ ] `upgrade()`のテスト完了
- [ ] `downgrade()`のテスト完了
- [ ] ENUMの変更がある場合、手動マイグレーションを作成

## Test Plan
<!-- テスト手順を箇条書きで記載 -->
- [ ] 全テストがパス (`pytest tests/ -v`)
- [ ] マイグレーションが正常に適用される
- [ ] ブラウザでの動作確認（該当する場合）
- [ ] セキュリティテスト（SQL injection、XSS、認可チェック）

## Security Checklist
- [ ] SQL injectionの脆弱性がないことを確認
- [ ] XSSの脆弱性がないことを確認
- [ ] 認可チェックが適切に実装されている
- [ ] 監査ログが記録されている（状態変更操作の場合）

## Architecture Compliance
- [ ] 4層アーキテクチャを遵守（API→Services→CRUD→Models）
- [ ] `from app import crud`パターンを使用
- [ ] `selectinload()`を使用してN+1問題を防止
- [ ] 日本語コメント・エラーメッセージを使用

## Related Issues
<!-- 関連するIssueがあればリンク -->
Closes #123

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

### 6.3 PR作成時のチェックリスト

**コードレビュアーの負担を減らすために**:

1. **✅ 変更範囲を明確にする**
   - 1つのPRで1つの機能または1つのバグ修正に限定
   - 無関係な変更（typo修正、リファクタリング）を混ぜない

2. **✅ スクリーンショットを添付**（フロントエンド変更の場合）
   - 変更前・変更後のスクリーンショット
   - エラーメッセージの表示例

3. **✅ パフォーマンスへの影響を記載**
   - クエリ数の変化（N+1問題の解消など）
   - レスポンスタイムの変化

4. **✅ Breaking Changes を明記**
   - API仕様の変更がある場合
   - フロントエンドとの互換性に影響がある場合

---

## 7. Code Review の観点

### 7.1 Self Review（自己レビュー）

**PRを作成する前に、自分で以下をチェックします**:

```bash
# 1. 差分を確認
git diff main...HEAD

# 2. 意図しない変更が含まれていないか確認
# - デバッグ用のprint文
# - TODO/FIXMEコメント
# - ハードコードされた値（環境変数にすべき）
# - 不要な空白行の変更

# 3. ファイルごとに変更理由を説明できるか確認
git diff --name-status main...HEAD
```

**チェック項目**:
- [ ] 全ての変更が意図的か
- [ ] コメントアウトされたコードが残っていないか
- [ ] デバッグ用のログが残っていないか
- [ ] ハードコードされた値がないか（環境変数化すべき）

### 7.2 Reviewer への配慮

**レビュアーがスムーズにレビューできるように**:

1. **小さなPRを心がける**
   - 目安: 変更行数300行以下
   - 理由: 大きなPRはレビュー品質が下がる

2. **コメントで変更の意図を説明**
   ```python
   # この変更の理由: N+1問題を解消するためselectinload()を追加
   .options(selectinload(Billing.office))
   ```

3. **複雑なロジックには図を添付**
   - PlantUMLやMermaidでフロー図を作成
   - PR descriptionに添付

4. **レビュー依頼時にポイントを伝える**
   ```
   @reviewer この変更で特に確認してほしい点:
   - 3層アーキテクチャを守れているか
   - selectinload()の使い方が適切か
   ```

---

## 8. 特にけいかくんで気をつけていること

### 8.1 個人情報の取り扱い

**けいかくん**は福祉サービス提供者向けシステムのため、個人情報を多数扱います。

**絶対にやってはいけないこと**:
- ❌ ログに個人情報を出力する
- ❌ エラーメッセージに利用者名を含める
- ❌ テストデータに実在の個人名を使う

**良い例**:
```python
# ✅ OK: 個人情報をログに出さない
logger.info(f"利用者ID {user_id} の個別支援計画を作成しました")

# ❌ NG: 個人情報をログに出す
logger.info(f"利用者 {user.full_name} の個別支援計画を作成しました")  # ❌ 名前を出してはいけない
```

### 8.2 課金関連の変更

**Stripe Webhook**や**Billing Status**に関わる変更は特に慎重に：

**必須チェック**:
- [ ] Webhook署名検証が実装されているか
- [ ] `webhook_events`テーブルで冪等性を担保しているか
- [ ] 課金ステータスの遷移が正しいか（`free → early_payment → active → past_due → canceled`）
- [ ] `past_due`状態で読み取り専用モードが機能するか

**テスト方法**:
```bash
# Stripe CLIでWebhookをローカルテスト
stripe listen --forward-to localhost:8000/api/v1/webhooks/stripe

# テストイベントを送信
stripe trigger payment_intent.succeeded
```

### 8.3 APScheduler のジョブ管理

**バッチ処理**（トライアル期限チェック、期限通知など）の変更時：

**必須チェック**:
- [ ] `replace_existing=True`が設定されているか（アプリ再起動時のConflictingIdError防止）
- [ ] 冪等性が担保されているか（同じジョブが2回実行されても問題ないか）
- [ ] タイムゾーンが正しいか（UTC固定）
- [ ] エラー発生時のリトライ戦略が適切か

**確認方法**:
```bash
# replace_existing=Trueが設定されているか確認
grep -A5 "add_job" k_back/app/scheduler/*.py | grep "replace_existing"
```

---

## 9. まとめ：PRチェックリスト（印刷用）

**PRを作成する前に、このチェックリストを全て確認します**:

### Pre-PR Checklist

#### テスト・品質
- [ ] 全テストがパス（`pytest tests/ -v`）
- [ ] 新機能にテストを追加
- [ ] マイグレーションのupgrade/downgradeをテスト

#### コード品質
- [ ] `from app import crud`パターンを使用
- [ ] MissingGreenletエラーが発生しない（`billing.office_id`を使用）
- [ ] `selectinload()`でN+1問題を防止
- [ ] 4層アーキテクチャを遵守

#### セキュリティ
- [ ] SQL injection対策（パラメータ化クエリ）
- [ ] XSS対策（エラーメッセージのエスケープ）
- [ ] 認可チェック（権限・事業所の確認）
- [ ] 監査ログの記録（状態変更操作）

#### 言語・ドキュメント
- [ ] コメントは日本語
- [ ] エラーメッセージは日本語
- [ ] 変数・関数名は英語
- [ ] PR Descriptionを記載

#### Migration（該当する場合）
- [ ] upgrade()とdowngrade()の両方を実装
- [ ] データ損失の警告コメントを記載
- [ ] ENUMの変更は手動マイグレーション

#### Git
- [ ] Commit messageが規約に従っている（`<type>: <subject>`）
- [ ] Co-Authored-By を追加（Claude Code使用時）
- [ ] 意図しない変更が含まれていない（Self Review実施）

---

## 面接での回答例

> **面接官**: 「PRを出すときに気をつけていることは？」

**回答**:

PRを出す際は、主に**3つの観点**を重視しています。

**1つ目は、レビュアーの負担を減らすことです。**
PRは1つの機能または1つのバグ修正に限定し、変更範囲を明確にしています。また、PR Descriptionには変更の意図、テスト手順、セキュリティチェック結果を詳細に記載し、レビュアーが効率的にレビューできるようにしています。

**2つ目は、品質とセキュリティの担保です。**
けいかくんでは155個のテストファイルに1,787個のテスト関数があり、PRを出す前に必ず全テストを実行し、パスすることを確認しています。また、福祉事業所向けのシステムのため、個人情報の取り扱いには特に注意し、SQL injection、XSS、認可チェックの漏れがないか、必ず確認しています。

**3つ目は、アーキテクチャの遵守です。**
けいかくんでは4層アーキテクチャ（API→Services→CRUD→Models）を採用しており、各層の責務を守ることを徹底しています。特にN+1問題を防ぐため、一覧取得APIでは必ず`selectinload()`を使用し、パフォーマンスを担保しています。

これらの観点を守ることで、チーム全体の開発効率を高め、本番環境でのインシデントを防ぐことができると考えています。

---

**作成日**: 2026-01-29
**対象プロジェクト**: けいかくん（個別支援計画管理システム）
**ドキュメント種別**: 面接準備資料
