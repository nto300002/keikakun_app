# メッセージ機能 実装レビュー要件定義

最終更新: 2025-11-23
作成者: API実装担当者

## 1. 実装方針

### 1.1 TDD（テスト駆動開発）の適用
- テストを先に作成してから実装を行う
- Red → Green → Refactor のサイクルを守る
- 各レイヤー（スキーマ、CRUD、API）ごとにテストを作成

### 1.2 既存コードの活用
- Notice機能の実装を参考にする
- CRUDBaseクラスを継承して効率的に実装
- 既存の認証・認可の仕組みを活用

## 2. 実装タスクの詳細

### Phase 1: データ層の準備
1. **マイグレーションの実行**
   - 既存のSQLファイルを基にAlembicマイグレーションファイルを作成
   - messages, message_recipients, message_audit_logs テーブルを作成
   - インデックスと制約を適切に設定

2. **モデルの確認**
   - ✅ 既存の Message, MessageRecipient モデルを確認
   - リレーションシップが正しく設定されているか確認
   - Enumが正しく定義されているか確認

### Phase 2: スキーマの実装（TDD）
1. **スキーマ設計**
   - `MessageCreate`: 個別メッセージ送信用
   - `MessageAnnouncementCreate`: 一斉通知送信用
   - `MessageResponse`: メッセージ詳細レスポンス
   - `MessageInboxResponse`: 受信箱リストアイテム
   - `MessageListResponse`: 受信箱リストレスポンス
   - `MessageStatsResponse`: 統計情報レスポンス

2. **バリデーション要件**
   - タイトル: 1-200文字
   - 本文: 1-10000文字
   - 受信者ID: UUID形式、空でないこと
   - メッセージタイプ: Enumで定義された値のみ
   - 優先度: Enumで定義された値のみ

3. **テストケース（test_message_schema.py）**
   - ✓ 有効なデータでスキーマ作成が成功すること
   - ✓ タイトルが空の場合にバリデーションエラー
   - ✓ タイトルが200文字を超える場合にエラー
   - ✓ 本文が10000文字を超える場合にエラー
   - ✓ 無効なUUIDでエラー
   - ✓ 無効なEnumでエラー

### Phase 3: CRUD層の実装（TDD）
1. **CRUD機能一覧**
   - `create_personal_message`: 個別メッセージ送信
   - `create_announcement`: 一斉通知送信（バルクインサート）
   - `get_inbox_messages`: 受信箱取得
   - `get_unread_messages`: 未読メッセージ取得
   - `mark_as_read`: 既読化
   - `get_message_stats`: 統計取得
   - `get_unread_count`: 未読件数取得

2. **トランザクション管理要件**
   - ❌ ループ内でcommitしない
   - ✅ commitはエンドポイントでのみ実行
   - ✅ 例外発生時は必ずrollback
   - ✅ 一斉通知はバルクインサートを使用
   - ✅ チャンク処理（500-2000件）で大量データに対応

3. **テストケース（test_crud_message.py）**
   - ✓ 個別メッセージの作成と取得
   - ✓ 一斉通知の作成（100人、1000人）
   - ✓ 受信箱の取得とフィルタリング
   - ✓ 未読メッセージのみ取得
   - ✓ 既読化の動作確認
   - ✓ 統計情報の正確性確認
   - ✓ 同一メッセージ・同一受信者の重複防止
   - ✓ トランザクションロールバックの確認

### Phase 4: API層の実装（TDD）
1. **エンドポイント一覧**
   ```
   POST   /api/v1/messages/personal          - 個別メッセージ送信
   POST   /api/v1/messages/announcement      - 一斉通知送信
   GET    /api/v1/messages/inbox              - 受信箱取得
   GET    /api/v1/messages/unread-count       - 未読件数取得
   POST   /api/v1/messages/{id}/read          - 既読化
   GET    /api/v1/messages/{id}/stats         - 統計取得
   GET    /api/v1/messages/{id}               - メッセージ詳細取得
   ```

2. **権限チェック要件**
   - 個別メッセージ: 送信者と受信者が同じ事務所に所属
   - 一斉通知: 送信者がowner権限を持つこと
   - 既読化: 受信者本人のみ
   - 統計閲覧: 送信者本人のみ

3. **テストケース（test_messages.py）**
   - ✓ 個別メッセージ送信の成功
   - ✓ 他の事務所のスタッフへの送信は403エラー
   - ✓ 一斉通知送信の成功（owner権限）
   - ✓ 一斉通知送信の失敗（owner以外）
   - ✓ 受信箱取得の成功
   - ✓ 未読フィルタの動作確認
   - ✓ 既読化の成功
   - ✓ 他人のメッセージを既読化しようとすると403エラー
   - ✓ 統計取得の成功（送信者のみ）
   - ✓ 統計取得の失敗（送信者以外）
   - ✓ 未読件数取得の成功

