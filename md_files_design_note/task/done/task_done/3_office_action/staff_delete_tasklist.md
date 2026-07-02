# スタッフ削除機能 実装タスクリスト

**作業ブランチ**: `issue/feature-管理者_事務所情報変更機能`

**最終更新日**: 2024-11-24

---

## 目次

1. [実装タスク一覧](#1-実装タスク一覧)
2. [セキュリティレビュー項目](#2-セキュリティレビュー項目)
3. [SQLAlchemyトランザクション管理レビュー項目](#3-sqlalchemyトランザクション管理レビュー項目)
4. [必須機能網羅性レビュー項目](#4-必須機能網羅性レビュー項目)

---

## 1. 実装タスク一覧

### Phase 1: データベース設計・マイグレーション

#### タスク 1.1: Staffモデル拡張
- [ ] `app/models/staff.py` に以下のカラムを追加
  - [ ] `is_deleted: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)`
  - [ ] `deleted_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)`
  - [ ] `deleted_by: Mapped[Optional[UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey('staffs.id'), nullable=True)`
- [ ] リレーションシップを追加
  - [ ] `deleted_by_staff: Mapped[Optional["Staff"]] = relationship("Staff", foreign_keys=[deleted_by])`

#### タスク 1.2: StaffAuditLogモデル作成
- [ ] `app/models/staff_audit_log.py` を新規作成
  - [ ] `id: UUID` (主キー)
  - [ ] `staff_id: UUID` (対象スタッフID)
  - [ ] `action: str` (操作種別: "deleted", "created", "updated")
  - [ ] `performed_by: UUID` (操作実行者ID)
  - [ ] `ip_address: Optional[str]` (IPアドレス)
  - [ ] `user_agent: Optional[str]` (User-Agent)
  - [ ] `details: Optional[dict]` (JSONB)
  - [ ] `created_at: datetime`
- [ ] `app/models/__init__.py` にインポート追加

#### タスク 1.3: マイグレーションファイル作成
- [x] `alembic revision` は使わず、自前でファイル作成
- [x] マイグレーションファイル確認・修正
  - [x] `is_deleted` にデフォルト値 `False` が設定されているか確認
  - [x] インデックス追加を確認
    - [x] `CREATE INDEX idx_staff_is_deleted ON staffs(is_deleted);`
    - [x] ~~`CREATE INDEX idx_staff_office_id_is_deleted ON staffs(office_id, is_deleted);`~~ **削除: office_idカラムは存在しない**
- [x] downgrade処理が正しいか確認
- [ ] マイグレーション実行: 修正版SQLファイル `migration_staff_deletion_upgrade_fixed.sql` を使用

**⚠️ 重要な修正事項**:
- **問題**: 元のマイグレーションファイル（18行目）でstaffsテーブルに存在しない`office_id`カラムへのインデックス作成を試みていた
- **原因**: StaffとOfficeは多対多関係で、`office_staffs`中間テーブル経由で管理されている
- **解決**: 修正版マイグレーションファイル `migration_staff_deletion_upgrade_fixed.sql` を使用
- **詳細**: `sql_error_analysis.md` を参照

### Phase 2: CRUD操作実装

#### タスク 2.1: Staff CRUD拡張
- [ ] `app/crud/crud_staff.py` に以下のメソッドを追加

**count_owners_in_office メソッド**
```python
async def count_owners_in_office(
    self,
    db: AsyncSession,
    office_id: UUID
) -> int:
    """事務所内の有効なOwnerの数を取得"""
```
- [ ] `is_deleted = False` でフィルタリング
- [ ] `role = StaffRole.owner` でフィルタリング
- [ ] COUNT関数を使用

**get_by_office_id メソッド拡張**
- [ ] `exclude_deleted: bool = True` パラメータを追加
- [ ] `is_deleted = False` でフィルタリング（exclude_deleted=Trueの場合）

**soft_delete メソッド追加**
```python
async def soft_delete(
    self,
    db: AsyncSession,
    staff_id: UUID,
    deleted_by: UUID
) -> Staff:
    """スタッフを論理削除"""
```
- [ ] `is_deleted = True` に設定
- [ ] `deleted_at = datetime.now(UTC)` に設定
- [ ] `deleted_by` に削除実行者IDを設定
- [ ] `db.flush()` を実行（commitはエンドポイントで行う）

#### タスク 2.2: RefreshToken CRUD拡張
- [ ] `app/crud/crud_refresh_token.py` に以下のメソッドを追加

**revoke_all_by_staff メソッド**
```python
async def revoke_all_by_staff(
    self,
    db: AsyncSession,
    staff_id: UUID
) -> int:
    """指定されたスタッフの全リフレッシュトークンを無効化"""
```
- [ ] `staff_id` でフィルタリング
- [ ] `is_revoked = True` に更新
- [ ] `revoked_at = datetime.now(UTC)` に設定
- [ ] 無効化したトークン数を返却
- [ ] `db.flush()` を実行

#### タスク 2.3: StaffAuditLog CRUD作成
- [ ] `app/crud/crud_staff_audit_log.py` を新規作成
- [ ] CRUDBase を継承
- [ ] `create_audit_log` メソッドを実装
  - [ ] IPアドレス、User-Agent、詳細情報をJSONBに保存
  - [ ] `db.flush()` を実行

### Phase 3: API実装

#### タスク 3.1: スタッフ削除エンドポイント作成
- [ ] `app/api/v1/endpoints/staffs.py` を新規作成（または既存ファイルに追加）

**DELETE /api/v1/staffs/{staff_id} エンドポイント**
```python
@router.delete("/{staff_id}")
async def delete_staff(
    *,
    db: AsyncSession = Depends(deps.get_db),
    staff_id: UUID,
    current_user: Staff = Depends(deps.require_owner),
) -> dict:
```

**実装内容**:
- [ ] スタッフの存在確認
  - [ ] 存在しない場合: `404 Not Found`
- [ ] 削除済みチェック
  - [ ] 既に削除済みの場合: `400 Bad Request` "このスタッフは既に削除されています"
- [ ] 同一事務所チェック
  - [ ] 異なる事務所の場合: `403 Forbidden` "異なる事務所のスタッフは削除できません"
- [ ] 自己削除チェック
  - [ ] 自分自身の場合: `400 Bad Request` "自分自身は削除できません"
- [ ] 最後のOwnerチェック
  - [ ] 削除対象がOwnerの場合、事務所内のOwner数を確認
  - [ ] 最後のOwnerの場合: `409 Conflict` "最後のOwnerは削除できません"

**削除処理（同一トランザクション内）**:
- [ ] スタッフの論理削除実行
  - [ ] `await crud.staff.soft_delete(db, staff_id, current_user.id)`
- [ ] 全リフレッシュトークンの無効化
  - [ ] `await crud.refresh_token.revoke_all_by_staff(db, staff_id)`
- [ ] 監査ログの記録
  - [ ] `await crud.staff_audit_log.create_audit_log(...)`
  - [ ] IPアドレス、User-Agent、削除されたスタッフ情報を記録
- [ ] システム通知の送信（事務所内の全スタッフへ）
  - [ ] 削除されたスタッフの氏名を取得
  - [ ] 事務所内の有効なスタッフIDリストを取得（削除されたスタッフを除く）
  - [ ] `await crud_message.create_announcement(...)` を呼び出し
  - [ ] タイトル: "スタッフ削除のお知らせ"
  - [ ] 本文: "{姓} {名}が事務所から削除されました。"
- [ ] `db.commit()` を実行

**レスポンス**:
- [ ] 成功時: `{"message": "スタッフを削除しました", "staff_id": "...", "deleted_at": "..."}`

#### タスク 3.2: ルーター登録
- [ ] `app/api/v1/api.py` にルーターを追加
  - [ ] `from app.api.v1.endpoints import staffs`
  - [ ] `api_router.include_router(staffs.router, prefix="/staffs", tags=["staffs"])`

### Phase 4: 認証・認可の修正

#### タスク 4.1: get_current_user 修正
- [ ] `app/api/deps.py` の `get_current_user()` を修正
- [ ] スタッフの `is_deleted` をチェック
- [ ] `is_deleted = True` の場合: `403 Forbidden` "このアカウントは削除されています"

#### タスク 4.2: ログイン処理修正
- [ ] `app/api/v1/endpoints/auths.py` のログインエンドポイントを修正
- [ ] ログイン時にスタッフの `is_deleted` をチェック
- [ ] `is_deleted = True` の場合: `403 Forbidden` "このアカウントは削除されています"

### Phase 5: フロントエンド実装

#### タスク 5.1: AdminMenu.tsx - 削除ボタン追加
- [ ] スタッフ一覧テーブルの各行に削除ボタンを追加
  - [ ] アイコン: 🗑️
  - [ ] ラベル: "削除"
  - [ ] 表示条件:
    - [ ] `currentUser.role === 'owner'`
    - [ ] `staff.id !== currentUser.id` (自分自身でない)

#### タスク 5.2: 削除確認ダイアログ実装
- [ ] `useState` で削除対象スタッフを管理
- [ ] `useState` で削除処理中フラグを管理
- [ ] ダイアログの表示制御
- [ ] ダイアログ内容:
  - [ ] タイトル: "スタッフ削除の確認"
  - [ ] メッセージ: "スタッフ「{姓} {名}」を削除しますか？..."
  - [ ] ボタン: "削除する" (赤色)、"キャンセル" (グレー)

#### タスク 5.3: 削除処理ハンドラー実装
```typescript
const handleDeleteStaff = async (staffId: string) => {
  setIsDeleting(true);
  try {
    await authApi.deleteStaff(staffId);
    toast.success('スタッフを削除しました');
    await fetchStaffList(); // スタッフ一覧を再取得
    setShowDeleteDialog(false);
  } catch (error: any) {
    const status = error.response?.status;
    const detail = error.response?.data?.detail;
    // エラーハンドリング（詳細は要件定義書参照）
  } finally {
    setIsDeleting(false);
  }
};
```
- [ ] エラーハンドリング実装
  - [ ] 400: バリデーションエラー
  - [ ] 403: 権限エラー
  - [ ] 404: スタッフが見つからない
  - [ ] 409: 最後のOwnerは削除できません

#### タスク 5.4: APIクライアント実装
- [ ] `k_front/lib/auth.ts` に `deleteStaff` メソッドを追加
```typescript
deleteStaff: (staffId: string): Promise<{
  message: string;
  staff_id: string;
  deleted_at: string;
}> => {
  return http.delete(`${API_V1_PREFIX}/staffs/${staffId}`);
}
```

### Phase 6: テスト実装

#### タスク 6.1: バックエンドテスト
- [ ] `tests/api/v1/test_staffs_api.py` を作成
  - [ ] 正常系: スタッフ削除成功
  - [ ] 異常系: 自分自身を削除
  - [ ] 異常系: 最後のOwnerを削除
  - [ ] 異常系: 既に削除済み
  - [ ] 異常系: 異なる事務所のスタッフ
  - [ ] 異常系: Ownerでないユーザーが削除
  - [ ] 正常系: 削除後のログイン拒否

- [ ] `tests/crud/test_crud_staff.py` を作成
  - [ ] `count_owners_in_office` テスト
  - [ ] `soft_delete` テスト
  - [ ] `get_by_office_id` with `exclude_deleted` テスト

- [ ] `tests/crud/test_crud_refresh_token.py` を作成
  - [ ] `revoke_all_by_staff` テスト

#### タスク 6.2: フロントエンドテスト
- [ ] 削除ボタンの表示制御テスト
  - [ ] Ownerの場合のみ表示
  - [ ] 自分自身の行には表示されない
- [ ] 削除確認ダイアログのテスト
- [ ] 削除処理のテスト
- [ ] エラーハンドリングのテスト

---

## 2. セキュリティレビュー項目

### 2.1 認証・認可

- [ ] **JWT認証が必須**: すべての削除エンドポイントでJWT検証が実施されているか
- [ ] **ロールベースアクセス制御**: Owner のみが削除を実行できることが保証されているか
  - [ ] `require_owner` dependency が使用されているか
- [ ] **同一事務所チェック**: 削除対象スタッフが自分の所属事務所に属しているか確認しているか
- [ ] **自己削除防止**: 自分自身を削除できないようにチェックしているか
- [ ] **最後のOwner保護**: 事務所に残る唯一のOwnerを削除できないようにチェックしているか

### 2.2 セッション無効化

- [ ] **リフレッシュトークンの無効化**: 削除時に全リフレッシュトークンが無効化されているか
  - [ ] `is_revoked = True` に設定されているか
  - [ ] `revoked_at` に現在日時が記録されているか
- [ ] **アクセストークンの検証強化**: `get_current_user()` で削除済みスタッフがチェックされているか
  - [ ] `is_deleted = True` の場合に `403 Forbidden` を返すか
- [ ] **ログイン時のチェック**: ログイン時に削除済みスタッフがチェックされているか

### 2.3 監査証跡

- [ ] **操作ログの記録**: すべての削除操作が監査ログに記録されているか
  - [ ] 操作実行者のID
  - [ ] 削除されたスタッフのID、メール、氏名、ロール
  - [ ] 操作日時（UTC）
  - [ ] IPアドレス
  - [ ] User-Agent
- [ ] **ログの不変性**: 一度記録されたログが変更・削除できないようになっているか

### 2.4 入力バリデーション

- [ ] **UUID検証**: スタッフIDが有効なUUID形式であることを確認しているか
- [ ] **存在確認**: 削除対象スタッフが実際に存在することを確認しているか
- [ ] **削除済みチェック**: 既に削除されたスタッフを再度削除しようとした場合にエラーを返すか

### 2.5 エラーハンドリング

- [ ] **エラーメッセージの一貫性**: すべてのエラーメッセージが日本語で統一されているか
- [ ] **詳細情報の非公開**: エラーメッセージにシステムの内部情報が含まれていないか
- [ ] **適切なHTTPステータスコード**: エラー種別に応じて適切なステータスコードが返されているか

---

## 3. SQLAlchemyトランザクション管理レビュー項目

### 3.1 トランザクションの基本原則

- [ ] **1つの論理操作 = 1つのトランザクション**: スタッフ削除とトークン無効化、通知送信が同一トランザクション内で実行されているか
- [ ] **commitはエンドポイントでのみ**: CRUD層では`flush()`のみを使用し、`commit()`はエンドポイント層で実行しているか
- [ ] **ループ内でcommitしない**: チャンク処理やバルクインサートが適切に実装されているか

### 3.2 CRUD層の実装

- [ ] **flushの使用**: CRUD層のメソッドは`db.flush()`を使用し、`db.commit()`を使用していないか
- [ ] **例外処理**: CRUD層でDBエラーが発生した場合、適切に例外を上位層に伝播させているか
- [ ] **セッションの再利用**: 同一トランザクション内で複数のCRUD操作を実行しているか

### 3.3 エンドポイント層の実装

- [ ] **トランザクション境界**: エンドポイントで`db.commit()`を1回だけ実行しているか
- [ ] **例外時のロールバック**: 例外発生時に自動的にロールバックされる仕組みになっているか
  - [ ] FastAPIの依存性注入により自動ロールバックが保証されているか
- [ ] **トランザクションの順序**:
  1. [ ] スタッフの論理削除（`soft_delete`）
  2. [ ] リフレッシュトークンの無効化（`revoke_all_by_staff`）
  3. [ ] 監査ログの記録（`create_audit_log`）
  4. [ ] システム通知の送信（`create_announcement`）
  5. [ ] `db.commit()`

### 3.4 同時実行制御

- [ ] **楽観的ロック**: `updated_at` カラムを使用して同時更新を検出しているか（必要に応じて）
- [ ] **デッドロック対策**: トランザクションの保持時間を短く保っているか
- [ ] **一意制約**: データベースレベルで一意制約が設定されているか

### 3.5 エラーハンドリング

- [ ] **IntegrityError のキャッチ**: データベース制約違反を適切にキャッチしているか
- [ ] **例外後のロールバック**: 例外発生後にセッションが適切にロールバックされているか
- [ ] **リトライ戦略**: デッドロックが発生した場合のリトライ戦略が実装されているか（必要に応じて）

### 3.6 パフォーマンス

- [ ] **N+1問題の回避**: `selectinload` や `joinedload` を使用して関連データを効率的に取得しているか
- [ ] **バルク操作**: 複数のトークンを無効化する際にバルク更新を使用しているか
- [ ] **インデックスの活用**: `is_deleted` や `office_id + is_deleted` にインデックスが設定されているか

---

## 4. 必須機能網羅性レビュー項目

### 4.1 ビジネス要件の実装

- [ ] **Owner のみが削除可能**: 権限チェックが実装されているか
- [ ] **自己削除の禁止**: 自分自身を削除できないようにチェックしているか
- [ ] **最後のOwner保護**: 事務所に残る唯一のOwnerを削除できないようにチェックしているか
- [ ] **即座のアクセス無効化**: 削除と同時に全トークンが無効化されているか
- [ ] **同一事務所内のみ**: 異なる事務所のスタッフは削除できないようにチェックしているか
- [ ] **監査証跡の保持**: 誰が、いつ、誰を削除したかが記録されているか

### 4.2 データ整合性

- [ ] **論理削除の実装**: `is_deleted` フラグが正しく設定されているか
- [ ] **削除日時の記録**: `deleted_at` に削除日時が記録されているか
- [ ] **削除実行者の記録**: `deleted_by` に削除実行者のIDが記録されているか
- [ ] **外部キー制約**: `deleted_by` が `staffs.id` への外部キーとして設定されているか

### 4.3 システム通知機能

- [ ] **自動通知送信**: スタッフ削除時に自動的に一斉通知が送信されているか
- [ ] **通知内容の正確性**: タイトルと本文が要件通りであるか
  - [ ] タイトル: "スタッフ削除のお知らせ"
  - [ ] 本文: "{姓} {名}が事務所から削除されました。"
- [ ] **受信者の正確性**: 削除されたスタッフが所属していた事務所の全スタッフ（削除されたスタッフを除く）に送信されているか
- [ ] **トランザクション内での送信**: 通知送信が削除処理と同一トランザクション内で実行されているか

### 4.4 UI/UXの実装

- [ ] **削除ボタンの表示制御**: Ownerの場合のみ表示されているか
- [ ] **自分自身の行に削除ボタンが表示されない**: 自分自身を削除できないようになっているか
- [ ] **削除確認ダイアログ**: 削除ボタンクリック時に確認ダイアログが表示されるか
- [ ] **ダイアログの内容**: 対象スタッフの氏名と警告メッセージが表示されているか
- [ ] **ローディング状態**: 削除処理中にローディング状態が表示されるか
- [ ] **フィードバックメッセージ**: 成功時とエラー時に適切なメッセージが表示されるか

### 4.5 エラーハンドリング

- [ ] **400 Bad Request**: 自己削除、削除済みスタッフの場合
- [ ] **403 Forbidden**: Ownerでない、削除済みアカウントでのログイン
- [ ] **404 Not Found**: 存在しないスタッフID
- [ ] **409 Conflict**: 最後のOwnerを削除
- [ ] **500 Internal Server Error**: その他のサーバーエラー

### 4.6 テストの実装

- [ ] **正常系テスト**: スタッフ削除が正常に完了するケース
- [ ] **異常系テスト**:
  - [ ] 自分自身を削除しようとするケース
  - [ ] 最後のOwnerを削除しようとするケース
  - [ ] 既に削除済みのスタッフを削除しようとするケース
  - [ ] 異なる事務所のスタッフを削除しようとするケース
  - [ ] Ownerでないユーザーが削除しようとするケース
- [ ] **セキュリティテスト**: 削除後のログイン拒否テスト

---

## まとめ

このタスクリストに従って実装を進め、各レビュー項目をチェックすることで、セキュアで信頼性の高いスタッフ削除機能を実装できます。

**実装の重要ポイント**:
1. トランザクション管理: 削除、トークン無効化、通知送信を1つのトランザクションで実行
2. セキュリティ: Owner権限、自己削除防止、最後のOwner保護
3. セッション無効化: 削除後の即座のアクセス拒否
4. 監査証跡: すべての操作をログに記録

**レビュー時の確認事項**:
- [ ] すべてのタスクが完了しているか
- [ ] すべてのセキュリティレビュー項目が満たされているか
- [ ] SQLAlchemyトランザクション管理のベストプラクティスに従っているか
- [ ] すべての必須機能が実装されているか
- [ ] すべてのテストが成功しているか
