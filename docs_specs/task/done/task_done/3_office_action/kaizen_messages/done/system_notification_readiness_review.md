# システム通知対応可能性レビュー

**レビュー日**: 2025-11-24
**レビュー対象**: メッセージ機能のシステム通知対応（スタッフ削除・事務所名変更）
**レビュアー**: バックエンド調査担当

---

## 1. エグゼクティブサマリー

### 1.1 結論

**現在のメッセージ機能は、システム通知機能に対応できる設計になっています。**

ただし、以下の追加実装が必要です：

- ✅ **基礎設計**: 完了（MessageType.system、Nullableなsender、バルクインサート対応）
- ⚠️ **部分実装**: システム通知用のCRUD/APIが未実装
- ❌ **未実装**: イベント連携メカニズム（スタッフ削除・事務所名変更時の自動通知）

### 1.2 対応可能性評価

| 要件 | 現状 | 対応可能性 | 備考 |
|------|------|-----------|------|
| スタッフ削除時の通知 | 未実装 | ✅ 高 | 基礎設計完了、追加実装で対応可能 |
| 事務所名変更時の通知 | 未実装 | ✅ 高 | 基礎設計完了、追加実装で対応可能 |
| システム送信者なし通知 | 対応済み | ✅ 可能 | sender_staff_id が nullable |
| 大量スタッフへの一斉通知 | 対応済み | ✅ 可能 | バルクインサート実装済み |
| 受信箱でのフィルタ | 対応済み | ✅ 可能 | message_type フィルタ実装済み |

---

## 2. 現状分析

### 2.1 実装済み機能

#### 2.1.1 データベース設計

**✅ MessageType.system が定義済み** (`k_back/app/models/enums.py:245-250`)

```python
class MessageType(str, enum.Enum):
    personal = 'personal'           # 個別メッセージ
    announcement = 'announcement'   # 一斉通知（お知らせ）
    system = 'system'               # システム通知 ← 定義済み
    inquiry = 'inquiry'             # 問い合わせ
```

**✅ sender_staff_id が Nullable** (`k_back/app/models/message.py:38-42`)

```python
sender_staff_id: Mapped[uuid.UUID] = mapped_column(
    ForeignKey('staffs.id', ondelete="SET NULL"),
    nullable=True,  # システム通知（送信者なし）に対応
    index=True
)
```

これにより、システムが自動生成する通知（送信者がいない）に対応可能。

**✅ messages テーブル構造**

| カラム | タイプ | 説明 | システム通知への適用 |
|--------|--------|------|---------------------|
| id | UUID | メッセージID | 自動生成 |
| sender_staff_id | UUID (nullable) | 送信者ID | NULL（システム送信） |
| office_id | UUID | 事務所ID | 通知対象の事務所 |
| message_type | MessageType | メッセージタイプ | 'system' |
| priority | MessagePriority | 優先度 | 'high' or 'urgent' |
| title | String(200) | タイトル | 例: "スタッフが削除されました" |
| content | Text | 本文 | 詳細メッセージ |
| created_at | DateTime | 作成日時 | 自動記録 |

**✅ message_recipients テーブル構造**

- 受信者ごとの既読/未読管理が可能
- 大量の受信者に対応（バルクインサート実装済み）

#### 2.1.2 CRUD層

**✅ バルクインサート対応** (`k_back/app/crud/crud_message.py:80-139`)

`create_announcement()` メソッドで以下が実装済み：
- 500件ごとのチャンク処理
- add_all によるバルクインサート
- トランザクション管理（flush のみ、commit はエンドポイント）

**現在の対応状況：**
- ✅ `create_personal_message()`: 個別メッセージ作成
- ✅ `create_announcement()`: 一斉通知作成
- ❌ `create_system_notification()`: システム通知作成（未実装）

#### 2.1.3 API層

**✅ 受信箱API** (`k_back/app/api/v1/endpoints/messages.py:162-230`)

```python
@router.get("/inbox", response_model=MessageInboxResponse)
async def get_inbox_messages(
    *,
    message_type: Optional[MessageType] = Query(None, description="メッセージタイプフィルタ"),
    # ...
):
```

- message_type パラメータでフィルタ可能
- MessageType.system を指定してシステム通知のみ取得可能

**現在の対応状況：**
- ✅ POST `/personal`: 個別メッセージ送信
- ✅ POST `/announcement`: 一斉通知送信
- ❌ POST `/system`: システム通知送信（未実装）
- ✅ GET `/inbox`: 受信箱取得（systemタイプもフィルタ可能）

#### 2.1.4 スキーマ層

