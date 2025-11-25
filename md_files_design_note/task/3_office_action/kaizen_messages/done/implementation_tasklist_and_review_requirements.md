# メッセージ機能 CRUD実装 タスクリスト & レビュー要件定義

最終更新: 2025-11-23
作成者: Claude Code
関連ドキュメント: message_design.md, implementation_status.md

## 📊 実装状況サマリー（2025-11-23時点）

| Phase | 項目 | 状態 | 進捗 |
|-------|------|------|------|
| Phase 1 | マイグレーション | ✅ 完了 (⚠️ is_test_dataなし) | 90% |
| Phase 1 | モデル (Message, MessageRecipient) | ✅ 完了 (⚠️ is_test_dataなし) | 100% |
| Phase 1 | モデル (MessageAuditLog) | ❌ 未実装 | 0% |
| Phase 1 | モデルテスト | ✅ 完了 | 100% |
| Phase 2 | スキーマ | ❌ 未実装 | 0% |
| Phase 3 | CRUD | ❌ 未実装 | 0% |
| Phase 4 | API | ❌ 未実装 | 0% |
| **全体進捗** | - | 🔄 実装中 | **12%** |

**次のタスク**: MessageAuditLogモデル追加 + is_test_dataフラグ追加

詳細な実装状況は [implementation_status.md](./implementation_status.md) を参照してください。

---

## 目的

メッセージ機能のバックエンドCRUD実装を、TDD方式で段階的に実装し、トランザクション管理・セキュリティ・パフォーマンス要件を満たすことを確認する。

## 実装方針

1. **TDD (Test-Driven Development)**: テスト → 実装の順序で進める
2. **トランザクション管理**: commitはエンドポイントでのみ行い、CRUD層では実行しない
3. **セキュリティファースト**: 権限チェック、XSS対策、レート制限を最初から組み込む
4. **パフォーマンス**: バルクインサートとチャンク処理で一斉通知を効率化

---

## Phase 1: データベース層（マイグレーション & モデル）

### 1.1 マイグレーション作成 ✅ **実装済み** (⚠️ 不足分あり)

**タスク**: Alembicマイグレーションファイル作成

**ファイル**: `k_back/migrations/versions/x1y2z3a4b5c6_add_messages_tables.py`

**実装内容**:
- ✅ `messages` テーブル作成
- ✅ `message_recipients` テーブル作成（中間テーブル）
- ✅ `message_audit_logs` テーブル作成（監査ログ）
- ✅ 各種インデックス作成（migration_messages_tables.sql を参照）
- ❌ **is_test_data フラグを全テーブルに追加** ← **未実装**

**レビューポイント**:
- [x] UUIDの主キー設定が正しいか
- [x] 外部キー制約（ON DELETE CASCADE / SET NULL）が適切か
- [x] インデックスが必要なカラムに設定されているか
- [x] ユニーク制約（message_id, recipient_staff_id）が設定されているか
- [x] タイムスタンプ（created_at, updated_at）がデフォルト値付きで設定されているか
- [ ] ⚠️ **is_test_data カラムがあるか** ← **未実装**

**テスト**:
```bash
cd k_back
alembic upgrade head
alembic downgrade -1
alembic upgrade head
```

---

### 1.2 モデル作成 ⚠️ **部分的に実装済み** (不足分あり)

**タスク**: SQLAlchemyモデル定義

**ファイル**:
- `k_back/app/models/message.py` - Message, MessageRecipient, ~~MessageAuditLog~~
- `k_back/app/models/enums.py` - MessageType, MessagePriority (✅ 実装済み)

**実装内容**:

✅ **Message モデル（メッセージ本体）** - 実装済み
  - ✅ sender_staff_id: UUID (FK to staffs, nullable for deleted users)
  - ✅ office_id: UUID (FK to offices, NOT NULL)
  - ✅ message_type: Enum (personal, announcement, system, inquiry)
  - ✅ priority: Enum (low, normal, high, urgent)
  - ✅ title: String(200)
  - ✅ content: Text
  - ✅ created_at, updated_at: DateTime
  - ❌ **is_test_data: Boolean** ← **未実装**
  - ✅ リレーション: sender, office, recipients (via MessageRecipient)

