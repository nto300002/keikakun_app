# 退会処理機能

> **注記**: app_admin専用の事務所管理機能（事務所一覧、事務所プレビュー）は [`app_admin.md`](./app_admin.md) に移動しました。

## 開発者画面（概要）
- ownerから受け取る: 退会処理、課金処理
- 全Staffから受け取る: 問い合わせ
- 発信: おしらせ送信
- 監視ログを可視化(audit_log)全て
- 新規事務所作成などのログ
- スタッフの同意状況を可視化

- ログインの際に決まった合言葉が必要 app_adminのみ
合言葉1, 合言葉2, 合言葉3　新規テーブル?

---

## 調査結果: app_admin合言葉（セカンドパスワード）機能

### 要件
- app_admin専用の追加認証
- passwordと同じ形式（数字、記号、文字列を扱える）
- ログイン時にパスワードに加えて合言葉も検証
- **合言葉の設定はPythonスクリプトで行う（UIからは設定不可）**
- `k_front/components/auth/app-admin/` はapp_admin専用機能

### 結論: 新規テーブルは不要

**推奨: Staffモデルにカラム追加**

```python
# k_back/app/models/staff.py に追加
class Staff(Base):
    # ... 既存のフィールド ...

    # app_admin専用の合言葉（セカンドパスワード）
    hashed_passphrase: Mapped[Optional[str]] = mapped_column(
        String(255),
        nullable=True,
        comment="app_admin専用の合言葉（bcryptハッシュ化）"
    )
    passphrase_changed_at: Mapped[Optional[datetime.datetime]] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        comment="合言葉の最終変更日時"
    )
```

### 理由

| 観点 | 説明 |
|------|------|
| セキュリティ | 既存のbcryptハッシュ関数（`get_password_hash`/`verify_password`）を再利用可能 |
| シンプルさ | 1:1リレーションシップはカラム追加で十分。別テーブルは過剰 |
| パフォーマンス | JOINなしでログイン認証可能 |
| 保守性 | 既存の認証フローに条件分岐を追加するだけ |

### 新規テーブルが不要な理由

```
Option B（新規テーブル）の場合:
┌──────────────────┐     ┌────────────────────────┐
│     staffs       │ 1:1 │  app_admin_credentials │
├──────────────────┤     ├────────────────────────┤
│ id               │────>│ staff_id (FK, UNIQUE)  │
│ hashed_password  │     │ hashed_passphrase      │
│ ...              │     │ ...                    │
└──────────────────┘     └────────────────────────┘

問題点:
- 追加のJOINが必要（パフォーマンス低下）
- 1:1リレーションシップに別テーブルは過剰設計
- app_admin以外には無関係なテーブルが増える
```

### 実装方針

#### 1. マイグレーション
```sql
ALTER TABLE staffs ADD COLUMN hashed_passphrase VARCHAR(255) NULL;
ALTER TABLE staffs ADD COLUMN passphrase_changed_at TIMESTAMP WITH TIME ZONE NULL;
COMMENT ON COLUMN staffs.hashed_passphrase IS 'app_admin専用の合言葉（bcryptハッシュ化）';
```

#### 2. 合言葉設定スクリプト（Pythonスクリプトで設定）

**UIからは設定不可。DB直接アクセス権限を持つ管理者のみが設定可能。**

```python
# k_back/scripts/set_admin_passphrase.py
"""
app_admin用の合言葉を設定するスクリプト

使用方法:
  docker compose exec backend python scripts/set_admin_passphrase.py <email> <passphrase>

例:
  docker compose exec backend python scripts/set_admin_passphrase.py admin@example.com "secret123!"
"""
import asyncio
import sys
from datetime import datetime, timezone

from sqlalchemy import select
from app.db.session import async_session_maker
from app.models.staff import Staff
from app.models.enums import StaffRole
from app.core.security import get_password_hash


async def set_passphrase(email: str, passphrase: str):
    async with async_session_maker() as db:
        # app_adminを取得
        result = await db.execute(
            select(Staff).where(
                Staff.email == email,
                Staff.role == StaffRole.app_admin
            )
        )
        admin = result.scalar_one_or_none()

        if not admin:
            print(f"Error: app_admin with email '{email}' not found")
            print("Note: This script only works for users with role='app_admin'")
            sys.exit(1)

        # 合言葉をハッシュ化して設定
        admin.hashed_passphrase = get_password_hash(passphrase)
        admin.passphrase_changed_at = datetime.now(timezone.utc)
        await db.commit()

        print(f"✓ Passphrase successfully set for {email}")
        print(f"  Changed at: {admin.passphrase_changed_at}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python scripts/set_admin_passphrase.py <email> <passphrase>")
        print("Example: python scripts/set_admin_passphrase.py admin@example.com 'my_secret!'")
        sys.exit(1)

    email = sys.argv[1]
    passphrase = sys.argv[2]

    # パスフレーズの最低要件チェック
    if len(passphrase) < 8:
        print("Error: Passphrase must be at least 8 characters")
        sys.exit(1)

    asyncio.run(set_passphrase(email, passphrase))
```

**スクリプト方式の利点:**
| 観点 | 説明 |
|------|------|
| セキュリティ | DB直接アクセス権限者のみが設定可能 |
| 互換性 | アプリ側の`get_password_hash()`を使用するためbcrypt互換性が保証 |
| シンプル | 合言葉変更UIやAPIが不要 |
| 監査 | スクリプト実行はサーバーログに記録される |

#### 3. 認証フロー変更

```
現在のフロー:
[メール/パスワード] → (MFA) → トークン発行

app_admin用フロー:
[メール/パスワード] → [合言葉検証] → (MFA) → トークン発行
```

#### 4. API変更

`POST /api/v1/auth/token` エンドポイントの変更:

