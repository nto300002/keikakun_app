# メッセージ機能 API設計書

最終更新: 2025-11-23

## 概要

メッセージ機能のAPIエンドポイント設計書。個別メッセージ送信、一斉通知、受信箱、統計情報などのエンドポイントを定義する。

## 認証・認可

すべてのエンドポイントは認証が必要。
- 認証: JWT Bearer Token
- 権限チェック: 各エンドポイントで実施

## エンドポイント一覧

### 1. 個別メッセージ送信

**POST** `/api/v1/messages/personal`

個別のスタッフにメッセージを送信する。

**リクエストボディ:**
```json
{
  "recipient_staff_ids": ["uuid1", "uuid2"],
  "title": "メッセージタイトル",
  "content": "メッセージ本文",
  "priority": "normal"  // optional: low, normal, high, urgent
}
```

**レスポンス:** `201 Created`
```json
{
  "id": "message-uuid",
  "sender_staff_id": "sender-uuid",
  "office_id": "office-uuid",
  "message_type": "personal",
  "priority": "normal",
  "title": "メッセージタイトル",
  "content": "メッセージ本文",
  "created_at": "2025-11-23T12:00:00Z",
  "updated_at": "2025-11-23T12:00:00Z",
  "recipient_count": 2
}
```

**エラー:**
- `400 Bad Request`: バリデーションエラー（受信者なし、タイトル空、など）
- `403 Forbidden`: 送信者と受信者が異なる事務所
- `404 Not Found`: 受信者が存在しない

**権限チェック:**
- 送信者と受信者が同じ事務所に所属していること

---

### 2. 一斉通知送信

**POST** `/api/v1/messages/announcement`

事務所内の全スタッフに一斉通知を送信する。

**リクエストボディ:**
```json
{
  "title": "お知らせタイトル",
  "content": "お知らせ本文",
  "priority": "high"  // optional: low, normal, high, urgent
}
```

**レスポンス:** `201 Created`
```json
{
  "id": "message-uuid",
  "sender_staff_id": "sender-uuid",
  "office_id": "office-uuid",
  "message_type": "announcement",
  "priority": "high",
  "title": "お知らせタイトル",
  "content": "お知らせ本文",
  "created_at": "2025-11-23T12:00:00Z",
  "updated_at": "2025-11-23T12:00:00Z",
  "recipient_count": 50
}
```

**エラー:**
- `400 Bad Request`: バリデーションエラー
- `403 Forbidden`: オーナーまたは管理者権限がない

**権限チェック:**
- オーナーまたは管理者権限が必要

---

### 3. 受信箱取得

**GET** `/api/v1/messages/inbox`

自分宛のメッセージ一覧を取得する。

**クエリパラメータ:**
- `is_read` (boolean, optional): 既読フィルタ（true=既読のみ、false=未読のみ）
- `message_type` (string, optional): メッセージタイプ（personal, announcement, system, inquiry）
- `skip` (integer, default=0): スキップ数
- `limit` (integer, default=20, max=100): 取得数上限

**レスポンス:** `200 OK`
```json
{
  "messages": [
    {
      "message_id": "message-uuid",
      "title": "メッセージタイトル",
      "content": "メッセージ本文",
      "message_type": "personal",
      "priority": "normal",
      "created_at": "2025-11-23T12:00:00Z",
      "sender_staff_id": "sender-uuid",
      "sender_name": "山田 太郎",
      "recipient_id": "recipient-uuid",
      "is_read": false,
      "read_at": null,
      "is_archived": false
    }
  ],
  "total": 100,
  "unread_count": 15
}
```

**エラー:**
- なし（空配列を返す）

---

### 4. メッセージを既読にする

**POST** `/api/v1/messages/{message_id}/read`

指定したメッセージを既読にする。

**パスパラメータ:**
- `message_id` (UUID): メッセージID

**レスポンス:** `200 OK`
```json
{
  "id": "recipient-uuid",
  "message_id": "message-uuid",
  "recipient_staff_id": "staff-uuid",
  "is_read": true,
  "read_at": "2025-11-23T12:30:00Z",
  "is_archived": false
}
```