✅ **MessageRecipient モデル（受信者中間テーブル）** - 実装済み
  - ✅ message_id: UUID (FK to messages)
  - ✅ recipient_staff_id: UUID (FK to staffs)
  - ✅ is_read: Boolean (default False)
  - ✅ read_at: DateTime (nullable)
  - ✅ is_archived: Boolean (default False)
  - ✅ created_at, updated_at: DateTime
  - ❌ **is_test_data: Boolean** ← **未実装**
  - ✅ リレーション: message, recipient_staff
  - ✅ ユニーク制約: (message_id, recipient_staff_id)

❌ **MessageAuditLog モデル（監査ログ）** - **未実装**
  - staff_id: UUID (FK to staffs, nullable)
  - message_id: UUID (FK to messages, nullable)
  - action: String(50) - sent, read, archived, deleted
  - ip_address: String(45) - IPv6対応
  - user_agent: Text
  - success: Boolean
  - error_message: Text (nullable)
  - created_at: DateTime
  - is_test_data: Boolean

**レビューポイント**:
- [x] TYPE_CHECKING を使った循環インポート回避
- [x] Mapped[] 型アノテーションの正しい使用
- [x] リレーションシップの設定（foreign_keys, back_populates）
- [x] Enum型の定義（message_type, priority）
- [x] CASCADE設定の確認
- [ ] ⚠️ **is_test_data フラグの追加** ← **未実装**
- [ ] ⚠️ **MessageAuditLog モデルの追加** ← **未実装**

**テスト**:
- ✅ `tests/models/test_message_model.py` 実装済み（Message, MessageRecipient）
- ❌ MessageAuditLog のテスト未作成

---

## Phase 2: スキーマ層（Pydantic）

### 2.1 スキーマ作成

**タスク**: リクエスト/レスポンススキーマ定義

**ファイル**: `k_back/app/schemas/message.py`

**実装内容**:

1. **MessageCreate** (個別メッセージ送信)
   - recipient_staff_ids: List[UUID] (1人以上)
   - message_type: str = "personal"
   - priority: str = "normal"
   - title: str (max 200)
   - content: str (max 10000)

2. **AnnouncementCreate** (一斉通知送信)
   - message_type: str = "announcement"
   - priority: str
   - title: str
   - content: str
   - (recipient_staff_idsは不要、全スタッフに送信)

3. **MessageResponse**
   - id: UUID
   - sender_staff_id: Optional[UUID]
   - sender_name: Optional[str] (計算プロパティ)
   - office_id: UUID
   - message_type: str
   - priority: str
   - title: str
   - content: str
   - created_at: datetime
   - updated_at: datetime

4. **MessageRecipientResponse**
   - id: UUID
   - message_id: UUID
   - message: MessageResponse
   - is_read: bool
   - read_at: Optional[datetime]
   - is_archived: bool
   - created_at: datetime

5. **InboxResponse**
   - messages: List[MessageRecipientResponse]
   - total: int
   - unread_count: int

6. **MessageStatsResponse**
   - message_id: UUID
   - total_recipients: int
   - read_count: int
   - unread_count: int
   - read_rate: float

**レビューポイント**:
- [ ] Field() バリデーション（min_length, max_length, ge, le）
- [ ] ConfigDict の from_attributes=True 設定
- [ ] Optional型の適切な使用
- [ ] エイリアス設定の確認
- [ ] XSS対策: content のサニタイズ（必要に応じて）

**テスト**:
- `tests/schemas/test_message.py` を作成（バリデーションテスト）

---

## Phase 3: CRUD層

### 3.1 CRUDMessage 実装

**タスク**: メッセージ本体のCRUD操作

**ファイル**: `k_back/app/crud/crud_message.py`

**実装内容**:

```python
class CRUDMessage(CRUDBase[Message, MessageCreate, MessageUpdate]):

    async def create_with_recipients(
        self,
        db: AsyncSession,
        *,
        sender_staff_id: UUID,
        office_id: UUID,
        message_in: MessageCreate,
        recipient_staff_ids: List[UUID],
        auto_commit: bool = False  # IMPORTANT: デフォルトFalse
    ) -> Message:
        """
        メッセージ本体と受信者レコードを一括作成
        - auto_commit=False: エンドポイントで最後にcommit
        - flush()のみ実行してIDを取得
        """
        pass

    async def get_by_sender(
        self,
        db: AsyncSession,
        sender_staff_id: UUID
    ) -> List[Message]:
        """送信者のメッセージ一覧取得"""
        pass

    async def get_by_office(
        self,
        db: AsyncSession,
        office_id: UUID
    ) -> List[Message]:
        """事務所のメッセージ一覧取得"""
        pass
```