```python
@router.post("/token")
async def login_for_access_token(
    username: str = Form(...),
    password: str = Form(...),
    passphrase: Optional[str] = Form(None),  # 追加
):
    user = await staff_crud.get_by_email(db, email=username)

    # パスワード検証
    if not verify_password(password, user.hashed_password):
        raise HTTPException(status_code=401, detail="認証に失敗しました")

    # app_adminの場合は合言葉も検証
    if user.role == StaffRole.app_admin:
        if not passphrase or not verify_password(passphrase, user.hashed_passphrase):
            raise HTTPException(status_code=401, detail="合言葉が正しくありません")

    # 以降は既存のMFA/トークン発行フロー
```

#### 5. フロントエンド変更

`/auth/app-admin/login` のログインフォームに合言葉入力フィールドを追加:

```tsx
// k_front/components/auth/app-admin/LoginForm.tsx
<Input
  type="password"
  name="passphrase"
  placeholder="合言葉を入力"
  required
/>
```

### セキュリティ考慮事項

| 項目 | 対応 |
|------|------|
| ブルートフォース対策 | 既存のレートリミット（5回/分）を適用 |
| エラーメッセージ | 「認証に失敗しました」で統一（合言葉が間違いか判別不可に） |
| ログ記録 | 合言葉検証失敗も監査ログに記録 |
| 変更通知 | 合言葉変更時にメール通知 |

### タスク追加

Phase 1.1 マイグレーションに追加:
- [ ] `staffs`テーブルに`hashed_passphrase`, `passphrase_changed_at`カラム追加

Phase 2 スクリプトに追加:
- [ ] `k_back/scripts/set_admin_passphrase.py` 合言葉設定スクリプト作成

Phase 3 API層に追加:
- [ ] `POST /api/v1/auth/token` にapp_admin用合言葉検証を追加
- ~~[ ] `PATCH /api/v1/admin/passphrase` 合言葉変更API作成~~ → **不要（スクリプトで設定）**

Phase 4 フロントエンドに追加:
- [ ] `/auth/app-admin/login` に合言葉入力フィールド追加
- ~~[ ] app_admin設定画面に合言葉変更機能追加~~ → **不要（スクリプトで設定）**

---

## データ設計
staffにrole追加
app_admin = 'app_admin'


## 機能: 退会処理
退会処理リクエストをapp_adminが承認した場合
通知機能を介して, StaffRole.app_adminのidとそれ以外のRoleを持つStaffのidを持つカラムを持ったテーブルを作成
- 退会処理リクエストテーブル(Staff.app_admin:Staff.owner = 1:1)

## 退会処理フロー
オーナー管理画面(AdminMenu.tsx)　事務所タブ > 退会モーダル -> アプリ管理者画面  :退会リクエスト
アプリ管理者画面 退会リクエスト受付, 承認 -> 事務所論理削除　ログインされているスタッフはログアウト　ログイン画面にて再度ログインしようとした際に,事務所が退会したことをアナウンスされる

## 受け入れ基準
Given オーナーがログインしている > When 退会リクエストを送信した > Then app_adminに通知が届き、 withdrawal_requests にレコードが作成される。


## ステークホルダーとユースケース
- オーナー(Staff.owner)
事務所退会申請を送信
- アプリ管理者
申請を承認/拒否、承認した場合は事務所の論理削除
- スタッフ(Staff.employee manager)
ログアウトされる、ログインしようとした際に事務所が退会したことをアナウンスされる

## 権限
お知らせ送信: オーナーのみ
退会承認: app_adminのみ
UIで操作できない+apiでも操作できないようにする(403エラーraise)

## 機能分割
### データ設計
```py
  #共通化案: ApprovalRequest テーブル <RoleChangeRequest,EmployeeActionRequest,WithdrawalRequest>

  class ResourceType(str, enum.Enum):
      role_change = 'role_change'
      employee_action = 'employee_action'
      withdrawal = 'withdrawal'  # 追加

  class ApprovalRequest(Base):
      __tablename__ = 'approval_requests'

      id: UUID
      requester_staff_id: UUID          # リクエスト者
      office_id: UUID                   # 対象事務所
      resource_type: ResourceType       # リクエスト種別
      status: RequestStatus             # pending/approved/rejected
      request_data: JSON                # リクエスト固有のデータ
      reviewed_by_staff_id: UUID        # 承認者
      reviewed_at: DateTime
      reviewer_notes: Text
      execution_result: JSON            # 実行結果
      created_at, updated_at: DateTime
```

### UI（概要）

> **詳細は Phase 4 を参照**

#### app_admin（アプリ管理者）側
| 機能 | ページパス | メインコンポーネント |
|------|-----------|---------------------|
| ログイン | `/auth/app-admin/login` | `LoginForm.tsx` |
| ダッシュボード | `/app-admin` | `AppAdminDashboard.tsx` |
| 事務所プレビュー | `/app-admin/offices/[officeId]` | `OfficePreview.tsx` |

**ダッシュボードタブ:**
| タブ名 | 機能 |
|--------|------|
| ログ | 監査ログ表示（30件/ページ） |
| 問い合わせ | スタッフからの問い合わせ確認 |
| 承認リクエスト | 退会リクエスト承認/却下 |
| お知らせ | 全スタッフへのお知らせ送信 |
| 事務所 | 事務所一覧（名前検索、プレビュー遷移） |

#### オーナー（事務所管理者）側
| 機能 | ページパス | 追加コンポーネント |
|------|-----------|-------------------|
| 退会申請 | `/admin`（既存） | `WithdrawalModal.tsx`（AdminMenu.tsxに追加） |

#### システム通知
- 事務所退会承認時: メッセージ機能で「事務所を退会しました」通知を送信

### API（概要）

> **詳細は Phase 3 を参照**

#### 退会リクエストAPI
| メソッド | エンドポイント | 権限 | 説明 |
|----------|---------------|------|------|
| POST | `/api/v1/withdrawal-requests` | owner | 退会リクエスト作成 |
| GET | `/api/v1/withdrawal-requests` | app_admin | 退会リクエスト一覧取得 |
| PATCH | `/api/v1/withdrawal-requests/{id}/approve` | app_admin | リクエスト承認 |
| PATCH | `/api/v1/withdrawal-requests/{id}/reject` | app_admin | リクエスト却下 |

