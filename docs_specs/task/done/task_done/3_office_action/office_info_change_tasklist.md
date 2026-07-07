# 事務所情報変更機能 - 実装タスクリスト

## 概要
事務所の基本情報（事務所名、住所、電話番号など）を変更できる機能の実装タスクリスト。
オーナーのみがアクセス可能で、変更履歴を監査ログに記録する。

## 現在の実装状況（最終更新: 2025-11-25）

**実装完了率: 83.3% (5/6 コンポーネント)**

### ✅ 実装済み
- ✅ **データベース設計**: Office モデル、OfficeAuditLog モデル実装済み
- ✅ **Models & Schemas**: OfficeInfoUpdate スキーマ実装済み（バリデーション含む）
- ✅ **CRUD 実装**: update_office_info, create_office_update_log 実装済み
- ✅ **API エンドポイント**: PUT /api/v1/offices/me, GET /api/v1/offices/me/audit-logs 実装済み
- ✅ **テスト**: test_office_info_update.py, test_crud_office_info.py 実装済み

### ❌ 未実装
- ❌ **システム通知**: 事務所情報更新時にスタッフへの通知機能が未実装

### 次のステップ
1. システム通知機能の TDD 実装（Phase 1: Red → Phase 2: Green）
2. 統合テストの実行と検証

---

## Phase 1: データベース設計

### 1.1 監査ログテーブルの確認・拡張
- [ ] `office_audit_logs` テーブルの既存構造を確認
- [ ] 事務所情報変更に必要なカラムが揃っているか確認
  - `id`, `office_id`, `staff_id`, `action_type`, `details`, `created_at`
- [ ] 必要に応じて `action_type` に新しい値を追加
  - `office_info_updated` など

### 1.2 マイグレーション作成
- [ ] 監査ログテーブル拡張のマイグレーション作成（必要な場合）
- [ ] マイグレーションの動作確認（up/down）
- [ ] テストデータ用のフラグ確認（`is_test_data`）

---

## Phase 2: バックエンド実装 - Models & Schemas

### 2.1 Model の確認・更新
- [ ] `app/models/office.py` の `Office` モデル確認
  - 変更対象フィールド: `name`, `address`, `phone_number`, `email` など
  - `updated_at` フィールドの自動更新設定確認
- [ ] `app/models/office_audit_log.py` の確認（監査ログ）

### 2.2 Schema の作成・更新
- [ ] `app/schemas/office.py` に事務所情報変更用スキーマを追加
  ```python
  class OfficeUpdate(BaseModel):
      name: Optional[str] = Field(None, min_length=1, max_length=200)
      address: Optional[str] = Field(None, max_length=500)
      phone_number: Optional[str] = Field(None, pattern=r'^\d{2,4}-\d{2,4}-\d{4}$')
      email: Optional[EmailStr] = None
      # その他変更可能なフィールド
  ```
- [ ] バリデーション追加（文字数制限、形式チェック）
- [ ] `OfficeRead` スキーマの確認（レスポンス用）

---

## Phase 3: バックエンド実装 - CRUD

### 3.1 CRUD 関数の実装
- [ ] `app/crud/crud_office.py` に `update_office_info` 関数を実装
  ```python
  async def update_office_info(
      db: AsyncSession,
      *,
      office_id: str,
      update_data: dict[str, Any]
  ) -> Office:
      """
      事務所情報を更新
      - flush のみ実行（commit は endpoint で実行）
      - 変更前の値を返す（監査ログ用）
      """
  ```
- [ ] 変更前の情報を取得して返す処理を追加
- [ ] `db.flush()` のみ実行（commit はエンドポイントで）
- [ ] 楽観的ロックの検討（必要に応じて `version` カラム追加）

### 3.2 監査ログ CRUD の実装
- [ ] `app/crud/crud_office_audit_log.py` に監査ログ作成関数
  ```python
  async def create_office_update_log(
      db: AsyncSession,
      *,
      office_id: str,
      staff_id: str,
      action_type: str,
      old_values: dict,
      new_values: dict
  ) -> OfficeAuditLog:
      """
      事務所情報変更の監査ログを記録
      """
  ```
- [ ] 変更内容を JSON 形式で `details` に保存
- [ ] `db.flush()` のみ実行

---

## Phase 4: バックエンド実装 - API Endpoints

### 4.1 認証・認可の実装
- [ ] `app/api/deps.py` に権限チェック関数を追加（または既存を確認）
  ```python
  async def require_office_owner(
      current_user: Staff = Depends(get_current_user)
  ) -> Staff:
      """オーナーのみアクセス可能"""
      if current_user.role != StaffRole.OWNER:
          raise HTTPException(status_code=403, detail="Owner access required")
      return current_user
  ```

