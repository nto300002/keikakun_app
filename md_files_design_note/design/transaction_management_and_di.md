# トランザクション管理と依存性注入 - 4層アーキテクチャにおける実装戦略

## 概要

本ドキュメントでは、けいかくんアプリケーションにおける4層アーキテクチャ（API → Services → CRUD → Models）におけるトランザクション境界の定義方法と、FastAPIでの依存性注入（Dependency Injection）の具体的なアプローチについて説明します。

---

## 目次

1. [トランザクション境界の定義戦略](#1-トランザクション境界の定義戦略)
2. [複数CRUD操作における整合性担保](#2-複数crud操作における整合性担保)
3. [依存性注入のアプローチ](#3-依存性注入のアプローチ)
4. [実装パターンと設計判断](#4-実装パターンと設計判断)

---

## 1. トランザクション境界の定義戦略

### 1.1 基本方針: Service層でのトランザクション管理

けいかくんアプリケーションでは、**Service層がトランザクション境界を明示的に定義**する設計を採用しています。

#### レイヤーごとの責務

```
┌─────────────────────────────────────────────────┐
│ API層 (Endpoints)                               │
│ - HTTPリクエスト/レスポンス処理                    │
│ - 入力バリデーション                               │
│ - 認証・認可チェック                               │
│ - Service層を呼び出すのみ（commit禁止）            │
└─────────────────┬───────────────────────────────┘
                  │ calls
┌─────────────────▼───────────────────────────────┐
│ Services層                                      │
│ - ビジネスロジック                                 │
│ - 複数CRUD操作の組み合わせ                         │
│ ✅ トランザクション管理（commit/rollback）          │
│ - データ整合性の保証                               │
└─────────────────┬───────────────────────────────┘
                  │ calls
┌─────────────────▼───────────────────────────────┐
│ CRUD層                                          │
│ - 単一モデルのCRUD操作                            │
│ - auto_commitパラメータで動作制御                 │
│ - デフォルト: auto_commit=True                   │
│ - Service層から呼ばれる場合: auto_commit=False   │
└─────────────────┬───────────────────────────────┘
                  │ accesses
┌─────────────────▼───────────────────────────────┐
│ Models層                                        │
│ - データベーステーブル定義                          │
│ - リレーションシップ定義                            │
└─────────────────────────────────────────────────┘
```

---

### 1.2 auto_commitパラメータによる制御

#### CRUD Base層の実装

**ファイル**: `k_back/app/crud/base.py:42-70`

```python
class CRUDBase(Generic[ModelType, CreateSchemaType, UpdateSchemaType]):
    """すべてのCRUDクラスのベースクラス"""

    async def create(
        self,
        db: AsyncSession,
        *,
        obj_in: CreateSchemaType,
        auto_commit: bool = True  # ✅ デフォルトはTrue（単独呼び出し時）
    ) -> ModelType:
        """新しいレコードを作成"""
        obj_in_data = jsonable_encoder(obj_in)
        db_obj = self.model(**obj_in_data)
        db.add(db_obj)

        if auto_commit:
            # 通常パターン: 即座にコミット
            await db.commit()
            await db.refresh(db_obj)
        else:
            # Service層からの呼び出し: コミットを遅延
            await db.flush()  # IDを確定させるがコミットしない

        return db_obj

    async def update(
        self,
        db: AsyncSession,
        *,
        db_obj: ModelType,
        obj_in: Union[UpdateSchemaType, Dict[str, Any]],
        auto_commit: bool = True  # ✅ デフォルトはTrue
    ) -> ModelType:
        """既存のレコードを更新"""
        # ... 更新処理 ...

        db.add(db_obj)

        if auto_commit:
            await db.commit()
            await db.refresh(db_obj)
        else:
            await db.flush()

        return db_obj
```

**設計意図**:

1. **単独呼び出し時**: `auto_commit=True`（デフォルト）により、CRUD操作単独で完結
2. **Service層からの呼び出し**: `auto_commit=False`で遅延コミット、Service層で一括コミット

---

### 1.3 Unit of Work（作業単位）パターン

Service層では、**複数のCRUD操作を1つのトランザクションでまとめる**Unit of Workパターンを実装しています。

#### 実装例: Billing Service

**ファイル**: `k_back/app/services/billing_service.py:37-146`

```python
class BillingService:
    """課金サービス層 - トランザクション管理を担当"""

    async def create_checkout_session_with_customer(
        self,
        db: AsyncSession,
        *,
        billing_id: UUID,
        office_id: UUID,
        # ... その他のパラメータ
    ) -> Dict[str, str]:
        """
        Stripe Checkout Sessionを作成（Customer作成を含む）

        ✅ トランザクション境界: このメソッド全体が1つのトランザクション
        """
        try:
            # ===== トランザクション開始 =====

            # ① 外部API呼び出し（Stripe Customer作成）
            stripe.api_key = stripe_secret_key
            customer = stripe.Customer.create(
                email=user_email,
                name=office_name,
                metadata={"office_id": str(office_id), "staff_id": str(user_id)}
            )
            customer_id = customer.id
            logger.info(f"Stripe Customer created: {customer_id}")

            # ② DB更新（auto_commit=Falseで遅延commit）
            await crud.billing.update_stripe_customer(
                db=db,
                billing_id=billing_id,
                stripe_customer_id=customer_id,
                auto_commit=False  # ← 重要: コミットを遅延
            )

            # ③ 外部API呼び出し（Stripe Checkout Session作成）
            checkout_session = stripe.checkout.Session.create(
                mode='subscription',
                customer=customer_id,
                # ... その他のパラメータ
            )
            logger.info(f"Stripe Checkout Session created: {checkout_session.id}")

            # ④ 全ての操作が成功した後、1回だけcommit
            await db.commit()

            # ===== トランザクション終了（成功） =====

            return {
                "session_id": checkout_session.id,
                "url": checkout_session.url
            }

        except stripe.error.StripeError as e:
            # Stripeエラー時はロールバック
            await db.rollback()
            logger.error(f"Stripe API error: {e}")
            raise HTTPException(...)

        except Exception as e:
            # その他のエラー時もロールバック
            await db.rollback()
            logger.error(f"Checkout session creation error: {e}")
            raise HTTPException(...)
```

**トランザクション境界の可視化**:

```
トランザクション開始（暗黙的 - AsyncSessionのライフサイクル）
    ↓
① Stripe Customer作成（外部API）
    ↓
② DB更新（auto_commit=False → flush()のみ）
    ↓
③ Stripe Checkout Session作成（外部API）
    ↓
④ db.commit() ← ✅ ここで初めてDBにコミット
    ↓
トランザクション終了（成功）

エラー発生時:
    ↓
db.rollback() ← ✅ すべての変更を破棄
    ↓
トランザクション終了（失敗）
```

---

## 2. 複数CRUD操作における整合性担保

### 2.1 トランザクションの原子性（Atomicity）

**すべての操作が成功するか、すべて失敗するか**を保証します。

#### 実装例: 支払い成功Webhook処理

**ファイル**: `k_back/app/services/billing_service.py:148-240`

```python
async def process_payment_succeeded(
    self,
    db: AsyncSession,
    *,
    event_id: str,
    customer_id: str
) -> None:
    """
    支払い成功Webhookを処理

    ✅ トランザクション境界: 複数のDB操作を1つのトランザクションで実行
    """
    try:
        # ===== トランザクション開始 =====

        # Session内のオブジェクトを期限切れにして最新データを取得
        db.expire_all()

        # Billing情報を取得
        billing = await crud.billing.get_by_stripe_customer_id(
            db=db,
            stripe_customer_id=customer_id
        )

        if not billing:
            # テストデータの場合はスキップ
            await crud.webhook_event.create_event_record(
                db=db,
                event_id=event_id,
                event_type='invoice.payment_succeeded',
                source='stripe',
                billing_id=None,
                office_id=None,
                payload={"customer_id": customer_id, "note": "Customer not found"},
                status='skipped',
                auto_commit=True  # ← スキップ記録は即座にコミット
            )
            return

        # ① 支払い記録を更新（auto_commit=False）
        await crud.billing.record_payment(
            db=db,
            billing_id=billing.id,
            auto_commit=False  # ← コミット遅延
        )

        # ② Webhookイベント記録（auto_commit=False）
        await crud.webhook_event.create_event_record(
            db=db,
            event_id=event_id,
            event_type='invoice.payment_succeeded',
            source='stripe',
            billing_id=billing.id,
            office_id=billing.office_id,
            payload={"customer_id": customer_id},
            status='processed',
            auto_commit=False  # ← コミット遅延
        )

        # ③ 監査ログ記録（auto_commit=False）
        await crud.audit_log.create_log(
            db=db,
            office_id=billing.office_id,
            action="billing.payment_succeeded",
            target_type="billing",
            target_id=billing.id,
            actor_id=None,
            details={
                "event_id": event_id,
                "customer_id": customer_id,
                "billing_status": billing.billing_status.value
            },
            auto_commit=False  # ← コミット遅延
        )

        # ④ 全ての操作が成功した後、1回だけcommit
        await db.commit()

        # ===== トランザクション終了（成功） =====

        logger.info(
            f"[Webhook:{event_id}] Payment succeeded processed successfully "
            f"for billing {billing.id}"
        )

    except Exception as e:
        # エラー時はロールバック
        await db.rollback()
        logger.error(f"[Webhook:{event_id}] Error processing payment: {e}")
        raise
```

**原子性の保証**:

```
シナリオ: ③の監査ログ記録でエラーが発生

auto_commitパターンなし（悪い例）:
  ① 支払い記録更新 → コミット ✅
  ② Webhookイベント記録 → コミット ✅
  ③ 監査ログ記録 → エラー ❌
  → 結果: 部分的なデータ更新（不整合）

auto_commitパターンあり（良い例）:
  ① 支払い記録更新 → flush()のみ
  ② Webhookイベント記録 → flush()のみ
  ③ 監査ログ記録 → エラー発生
  → db.rollback() → すべての変更が破棄 ✅
  → 結果: データ整合性が保たれる
```

---

### 2.2 外部APIとDB操作の統合

外部API（Stripe、Google Calendar等）とDB操作を組み合わせる場合の戦略。

#### 基本方針

```
原則: 外部API呼び出しを先に実行し、成功したらDB更新

理由:
  - 外部APIはロールバック不可（一度作成したリソースは削除が必要）
  - DB操作はロールバック可能
  → 外部API成功 → DB失敗 → ロールバック → 再試行可能
  → DB成功 → 外部API失敗 → DBロールバック必要だが外部リソースが残る
```

#### 実装例: 正しい順序

```python
async def create_checkout_session_with_customer(self, db: AsyncSession, ...):
    try:
        # ① 外部API（作成）- ロールバック不可なので先に実行
        customer = stripe.Customer.create(...)

        # ② 外部API（作成）- ロールバック不可
        checkout_session = stripe.checkout.Session.create(...)

        # ③ DB更新（ロールバック可能）- 最後に実行
        await crud.billing.update_stripe_customer(
            db=db,
            billing_id=billing_id,
            stripe_customer_id=customer.id,
            auto_commit=False
        )

        # ④ すべて成功したらコミット
        await db.commit()

    except stripe.error.StripeError as e:
        # Stripeエラー時
        # - Customerが作成されている可能性あり → 手動削除が必要（別タスクで実行）
        # - DBはロールバック
        await db.rollback()
        raise

    except Exception as e:
        # DBエラー時
        # - Stripeリソースは作成済み → クリーンアップが必要
        # - DBはロールバック
        await db.rollback()
        raise
```

#### 冪等性（Idempotency）の保証

Webhookなど、同じイベントが複数回処理される可能性がある場合。

```python
async def process_webhook(self, db: AsyncSession, event_id: str, ...):
    """Webhookイベントを処理（冪等性保証）"""

    # ① 既に処理済みかチェック
    existing_event = await crud.webhook_event.get_by_event_id(
        db=db,
        event_id=event_id
    )

    if existing_event:
        logger.info(f"Event {event_id} already processed - skipping")
        return  # 既に処理済み → 何もしない

    # ② 新規イベント処理
    try:
        # ビジネスロジック実行
        await self._process_business_logic(db, ...)

        # イベント記録を作成（処理完了マーカー）
        await crud.webhook_event.create_event_record(
            db=db,
            event_id=event_id,
            status='processed',
            auto_commit=False
        )

        # すべて成功したらコミット
        await db.commit()

    except Exception as e:
        await db.rollback()
        logger.error(f"Webhook processing failed: {e}")
        raise
```

---

### 2.3 長時間実行トランザクションの回避

#### アンチパターン

```python
# ❌ Bad: 外部API呼び出しをトランザクション内で実行
async def bad_example(db: AsyncSession):
    try:
        # トランザクション開始
        await crud.billing.update_status(db, ..., auto_commit=False)

        # 長時間かかる外部API呼び出し（10秒以上）
        result = await slow_external_api_call()  # ← DBコネクションが長時間保持される

        await crud.billing.update_result(db, ..., auto_commit=False)
        await db.commit()
    except:
        await db.rollback()
```

**問題点**:
- DBコネクションプールの枯渇
- 他のリクエストがブロックされる
- デッドロックのリスク

#### 推奨パターン

```python
# ✅ Good: 外部API呼び出しはトランザクション外で実行
async def good_example(db: AsyncSession):
    # ① トランザクション外で外部API呼び出し
    result = await slow_external_api_call()

    # ② 短いトランザクションでDB更新
    try:
        await crud.billing.update_status(db, ..., auto_commit=False)
        await crud.billing.update_result(db, result=result, auto_commit=False)
        await db.commit()
    except:
        await db.rollback()
```

---

## 3. 依存性注入のアプローチ

### 3.1 FastAPIのDependsパターン

FastAPIでは、**Depends**を使用して依存性注入を実現します。

#### 3.1.1 DBセッションの注入

**ファイル**: `k_back/app/api/deps.py:25-31`

```python
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import AsyncSessionLocal

async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """
    各APIリクエストに対して、独立したDBセッションを提供する依存性注入関数。
    セッションはリクエスト処理の完了後に自動的にクローズされます。
    """
    async with AsyncSessionLocal() as session:
        yield session
        # リクエスト終了時に自動的にクローズ
```

**使用例（API層）**:

```python
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from app.api import deps

router = APIRouter()

@router.get("/billing/status")
async def get_billing_status(
    db: AsyncSession = Depends(deps.get_db),  # ✅ DBセッションを注入
    current_user: Staff = Depends(deps.get_current_user)
):
    """課金ステータス取得"""
    billing = await crud.billing.get_by_office_id(db=db, office_id=current_user.office_id)
    return billing
```

**ライフサイクル**:

```
リクエスト開始
    ↓
get_db() 実行 → AsyncSessionLocal() でセッション作成
    ↓
yield session → エンドポイント関数にセッションを渡す
    ↓
エンドポイント関数実行（Service層、CRUD層でセッション使用）
    ↓
エンドポイント関数終了
    ↓
async with ブロック終了 → session.close() 自動実行
    ↓
リクエスト終了
```

---

### 3.2 Service層のインスタンス化戦略

けいかくんアプリケーションでは、**2つのパターン**を使い分けています。

#### パターン1: クラスベース + 手動インスタンス化（推奨）

**特徴**: Service層をクラスとして定義し、エンドポイントで手動インスタンス化

**実装例**:

```python
# ==========================================
# Service層定義
# ==========================================
# k_back/app/services/billing_service.py

class BillingService:
    """課金サービス層"""

    async def create_checkout_session_with_customer(
        self,
        db: AsyncSession,  # ← DBセッションをメソッド引数で受け取る
        *,
        billing_id: UUID,
        # ... その他のパラメータ
    ) -> Dict[str, str]:
        """Checkout Session作成"""
        # ビジネスロジック実装
        pass


# ==========================================
# API層での使用
# ==========================================
# k_back/app/api/v1/endpoints/billing.py

from app.services import BillingService

# モジュールレベルでインスタンス化
billing_service = BillingService()

@router.post("/create-checkout-session")
async def create_checkout_session(
    db: AsyncSession = Depends(deps.get_db),
    current_user: Staff = Depends(deps.require_owner)
):
    """Checkout Session作成API"""

    # Service層を呼び出し（DBセッションを渡す）
    return await billing_service.create_checkout_session_with_customer(
        db=db,  # ✅ DBセッションをService層に渡す
        billing_id=billing.id,
        office_id=office_id,
        # ... その他のパラメータ
    )
```

**利点**:
- **シンプル**: インスタンス化が明示的
- **テストしやすい**: モック化が容易
- **柔軟性**: 複数のServiceメソッドを呼び出しやすい

**欠点**:
- DIコンテナの恩恵を受けにくい
- グローバルインスタンス（モジュールレベル）になりがち

---

#### パターン2: 関数ベース + 依存性注入

**特徴**: Service層を依存性注入可能な関数として定義

**実装例**:

```python
# ==========================================
# Service層定義（依存性注入対応）
# ==========================================
# k_back/app/services/mfa.py

class MfaService:
    def __init__(self, db: AsyncSession):
        """
        コンストラクタでDBセッションを受け取る

        Args:
            db: データベースセッション
        """
        self.db = db

    async def enroll(self, user: Staff) -> dict[str, str]:
        """MFA登録処理"""
        # self.dbを使用してDB操作
        mfa_secret = generate_totp_secret()
        user.set_mfa_secret(mfa_secret)

        return {
            "secret_key": mfa_secret,
            "qr_code_uri": generate_totp_uri(user.email, mfa_secret)
        }


# ==========================================
# 依存性注入ファクトリー関数
# ==========================================
def get_mfa_service(db: AsyncSession = Depends(deps.get_db)) -> MfaService:
    """MfaServiceのインスタンスを生成する依存性注入関数"""
    return MfaService(db)


# ==========================================
# API層での使用
# ==========================================
# k_back/app/api/v1/endpoints/mfa.py

@router.post("/mfa/enroll")
async def enroll_mfa(
    current_user: Staff = Depends(deps.get_current_user),
    mfa_service: MfaService = Depends(get_mfa_service)  # ✅ Service層を注入
):
    """MFA登録API"""

    # Service層を呼び出し（DBセッションは既に注入済み）
    mfa_enrollment_data = await mfa_service.enroll(user=current_user)

    # トランザクションをコミット（必要な場合）
    await mfa_service.db.commit()

    return mfa_enrollment_data
```

**利点**:
- **依存性注入の恩恵**: FastAPIのDIシステムを活用
- **テストしやすい**: モック化が容易（Dependsをオーバーライド）
- **スコープ管理**: リクエストスコープでインスタンス化

**欠点**:
- ファクトリー関数が必要（ボイラープレート）
- やや複雑

---

### 3.3 推奨パターンの選択基準

| 条件 | 推奨パターン | 理由 |
|------|------------|------|
| **複数のServiceメソッドを呼ぶ** | パターン1（手動） | インスタンスを使い回しやすい |
| **Serviceが状態を持つ** | パターン2（DI） | リクエストスコープで管理 |
| **テストの複雑度が高い** | パターン2（DI） | モック化が容易 |
| **シンプルさ優先** | パターン1（手動） | ボイラープレート最小 |

**けいかくんアプリの実装**: 現在は**パターン1（手動インスタンス化）**を主に使用

**理由**:
- シンプルで理解しやすい
- DBセッションの受け渡しが明示的
- テストでのモック化も十分可能

---

### 3.4 CRUD層への依存性注入

CRUD層は**シングルトンパターン**で実装し、グローバルにインポート可能にしています。

#### 実装例

**ファイル**: `k_back/app/crud/__init__.py`

```python
"""CRUD操作の集約モジュール"""

from app.crud.crud_billing import CRUDBilling
from app.crud.crud_office import CRUDOffice
from app.crud.crud_staff import CRUDStaff
# ... その他のCRUD

from app.models.billing import Billing
from app.models.office import Office
from app.models.staff import Staff
# ... その他のモデル

# シングルトンインスタンス作成
billing = CRUDBilling(Billing)
office = CRUDOffice(Office)
staff = CRUDStaff(Staff)
# ... その他のCRUDインスタンス
```

**使用例（Service層）**:

```python
from app import crud  # ← シングルトンインスタンスをインポート

class BillingService:
    async def process_payment(self, db: AsyncSession, billing_id: UUID):
        # CRUDインスタンスを直接使用（DBセッションを渡す）
        billing = await crud.billing.get(db=db, id=billing_id)
        #                  ↑ シングルトン

        await crud.billing.update_status(
            db=db,
            billing_id=billing_id,
            status=BillingStatus.active,
            auto_commit=False
        )

        await crud.audit_log.create_log(
            db=db,
            office_id=billing.office_id,
            action="payment.processed",
            auto_commit=False
        )

        await db.commit()
```

**利点**:
- **循環インポート回避**: `from app import crud`で一元管理
- **シンプル**: DIコンテナ不要
- **一貫性**: すべてのServiceで同じCRUDインスタンスを使用

---

## 4. 実装パターンと設計判断

### 4.1 トランザクション境界の判断基準

#### ケース1: 単一CRUD操作

```python
# API層で直接CRUD呼び出し（Service層不要）
@router.get("/offices/{office_id}")
async def get_office(
    office_id: UUID,
    db: AsyncSession = Depends(deps.get_db)
):
    """事業所取得（単純な読み取り）"""
    office = await crud.office.get(db=db, id=office_id)
    # auto_commit=Trueがデフォルト → トランザクション自動管理
    return office
```

**判断**: Service層不要、CRUD層で完結

---

#### ケース2: 複数CRUD操作（関連性あり）

```python
# Service層で複数CRUD操作をまとめる
class SupportPlanService:
    @staticmethod
    async def create_new_cycle(
        db: AsyncSession,
        welfare_recipient_id: UUID,
        office_id: UUID
    ) -> SupportPlanCycle:
        """新しいサイクルを作成（複数テーブル更新）"""
        try:
            # ① 旧サイクルを「最新ではない」に更新
            old_cycle = await crud.support_plan_cycle.get_latest(
                db=db,
                welfare_recipient_id=welfare_recipient_id
            )
            old_cycle.is_latest_cycle = False

            # ② 新サイクルを作成
            new_cycle = SupportPlanCycle(
                welfare_recipient_id=welfare_recipient_id,
                office_id=office_id,
                cycle_number=old_cycle.cycle_number + 1
            )
            db.add(new_cycle)
            await db.flush()

            # ③ ステータスレコードを作成（5つのステップ）
            for step in CYCLE_STEPS:
                status = SupportPlanStatus(
                    plan_cycle_id=new_cycle.id,
                    step_type=step
                )
                db.add(status)

            await db.flush()

            # ④ すべて成功したらコミット
            await db.commit()

            return new_cycle

        except Exception as e:
            await db.rollback()
            logger.error(f"Error creating cycle: {e}")
            raise
```

**判断**: Service層で複数CRUD操作を1つのトランザクションで管理

---

#### ケース3: 外部API + DB操作

```python
# Service層で外部APIとDB操作を統合
class BillingService:
    async def create_checkout_session_with_customer(
        self,
        db: AsyncSession,
        # ... パラメータ
    ):
        """外部API（Stripe）とDB操作の統合"""
        try:
            # ① 外部API（先に実行）
            customer = stripe.Customer.create(...)

            # ② DB操作（後に実行）
            await crud.billing.update_stripe_customer(
                db=db,
                stripe_customer_id=customer.id,
                auto_commit=False
            )

            # ③ 外部API
            checkout_session = stripe.checkout.Session.create(...)

            # ④ コミット
            await db.commit()

            return {"url": checkout_session.url}

        except Exception as e:
            await db.rollback()
            raise
```

**判断**: Service層で外部APIとDB操作を協調させる

---

### 4.2 エラーハンドリング戦略

#### レイヤーごとのエラーハンドリング

```python
# ==========================================
# API層: HTTPExceptionを返す
# ==========================================
@router.post("/create-checkout-session")
async def create_checkout_session(
    db: AsyncSession = Depends(deps.get_db),
    current_user: Staff = Depends(deps.require_owner)
):
    try:
        # Service層を呼び出し
        result = await billing_service.create_checkout_session_with_customer(
            db=db,
            # ... パラメータ
        )
        return result

    except HTTPException:
        # Service層からのHTTPExceptionはそのまま再スロー
        raise

    except Exception as e:
        # 予期しないエラー → 500エラー
        logger.error(f"Unexpected error: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="予期しないエラーが発生しました"
        )


# ==========================================
# Service層: ビジネスロジックエラーをHTTPExceptionに変換
# ==========================================
class BillingService:
    async def create_checkout_session_with_customer(
        self,
        db: AsyncSession,
        # ... パラメータ
    ):
        try:
            # ビジネスロジック実行
            # ...
            await db.commit()
            return result

        except stripe.error.StripeError as e:
            # Stripeエラー → HTTPException
            await db.rollback()
            logger.error(f"Stripe error: {e}")
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="決済処理でエラーが発生しました"
            )

        except Exception as e:
            # その他のエラー → ロールバック後、再スロー
            await db.rollback()
            logger.error(f"Service error: {e}")
            raise


# ==========================================
# CRUD層: 低レベルエラーをそのまま伝播
# ==========================================
class CRUDBilling:
    async def update_stripe_customer(
        self,
        db: AsyncSession,
        billing_id: UUID,
        stripe_customer_id: str,
        auto_commit: bool = True
    ):
        billing = await self.get(db=db, id=billing_id)

        if not billing:
            # NotFoundエラー（呼び出し元で処理）
            raise ValueError(f"Billing {billing_id} not found")

        billing.stripe_customer_id = stripe_customer_id
        db.add(billing)

        if auto_commit:
            await db.commit()
            await db.refresh(billing)
        else:
            await db.flush()

        return billing
```

---

### 4.3 まとめ: トランザクション管理と依存性注入のベストプラクティス

#### トランザクション管理

| 原則 | 実装方法 | 効果 |
|------|---------|------|
| **Service層で境界定義** | auto_commit=Falseパラメータ | 明確なトランザクション境界 |
| **Unit of Work** | 複数CRUD操作を1つのcommitでまとめる | データ整合性保証 |
| **外部API先行** | 外部API → DB操作の順序 | ロールバック可能性の最大化 |
| **エラーハンドリング** | try-except + rollback | 確実なロールバック |

#### 依存性注入

| 要素 | 実装方法 | 利点 |
|------|---------|------|
| **DBセッション** | FastAPI Depends + get_db() | リクエストスコープ管理 |
| **Service層** | 手動インスタンス化（推奨） | シンプル、明示的 |
| **CRUD層** | シングルトンパターン | 循環インポート回避 |

#### コード品質の指標

```python
# ✅ Good: 明確なトランザクション境界
async def good_service_method(self, db: AsyncSession):
    try:
        await crud.model1.create(db, obj_in=data1, auto_commit=False)
        await crud.model2.create(db, obj_in=data2, auto_commit=False)
        await db.commit()
    except Exception as e:
        await db.rollback()
        raise

# ❌ Bad: 不明確なトランザクション境界
async def bad_service_method(self, db: AsyncSession):
    await crud.model1.create(db, obj_in=data1)  # いつコミット？
    await crud.model2.create(db, obj_in=data2)  # 独立したトランザクション？
```

---

**最終更新日**: 2026-01-26
**文書管理者**: 開発チーム
