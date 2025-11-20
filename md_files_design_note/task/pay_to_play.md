# 課金機能要件

## 概要
- **無料期間**: 180日間（お試し期間）
- **月額料金**: 6,000円
- **決済サービス**: Stripe

---

## 現在の実装状況

### データベース（Office テーブル）
`k_back/app/models/office.py`

```python
class Office(Base):
    __tablename__ = 'offices'

    # 基本情報
    id: UUID
    name: str
    type: OfficeType

    # 課金関連（現在Officeテーブルに含まれている）
    billing_status: BillingStatus  # 'free', 'active', 'past_due', 'canceled'
    stripe_customer_id: Optional[str]
    stripe_subscription_id: Optional[str]

    # タイムスタンプ
    created_at: datetime
    updated_at: datetime
    deactivated_at: Optional[datetime]
```

### BillingStatus Enum
`k_back/app/models/enums.py`

```python
class BillingStatus(str, enum.Enum):
    free = 'free'          # 無料プラン（180日間）
    active = 'active'      # 課金中
    past_due = 'past_due'  # 支払い延滞
    canceled = 'canceled'  # キャンセル済み
```

---

## 疑問点への回答

### 1. 自動課金機能（180日後）

#### 仕組み
Stripe の **Subscription（サブスクリプション）** を使用します。

**実装フロー**:

1. **事業所作成時（初日）**
   ```python
   # Stripe Customer を作成
   customer = stripe.Customer.create(
       email=owner_email,
       metadata={"office_id": office.id}
   )

   # DBに保存
   office.stripe_customer_id = customer.id
   office.billing_status = BillingStatus.free
   office.created_at = datetime.now()
   ```

2. **180日経過前（例: 170日目）**
   - ユーザーに通知メールを送信
   - 「10日後に自動的に有料プランに移行します」
   - 支払い方法の登録を促す

3. **180日経過時点**

   **パターンA: 支払い方法が登録済みの場合**
   ```python
   # Subscription を自動作成
   subscription = stripe.Subscription.create(
       customer=office.stripe_customer_id,
       items=[{"price": "price_xxx"}],  # 月額6,000円のPriceID
       trial_end="now",  # 無料期間終了
   )

   # DBを更新
   office.stripe_subscription_id = subscription.id
   office.billing_status = BillingStatus.active
   ```

   **パターンB: 支払い方法が未登録の場合**
   ```python
   # サービスへのアクセスを制限（リードオンリーモードなど）
   office.billing_status = BillingStatus.past_due

   # 支払い方法登録を促す通知を表示
   # 猶予期間（例: 30日）を設ける
   ```

4. **毎月の自動課金**
   - Stripe が自動的に課金処理を実行
   - 課金成功 → `billing_status` は `active` のまま
   - 課金失敗 → `billing_status` を `past_due` に変更

#### スケジューラー実装
```python
# app/tasks/billing_check.py

from datetime import datetime, timedelta
from sqlalchemy import select
from app.models import Office, BillingStatus

async def check_trial_expiration():
    """180日経過した事業所をチェック"""
    trial_end_date = datetime.now() - timedelta(days=180)

    query = select(Office).where(
        Office.billing_status == BillingStatus.free,
        Office.created_at <= trial_end_date
    )

    expired_offices = await db.execute(query)

    for office in expired_offices.scalars():
        # 支払い方法が登録されているかチェック
        customer = stripe.Customer.retrieve(office.stripe_customer_id)

        if customer.default_source or customer.invoice_settings.default_payment_method:
            # サブスクリプション作成
            create_subscription(office)
        else:
            # 支払い方法登録を促す
            office.billing_status = BillingStatus.past_due
            send_payment_required_notification(office)
```

---

### 2. 課金した場合の口座

#### Stripe の入金スケジュール

**日本の場合**:
- **入金サイクル**: 週次または月次（設定可能）
- **デフォルト**: 毎週金曜日に前週分の売上を入金
- **最短**: 決済の2営業日後に入金可能（Express Payout機能）

