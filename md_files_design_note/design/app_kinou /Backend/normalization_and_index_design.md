# 個別支援計画 DB 正規化・インデックス設計書

**対象**: keikakun_app バックエンド（FastAPI + SQLAlchemy + PostgreSQL）  
**作成日**: 2026-04-16  
**関連ファイル**: `k_back/app/models/support_plan_cycle.py`, `k_back/app/models/welfare_recipient.py`, `k_back/app/models/assessment.py`

---

## 目次

1. [正規化の設計方針](#1-正規化の設計方針)
2. [個別支援計画ドメインの正規化レベル](#2-個別支援計画ドメインの正規化レベル)
3. [意図的な非正規化（冗長カラム）](#3-意図的な非正規化冗長カラム)
4. [インデックス設計](#4-インデックス設計)
5. [制約設計](#5-制約設計)
6. [設計のトレードオフまとめ](#6-設計のトレードオフまとめ)

---

## 1. 正規化の設計方針

### 基本方針: 「第3正規形を基本とし、検索・更新パターンに応じて選択的に非正規化する」

純粋な正規化（全カラムを1テーブルに詰め込まない）を基本としつつ、以下の2軸でテーブル分割の粒度を決定している。

| 分割する理由 | 分割しない理由 |
|---|---|
| 更新頻度・更新者が異なる | テーブルをまたぐJOINのコスト増大 |
| 法令様式が独立した記入単位として定まっている | 1:1の分割はクエリを複雑にする |
| 1:N が発生する（複数件持てる） | カラム数が少なく1テーブルで済む |
| NULLカラムが多くなる（スキーマが読みづらい） | |

---

## 2. 個別支援計画ドメインの正規化レベル

### 2-1. テーブル全体構造（ER図相当）

```
welfare_recipients  ← 受給者エンティティのルート
  │  （基本属性のみ: 氏名・ふりがな・生年月日・性別）
  │
  ├── [1:1] service_recipient_details    ← 基本詳細情報（住所・交通手段・電話）
  │       └── [1:N] emergency_contacts   ← 緊急連絡先（複数）
  │
  ├── [1:1] disability_statuses          ← 障害基本情報
  │       └── [1:N] disability_details   ← 手帳・年金ごとの詳細（複数）
  │
  ├── [1:N] family_of_service_recipients ← 家族構成（複数）
  ├── [1:N] welfare_services_used        ← 過去サービス利用歴（複数）
  ├── [1:1] medical_matters              ← 医療基本情報
  │       └── [1:N] history_of_hospital_visits ← 通院歴（複数）
  ├── [1:1] employment_related           ← 就労関係情報
  ├── [1:1] issue_analyses               ← 課題分析
  │
  └── [1:N] support_plan_cycles          ← 個別支援計画サイクル（約6ヶ月ごと）
          ├── [1:N] support_plan_statuses ← ステップ別進捗
          └── [1:N] plan_deliverables     ← 成果物ファイル（PDF等）
```

---

### 2-2. welfare_recipients（受給者）

**正規化レベル: 第3正規形（3NF）**

```python
# k_back/app/models/welfare_recipient.py:35-47
class WelfareRecipient(Base):
    __tablename__ = "welfare_recipients"
    id: UUID          # PK
    first_name: str
    last_name: str
    first_name_furigana: str
    last_name_furigana: str
    birth_day: date
    gender: GenderType
```

**カラムを絞った理由**:  
受給者は「誰か」を識別する最小属性のみを持つ。住所・医療・就労などの詳細情報は更新頻度・更新者・バリデーションルールが異なるため別テーブルに分離した。

`full_name` を持たない設計（`staffs` テーブルは `full_name` を持つのと対比）:  
受給者の氏名は検索対象だが、`staffs` と異なりシステム内の認証・認可に使われないため計算プロパティで都度生成する。

```python
@property
def full_name(self) -> str:
    return f"{self.last_name} {self.first_name}"
```

---

### 2-3. service_recipient_details（受給者詳細）/ emergency_contacts（緊急連絡先）

**正規化レベル: 第3正規形（受給者との1:1分割）**

```python
# k_back/app/models/welfare_recipient.py:91-108
class ServiceRecipientDetail(Base):
    __tablename__ = 'service_recipient_details'
    id: int                      # PK（Integer連番、外部非公開）
    welfare_recipient_id: UUID   # FK unique=True → 1:1を強制
    address: str
    form_of_residence: FormOfResidence
    means_of_transportation: MeansOfTransportation
    tel: str
```

**`welfare_recipients` から分離した理由**:
- 法令様式「基本情報シート」の記入単位が独立している
- 管理担当者（支援員）が更新する情報と受給者識別情報（システム管理者が登録）を分離
- 将来的に複数住所（主居所・緊急時居所）に拡張しやすくする

**PKをIntegerにした理由**:  
外部に公開されないサブテーブルのため、UUIDによるランダム生成は不要。シーケンシャルなIntegerで十分かつ結合コストが低い。

`emergency_contacts` は `service_recipient_details` から1:N で分離:  
緊急連絡先は複数人登録するユースケースが確定しているため別テーブル。`priority` カラムで表示順を管理する。

---

### 2-4. disability_statuses / disability_details（障害情報）

**正規化レベル: 第3正規形（2階層分割）**

```
disability_statuses (1:1 with welfare_recipients)
  ├── disability_or_disease_name  ← 障害・疾病名（全体共通）
  ├── livelihood_protection       ← 生活保護区分
  └── [1:N] disability_details
          ├── category            ← 手帳種別（身体/知的/精神/年金）
          ├── grade_or_level      ← 等級・程度
          └── application_status  ← 申請状況
```

**2階層に分けた理由**:  
1人が複数の障害者手帳（身体障害・知的障害・精神障害）や年金を同時に保持するケースがある。手帳ごとの等級・申請状態を `disability_details` に分割することで、手帳の追加・更新を独立して行える。

**DisabilityCategory Enum** (`k_back/app/models/enums.py`):

```python
class DisabilityCategory(str, enum.Enum):
    physical_handbook = "physical_handbook"          # 身体障害者手帳
    intellectual_handbook = "intellectual_handbook"  # 療育手帳
    mental_health_handbook = "mental_health_handbook"
    disability_basic_pension = "disability_basic_pension"
    other_disability_pension = "other_disability_pension"
    public_assistance = "public_assistance"
```

---

### 2-5. アセスメント情報（family / welfare_services / medical / employment / issue）

**正規化レベル: 第3正規形（テーブル分割による業務単位での管理）**

| テーブル | リレーション | 分割理由 |
|---|---|---|
| `family_of_service_recipients` | welfare_recipient 1:N | 家族は複数登録 |
| `welfare_services_used` | welfare_recipient 1:N | サービス利用歴は複数件 |
| `medical_matters` | welfare_recipient 1:1 | 医療情報専任者が更新 |
| `history_of_hospital_visits` | medical_matters 1:N | 通院先は複数 |
| `employment_related` | welfare_recipient 1:1 | 就労支援員が更新 |
| `issue_analyses` | welfare_recipient 1:1 | 課題分析担当者が更新 |

**1テーブルに入れなかった理由（共通）**:

> アセスメントシートは福祉法令で定まった様式（基本情報シート・就労関係シート・課題分析シート）に従い、それぞれ独立した記入単位である。各情報の更新者・更新頻度・バリデーションルールが異なり、`welfare_recipients` に全カラムを入れると100カラムを超え、NULL比率が高くなりスキーマが読みづらくなる。

`employment_related` と `issue_analyses` には `created_by_staff_id` FK を持つ:  
誰がその情報を入力したかを記録するため（責任追跡）。他のアセスメントテーブルは記録なし（記録が不要な業務要件）。

---

### 2-6. support_plan_cycles（個別支援計画サイクル）

**正規化レベル: 第3正規形 + 意図的な非正規化**

```python
# k_back/app/models/support_plan_cycle.py:27-48
class SupportPlanCycle(Base):
    __tablename__ = 'support_plan_cycles'
    id: int                       # PK（Integer連番）
    welfare_recipient_id: UUID    # FK
    office_id: UUID               # FK（非正規化カラム ← 後述）
    plan_cycle_start_date: date
    final_plan_signed_date: date
    next_renewal_deadline: date
    is_latest_cycle: bool         # 最新サイクルフラグ（非正規化 ← 後述）
    cycle_number: int             # 第N回目
    next_plan_start_date: int     # 次回開始の猶予日数
```

**PKをIntegerにした理由**:  
`support_plan_cycles` は外部APIに直接公開されないサブテーブル。URLパスには `welfare_recipient_id`（UUID）が先に現れ、サイクルIDを直接推測される危険性が低い。シーケンシャルIntegerでJOINコストを下げる。

---

### 2-7. support_plan_statuses（ステップ進捗）

**正規化レベル: 第3正規形 + 非正規化**

```python
# k_back/app/models/support_plan_cycle.py:58-90
class SupportPlanStatus(Base):
    __tablename__ = 'support_plan_statuses'
    id: int
    plan_cycle_id: int            # FK → support_plan_cycles
    welfare_recipient_id: UUID    # FK（非正規化 ← 後述）
    office_id: UUID               # FK（非正規化 ← 後述）
    step_type: SupportPlanStep    # assessment / draft_plan / ... / monitoring
    is_latest_status: bool
    completed: bool
    completed_at: datetime
    completed_by: UUID            # FK → staffs（責任追跡）
    due_date: date
    notes: str
```

**`SupportPlanCycle` から分離した理由**:  
各ステップの完了日時・完了者・期限・メモを独立して管理する。1サイクルに必ず5ステップ（assessment → draft_plan → staff_meeting → final_plan_signed → monitoring）が対応し、各ステップが独立した更新単位になる。

---

### 2-8. plan_deliverables（成果物）

```python
# k_back/app/models/support_plan_cycle.py:93-107
class PlanDeliverable(Base):
    __tablename__ = 'plan_deliverables'
    id: int
    plan_cycle_id: int            # FK → support_plan_cycles
    deliverable_type: DeliverableType
    file_path: str                # GCS等のパス
    original_filename: str
    uploaded_by: UUID             # FK → staffs
    uploaded_at: datetime
```

**`support_plan_cycles` から分離した理由**:  
1サイクルに複数の成果物（アセスメントシート・計画案PDF・議事録・最終計画PDF・モニタリング報告書）が対応し、各ファイルが独立した追加・置き換えの単位になる。

---

## 3. 意図的な非正規化（冗長カラム）

### 3-1. `support_plan_cycles.office_id`（冗長保持）

**状況**: `support_plan_cycles` は `welfare_recipient_id` を持つ。`office_id` は `welfare_recipient_id → office_welfare_recipients → office_id` のJOINで取得できる（第3正規形的には不要）。

**あえて `office_id` を直接持った理由**:

```python
# 事業所フィルタークエリ（k_back/app/crud/crud_support_plan.py:103-108）
query = query.join(
    OfficeWelfareRecipient,
    WelfareRecipient.id == OfficeWelfareRecipient.welfare_recipient_id
).where(OfficeWelfareRecipient.office_id == office_id)
```

正規化に従うと上記のような余分なJOINが常に必要になる。マルチテナント分離のフィルター（`WHERE office_id = ?`）は全クエリに適用される最重要条件のため、`office_id` を直接持たせることでこのJOINを省いてインデックス検索を最速にする。

### 3-2. `support_plan_statuses.welfare_recipient_id` / `office_id`（冗長保持）

**状況**: `plan_cycle_id → support_plan_cycles.welfare_recipient_id` で辿れるが、`support_plan_statuses` に直接保持している。

**理由**: 締切通知バッチ（`k_back/app/tasks/deadline_notification.py`）が `office_id` で直接フィルタリングするためのクエリ最適化。`plan_cycle_id` 経由のJOINを1段省く。

### 3-3. `staffs.full_name`（計算結果の冗長保持）

**状況**: `last_name + " " + first_name` は計算で求まる。`welfare_recipients` は計算プロパティのみで `full_name` カラムを持たない。

**`staffs` だけが `full_name` カラムを持つ理由**:

```python
# k_back/app/crud/crud_staff.py:38-40
db_obj = Staff(
    ...
    full_name=f"{obj_in.last_name} {obj_in.first_name}",  # 姓名を結合して保存
)
```

スタッフは氏名で全文検索（`ilike`）の対象になり、インデックス対象とするためDBに保持する。受給者の氏名検索は `last_name`・`first_name` を `concat` して行うため、カラムは不要。

### 3-4. `is_latest_cycle` / `is_latest_status` フラグ（集約結果の冗長保持）

**状況**: 「最新かどうか」は `MAX(cycle_number)` や `ORDER BY created_at DESC LIMIT 1` で求まる。

**あえてフラグを持った理由**:  
締切管理・ダッシュボード表示で「最新サイクルのみ」を即時取得するユースケースが頻繁にある。集約クエリを毎回実行するのではなく `WHERE is_latest_cycle = TRUE` で直接フィルタリングすることで、サイクル数が増えてもスキャン対象を絞り込める。

**トレードオフ**: 新サイクル作成時に旧サイクルの `is_latest_cycle = FALSE` 更新が必要（更新漏れのリスク）。CRUD層 `_create_initial_support_plan` でこの更新を一括で行う。

---

## 4. インデックス設計

### 4-1. 設計方針

```
1. 外部キー（FK）には原則インデックスを付与（JOIN・DELETE時のスキャン回避）
2. WHERE句で頻繁に使うフィルタカラムに単体インデックス
3. 複合インデックスは実際のクエリパターンに合わせて追加
4. 部分インデックス（postgresql_where）でインデックスサイズを削減
5. UNIQUE制約は暗黙的にインデックスを生成（明示不要）
```

---

### 4-2. 個別支援計画ドメインのインデックス一覧

#### `welfare_recipients`

| カラム | インデックス種別 | 理由 |
|---|---|---|
| `id` | PK（自動） | |
| `is_test_data` | `index=True` | テストデータ一括削除バッチ |

**注**: `first_name`, `last_name`, `first_name_furigana`, `last_name_furigana` に単体インデックスなし。受給者検索は `concat(last_name, first_name).ilike(...)` で行うため、単体カラムインデックスより関数インデックスが有効だが現時点では未設定（ilike検索は full scan）。

---

#### `office_welfare_recipients`（受給者×事業所の中間テーブル）

| カラム | インデックス種別 | 理由 |
|---|---|---|
| `id` | PK（UUID、自動） | |
| `welfare_recipient_id` | FK（インデックスなし） | |
| `office_id` | FK（インデックスなし） | |
| `is_test_data` | `index=True` | テストデータ削除 |

**注意点**: `office_id` で事業所の受給者一覧を取得するクエリ（`crud_support_plan.py:103-108`）が頻繁に実行されるが、`office_id` に明示的なインデックスが設定されていない。PKがUUIDのため行数が増えるとスキャンコストが上がる可能性がある。

---

#### `service_recipient_details`

| カラム | インデックス種別 | 理由 |
|---|---|---|
| `id` | PK（Integer、自動） | |
| `welfare_recipient_id` | `unique=True`（暗黙インデックス） | 1:1を保証 + 受給者IDからの引き当て |
| `is_test_data` | `index=True` | テストデータ削除 |

---

#### `disability_statuses`

| カラム | インデックス種別 | 理由 |
|---|---|---|
| `id` | PK（Integer、自動） | |
| `welfare_recipient_id` | `unique=True`（暗黙インデックス） | 1:1を保証 + 受給者IDからの引き当て |
| `is_test_data` | `index=True` | テストデータ削除 |

---

#### `support_plan_cycles`

| カラム | インデックス種別 | 理由 |
|---|---|---|
| `id` | PK（Integer、自動） | |
| `welfare_recipient_id` | FK（インデックスなし） | ← 要注意（後述） |
| `office_id` | FK（インデックスなし） | ← 要注意（後述） |
| `is_test_data` | `index=True` | テストデータ削除 |

```python
# k_back/app/models/support_plan_cycle.py:30-36
class SupportPlanCycle(Base):
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    welfare_recipient_id: Mapped[uuid.UUID] = mapped_column(ForeignKey('welfare_recipients.id'))
    # ↑ index=True 未指定
    office_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey('offices.id', ondelete='CASCADE'),
        # ↑ index=True 未指定
    )
```

**重要**: `get_cycles_by_recipient` が `WHERE welfare_recipient_id = ?` で検索するが、インデックスが付与されていない。受給者1人あたりのサイクル数は最大でも数十件程度のため、現時点ではテーブルスキャンでも許容範囲内と判断している。ただし事業所規模が大きくなると要注意。

---

#### `support_plan_statuses`

| カラム | インデックス種別 | 理由 |
|---|---|---|
| `id` | PK（Integer、自動） | |
| `plan_cycle_id` | FK（インデックスなし） | |
| `welfare_recipient_id` | FK（インデックスなし） | |
| `office_id` | FK（インデックスなし） | |
| `completed_by` | FK（インデックスなし） | |
| `is_test_data` | `index=True` | テストデータ削除 |

**設計上の判断**: `support_plan_statuses` は常に `plan_cycle_id` をキーに `selectinload` で取得する（`get_cycles_by_recipient` の `selectinload(SupportPlanCycle.statuses)`）。1サイクルに5ステップ固定のため件数が少なく、`plan_cycle_id` のインデックスなしでも現時点で性能問題は発生していない。

---

#### `plan_deliverables`

| カラム | インデックス種別 | 理由 |
|---|---|---|
| `id` | PK（Integer、自動） | |
| `plan_cycle_id` | FK（インデックスなし） | |
| `uploaded_by` | FK（インデックスなし） | |
| `is_test_data` | `index=True` | テストデータ削除 |

**PDF一覧クエリのアクセスパターン** (`k_back/app/crud/crud_support_plan.py:51-68`):

```
plan_deliverables
  JOIN support_plan_cycles ON plan_cycle_id
  JOIN welfare_recipients ON welfare_recipient_id
  JOIN office_welfare_recipients ON welfare_recipient_id
  WHERE office_welfare_recipients.office_id = ?
  AND (filters)
  ORDER BY uploaded_at DESC
```

`uploaded_at` による降順ソートが頻繁に使われるが、明示的なインデックスは未設定。ページネーション（`LIMIT 20`）で件数を絞っているため、現時点では `uploaded_at` のフルスキャンを許容している。

---

#### アセスメントテーブル共通

| テーブル | FKカラム | インデックス |
|---|---|---|
| `family_of_service_recipients` | `welfare_recipient_id` | なし |
| `welfare_services_used` | `welfare_recipient_id` | なし |
| `medical_matters` | `welfare_recipient_id` | `unique=True`（暗黙） |
| `history_of_hospital_visits` | `medical_matters_id` | なし |
| `employment_related` | `welfare_recipient_id` | `unique=True`（暗黙） |
| `issue_analyses` | `welfare_recipient_id` | `unique=True`（暗黙） |

1:1のサブテーブルは `unique=True` で暗黙インデックスが作成される。1:Nのサブテーブル（`family`、`welfare_services_used`、`hospital_visits`）はFKインデックス未設定。

---

### 4-3. システム全体の重要インデックス（参照用）

#### `offices`（テナントルート）

```python
# k_back/app/models/office.py:30-35
__table_args__ = (
    # get_or_create_system_office が name + is_deleted で検索
    Index('ix_offices_name_is_deleted', 'name', 'is_deleted'),
)
is_deleted: Mapped[bool] = mapped_column(Boolean, index=True)
```

#### `staffs`

```python
# k_back/app/models/staff.py:62-64
is_deleted: Mapped[bool] = mapped_column(Boolean, index=True)
```

#### `message_recipients`（受信箱クエリ最適化）

```python
# k_back/app/models/message.py:184-197
__table_args__ = (
    UniqueConstraint('message_id', 'recipient_staff_id', name='uq_message_recipient'),
    # 未読メッセージ取得（受信箱クエリ）
    Index('ix_message_recipients_recipient_read', 'recipient_staff_id', 'is_read'),
    Index('ix_message_recipients_message', 'message_id'),
)
```

#### カレンダーイベント（部分インデックス）

```python
# k_back/app/models/calendar_events.py:131-161
Index(
    "idx_calendar_events_cycle_type_unique",
    "support_plan_cycle_id", "event_type",
    unique=True,
    # キャンセル済みを一意制約の対象外にする部分インデックス
    postgresql_where="support_plan_cycle_id IS NOT NULL AND (sync_status = 'pending' OR sync_status = 'synced')"
)
```

---

## 5. 制約設計

### 5-1. 1:1 制約の実装パターン

| テーブル | カラム | 制約 |
|---|---|---|
| `service_recipient_details` | `welfare_recipient_id` | `unique=True` |
| `disability_statuses` | `welfare_recipient_id` | `unique=True` |
| `medical_matters` | `welfare_recipient_id` | `unique=True` |
| `employment_related` | `welfare_recipient_id` | `unique=True` |
| `issue_analyses` | `welfare_recipient_id` | `unique=True` |

UNIQUEインデックスによりDB層でも1:1を保証する。ORMの `uselist=False` と二重防御。

### 5-2. カスケード削除設計

| FK方向 | ondelete | 理由 |
|---|---|---|
| `support_plan_cycles.office_id → offices.id` | `CASCADE` | 事業所削除でサイクルも不要 |
| `support_plan_statuses.welfare_recipient_id → welfare_recipients.id` | `CASCADE` | 受給者削除でステータスも不要 |
| `support_plan_statuses.office_id → offices.id` | `CASCADE` | 事業所削除でステータスも不要 |
| `service_recipient_details.welfare_recipient_id` | なし（ORM cascade） | Pythonレベルのcascade |
| `disability_statuses.welfare_recipient_id` | なし（ORM cascade） | Pythonレベルのcascade |

---

## 6. 設計のトレードオフまとめ

### 正規化についての判断

| 判断 | 正規化遵守 | 非正規化 | 採用した理由 |
|---|---|---|---|
| `welfare_recipients` のカラム数 | 最小限（6カラム） | — | 更新単位が独立 |
| `support_plan_cycles.office_id` | — | 冗長保持 | マルチテナントフィルタの最適化 |
| `staffs.full_name` | — | 冗長保持 | 全文検索インデックス対象にするため |
| `is_latest_cycle` フラグ | — | 集約結果を冗長保持 | 最新サイクルの即時取得 |

### インデックスについての判断

| 判断 | インデックスあり | インデックスなし | 採用した理由 |
|---|---|---|---|
| `service_recipient_details.welfare_recipient_id` | unique=True | — | 1:1制約 + 検索最適化 |
| `support_plan_cycles.welfare_recipient_id` | — | インデックスなし | 受給者あたりのサイクル数が少ない（現状で許容） |
| `office_welfare_recipients.office_id` | — | インデックスなし | 現状の事業所規模では許容、今後の要注意箇所 |
| `plan_deliverables.uploaded_at` | — | インデックスなし | LIMIT 20のページネーションで許容 |
| カレンダーイベントの部分インデックス | postgresql_where | — | キャンセル済みをスコープ外にしてインデックスサイズ削減 |

### 今後の検討事項

1. `office_welfare_recipients.office_id` — 事業所規模が大きくなった際にインデックス追加を検討
2. `support_plan_cycles.welfare_recipient_id` — サイクル数の多い事業所が増えた場合に追加検討
3. 受給者名の検索最適化 — `concat(last_name, first_name)` への関数インデックス（pg_trgm 拡張）
4. `plan_deliverables.uploaded_at` — ページネーションのオフセット方式からカーソル方式への移行でインデックスが有効になる