**エラーレスポンス:**
- 403: 権限がありません
- 422: バリデーションエラー（タイトル/申請内容未入力）
- 404: リクエストが見つかりません

**承認時の処理:**
1. 事務所に`is_deleted=True`, `deleted_at`, `deleted_by`を設定
2. 全スタッフの論理削除
3. システム通知送信
4. 監査ログ記録

**保持期間:** 論理削除後30日で完全削除

**認証:** Cookie + CSRF



## 質問
監査・ログ要件（必須）
監査ログのスキーマ（actor_id, action, target_type, target_id, ip, user_agent, timestamp, details）。読み出し用クエリや削除ポリシー（保持期間）も決める。
重要操作は必ず監査ログに出す（退会承認、アカウント削除、権限変更、データエクスポート）。

- crud 読み出し用クエリ
- 削除ボリシー: 利用規約の変更(追記?)


### 回答済み

#### 1. リファクタリング
role_change_requestとwithrawal_requestsのテーブルが同じ役割 =>共通かしたほうが良いか
-> **共通化する**

#### 2. トランザクション
-> **単一トランザクション**

#### 3. 監査ログ設計

##### 3.1 テーブル設計: 統合型
```py
class AuditLog(Base):
    __tablename__ = 'audit_logs'

    id: UUID                          # PK
    actor_id: UUID                    # 操作実行者（FK: staffs.id）
    actor_role: StaffRole             # 実行時のロール
    action: str                       # "staff.deleted", "office.updated", "withdrawal.approved"
    target_type: str                  # "staff", "office", "withdrawal_request"
    target_id: UUID                   # 対象リソースのID
    office_id: UUID                   # 事務所ID（横断検索用、app_adminはNULL可）
    ip_address: str(45)               # IPv4/IPv6
    user_agent: Text                  # ブラウザ情報
    details: JSONB                    # 変更内容（old_values, new_values）
    created_at: DateTime              # タイムスタンプ（UTC）
    is_test_data: Boolean             # テストデータフラグ
```

##### 3.2 読み出しクエリ設計: 候補A + 候補B併用

**候補A: フィルター付きページネーション（検索用）**
```py
async def get_audit_logs(
    db: AsyncSession,
    *,
    office_id: Optional[UUID] = None,      # 事務所フィルター（app_adminは全件可）
    target_type: Optional[str] = None,     # リソース種別フィルター
    action: Optional[str] = None,          # アクション種別フィルター
    actor_id: Optional[UUID] = None,       # 実行者フィルター
    start_date: Optional[datetime] = None, # 期間フィルター
    end_date: Optional[datetime] = None,
    skip: int = 0,
    limit: int = 30                        # 30件ごと
) -> Tuple[List[AuditLog], int]:
```

**候補B: カーソルベースページネーション（無限スクロール用）**
```py
async def get_audit_logs_cursor(
    db: AsyncSession,
    *,
    cursor: Optional[datetime] = None,  # 前回の最後のcreated_at
    limit: int = 30
) -> List[AuditLog]:
```

##### 3.3 削除ポリシー: アクション種別ごとの保持期間
```py
RETENTION_POLICY = {
    # 法的要件（5年）
    "staff.deleted": 365 * 5,
    "withdrawal.approved": 365 * 5,
    "withdrawal.rejected": 365 * 5,
    "terms.agreed": 365 * 5,           # 利用規約同意
    "data.exported": 365 * 5,

    # 重要操作（3年）
    "office.updated": 365 * 3,
    "role.changed": 365 * 3,
    "mfa.enabled": 365 * 3,
    "mfa.disabled": 365 * 3,

    # 軽微な操作（1年）
    "login.success": 365 * 1,
    "password.changed": 365 * 1,

    # 短期保持（90日）
    "login.failed": 90,
}
```

##### 3.4 重要操作の監査ログ記録一覧
| 操作 | action値 | 記録すべき詳細 | 保持期間 |
|------|----------|---------------|----------|
| 退会承認 | `withdrawal.approved` | 事務所名、承認者、対象スタッフ数 | 5年 |
| 退会却下 | `withdrawal.rejected` | 事務所名、却下理由 | 5年 |
| アカウント削除 | `staff.deleted` | 削除者、対象者情報、理由 | 5年 |
| 権限変更 | `role.changed` | 変更前/後のロール、承認者 | 3年 |
| データエクスポート | `data.exported` | エクスポート種別、対象期間 | 5年 |
| **利用規約同意** | `terms.agreed` | 同意バージョン、IP、User-Agent | 5年 |
| 事務所情報変更 | `office.updated` | 変更前/後の値 | 3年 |
| MFA有効化/無効化 | `mfa.enabled`/`mfa.disabled` | 対象スタッフ | 3年 |
| ログイン成功/失敗 | `login.success`/`login.failed` | IPアドレス、User-Agent | 1年/90日 |

#### 4. 利用規約同意記録について

##### 現在の実装状況
- **専用テーブル `terms_agreements`**: 実装済み（同意の現在状態を管理）
- **記録内容**: staff_id, terms_version, privacy_version, ip_address, user_agent, agreed_at

##### 監査ログとの関係
```
terms_agreements  = 同意の「現在状態」（1スタッフ1レコード、最新バージョンへの同意状況）
audit_logs        = 同意の「操作履歴」（いつ、どのバージョンに同意したかの時系列記録）
```

##### 結論
- `terms_agreements`テーブルは維持（同意状態管理用）
- **監査ログにも `terms.agreed` アクションを記録すべき**（法的証拠として5年保持）
- 同意操作時に両方のテーブルに書き込む

##### 利用規約への追記案
```markdown
## データの保持期間

当サービスでは、以下のデータを所定の期間保持します：

- アカウント操作履歴（削除、退会、利用規約同意等）: 5年間
- 権限変更・事務所情報変更履歴: 3年間
- ログイン履歴: 1年間

保持期間経過後、データは自動的に削除されます。
法令に基づく開示請求があった場合、保持期間内のデータを提供することがあります。
```