**エラー:**
- `404 Not Found`: メッセージが存在しない、または自分宛でない

**権限チェック:**
- 自分宛のメッセージのみ既読化できる

---

### 5. メッセージ統計取得

**GET** `/api/v1/messages/{message_id}/stats`

メッセージの統計情報を取得する（送信者のみ）。

**パスパラメータ:**
- `message_id` (UUID): メッセージID

**レスポンス:** `200 OK`
```json
{
  "message_id": "message-uuid",
  "total_recipients": 50,
  "read_count": 30,
  "unread_count": 20,
  "read_rate": 0.6
}
```

**エラー:**
- `403 Forbidden`: 送信者以外がアクセスした
- `404 Not Found`: メッセージが存在しない

**権限チェック:**
- メッセージの送信者のみアクセス可能

---

### 6. 未読件数取得

**GET** `/api/v1/messages/unread-count`

自分宛の未読メッセージ件数を取得する（通知バッジ用）。

**レスポンス:** `200 OK`
```json
{
  "unread_count": 15
}
```

**エラー:**
- なし

---

### 7. 全既読化

**POST** `/api/v1/messages/mark-all-read`

自分宛の全未読メッセージを既読にする。

**レスポンス:** `200 OK`
```json
{
  "updated_count": 15
}
```

**エラー:**
- なし

---

### 8. メッセージアーカイブ

**POST** `/api/v1/messages/{message_id}/archive`

メッセージをアーカイブ/解除する。

**パスパラメータ:**
- `message_id` (UUID): メッセージID

**リクエストボディ:**
```json
{
  "is_archived": true
}
```

**レスポンス:** `200 OK`
```json
{
  "id": "recipient-uuid",
  "message_id": "message-uuid",
  "recipient_staff_id": "staff-uuid",
  "is_read": true,
  "read_at": "2025-11-23T12:30:00Z",
  "is_archived": true
}
```

**エラー:**
- `404 Not Found`: メッセージが存在しない、または自分宛でない

**権限チェック:**
- 自分宛のメッセージのみアーカイブできる

---

## セキュリティ要件

1. **認証**: すべてのエンドポイントはJWT認証が必要
2. **権限チェック**:
   - 個別メッセージ: 同じ事務所内のスタッフのみ送信可能
   - 一斉通知: オーナーまたは管理者権限が必要
   - 既読化・アーカイブ: 自分宛のメッセージのみ操作可能
   - 統計情報: 送信者のみアクセス可能
3. **レート制限**: 一斉通知は1分に1回まで（Redis使用）
4. **XSS対策**: フロントエンドで自動エスケープ
5. **監査ログ**: メッセージ送信・既読・削除操作を記録

## エラーハンドリング

すべてのエラーは以下の形式で返す:
```json
{
  "detail": "エラーメッセージ"
}
```

## トランザクション管理

- すべてのエンドポイントでトランザクションを適切に管理
- エラー発生時は自動的にロールバック
- 一斉通知はチャンク処理で500件ごとにコミット

## パフォーマンス考慮事項

1. **受信箱取得**: ページネーションを必須とする（デフォルト20件、最大100件）
2. **一斉通知**: バルクインサートとチャンク処理で高速化
3. **統計情報**: 集計クエリを最適化（インデックス活用）
4. **未読件数**: 軽量なCOUNTクエリで高速応答

## 監査ログ記録

以下の操作を監査ログに記録:
1. メッセージ送信（個別・一斉）
2. メッセージ既読化
3. メッセージアーカイブ
4. 統計情報アクセス

記録項目:
- スタッフID
- メッセージID
- アクション（send, read, archive, stats_view）
- IPアドレス
- User-Agent
- 成功/失敗
- エラーメッセージ（失敗時）
- タイムスタンプ

## テスト要件

各エンドポイントについて以下をテスト:
1. 正常系: 期待通りの動作
2. バリデーションエラー: 不正な入力
3. 権限エラー: 権限のないユーザーのアクセス
4. Not Found: 存在しないリソースへのアクセス
5. トランザクション: ロールバックの確認