**例**:
- 1月1日（月）に顧客が6,000円支払い
- 1月5日（金）にStripeから銀行口座に入金
- 手数料: 3.6% + 1件あたり0円 = 約216円
- 入金額: 5,784円

#### 登録する銀行口座

**Stripe ダッシュボードで設定**:
1. Stripe ダッシュボードにログイン
2. 「設定」→「銀行口座と入金スケジュール」
3. 銀行口座情報を入力:
   - 銀行名
   - 支店名
   - 口座種別（普通/当座）
   - 口座番号
   - 口座名義

**必要書類**（Stripe 本人確認）:
- 代表者の本人確認書類（運転免許証、パスポートなど）
- 事業者情報（法人の場合: 登記簿謄本）

---

### 3. Stripe の使い方

#### 基本的なフロー

##### ステップ1: Stripe アカウント作成
1. https://stripe.com/jp にアクセス
2. 「アカウントを作成」
3. メールアドレス、パスワードを入力
4. 本人確認書類を提出

##### ステップ2: API キーを取得
```python
# .env ファイルに追加
STRIPE_SECRET_KEY=sk_test_xxx  # テスト環境
STRIPE_PUBLISHABLE_KEY=pk_test_xxx

# 本番環境
STRIPE_SECRET_KEY=sk_live_xxx
STRIPE_PUBLISHABLE_KEY=pk_live_xxx
```

##### ステップ3: Stripe ライブラリをインストール
```bash
pip install stripe
```

##### ステップ4: Price（料金プラン）を作成
Stripe ダッシュボードで:
1. 「商品」→「新しい商品を追加」
2. 商品名: 「けいかくん 月額プラン」
3. 料金設定:
   - 金額: 6,000円
   - 請求期間: 月次
   - 通貨: JPY

作成後、Price ID をメモ（例: `price_1ABC123...`）

##### ステップ5: バックエンド実装例

```python
# app/services/billing_service.py

import stripe
import os

stripe.api_key = os.getenv("STRIPE_SECRET_KEY")
PRICE_ID = os.getenv("STRIPE_PRICE_ID")  # 上記で作成したPrice ID

class BillingService:

    @staticmethod
    async def create_customer(office: Office, email: str):
        """Stripe Customer を作成"""
        customer = stripe.Customer.create(
            email=email,
            name=office.name,
            metadata={
                "office_id": str(office.id),
                "office_name": office.name,
            }
        )

        office.stripe_customer_id = customer.id
        await db.commit()
        return customer

    @staticmethod
    async def create_checkout_session(office: Office, success_url: str, cancel_url: str):
        """支払い方法登録用のCheckout Sessionを作成"""
        session = stripe.checkout.Session.create(
            customer=office.stripe_customer_id,
            mode='setup',  # 支払い方法の登録のみ
            success_url=success_url,
            cancel_url=cancel_url,
            payment_method_types=['card'],
        )
        return session

    @staticmethod
    async def create_subscription(office: Office):
        """サブスクリプションを作成（180日後に実行）"""
        subscription = stripe.Subscription.create(
            customer=office.stripe_customer_id,
            items=[{"price": PRICE_ID}],
            payment_behavior='default_incomplete',
        )

        office.stripe_subscription_id = subscription.id
        office.billing_status = BillingStatus.active
        await db.commit()
        return subscription

    @staticmethod
    async def cancel_subscription(office: Office):
        """サブスクリプションをキャンセル"""
        stripe.Subscription.delete(office.stripe_subscription_id)

        office.billing_status = BillingStatus.canceled
        await db.commit()
```

##### ステップ6: フロントエンド実装例