## タスク達成状況サマリー

| Phase | 項目 | 状況 | テスト結果 |
|-------|------|------|-----------|
| Phase 1 | データベース・モデル層 | ✅ 完了 | - |
| Phase 2 | CRUD・サービス層 | ✅ 完了 | CRUD: 30/30 ✅, Service: 20/20 ✅ |
| Phase 3 | API層 | ✅ 完了 | API: 実装済み |
| Phase 4 | フロントエンド | ⬜ 未着手 | - |
| Phase 5 | 既存機能統合・リファクタリング | 🔶 一部完了 | StaffAuditLog→AuditLog統合完了 |
| Phase 6 | テスト | 🔶 一部完了 | CRUD: 30/30 ✅, Service: 20/20 ✅, API: 実装済み |

**最終更新: 2025-11-27**

---

## セキュリティ・マイグレーションレビュー

**レビュー実施日: 2025-11-27**
**対象バージョン: 現行実装**

---

### セキュリティレビュー

#### 1. 認可（Authorization） ✅ 良好

| 観点 | 評価 | 詳細 |
|------|------|------|
| ロールベースアクセス制御 | ✅ | `StaffRole.owner` / `StaffRole.app_admin` での明示的なチェック |
| API層での権限チェック | ✅ | `withdrawal_requests.py:79`, `246`, `320` で実装 |
| Service層での二重チェック | ✅ | `withdrawal_service.py:143`, `231`, `328` で再確認 |

**実装例:**
```python
# withdrawal_service.py:143-147
if not requester or requester.role != StaffRole.owner:
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="事務所の退会リクエストはオーナーのみが作成できます"
    )
```

#### 2. 入力バリデーション ✅ 良好

| 観点 | 評価 | 詳細 |
|------|------|------|
| Pydanticスキーマ | ✅ | `withdrawal_request.py` で `Field` による制約 |
| 長さ制限 | ✅ | `title: max_length=100`, `reason: max_length=2000` |
| 必須チェック | ✅ | `min_length=1` で空文字を拒否 |

**実装例:**
```python
# withdrawal_request.py:16-17
title: str = Field(..., min_length=1, max_length=100)
reason: str = Field(..., min_length=1, max_length=2000)
```

#### 3. SQLインジェクション対策 ✅ 良好

| 観点 | 評価 | 詳細 |
|------|------|------|
| ORMクエリ使用 | ✅ | SQLAlchemy ORM経由でのクエリ（raw SQL なし） |
| パラメータバインディング | ✅ | `select()`, `delete()`, `update()` で自動エスケープ |

**安全な実装例:**
```python
# withdrawal_service.py:496-498
await db.execute(
    delete(OfficeStaff).where(OfficeStaff.staff_id == target_staff_id)
)
```

#### 4. 監査ログ ✅ 良好

| 観点 | 評価 | 詳細 |
|------|------|------|
| 重要操作の記録 | ✅ | リクエスト作成/承認/却下/実行のすべてを記録 |
| IPアドレス記録 | ✅ | `ip_address`, `user_agent` を保存 |
| 削除前の情報保存 | ✅ | `staff_info`, `office_info` を削除前に取得・記録 |
| 保持期間管理 | ✅ | `RETENTION_POLICIES` で5年/3年/1年/90日を定義 |

**重要:**
```python
# withdrawal_service.py:479-493 - 削除前に情報を保存して監査ログに記録
staff_info = {
    "id": str(target_staff.id),
    "email": target_staff.email,
    "full_name": target_staff.full_name,
    "role": target_staff.role.value
}
await crud_audit_log.create_log(..., details={"deleted_staff": staff_info})
```

#### 5. トランザクション管理 ✅ 良好

| 観点 | 評価 | 詳細 |
|------|------|------|
| 単一トランザクション | ✅ | 退会処理は `flush()` のみ、最終 `commit()` はAPI層 |
| エラー時のロールバック | ✅ | 例外発生時はトランザクションがロールバック |
| 順序の整合性 | ✅ | FK制約を考慮した削除順序（OfficeStaff → Staff） |

**削除順序の例:**
```python
# withdrawal_service.py:610-627
# 1. office_staffsを先に削除（FK制約対応）
await db.execute(delete(OfficeStaff).where(...))
# 2. Officeの参照を更新（created_by, last_modified_by）
await db.execute(update(Office).where(...).values(created_by=executor_id))
# 3. Staffを削除
await db.execute(delete(Staff).where(...))
# 4. Officeを論理削除
await crud_office.soft_delete(...)
```

#### 6. 重複リクエスト防止 ✅ 良好

| 観点 | 評価 | 詳細 |
|------|------|------|
| 承認待ちチェック | ✅ | `has_pending_withdrawal()` で重複検出 |
| 409 Conflict返却 | ✅ | 重複時は適切なエラーコード |

---

### セキュリティ上の注意点・改善提案

#### ⚠️ 要確認事項

| # | 項目 | 現状 | 推奨対応 | 優先度 |
|---|------|------|---------|--------|
| 1 | レートリミット | API層でのチェック未確認 | 退会リクエストAPIにレートリミット適用 | 中 |
| 2 | CSRFトークン | 設計書に記載あり | 実装確認が必要 | 高 |
| 3 | セッション無効化 | 未実装 | 退会時に対象ユーザーのセッション無効化 | 高 |
| 4 | 通知機能 | 未連携 | 退会承認時のメール/システム通知 | 中 |
| 5 | ソフトデリート復元 | 未実装 | 30日以内の誤削除復元機能 | 低 |

#### 推奨：セッション無効化の実装

```python
# 退会処理完了後に追加すべき処理
async def _invalidate_user_sessions(self, db: AsyncSession, staff_ids: List[UUID]):
    """退会対象ユーザーのリフレッシュトークンをブラックリストに追加"""
    from app.models.staff import RefreshTokenBlacklist
    # 実装が必要
```

