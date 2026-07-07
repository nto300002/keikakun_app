# app_admin（アプリ管理者）機能

**最終更新: 2025-11-27**

## 概要

app_adminは、システム全体を管理するアプリケーション管理者向けの機能です。

### 主な機能
- 全事務所の監視・管理
- 監査ログの可視化
    - "staff.deleted", "office.updated", "withdrawal.approved", "terms.agreed": フィルタリング 
- 問い合わせ対応
- 退会リクエストの承認/却下
- お知らせ送信

---

## 実装状況

### バックエンド

| 機能 | 状況 | 備考 |
|------|------|------|
| `AuditLogTargetType` enum | ✅ 完了 | `k_back/app/models/enums.py:268-273` |
| `terms.agreed` 監査ログ | ✅ 完了 | `k_back/app/api/v1/endpoints/terms.py:63-78` |
| 退会リクエストAPI | ✅ 完了 | Phase 3 完了（withdrawal.md参照） |
| 事務所管理API | ⬜ 未着手 | Phase 3.3 |
| 監査ログAPI | ⬜ 未着手 | Phase 3.2 |

### フロントエンド

| 機能 | 状況 | 備考 |
|------|------|------|
| app-admin専用レイアウト | ✅ 完了 | `k_front/app/(protected)/app-admin/layout.tsx` |
| app_admin認証画面 | ⬜ 未着手 | 合言葉対応が必要 |
| ダッシュボード | ⬜ 未着手 | 5タブ構成 |
| 事務所一覧タブ | ⬜ 未着手 | - |
| 事務所プレビュー | ⬜ 未着手 | - |

---

## Phase 3.3: 事務所管理API（app_admin用）

### エンドポイント一覧

| メソッド | エンドポイント | 権限 | 説明 |
|----------|---------------|------|------|
| GET | `/api/v1/admin/offices` | app_admin | 事務所一覧取得（名前検索、ページネーション対応） |
| GET | `/api/v1/admin/offices/{id}` | app_admin | 事務所詳細取得（事務所情報+スタッフ一覧+同意状況） |

### 実装タスク

- [ ] `GET /api/v1/admin/offices`
  - 権限: app_adminのみ
  - パラメータ: search（名前検索）, skip, limit
  - レスポンス: 事務所一覧（30件/ページ）

- [ ] `GET /api/v1/admin/offices/{id}`
  - 権限: app_adminのみ
  - レスポンス: 事務所情報 + スタッフ一覧 + 同意状況

- [ ] `deps.py` に `require_app_admin()` 依存関係追加

- [ ] 既存の認証フローで削除済み事務所チェック追加

---

## Phase 4: フロントエンド（事務所管理機能）

### 4.3 OfficesTab（事務所一覧タブ）

**ファイル**: `k_front/components/protected/app-admin/tabs/OfficesTab.tsx`

#### 機能要件
- 事務所一覧をテーブル形式で表示
- 名前検索機能（デバウンス処理）
- ページネーション（30件/ページ）
- 行クリックで事務所プレビューページへ遷移

#### API
- `GET /api/v1/admin/offices`

#### 実装タスク
- [ ] 事務所一覧テーブルコンポーネント作成
- [ ] 名前検索フィールド実装（デバウンス処理）
- [ ] ページネーションUI実装
- [ ] 行クリックイベントで `/app-admin/offices/[officeId]` へ遷移
- [ ] ローディング・エラー状態の処理

---

### 4.4 事務所プレビュー画面

**ページパス**: `/app-admin/offices/[officeId]`
**ページファイル**: `k_front/app/(protected)/app-admin/offices/[officeId]/page.tsx`
**コンポーネント**: `k_front/components/protected/app-admin/OfficePreview.tsx`

#### 機能要件
- 事務所基本情報表示
  - 名前
  - 種別
  - 住所
  - 電話番号
  - メールアドレス
- スタッフ一覧テーブル
  - 名前
  - メールアドレス
  - 役割（role）
  - MFA有効/無効状態
- 利用規約同意状況の可視化
  - 同意済み/未同意バッジ表示
- 戻るボタン（事務所一覧へ）

#### API
- `GET /api/v1/admin/offices/{id}`

#### 実装タスク

