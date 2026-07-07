<!--
作業ブランチ: issue/feature-管理者のoffice操作
注意: このファイルに変更を加える場合、必ず上記に現在作業しているブランチ名を明記し、変更はそのブランチへ push してください。
-->

# スタッフ削除機能

管理者（Owner）向けのスタッフ削除機能の要件定義兼タスクリスト

---

## 1. 概要

管理者権限を持つユーザー（Owner）が、AdminMenu画面から所属スタッフを削除できるようにします。

**主要機能**:
- AdminMenuの「事務所タブ」から個別スタッフを削除
- 削除前の確認ダイアログ表示
- 削除時の関連データ処理（論理削除）
- 削除されたスタッフのセッション無効化
- 監査ログの記録

**既存実装との統合**:
- AdminMenu.tsx の事務所タブに統合
- 既存のスタッフ一覧テーブルに「削除」ボタンを追加

---

## 2. 機能要件

### 2.1 スタッフ削除機能

#### 2.1.1 機能概要
- AdminMenuの「事務所タブ」に表示されるスタッフ一覧から、各スタッフを削除できる
- 削除は論理削除（`is_deleted` フラグ）で実装し、データは物理的には残す
- 削除されたスタッフは即座にログアウトされ、再ログイン不可になる

#### 2.1.2 UI要件

**表示場所**
- AdminMenu.tsx > 事務所タブ > スタッフ一覧テーブル > 操作列

**UIコンポーネント**

| 要素 | 説明 |
|------|------|
| 削除ボタン | 各スタッフ行に「🗑️ 削除」ボタンを表示 |
| 確認ダイアログ | 削除実行前に確認ダイアログを表示 |
| ローディング状態 | 処理中は spinner アニメーションと「削除中...」テキストを表示 |
| 成功メッセージ | 削除完了後に「スタッフを削除しました」と表示 |

**削除ボタンの表示制御**
- 自分自身の行には削除ボタンを表示しない
- Ownerのみに削除ボタンを表示（Manager、Employeeには非表示）

**操作フロー**

```
1. Owner が「削除」ボタンをクリック
   ↓
2. 確認ダイアログ表示
   「スタッフ [姓 名] を削除しますか？
    削除すると、このスタッフはログインできなくなります。
    この操作は取り消せません。」
   [削除する] [キャンセル]
   ↓
3. [削除する]を選択
   ↓
4. API リクエスト送信（DELETE /api/v1/auth/staffs/{staff_id}）
   ボタンをローディング状態に変更
   ↓
5. レスポンス受信
   ↓
6. 成功時：
   - スタッフリストを再取得して表示を更新
   - 成功メッセージ表示「スタッフを削除しました」
   - 削除されたスタッフの行がリストから消える

   失敗時：
   - エラーメッセージ表示
   - ボタンを元の状態に戻す
```

#### 2.1.3 権限要件
- **許可ロール**: Owner のみ
- **禁止ロール**: Manager、Employee（403 Forbidden）
- **依存性注入**: `require_owner`

#### 2.1.4 削除制約
- **自分自身は削除不可**: 操作ユーザーと削除対象が同一の場合はエラー（400 Bad Request）
- **最後のOwnerは削除不可**: 事務所に残るOwnerが1人の場合、そのOwnerは削除不可（409 Conflict）
- **別の事務所のスタッフは削除不可**: 同じ事務所に所属していることを確認（403 Forbidden）

#### 2.1.5 バリデーション
- スタッフIDの存在確認
- 削除対象スタッフが同じ事務所に所属していることを確認
- 既に削除済み（`is_deleted=true`）の場合はエラー
- 自分自身を削除しようとした場合はエラー
- 最後のOwnerを削除しようとした場合はエラー

---

## 3. 非機能要件

### 3.1 セキュリティ

#### 3.1.1 認証・認可
- すべてのエンドポイントでJWT認証必須
- ロールベースのアクセス制御（RBAC）
  - スタッフ削除: Owner のみ
- 監査ログの記録（操作者、操作日時、削除されたスタッフ、IPアドレス）

#### 3.1.2 データ保護
- 論理削除の実装（`is_deleted` フラグ）
- 削除されたスタッフのデータは保持（監査・復旧目的）
- 削除時刻を記録（`deleted_at` タイムスタンプ）

#### 3.1.3 セッション無効化
- 削除されたスタッフの全トークン（アクセストークン、リフレッシュトークン）を無効化
- 削除後、対象スタッフは即座にログアウトされる
- 削除されたスタッフは再ログイン不可（`is_deleted=true` のチェック）