---

### マイグレーションレビュー

#### 1. スキーマ設計 ✅ 良好

| 観点 | 評価 | 詳細 |
|------|------|------|
| 外部キー設計 | ✅ | `ondelete="CASCADE"` / `"SET NULL"` 適切に設定 |
| インデックス | ✅ | 検索頻度の高いカラムにindex設定 |
| JSONB活用 | ✅ | `request_data`, `execution_result` で柔軟性確保 |

**ApprovalRequestモデルのFK設計:**
```python
# approval_request.py:43-55
requester_staff_id: ForeignKey('staffs.id', ondelete="CASCADE")  # スタッフ削除時に連動削除
office_id: ForeignKey('offices.id', ondelete="CASCADE")          # 事務所削除時に連動削除
reviewed_by_staff_id: ForeignKey('staffs.id', ondelete="SET NULL") # 承認者削除時はNULL
```

#### 2. 後方互換性 🔶 要注意

| 項目 | 状況 | 対応策 |
|------|------|--------|
| `approval_requests` テーブル | 新規作成 | 既存データなし、問題なし |
| `StaffAuditLog` 非推奨化 | 完了 | Base継承削除済み |
| `staff_audit_logs` テーブル | DB内に残存？ | マイグレーションで削除または維持を決定 |
| `role_change_requests` | 未統合 | Phase 5で対応予定 |

#### 3. ダウンタイム影響

| 操作 | ダウンタイム | 理由 |
|------|------------|------|
| `approval_requests` テーブル作成 | なし | 新規テーブル追加 |
| `audit_logs` テーブル作成 | なし | 新規テーブル追加 |
| `offices` への論理削除カラム追加 | なし | NULLable カラム追加 |
| 古いテーブル削除 | なし | 使用停止後に削除 |

#### 4. ロールバック計画

```sql
-- 緊急ロールバック手順（本番適用前に検証必須）

-- 1. approval_requests テーブル削除
DROP TABLE IF EXISTS approval_requests CASCADE;

-- 2. audit_logs テーブル削除（データ損失注意）
DROP TABLE IF EXISTS audit_logs CASCADE;

-- 3. offices テーブルの論理削除カラム削除
ALTER TABLE offices DROP COLUMN IF EXISTS is_deleted;
ALTER TABLE offices DROP COLUMN IF EXISTS deleted_at;
ALTER TABLE offices DROP COLUMN IF EXISTS deleted_by;

-- 4. StaffRole enumから app_admin 削除
-- 注意: 既存の app_admin ユーザーがいる場合は先にロール変更が必要
```

---

### マイグレーション実行チェックリスト

#### 本番適用前

- [ ] ステージング環境でのテスト完了
- [ ] マイグレーションスクリプトのレビュー完了
- [ ] ロールバックスクリプトの動作確認
- [ ] バックアップ取得完了
- [ ] メンテナンスウィンドウの周知

#### 本番適用後

- [ ] テーブル作成確認 (`approval_requests`, `audit_logs`)
- [ ] カラム追加確認 (`offices.is_deleted` 等)
- [ ] アプリケーション動作確認
- [ ] 監査ログ記録確認
- [ ] 退会フロー動作確認（テスト環境で）

---

### 総合評価

| カテゴリ | 評価 | コメント |
|---------|------|---------|
| **セキュリティ** | ⭐⭐⭐⭐ (4/5) | 基本的なセキュリティ対策は良好。セッション無効化の実装を推奨 |
| **コード品質** | ⭐⭐⭐⭐⭐ (5/5) | 明確な責務分離、適切なログ出力、型ヒント完備 |
| **テストカバレッジ** | ⭐⭐⭐⭐ (4/5) | CRUD 30件、Service 20件でカバー。E2Eテスト追加を推奨 |
| **マイグレーション** | ⭐⭐⭐⭐ (4/5) | 新規テーブルなので影響小。既存テーブル統合は Phase 5 で対応 |

**次のアクション:**
1. ✅ ~~`AuditLogTargetType` enum追加~~ → 完了 (2025-11-27)
2. ✅ ~~`terms.agreed` 監査ログ実装~~ → 完了 (2025-11-27)
3. ✅ ~~app-admin専用レイアウト実装~~ → 完了 (2025-11-27)
4. 🔜 **Phase 4 フロントエンド実装開始**
   - app_admin認証画面（合言葉対応）
   - app_adminダッシュボード
   - 退会リクエスト送信モーダル（オーナー側）
5. Phase 5 既存テーブル統合（role_change_requests, employee_action_requests）
6. セッション無効化機能の実装（セキュリティ強化）
7. E2Eテストの追加

---

### 実装済みファイル一覧

| レイヤー | ファイルパス | 説明 |
|---------|-------------|------|
| Model | `app/models/approval_request.py` | ApprovalRequestモデル |
| Model | `app/models/staff_profile.py` | AuditLogモデル（統合型） |
| Schema | `app/schemas/approval_request.py` | 承認リクエストスキーマ |
| Schema | `app/schemas/withdrawal_request.py` | 退会リクエストスキーマ |
| CRUD | `app/crud/crud_approval_request.py` | 承認リクエストCRUD |
| CRUD | `app/crud/crud_audit_log.py` | 監査ログCRUD |
| Service | `app/services/withdrawal_service.py` | 退会サービス層 |
| API | `app/api/v1/endpoints/withdrawal_requests.py` | 退会リクエストAPI |
| Test | `tests/crud/test_crud_approval_request.py` | CRUD層テスト（30件） |
| Test | `tests/services/test_withdrawal_service.py` | Service層テスト（20件） |
| Test | `tests/api/v1/test_withdrawal_requests.py` | API層テスト |

---

## タスク

### Phase 1: データベース・モデル層（依存なし、最初に実施） ✅ 完了

#### 1.1 マイグレーション
- [x] `StaffRole` enumに `app_admin` を追加
  - ファイル: `k_back/app/models/enums.py`