**ページコンポーネント** (`page.tsx`):
- [ ] 動的ルート: `officeId`をパラメータとして取得
- [ ] 認証チェック: app_adminのみアクセス可
- [ ] `OfficePreview`コンポーネントに`officeId`をプロップとして渡す

**プレビューコンポーネント** (`OfficePreview.tsx`):
- [ ] 事務所基本情報表示セクション
- [ ] スタッフ一覧テーブル
- [ ] 利用規約同意状況の可視化（同意済み/未同意バッジ）
- [ ] 戻るボタン実装
- [ ] ローディング・エラー状態の処理

---

## 型定義

**新規ファイル**: `k_front/types/office.ts`（既存の場合は拡張）

```typescript
// 事務所一覧レスポンス
export interface OfficeListResponse {
  id: string;
  name: string;
  office_type: string;
  is_deleted: boolean;
  created_at: string;
  staff_count: number; // スタッフ数
}

// 事務所詳細レスポンス
export interface OfficeDetailResponse {
  id: string;
  name: string;
  office_type: string;
  address: string;
  phone: string;
  email: string;
  is_deleted: boolean;
  created_at: string;
  updated_at: string;
  staffs: StaffInOffice[];
  terms_agreements: TermsAgreementStatus[];
}

// 事務所所属スタッフ
export interface StaffInOffice {
  id: string;
  full_name: string;
  email: string;
  role: StaffRole;
  is_mfa_enabled: boolean;
  is_email_verified: boolean;
}

// 利用規約同意状況
export interface TermsAgreementStatus {
  staff_id: string;
  staff_name: string;
  terms_version: string;
  privacy_version: string;
  agreed_at: string;
}
```

---

## セキュリティ要件

### 権限チェック
- すべてのエンドポイントで `StaffRole.app_admin` チェック必須
- 権限がない場合は403 Forbiddenを返す

### 監査ログ
以下の操作を監査ログに記録:
- 事務所一覧取得: `office.list_viewed`
- 事務所詳細取得: `office.detail_viewed`

---

## 監査ログ target_type enum

監査ログの `target_type` カラムに使用する列挙型。

**定義場所**: `k_back/app/models/enums.py`

```python
class AuditLogTargetType(str, enum.Enum):
    """監査ログの対象リソースタイプ"""
    staff = 'staff'                           # スタッフ関連操作
    office = 'office'                         # 事務所関連操作
    withdrawal_request = 'withdrawal_request' # 退会リクエスト関連操作
    terms_agreement = 'terms_agreement'       # 利用規約同意記録
```

### target_type 一覧

| target_type | 説明 | 使用例 |
|------------|------|--------|
| `staff` | スタッフ関連操作 | スタッフ削除、作成、更新、パスワード変更 |
| `office` | 事務所関連操作 | 事務所情報更新、論理削除 |
| `withdrawal_request` | 退会リクエスト関連操作 | 退会申請、承認、却下、実行 |
| `terms_agreement` | 利用規約同意記録 | 利用規約・プライバシーポリシー同意 |

### action 命名規則

`{target_type}.{operation}` の形式で命名。

#### staff 関連

| action | 説明 |
|--------|------|
| `staff.created` | スタッフ作成 |
| `staff.updated` | スタッフ情報更新 |
| `staff.deleted` | スタッフ削除 |
| `staff.password_changed` | パスワード変更 |

#### office 関連

| action | 説明 |
|--------|------|
| `office.created` | 事務所作成 |
| `office.updated` | 事務所情報更新 |
| `office.soft_deleted` | 事務所論理削除（退会） |

#### withdrawal_request 関連

| action | 説明 |
|--------|------|
| `withdrawal.requested` | 退会申請 |
| `withdrawal.approved` | 退会承認 |
| `withdrawal.rejected` | 退会却下 |
| `withdrawal.executed` | 退会実行 |

#### terms_agreement 関連

| action | 説明 |
|--------|------|
| `terms.agreed` | 利用規約・プライバシーポリシー同意 |

### 実装ファイル

#### AuditLog モデル
- `k_back/app/models/staff_profile.py`

#### CRUD
- `k_back/app/crud/crud_audit_log.py`

#### 利用規約同意API
- `k_back/app/api/v1/endpoints/terms.py`