### 3.2 パフォーマンス
- API レスポンスタイム: 200ms以内（通常時）
- トランザクション処理: スタッフ削除とトークン無効化を同一トランザクションで実行

### 3.3 ユーザビリティ
- エラーメッセージは日本語で明確に表示
- 削除の確認ダイアログで操作の重大性を明示
- ローディング状態の視覚的フィードバック
- 操作完了後の成功メッセージ表示

---

## 4. API設計

### 4.1 スタッフ削除

**エンドポイント**: `DELETE /api/v1/auth/staffs/{staff_id}`

**権限**: Owner のみ（`require_owner`）

**パスパラメータ**:
- `staff_id` (UUID): 削除対象スタッフのID

**リクエストボディ**: なし

**レスポンス**:
```json
{
  "message": "スタッフを削除しました",
  "staff_id": "uuid",
  "deleted_at": "2024-01-01T00:00:00Z"
}
```

**ステータスコード**:
- `200 OK`: 成功
- `400 Bad Request`: 自分自身を削除しようとした、既に削除済み
- `403 Forbidden`: 権限不足、別の事務所のスタッフ
- `404 Not Found`: スタッフが存在しない
- `409 Conflict`: 最後のOwnerを削除しようとした

**処理フロー**:
```python
1. 認証・認可チェック（Owner のみ）
2. スタッフの存在確認
3. 同じ事務所に所属していることを確認
4. 自分自身でないことを確認
5. 既に削除済みでないことを確認
6. 最後のOwnerでないことを確認
7. トランザクション開始
   7-1. Staff.is_deleted = True
   7-2. Staff.deleted_at = datetime.utcnow()
   7-3. 削除されたスタッフの全トークンを無効化
   7-4. 監査ログに記録
8. トランザクションコミット
9. レスポンスを返す
```

---

## 5. フロントエンド設計

### 5.1 AdminMenu.tsx の修正

#### 5.1.1 削除機能の追加

**追加State**
```typescript
const [showDeleteConfirmModal, setShowDeleteConfirmModal] = useState<boolean>(false);
const [targetDeleteStaff, setTargetDeleteStaff] = useState<StaffResponse | null>(null);
const [isDeletingStaff, setIsDeletingStaff] = useState<boolean>(false);
```

**削除確認ダイアログの追加**
```tsx
{showDeleteConfirmModal && targetDeleteStaff && (
  <Modal isOpen={showDeleteConfirmModal} onClose={() => setShowDeleteConfirmModal(false)}>
    <h3>スタッフ削除の確認</h3>
    <p className="warning-text">
      スタッフ「{targetDeleteStaff.last_name} {targetDeleteStaff.first_name}」を削除しますか？
    </p>
    <p className="warning-text">
      削除すると、このスタッフはログインできなくなります。<br />
      この操作は取り消せません。
    </p>
    <div className="modal-buttons">
      <button
        onClick={handleDeleteConfirm}
        disabled={isDeletingStaff}
        className="btn-danger"
      >
        {isDeletingStaff ? '削除中...' : '削除する'}
      </button>
      <button
        onClick={() => setShowDeleteConfirmModal(false)}
        disabled={isDeletingStaff}
        className="btn-secondary"
      >
        キャンセル
      </button>
    </div>
  </Modal>
)}
```

**削除ボタンの追加（スタッフ一覧テーブル）**
```tsx
{/* 操作列 */}
<td>
  {/* 既存のMFA操作ボタン */}
  {staff.is_mfa_enabled ? (
    <button onClick={() => handleStaffMfaDisable(staff)}>無効化</button>
  ) : (
    <button onClick={() => handleStaffMfaEnable(staff)}>有効化</button>
  )}

  {/* 削除ボタン（自分自身以外、かつOwnerのみ表示） */}
  {currentUser?.role === 'Owner' && staff.id !== currentUser.id && (
    <button
      onClick={() => handleDeleteStaffClick(staff)}
      title="このスタッフを削除します"
      className="btn-delete"
    >
      🗑️ 削除
    </button>
  )}
</td>
```

**削除処理の実装**
```typescript
const handleDeleteStaffClick = (staff: StaffResponse) => {
  setTargetDeleteStaff(staff);
  setShowDeleteConfirmModal(true);
};

const handleDeleteConfirm = async () => {
  if (!targetDeleteStaff) return;

  try {
    setIsDeletingStaff(true);
    await apiClient.deleteStaff(targetDeleteStaff.id);

    setMessage('スタッフを削除しました');
    setShowDeleteConfirmModal(false);
    setTargetDeleteStaff(null);

    // スタッフリストを再取得
    await fetchStaffList();
  } catch (error: any) {
    if (error.response?.status === 400) {
      setError('自分自身は削除できません');
    } else if (error.response?.status === 409) {
      setError('最後のOwnerは削除できません');
    } else if (error.response?.status === 403) {
      setError('この操作を実行する権限がありません');
    } else {
      setError('スタッフの削除に失敗しました');
    }
  } finally {
    setIsDeletingStaff(false);
  }
};
```