- [x] `offices` テーブルに論理削除カラム追加
  - カラム: `is_deleted`, `deleted_at`, `deleted_by`
- [x] `audit_logs` テーブル作成（統合型監査ログ）
  - カラム: actor_id, actor_role, action, target_type, target_id, office_id, ip_address, user_agent, details, created_at, is_test_data
  - 既存の `staff_audit_logs`, `office_audit_logs` からのデータ移行検討
- [x] `approval_requests` テーブル作成（統合型リクエスト）
  - カラム: requester_staff_id, office_id, resource_type, status, request_data, reviewed_by_staff_id, reviewed_at, reviewer_notes, execution_result, created_at, updated_at
  - 既存の `role_change_requests`, `employee_action_requests` からのデータ移行検討

#### 1.2 モデル・スキーマ
- [x] `AuditLog` モデル作成
  - ファイル: `k_back/app/models/staff_profile.py`（統合済み）
- [x] `ApprovalRequest` モデル作成
  - ファイル: `k_back/app/models/approval_request.py`
- [x] `ResourceType` enum作成（role_change, employee_action, withdrawal）
  - ファイル: `k_back/app/models/enums.py`
- [x] Pydanticスキーマ作成
  - ファイル: `k_back/app/schemas/audit_log.py`
  - ファイル: `k_back/app/schemas/approval_request.py`

---

### Phase 2: CRUD・サービス層（Phase 1完了後） ✅ 完了

#### 2.1 監査ログCRUD ✅
- [x] `crud_audit_log.py` 作成
  - ファイル: `k_back/app/crud/crud_audit_log.py`
  - `create_log()`: ログ記録
  - `get_logs()`: フィルター付きページネーション（候補A）
  - `get_logs_cursor()`: カーソルベースページネーション（候補B）
  - `cleanup_old_logs()`: 保持期間に基づく削除

#### 2.2 承認リクエストCRUD ✅
- [x] `crud_approval_request.py` 作成
  - ファイル: `k_back/app/crud/crud_approval_request.py`
  - `create_request()`: リクエスト作成
  - `get_pending_requests()`: 承認待ちリクエスト取得
  - `approve()`: 承認処理
  - `reject()`: 却下処理
  - `set_execution_result()`: 実行結果記録

#### 2.3 事務所論理削除 ✅
- [x] `crud_office.py` に `soft_delete()` メソッド追加
  - 事務所の `is_deleted=True`, `deleted_at`, `deleted_by` を設定
  - 全スタッフの論理削除も同時実行（単一トランザクション）

#### 2.4 サービス層 ✅
- [x] `withdrawal_service.py` 作成
  - ファイル: `k_back/app/services/withdrawal_service.py`
  - `create_staff_withdrawal_request()`: スタッフ退会リクエスト作成
  - `create_office_withdrawal_request()`: 事務所退会リクエスト作成
  - `approve_withdrawal()`: 承認 + 退会処理実行 + 監査ログ記録
  - `reject_withdrawal()`: 却下 + 監査ログ記録
  - `get_pending_withdrawal_requests()`: 承認待ちリクエスト取得
  - `get_withdrawal_request()`: リクエスト詳細取得
  - `_execute_staff_withdrawal()`: スタッフ物理削除
  - `_execute_office_withdrawal()`: 事務所論理削除 + スタッフ物理削除

#### テスト結果
- **CRUD層テスト**: `tests/crud/test_crud_approval_request.py` - 30/30 ✅
- **Service層テスト**: `tests/services/test_withdrawal_service.py` - 20/20 ✅

---

### Phase 3: API層（Phase 2完了後） ✅ 完了

#### 3.1 退会リクエストAPI ✅
- [x] `POST /api/v1/withdrawal-requests`
  - ファイル: `k_back/app/api/v1/endpoints/withdrawal_requests.py`
  - 権限: ownerのみ
  - エラー: 403（権限なし）, 409（既存リクエストあり）
  - 認証: Cookie + CSRF
- [x] `GET /api/v1/withdrawal-requests`
  - 権限: app_adminのみ（全件）、owner（自事務所のみ）
- [x] `PATCH /api/v1/withdrawal-requests/{id}/approve`
  - 権限: app_adminのみ
  - エラー: 403（権限なし）, 404（リクエスト不存在）, 400（処理済み）
- [x] `PATCH /api/v1/withdrawal-requests/{id}/reject`
  - 権限: app_adminのみ
  - エラー: 403（権限なし）, 404（リクエスト不存在）, 400（処理済み）

#### 3.2 監査ログAPI（app_admin用）
- [ ] `GET /api/v1/admin/audit-logs`
  - 権限: app_adminのみ
  - パラメータ: office_id, target_type, action, actor_id, start_date, end_date, skip, limit
- [ ] `GET /api/v1/admin/audit-logs/cursor`
  - 権限: app_adminのみ
  - パラメータ: cursor, limit

#### 3.3 権限チェック追加
- [ ] `deps.py` に `require_app_admin()` 依存関係追加
- [ ] 既存の認証フローで削除済み事務所チェック追加

---

### Phase 4: フロントエンド（Phase 3と並行可能）

> **注記**: 既存の命名規則に従い、`admin`はオーナー（事務所管理者）用、`app-admin`はアプリ管理者用として区別する。

---

#### 4.1 app_admin認証画面

**ページ（Next.js App Router）:**
| パス | ファイル | 説明 |
|------|----------|------|
| `/auth/app-admin/login` | `k_front/app/auth/app-admin/login/page.tsx` | アプリ管理者ログインページ |
| `/auth/app-admin/signup` | `k_front/app/auth/app-admin/signup/page.tsx` | （オプション）初期管理者作成ページ |

**コンポーネント:**
| ファイル | 説明 |
|----------|------|
| `k_front/components/auth/app-admin/LoginForm.tsx` | ログインフォーム（メール/パスワード + MFA対応） |
| `k_front/components/auth/app-admin/SignupForm.tsx` | （オプション）初期管理者作成フォーム |

