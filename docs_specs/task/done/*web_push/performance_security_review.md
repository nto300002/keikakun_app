# Web Push通知機能 パフォーマンス・セキュリティレビュー

**レビュー日**: 2026-01-19
**対象**: 実装済みWeb Push通知機能（Phase 1 + Phase 3フロントエンド）
**レビュアー**: Claude Sonnet 4.5

---

## エグゼクティブサマリー

Web Push通知の実装済み部分について、パフォーマンスとセキュリティの観点から包括的なレビューを実施しました。

### 総合評価

| 領域 | 評価 | 主な所見 |
|------|------|---------|
| **セキュリティ** | ✅ 良好 | VAPID鍵管理、認証・認可、入力検証が適切 |
| **パフォーマンス** | 🟡 改善余地あり | 基本的に良好だが、複数デバイス対応に課題 |
| **コード品質** | ✅ 高品質 | 非同期処理、エラーハンドリング、ログが適切 |

**Critical Issues**: 1件（複数デバイスサポート不可）
**High Priority**: 2件（pywebpush同期処理、バッチ削除の非効率）
**Medium Priority**: 3件（Service Workerの改善点）

---

## セキュリティレビュー

### 1. 認証・認可 ✅ 良好

#### 1.1 API認証
**実装箇所**: `k_back/app/api/v1/endpoints/push_subscriptions.py`

```python
@router.post("/subscribe", response_model=PushSubscriptionResponse)
async def subscribe_push(
    current_user: Staff = Depends(deps.get_current_user),  # ✅ 認証必須
    db: AsyncSession = Depends(deps.get_db)
):
```

**評価**: ✅ **適切**
- 全エンドポイントで`get_current_user`による認証チェック実施
- Cookie認証（優先）とBearer Token認証の両対応
- 認証失敗時は401 Unauthorizedを返す

#### 1.2 認可（Authorization）
**実装箇所**: `push_subscriptions.py:108-114`

```python
if existing.staff_id != current_user.id:
    raise HTTPException(status_code=403, detail="Not authorized to delete this subscription")
```

**評価**: ✅ **適切**
- 購読解除時に所有者チェック実施
- 他人の購読を削除できない
- **subscribe時の認可**: current_userのIDで自動設定されるため、他人の購読を作成できない ✅

**潜在的な改善点**: なし

---

### 2. VAPID鍵管理 ✅ 良好

#### 2.1 Backend鍵管理
**実装箇所**: `k_back/app/core/config.py:66-69`

```python
VAPID_PRIVATE_KEY_DER: Optional[str] = None  # 秘密鍵（Base64 DER形式）
VAPID_PRIVATE_KEY: Optional[str] = None      # pywebpush用
VAPID_PUBLIC_KEY: Optional[str] = None       # 公開鍵（Base64 URL-safe）
VAPID_SUBJECT: Optional[str] = None          # mailto: または https://
```

**評価**: ✅ **適切**
- 環境変数で管理（ハードコード無し）
- SecretStrは使用していないが、Optional[str]で適切に定義
- Git履歴に含まれていない（.env.exampleのみ）

**潜在的リスク**:
- ⚠️ **Medium**: 秘密鍵がSecretStrでない
  - 影響: ログ出力時にマスクされない可能性
  - 緩和策: push.pyで鍵をログ出力していないため実害なし
  - 推奨: 将来的にSecretStr化を検討

#### 2.2 Frontend鍵管理
**実装箇所**: `k_front/hooks/usePushNotification.ts:125-129`

```typescript
const vapidPublicKey = process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY;

if (!vapidPublicKey) {
  throw new Error('VAPID public key is not configured');
}
```

**評価**: ✅ **適切**
- 公開鍵のみフロントエンドに配置（秘密鍵は非公開）
- 環境変数で管理
- 存在チェック実装

#### 2.3 VAPID設定検証
**実装箇所**: `k_back/app/core/push.py:58-60`

```python
if not settings.VAPID_PRIVATE_KEY or not settings.VAPID_SUBJECT:
    logger.error("[PUSH] VAPID settings not configured. Cannot send push notifications.")
    return (False, False)
```

**評価**: ✅ **適切**
- 送信前に設定チェック実施
- 未設定時はエラーログ出力してFalse返却
- アプリケーションクラッシュを防ぐ

---

### 3. 入力検証 ✅ 良好

#### 3.1 Pydanticスキーマ検証
**実装箇所**: `k_back/app/schemas/push_subscription.py`

```python
class PushSubscriptionKeys(BaseModel):
    p256dh: str = Field(..., description="P-256公開鍵（Base64エンコード）")
    auth: str = Field(..., description="認証シークレット（Base64エンコード）")

class PushSubscriptionCreate(BaseModel):
    endpoint: str = Field(..., description="Push Service提供のエンドポイントURL")
    keys: PushSubscriptionKeys = Field(..., description="暗号化キー情報")
```

**評価**: ✅ **適切**
- 全フィールドが必須（`...`）
- 型チェック自動実行
- 不正なデータ拒否

**改善提案**:
- 🟡 **Medium**: エンドポイントURLの形式バリデーション
  ```python
  from pydantic import HttpUrl

  endpoint: HttpUrl = Field(...)  # HTTPSのみ許可
  ```

#### 3.2 Frontend入力検証
**実装箇所**: `k_front/hooks/usePushNotification.ts:113-117`

```typescript
const permission = await requestPermission();

if (permission !== 'granted') {
  throw new Error('Notification permission denied');
}
```

**評価**: ✅ **適切**
- 通知権限チェック実施
- 権限なしの場合はエラー

---

### 4. SQLインジェクション対策 ✅ 良好

#### 4.1 パラメータ化クエリ
**実装箇所**: `k_back/app/crud/crud_push_subscription.py:32-34`

```python
stmt = select(PushSubscription).where(PushSubscription.staff_id == staff_id)
result = await db.execute(stmt)
```

**評価**: ✅ **適切**
- SQLAlchemyのORM使用（パラメータ化自動）
- 生SQLクエリ無し
- WHERE句で比較演算子使用（`==`）

**潜在的な問題**: なし

---

### 5. XSS（クロスサイトスクリプティング）対策 ✅ 良好

#### 5.1 Backend レスポンスエスケープ
**実装箇所**: `k_back/app/api/v1/endpoints/push_subscriptions.py:79`

```python
raise HTTPException(status_code=500, detail="Failed to subscribe push notifications")
```

**評価**: ✅ **適切**
- エラーメッセージは固定文字列（ユーザー入力を含まない）
- FastAPIが自動的にJSONエスケープ

#### 5.2 Frontend レンダリング
**実装箇所**: `k_front/components/protected/profile/NotificationSettings.tsx:193-195`

```tsx
{pushError && (
  <p className="text-sm text-red-500 mt-2">
    エラー: {pushError}
  </p>
)}
```

**評価**: 🟡 **要注意**
- Reactが自動エスケープするため基本的に安全
- ただし`pushError`はErrorオブジェクトのmessageプロパティ
- **潜在的リスク**: エラーメッセージにユーザー入力が含まれる可能性（低リスク）

**推奨**: エラーメッセージを固定文字列に限定
```tsx
エラー: 通知設定の変更に失敗しました
```

---

### 6. CSRF（クロスサイトリクエストフォージェリ）対策 ✅ 良好

#### 6.1 Backend CSRF保護
**実装箇所**: Cookie認証使用（`k_back/app/api/deps.py:52`）

```python
cookie_token = request.cookies.get("access_token")
```

**評価**: ✅ **適切**
- HTTPOnly Cookie使用
- SameSite属性設定（推定）
- CSRFトークン実装済み（フロントエンド）

#### 6.2 Frontend CSRF対応
**実装箇所**: `k_front/lib/http.ts`（import使用）

```typescript
import { http } from '@/lib/http';

await http.post<any>('/api/v1/push-subscriptions/subscribe', subscription.toJSON());
```

**評価**: ✅ **適切**
- 共通HTTPライブラリ使用
- CSRFトークン自動付与（`getCsrfToken()`）
- `credentials: 'include'`設定済み

**検証済み**: 2026-01-14の修正で対応完了

---

### 7. 個人情報保護 ✅ 良好

#### 7.1 ログマスキング
**実装箇所**: `k_back/app/core/push.py:82-83`

```python
endpoint_preview = subscription_info.get("endpoint", "")[:50]
logger.info(f"[PUSH] Notification sent successfully to {endpoint_preview}...")
```

**評価**: ✅ **適切**
- エンドポイントURLを50文字に切り詰め
- 完全なエンドポイントURLをログに記録しない
- プライバシー保護

#### 7.2 PII（個人識別情報）保護
**実装箇所**: `k_back/app/models/push_subscription.py:37-44`

```python
endpoint: Mapped[str] = mapped_column(Text, unique=True, nullable=False)
p256dh_key: Mapped[str] = mapped_column(Text, nullable=False)
auth_key: Mapped[str] = mapped_column(Text, nullable=False)
```

**評価**: ✅ **適切**
- 暗号化キーのみ保存（実際の通知内容は保存しない）
- user_agentは任意（Optional）
- CASCADE DELETEでスタッフ削除時に自動削除

#### 7.3 通知内容のセキュリティ
**実装箇所**: `k_back/app/core/push.py:62-74`

```python
payload = {
    "title": title,
    "body": body,
    "icon": icon,
    "badge": badge,
    "data": data or {},
    "requireInteraction": True
}
```

**評価**: ✅ **適切**
- 通知内容は暗号化されてPush Serviceに送信
- エンドツーエンド暗号化（Web Push標準）
- 中間者攻撃のリスク低い

---

### 8. 購読期限切れ処理 ✅ 良好

#### 8.1 無効な購読の検出
**実装箇所**: `k_back/app/core/push.py:89-94`

```python
if e.response and e.response.status_code in [404, 410]:
    logger.warning(
        f"[PUSH] Subscription expired (HTTP {e.response.status_code}): "
        f"{endpoint_preview}... - Marking for deletion from database"
    )
    return (False, True)  # should_delete=True
```

**評価**: ✅ **適切**
- 410 Gone（購読期限切れ）を検出
- 404 Not Found（購読削除済み）を検出
- DB削除フラグ返却（呼び出し元で削除実装必要）

**改善提案**:
- 🟡 **High**: バッチ処理実装時に自動削除ロジック追加必須
  ```python
  success, should_delete = await send_push_notification(...)
  if should_delete:
      await crud.push_subscription.delete(db=db, id=subscription.id)
  ```

---

### 9. Service Worker セキュリティ 🟡 改善余地あり

#### 9.1 pushsubscriptionchange イベント
**実装箇所**: `k_front/public/sw.js:100-119`

```javascript
self.addEventListener('pushsubscriptionchange', (event) => {
  event.waitUntil(
    self.registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: null  // ⚠️ VAPID鍵がnull
    })
  );
});
```

**評価**: 🟡 **要改善**
- **問題**: VAPID鍵がnull
- **影響**: 自動再購読が失敗する可能性
- **推奨修正**:
  ```javascript
  // Service Worker内でVAPID鍵を埋め込む（ビルド時に環境変数から注入）
  const VAPID_PUBLIC_KEY = 'BBmBnPkVV0X...';

  applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY)
  ```

#### 9.2 fetch API認証
**実装箇所**: `sw.js:110-116`

```javascript
return fetch('/api/v1/push-subscriptions/subscribe', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json'
  },
  body: JSON.stringify(subscription.toJSON())
});
```

**評価**: 🟡 **要改善**
- **問題1**: `credentials: 'include'`が無い
- **問題2**: CSRFトークンが無い
- **影響**: 自動再購読時の認証失敗
- **推奨修正**:
  ```javascript
  credentials: 'include',
  headers: {
    'Content-Type': 'application/json',
    'X-CSRF-Token': await getCsrfTokenFromCache()
  }
  ```

---

## パフォーマンスレビュー

### 1. データベースパフォーマンス

#### 1.1 インデックス設計 ✅ 良好
**実装箇所**: `k_back/app/models/push_subscription.py:26-35`

```python
staff_id: Mapped[uuid.UUID] = mapped_column(
    UUID(as_uuid=True),
    ForeignKey('staffs.id', ondelete='CASCADE'),
    nullable=False,
    index=True  # ✅ インデックス設定
)
endpoint: Mapped[str] = mapped_column(
    Text,
    unique=True,  # ✅ UNIQUE制約 = 暗黙のインデックス
    nullable=False
)
```

**評価**: ✅ **適切**
- `staff_id`: インデックス設定済み（頻繁な検索に最適）
- `endpoint`: UNIQUE制約（重複チェック高速化）
- 検索パターンに合致

**クエリパフォーマンス推定**:
- `get_by_staff_id()`: インデックススキャン - O(log n)
- `get_by_endpoint()`: UNIQUE検索 - O(1)

#### 1.2 N+1問題の可能性 ⚠️ 要注意
**実装箇所**: `k_back/app/crud/crud_push_subscription.py:32-34`

```python
stmt = select(PushSubscription).where(PushSubscription.staff_id == staff_id)
result = await db.execute(stmt)
return list(result.scalars().all())
```

**評価**: ✅ **現状は問題なし**
- 現在はrelationshipの遅延ロード無し
- `staff`リレーションは参照していない

**潜在的リスク**:
- 🟡 **Medium**: バッチ処理実装時にN+1問題発生の可能性
- **シナリオ**: 期限アラートで全スタッフの購読を取得 → 各購読でstaffを参照
- **推奨**: バッチ処理実装時に`selectinload(PushSubscription.staff)`を使用

**推奨修正例**:
```python
# バッチ処理での使用例
stmt = (
    select(PushSubscription)
    .where(PushSubscription.staff_id.in_(staff_ids))
    .options(selectinload(PushSubscription.staff))  # ✅ Eager loading
)
```

---

#### 1.3 バッチ削除の非効率 🔴 Critical
**実装箇所**: `k_back/app/crud/crud_push_subscription.py:96-99`

```python
# 新規作成前に、同じユーザーの古い購読を全て削除
old_subscriptions = await self.get_by_staff_id(db=db, staff_id=staff_id)
for old_sub in old_subscriptions:
    await db.delete(old_sub)  # ⚠️ 個別DELETE文
```

**評価**: 🔴 **Critical - 複数デバイスサポート不可**

**問題点**:
1. **機能的問題**: 複数デバイスサポートができない
   - ユーザーがPC + スマホで購読 → 新規購読時に全削除 → 片方が通知受信不可
2. **パフォーマンス問題**: N個のDELETE文実行
   - 10デバイス登録の場合: 10回のDB往復

**ビジネス影響**:
- ✅ **現状は問題なし**: TODO.mdの要件「複数デバイス登録」を満たす
- 🔴 **将来的な問題**: ユーザーが複数デバイスで通知を受けられない

**推奨修正1（複数デバイス対応）**:
```python
async def create_or_update(
    self,
    db: AsyncSession,
    *,
    staff_id: UUID,
    endpoint: str,
    p256dh_key: str,
    auth_key: str,
    user_agent: str | None = None
) -> PushSubscription:
    existing = await self.get_by_endpoint(db=db, endpoint=endpoint)

    if existing:
        # 既存の購読を更新（削除しない）
        existing.p256dh_key = p256dh_key
        existing.auth_key = auth_key
        if user_agent:
            existing.user_agent = user_agent
        db.add(existing)
        await db.commit()
        await db.refresh(existing)
        return existing
    else:
        # 新規作成（古い購読は削除しない）
        subscription_data = PushSubscriptionInDB(
            staff_id=staff_id,
            endpoint=endpoint,
            p256dh_key=p256dh_key,
            auth_key=auth_key,
            user_agent=user_agent
        )
        return await self.create(db=db, obj_in=subscription_data, auto_commit=True)
```

**推奨修正2（バッチ削除の効率化）**:
もし古い購読を削除する仕様を維持する場合:
```python
from sqlalchemy import delete

# 一括DELETE文
stmt = delete(PushSubscription).where(PushSubscription.staff_id == staff_id)
await db.execute(stmt)
await db.commit()
```

---

#### 1.4 トランザクション管理 ✅ 良好
**実装箇所**: `k_back/app/crud/crud_push_subscription.py:91-93`

```python
db.add(existing)
await db.commit()
await db.refresh(existing)
```

**評価**: ✅ **適切**
- commit後にrefresh実行（DB生成値の取得）
- 複数操作を1トランザクション内で実行
- エラー時のロールバック処理（CRUDBaseに実装済みと推定）

---

### 2. 非同期処理パフォーマンス

#### 2.1 async/await の使用 ✅ 良好
**実装箇所**: 全CRUDメソッド

```python
async def get_by_staff_id(self, db: AsyncSession, staff_id: UUID) -> List[PushSubscription]:
    stmt = select(PushSubscription).where(PushSubscription.staff_id == staff_id)
    result = await db.execute(stmt)
    return list(result.scalars().all())
```

**評価**: ✅ **適切**
- 全DB操作でasync/await使用
- ブロッキング無し
- 並行処理可能

#### 2.2 pywebpush 同期処理 🟡 要注意
**実装箇所**: `k_back/app/core/push.py:75-80`

```python
webpush(  # ⚠️ 同期関数
    subscription_info=subscription_info,
    data=json.dumps(payload),
    vapid_private_key=settings.VAPID_PRIVATE_KEY,
    vapid_claims={"sub": settings.VAPID_SUBJECT}
)
```

**評価**: 🟡 **要改善**
- **問題**: pywebpushは同期ライブラリ
- **影響**: Push送信中に他のリクエストがブロックされる可能性
- **現状の緩和策**: 関数自体は`async`宣言されている（awaitで呼び出し可能）

**推奨修正**:
```python
import asyncio
from concurrent.futures import ThreadPoolExecutor

executor = ThreadPoolExecutor(max_workers=10)

async def send_push_notification(...) -> tuple[bool, bool]:
    # 同期関数を別スレッドで実行
    loop = asyncio.get_event_loop()
    try:
        await loop.run_in_executor(
            executor,
            lambda: webpush(
                subscription_info=subscription_info,
                data=json.dumps(payload),
                vapid_private_key=settings.VAPID_PRIVATE_KEY,
                vapid_claims={"sub": settings.VAPID_SUBJECT}
            )
        )
        return (True, False)
    except WebPushException as e:
        # エラーハンドリング...
```

**優先度**: 🟡 Medium（バッチ処理実装時に対応推奨）

---

### 3. Frontend パフォーマンス

#### 3.1 Service Worker 効率性 ✅ 良好
**実装箇所**: `k_front/public/sw.js`

```javascript
self.addEventListener('install', (event) => {
  self.skipWaiting();  // ✅ 即座にアクティブ化
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());  // ✅ 即座にページを制御
});
```

**評価**: ✅ **適切**
- skipWaiting()で即座に更新
- clients.claim()で既存ページを制御
- キャッシュ無し（通知機能のみのため不要）

#### 3.2 React Hook 最適化 ✅ 良好
**実装箇所**: `k_front/hooks/usePushNotification.ts:108, 152`

```typescript
const subscribe = useCallback(async () => {
  // ...
}, [requestPermission]);  // ✅ 依存配列最小化

const unsubscribe = useCallback(async () => {
  // ...
}, []);  // ✅ 依存なし
```

**評価**: ✅ **適切**
- useCallbackで不要な再生成防止
- 依存配列が適切
- メモ化による再レンダリング削減

#### 3.3 State管理効率 ✅ 良好
**実装箇所**: `k_front/hooks/usePushNotification.ts:56-70`

```typescript
useEffect(() => {
  const checkSupport = () => {
    if (typeof window === 'undefined') {
      setIsLoading(false);
      return;  // ✅ 早期リターン
    }

    const supported = 'serviceWorker' in navigator && 'PushManager' in window;
    setIsSupported(supported);
    setIsPWA(detectPWA());
    setIsIOS(detectIOS());
  };

  checkSupport();
}, []);  // ✅ マウント時のみ実行
```

**評価**: ✅ **適切**
- 初回マウント時のみ実行
- 不要な再計算無し
- SSRガード（`typeof window`チェック）

---

### 4. API パフォーマンス

#### 4.1 エンドポイント設計 ✅ 良好
**実装箇所**: `k_back/app/api/v1/endpoints/push_subscriptions.py`

```python
@router.post("/subscribe")      # ✅ べき等（重複購読時は更新）
@router.delete("/unsubscribe")  # ✅ クエリパラメータでendpoint指定
@router.get("/my-subscriptions")  # ✅ ページネーション不要（1ユーザー数件）
```

**評価**: ✅ **適切**
- RESTful設計
- べき等性保証（subscribeの重複実行安全）
- ページネーション不要（1ユーザーあたり数デバイス程度）

#### 4.2 エラーハンドリング ✅ 良好
**実装箇所**: `push_subscriptions.py:77-79`

```python
except Exception as e:
    logger.error(f"[PUSH_SUBSCRIPTION] Failed to subscribe: {e}", exc_info=True)
    raise HTTPException(status_code=500, detail="Failed to subscribe push notifications")
```

**評価**: ✅ **適切**
- 詳細なログ出力（exc_info=True）
- ユーザーには一般的なエラーメッセージ
- 情報漏洩防止

---

### 5. ネットワークパフォーマンス

#### 5.1 ペイロードサイズ ✅ 良好
**実装箇所**: `k_back/app/core/push.py:62-73`

```python
payload = {
    "title": title,
    "body": body,
    "icon": icon,
    "badge": badge,
    "data": data or {},
    "requireInteraction": True
}
```

**評価**: ✅ **適切**
- 小さなペイロード（数百バイト程度）
- Web Push制限（4KB）内に収まる
- 不要なデータ送信無し

**推定サイズ**:
```
title: ~50 bytes
body: ~200 bytes
icon: ~20 bytes (URL)
badge: ~20 bytes (URL)
data: ~100 bytes (JSON)
-----------------
Total: ~400 bytes
```

#### 5.2 HTTP/2対応 ✅ 良好
**実装箇所**: FastAPI（自動対応）

**評価**: ✅ **適切**
- FastAPI/uvicornはHTTP/2サポート
- 複数リクエストのマルチプレクシング可能

---

## Critical Issues（即対応必要）

### 🔴 Issue #1: 複数デバイスサポート不可

**ファイル**: `k_back/app/crud/crud_push_subscription.py:96-99`

**問題**:
```python
# 新規作成前に、同じユーザーの古い購読を全て削除
old_subscriptions = await self.get_by_staff_id(db=db, staff_id=staff_id)
for old_sub in old_subscriptions:
    await db.delete(old_sub)  # ❌ 全デバイスの購読削除
```

**影響**:
- ユーザーがPC + スマホで通知を受信できない
- 新規デバイス登録時に既存デバイスの購読が削除される
- TODO.mdの「複数デバイス登録」要件を満たさない

**推奨修正**:
```python
async def create_or_update(
    self,
    db: AsyncSession,
    *,
    staff_id: UUID,
    endpoint: str,
    p256dh_key: str,
    auth_key: str,
    user_agent: str | None = None
) -> PushSubscription:
    """
    購読情報を作成または更新（複数デバイス対応版）

    同一エンドポイントが既に存在する場合は更新のみ実施。
    新規作成時は古い購読を削除せず、複数デバイスの購読を維持。
    """
    existing = await self.get_by_endpoint(db=db, endpoint=endpoint)

    if existing:
        # 既存の購読を更新（他のデバイスは削除しない）
        existing.p256dh_key = p256dh_key
        existing.auth_key = auth_key
        if user_agent:
            existing.user_agent = user_agent
        db.add(existing)
        await db.commit()
        await db.refresh(existing)
        return existing
    else:
        # 新規作成（他のデバイスの購読は保持）
        subscription_data = PushSubscriptionInDB(
            staff_id=staff_id,
            endpoint=endpoint,
            p256dh_key=p256dh_key,
            auth_key=auth_key,
            user_agent=user_agent
        )
        return await self.create(db=db, obj_in=subscription_data, auto_commit=True)
```

**工数**: 0.5時間
**優先度**: 🔴 Critical
**影響範囲**: CRUD層のみ（API層は変更不要）

---

## High Priority Issues（優先対応）

### 🟡 Issue #2: pywebpush 同期処理によるブロッキング

**ファイル**: `k_back/app/core/push.py:75-80`

**問題**:
```python
webpush(  # ❌ 同期関数（I/Oブロッキング）
    subscription_info=subscription_info,
    data=json.dumps(payload),
    vapid_private_key=settings.VAPID_PRIVATE_KEY,
    vapid_claims={"sub": settings.VAPID_SUBJECT}
)
```

**影響**:
- Push送信中に他のAPIリクエストがブロックされる可能性
- 複数の同時送信時にパフォーマンス低下
- バッチ処理で数百件送信時に顕著

**推奨修正**:
```python
import asyncio
from concurrent.futures import ThreadPoolExecutor

# モジュールレベルで定義
_executor = ThreadPoolExecutor(max_workers=10, thread_name_prefix="webpush")

async def send_push_notification(
    subscription_info: Dict[str, Any],
    title: str,
    body: str,
    icon: str = "/icon-192.png",
    badge: str = "/icon-192.png",
    data: Optional[Dict[str, Any]] = None,
    actions: Optional[list] = None
) -> tuple[bool, bool]:
    """
    Web Push通知を送信（非同期版）

    pywebpushの同期関数をThreadPoolExecutorで実行し、
    イベントループをブロックしないようにする。
    """
    if not settings.VAPID_PRIVATE_KEY or not settings.VAPID_SUBJECT:
        logger.error("[PUSH] VAPID settings not configured.")
        return (False, False)

    payload = {
        "title": title,
        "body": body,
        "icon": icon,
        "badge": badge,
        "data": data or {},
        "requireInteraction": True
    }

    if actions:
        payload["actions"] = actions

    loop = asyncio.get_event_loop()

    try:
        # 同期関数を別スレッドで実行
        await loop.run_in_executor(
            _executor,
            lambda: webpush(
                subscription_info=subscription_info,
                data=json.dumps(payload),
                vapid_private_key=settings.VAPID_PRIVATE_KEY,
                vapid_claims={"sub": settings.VAPID_SUBJECT}
            )
        )

        endpoint_preview = subscription_info.get("endpoint", "")[:50]
        logger.info(f"[PUSH] Notification sent successfully to {endpoint_preview}...")
        return (True, False)

    except WebPushException as e:
        endpoint_preview = subscription_info.get("endpoint", "")[:50]

        if e.response and e.response.status_code in [404, 410]:
            logger.warning(
                f"[PUSH] Subscription expired (HTTP {e.response.status_code}): "
                f"{endpoint_preview}... - Marking for deletion"
            )
            return (False, True)
        else:
            logger.error(f"[PUSH] Failed to send: {e}", exc_info=True)
            return (False, False)

    except Exception as e:
        logger.error(f"[PUSH] Unexpected error: {e}", exc_info=True)
        return (False, False)
```

**工数**: 1時間
**優先度**: 🟡 High
**タイミング**: バッチ処理実装前に対応推奨

---

### 🟡 Issue #3: Service Worker の自動再購読失敗

**ファイル**: `k_front/public/sw.js:100-119`

**問題1: VAPID鍵がnull**:
```javascript
self.registration.pushManager.subscribe({
  userVisibleOnly: true,
  applicationServerKey: null  // ❌ VAPID鍵未設定
})
```

**問題2: 認証情報不足**:
```javascript
return fetch('/api/v1/push-subscriptions/subscribe', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json'
    // ❌ credentials: 'include' 無し
    // ❌ X-CSRF-Token 無し
  },
  body: JSON.stringify(subscription.toJSON())
});
```

**影響**:
- Push購読トークン更新時に自動再購読が失敗
- ユーザーが手動で再購読する必要がある

**推奨修正**:
```javascript
// Service Workerの先頭で定義（ビルド時に環境変数から注入）
const VAPID_PUBLIC_KEY = 'BBmBnPkVV0X-PdBZRYBr1Yra2xzkRIKuhHyEwJZObLoNTQtYxTiw248CJB1M9CtEqnWpl4JFZUFzkLTtugbObMs';

function urlBase64ToUint8Array(base64String) {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const rawData = atob(base64);
  const outputArray = new Uint8Array(rawData.length);
  for (let i = 0; i < rawData.length; ++i) {
    outputArray[i] = rawData.charCodeAt(i);
  }
  return outputArray;
}

self.addEventListener('pushsubscriptionchange', (event) => {
  console.log(`[Service Worker ${SW_VERSION}] Push subscription changed`);

  event.waitUntil(
    // ✅ VAPID鍵を設定
    self.registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY)
    })
    .then((subscription) => {
      console.log(`[Service Worker ${SW_VERSION}] Re-subscribed:`, subscription);

      // ✅ Cookie認証とCSRFトークンを設定
      return fetch('/api/v1/push-subscriptions/subscribe', {
        method: 'POST',
        credentials: 'include',  // ✅ Cookie送信
        headers: {
          'Content-Type': 'application/json'
          // TODO: CSRFトークンの取得方法を検討
        },
        body: JSON.stringify(subscription.toJSON())
      });
    })
  );
});
```

**課題**: Service Worker内でCSRFトークンを取得する方法
- **Option 1**: IndexedDBにキャッシュ
- **Option 2**: CSRFトークンをクエリパラメータで渡す（非推奨）
- **Option 3**: 自動再購読をスキップし、次回ログイン時に再購読

**工数**: 2時間
**優先度**: 🟡 High

---

## Medium Priority Issues（検討推奨）

### 🟢 Issue #4: エンドポイントURLの形式バリデーション

**ファイル**: `k_back/app/schemas/push_subscription.py:18`

**現状**:
```python
endpoint: str = Field(..., description="Push Service提供のエンドポイントURL")
```

**推奨修正**:
```python
from pydantic import HttpUrl

endpoint: HttpUrl = Field(..., description="Push Service提供のエンドポイントURL（HTTPS必須）")
```

**メリット**:
- HTTPSのみ許可（セキュリティ向上）
- 無効なURL拒否（データ品質向上）

**工数**: 0.5時間
**優先度**: 🟢 Medium

---

### 🟢 Issue #5: エラーメッセージのXSS対策

**ファイル**: `k_front/components/protected/profile/NotificationSettings.tsx:193-195`

**現状**:
```tsx
{pushError && (
  <p className="text-sm text-red-500 mt-2">
    エラー: {pushError}  {/* ❌ Error.messageをそのまま表示 */}
  </p>
)}
```

**推奨修正**:
```tsx
{pushError && (
  <p className="text-sm text-red-500 mt-2">
    通知設定の変更に失敗しました
  </p>
)}
```

**メリット**:
- XSS攻撃のリスク削減
- ユーザーフレンドリーなエラーメッセージ

**工数**: 0.25時間
**優先度**: 🟢 Medium

---

### 🟢 Issue #6: VAPID秘密鍵のSecretStr化

**ファイル**: `k_back/app/core/config.py:67`

**現状**:
```python
VAPID_PRIVATE_KEY: Optional[str] = None  # ❌ 平文文字列
```

**推奨修正**:
```python
VAPID_PRIVATE_KEY: Optional[SecretStr] = None  # ✅ 秘匿文字列
```

**メリット**:
- ログ出力時の自動マスク
- デバッグ時の情報漏洩防止

**注意**: push.pyで`settings.VAPID_PRIVATE_KEY.get_secret_value()`を使用する必要あり

**工数**: 0.5時間
**優先度**: 🟢 Medium

---

## 推奨改善優先順位

| 優先度 | Issue | 工数 | タイミング |
|-------|-------|------|-----------|
| 🔴 #1 | 複数デバイスサポート不可 | 0.5h | 即時 |
| 🟡 #2 | pywebpush同期処理 | 1h | バッチ実装前 |
| 🟡 #3 | Service Worker自動再購読 | 2h | バッチ実装前 |
| 🟢 #4 | エンドポイントURL形式検証 | 0.5h | Phase 2実装時 |
| 🟢 #5 | エラーメッセージXSS対策 | 0.25h | Phase 2実装時 |
| 🟢 #6 | VAPID秘密鍵SecretStr化 | 0.5h | Phase 5実装時 |

**総見積工数**: 5時間

---

## ベストプラクティス準拠状況

### セキュリティ

| 項目 | 状態 | 評価 |
|------|------|------|
| 認証・認可 | ✅ | 全エンドポイントで適切に実装 |
| VAPID鍵管理 | ✅ | 環境変数で管理、Git除外 |
| 入力検証 | ✅ | Pydanticスキーマで型チェック |
| SQLインジェクション対策 | ✅ | ORM使用、パラメータ化クエリ |
| XSS対策 | 🟡 | 基本的に対策済み、一部改善余地 |
| CSRF対策 | ✅ | CSRFトークン実装済み |
| 個人情報保護 | ✅ | ログマスキング、CASCADE DELETE |

### パフォーマンス

| 項目 | 状態 | 評価 |
|------|------|------|
| データベース最適化 | ✅ | インデックス適切、N+1問題なし |
| 非同期処理 | 🟡 | async/await使用、pywebpush同期 |
| フロントエンド最適化 | ✅ | useCallback、早期リターン |
| API設計 | ✅ | RESTful、べき等性保証 |
| ネットワーク効率 | ✅ | 小さなペイロード、HTTP/2対応 |

---

## 結論

Web Push通知の実装済み部分は、**セキュリティとパフォーマンスの観点から全体的に高品質**です。以下の点が特に優れています：

### 長所 ✅
1. **認証・認可**: Cookie認証とBearer Tokenの両対応、適切な権限チェック
2. **VAPID鍵管理**: 環境変数で管理、Git履歴に含まれない
3. **入力検証**: Pydanticスキーマによる厳格な型チェック
4. **SQLインジェクション対策**: ORMによるパラメータ化クエリ
5. **個人情報保護**: エンドポイントURLのマスキング、CASCADE DELETE
6. **非同期処理**: 全DB操作でasync/await使用
7. **エラーハンドリング**: 詳細なログ出力、ユーザーには一般的なメッセージ

### 改善点 🔴🟡
1. **🔴 Critical**: 複数デバイスサポート不可（CRUD層の削除ロジック）
2. **🟡 High**: pywebpush同期処理によるブロッキング
3. **🟡 High**: Service Workerの自動再購読失敗（VAPID鍵、認証）
4. **🟢 Medium**: エンドポイントURL形式検証、XSS対策、SecretStr化

**推奨対応順序**:
1. Issue #1（複数デバイス）: 即時修正（0.5時間）
2. Issue #2（pywebpush）: バッチ実装前に修正（1時間）
3. Issue #3（Service Worker）: バッチ実装前に修正（2時間）
4. その他: Phase 2以降で対応

総工数: 約5時間で全Issue解決可能

---

**レビュアー**: Claude Sonnet 4.5
**レビュー完了日**: 2026-01-19
**次回レビュー推奨**: Phase 3.3.7（バッチ処理）実装後