### 5.2 API クライアントの追加

**lib/auth.ts への追加**
```typescript
// スタッフ削除
deleteStaff: (staffId: string): Promise<{message: string, staff_id: string, deleted_at: string}> => {
  return http.delete(`${API_V1_PREFIX}/auth/staffs/${staffId}`);
},
```

---

## 6. データベース設計

### 6.1 Staff モデルの拡張

**追加カラム**
```python
class Staff(Base):
    # 既存フィールド
    id: Mapped[UUID]
    email: Mapped[str]
    first_name: Mapped[str]
    last_name: Mapped[str]
    role: Mapped[StaffRole]
    office_id: Mapped[UUID]

    # 論理削除用フィールド（新規追加）
    is_deleted: Mapped[bool] = mapped_column(default=False, nullable=False)
    deleted_at: Mapped[Optional[datetime]] = mapped_column(default=None)
    deleted_by: Mapped[Optional[UUID]] = mapped_column(ForeignKey("staff.id"), default=None)
```

**インデックス追加**
```sql
CREATE INDEX idx_staff_is_deleted ON staff(is_deleted);
CREATE INDEX idx_staff_office_id_is_deleted ON staff(office_id, is_deleted);
```

### 6.2 監査ログの拡張

**StaffAuditLog モデル（新規作成推奨）**
```python
class StaffAuditLog(Base):
    __tablename__ = "staff_audit_log"

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    staff_id: Mapped[UUID] = mapped_column(ForeignKey("staff.id"))
    action: Mapped[str]  # 'deleted', 'created', 'updated', etc.
    performed_by: Mapped[UUID] = mapped_column(ForeignKey("staff.id"))
    ip_address: Mapped[Optional[str]]
    user_agent: Mapped[Optional[str]]
    details: Mapped[Optional[str]]  # JSON形式で詳細情報
    created_at: Mapped[datetime] = mapped_column(default=datetime.utcnow)
```

### 6.3 トークン無効化

**RefreshToken モデルの拡張**
```python
class RefreshToken(Base):
    # 既存フィールド
    id: Mapped[UUID]
    token: Mapped[str]
    staff_id: Mapped[UUID]
    expires_at: Mapped[datetime]

    # 追加フィールド（推奨）
    is_revoked: Mapped[bool] = mapped_column(default=False)
    revoked_at: Mapped[Optional[datetime]]
```

---

## 7. セキュリティ考慮事項

### 7.1 権限チェック

**スタッフ削除エンドポイント**
```python
@router.delete("/staffs/{staff_id}")
async def delete_staff(
    staff_id: UUID,
    request: Request,
    db: AsyncSession = Depends(deps.get_db),
    current_user: models.Staff = Depends(deps.require_owner),
):
    # 対象スタッフの取得
    target_staff = await crud.staff.get(db, id=staff_id)
    if not target_staff:
        raise HTTPException(404, detail=messages.STAFF_NOT_FOUND)

    # 既に削除済みチェック
    if target_staff.is_deleted:
        raise HTTPException(400, detail="このスタッフは既に削除されています")

    # 同じ事務所に所属していることを確認
    if target_staff.office_id != current_user.office_id:
        raise HTTPException(403, detail=messages.STAFF_DIFFERENT_OFFICE)

    # 自分自身でないことを確認
    if target_staff.id == current_user.id:
        raise HTTPException(400, detail="自分自身は削除できません")

    # 最後のOwnerでないことを確認
    if target_staff.role == StaffRole.Owner:
        owner_count = await crud.staff.count_owners_in_office(
            db,
            office_id=current_user.office_id,
            exclude_deleted=True
        )
        if owner_count <= 1:
            raise HTTPException(409, detail="最後のOwnerは削除できません")

    # 削除処理（トランザクション）
    async with db.begin():
        # 論理削除
        target_staff.is_deleted = True
        target_staff.deleted_at = datetime.utcnow()
        target_staff.deleted_by = current_user.id

        # 全トークンを無効化
        await crud.refresh_token.revoke_all_by_staff(db, staff_id=staff_id)

        # 監査ログに記録
        audit_log = models.StaffAuditLog(
            staff_id=staff_id,
            action="deleted",
            performed_by=current_user.id,
            ip_address=request.client.host,
            user_agent=request.headers.get("user-agent"),
            details=json.dumps({
                "deleted_staff_email": target_staff.email,
                "deleted_staff_name": f"{target_staff.last_name} {target_staff.first_name}",
                "deleted_staff_role": target_staff.role.value,
            })
        )
        db.add(audit_log)

    return {
        "message": "スタッフを削除しました",
        "staff_id": str(staff_id),
        "deleted_at": target_staff.deleted_at.isoformat(),
    }
```