### Phase 5: セキュリティレビュー
1. **XSS対策**
   - フロントエンドでReactの自動エスケープを利用
   - dangerouslySetInnerHTMLを使用しない
   - サーバー側でもHTMLタグのバリデーション

2. **権限チェック**
   - 全エンドポイントで認証チェック
   - 事務所IDの一致確認
   - ロールベースのアクセス制御

3. **レート制限**
   - 一斉通知: 1時間あたり10回まで
   - 個別メッセージ: 1分あたり30回まで
   - APIキーまたはセッションベースで制限

### Phase 6: パフォーマンステスト
1. **テストシナリオ**
   - 100人への一斉通知: 1秒以内
   - 1000人への一斉通知: 5秒以内
   - 受信箱取得（100件）: 500ms以内
   - 未読件数取得: 100ms以内

2. **最適化ポイント**
   - バルクインサートの使用
   - 適切なインデックス設定
   - N+1問題の回避（selectinload使用）
   - チャンク処理の実装

### Phase 7: 監査ログ機能
1. **監査対象の操作**
   - メッセージ送信（sent）
   - メッセージ既読（read）
   - メッセージアーカイブ（archived）
   - メッセージ削除（deleted）

2. **監査ログの内容**
   - スタッフID
   - メッセージID
   - 操作種別
   - IPアドレス
   - User-Agent
   - 成功/失敗フラグ
   - エラーメッセージ

## 3. レビューチェックリスト

### コード品質
- [ ] コードがPEP8に準拠している
- [ ] 型ヒントが正しく設定されている
- [ ] docstringが適切に記述されている
- [ ] 変数名・関数名が適切である

### トランザクション管理
- [ ] commitが複数回行われていないか
- [ ] commitはエンドポイントでのみ行っているか
- [ ] 例外時に必ずロールバックしているか
- [ ] ループ内でcommitしていないか

### セキュリティ
- [ ] SQLインジェクション対策ができているか
- [ ] XSS対策ができているか
- [ ] 権限チェックが適切に行われているか
- [ ] レート制限が実装されているか

### パフォーマンス
- [ ] N+1問題が発生していないか
- [ ] バルクインサートが適切に使われているか
- [ ] インデックスが適切に設定されているか
- [ ] 不要なデータ取得がないか

### テスト
- [ ] 全ての主要機能にテストがあるか
- [ ] エッジケースがテストされているか
- [ ] エラーケースがテストされているか
- [ ] テストカバレッジが80%以上か

## 4. 実装順序

1. **スキーマのテストと実装**
   - test_message_schema.py を作成（Red）
   - app/schemas/message.py を実装（Green）
   - リファクタリング（Refactor）

2. **CRUDのテストと実装**
   - test_crud_message.py を作成（Red）
   - app/crud/crud_message.py を実装（Green）
   - リファクタリング（Refactor）

3. **APIエンドポイントのテストと実装**
   - test_messages.py を作成（Red）
   - app/api/v1/endpoints/messages.py を実装（Green）
   - リファクタリング（Refactor）

4. **監査ログのテストと実装**
   - message_audit_logs のモデル確認
   - 監査ログCRUDの実装
   - エンドポイントへの統合

5. **パフォーマンステスト**
   - 大量データでの動作確認
   - ボトルネックの特定と最適化

6. **セキュリティレビュー**
   - 全エンドポイントの権限チェック確認
   - レート制限の実装確認
   - XSS対策の確認

## 5. 注意事項

### データ整合性
- message_recipients テーブルの UNIQUE制約（message_id, recipient_staff_id）を活用
- トランザクション内で Message と MessageRecipient を同時に作成
- 外部キー制約による参照整合性の保証

### スケーラビリティ
- 受信者数が多い場合（1000人以上）はチャンク処理を実装
- 将来的にはバックグラウンドジョブ（Celery等）の導入を検討
- キャッシュの活用（未読件数など）

### 後方互換性
- 既存のnotices機能と並行運用
- notices と messages を統合表示する機能は将来の拡張として保留

## 6. 参考資料

- Notice機能の実装: `app/api/v1/endpoints/notices.py`
- CRUDBase: `app/crud/base.py`
- 認証・認可: `app/api/deps.py`
- マイグレーション: `md_files_design_note/task/2_messages/migration_messages_tables.sql`
