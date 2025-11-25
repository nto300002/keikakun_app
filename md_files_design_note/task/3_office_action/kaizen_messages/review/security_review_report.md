

## 10. セキュリティチェックリスト

### 認証・認可

- [x] JWT認証の実装
- [x] Cookie/Header両対応
- [x] パスワード変更後のトークン無効化
- [x] 権限チェック（Owner/Manager/Employee）
- [x] リソース所有者チェック
- [x] 同一事務所制限

### 入力バリデーション

- [x] Pydanticによるスキーマ検証
- [x] タイトル長の制限（200文字）
- [x] 本文長の制限（10000文字）
- [x] 受信者数の制限（100人）
- [x] 重複受信者の除外

### SQLインジェクション対策

- [x] SQLAlchemy ORM使用
- [x] パラメータ化クエリ
- [x] 動的SQL禁止

### データ保護

- [x] 受信者単位のアクセス制御
- [x] 送信者の統計情報アクセス制限
- [x] 事務所単位の分離

### エラーハンドリング

- [x] 適切なHTTPステータスコード
- [⚠️] エラーメッセージの情報漏洩防止（要改善）

### ロギング・監査

- [⚠️] 監査ログの実装（未実装）
- [x] 監査ログモデルの定義

### パフォーマンス

- [x] N+1クエリの回避
- [x] インデックスの設定
- [x] バルクインサート
- [x] チャンク処理



---

## 11. まとめ

### 強み

1. **堅牢な認証・認可**: JWT認証、パスワード変更時のトークン無効化、適切な権限チェック
2. **適切なアクセス制御**: 受信者単位、送信者単位、事務所単位の分離
3. **優れた設計**: トランザクション管理、バルクインサート、チャンク処理
4. **包括的な入力バリデーション**: Pydanticによる厳格なバリデーション

### 改善が必要な領域

1. **レート制限**: DoS攻撃、スパム対策のため早急に実装が必要
2. **CSRF対策**: Cookie認証を使用しているため、対策の強化が必要
3. **監査ログ**: コンプライアンスとセキュリティインシデント対応のため実装推奨

### 最終評価

メッセージ機能は基本的なセキュリティ対策が適切に実装されており、**本番環境へのデプロイは可能**です。ただし、上記の中程度の改善推奨事項（特にレート制限とCSRF対策）については、早期に実装することを強く推奨します。

---

**レビュー完了日**: 2025-11-24
**次回レビュー推奨日**: 改善実施後、または3ヶ月後


# 改善要件

## セキュリティ

### CSRF対策

#### 現状調査結果

**Cookie設定の状況**
- [✅] **SameSite属性**: 設定済み
  - 本番環境（HTTPS）: `SameSite=None`
  - 開発環境（HTTP）: `SameSite=Lax`
  - 実装箇所: `k_back/app/api/v1/endpoints/auths.py` (行286-291)

- [✅] **Secure属性**: 設定済み
  - 本番環境: `Secure=True`
  - 開発環境: `Secure=False`

- [✅] **HttpOnly属性**: 全環境で `HttpOnly=True`

**CSRFトークンの実装状況**
- [❌] **CSRFトークン**: 未実装
  - FastAPI用のCSRF保護ライブラリ（`fastapi-csrf-protect`等）は未使用
  - CSRFミドルウェアの導入なし
  - CSRFトークン生成・検証の機能なし

**既存のCSRF対策**
- CORS設定による部分的な保護
  - 許可されたオリジンのみからのリクエストを受け付け
  - 実装箇所: `k_back/app/main.py` (行132-138)
- SameSite属性による保護
  - 開発環境: `SameSite=Lax` → GET以外のクロスサイトリクエストでCookieが送信されない
  - **本番環境: `SameSite=None` → CSRF脆弱性のリスクが高い**

#### 問題点

**重大な脆弱性**
1. 本番環境で `SameSite=None` + Cookie認証を使用
2. CSRFトークンによる保護がない
3. CORS設定のみでは、許可されたオリジンからの攻撃は防げない

#### 改善方法

**優先度: 高**

1. **CSRFトークンの実装**
   - `fastapi-csrf-protect` ライブラリの導入
   - トークン生成・検証機能の実装
   - Cookie経由でのトークン送信

2. **Double Submit Cookie パターンの採用**
   - CSRFトークンをCookieとリクエストヘッダーの両方で送信
   - サーバー側で両者の一致を検証

3. **本番環境のSameSite設定を再考**
   - `SameSite=Strict` または `Lax` への変更を検討
   - クロスサイト要件がある場合はCSRFトークン必須

4. **テストの有効化**
   - 既存のCSRFテストのコメントアウトを解除
   - 実装後にテストが通ることを確認

**参考実装**
```python
from fastapi_csrf_protect import CsrfProtect
from fastapi_csrf_protect.exceptions import CsrfProtectError

# 設定
class CsrfSettings(BaseModel):
    secret_key: str = os.getenv("SECRET_KEY")
    cookie_samesite: str = "lax"

@CsrfProtect.load_config
def get_csrf_config():
    return CsrfSettings()

# エンドポイントでの使用
@router.post("/endpoint")
async def protected_endpoint(
    csrf_protect: CsrfProtect = Depends()
):
    await csrf_protect.validate_csrf(request)
    # 処理
```

---

### レート制限

#### 現状調査結果