**現在の対応状況：**
- ✅ `MessagePersonalCreate`: 個別メッセージ作成スキーマ
- ✅ `MessageAnnouncementCreate`: 一斉通知作成スキーマ
- ❌ `MessageSystemCreate`: システム通知作成スキーマ（未実装）

### 2.2 未実装機能

#### 2.2.1 システム通知専用のCRUD/API

**必要な実装：**

1. **CRUD層** (`crud_message.py`)
   ```python
   async def create_system_notification(
       self,
       db: AsyncSession,
       *,
       office_id: UUID,
       recipient_ids: List[UUID],
       title: str,
       content: str,
       priority: MessagePriority = MessagePriority.high
   ) -> Message:
       """システム通知を作成（送信者なし）"""
       # sender_staff_id = None
       # message_type = MessageType.system
       # バルクインサート処理
   ```

2. **スキーマ層** (`schemas/message.py`)
   ```python
   class MessageSystemCreate(BaseModel):
       """システム通知作成スキーマ（内部API用）"""
       office_id: uuid.UUID
       recipient_ids: List[uuid.UUID]
       title: str
       content: str
       priority: MessagePriority = MessagePriority.high
   ```

3. **サービス層** (新規: `services/system_notification_service.py`)
   ```python
   class SystemNotificationService:
       async def notify_staff_deleted(
           self,
           db: AsyncSession,
           office_id: UUID,
           deleted_staff_name: str
       ):
           """スタッフ削除時のシステム通知"""

       async def notify_office_name_changed(
           self,
           db: AsyncSession,
           office_id: UUID,
           old_name: str,
           new_name: str
       ):
           """事務所名変更時のシステム通知"""
   ```

#### 2.2.2 イベント連携メカニズム

**現在の状況：**

1. **スタッフ削除機能** (`md_files_design_note/task/3_office_action/staff_delete.md`)
   - 要件定義書が存在
   - 実装はまだ（`k_back/app/api/v1/endpoints/staffs.py` に削除エンドポイントなし）
   - システム通知との連携は設計されていない

2. **事務所名変更機能**
   - `k_back/app/api/v1/endpoints/offices.py` に更新エンドポイントなし
   - システム通知との連携は設計されていない

**必要な実装：**

1. スタッフ削除エンドポイントでの通知生成
   ```python
   # DELETE /api/v1/auth/staffs/{staff_id}
   async def delete_staff(...):
       # 削除処理
       target_staff.is_deleted = True

       # システム通知を生成
       await system_notification_service.notify_staff_deleted(
           db=db,
           office_id=target_staff.office_id,
           deleted_staff_name=f"{target_staff.last_name} {target_staff.first_name}"
       )

       await db.commit()
   ```

2. 事務所名変更エンドポイントでの通知生成
   ```python
   # PATCH /api/v1/offices/{office_id}
   async def update_office(...):
       old_name = office.name
       office.name = new_name

       # システム通知を生成
       await system_notification_service.notify_office_name_changed(
           db=db,
           office_id=office.id,
           old_name=old_name,
           new_name=new_name
       )

       await db.commit()
   ```

---

## 3. システム通知ユースケース設計

### 3.1 スタッフ削除時の通知

#### 3.1.1 トリガー条件
- Owner がスタッフを削除した時（`DELETE /api/v1/auth/staffs/{staff_id}`）

#### 3.1.2 通知内容

**タイトル**: `スタッフが削除されました`

**本文例**:
```
スタッフ「{deleted_staff_last_name} {deleted_staff_first_name}」が削除されました。

削除日時: {deleted_at}
削除者: {performer_name}

このスタッフはログインできなくなりました。
```

#### 3.1.3 受信者
- 削除されたスタッフが所属していた事務所の全スタッフ（削除されたスタッフ自身を除く）

#### 3.1.4 メッセージ属性
- `message_type`: `MessageType.system`
- `sender_staff_id`: `None` (システム送信)
- `priority`: `MessagePriority.high`
- `office_id`: 削除されたスタッフの事務所ID

### 3.2 事務所名変更時の通知

#### 3.2.1 トリガー条件
- Owner が事務所名を変更した時（`PATCH /api/v1/offices/{office_id}`）

#### 3.2.2 通知内容

**タイトル**: `事務所名が変更されました`

**本文例**:
```
事務所名が変更されました。

変更前: {old_name}
変更後: {new_name}

変更日時: {updated_at}
変更者: {performer_name}
```

#### 3.2.3 受信者
- 事務所に所属する全スタッフ（変更を実行したOwnerを除く）