```python
# 監査ログ記録例（terms.py）
await crud.audit_log.create_log(
    db=db,
    actor_id=current_user.id,
    action="terms.agreed",
    target_type=AuditLogTargetType.terms_agreement.value,
    target_id=agreement.id,
    office_id=None,  # 利用規約同意は事務所に紐づかない
    ip_address=ip_address,
    user_agent=user_agent,
    details={
        "terms_version": agreement_data.terms_version,
        "privacy_version": agreement_data.privacy_version,
        "agreed_at": agreement.terms_of_service_agreed_at.isoformat()
    }
)
```

### audit_logs テーブル設計

| カラム | 型 | 説明 |
|--------|-----|------|
| id | UUID | 主キー |
| staff_id | UUID | 操作実行者のスタッフID |
| actor_role | VARCHAR(50) | 実行時のロール |
| action | VARCHAR(100) | アクション種別 |
| target_type | VARCHAR(50) | 対象リソースタイプ（enum値） |
| target_id | UUID | 対象リソースのID |
| office_id | UUID | 事務所ID（app_adminはNULL可） |
| ip_address | VARCHAR(45) | 操作元IPアドレス |
| user_agent | TEXT | 操作元User-Agent |
| details | JSONB | 変更内容（JSON形式） |
| timestamp | TIMESTAMP WITH TIME ZONE | 記録日時 |
| is_test_data | BOOLEAN | テストデータフラグ |

### エラーハンドリング
- 404: 事務所が見つかりません
- 403: 権限がありません
- 500: 内部サーバーエラー

---

## 実装優先度

| タスク | 優先度 | 依存関係 |
|--------|--------|----------|
| Phase 3.3 API実装 | 高 | Phase 1, 2 完了後 |
| OfficesTab実装 | 高 | Phase 3.3 完了後 |
| 事務所プレビュー実装 | 高 | Phase 3.3 完了後 |
| 型定義追加 | 高 | フロントエンド実装前 |

---

## テスト計画

### API層テスト
- [ ] `tests/api/v1/test_admin_offices.py`
  - 正常系: 事務所一覧取得、事務所詳細取得
  - 異常系: 権限エラー(403)、404エラー
  - フィルター・検索機能のテスト
  - ページネーションのテスト

### フロントエンドテスト（オプション）
- [ ] OfficesTab のユニットテスト
- [ ] OfficePreview のユニットテスト
- [ ] E2E: 事務所一覧→プレビュー遷移のテスト

---

## 次のアクション

### 優先度: 高

1. **app_admin認証画面（合言葉対応）**
   - `k_front/app/auth/app-admin/login/page.tsx`
   - `k_front/components/auth/app-admin/LoginForm.tsx`
   - 合言葉入力フィールド追加
   - バックエンド: `POST /api/v1/auth/token` への合言葉検証追加

2. **app_adminダッシュボード**
   - `k_front/app/(protected)/app-admin/page.tsx`
   - `k_front/components/protected/app-admin/AppAdminDashboard.tsx`
   - 5タブ: ログ、問い合わせ、承認リクエスト、お知らせ、事務所

3. **退会リクエスト承認タブ（ApprovalRequestsTab）**
   - `k_front/components/protected/app-admin/tabs/ApprovalRequestsTab.tsx`
   - API: `GET /api/v1/withdrawal-requests`（実装済み）
   - 承認/却下ボタン

### 優先度: 中

4. **オーナー側: 退会リクエスト送信モーダル**
   - `k_front/components/protected/admin/WithdrawalModal.tsx`
   - `AdminMenu.tsx` への統合

5. **事務所管理API（Phase 3.3）**
   - `GET /api/v1/admin/offices`
   - `GET /api/v1/admin/offices/{id}`

### 優先度: 低

6. **監査ログAPI（Phase 3.2）**
   - `GET /api/v1/admin/audit-logs`
   - カーソルベースページネーション

7. **事務所一覧・プレビュー画面**
   - OfficesTab
   - OfficePreview

## 追加タスク(優先度: 基本API完了後)
- 監査ログapi
- "staff.deleted", "office.updated", "withdrawal.approved", "terms.agreed": フィルタリング 
target_typeにおけるフィルタリングを実装: バックエンドのk_back/app/crud/crud_audit_log.pyにて絞り込みメソッドを実装
k_back/app/api/v1/endpoints/admin_offices.pyに
GET filtering_logsを設定
複合条件なし
取得上限(50)とページネーション設定
50件以降を読み込もうとした場合: 次の50件の読み込み