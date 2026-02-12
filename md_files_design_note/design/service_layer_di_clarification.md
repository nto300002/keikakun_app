# Service層における依存性注入の実装詳細と設計判断

## 質問への回答

**Q: サービス層はDIを明示的には利用していないということですか？**

**A: はい、その理解で正しいです。** けいかくんアプリケーションでは、Service層のインスタンス自体はFastAPIのDIコンテナから注入されておらず、**モジュールレベルで手動インスタンス化**しています。ただし、DBセッションはFastAPIのDependsで注入されています。

---

## 現在の実装パターン

### 1. 実際のコード例

**ファイル**: `k_back/app/api/v1/endpoints/billing.py:20-46`

```python
"""Billing API エンドポイント"""
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app import crud
from app.api import deps
from app.services import BillingService

router = APIRouter()

# ✅ ポイント: モジュールレベルでService層を手動インスタンス化
# DIコンテナは使用していない
billing_service = BillingService()


@router.post("/create-checkout-session")
async def create_checkout_session(
    db: AsyncSession = Depends(deps.get_db),  # ← DBセッションはDI
    current_user: Staff = Depends(deps.require_owner)
):
    """Checkout Session作成API"""

    # Service層を呼び出し（手動インスタンス化されたオブジェクトを使用）
    return await billing_service.create_checkout_session_with_customer(
        db=db,  # ← DBセッションを引数で渡す
        billing_id=billing.id,
        office_id=office_id,
        # ... その他のパラメータ
    )
```

### 2. 図解: 現在の依存性注入の範囲

```
┌─────────────────────────────────────────────────────────┐
│ API層 (Endpoints)                                        │
│                                                          │
│  billing_service = BillingService()  ← 手動インスタンス化│
│  ↑ DIコンテナからの注入ではない                           │
│                                                          │
│  @router.post("/endpoint")                              │
│  async def endpoint(                                     │
│      db: AsyncSession = Depends(deps.get_db)  ← DI ✅   │
│  ):                                                      │
│      result = await billing_service.method(             │
│          db=db  ← 引数として渡す                          │
│      )                                                   │
└─────────────────────────────────────────────────────────┘
                           ↓ calls
┌─────────────────────────────────────────────────────────┐
│ Services層                                               │
│                                                          │
│  class BillingService:                                  │
│      async def method(                                  │
│          self,                                          │
│          db: AsyncSession  ← 引数として受け取る           │
│      ):                                                 │
│          # DBセッションを使用                             │
│          await crud.billing.get(db=db, ...)             │
└─────────────────────────────────────────────────────────┘
```

---

## DIを使う部分と使わない部分の整理

### DIを使っている部分（FastAPI Depends）

#### 1. DBセッション

```python
from app.api import deps

async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """DBセッションを提供（DIで注入される）"""
    async with AsyncSessionLocal() as session:
        yield session

# エンドポイントでの使用
@router.get("/endpoint")
async def endpoint(
    db: AsyncSession = Depends(deps.get_db)  # ✅ DI
):
    pass
```

#### 2. 認証情報

```python
async def get_current_user(
    request: Request,
    db: AsyncSession = Depends(get_db),
    token: Optional[str] = Depends(reusable_oauth2)
) -> Staff:
    """現在のユーザーを取得（DIで注入される）"""
    # トークン検証ロジック
    return user

# エンドポイントでの使用
@router.get("/endpoint")
async def endpoint(
    current_user: Staff = Depends(deps.get_current_user)  # ✅ DI
):
    pass
```

#### 3. 権限チェック

```python
async def require_owner(
    current_staff: Staff = Depends(get_current_user)
) -> Staff:
    """Owner権限をチェック（DIで注入される）"""
    if current_staff.role != StaffRole.owner:
        raise HTTPException(status_code=403, detail="権限がありません")
    return current_staff

# エンドポイントでの使用
@router.post("/endpoint")
async def endpoint(
    current_user: Staff = Depends(deps.require_owner)  # ✅ DI
):
    pass
```

#### 4. CSRF検証

```python
async def validate_csrf(request: Request) -> None:
    """CSRFトークンを検証（DIで注入される）"""
    # CSRF検証ロジック
    pass

# エンドポイントでの使用
@router.post("/endpoint")
async def endpoint(
    _: None = Depends(deps.validate_csrf)  # ✅ DI
):
    pass
```

