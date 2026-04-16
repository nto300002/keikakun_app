# バックエンド データ設計書

**対象**: keikakun_app バックエンド（FastAPI + SQLAlchemy + PostgreSQL）
**最終更新**: 2026-03-10

---

## 目次

1. [設計方針](#設計方針)
2. [ドメイン構成](#ドメイン構成)
3. [テーブル一覧](#テーブル一覧)
4. [各テーブルの設計詳細](#各テーブルの設計詳細)
   - [コアドメイン](#コアドメイン)
   - [個別支援計画ドメイン](#個別支援計画ドメイン)
   - [アセスメントドメイン](#アセスメントドメイン)
   - [セキュリティ・認証ドメイン](#セキュリティ認証ドメイン)
   - [カレンダードメイン](#カレンダードメイン)
   - [通知・コミュニケーションドメイン](#通知コミュニケーションドメイン)
   - [監査・コンプライアンスドメイン](#監査コンプライアンスドメイン)
5. [共通設計ルール](#共通設計ルール)

---

## 設計方針

### マルチテナンシー戦略

**Row-Level Multi-tenancy（行レベル分離）**を採用している。

```
offices (テナントルート)
  ├── office_staffs     ← スタッフの所属
  ├── office_welfare_recipients ← 受給者の所属
  ├── billings          ← 課金情報 (1:1)
  ├── support_plan_cycles
  ├── calendar_events
  └── ...
```

- 物理的にDBを分けるスキーマ分離ではなく、全テーブルに `office_id` を持たせる
- **理由**: 中小規模の福祉事業所向けSaaSとして、コストと運用の簡便さを優先
- APIレイヤーで `office_id` フィルタを必ず適用し、テナント間データ漏洩を防止

**実コードでの適用例** (`k_back/app/crud/crud_support_plan.py:103-108`):

```python
# 事業所フィルター（必須）
# WelfareRecipient -> OfficeWelfareRecipient -> Office の JOINでテナント分離
query = query.join(
    OfficeWelfareRecipient,
    WelfareRecipient.id == OfficeWelfareRecipient.welfare_recipient_id
).where(OfficeWelfareRecipient.office_id == office_id)
```

受給者は `office_welfare_recipients` 経由で事業所に紐づくため、直接 `welfare_recipients.office_id` を持たない。これを JOIN でつなぐパターンがテナント分離の基本形。

---

### UUID主キー戦略

- ほぼ全テーブルで `UUID` を主キーとして使用（`gen_random_uuid()` by PostgreSQL）
- **理由**: 連番だと `/users/1` のようなエンドポイントでIDが予測可能になりセキュリティリスク
- 例外: `service_recipient_details`、`disability_details` 等の詳細サブテーブルは `Integer` 連番（外部に公開されない内部参照のみのため）

**実コードでの定義** (`k_back/app/models/office.py:30`):

```python
# PostgreSQL の gen_random_uuid() をサーバー側で生成
id: Mapped[uuid.UUID] = mapped_column(
    UUID(as_uuid=True),
    primary_key=True,
    server_default=func.gen_random_uuid()  # アプリ側でなくDB側で生成
)
```

`server_default` でDB側生成にする理由: INSERT前にIDが確定することで、flush前に参照が必要な場合でも `await db.flush()` → `await db.refresh(obj)` で取得できる。

---

### 論理削除戦略

主要エンティティ（`offices`、`staffs`）は物理削除ではなく論理削除を採用:

**実コードでの定義** (`k_back/app/models/staff.py:62-64`):

```python
# 論理削除関連（スタッフ削除機能用）
is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False, index=True)
deleted_at: Mapped[Optional[datetime.datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
deleted_by: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey('staffs.id'), nullable=True)
```

**理由**:
- 退会後も監査ログ・`archived_staffs` でデータ追跡が必要
- 関連テーブルの `ondelete="SET NULL"` との組み合わせで参照整合性を維持
- `deleted_by` に自己参照FK（誰が削除したか）を記録する設計

---

### is_test_data フラグ

全テーブルに `is_test_data: bool` カラムを持つ。

**実コードでの使われ方** (`k_back/app/crud/crud_staff.py:31-33`):

```python
async def create_admin(self, db: AsyncSession, *, obj_in: AdminCreate) -> Staff:
    # テスト環境の場合はis_test_data=Trueを設定
    is_test_data = os.getenv("TESTING") == "1"
    db_obj = Staff(
        ...
        is_test_data=is_test_data,
    )
```

環境変数 `TESTING=1` が立っている場合は自動的に `is_test_data=True` にセット。テスト後のクリーンアップは `WHERE is_test_data = true` で一括削除できる。

---

## ドメイン構成

```
[コアドメイン]
  offices ─── office_staffs ─── staffs
      └────── office_welfare_recipients ─── welfare_recipients
      └────── billings

[個別支援計画ドメイン]
  welfare_recipients
      └── support_plan_cycles
              └── support_plan_statuses
              └── plan_deliverables

[アセスメントドメイン]
  welfare_recipients
      ├── service_recipient_details ── emergency_contacts
      ├── disability_statuses ── disability_details
      ├── family_of_service_recipients
      ├── welfare_services_used
      ├── medical_matters ── history_of_hospital_visits
      ├── employment_related
      └── issue_analyses

[セキュリティ・認証ドメイン]
  staffs
      ├── password_reset_tokens
      ├── password_reset_audit_logs
      ├── refresh_token_blacklist
      ├── email_change_requests
      ├── password_histories
      ├── mfa_backup_codes
      ├── mfa_audit_logs
      └── terms_agreements

[カレンダードメイン]
  offices ── office_calendar_accounts
  staffs  ── staff_calendar_accounts
  offices + welfare_recipients
      ├── calendar_events (legacy)
      └── calendar_event_series ── calendar_event_instances
              └── notification_patterns

[通知・コミュニケーションドメイン]
  offices + staffs
      ├── notices
      ├── messages ── message_recipients
      │         └── inquiry_details
      └── push_subscriptions

[監査・コンプライアンスドメイン]
  audit_logs
  office_audit_logs
  message_audit_logs
  archived_staffs
  approval_requests
  webhook_events
```

---

## テーブル一覧

| テーブル名 | モデルクラス | ファイル | 概要 |
|---|---|---|---|
| offices | Office | `models/office.py` | 事業所（テナントルート） |
| office_staffs | OfficeStaff | `models/office.py` | 事業所×スタッフ 中間テーブル |
| office_audit_logs | OfficeAuditLog | `models/office.py` | 事業所情報変更監査ログ |
| staffs | Staff | `models/staff.py` | スタッフ（認証ユーザー） |
| billings | Billing | `models/billing.py` | 事業所の課金情報 |
| webhook_events | WebhookEvent | `models/webhook_event.py` | Stripe Webhook冪等性管理 |
| welfare_recipients | WelfareRecipient | `models/welfare_recipient.py` | 受給者（サービス利用者） |
| office_welfare_recipients | OfficeWelfareRecipient | `models/welfare_recipient.py` | 事業所×受給者 中間テーブル |
| service_recipient_details | ServiceRecipientDetail | `models/welfare_recipient.py` | 受給者基本詳細情報 |
| emergency_contacts | EmergencyContact | `models/welfare_recipient.py` | 緊急連絡先 |
| disability_statuses | DisabilityStatus | `models/welfare_recipient.py` | 障害基本情報 |
| disability_details | DisabilityDetail | `models/welfare_recipient.py` | 個別の障害・手帳・年金詳細 |
| support_plan_cycles | SupportPlanCycle | `models/support_plan_cycle.py` | 個別支援計画サイクル（約6ヶ月） |
| support_plan_statuses | SupportPlanStatus | `models/support_plan_cycle.py` | 計画ステップの進捗状態 |
| plan_deliverables | PlanDeliverable | `models/support_plan_cycle.py` | 計画の成果物ファイル |
| family_of_service_recipients | FamilyOfServiceRecipients | `models/assessment.py` | 家族構成 |
| welfare_services_used | WelfareServicesUsed | `models/assessment.py` | 過去の福祉サービス利用歴 |
| medical_matters | MedicalMatters | `models/assessment.py` | 医療基本情報 |
| history_of_hospital_visits | HistoryOfHospitalVisits | `models/assessment.py` | 通院歴 |
| employment_related | EmploymentRelated | `models/assessment.py` | 就労関係情報 |
| issue_analyses | IssueAnalysis | `models/assessment.py` | 課題分析 |
| password_reset_tokens | PasswordResetToken | `models/staff.py` | パスワードリセットトークン |
| password_reset_audit_logs | PasswordResetAuditLog | `models/staff.py` | パスワードリセット監査ログ |
| refresh_token_blacklist | RefreshTokenBlacklist | `models/staff.py` | リフレッシュトークンブラックリスト |
| email_change_requests | EmailChangeRequest | `models/staff_profile.py` | メールアドレス変更リクエスト |
| password_histories | PasswordHistory | `models/staff_profile.py` | パスワード履歴 |
| mfa_backup_codes | MFABackupCode | `models/mfa.py` | MFAバックアップコード |
| mfa_audit_logs | MFAAuditLog | `models/mfa.py` | MFA操作監査ログ |
| terms_agreements | TermsAgreement | `models/terms_agreement.py` | 利用規約・PP同意履歴 |
| office_calendar_accounts | OfficeCalendarAccount | `models/calendar_account.py` | 事業所Googleカレンダー連携 |
| staff_calendar_accounts | StaffCalendarAccount | `models/calendar_account.py` | スタッフ通知設定 |
| calendar_events | CalendarEvent | `models/calendar_events.py` | カレンダーイベント（レガシー） |
| notification_patterns | NotificationPattern | `models/calendar_events.py` | 通知パターンテンプレート |
| calendar_event_series | CalendarEventSeries | `models/calendar_events.py` | カレンダーイベントシリーズ |
| calendar_event_instances | CalendarEventInstance | `models/calendar_events.py` | 個別通知イベント |
| notices | Notice | `models/notice.py` | アプリ内通知 |
| messages | Message | `models/message.py` | メッセージ本体 |
| message_recipients | MessageRecipient | `models/message.py` | メッセージ受信者（中間テーブル） |
| message_audit_logs | MessageAuditLog | `models/message.py` | メッセージ操作監査ログ |
| inquiry_details | InquiryDetail | `models/inquiry.py` | 問い合わせ詳細 |
| push_subscriptions | PushSubscription | `models/push_subscription.py` | Web Push通知購読情報 |
| audit_logs | AuditLog | `models/staff_profile.py` | 統合型監査ログ |
| archived_staffs | ArchivedStaff | `models/archived_staff.py` | スタッフアーカイブ（法定保存） |
| approval_requests | ApprovalRequest | `models/approval_request.py` | 統合型承認リクエスト |

---

## 各テーブルの設計詳細

---

### コアドメイン

#### `offices`（事業所）

**役割**: システム全体のテナントルート。全データは `office_id` でこのテーブルに紐づく。

**主要カラム**:
| カラム | 型 | 説明 |
|---|---|---|
| id | UUID | PK（`gen_random_uuid()`） |
| name | String(255) | 事業所名 |
| type | OfficeType | 事業所種別（就労移行/A型/B型） |
| is_group | Boolean | グループ事業所フラグ |
| address / phone_number / email | 連絡先情報 | |
| is_deleted / deleted_at / deleted_by | 論理削除 | 退会機能で使用 |
| created_by / last_modified_by | UUID | 変更者追跡 |

**モデル定義** (`k_back/app/models/office.py:19-86`):

```python
class Office(Base):
    """事業所"""
    __tablename__ = 'offices'

    __table_args__ = (
        # get_or_create_system_office のクエリ（name + is_deleted）を高速化
        Index('ix_offices_name_is_deleted', 'name', 'is_deleted'),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    name: Mapped[str] = mapped_column(String(255))
    type: Mapped[OfficeType] = mapped_column(SQLAlchemyEnum(OfficeType))
    is_group: Mapped[bool] = mapped_column(Boolean, default=False)

    # 論理削除（退会機能）
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False, index=True)
    deleted_at: Mapped[Optional[datetime.datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    deleted_by: Mapped[Optional[uuid.UUID]] = mapped_column(ForeignKey('staffs.id', ondelete="SET NULL"), nullable=True)

    # Office -> Billing (one-to-one)
    billing: Mapped[Optional["Billing"]] = relationship("Billing", back_populates="office", uselist=False, cascade="all, delete-orphan")
```

**設計理由**:
- `type` は `OfficeType` Enum（`transition_to_employment` / `type_A_office` / `type_B_office`）で福祉制度の事業所種別に対応
- `deleted_by` の FK は `ondelete="SET NULL"`: 削除者自身が後で削除されても Office レコードは保持
- `Billing` との `uselist=False` (1:1): 事業所1件につき課金情報は1件のみという制約をORM層で強制
- 複合インデックス `ix_offices_name_is_deleted`: `get_or_create_system_office` が `name + is_deleted` の組み合わせで検索するためのクエリ最適化

---

#### `office_staffs`（事業所×スタッフ中間テーブル）

**役割**: スタッフと事業所の多対多リレーションを管理。`is_primary` で主所属事業所を識別。

**モデル定義** (`k_back/app/models/office.py:116-138`):

```python
class OfficeStaff(Base):
    """スタッフと事業所の中間テーブル"""
    __tablename__ = 'office_staffs'
    staff_id: Mapped[uuid.UUID] = mapped_column(ForeignKey('staffs.id', ondelete="CASCADE"))
    office_id: Mapped[uuid.UUID] = mapped_column(ForeignKey('offices.id', ondelete="CASCADE"))
    is_primary: Mapped[bool] = mapped_column(Boolean, default=True)  # メインの所属か
```

**プロパティによるアクセス** (`k_back/app/models/staff.py:119-127`):

```python
@property
def office(self) -> Optional["Office"]:
    """プライマリ事業所を取得する（プロパティ）"""
    if not self.office_associations:
        return None
    # is_primary=True のものを優先、なければ最初のものを使用
    for assoc in self.office_associations:
        if assoc.is_primary:
            return assoc.office
    return self.office_associations[0].office if self.office_associations else None
```

**設計理由**:
- M:N 中間テーブルにした理由: 将来的に1スタッフが複数事業所を兼務するケース（グループ法人内の異動）に対応
- `Staff.office` プロパティで `is_primary=True` を優先取得することで、既存コードが `staff.office` とシンプルに書ける

**CRUDでの selectinload 活用** (`k_back/app/crud/crud_staff.py:17-23`):

```python
async def get(self, db: AsyncSession, *, id: uuid.UUID) -> Staff | None:
    query = select(Staff).filter(Staff.id == id).options(
        # 文字列ではなくクラス属性を直接指定（型安全）
        selectinload(Staff.office_associations).selectinload(OfficeStaff.office),
        selectinload(Staff.mfa_backup_codes)
    )
```

`selectinload` を2段ネストすることで `office_associations` → `office` まで一度に先読みし、N+1クエリを防止している。

---

#### `staffs`（スタッフ）

**役割**: システムの認証ユーザー。`role` によって権限が異なる。

**主要カラム**:
| カラム | 型 | 説明 |
|---|---|---|
| email | String(255) | ログインID（unique） |
| hashed_password | String(255) | bcryptハッシュ |
| role | StaffRole | employee / manager / owner / app_admin |
| full_name | String(255) | last_name + first_name の結合 |
| last_name_furigana / first_name_furigana | ふりがな | 五十音ソート用 |
| is_mfa_enabled / mfa_secret | MFA設定 | 暗号化TOTP |
| failed_password_attempts / is_locked | アカウントロック | ブルートフォース対策 |
| notification_preferences | JSONB | 通知チャネル設定 + 閾値 |

**notification_preferences の実際の値** (`k_back/app/models/staff.py:71-76`):

```python
notification_preferences: Mapped[dict] = mapped_column(
    JSONB,
    nullable=False,
    server_default=text(
        "'{\"in_app_notification\": true, \"email_notification\": true, "
        "\"system_notification\": false, \"email_threshold_days\": 30, "
        "\"push_threshold_days\": 10}'::jsonb"
    ),
    comment="通知チャネル設定（in_app: アプリ内通知、email: メール通知、system: Web Push通知）+ 閾値設定"
)
```

`server_default` でDB側のデフォルト値を定義することで、INSERT時にアプリ側で値を渡さなくても常に有効な通知設定が入る。JSONB を使う理由は通知設定の構造が今後変化しやすく、マイグレーション不要で柔軟にキー追加できるため。

**MFAシークレットの暗号化** (`k_back/app/models/staff.py:146-149`):

```python
def set_mfa_secret(self, secret: str) -> None:
    """MFAシークレットを暗号化して設定"""
    from app.core.security import encrypt_mfa_secret
    self.mfa_secret = encrypt_mfa_secret(secret)  # Fernet暗号化
```

モデルのメソッドとして実装し、`mfa_secret` カラムへの直接代入を禁止する設計。DB漏洩時に平文TOTPシークレットが取得されるのを防止する。

**full_name の生成** (`k_back/app/crud/crud_staff.py:38-40`):

```python
db_obj = Staff(
    ...
    full_name=f"{obj_in.last_name} {obj_in.first_name}",  # 姓名を結合して保存
)
```

`full_name` を冗長に持つ理由: 検索・表示のたびに `last_name + " " + first_name` を計算するのではなく、DB側に保持して全文検索インデックスの対象にできる。

**ロール権限マップ**:
```
employee  → 自分のデータ参照のみ（CRUD申請が必要）
manager   → 事業所内データのCRUD
owner     → 事業所全体の管理（スタッフ管理を含む）
app_admin → システム全体の管理（退会承認、課金確認等）
```

---

#### `billings`（課金情報）

**役割**: 事業所の課金状態とStripe連携情報を1:1で管理。

**主要カラム**:
| カラム | 型 | 説明 |
|---|---|---|
| office_id | UUID (unique) | 事業所との1:1 |
| stripe_customer_id / stripe_subscription_id | Stripe識別子 | |
| billing_status | BillingStatus | 課金ステータス |
| trial_start_date / trial_end_date | 無料トライアル期間 | |
| subscription_start_date / next_billing_date | 課金期間 | |
| scheduled_cancel_at | キャンセル予定日時 | |

**課金ステータス遷移**:
```
free（無料トライアル）
  ↓ トライアル中に課金登録
early_payment（トライアル中に支払い完了）
  ↓ トライアル終了
active（課金中）
  ↓ 支払い失敗
past_due（支払い遅延）
  ↓ 継続失敗
canceled（解約済み）

active → canceling（期間終了時キャンセル予約）→ canceled
```

**CRUDの record_payment メソッド** (`k_back/app/crud/crud_billing.py:138-165`):

```python
async def record_payment(self, db: AsyncSession, billing_id: UUID, ...) -> Optional[Billing]:
    """支払い記録を更新: trial期間中なら early_payment、そうでなければ active に設定"""
    billing = await self.get(db=db, id=billing_id)

    now = datetime.now(timezone.utc)
    is_trial_active = billing.trial_end_date and billing.trial_end_date > now

    # トライアル中なら early_payment、そうでなければ active
    new_status = BillingStatus.early_payment if is_trial_active else BillingStatus.active
```

この分岐がビジネスロジックの核心: 同じ「支払い完了」イベントでもトライアル中かどうかで遷移先が変わる。

**Service層でのトランザクション管理** (`k_back/app/services/billing_service.py:88-95`):

```python
# 2. DB更新（auto_commit=False で遅延commit）
await crud.billing.update_stripe_customer(
    db=db,
    billing_id=billing_id,
    stripe_customer_id=customer_id,
    auto_commit=False  # ← 重要: Stripe API成功後にまとめてcommit
)
# 3. Checkout Session作成（Stripe API）
checkout_session = stripe.checkout.Session.create(...)
# 4. ここで初めてcommit（Stripeとの整合性を保つ）
```

Stripe APIと DB更新を同一トランザクションで管理できないため、`auto_commit=False` で DB更新を保留 → Stripe API成功後にまとめて commit する設計。

**ステータス判定メソッド群** (`k_back/app/crud/crud_billing.py:171-217`):

```python
def can_access_paid_features(self, billing: Billing) -> bool:
    """有料機能にアクセスできるかを判定"""
    return billing.billing_status in [
        BillingStatus.early_payment,  # トライアル中に支払い済み
        BillingStatus.active,         # 課金中
        BillingStatus.canceling       # キャンセル予定（期間終了まで利用可能）
    ]

def requires_payment_action(self, billing: Billing) -> bool:
    """支払いアクションが必要かを判定（past_due のみ）"""
    return billing.billing_status == BillingStatus.past_due
```

ステータス判定をモデルではなく CRUD クラスのメソッドとして実装している理由: 判定ロジックが複数のステータス値を参照するため、CRUD層に集約することでロジックの重複を防ぐ。

---

### 個別支援計画ドメイン

#### `support_plan_cycles`（個別支援計画サイクル）

**役割**: 受給者1人の個別支援計画1サイクル（約6ヶ月）を管理する親テーブル。

**主要カラム**:
| カラム | 型 | 説明 |
|---|---|---|
| welfare_recipient_id | UUID | 受給者FK |
| office_id | UUID | 事業所FK（非正規化） |
| plan_cycle_start_date | date | 計画開始日 |
| final_plan_signed_date | date | 計画署名日（確定日） |
| next_renewal_deadline | date | 次回更新期限 |
| is_latest_cycle | Boolean | 最新サイクルフラグ |
| cycle_number | Integer | 第N回目の計画 |
| next_plan_start_date | Integer | 次回計画開始の猶予日数 |

**初期サイクル作成の実コード** (`k_back/app/crud/crud_welfare_recipient.py:321-355`):

```python
async def _create_initial_support_plan(self, db: AsyncSession, recipient_id: UUID, office_id: UUID) -> None:
    """受給者登録時に初期支援計画サイクルを自動生成"""
    cycle = SupportPlanCycle(
        welfare_recipient_id=recipient_id,
        office_id=office_id,
        is_latest_cycle=True,
        plan_cycle_start_date=date.today(),
        next_renewal_deadline=date.today() + timedelta(days=settings.SUPPORT_PLAN_RENEWAL_DAYS)
    )
    db.add(cycle)
    await db.flush()  # cycle.id を取得するため（commitより前にIDが必要）

    # 全ステップを一度に作成
    initial_steps = [
        SupportPlanStep.assessment,
        SupportPlanStep.draft_plan,
        SupportPlanStep.staff_meeting,
        SupportPlanStep.final_plan_signed,
        SupportPlanStep.monitoring
    ]
    for step in initial_steps:
        status = SupportPlanStatus(
            plan_cycle_id=cycle.id,  # flush後のIDを使用
            welfare_recipient_id=recipient_id,
            office_id=office_id,
            step_type=step,
            completed=False
        )
        db.add(status)
    await db.flush()
```

`flush()` → `cycle.id` 取得 → 子レコード作成という流れが典型パターン。`commit()` はサービス層で行い、CRUD層では `flush()` のみ。

**サイクル一覧クエリ** (`k_back/app/crud/crud_support_plan.py:17-30`):

```python
async def get_cycles_by_recipient(self, db: AsyncSession, *, recipient_id: UUID) -> list[SupportPlanCycle]:
    """指定された利用者のすべての支援計画サイクルを関連ステータスと共に取得"""
    stmt = (
        select(SupportPlanCycle)
        .where(SupportPlanCycle.welfare_recipient_id == recipient_id)
        .options(selectinload(SupportPlanCycle.statuses))  # N+1防止
        .order_by(SupportPlanCycle.cycle_number.desc())    # 最新サイクルが先頭
    )
```

**設計理由**:
- `office_id` を直接持つ（非正規化）: `welfare_recipient_id` → `office_welfare_recipients` 経由でも `office_id` は取れるが、`WHERE office_id = ?` のインデックス検索を最速にするために直接保持
- `is_latest_cycle` フラグ: 全サイクルをスキャンせず最新サイクルを即座に特定するための最適化

---

#### `support_plan_statuses`（計画ステップ進捗）

**役割**: 1サイクル内の各ステップの進捗を記録。

**ステップ種別** (`k_back/app/models/enums.py:19-31`):
```python
class SupportPlanStep(str, enum.Enum):
    assessment = 'assessment'           # アセスメント
    draft_plan = 'draft_plan'           # 計画案作成
    staff_meeting = 'staff_meeting'     # 担当者会議
    final_plan_signed = 'final_plan_signed'  # 計画署名（完成）
    monitoring = 'monitoring'           # モニタリング

CYCLE_STEPS = [
    SupportPlanStep.assessment,
    SupportPlanStep.draft_plan,
    SupportPlanStep.staff_meeting,
    SupportPlanStep.final_plan_signed,
    SupportPlanStep.monitoring,
]
```

`CYCLE_STEPS` リストは `_create_initial_support_plan` でステップを一括生成するときに参照される定数。

**設計理由**:
- `SupportPlanCycle` とは別テーブルにした理由: 各ステップの完了日時・完了者・期限・メモを独立して管理するため
- `completed_by` に `ForeignKey('staffs.id')` を持つ: 誰がそのステップを完了させたかを記録（責任追跡）

---

#### `plan_deliverables`（成果物）

**役割**: 計画サイクルに関連するファイル（PDFなど）を管理。

**成果物種別** (`k_back/app/models/enums.py:34-39`):
```python
class DeliverableType(str, enum.Enum):
    assessment_sheet = 'assessment_sheet'
    draft_plan_pdf = 'draft_plan_pdf'
    staff_meeting_minutes = 'staff_meeting_minutes'
    final_plan_signed_pdf = 'final_plan_signed_pdf'
    monitoring_report_pdf = 'monitoring_report_pdf'
```

**PDF一覧取得クエリ** (`k_back/app/crud/crud_support_plan.py:32-74`):

```python
query = (
    select(PlanDeliverable)
    .join(PlanDeliverable.plan_cycle)
    .join(SupportPlanCycle.welfare_recipient)
    .options(
        # 多対一: joinedload（JOINで1クエリに統合）
        joinedload(PlanDeliverable.plan_cycle).selectinload(SupportPlanCycle.welfare_recipient),
        # 多対一: joinedload（アップロード者情報）
        joinedload(PlanDeliverable.uploaded_by_staff)
    )
)
```

`joinedload` と `selectinload` を使い分けている: 多対一（N件が1件を参照）は `joinedload`、一対多（1件がN件を参照）は `selectinload` がメモリ効率的。

---

### アセスメントドメイン

アセスメントドメインは受給者の詳細情報を複数の専用テーブルに分割して管理している。

**なぜ `welfare_recipients` テーブルに全カラムを入れないのか**:
- アセスメントシートは福祉法令で定まった様式（基本情報シート・就労関係シート・課題分析シート）に従い、それぞれ独立した記入単位
- 各情報の更新頻度・更新者・バリデーションルールが異なる（就労情報は就労支援員が更新、医療情報は別担当者が更新）
- 1テーブルに入れると100カラムを超え、NULL が多くなりスキーマが読みづらくなる

**WelfareRecipient から全関連データを取得するクエリ** (`k_back/app/crud/crud_welfare_recipient.py:40-52`):

```python
async def get_with_details(self, db: AsyncSession, recipient_id: UUID) -> Optional[WelfareRecipient]:
    """全関連データを含む受給者情報を取得"""
    stmt = (
        select(WelfareRecipient)
        .where(WelfareRecipient.id == recipient_id)
        .options(
            # detail → emergency_contacts の2段selectinload
            selectinload(WelfareRecipient.detail).selectinload(ServiceRecipientDetail.emergency_contacts),
            # disability_status → details の2段selectinload
            selectinload(WelfareRecipient.disability_status).selectinload(DisabilityStatus.details),
            selectinload(WelfareRecipient.office_associations)
        )
    )
```

2段ネストの `selectinload` で階層構造を一度に取得する。`get_with_office_associations` という軽量版も別に用意し、削除・権限確認時には詳細情報不要なユースケースに対応している（無駄なデータ取得を避ける）。

**受給者登録時の関連データ一括作成** (`k_back/app/crud/crud_welfare_recipient.py:70-146`):

```python
async def create_related_data(self, db, *, welfare_recipient, registration_data, office_id) -> None:
    """受給者登録時に関連テーブルをまとめて作成"""
    # ServiceRecipientDetail → flush → id取得
    detail = ServiceRecipientDetail(welfare_recipient_id=welfare_recipient.id, ...)
    db.add(detail)
    await db.flush()  # detail.id を取得するため

    # EmergencyContact（複数）
    for contact_data in registration_data.emergency_contacts:
        emergency_contact = EmergencyContact(
            service_recipient_detail_id=detail.id,  # flush後のidを使用
            ...
        )
        db.add(emergency_contact)

    # DisabilityStatus → flush → id取得
    disability_status = DisabilityStatus(welfare_recipient_id=welfare_recipient.id, ...)
    db.add(disability_status)
    await db.flush()

    # DisabilityDetail（複数）
    for detail_data in registration_data.disability_details:
        disability_detail = DisabilityDetail(
            disability_status_id=disability_status.id,  # flush後のidを使用
            ...
        )
        db.add(disability_detail)

    # OfficeWelfareRecipient（事業所との紐付け）
    office_association = OfficeWelfareRecipient(
        welfare_recipient_id=welfare_recipient.id,
        office_id=office_id
    )
    db.add(office_association)
```

複数テーブルへの INSERT を1トランザクションでまとめる典型パターン。`flush()` でIDを確定させてから子テーブルに使うことで整合性を保つ。

---

#### `disability_statuses` / `disability_details`

```
disability_statuses (1:1 with welfare_recipient)
  └── disability_details (1:N) ← 手帳・年金ごとの詳細
```

**なぜ2階層か**: 1人が複数の障害手帳（身体・知的・精神）を持つケースがある。各手帳の等級・申請状態を別々に管理するため `disability_details` に分割。

**DisabilityCategory Enum** (`k_back/app/models/enums.py:135-141`):
```python
class DisabilityCategory(str, enum.Enum):
    physical_handbook = "physical_handbook"          # 身体障害者手帳
    intellectual_handbook = "intellectual_handbook"  # 療育手帳
    mental_health_handbook = "mental_health_handbook"  # 精神障害者保健福祉手帳
    disability_basic_pension = "disability_basic_pension"  # 障害基礎年金
    other_disability_pension = "other_disability_pension"  # その他障害年金
    public_assistance = "public_assistance"           # 生活保護
```

---

### セキュリティ・認証ドメイン

認証セキュリティを強化するために多数の補助テーブルを設けている。

#### `password_reset_tokens`

**設計ポイントのコード** (`k_back/app/models/staff.py:242-303`):

```python
class PasswordResetToken(Base):
    """
    パスワードリセットトークン（トークンはSHA-256でハッシュ化して保存）

    セキュリティ:
    - トークンは平文で保存せず、SHA-256でハッシュ化
    - DB侵害時でもトークンの漏洩を防止
    - 有効期限は30分（セキュリティレビュー対応）
    - 一度使用されたら無効化（楽観的ロックで実装）
    """
    token_hash: Mapped[str] = mapped_column(
        String(64),   # SHA-256ハッシュは64文字の16進数
        unique=True,
        index=True,
        nullable=False
    )
    # 楽観的ロック用バージョン番号（トークン二重使用防止）
    version: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    # リクエスト元情報（監査ログ用）
    request_ip: Mapped[Optional[str]] = mapped_column(String(45), nullable=True)   # IPv6対応
    request_user_agent: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
```

- `token_hash` を `unique=True` にしつつ `version` で楽観的ロック: 同一トークンの並行使用（二重パスワードリセット）を DB レベルで防止
- `String(45)` は IPv6 の最大長（39文字）+ 余裕

---

#### `refresh_token_blacklist`

**設計コード** (`k_back/app/models/staff.py:368-416`):

```python
class RefreshTokenBlacklist(Base):
    """
    Option 2: パスワード変更時に既存のリフレッシュトークンを無効化
    OWASP A07:2021 Identification and Authentication Failures 対策
    """
    jti: Mapped[str] = mapped_column(
        String(64),   # JWT ID (UUID)
        unique=True,
        index=True,
        nullable=False
    )
    reason: Mapped[str] = mapped_column(String(100), default="password_changed", nullable=False)
    expires_at: Mapped[datetime.datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
```

`expires_at` でトークンの本来の有効期限を保持する理由: 期限切れのブラックリストエントリをバッチで定期削除するため。

---

#### `mfa_backup_codes`

**MFA有効化の実コード** (`k_back/app/models/staff.py:180-196`):

```python
async def enable_mfa(self, db: AsyncSession, secret: str, recovery_codes: List[str]) -> None:
    """MFAを有効化"""
    self.set_mfa_secret(secret)  # Fernet暗号化して保存
    self.is_mfa_enabled = True

    from app.core.security import hash_recovery_code
    for code in recovery_codes:
        backup_code = MFABackupCode(
            staff_id=self.id,
            code_hash=hash_recovery_code(code),  # bcryptハッシュ
            is_used=False
        )
        db.add(backup_code)
```

**MFA無効化の実コード** (`k_back/app/models/staff.py:197-207`):

```python
async def disable_mfa(self, db: AsyncSession) -> None:
    """MFAを無効化"""
    self.is_mfa_enabled = False
    self.is_mfa_verified_by_user = False
    self.mfa_secret = None
    self.mfa_backup_codes_used = 0

    # バックアップコードを明示的なDELETEクエリで削除（cascade削除を使わない）
    stmt = delete(MFABackupCode).where(MFABackupCode.staff_id == self.id)
    await db.execute(stmt)
```

`cascade="all, delete-orphan"` でも削除できるが、明示的な DELETE クエリを使う理由: ORM の cascade は関連オブジェクトを先にロードしてから削除するのでN+1になる可能性がある。直接 DELETE は1クエリで完結する。

---

#### `archived_staffs`（スタッフアーカイブ）

**設計ポイントのコード** (`k_back/app/crud/crud_archived_staff.py:35-117`):

```python
async def create_from_staff(self, db: AsyncSession, *, staff: Staff, reason: str, ...) -> ArchivedStaff:
    """Staffレコードからアーカイブを作成（個人識別情報を匿名化）"""
    # SHA-256の先頭9文字で匿名化ID生成
    hash_hex = hashlib.sha256(str(staff.id).encode()).hexdigest()
    anon_id = hash_hex[:9].upper()

    # 事業所情報はスナップショットとして保存（FK参照なし）
    office_name = primary_assoc.office.name  # 削除時点の名前を記録

    # 法定保存期限 = terminated_at + 5年
    retention_until = ArchivedStaff.calculate_retention_until(terminated_at, years=5)

    archived_staff = ArchivedStaff(
        original_staff_id=staff.id,                          # FK制約なし（参照整合性なし）
        anonymized_full_name=f"スタッフ-{anon_id}",          # 匿名化
        anonymized_email=f"archived-{anon_id}@deleted.local", # 匿名化
        office_name=office_name,                              # スナップショット
        legal_retention_until=retention_until,
        metadata_={
            "deleted_by_staff_id": str(deleted_by),
            "original_email_domain": staff.email.split("@")[1],  # ドメインのみ保持
            "mfa_was_enabled": staff.is_mfa_enabled,
        }
    )
```

**法定保存期限切れレコードの削除** (`k_back/app/crud/crud_archived_staff.py:216-270`):

```python
async def get_expired_archives(self, db: AsyncSession, ...) -> List[ArchivedStaff]:
    """法定保存期限が過ぎたアーカイブを取得"""
    now = datetime.now(timezone.utc)
    stmt = select(ArchivedStaff).where(
        ArchivedStaff.legal_retention_until <= now  # 期限切れのみ
    )
```

`legal_retention_until` インデックスにより、バッチジョブでの期限切れスキャンが高速。

---

### カレンダードメイン

#### `office_calendar_accounts`（事業所カレンダー連携）

**サービスアカウントキーの暗号化** (`k_back/app/models/calendar_account.py:101-125`):

```python
def encrypt_service_account_key(self, key_data: Optional[str]) -> None:
    """サービスアカウントキーを Fernet 暗号化して保存"""
    encryption_key = os.getenv("CALENDAR_ENCRYPTION_KEY")
    fernet = Fernet(encryption_key.encode())
    encrypted_key = fernet.encrypt(key_data.encode())
    self.service_account_key = encrypted_key.decode()

def decrypt_service_account_key(self) -> Optional[str]:
    """暗号化されたサービスアカウントキーを復号化"""
    fernet = Fernet(encryption_key.encode())
    decrypted_key = fernet.decrypt(self.service_account_key.encode())
    return decrypted_key.decode()
```

環境変数 `CALENDAR_ENCRYPTION_KEY` でキーを管理し、Google サービスアカウントの秘密鍵をDBに暗号化して保存。

---

#### `staff_calendar_accounts`（スタッフ通知設定）

**通知タイミング設定の実コード** (`k_back/app/models/calendar_account.py:232-243`):

```python
def get_reminder_days(self) -> list[int]:
    """設定に応じた通知日数リストを返す"""
    if self.notification_timing == NotificationTiming.early:
        return [30, 14, 7, 3, 1]   # 早め
    elif self.notification_timing == NotificationTiming.standard:
        return [30, 7, 1]          # 標準
    elif self.notification_timing == NotificationTiming.minimal:
        return [7, 1]              # 最小限
    elif self.notification_timing == NotificationTiming.custom and self.custom_reminder_days:
        return [int(day.strip()) for day in self.custom_reminder_days.split(',')]
    else:
        return [7, 1]  # デフォルト
```

通知タイミングパターンはモデルのメソッドとして実装することで、APIレイヤーやバッチ処理から共通で利用できる。

---

#### カレンダーイベント管理（シリーズ方式）

```
notification_patterns （通知パターンテンプレート）
  └── calendar_event_series （1期限に対するシリーズ）
          └── calendar_event_instances （個別通知イベント、Googleカレンダーと1:1）
```

**なぜ Series/Instance の2階層か**:
- 1つの更新期限に対して「30日前・7日前・1日前」のように複数のリマインダーが発生する
- 期限日が変更された場合、Series の `base_deadline_date` を変更するだけで配下のInstanceを一括管理できる
- GoogleカレンダーのイベントID（`google_event_id`）はInstance側に持ち、実際のGoogle APIコール単位と対応

**排他参照制約のコード** (`k_back/app/models/calendar_events.py:131-161`):

```python
__table_args__ = (
    # cycle_id と status_id のどちらか一方のみ設定可能（DB制約）
    CheckConstraint(
        """
        (support_plan_cycle_id IS NOT NULL AND support_plan_status_id IS NULL) OR
        (support_plan_cycle_id IS NULL AND support_plan_status_id IS NOT NULL)
        """,
        name="chk_calendar_events_ref_exclusive"
    ),
    # 同じサイクルIDとイベントタイプの組み合わせでは1つのみ許可（部分ユニークインデックス）
    Index(
        "idx_calendar_events_cycle_type_unique",
        "support_plan_cycle_id", "event_type",
        unique=True,
        postgresql_where="support_plan_cycle_id IS NOT NULL AND (sync_status = 'pending' OR sync_status = 'synced')"
    ),
)
```

PostgreSQL の部分インデックス（`postgresql_where`）を使うことで、`cancelled` 状態のイベントを一意制約から除外しながら、有効なイベントのみ重複防止できる。

---

### 通知・コミュニケーションドメイン

#### `messages` / `message_recipients`

**メッセージ作成の実コード** (`k_back/app/crud/crud_message.py:22-78`):

```python
async def create_personal_message(self, db: AsyncSession, *, obj_in: Dict[str, Any]) -> Message:
    """個別メッセージを作成（1トランザクションでメッセージ本体と受信者を作成）"""
    # 受信者IDの重複を除去
    recipient_ids = list(set(obj_in.get("recipient_ids", [])))

    # メッセージ本体を作成
    message = Message(
        sender_staff_id=obj_in["sender_staff_id"],
        office_id=obj_in["office_id"],
        message_type=obj_in.get("message_type", MessageType.personal),
        ...
    )
    db.add(message)
    await db.flush()  # message.id を取得するため

    # 受信者レコードをバルクインサート（1件ずつではなくadd_allで効率化）
    recipients = [
        MessageRecipient(
            message_id=message.id,
            recipient_staff_id=recipient_id,
            is_read=False,
            is_archived=False
        )
        for recipient_id in recipient_ids
    ]
    db.add_all(recipients)  # バルクインサート
    await db.flush()
```

`db.add_all(recipients)` でN件のレコードをバルクインサート。`set()` で重複IDを除去し、DB の `UniqueConstraint('message_id', 'recipient_staff_id')` との二重防御にしている。

**MessageRecipient の中間テーブル制約** (`k_back/app/models/message.py:184-191`):

```python
__table_args__ = (
    # 同じメッセージに同じ受信者を複数回追加できない
    UniqueConstraint('message_id', 'recipient_staff_id', name='uq_message_recipient'),
    # 受信者の未読メッセージを効率的に取得（受信箱クエリ最適化）
    Index('ix_message_recipients_recipient_read', 'recipient_staff_id', 'is_read'),
    # メッセージの受信者一覧を効率的に取得
    Index('ix_message_recipients_message', 'message_id'),
)
```

**メッセージタイプ** (`k_back/app/models/enums.py:256-263`):
```python
class MessageType(str, enum.Enum):
    personal = 'personal'           # 個別メッセージ
    announcement = 'announcement'   # 一斉通知（お知らせ）
    system = 'system'               # システム通知
    inquiry = 'inquiry'             # 問い合わせ
    inquiry_reply = 'inquiry_reply' # 問い合わせ返信
```

---

#### `inquiry_details`（問い合わせ詳細）

**なぜ Message の拡張として設計したか** (`k_back/app/models/inquiry.py:23-35`):

```python
class InquiryDetail(Base):
    """
    問い合わせ詳細（Messageテーブルと1:1で関連）

    - sender_name, sender_email: 未ログインユーザーからの問い合わせに使用
    - status: 問い合わせの対応状態（new/open/in_progress/answered/closed/spam）
    - priority: 優先度（low/normal/high）
    - assigned_staff_id: 担当者
    - delivery_log: メール送信履歴（JSON形式）
    """
    message_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey('messages.id', ondelete="CASCADE"),
        nullable=False,
        unique=True,  # 1:1 を保証
        index=True
    )
    delivery_log: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)  # 送信履歴
```

問い合わせの「本文・タイトル」は Message と共通構造なので `Message` に乗せ、問い合わせ固有の管理情報（ステータス・担当者・優先度）のみを `InquiryDetail` に分離。

---

### 監査・コンプライアンスドメイン

#### `audit_logs`（統合型監査ログ）

**保持期間ポリシーのコード** (`k_back/app/crud/crud_audit_log.py:18-62`):

```python
# アクション別の保持期間設定（法的要件に基づく）
RETENTION_POLICIES = {
    "legal": {
        "days": 1825,  # 5年（法的要件）
        "actions": [
            "withdrawal.approved",   # 退会承認
            "withdrawal.executed",   # 退会実行
            "staff.deleted",         # スタッフ削除
            "office.deleted",        # 事業所削除
            "terms.agreed",          # 利用規約同意
        ]
    },
    "important": {
        "days": 1095,  # 3年
        "actions": ["staff.created", "staff.role_changed", "office.created", ...]
    },
    "standard": {
        "days": 365,   # 1年
        "actions": ["staff.updated", "staff.password_changed", "profile.updated", ...]
    },
    "short_term": {
        "days": 90,    # 90日
        "actions": ["staff.login", "staff.logout", "mfa.enabled", "mfa.disabled"]
    },
}
```

単純に全レコードを同じ期間保持するのではなく、アクション種別ごとに法的要件に合わせた保持期間を設定。ログの肥大化を防ぎつつコンプライアンスを満たす設計。

**AuditLog モデルの設計** (`k_back/app/models/staff_profile.py:37-114`):

```python
class AuditLog(Base):
    action: Mapped[str] = mapped_column(
        String(100), nullable=False, index=True,
        comment="アクション種別: staff.deleted, office.updated, withdrawal.approved 等"
    )
    target_type: Mapped[Optional[str]] = mapped_column(
        String(50), nullable=True, index=True,
        comment="対象リソースタイプ: staff, office, withdrawal_request 等"
    )
    target_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), nullable=True,
        comment="対象リソースのID"
    )
    office_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        ForeignKey('offices.id', ondelete='SET NULL'), nullable=True, index=True,
        comment="事務所ID（横断検索用、app_adminはNULL可）"
    )
    details: Mapped[Optional[dict]] = mapped_column(
        JSONB, nullable=True,
        comment="変更内容（old_values, new_values等のJSON形式）"
    )
```

`office_id` を持たせる理由: app_admin が特定事業所の操作履歴を横断検索するため。`target_type` + `target_id` で任意のリソースの変更履歴を検索できる汎用設計。

---

#### `approval_requests`（統合型承認リクエスト）

**JSONB request_data の設計** (`k_back/app/models/approval_request.py:31-34`):

```python
# request_data の構造（resource_type ごとに異なる）:
# role_change:    {"from_role": "employee", "requested_role": "manager", "request_notes": "..."}
# employee_action: {"resource_type": "...", "action_type": "...", "resource_id": "..."}
# withdrawal:     {"withdrawal_type": "staff|office", "reason": "...", "affected_staff_ids": [...]}
request_data: Mapped[Optional[dict]] = mapped_column(JSONB, nullable=True)
```

**退会リクエスト作成の実コード** (`k_back/app/services/withdrawal_service.py:38-79`):

```python
async def create_staff_withdrawal_request(self, db, *, requester_staff_id, office_id, target_staff_id, ...) -> ApprovalRequest:
    """スタッフ退会リクエストを作成"""
    # 重複チェック（同一スタッフへの重複リクエストを防止）
    has_pending = await crud.approval_request.has_pending_withdrawal(
        db, office_id=office_id, withdrawal_type="staff", target_staff_id=target_staff_id
    )
    if has_pending:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="このスタッフに対する退会リクエストは既に承認待ちです"
        )
    # リクエスト作成（resource_type="withdrawal" で統合テーブルに保存）
```

**なぜ統合するか**: 旧来は `role_change_requests` / `employee_action_requests` が別テーブルだったが、承認フロー（申請→審査→承認/却下）の処理ロジックが共通のため統合。新しい承認フローを追加する際も `resource_type` Enum の拡張のみで対応可能。

---

#### `webhook_events`（Webhook冪等性管理）

**WebhookEvent モデル** (`k_back/app/models/webhook_event.py:15-26`):

```python
class WebhookEvent(Base):
    """
    Stripe Webhook 冪等性管理テーブル

    使用方法:
    1. Webhook受信時に event_id の存在確認
    2. 既に存在する場合は200 OKを返して処理スキップ
    3. 新規イベントの場合は処理を実行してテーブルに記録
    """
    event_id: Mapped[str] = mapped_column(
        String(255), unique=True, nullable=False, index=True,
        comment="Stripe Event ID (例: evt_1234567890)"
    )
    event_type: Mapped[str] = mapped_column(
        String(100), nullable=False, index=True,
        comment="イベントタイプ (例: invoice.payment_succeeded)"
    )
    payload: Mapped[Optional[dict]] = mapped_column(JSONB, nullable=True, comment="Webhookペイロード（デバッグ用）")
```

`event_id` を `unique=True` にすることで、同一イベントの INSERT を DB レベルで排除。`payload` を JSONB で保持する理由: Stripe のペイロード構造は変わることがあるため、スキーマレスで保持し後からデバッグ・再処理に使用できる。

---

## 共通設計ルール

### 外部キー設定方針

| ケース | ondelete | 実例 |
|---|---|---|
| 親が削除されたら子も不要 | `CASCADE` | `OfficeStaff.staff_id → staffs.id` |
| 親が削除されてもログ・履歴は残したい | `SET NULL` | `AuditLog.staff_id → staffs.id` |
| 参照整合性なし（スナップショット） | なし | `ArchivedStaff.original_staff_id` |

**実コードでの使い分け** (`k_back/app/models/office.py:40-64`):

```python
# スタッフが削除されても Office は残す → SET NULL
deleted_by: Mapped[Optional[uuid.UUID]] = mapped_column(
    ForeignKey('staffs.id', ondelete="SET NULL"), nullable=True
)
# 事業所が削除されたらスタッフ所属情報も不要 → CASCADE
staff_id: Mapped[uuid.UUID] = mapped_column(ForeignKey('staffs.id', ondelete="CASCADE"))
```

### flush/commit/refresh パターン

CRUD層とService層での役割分担:

```python
# CRUD層: flush のみ（IDが必要な場合）
db.add(obj)
await db.flush()      # ID確定・トランザクション内に留める
await db.refresh(obj) # 最新状態を取得

# Service層: commit（複数CRUD操作後）
await crud.billing.update_stripe_customer(db, ..., auto_commit=False)
await crud.billing.update_stripe_subscription(db, ..., auto_commit=False)
await db.commit()  # 全操作をまとめてcommit

# API層: commit 禁止（Service層に委譲）
```

### タイムスタンプ

全テーブルに `created_at` / `updated_at` を持つ。

```python
created_at: Mapped[datetime.datetime] = mapped_column(
    DateTime(timezone=True), server_default=func.now()
)
updated_at: Mapped[datetime.datetime] = mapped_column(
    DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
)
```

`timezone=True` でUTC保存。`server_default=func.now()` でDB側がタイムスタンプを生成し、アプリ側のタイムゾーン設定ミスを防止。

### インデックス設計方針

```python
# 外部キーには必ずインデックス
office_id = mapped_column(ForeignKey('offices.id'), index=True)

# 検索頻度の高いステータス系
is_deleted = mapped_column(Boolean, index=True)
billing_status = mapped_column(Enum(BillingStatus), index=True)

# 実際のクエリパターンに合わせた複合インデックス
Index('ix_offices_name_is_deleted', 'name', 'is_deleted')

# 条件付き部分インデックス（インデックスサイズ削減）
Index(
    "idx_notification_patterns_active",
    "is_active",
    postgresql_where="is_active = TRUE"  # 有効なパターンのみ
)
```

### Enum 管理

全 Enum は `k_back/app/models/enums.py` に集約管理:

```python
# str を継承 → JSON シリアライズ可能、比較演算子も使用可能
class BillingStatus(str, enum.Enum):
    free = 'free'
    active = 'active'
    ...

# 使用例（文字列比較と同等）
if billing.billing_status == BillingStatus.active:
    ...
# または
if billing.billing_status == 'active':  # これも動く（str継承のため）
    ...
```

値は英語スネークケース（コードとの親和性）、表示名は日本語（`crud_billing.get_status_display_message()` でUI層で変換）。