```typescript
// k_front/lib/billing.ts

export const billingApi = {
  // Checkout Session を作成
  createCheckoutSession: async () => {
    const response = await fetch('/api/v1/billing/checkout-session', {
      method: 'POST',
      credentials: 'include',
    });
    return response.json();
  },

  // 支払い方法登録ページにリダイレクト
  redirectToCheckout: async () => {
    const session = await billingApi.createCheckoutSession();

    // Stripe Checkout にリダイレクト
    const stripe = await loadStripe(process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY);
    await stripe.redirectToCheckout({ sessionId: session.id });
  },
};
```

##### ステップ7: Webhook の設定（重要）

Stripe からの通知（課金成功、失敗など）を受け取る:

```python
# app/api/v1/endpoints/webhooks.py

from fastapi import APIRouter, Request, HTTPException
import stripe

router = APIRouter()

@router.post("/stripe")
async def stripe_webhook(request: Request):
    payload = await request.body()
    sig_header = request.headers.get('stripe-signature')

    try:
        event = stripe.Webhook.construct_event(
            payload, sig_header, os.getenv("STRIPE_WEBHOOK_SECRET")
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid payload")
    except stripe.error.SignatureVerificationError:
        raise HTTPException(status_code=400, detail="Invalid signature")

    # イベントの種類に応じて処理
    if event['type'] == 'invoice.payment_succeeded':
        # 課金成功
        subscription_id = event['data']['object']['subscription']
        await handle_payment_success(subscription_id)

    elif event['type'] == 'invoice.payment_failed':
        # 課金失敗
        subscription_id = event['data']['object']['subscription']
        await handle_payment_failed(subscription_id)

    elif event['type'] == 'customer.subscription.deleted':
        # サブスクリプション削除
        subscription_id = event['data']['object']['id']
        await handle_subscription_canceled(subscription_id)

    return {"status": "success"}
```

Stripe ダッシュボードで Webhook URL を登録:
- URL: `https://yourdomain.com/api/v1/webhooks/stripe`
- イベント: `invoice.payment_succeeded`, `invoice.payment_failed`, `customer.subscription.deleted`

---

## リファクタリング: 課金テーブルの分離

### 提案: `OfficeBilling` テーブルを作成

#### メリット ✅

1. **関心の分離**: 課金機能のみを独立して管理
2. **将来の拡張性**: 複数プラン、クーポン、請求履歴などを追加しやすい
3. **パフォーマンス**: Office テーブルが肥大化しない
4. **セキュリティ**: 課金情報へのアクセス制御が容易

#### デメリット ❌

1. **JOIN が増える**: Office と OfficeBilling を JOIN する必要がある
2. **マイグレーションコスト**: 既存データの移行が必要
3. **初期実装コスト**: テーブル、モデル、CRUD の追加

---

### 新しいテーブル設計

```python
# app/models/billing.py

class OfficeBilling(Base):
    """事業所の課金情報"""
    __tablename__ = 'office_billings'

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    office_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey('offices.id', ondelete="CASCADE"),
        unique=True,  # 1:1 リレーション
        nullable=False
    )

    # Stripe情報
    stripe_customer_id: Mapped[Optional[str]] = mapped_column(String(255), unique=True)
    stripe_subscription_id: Mapped[Optional[str]] = mapped_column(String(255), unique=True)

    # 課金ステータス
    billing_status: Mapped[BillingStatus] = mapped_column(
        SQLAlchemyEnum(BillingStatus),
        default=BillingStatus.free,
        nullable=False
    )

    # 無料期間
    trial_start_date: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    trial_end_date: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)

    # 課金開始日
    subscription_start_date: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))

    # 次回請求日
    next_billing_date: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))

    # 課金額（履歴として保存）
    current_plan_amount: Mapped[Optional[int]] = mapped_column(default=6000)  # 円

    # タイムスタンプ
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.now)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.now, onupdate=datetime.now)

    # リレーション
    office: Mapped["Office"] = relationship("Office", back_populates="billing")


# app/models/office.py (変更)

class Office(Base):
    __tablename__ = 'offices'

    # ... 既存のフィールド ...

    # 課金関連フィールドを削除
    # billing_status: 削除
    # stripe_customer_id: 削除
    # stripe_subscription_id: 削除

    # リレーションを追加
    billing: Mapped[Optional["OfficeBilling"]] = relationship(
        "OfficeBilling",
        back_populates="office",
        uselist=False,
        cascade="all, delete-orphan"
    )
```