### DIを使っていない部分

#### Service層のインスタンス化

```python
# ❌ DIコンテナからの注入ではない
billing_service = BillingService()

# エンドポイントでの使用
@router.post("/endpoint")
async def endpoint(
    db: AsyncSession = Depends(deps.get_db)
):
    # 手動インスタンス化されたServiceオブジェクトを使用
    result = await billing_service.method(db=db)
    return result
```

---

## なぜService層にDIを使わないのか？

### 理由1: シンプルさの優先

**FastAPIの特性**:
- FastAPIはDIフレームワークが軽量（Dependsのみ）
- Spring BootやNestJSのような重厚なDIコンテナはない
- シンプルな設計が好まれる

**実装の比較**:

```python
# ==========================================
# パターンA: 手動インスタンス化（現在の実装）
# ==========================================
# エンドポイント
billing_service = BillingService()  # シンプル

@router.post("/endpoint")
async def endpoint(db: AsyncSession = Depends(deps.get_db)):
    result = await billing_service.method(db=db)
    return result


# ==========================================
# パターンB: DIコンテナ使用（採用していない）
# ==========================================
# サービス定義
class BillingService:
    def __init__(self, db: AsyncSession):
        self.db = db

# ファクトリー関数
def get_billing_service(
    db: AsyncSession = Depends(deps.get_db)
) -> BillingService:
    return BillingService(db)

# エンドポイント
@router.post("/endpoint")
async def endpoint(
    billing_service: BillingService = Depends(get_billing_service)  # やや複雑
):
    result = await billing_service.method()  # DBセッションは既に注入済み
    return result
```

**比較**:
- パターンA: 3行で完結、明示的
- パターンB: ファクトリー関数が必要、ボイラープレート

### 理由2: DBセッションのスコープ管理

**問題**: Service層がDBセッションを保持すると、スコープ管理が複雑になる

```python
# ❌ 問題のあるパターン
class BillingService:
    def __init__(self, db: AsyncSession):
        self.db = db  # ← DBセッションを保持

    async def method1(self):
        # self.dbを使用
        pass

    async def method2(self):
        # 同じself.dbを使用
        # method1とmethod2が異なるリクエストで呼ばれた場合、
        # セッションの状態が不明確になる可能性
        pass
```

**現在の実装（推奨）**:

```python
# ✅ 推奨パターン
class BillingService:
    # コンストラクタでDBセッションを受け取らない

    async def method1(self, db: AsyncSession):
        # 引数でDBセッションを受け取る
        # 各メソッド呼び出しで明示的にセッションを渡す
        pass

    async def method2(self, db: AsyncSession):
        # 別のセッションを渡すことも可能（柔軟）
        pass
```

### 理由3: テストのしやすさ

**手動インスタンス化のテスト**:

```python
# テストコード
import pytest
from app.services.billing_service import BillingService

@pytest.mark.asyncio
async def test_billing_service(db_session):
    # シンプル: 直接インスタンス化
    service = BillingService()

    # DBセッションをモックとして渡す
    result = await service.create_checkout_session_with_customer(
        db=db_session,  # ← テスト用のセッションを渡す
        billing_id=test_billing_id,
        # ... その他のパラメータ
    )

    assert result["session_id"] is not None
```

**DIを使った場合のテスト**:

```python
# DIを使った場合（やや複雑）
from fastapi.testclient import TestClient

def test_endpoint(client: TestClient):
    # Dependsをオーバーライドする必要がある
    app.dependency_overrides[get_billing_service] = lambda: MockBillingService()

    response = client.post("/endpoint")
    assert response.status_code == 200

    # クリーンアップ
    app.dependency_overrides.clear()
```

---

## 他のフレームワークとの比較

### Spring Boot（Java）の場合

```java
// Service層に@Serviceアノテーション → DIコンテナで管理
@Service
public class BillingService {
    // @Autowiredでリポジトリを注入
    @Autowired
    private BillingRepository billingRepository;

    public void processPayment() {
        // リポジトリを使用
    }
}

// Controller層
@RestController
public class BillingController {
    // @AutowiredでServiceを注入
    @Autowired
    private BillingService billingService;

    @PostMapping("/billing")
    public ResponseEntity<?> createBilling() {
        billingService.processPayment();
        return ResponseEntity.ok().build();
    }
}
```