**実装詳細:**
- [ ] `k_front/app/auth/app-admin/login/page.tsx`
  - `AppAdminLoginForm`をインポートして表示
  - 認証成功後は`/app-admin`にリダイレクト
- [ ] `k_front/components/auth/app-admin/LoginForm.tsx`
  - 既存の`k_front/components/auth/admin/LoginForm.tsx`を参考に実装
  - Cookie + CSRF認証を使用
  - MFA検証フロー対応

---

#### 4.2 app_admin管理画面（ダッシュボード）

**ページ:**
| パス | ファイル | 説明 |
|------|----------|------|
| `/app-admin` | `k_front/app/(protected)/app-admin/page.tsx` | メインダッシュボード |

**コンポーネント:**
| ファイル | 説明 |
|----------|------|
| `k_front/components/protected/app-admin/AppAdminDashboard.tsx` | ダッシュボードメインコンポーネント（タブ管理） |

**実装詳細:**
- [ ] `k_front/app/(protected)/app-admin/page.tsx`
  - 認証チェック: `staff.role === 'app_admin'`のみアクセス可
  - 権限なしの場合は`/dashboard`へリダイレクト
  - `AppAdminDashboard`コンポーネントをレンダリング
- [ ] `k_front/components/protected/app-admin/AppAdminDashboard.tsx`
  - 5つのタブを管理: ログ、問い合わせ、承認リクエスト、お知らせ、事務所
  - 既存の`AdminMenu.tsx`を参考にタブUIを実装
  - タブ切り替え時に各タブコンポーネントをレンダリング

---

#### 4.3 タブコンポーネント

**配置ディレクトリ:** `k_front/components/protected/app-admin/tabs/`

| ファイル | タブ名 | 説明 |
|----------|--------|------|
| `AuditLogTab.tsx` | ログ | 監査ログ表示（30件ごとページネーション、フィルター機能） |
| `InquiriesTab.tsx` | 問い合わせ | スタッフからの問い合わせ一覧 |
| `ApprovalRequestsTab.tsx` | 承認リクエスト | 退会リクエスト承認/却下UI |
| `AnnouncementsTab.tsx` | お知らせ | 全スタッフへのお知らせ送信 |
| `OfficesTab.tsx` | 事務所 | 事務所一覧（名前検索、30件ごと） |

**実装詳細:**

- [ ] `k_front/components/protected/app-admin/tabs/AuditLogTab.tsx`
  - フィルター: target_type, action, actor_id, 日付範囲
  - ページネーション: オフセットベース（30件/ページ）
  - 無限スクロール: カーソルベースオプション
  - API: `GET /api/v1/admin/audit-logs`

- [ ] `k_front/components/protected/app-admin/tabs/InquiriesTab.tsx`
  - 未読/既読フィルター
  - 返信機能
  - API: `GET /api/v1/admin/inquiries`

- [ ] `k_front/components/protected/app-admin/tabs/ApprovalRequestsTab.tsx`
  - 退会リクエスト一覧表示
  - ステータス: pending, approved, rejected
  - 承認/却下ボタン + 却下理由入力
  - API: `GET /api/v1/withdrawal-requests`, `PATCH .../approve`, `PATCH .../reject`

- [ ] `k_front/components/protected/app-admin/tabs/AnnouncementsTab.tsx`
  - 送信フォーム: タイトル、本文
  - 送信履歴一覧
  - API: `POST /api/v1/announcements`

---

#### 4.4 オーナー側: 退会リクエスト送信

**既存ファイル修正:**
| ファイル | 修正内容 |
|----------|----------|
| `k_front/components/protected/admin/AdminMenu.tsx` | 事業所タブに「退会申請」ボタンを追加 |

**新規コンポーネント:**
| ファイル | 説明 |
|----------|------|
| `k_front/components/protected/admin/WithdrawalModal.tsx` | 退会申請モーダル |

**新規API関数:**
| ファイル | 説明 |
|----------|------|
| `k_front/lib/api/withdrawalRequests.ts` | 退会リクエストAPI呼び出し関数 |

**実装詳細:**

- [ ] `k_front/components/protected/admin/AdminMenu.tsx` の修正
  - 事業所タブ下部に「退会申請」セクションを追加
  - 赤い警告スタイルの「退会を申請する」ボタン
  - クリックで`WithdrawalModal`を表示
  - 状態管理: `showWithdrawalModal`, `isSubmittingWithdrawal`

- [ ] `k_front/components/protected/admin/WithdrawalModal.tsx`
  - モーダルUI（既存の編集モーダルを参考）
  - 入力フィールド: タイトル（必須）、退会理由（必須）
  - 警告文: 「退会申請後、アプリ管理者による承認が必要です。承認されると事務所データは論理削除され、30日後に完全削除されます。」
  - 送信ボタン、キャンセルボタン
  - エラー/成功メッセージ表示
  - props: `isOpen`, `onClose`, `onSuccess`

- [ ] `k_front/lib/api/withdrawalRequests.ts`
  ```typescript
  // 退会リクエスト作成
  export async function createWithdrawalRequest(data: {
    title: string;
    reason: string;
  }): Promise<WithdrawalRequestResponse>

  // （app_admin用）退会リクエスト一覧取得
  export async function getWithdrawalRequests(params?: {
    status?: 'pending' | 'approved' | 'rejected';
    skip?: number;
    limit?: number;
  }): Promise<PaginatedResponse<WithdrawalRequestResponse>>

  // （app_admin用）退会リクエスト承認
  export async function approveWithdrawalRequest(
    requestId: string
  ): Promise<ApprovalResponse>

  // （app_admin用）退会リクエスト却下
  export async function rejectWithdrawalRequest(
    requestId: string,
    reason: string
  ): Promise<ApprovalResponse>
  ```

---

#### 4.5 削除済み事務所対応

**新規コンポーネント:**
| ファイル | 説明 |
|----------|------|
| `k_front/components/auth/DeletedOfficeNotice.tsx` | 削除済み事務所通知コンポーネント |