### 4.2 事務所情報取得エンドポイント
- [ ] `GET /api/v1/offices/me` の既存実装を確認
- [ ] 必要に応じて情報を追加・修正

### 4.3 事務所情報更新エンドポイント
- [ ] `PUT /api/v1/offices/me` エンドポイントを実装
  ```python
  @router.put("/me", response_model=schemas.office.OfficeRead)
  async def update_office_info(
      *,
      db: AsyncSession = Depends(deps.get_db),
      office_in: schemas.office.OfficeUpdate,
      current_user: models.Staff = Depends(deps.require_office_owner)
  ) -> Any:
      """
      事務所情報更新（オーナーのみ）
      - 変更前の値を取得
      - CRUD で更新（flush のみ）
      - 監査ログ作成（flush のみ）
      - 最後に commit
      """
  ```
- [ ] トランザクション管理（commit はエンドポイントで一度だけ）
- [ ] エラーハンドリング（ロールバック処理）
- [ ] 変更がない場合の処理

### 4.4 監査ログ取得エンドポイント（オプション）
- [ ] `GET /api/v1/offices/me/audit-logs` エンドポイント実装
- [ ] ページネーション対応
- [ ] オーナーのみアクセス可能

---

## Phase 5: バックエンド実装 - Tests

### 5.1 CRUD テスト
- [ ] `tests/crud/test_office.py` に更新機能のテストを追加
  - 正常系: 事務所情報が正しく更新される
  - 異常系: 存在しない office_id での更新
  - バリデーション: 不正なデータでの更新失敗

### 5.2 API テスト
- [ ] `tests/api/test_offices.py` にテストを追加
  - **認証テスト**:
    - オーナーは更新可能
    - マネージャーは更新不可（403 エラー）
    - 一般スタッフは更新不可（403 エラー）
    - 未認証ユーザーは更新不可（401 エラー）
  - **正常系**:
    - 事務所名の更新
    - 住所の更新
    - 電話番号の更新
    - 複数フィールドの同時更新
  - **異常系**:
    - 無効なメールアドレス形式
    - 電話番号形式エラー
    - 文字数制限超過
  - **監査ログ**:
    - 更新時に監査ログが作成される
    - 変更前後の値が正しく記録される

### 5.3 統合テスト
- [ ] トランザクション管理のテスト
  - 更新と監査ログ作成が同一トランザクションで実行される
  - エラー時に両方がロールバックされる
- [ ] 並行更新のテスト（楽観的ロック）

---

## Phase 6: フロントエンド実装

### 6.1 型定義
- [ ] `k_front/types/office.ts` に型を追加
  ```typescript
  export interface OfficeUpdateRequest {
    name?: string;
    address?: string;
    phone_number?: string;
    email?: string;
  }

  export interface OfficeInfo {
    id: string;
    name: string;
    address: string;
    phone_number: string;
    email: string;
    created_at: string;
    updated_at: string;
  }
  ```

### 6.2 API クライアント
- [ ] `k_front/lib/api/offices.ts` に更新関数を追加
  ```typescript
  export const officesApi = {
    getMyOffice: (): Promise<OfficeInfo> => {
      return http.get<OfficeInfo>('/api/v1/offices/me');
    },

    updateOfficeInfo: (data: OfficeUpdateRequest): Promise<OfficeInfo> => {
      return http.put<OfficeInfo>('/api/v1/offices/me', data);
    },
  };
  ```

### 6.3 フォームコンポーネント
- [ ] `k_front/components/settings/OfficeInfoForm.tsx` を作成
  - 現在の事務所情報を表示
  - 編集モード切り替え
  - フォームバリデーション
  - 送信処理とエラーハンドリング
  ```typescript
  export default function OfficeInfoForm() {
    const [officeInfo, setOfficeInfo] = useState<OfficeInfo | null>(null);
    const [isEditing, setIsEditing] = useState(false);
    const [formData, setFormData] = useState<OfficeUpdateRequest>({});

    // 取得、更新処理など
  }
  ```

### 6.4 設定ページ
- [ ] `k_front/app/(protected)/settings/office/page.tsx` を作成
  - オーナーのみアクセス可能なページ
  - OfficeInfoForm コンポーネントを表示
- [ ] ナビゲーションメニューに追加（オーナーのみ表示）

### 6.5 権限制御
- [ ] オーナー以外がアクセスした場合の処理
  - 403 エラーページへリダイレクト
  - または権限不足のメッセージ表示

---

## Phase 7: UI/UX 改善

### 7.1 入力検証
- [ ] リアルタイムバリデーション
  - メールアドレス形式チェック
  - 電話番号形式チェック
  - 文字数制限表示
- [ ] エラーメッセージの表示