**レビューポイント**:
- [ ] **CRITICAL**: commitを呼び出していないこと
- [ ] auto_commit パラメータがデフォルト False
- [ ] flush() のみで ID 取得していること
- [ ] selectinload でリレーションを効率的に取得
- [ ] トランザクションスコープはエンドポイントで管理

**テスト**:
- `tests/crud/test_crud_message.py`

---

### 3.2 CRUDMessageRecipient 実装

**タスク**: 受信者管理のCRUD操作

**ファイル**: `k_back/app/crud/crud_message_recipient.py`

**実装内容**:

```python
class CRUDMessageRecipient(CRUDBase[MessageRecipient, MessageRecipientCreate, MessageRecipientUpdate]):

    async def create_bulk(
        self,
        db: AsyncSession,
        *,
        message_id: UUID,
        recipient_staff_ids: List[UUID],
        chunk_size: int = 1000
    ) -> int:
        """
        一斉通知の受信者レコードをバルク作成
        - チャンク単位で分割（大量配信対応）
        - commitはエンドポイントで実行
        - 戻り値: 作成件数
        """
        pass

    async def get_inbox(
        self,
        db: AsyncSession,
        recipient_staff_id: UUID,
        is_read: Optional[bool] = None,
        skip: int = 0,
        limit: int = 100
    ) -> Tuple[List[MessageRecipient], int]:
        """
        受信箱取得（未読フィルタ対応）
        - 戻り値: (メッセージリスト, 総件数)
        """
        pass

    async def mark_as_read(
        self,
        db: AsyncSession,
        recipient_id: UUID
    ) -> Optional[MessageRecipient]:
        """
        既読化（is_read=True, read_at=now()）
        - commitはエンドポイントで実行
        """
        pass

    async def get_unread_count(
        self,
        db: AsyncSession,
        recipient_staff_id: UUID
    ) -> int:
        """未読件数取得"""
        pass

    async def get_stats(
        self,
        db: AsyncSession,
        message_id: UUID
    ) -> dict:
        """
        メッセージの統計取得
        - total_recipients
        - read_count
        - unread_count
        - read_rate
        """
        pass
```

**レビューポイント**:
- [ ] **CRITICAL**: commitを呼び出していないこと
- [ ] バルク作成でループ内commitをしていないこと
- [ ] チャンク処理の実装
- [ ] db.add_all() でまとめて追加
- [ ] flush() で ID 取得後も commit せず

**テスト**:
- `tests/crud/test_crud_message_recipient.py`

---

### 3.3 CRUDMessageAuditLog 実装

**タスク**: 監査ログのCRUD操作

**ファイル**: `k_back/app/crud/crud_message_audit_log.py`

**実装内容**:

```python
class CRUDMessageAuditLog(CRUDBase[MessageAuditLog, MessageAuditLogCreate, MessageAuditLogUpdate]):

    async def log_action(
        self,
        db: AsyncSession,
        *,
        staff_id: Optional[UUID],
        message_id: Optional[UUID],
        action: str,
        ip_address: Optional[str],
        user_agent: Optional[str],
        success: bool = True,
        error_message: Optional[str] = None
    ) -> MessageAuditLog:
        """監査ログ記録（commitはエンドポイントで）"""
        pass
```

**レビューポイント**:
- [ ] commitを呼び出していないこと
- [ ] 必須フィールドの検証

**テスト**:
- `tests/crud/test_crud_message_audit_log.py`

---

## Phase 4: API層（エンドポイント）

### 4.1 個別メッセージ送信

**エンドポイント**: `POST /api/v1/messages/personal`

**ファイル**: `k_back/app/api/v1/endpoints/messages.py`

**実装内容**:
- 送信者と受信者が同じ事務所に所属しているか確認
- メッセージ本体作成 + 受信者レコード作成（1トランザクション）
- 監査ログ記録
- **最後に1回だけ db.commit()**

**セキュリティ**:
- [ ] 送信者と受信者の office_id 一致チェック
- [ ] 受信者が存在するか確認
- [ ] レート制限（例: 1分に10件まで）