### 7.2 認証時の削除チェック

**ログイン時のバリデーション**
```python
# app/api/v1/endpoints/auth.py
@router.post("/login")
async def login(...):
    # 既存の認証処理
    staff = await authenticate_staff(db, email, password)

    # 削除済みスタッフのログイン拒否
    if staff.is_deleted:
        raise HTTPException(403, detail="このアカウントは削除されています")

    # トークン発行
    ...
```

**トークン検証時のチェック**
```python
# app/api/deps.py
async def get_current_user(...):
    # 既存のトークン検証
    staff = await get_staff_from_token(db, token)

    # 削除済みスタッフのアクセス拒否
    if staff.is_deleted:
        raise HTTPException(403, detail="このアカウントは削除されています")

    return staff
```

### 7.3 監査ログの記録

**削除操作の詳細記録**
```python
# 監査ログに以下の情報を記録
audit_log_details = {
    "deleted_staff_id": str(staff_id),
    "deleted_staff_email": target_staff.email,
    "deleted_staff_name": f"{target_staff.last_name} {target_staff.first_name}",
    "deleted_staff_role": target_staff.role.value,
    "performed_by_id": str(current_user.id),
    "performed_by_email": current_user.email,
    "ip_address": request.client.host,
    "user_agent": request.headers.get("user-agent"),
    "timestamp": datetime.utcnow().isoformat(),
}
```

---

## 8. エラーハンドリング

### 8.1 バックエンドエラーメッセージ（日本語）

**messages/ja.py への追加**
```python
# スタッフ削除
STAFF_ALREADY_DELETED = "このスタッフは既に削除されています"
STAFF_CANNOT_DELETE_SELF = "自分自身は削除できません"
STAFF_CANNOT_DELETE_LAST_OWNER = "最後のOwnerは削除できません"
STAFF_DELETE_SUCCESS = "スタッフを削除しました"
ACCOUNT_DELETED = "このアカウントは削除されています"
```

### 8.2 フロントエンドエラー表示

**エラーメッセージの表示パターン**
```typescript
try {
  await apiClient.deleteStaff(staffId);
  setMessage('スタッフを削除しました');
  await fetchStaffList();
} catch (error: any) {
  if (error.response?.status === 400) {
    const detail = error.response.data.detail;
    if (detail.includes('自分自身')) {
      setError('自分自身は削除できません');
    } else if (detail.includes('既に削除')) {
      setError('このスタッフは既に削除されています');
    } else {
      setError(detail || 'バリデーションエラーが発生しました');
    }
  } else if (error.response?.status === 403) {
    setError('この操作を実行する権限がありません');
  } else if (error.response?.status === 409) {
    setError('最後のOwnerは削除できません');
  } else {
    setError('スタッフの削除に失敗しました');
  }
}
```

---

## 9. テスト計画

### 9.1 バックエンドテスト

#### 9.1.1 スタッフ削除エンドポイント

**正常系テスト**
- ✅ Owner が同じ事務所のスタッフを削除できる
- ✅ 削除されたスタッフの `is_deleted` が `True` になる
- ✅ 削除されたスタッフの `deleted_at` が設定される
- ✅ 削除されたスタッフの全トークンが無効化される
- ✅ 監査ログが正しく記録される

**異常系テスト**
- ❌ Manager がスタッフ削除を試みると 403 Forbidden
- ❌ Employee がスタッフ削除を試みると 403 Forbidden
- ❌ 別の事務所のスタッフを削除しようとすると 403 Forbidden
- ❌ 存在しないスタッフIDを指定すると 404 Not Found
- ❌ 自分自身を削除しようとすると 400 Bad Request
- ❌ 既に削除済みのスタッフを削除しようとすると 400 Bad Request
- ❌ 最後のOwnerを削除しようとすると 409 Conflict

**セキュリティテスト**
- ✅ 削除されたスタッフはログインできない
- ✅ 削除されたスタッフのトークンは無効化される
- ✅ 削除されたスタッフのリフレッシュトークンは使用できない

### 9.2 フロントエンドテスト