---

### マイグレーション例

```python
# alembic/versions/xxx_create_office_billing.py

def upgrade():
    # 1. office_billings テーブルを作成
    op.create_table(
        'office_billings',
        sa.Column('id', UUID(as_uuid=True), primary_key=True),
        sa.Column('office_id', UUID(as_uuid=True), sa.ForeignKey('offices.id', ondelete='CASCADE'), unique=True, nullable=False),
        sa.Column('stripe_customer_id', sa.String(255), unique=True),
        sa.Column('stripe_subscription_id', sa.String(255), unique=True),
        sa.Column('billing_status', sa.Enum('free', 'active', 'past_due', 'canceled', name='billingstatus'), nullable=False, default='free'),
        sa.Column('trial_start_date', sa.DateTime(timezone=True), nullable=False),
        sa.Column('trial_end_date', sa.DateTime(timezone=True), nullable=False),
        sa.Column('subscription_start_date', sa.DateTime(timezone=True)),
        sa.Column('next_billing_date', sa.DateTime(timezone=True)),
        sa.Column('current_plan_amount', sa.Integer, default=6000),
        sa.Column('created_at', sa.DateTime(timezone=True), default=datetime.now),
        sa.Column('updated_at', sa.DateTime(timezone=True), default=datetime.now, onupdate=datetime.now),
    )

    # 2. 既存データを移行
    connection = op.get_bind()
    offices = connection.execute(sa.text("SELECT id, stripe_customer_id, stripe_subscription_id, billing_status, created_at FROM offices"))

    for office in offices:
        trial_start = office.created_at
        trial_end = trial_start + timedelta(days=180)

        connection.execute(
            sa.text("""
                INSERT INTO office_billings (id, office_id, stripe_customer_id, stripe_subscription_id, billing_status, trial_start_date, trial_end_date, created_at, updated_at)
                VALUES (gen_random_uuid(), :office_id, :customer_id, :subscription_id, :status, :trial_start, :trial_end, :created_at, :updated_at)
            """),
            {
                "office_id": office.id,
                "customer_id": office.stripe_customer_id,
                "subscription_id": office.stripe_subscription_id,
                "status": office.billing_status,
                "trial_start": trial_start,
                "trial_end": trial_end,
                "created_at": datetime.now(),
                "updated_at": datetime.now(),
            }
        )

    # 3. offices テーブルから課金関連カラムを削除
    op.drop_column('offices', 'stripe_customer_id')
    op.drop_column('offices', 'stripe_subscription_id')
    op.drop_column('offices', 'billing_status')


def downgrade():
    # 1. offices テーブルにカラムを復元
    op.add_column('offices', sa.Column('stripe_customer_id', sa.String(255), unique=True))
    op.add_column('offices', sa.Column('stripe_subscription_id', sa.String(255), unique=True))
    op.add_column('offices', sa.Column('billing_status', sa.Enum('free', 'active', 'past_due', 'canceled', name='billingstatus'), nullable=False, default='free'))

    # 2. データを戻す
    connection = op.get_bind()
    billings = connection.execute(sa.text("SELECT * FROM office_billings"))

    for billing in billings:
        connection.execute(
            sa.text("UPDATE offices SET stripe_customer_id = :customer_id, stripe_subscription_id = :subscription_id, billing_status = :status WHERE id = :office_id"),
            {
                "customer_id": billing.stripe_customer_id,
                "subscription_id": billing.stripe_subscription_id,
                "status": billing.billing_status,
                "office_id": billing.office_id,
            }
        )

    # 3. office_billings テーブルを削除
    op.drop_table('office_billings')
```

---

## 実装タスク

### Phase 1: Stripe セットアップ（1週間）