**特徴**:
- すべてがDIコンテナで管理される
- アノテーションベース
- 暗黙的な依存性解決

### NestJS（TypeScript）の場合

```typescript
// Service層に@Injectableデコレーター → DIコンテナで管理
@Injectable()
export class BillingService {
  constructor(
    // DIで注入
    @InjectRepository(Billing)
    private billingRepository: Repository<Billing>,
  ) {}

  async processPayment() {
    // リポジトリを使用
  }
}

// Controller層
@Controller('billing')
export class BillingController {
  constructor(
    // DIで注入
    private readonly billingService: BillingService
  ) {}

  @Post()
  async createBilling() {
    return this.billingService.processPayment();
  }
}
```

**特徴**:
- Spring Boot風のDI
- デコレーターベース
- 暗黙的な依存性解決

### FastAPI（Python）の場合（けいかくんアプリ）

```python
# Service層: 単純なクラス（デコレーターなし）
class BillingService:
    async def process_payment(self, db: AsyncSession):
        # DBセッションを引数で受け取る
        pass

# API層
billing_service = BillingService()  # 手動インスタンス化

@router.post("/billing")
async def create_billing(
    db: AsyncSession = Depends(deps.get_db)  # DBセッションのみDI
):
    await billing_service.process_payment(db=db)
    return {"status": "success"}
```

**特徴**:
- Service層はDIコンテナで管理されない
- DBセッションなど特定のものだけDI
- 明示的な依存性管理

---

## FastAPIでService層にDIを使うことも可能

実際には、FastAPIでもService層にDIを使うことは可能です。

### 実装例

```python
# ==========================================
# Service層定義
# ==========================================
class BillingService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def process_payment(self, billing_id: UUID):
        # self.dbを使用
        billing = await crud.billing.get(db=self.db, id=billing_id)
        # ... ビジネスロジック
        await self.db.commit()
        return billing


# ==========================================
# DIファクトリー関数
# ==========================================
def get_billing_service(
    db: AsyncSession = Depends(deps.get_db)
) -> BillingService:
    """BillingServiceのインスタンスを生成（DIで注入）"""
    return BillingService(db)


# ==========================================
# API層での使用
# ==========================================
@router.post("/billing")
async def create_billing(
    billing_service: BillingService = Depends(get_billing_service)  # ✅ DI
):
    result = await billing_service.process_payment(billing_id=billing_id)
    return result
```

### なぜこのパターンを採用しなかったか

1. **ファクトリー関数のボイラープレート**: すべてのServiceにファクトリー関数が必要
2. **セッションスコープの複雑さ**: Service内部でDBセッションを保持すると、複数メソッド呼び出し時の管理が複雑
3. **明示性の低下**: DBセッションがどこから来ているか不明確
4. **けいかくんアプリの規模**: 中規模アプリケーションではシンプルなパターンで十分

---

## まとめ

### 現在の設計判断

| 要素 | DIを使用 | 理由 |
|------|---------|------|
| **DBセッション** | ✅ Yes（Depends） | リクエストスコープ管理が必要 |
| **認証情報** | ✅ Yes（Depends） | 複数エンドポイントで共通使用 |
| **権限チェック** | ✅ Yes（Depends） | 宣言的な権限管理 |
| **Service層** | ❌ No（手動） | シンプルさ、明示性、柔軟性 |

### 設計方針

```
FastAPIのDI = 軽量でシンプル
→ 必要最小限のものだけDI
→ Service層は手動管理で十分

vs

Spring Boot / NestJS = 重厚なDIコンテナ
→ すべてをDIコンテナで管理
→ アノテーション/デコレーターで宣言的
```

### 今後の方針

**現状維持を推奨**:
- けいかくんアプリの規模では現在のパターンが最適
- シンプルで理解しやすい
- テストも容易

**DIパターンへの移行が必要になる場合**:
- Service層が状態を持つようになった場合
- Serviceの依存関係が複雑になった場合
- マイクロサービス化を検討する場合

---

## 補足: DIコンテナとは何か？

### DIコンテナの定義