**レビューポイント**:
- [ ] commitが1回だけ
- [ ] 例外時のロールバック処理
- [ ] 権限チェックの実装

**テスト**:
- `tests/api/v1/test_messages_personal.py`

---

### 4.2 一斉通知送信

**エンドポイント**: `POST /api/v1/messages/announcement`

**ファイル**: `k_back/app/api/v1/endpoints/messages.py`

**実装内容**:
- オーナーのみ実行可能（権限チェック）
- 事務所の全スタッフを取得
- メッセージ本体作成
- 受信者レコードをバルク作成（チャンク処理）
- 監査ログ記録
- **最後に1回だけ db.commit()**

**パフォーマンス**:
- [ ] バルクインサート（db.add_all）
- [ ] チャンク処理（1000件ずつ）
- [ ] トランザクション最適化

**レビューポイント**:
- [ ] オーナー権限チェック
- [ ] commitが1回だけ
- [ ] チャンク処理の実装
- [ ] 大量配信時のタイムアウト対策

**テスト**:
- `tests/api/v1/test_messages_announcement.py`
- パフォーマンステスト（100〜1000件）

---

### 4.3 受信箱取得

**エンドポイント**: `GET /api/v1/messages/inbox`

**クエリパラメータ**:
- is_read: Optional[bool] - 未読フィルタ
- skip: int = 0
- limit: int = 100

**実装内容**:
- 自分宛のメッセージ一覧を取得
- 未読フィルタ対応
- ページネーション

**レビューポイント**:
- [ ] 自分宛のメッセージのみ取得
- [ ] インデックスの活用（パフォーマンス）

**テスト**:
- `tests/api/v1/test_messages_inbox.py`

---

### 4.4 既読化

**エンドポイント**: `POST /api/v1/messages/{message_id}/read`

**実装内容**:
- 自分宛のメッセージか確認
- 既読化（is_read=True, read_at=now()）
- 監査ログ記録
- **commitは1回だけ**

**レビューポイント**:
- [ ] 受信者本人のみ既読化可能
- [ ] 既に既読の場合の処理
- [ ] commitが1回だけ

**テスト**:
- `tests/api/v1/test_messages_read.py`

---

### 4.5 統計取得

**エンドポイント**: `GET /api/v1/messages/{message_id}/stats`

**実装内容**:
- 送信者のみアクセス可能
- 既読数、未読数、既読率を返す

**レビューポイント**:
- [ ] 送信者のみアクセス可能
- [ ] 統計の正確性

**テスト**:
- `tests/api/v1/test_messages_stats.py`

---

### 4.6 未読件数取得

**エンドポイント**: `GET /api/v1/messages/unread-count`

**実装内容**:
- 未読件数を返す（通知バッジ用）

**テスト**:
- `tests/api/v1/test_messages_unread_count.py`

---

## Phase 5: 監査ログ統合

### 5.1 監査ログの記録

**実装箇所**: 各エンドポイント

**記録対象**:
- メッセージ送信（sent）
- 既読化（read）
- アーカイブ（archived）
- 削除（deleted）

**記録内容**:
- staff_id: 操作者
- message_id: 対象メッセージ
- action: 操作種別
- ip_address: クライアントIP
- user_agent: User-Agent
- success: 成功/失敗
- error_message: エラー内容（失敗時）

**レビューポイント**:
- [ ] すべての操作で監査ログを記録
- [ ] 失敗時もログ記録
- [ ] 個人情報の適切な取り扱い

---

## Phase 6: テスト（TDD）

### 6.1 ユニットテスト

**対象**:
- モデル: `tests/models/test_message.py`
- スキーマ: `tests/schemas/test_message.py`
- CRUD: `tests/crud/test_crud_message.py`, `test_crud_message_recipient.py`, `test_crud_message_audit_log.py`

**テストケース例**:
- モデルのインスタンス化
- リレーションの取得
- スキーマバリデーション
- CRUD操作の基本動作
- バルク作成の動作確認

---

### 6.2 統合テスト（API）

**対象**:
- `tests/api/v1/test_messages_personal.py`
- `tests/api/v1/test_messages_announcement.py`
- `tests/api/v1/test_messages_inbox.py`
- `tests/api/v1/test_messages_read.py`
- `tests/api/v1/test_messages_stats.py`
- `tests/api/v1/test_messages_unread_count.py`