- [✅] **slowapi ライブラリによるレート制限**: 実装済み
  - 実装箇所: `k_back/app/api/v1/endpoints/auths.py`
  - ログインエンドポイント等に適用済み

#### 改善要件

**データ量制限**
- [❌] 事務所に紐づくメッセージの上限設定: 未実装
- 要件: 事務所ごとに保存できるメッセージ数を50件に制限
- 50件を超えた場合、古いメッセージから自動削除

#### 改善方法

**優先度: 中**

1. **メッセージ数の上限チェック処理を追加**
   - メッセージ作成時に事務所のメッセージ数をカウント
   - 50件を超える場合、最も古いメッセージを削除

2. **バッチ処理による定期クリーンアップ**
   - 定期的に各事務所のメッセージ数をチェック
   - 上限を超えている場合、古いものから削除

**参考実装**
```python
async def create_message_with_limit(
    db: AsyncSession,
    office_id: UUID,
    message_data: dict,
    limit: int = 50
) -> Message:
    # メッセージ数をカウント
    count_stmt = select(func.count(Message.id)).where(
        Message.office_id == office_id,
        Message.is_test_data == False
    )
    result = await db.execute(count_stmt)
    current_count = result.scalar()

    # 上限チェック
    if current_count >= limit:
        # 最も古いメッセージを取得して削除
        oldest_stmt = (
            select(Message)
            .where(Message.office_id == office_id)
            .order_by(Message.created_at.asc())
            .limit(current_count - limit + 1)
        )
        oldest_messages = await db.execute(oldest_stmt)
        for old_msg in oldest_messages.scalars():
            await db.delete(old_msg)

    # 新しいメッセージを作成
    new_message = Message(**message_data)
    db.add(new_message)
    await db.flush()

    return new_message
```

---

## UI

### MessageCard.tsx 送信者の名前が受信者側から見えない

#### 現状調査結果

**問題の原因: バックエンドとフロントエンドのスキーマ不一致**

1. **バックエンド** (`MessageInboxItem` スキーマ)
   - 実装箇所: `k_back/app/schemas/message.py` (行154-155)
   - 送信者情報を `sender_name: Optional[str]` として返している
   - 例: `"sender_name": "山田 太郎"`

2. **フロントエンド** (`MessageInboxItem` 型定義)
   - 実装箇所: `k_front/types/message.ts` (行49-62)
   - `sender?: MessageSenderInfo` オブジェクトを期待している
   - `MessageSenderInfo` は `{ id, username, email }` の構造

3. **MessageCard.tsx の表示処理** (行160-164)
   - `message.sender.username` を参照している
   - しかし、APIからは `sender_name` 文字列しか返ってこないため表示されない

#### 改善方法

**優先度: 中**

**オプション1: バックエンドのスキーマとAPIレスポンスを修正（推奨）**

フロントエンドの型定義に合わせて、バックエンドで `MessageSenderInfo` オブジェクトを返すように修正します。

**利点:**
- `MessageDetailResponse` や他のAPIとの一貫性
- 将来的な拡張性（プロフィール画像など）
- 型安全性の向上

**修正箇所:**

1. `k_back/app/schemas/message.py` の `MessageInboxItem` を修正:
```python
class MessageInboxItem(BaseModel):
    """受信箱アイテムスキーマ"""
    # ...
    sender_staff_id: Optional[uuid.UUID] = None
    sender: Optional[MessageSenderInfo] = None  # sender_nameから変更
    # ...
```

2. `k_back/app/api/v1/endpoints/messages.py` の `/inbox` エンドポイントを修正:
```python
sender_info = None
if message.sender:
    sender_info = MessageSenderInfo(
        id=message.sender.id,
        first_name=message.sender.first_name,
        last_name=message.sender.last_name,
        email=message.sender.email
    )

inbox_item = MessageInboxItem(
    # ...
    sender=sender_info,  # オブジェクトとして渡す
    # ...
)
```

3. `k_front/components/notice/MessageCard.tsx` を修正:
```tsx
{message.sender && (
  <span className="text-gray-400 text-xs">
    送信者: {message.sender.last_name} {message.sender.first_name}
  </span>
)}
```

**オプション2: フロントエンドを修正（簡易対応）**

バックエンドはそのままで、フロントエンドの型定義と表示ロジックを修正します。

**修正箇所:**

1. `k_front/types/message.ts` を修正:
```typescript
export interface MessageInboxItem {
  // ...
  sender_staff_id: string | null;
  sender_name?: string | null;  // 追加
  // ...
}
```

2. `k_front/components/notice/MessageCard.tsx` を修正:
```tsx
{message.sender_name && (
  <span className="text-gray-400 text-xs">
    送信者: {message.sender_name}
  </span>
)}
```

#### 推奨事項

**オプション1（バックエンド修正）を推奨**

理由:
- API全体での一貫性
- 拡張性と型安全性
- フロントエンドの既存の型定義との整合性

注意: オプション1の場合はバックエンドのテストも修正が必要

---

## まとめ

### 改善優先度

1. **高優先度**: CSRF対策（CSRFトークン実装）
2. **中優先度**: MessageCard送信者名表示の修正
3. **中優先度**: メッセージ数上限設定

### 次のアクション

1. CSRF対策の実装とテスト
2. MessageCard送信者名表示の修正（オプション1推奨）
3. メッセージ数上限機能の実装と動作確認

---

**調査完了日**: 2025-11-25
**次回確認推奨日**: 改善実施後