**DIコンテナ（Dependency Injection Container）**は、アプリケーション全体のオブジェクトのライフサイクルと依存関係を**自動的に管理**するフレームワークコンポーネントです。

### DIコンテナの主な機能

#### 1. オブジェクトの登録（Registration）
アプリケーション起動時に、管理対象のクラスやインターフェースをコンテナに登録します。

#### 2. 依存関係の解決（Resolution）
オブジェクトが必要とする依存関係を自動的に解析し、適切なインスタンスを生成・注入します。

#### 3. ライフサイクル管理（Lifecycle Management）
オブジェクトのスコープを管理します：
- **Singleton**: アプリケーション全体で1つのインスタンス
- **Request/Scoped**: HTTPリクエストごとに1つのインスタンス
- **Transient**: 必要なたびに新しいインスタンスを生成

#### 4. 依存関係グラフの構築
複雑な依存関係を自動的に解決します：
```
A depends on B
B depends on C and D
D depends on E

→ コンテナが E → D → C → B → A の順に自動生成
```

---

## 実際のDIコンテナ使用例

### Spring Boot（Java）のDIコンテナ

#### コンテナの起動と構成

```java
// ==========================================
// 1. メインアプリケーションクラス
// ==========================================
@SpringBootApplication  // ← DIコンテナを自動設定
public class KeikakuApplication {
    public static void main(String[] args) {
        // ApplicationContextがDIコンテナの実体
        ApplicationContext context =
            SpringApplication.run(KeikakuApplication.class, args);

        // コンテナから任意のBeanを取得可能
        BillingService service = context.getBean(BillingService.class);
    }
}


// ==========================================
// 2. リポジトリ層の登録
// ==========================================
@Repository  // ← コンテナに登録（Singleton scope）
public class BillingRepository {

    @Autowired  // ← EntityManagerをコンテナから注入
    private EntityManager entityManager;

    public Billing findById(UUID id) {
        return entityManager.find(Billing.class, id);
    }
}


// ==========================================
// 3. サービス層の登録と注入
// ==========================================
@Service  // ← コンテナに登録（Singleton scope）
public class BillingService {

    private final BillingRepository billingRepository;
    private final StripeService stripeService;

    // コンストラクタインジェクション（推奨）
    @Autowired
    public BillingService(
        BillingRepository billingRepository,  // ← コンテナが自動注入
        StripeService stripeService           // ← コンテナが自動注入
    ) {
        this.billingRepository = billingRepository;
        this.stripeService = stripeService;
    }

    @Transactional  // ← コンテナがトランザクション管理
    public void processPayment(UUID billingId) {
        Billing billing = billingRepository.findById(billingId);
        stripeService.charge(billing);
    }
}


// ==========================================
// 4. コントローラ層の登録と注入
// ==========================================
@RestController
@RequestMapping("/api/billing")
public class BillingController {

    private final BillingService billingService;

    @Autowired  // ← コンテナが自動注入
    public BillingController(BillingService billingService) {
        this.billingService = billingService;
    }

    @PostMapping("/{id}/process")
    public ResponseEntity<?> processPayment(@PathVariable UUID id) {
        billingService.processPayment(id);
        return ResponseEntity.ok().build();
    }
}


// ==========================================
// 5. カスタムBean設定
// ==========================================
@Configuration  // ← 設定クラスとして登録
public class AppConfig {

    @Bean  // ← 手動でBeanを登録
    @Scope("request")  // ← リクエストスコープ
    public StripeClient stripeClient() {
        return new StripeClient(apiKey);
    }

    @Bean
    @Primary  // ← 複数候補がある場合の優先Bean
    public ObjectMapper objectMapper() {
        return new ObjectMapper()
            .registerModule(new JavaTimeModule());
    }
}
```

#### DIコンテナの動作フロー

```
1. アプリケーション起動
   ↓
2. @SpringBootApplicationをスキャン
   ↓
3. @Component, @Service, @Repository, @Controllerアノテーションを持つクラスを検出
   ↓
4. ApplicationContext（DIコンテナ）に登録
   ↓
5. 依存関係グラフを構築
   - BillingController → BillingService
   - BillingService → BillingRepository, StripeService
   ↓
6. Singletonスコープのインスタンスを事前生成
   ↓
7. HTTPリクエスト受信時
   ↓
8. Request scopeのBeanを生成（必要に応じて）
   ↓
9. コントローラに依存関係を注入して実行
```