| タスク | 詳細 | 工数 |
|--------|------|------|
| Stripe アカウント作成 | 本人確認書類提出、銀行口座登録 | 2時間 |
| Price 作成 | 月額6,000円プランを作成 | 0.5時間 |
| 環境変数設定 | API キー、Webhook Secret | 0.5時間 |
| Webhook エンドポイント実装 | 課金成功/失敗の通知受信 | 4時間 |
| テスト | Stripe テストモードで動作確認 | 2時間 |

**小計**: 9時間（約1日）

### Phase 2: バックエンド実装（2週間）

| タスク | 詳細 | 工数 |
|--------|------|------|
| OfficeBilling テーブル作成 | マイグレーション、モデル定義 | 3時間 |
| 既存データ移行 | Office → OfficeBilling | 2時間 |
| BillingService 実装 | Customer、Subscription 作成 | 6時間 |
| スケジューラー実装 | 180日経過チェック | 4時間 |
| APIエンドポイント追加 | Checkout Session 作成など | 4時間 |
| テスト | ユニットテスト、統合テスト | 6時間 |

**小計**: 25時間（約3日）

### Phase 3: フロントエンド実装（1週間）

| タスク | 詳細 | 工数 |
|--------|------|------|
| 支払い方法登録画面 | Stripe Checkout 連携 | 4時間 |
| 課金ステータス表示 | ダッシュボードに表示 | 2時間 |
| 通知UI | 180日経過前の通知バナー | 3時間 |
| サブスクリプション管理画面 | キャンセル、再開 | 4時間 |
| テスト | E2Eテスト | 3時間 |

**小計**: 16時間（約2日）

### Phase 4: テスト・デプロイ（1週間）

| タスク | 詳細 | 工数 |
|--------|------|------|
| Stripe テストモードで検証 | 全フロー確認 | 4時間 |
| 利用規約更新 | 無償期間、課金条件を明記 | 2時間 |
| 本番環境デプロイ | Stripe 本番モードに切り替え | 2時間 |
| 監視設定 | 課金エラーの通知設定 | 2時間 |

**小計**: 10時間（約1.5日）

**総実装期間**: 約7.5日

---

## 利用規約の修正

### 追加すべき項目

```markdown
## 第X条（無料試用期間）
1. 本サービスは、登録日から180日間、無料でご利用いただけます。
2. 無料試用期間終了後、自動的に有料プラン（月額6,000円）に移行します。
3. 有料プランへの移行を希望しない場合は、試用期間終了前にサービスを解約してください。

## 第X条（料金および支払い）
1. 有料プランの料金は、月額6,000円（税込）とします。
2. 支払い方法は、クレジットカード決済のみとします。
3. 料金は、毎月の課金日に自動的に請求されます。
4. 支払いが確認できない場合、サービスの利用を制限することがあります。

## 第X条（解約）
1. お客様は、いつでもサービスを解約できます。
2. 解約は、次回課金日の前日までに行ってください。
3. 解約後、データは30日間保存され、その後削除されます。
4. 一度支払われた料金の返金は行いません。
```

---

## まとめ

### 自動課金機能
- **Stripe Subscription** を使用
- 180日経過時に自動的にサブスクリプションを作成
- 支払い失敗時は `past_due` ステータスに変更し、通知を送信

### 課金した場合の口座
- **Stripe ダッシュボード**で銀行口座を登録
- **入金サイクル**: 週次（毎週金曜日）または月次
- **手数料**: 3.6%

### Stripe の使い方
1. アカウント作成 → 本人確認
2. Price（料金プラン）作成
3. APIキーを環境変数に設定
4. バックエンドで Customer、Subscription を作成
5. Webhook で課金イベントを受信
6. フロントエンドで Stripe Checkout に連携

### テーブル分離のメリット・デメリット
- **メリット**: 関心の分離、拡張性、セキュリティ
- **デメリット**: JOIN が増える、マイグレーションコスト
- **推奨**: 将来の拡張を考えると分離した方が良い