**既存ファイル修正:**
| ファイル | 修正内容 |
|----------|----------|
| `k_front/components/auth/LoginForm.tsx` | 削除済み事務所のエラーハンドリング追加 |
| `k_front/lib/auth.ts` | ログインレスポンスに`is_office_deleted`フラグ対応 |

**実装詳細:**

- [ ] `k_front/components/auth/DeletedOfficeNotice.tsx`
  - 表示内容: 「お知らせ: ご利用の事務所は退会処理が完了しました。ご利用ありがとうございました。」
  - スタイル: 中央配置、情報カード風
  - サポート連絡先リンク（オプション）

- [ ] `k_front/components/auth/LoginForm.tsx` の修正
  - ログインAPI呼び出し後、レスポンスで`is_office_deleted: true`の場合
  - `DeletedOfficeNotice`コンポーネントを表示
  - ログイン処理を中断

- [ ] `k_front/lib/auth.ts` の修正
  - `LoginResponse`型に`is_office_deleted?: boolean`を追加
  - エラーハンドリング: 403で`office_deleted`コードの場合の処理

---

#### 4.6 型定義ファイル

**新規/修正ファイル:**
| ファイル | 説明 |
|----------|------|
| `k_front/types/withdrawalRequest.ts` | 退会リクエスト関連の型定義 |
| `k_front/types/auditLog.ts` | 監査ログ関連の型定義 |
| `k_front/types/staff.ts` | `StaffRole`に`app_admin`を追加 |

**型定義例:**
```typescript
// k_front/types/withdrawalRequest.ts
export interface WithdrawalRequestResponse {
  id: string;
  requester_staff_id: string;
  office_id: string;
  office_name: string;
  title: string;
  reason: string;
  status: 'pending' | 'approved' | 'rejected';
  reviewed_by_staff_id?: string;
  reviewed_at?: string;
  reviewer_notes?: string;
  created_at: string;
  updated_at: string;
}

// k_front/types/auditLog.ts
export interface AuditLogResponse {
  id: string;
  actor_id: string;
  actor_name: string;
  actor_role: string;
  action: string;
  target_type: string;
  target_id: string;
  office_id?: string;
  office_name?: string;
  ip_address: string;
  user_agent: string;
  details: Record<string, unknown>;
  created_at: string;
}
```

---

### Phase 5: 既存機能統合・リファクタリング 🔶 一部完了

#### 5.1 監査ログ統合 ✅
- [x] 既存の `staff_audit_logs` 記録箇所を `audit_logs` に変更
  - ファイル: `k_back/app/api/v1/endpoints/staffs.py` - `crud.audit_log.create_log()` に変更
- [x] 既存の `StaffAuditLog` モデルを非推奨化
  - ファイル: `k_back/app/models/_staff_audit_log_deprecated.py` - Base継承を削除してSQLAlchemy登録を無効化
  - ファイル: `k_back/app/crud/_crud_staff_audit_log_deprecated.py` - 非推奨化
- [x] `k_back/app/models/__init__.py` から `StaffAuditLog` インポートを削除
- [x] `k_back/app/crud/__init__.py` から `staff_audit_log` インポートを削除
- [ ] 既存の `office_audit_logs` 記録箇所を `audit_logs` に変更
- [x] `terms.agreed` アクションの追加（利用規約同意時）
  - ファイル: `k_back/app/api/v1/endpoints/terms.py:63-78`
  - `AuditLogTargetType` enum追加: `k_back/app/models/enums.py:268-273`

#### 5.2 承認リクエスト統合
- [ ] 既存の `role_change_requests` を `approval_requests` で管理するよう変更
- [ ] 既存の `employee_action_requests` を `approval_requests` で管理するよう変更
- [ ] 既存APIのリダイレクトまたは互換性維持

#### 5.3 利用規約更新
- [ ] プライバシーポリシーに「データの保持期間」セクション追加
- [ ] TermsModal.tsx のコンテンツ更新

---

### Phase 6: テスト 🔶 一部完了

#### 6.1 ユニットテスト
- [ ] `tests/models/test_audit_log.py`
- [ ] `tests/models/test_approval_request.py`
- [x] `tests/crud/test_crud_audit_log.py` ✅ （CRUD層テストの一部として実装）
- [x] `tests/crud/test_crud_approval_request.py` ✅ 30/30 パス
- [ ] `tests/crud/test_crud_office_soft_delete.py`

#### 6.2 Service層テスト ✅
- [x] `tests/services/test_withdrawal_service.py` ✅ 20/20 パス
  - スタッフ退会リクエスト作成
  - 事務所退会リクエスト作成
  - 承認・却下フロー
  - 退会実行（スタッフ物理削除、事務所論理削除）

#### 6.3 APIテスト
- [x] `tests/api/v1/test_withdrawal_requests.py` ✅ 実装済み
  - 正常系: リクエスト作成、承認、却下
  - 異常系: 権限エラー(403)、バリデーションエラー(422)
- [ ] `tests/api/v1/test_admin_audit_logs.py`
- [ ] `tests/api/v1/test_admin_offices.py`

#### 6.4 E2Eテスト（オプション）
- [ ] 退会フロー全体のE2Eテスト

---

### 優先度・依存関係まとめ

```
Phase 1 (DB/モデル) ─┬─> Phase 2 (CRUD/サービス) ─> Phase 3 (API)
                     │
                     └─> Phase 4 (フロントエンド) ─────────────────┐
                                                                   │
Phase 5 (リファクタリング) <───────────────────────────────────────┘
                     │
                     v
              Phase 6 (テスト)
```

### 実装順序の推奨
1. **最初**: Phase 1.1（マイグレーション）- 全ての土台
2. **次に**: Phase 1.2 + Phase 2 - バックエンドコア機能
3. **並行**: Phase 3（API）+ Phase 4（フロントエンド）
4. **最後**: Phase 5（リファクタリング）+ Phase 6（テスト） 