#### 3.2.4 メッセージ属性
- `message_type`: `MessageType.system`
- `sender_staff_id`: `None` (システム送信)
- `priority`: `MessagePriority.normal`
- `office_id`: 変更された事務所ID

---

## 4. 実装推奨事項

### 4.1 優先順位

#### フェーズ1: システム通知の基盤実装（必須）

1. **CRUDメソッドの追加** (`crud_message.py`)
   - `create_system_notification()` の実装
   - 既存の `create_announcement()` をベースにして、sender_staff_id を None にする

2. **スキーマの追加** (`schemas/message.py`)
   - `MessageSystemCreate` スキーマの定義
   - 内部API用なので、バリデーションは最小限でOK

3. **サービス層の作成** (`services/system_notification_service.py`)
   - `notify_staff_deleted()` メソッド
   - `notify_office_name_changed()` メソッド
   - 通知メッセージのテンプレート管理

#### フェーズ2: イベント連携の実装（必須）

4. **スタッフ削除エンドポイントの実装** (`api/v1/endpoints/auth.py` または `staffs.py`)
   - `DELETE /api/v1/auth/staffs/{staff_id}` の実装
   - 削除処理後にシステム通知を生成

5. **事務所更新エンドポイントの実装** (`api/v1/endpoints/offices.py`)
   - `PATCH /api/v1/offices/{office_id}` の実装または拡張
   - 名前変更検出とシステム通知生成

#### フェーズ3: フロントエンド対応（推奨）

6. **システム通知の表示** (`k_front`)
   - 受信箱でのシステム通知表示
   - システム通知専用のアイコン・スタイル
   - 送信者なしの表示対応（"システム" などのラベル表示）

### 4.2 技術的推奨事項

#### 4.2.1 トランザクション管理

システム通知の生成は、元のイベント（削除・更新）と同一トランザクションで実行すること。

```python
async with db.begin():
    # メインの処理（削除・更新）
    target_staff.is_deleted = True

    # システム通知を生成（同一トランザクション内）
    await system_notification_service.notify_staff_deleted(
        db=db,
        office_id=target_staff.office_id,
        deleted_staff_name=f"{target_staff.last_name} {target_staff.first_name}"
    )

    # 監査ログ記録
    # ...

# コミットはエンドポイントで一度だけ
await db.commit()
```

**理由**:
- メイン処理が失敗した場合、通知も送信されない（整合性）
- 通知生成が失敗した場合、メイン処理もロールバック（確実性）

#### 4.2.2 エラーハンドリング

システム通知の生成失敗は、メイン処理の成功を妨げないように検討すること。

**オプション1**: 同一トランザクション（推奨）
- 通知生成失敗 → 全体をロールバック
- メリット: 整合性が保たれる
- デメリット: 通知機能の問題でメイン機能が使えなくなる

**オプション2**: 別トランザクション（代替案）
- 通知生成失敗 → ログに記録してメイン処理は成功
- メリット: メイン機能の可用性が高い
- デメリット: 通知が送信されない可能性がある

**推奨**: オプション1（同一トランザクション）
- システム通知は重要な情報なので、確実に送信すべき
- 通知生成の失敗は稀（DBエラーなど）なので、許容可能

#### 4.2.3 パフォーマンス

大量のスタッフへの通知は、既存のバルクインサート機能を活用すること。

```python
# 既存の create_announcement() をベースにする
async def create_system_notification(
    self,
    db: AsyncSession,
    *,
    obj_in: Dict[str, Any]
) -> Message:
    recipient_ids = list(set(obj_in.get("recipient_ids", [])))

    # メッセージ本体を作成
    message = Message(
        sender_staff_id=None,  # システム送信
        office_id=obj_in["office_id"],
        message_type=MessageType.system,
        priority=obj_in.get("priority", MessagePriority.high),
        title=obj_in["title"],
        content=obj_in["content"]
    )
    db.add(message)
    await db.flush()

    # バルクインサート（500件チャンク）
    chunk_size = 500
    for i in range(0, len(recipient_ids), chunk_size):
        chunk = recipient_ids[i:i + chunk_size]
        recipients = [
            MessageRecipient(
                message_id=message.id,
                recipient_staff_id=recipient_id,
                is_read=False,
                is_archived=False
            )
            for recipient_id in chunk
        ]
        db.add_all(recipients)
        await db.flush()

    await db.refresh(message, ["recipients"])
    return message
```

#### 4.2.4 テスト要件

**ユニットテスト**:
- ✅ `create_system_notification()` のテスト
- ✅ sender_staff_id が None でメッセージが作成できることを確認
- ✅ message_type が system になることを確認