### 7.2 確認ダイアログ
- [ ] 変更内容の確認ダイアログ
  - 変更前後の値を表示
  - キャンセル・確定ボタン

### 7.3 成功・エラー通知
- [ ] 更新成功時のトースト通知
- [ ] エラー時のわかりやすいメッセージ

---

## Phase 8: ドキュメント作成

### 8.1 API ドキュメント
- [ ] エンドポイント仕様書の更新
  - `PUT /api/v1/offices/me`
  - リクエスト/レスポンス例
  - エラーコード一覧

### 8.2 実装ドキュメント
- [ ] 機能概要の記載
- [ ] 権限設定の説明
- [ ] 監査ログの見方

---

## Phase 9: テスト・QA

### 9.1 手動テスト
- [ ] オーナーアカウントでログイン
  - 事務所情報の取得確認
  - 各フィールドの更新確認
  - 監査ログの記録確認
- [ ] マネージャーアカウントでログイン
  - アクセス拒否の確認（403 エラー）
- [ ] 一般スタッフアカウントでログイン
  - アクセス拒否の確認（403 エラー）

### 9.2 バリデーションテスト
- [ ] 無効なメールアドレス入力
- [ ] 無効な電話番号形式
- [ ] 文字数制限超過
- [ ] 空文字の送信

### 9.3 並行更新テスト
- [ ] 同時に複数のオーナーが更新した場合の挙動確認
- [ ] 楽観的ロックの動作確認（実装した場合）

---

## セキュリティレビュー項目

### S1. 認証・認可
- [ ] オーナーのみがアクセス可能か確認
- [ ] JWT トークンの検証が正しく行われているか
- [ ] 他の事務所の情報にアクセスできないか確認

### S2. 入力検証
- [ ] すべての入力フィールドにバリデーションが実装されているか
  - メールアドレス形式
  - 電話番号形式
  - 文字数制限
- [ ] SQL インジェクション対策（SQLAlchemy の ORM 使用）
- [ ] XSS 対策（フロントエンドでのエスケープ処理）

### S3. 監査ログ
- [ ] すべての変更が監査ログに記録されるか
- [ ] 変更前後の値が正しく記録されるか
- [ ] 変更者（staff_id）が正しく記録されるか
- [ ] タイムスタンプが正確に記録されるか

### S4. エラーハンドリング
- [ ] エラーメッセージで内部情報が漏洩しないか
- [ ] 権限エラー時に適切な HTTP ステータスコード（403）を返すか
- [ ] 不正なデータでエラー時に適切なメッセージを返すか

### S5. データ整合性
- [ ] トランザクション管理が適切か
- [ ] 楽観的ロックの実装（必要な場合）
- [ ] 更新と監査ログ作成が同一トランザクションで実行されるか

---

## SQLAlchemy トランザクション管理レビュー項目

### T1. 基本原則
- [ ] **CRUD 層では `flush()` のみ、`commit()` は使わない**
- [ ] **エンドポイント（API 層）で一度だけ `commit()` を実行**
- [ ] **エラー時は自動的に `rollback()` される設定か確認**

### T2. CRUD 実装の確認
- [ ] `crud_office.py` の `update_office_info` 関数
  ```python
  async def update_office_info(db: AsyncSession, ...) -> Office:
      # 1. 既存データ取得
      office = await db.get(Office, office_id)

      # 2. 更新処理
      for key, value in update_data.items():
          setattr(office, key, value)

      # 3. flush のみ（commit しない）
      await db.flush()
      await db.refresh(office)

      return office
  ```
- [ ] `crud_office_audit_log.py` の監査ログ作成関数
  ```python
  async def create_office_update_log(db: AsyncSession, ...) -> OfficeAuditLog:
      log = OfficeAuditLog(...)
      db.add(log)

      # flush のみ（commit しない）
      await db.flush()
      await db.refresh(log)

      return log
  ```

### T3. エンドポイント実装の確認
- [ ] API エンドポイントで複数の CRUD 操作を実行
  ```python
  @router.put("/me", response_model=schemas.office.OfficeRead)
  async def update_office_info(
      *,
      db: AsyncSession = Depends(deps.get_db),
      office_in: schemas.office.OfficeUpdate,
      current_user: models.Staff = Depends(deps.require_office_owner)
  ) -> Any:
      try:
          # 1. 変更前の値を取得
          old_office = await crud.office.get(db, id=current_user.office_id)
          old_values = {...}

          # 2. 事務所情報更新（flush のみ）
          update_data = office_in.model_dump(exclude_unset=True)
          updated_office = await crud.office.update_office_info(
              db, office_id=current_user.office_id, update_data=update_data
          )

          # 3. 監査ログ作成（flush のみ）
          await crud.office_audit_log.create_office_update_log(
              db,
              office_id=current_user.office_id,
              staff_id=current_user.id,
              action_type="office_info_updated",
              old_values=old_values,
              new_values=update_data
          )

          # 4. すべての操作が成功したら commit（一度だけ）
          await db.commit()
          await db.refresh(updated_office)

          return updated_office

      except Exception as e:
          # エラー時は自動的に rollback される
          await db.rollback()
          raise HTTPException(status_code=500, detail=str(e))
  ```