---

### NestJS（TypeScript）のDIコンテナ

#### モジュールシステムとコンテナ

```typescript
// ==========================================
// 1. リポジトリ層（TypeORM）
// ==========================================
import { EntityRepository, Repository } from 'typeorm';
import { Billing } from './billing.entity';

@EntityRepository(Billing)
export class BillingRepository extends Repository<Billing> {
  // カスタムメソッド
  async findByOfficeId(officeId: string): Promise<Billing[]> {
    return this.find({ where: { officeId } });
  }
}


// ==========================================
// 2. サービス層の登録
// ==========================================
import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';

@Injectable()  // ← DIコンテナに登録
export class BillingService {
  constructor(
    // リポジトリを注入（コンテナが自動解決）
    @InjectRepository(BillingRepository)
    private readonly billingRepository: BillingRepository,

    // 別のサービスを注入（コンテナが自動解決）
    private readonly stripeService: StripeService,
  ) {}

  async processPayment(billingId: string): Promise<void> {
    const billing = await this.billingRepository.findOne(billingId);
    await this.stripeService.charge(billing);
  }
}


// ==========================================
// 3. コントローラ層
// ==========================================
import { Controller, Post, Param } from '@nestjs/common';

@Controller('billing')  // ← DIコンテナに登録
export class BillingController {
  constructor(
    // サービスを注入（コンテナが自動解決）
    private readonly billingService: BillingService,
  ) {}

  @Post(':id/process')
  async processPayment(@Param('id') id: string) {
    await this.billingService.processPayment(id);
    return { status: 'success' };
  }
}


// ==========================================
// 4. モジュール定義（DIコンテナの設定）
// ==========================================
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

@Module({
  imports: [
    // BillingRepositoryをコンテナに登録
    TypeOrmModule.forFeature([BillingRepository]),
  ],
  controllers: [
    BillingController,  // ← コンテナに登録
  ],
  providers: [
    BillingService,     // ← コンテナに登録
    StripeService,      // ← コンテナに登録
  ],
  exports: [
    BillingService,     // ← 他のモジュールで使えるようにエクスポート
  ],
})
export class BillingModule {}


// ==========================================
// 5. アプリケーションルートモジュール
// ==========================================
@Module({
  imports: [
    BillingModule,      // ← サブモジュールをインポート
    TypeOrmModule.forRoot({
      // DB設定
    }),
  ],
})
export class AppModule {}


// ==========================================
// 6. アプリケーション起動
// ==========================================
import { NestFactory } from '@nestjs/core';

async function bootstrap() {
  // DIコンテナを初期化してアプリケーション生成
  const app = await NestFactory.create(AppModule);

  // コンテナから任意のサービスを取得可能
  const billingService = app.get(BillingService);

  await app.listen(3000);
}
bootstrap();
```

#### NestJS DIコンテナの特徴

```typescript
// ==========================================
// カスタムプロバイダー（高度な使い方）
// ==========================================
@Module({
  providers: [
    // 1. クラスベースプロバイダー（標準）
    BillingService,

    // 2. 値ベースプロバイダー
    {
      provide: 'API_KEY',
      useValue: process.env.STRIPE_API_KEY,
    },

    // 3. ファクトリープロバイダー（動的生成）
    {
      provide: 'STRIPE_CLIENT',
      useFactory: (apiKey: string) => {
        return new StripeClient(apiKey);
      },
      inject: ['API_KEY'],  // ← ファクトリーの依存関係
    },

    // 4. 既存プロバイダーのエイリアス
    {
      provide: 'BILLING_SERVICE',
      useExisting: BillingService,
    },
  ],
})
export class BillingModule {}


// ==========================================
// スコープ管理
// ==========================================
@Injectable({ scope: Scope.REQUEST })  // ← リクエストスコープ
export class RequestScopedService {
  // HTTPリクエストごとに新しいインスタンス
}

@Injectable({ scope: Scope.TRANSIENT })  // ← 都度生成
export class TransientService {
  // 注入されるたびに新しいインスタンス
}

@Injectable()  // ← デフォルトはSingleton
export class SingletonService {
  // アプリケーション全体で1つのインスタンス
}
```

---