**削除機能UI**
- ✅ Ownerのみに削除ボタンが表示される
- ✅ 自分自身の行には削除ボタンが表示されない
- ✅ 削除ボタンクリック時に確認ダイアログが表示される
- ✅ 確認ダイアログに対象スタッフ名が表示される
- ✅ 削除中はローディング状態が表示される
- ✅ 削除成功時にスタッフリストが更新される
- ✅ 削除成功時にメッセージが表示される
- ✅ エラー時にエラーメッセージが表示される

---

## 10. 実装タスクリスト

### Phase 1: バックエンド実装

#### タスク1: データベーススキーマ拡張
- [ ] Staff モデルに `is_deleted`, `deleted_at`, `deleted_by` カラム追加
- [ ] マイグレーションファイル作成
- [ ] インデックス追加（`idx_staff_is_deleted`, `idx_staff_office_id_is_deleted`）
- [ ] StaffAuditLog モデル作成（推奨）
- [ ] RefreshToken モデルに `is_revoked`, `revoked_at` 追加（推奨）

#### タスク2: CRUD操作の実装
- [ ] `crud/staff.py` に `count_owners_in_office()` メソッド追加
- [ ] `crud/staff.py` に論理削除フィルタリング機能追加
- [ ] `crud/refresh_token.py` に `revoke_all_by_staff()` メソッド追加

#### タスク3: スタッフ削除エンドポイントの作成
- [ ] `DELETE /api/v1/auth/staffs/{staff_id}` エンドポイント実装
- [ ] 権限チェック（Owner のみ）
- [ ] バリデーション（自分自身、最後のOwner、同じ事務所）
- [ ] トランザクション処理（削除 + トークン無効化 + 監査ログ）

#### タスク4: 認証・認可の修正
- [ ] `get_current_user()` に削除済みチェック追加
- [ ] ログイン処理に削除済みチェック追加
- [ ] スタッフ一覧取得で削除済みスタッフを除外

#### タスク5: エラーメッセージの日本語化
- [ ] `messages/ja.py` への追加

### Phase 2: フロントエンド実装

#### タスク6: AdminMenu.tsx の修正
- [ ] 削除ボタンの追加（自分自身とOwnerチェック）
- [ ] 削除確認ダイアログの実装
- [ ] 削除処理ハンドラーの実装
- [ ] ローディング状態の実装
- [ ] エラーハンドリング

#### タスク7: APIクライアントの追加
- [ ] `lib/auth.ts` に `deleteStaff()` メソッド追加
- [ ] 型定義の追加

### Phase 3: テスト

#### タスク8: バックエンドテスト
- [ ] 正常系テスト（削除成功）
- [ ] 異常系テスト（権限、バリデーション）
- [ ] セキュリティテスト（削除後のログイン拒否）
- [ ] トランザクションテスト

#### タスク9: フロントエンドテスト
- [ ] 削除ボタンの表示制御テスト
- [ ] 確認ダイアログのテスト
- [ ] エラーハンドリングのテスト

### Phase 4: ドキュメント・レビュー

#### タスク10: ドキュメント更新
- [ ] APIドキュメントの更新（OpenAPI仕様）
- [ ] README の更新

#### タスク11: コードレビュー
- [ ] セキュリティレビュー
- [ ] パフォーマンスレビュー

---

## 11. 参考情報

### 11.1 既存実装の参照先

**AdminMenu.tsx**
- ファイルパス: `/k_front/components/protected/admin/AdminMenu.tsx`
- スタッフ一覧テーブル: 行686-722

**Auth エンドポイント**
- ファイルパス: `/k_back/app/api/v1/endpoints/auth.py`
- ログイン処理、トークン検証

**依存性注入**
- ファイルパス: `/k_back/app/api/deps.py`
- `require_owner`: 行189-199
- `get_current_user`: トークン検証

**Staff モデル**
- ファイルパス: `/k_back/app/models/staff.py`

**RefreshToken モデル**
- ファイルパス: `/k_back/app/models/refresh_token.py`

### 11.2 関連ドキュメント
- 事務所管理機能設計: `/md_files_design_note/task/3_office_action/office_action.md`
- エラーメッセージ定義: `/k_back/app/messages/ja.py`

---

## 12. まとめ

本要件定義では、管理者向けのスタッフ削除機能を実装します：

**主要機能**:
1. Owner のみがスタッフを削除可能
2. 論理削除による安全なデータ保持
3. 削除されたスタッフの即座のセッション無効化
4. 詳細な監査ログの記録

**セキュリティ対策**:
- 自分自身は削除不可
- 最後のOwnerは削除不可
- 削除後の即座のログアウト
- 削除済みアカウントのログイン拒否

この機能により、Owner は事務所のスタッフを安全に管理できるようになります。