**統合テスト**:
- ✅ スタッフ削除時にシステム通知が生成されることを確認
- ✅ 事務所名変更時にシステム通知が生成されることを確認
- ✅ トランザクション整合性のテスト（削除失敗時に通知も送信されないこと）

**APIテスト**:
- ✅ 受信箱APIでシステム通知を取得できることを確認
- ✅ message_type=system でフィルタできることを確認
- ✅ sender_name が None または "システム" と表示されることを確認

---

## 5. リスクと制約事項

### 5.1 技術的リスク

| リスク | 影響度 | 対策 |
|--------|--------|------|
| システム通知生成失敗でメイン処理が失敗 | 中 | エラーハンドリングとロギングを強化 |
| 大量スタッフへの通知でパフォーマンス低下 | 低 | バルクインサート実装済み、500件チャンク処理 |
| 送信者なし通知の表示崩れ | 低 | フロントエンドで "システム" ラベル表示 |

### 5.2 設計上の制約

1. **sender_staff_id が nullable なので、誰が通知を送ったか不明**
   - 対策: 本文に「削除者: {performer_name}」などの情報を含める

2. **システム通知は削除できない設計が必要**
   - 対策: フロントエンドでシステム通知の削除ボタンを非表示にする

3. **既読管理はユーザーごとに可能**
   - 現在の message_recipients 設計で対応可能

---

## 6. 結論と次のステップ

### 6.1 総合評価

**✅ 現在のメッセージ機能は、システム通知に対応可能**

- データベース設計: 完璧
- CRUD層: 90%完了（システム通知専用メソッドの追加のみ）
- API層: 70%完了（受信箱は対応済み、送信APIの追加が必要）
- イベント連携: 未実装（新規実装が必要）

### 6.2 推定工数

| タスク | 工数（人日） | 優先度 |
|--------|------------|--------|
| CRUDメソッド追加 | 0.5 | 高 |
| スキーマ定義 | 0.25 | 高 |
| サービス層実装 | 1.0 | 高 |
| スタッフ削除エンドポイント + 通知連携 | 2.0 | 高 |
| 事務所更新エンドポイント + 通知連携 | 1.5 | 高 |
| フロントエンド対応 | 2.0 | 中 |
| テスト実装 | 1.5 | 高 |
| **合計** | **8.75** | - |

### 6.3 次のステップ

#### ステップ1: システム通知基盤の実装（必須）
1. `crud_message.py` に `create_system_notification()` を追加
2. `schemas/message.py` に `MessageSystemCreate` を追加
3. `services/system_notification_service.py` を新規作成

#### ステップ2: スタッフ削除機能の実装と連携（必須）
1. `DELETE /api/v1/auth/staffs/{staff_id}` エンドポイントを実装
2. 削除処理後にシステム通知を生成する処理を追加
3. テストコードの実装

#### ステップ3: 事務所名変更機能の実装と連携（必須）
1. `PATCH /api/v1/offices/{office_id}` エンドポイントを実装または拡張
2. 名前変更検出とシステム通知生成を追加
3. テストコードの実装

#### ステップ4: フロントエンド対応（推奨）
1. 受信箱でシステム通知を表示
2. 送信者なしの表示対応（"システム" ラベル）
3. システム通知専用のアイコン・スタイル

---

## 7. 参考資料

### 7.1 関連ファイル

**バックエンド（モデル・CRUD・API）**:
- `k_back/app/models/message.py`: Message, MessageRecipient モデル（lines 24-185）
- `k_back/app/models/enums.py`: MessageType 定義（lines 245-250）
- `k_back/app/crud/crud_message.py`: メッセージCRUD操作（lines 1-427）
- `k_back/app/api/v1/endpoints/messages.py`: メッセージAPIエンドポイント（lines 1-367）
- `k_back/app/schemas/message.py`: メッセージスキーマ定義（lines 1-246）

**ドキュメント**:
- `md_files_design_note/task/2_messages/message_design.md`: メッセージ機能要件定義
- `md_files_design_note/task/3_office_action/staff_delete.md`: スタッフ削除機能要件定義

### 7.2 設計パターン参考

**既存の announcement 実装をベースにする**:
- `crud_message.create_announcement()` (k_back/app/crud/crud_message.py:80-139)
- `messages.send_announcement()` (k_back/app/api/v1/endpoints/messages.py:100-159)

これらを参考に、sender_staff_id を None にするだけでシステム通知に対応可能。

---

**レビュー完了**: 2025-11-24