### Python（dependency-injector）の例

FastAPIにはDIコンテナがないので、Pythonで専用ライブラリを使った例：

```python
from dependency_injector import containers, providers
from dependency_injector.wiring import Provide, inject

# ==========================================
# 1. サービスクラス定義
# ==========================================
class BillingRepository:
    def __init__(self, db_session):
        self.db_session = db_session

    def get_by_id(self, billing_id):
        return self.db_session.query(Billing).filter_by(id=billing_id).first()


class StripeService:
    def __init__(self, api_key: str):
        self.api_key = api_key

    def charge(self, amount: int):
        # Stripe API呼び出し
        pass


class BillingService:
    def __init__(self, repository: BillingRepository, stripe: StripeService):
        self.repository = repository
        self.stripe = stripe

    def process_payment(self, billing_id: str):
        billing = self.repository.get_by_id(billing_id)
        self.stripe.charge(billing.amount)


# ==========================================
# 2. DIコンテナ定義
# ==========================================
class Container(containers.DeclarativeContainer):

    # 設定値
    config = providers.Configuration()

    # データベースセッション（Singletonスコープ）
    db_session = providers.Singleton(
        create_db_session,
        connection_string=config.db.connection_string,
    )

    # BillingRepository（Singletonスコープ）
    billing_repository = providers.Singleton(
        BillingRepository,
        db_session=db_session,
    )

    # StripeService（Singletonスコープ）
    stripe_service = providers.Singleton(
        StripeService,
        api_key=config.stripe.api_key,
    )

    # BillingService（依存関係を自動解決）
    billing_service = providers.Singleton(
        BillingService,
        repository=billing_repository,  # ← 自動注入
        stripe=stripe_service,          # ← 自動注入
    )


# ==========================================
# 3. コンテナの使用
# ==========================================
# アプリケーション起動時
container = Container()
container.config.from_yaml('config.yaml')

# 依存関係を注入してサービスを取得
billing_service = container.billing_service()
billing_service.process_payment("billing-123")


# ==========================================
# 4. FastAPIとの統合
# ==========================================
from fastapi import FastAPI, Depends

app = FastAPI()
container = Container()

# DIコンテナからの注入をFastAPIのDependsで使用
@app.post("/billing/{billing_id}/process")
@inject
async def process_payment(
    billing_id: str,
    service: BillingService = Depends(Provide[Container.billing_service])
):
    service.process_payment(billing_id)
    return {"status": "success"}
```

---

## 補足: FastAPIのDependsは「DI」ではないのか？

### 答え: Dependsは立派なDIメカニズムです

**FastAPIのDependsは**:
- ✅ 依存性注入（Dependency Injection）の仕組み
- ✅ 実行時に依存関係を解決
- ✅ テスト時にオーバーライド可能

**ただし**:
- Spring BootやNestJSのような**DIコンテナ**ではない
- アプリケーション全体の依存関係を管理する仕組みはない
- 必要に応じて手動でインスタンス化する設計も推奨される

### DIコンテナ vs FastAPI Dependsの比較

| 特性 | DIコンテナ（Spring/NestJS） | FastAPI Depends |
|------|---------------------------|-----------------|
| **登録方法** | @Service, @Injectableで自動登録 | 関数定義のみ（登録不要） |
| **スコープ管理** | Singleton/Request/Transient | 関数実行ごと（キャッシュ可） |
| **依存関係解決** | コンテナが自動解決 | Dependsチェーンで明示的 |
| **ライフサイクル** | コンテナが管理 | 開発者が管理 |
| **複雑さ** | 高（学習コスト大） | 低（シンプル） |
| **柔軟性** | 低（フレームワーク依存） | 高（Pythonic） |

### 用語の整理

| 用語 | 意味 | FastAPIにおける実装 |
|------|------|-------------------|
| **DI（依存性注入）** | オブジェクトの依存関係を外部から注入する設計パターン | ✅ Dependsで実現 |
| **DIコンテナ** | アプリケーション全体の依存関係を管理する仕組み | ❌ FastAPIには存在しない |
| **IoC（制御の反転）** | フレームワークがアプリケーションコードを呼び出す | ✅ FastAPIのルーティング |

---

**最終更新日**: 2026-01-26
**文書管理者**: 開発チーム