**テストケース例**:
- 個別メッセージ送信（成功/失敗）
- 一斉通知送信（オーナーのみ）
- 受信箱取得（フィルタ、ページネーション）
- 既読化（権限チェック）
- 統計取得（送信者のみ）
- 未読件数取得

---

### 6.3 パフォーマンステスト

**対象**:
- 一斉通知の大量配信（100〜1000件）

**テストケース**:
- 100人への一斉通知
- 500人への一斉通知
- 1000人への一斉通知
- レスポンスタイム計測
- データベース負荷確認

**ファイル**: `tests/performance/test_message_bulk_insert.py`

---

## Phase 7: レビュー & セキュリティチェック

### 7.1 トランザクション管理レビュー

**チェック項目**:
- [ ] commitがエンドポイントでのみ実行されているか
- [ ] CRUD層でcommitを呼び出していないか
- [ ] 例外時にrollbackが実行されるか（AsyncSessionのコンテキストマネージャで自動）
- [ ] flush()のみで処理が完結しているか
- [ ] ループ内でcommitしていないか

**確認コマンド**:
```bash
# commitの使用箇所を確認
grep -rn "await db.commit()" k_back/app/crud/crud_message*.py
# 結果: 0件であること（CRUD層でcommitしないこと）

grep -rn "await db.commit()" k_back/app/api/v1/endpoints/messages.py
# 結果: 各エンドポイントで1回のみ
```

---

### 7.2 セキュリティレビュー

**チェック項目**:
- [ ] 権限チェック
  - [ ] 送信者と受信者が同じ事務所か
  - [ ] 一斉通知はオーナーのみ
  - [ ] 既読化は受信者本人のみ
  - [ ] 統計取得は送信者のみ
- [ ] XSS対策
  - [ ] content のサニタイズ（フロントエンドで自動エスケープ）
  - [ ] dangerouslySetInnerHTML を使用していないか（フロントエンド）
- [ ] レート制限
  - [ ] 個別メッセージ送信: 1分に10件
  - [ ] 一斉通知: 1時間に5件（オーナーのみ）
- [ ] 入力バリデーション
  - [ ] title: 最大200文字
  - [ ] content: 最大10,000文字
  - [ ] recipient_staff_ids: 1人以上

---

### 7.3 パフォーマンスレビュー

**チェック項目**:
- [ ] バルクインサートの実装
- [ ] チャンク処理（1000件ずつ）
- [ ] インデックスの活用
- [ ] N+1問題の回避（selectinload）
- [ ] 大量配信のタイムアウト対策

---

## Phase 8: 実装完了後の確認

### 8.1 最終チェックリスト

**データベース**:
- [ ] マイグレーション実行済み
- [ ] テーブル作成確認
- [ ] インデックス作成確認

**コード**:
- [ ] モデル作成済み
- [ ] スキーマ作成済み
- [ ] CRUD作成済み
- [ ] API作成済み
- [ ] 監査ログ実装済み

**テスト**:
- [ ] ユニットテスト全通過
- [ ] 統合テスト全通過
- [ ] パフォーマンステスト実施済み

**セキュリティ**:
- [ ] 権限チェック実装済み
- [ ] XSS対策済み
- [ ] レート制限実装済み

**トランザクション**:
- [ ] commitがエンドポイントでのみ実行
- [ ] CRUD層でcommitしていない

---

## 実装順序まとめ

1. **マイグレーション作成 & 実行**
2. **モデル作成**
3. **モデルのユニットテスト作成 & 実行**
4. **スキーマ作成**
5. **スキーマのユニットテスト作成 & 実行**
6. **CRUD作成**
7. **CRUDのユニットテスト作成 & 実行**
8. **API作成**
9. **API統合テスト作成 & 実行**
10. **監査ログ統合**
11. **パフォーマンステスト実施**
12. **レビュー（トランザクション、セキュリティ、パフォーマンス）**

---

## 備考

- このドキュメントはCRUD実装のタスクリストとレビュー要件を定義したものです
- 実装時は各Phaseごとにテストを先に書いてから実装してください
- トランザクション管理は必ず守ってください（commitはエンドポイントでのみ）
- セキュリティ要件は妥協しないでください