- [ ] **commit は一度だけ、すべての操作が成功した後に実行**
- [ ] **エラー時の rollback 処理が適切に実装されているか**

### T4. 並行制御
- [ ] 楽観的ロック（version カラム）の実装検討
  ```python
  class Office(Base):
      # ...
      version: Mapped[int] = mapped_column(default=0)
  ```
- [ ] 更新時に version チェック
  ```python
  stmt = (
      update(Office)
      .where(Office.id == office_id, Office.version == old_version)
      .values(version=old_version + 1, ...)
  )
  result = await db.execute(stmt)
  if result.rowcount == 0:
      raise HTTPException(status_code=409, detail="Conflict: Data was modified")
  ```

### T5. エラーハンドリング
- [ ] データベースエラーの適切なハンドリング
- [ ] 制約違反エラーのハンドリング
- [ ] トランザクションタイムアウトの考慮

### T6. パフォーマンス
- [ ] 不要な `refresh()` 呼び出しを避ける
- [ ] N+1 問題がないか確認
- [ ] インデックスの活用

---

## 必須機能網羅性レビュー項目

### F1. ビジネス要件
- [ ] オーナーのみが事務所情報を変更できる
- [ ] 変更可能な項目が要件通りか（事務所名、住所、電話番号、メールなど）
- [ ] 変更履歴が監査ログに記録される

### F2. データ整合性
- [ ] 事務所情報の更新が正しく保存される
- [ ] 監査ログが確実に記録される（更新とログ作成が同一トランザクション）
- [ ] エラー時にロールバックされ、不完全な状態にならない

### F3. UI/UX 要件
- [ ] オーナーのみ設定ページにアクセスできる
- [ ] 現在の情報が表示される
- [ ] 編集モードと表示モードの切り替え
- [ ] フォームバリデーションとエラー表示
- [ ] 確認ダイアログの表示
- [ ] 成功・エラー通知

### F4. エラーハンドリング
- [ ] 権限不足の場合に 403 エラー
- [ ] バリデーションエラー時に適切なメッセージ
- [ ] サーバーエラー時の適切なハンドリング
- [ ] ネットワークエラー時の処理

### F5. テスト要件
- [ ] ユニットテスト（CRUD 層）
- [ ] 統合テスト（API 層）
- [ ] 権限テスト（オーナー/マネージャー/スタッフ）
- [ ] バリデーションテスト
- [ ] 並行更新テスト

### F6. ドキュメント要件
- [ ] API 仕様書の作成
- [ ] 実装ドキュメントの作成
- [ ] コードコメントの記載

---

## 実装優先度

### 高優先度（Phase 1 リリース必須）
- Phase 1: データベース設計
- Phase 2: Models & Schemas
- Phase 3: CRUD 実装
- Phase 4: API Endpoints
- Phase 5: Tests（基本的なもの）
- Phase 6: フロントエンド実装（基本機能）

### 中優先度（Phase 2 リリース検討）
- Phase 7: UI/UX 改善
- Phase 5: Tests（詳細なエッジケース）
- 監査ログ取得エンドポイント

### 低優先度（将来的な改善）
- 楽観的ロックの実装
- 高度な並行制御
- パフォーマンス最適化

---

## 完了条件

- [ ] すべての高優先度タスクが完了
- [ ] セキュリティレビューがすべて PASS
- [ ] SQLAlchemy トランザクション管理レビューがすべて PASS
- [ ] 必須機能網羅性レビューがすべて PASS
- [ ] ユニットテスト・統合テストがすべて PASS
- [ ] 手動テストで問題がないことを確認
- [ ] ドキュメントが完成

---

## 注意事項

1. **トランザクション管理**
   - CRUD 層では `flush()` のみ
   - エンドポイントで一度だけ `commit()`
   - エラー時は必ず `rollback()`

2. **セキュリティ**
   - オーナー権限の厳密なチェック
   - 入力データの徹底的なバリデーション
   - 監査ログの確実な記録

3. **データ整合性**
   - 事務所情報更新と監査ログ作成は同一トランザクション
   - 並行更新への対応（必要に応じて楽観的ロック）

4. **テスト**
   - 権限テストを徹底的に実施
   - エラーケースのテストを網羅
   - 並行更新のテスト実施
