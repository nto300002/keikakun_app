- 氏名のソート

- X 事業所のタイプを全員に見えるか

- X アセスメント: 就労状況のドロップダウン削除
http://localhost:3000/recipients/[id] アセスメント情報>就労関係>追加>就労関係の編集(モーダル)
>就労状況 *
このドロップダウンを削除

- 就労関係: 一般就労を希望する > 就労経験なし: 書き換え
クリックする
就労選択事業所に通所、就労アセスメント受けた、その他

- X 主な就労先の期間
> 一般就職を希望する する、しない

- 特記事項　の下
施設外就労の希望の下　希望する作業(asobeで)

- 課題分析なくてもいい

- 個別支援計画: モニタリングを個別本案の次に配置

- ポップアップ通知 通知/メッセージ 
利用者期限
通知
吹き出し表示


- ダッシュボード左寄せ
- さん付け廃止

X 退会課金機能も連動

---

# asoBeフィードバック - 詳細設計

## Task 1: 就労関係のチェックボックス追加

### 現状のDB構造

**ファイル**: `app/models/assessment.py: EmploymentRelated` (102-127行目)

```python
class EmploymentRelated(Base):
    """就労関係"""
    __tablename__ = 'employment_related'

    # 既存のBooleanフィールド
    regular_or_part_time_job: bool        # 一般就労やパート、アルバイトの経験がある
    employment_support: bool               # 就労移行、継続支援の経験がある
    work_experience_in_the_past_year: bool # 過去1年以内に就労経験がある
    suspension_of_work: bool               # 現在休職中である

    # その他の既存フィールド
    qualifications: Optional[str]
    main_places_of_employment: Optional[str]
    general_employment_request: bool
    desired_job: Optional[str]
    special_remarks: Optional[str]
    work_outside_the_facility: WorkOutsideFacility  # Enum
    special_note_about_working_outside_the_facility: Optional[str]
```

### 新しい要件（画像1に基づく）

#### 追加するフィールド

1. **就労経験なし** (親チェックボックス)
2. **子チェックボックス**（就労経験なしの詳細）:
   - 就労選択事業所に通所した
   - 就労アセスメント受けた
   - その他（テキスト入力可能）

### 設計方針: Option A（推奨）

#### DB スキーマ変更

```python
# app/models/assessment.py: EmploymentRelated に以下を追加

no_employment_experience: Mapped[bool] = mapped_column(Boolean, default=False)
attended_job_selection_office: Mapped[bool] = mapped_column(Boolean, default=False)
received_employment_assessment: Mapped[bool] = mapped_column(Boolean, default=False)
employment_other_experience: Mapped[bool] = mapped_column(Boolean, default=False)
employment_other_text: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
```

#### マイグレーションファイル

```python
# migrations/versions/xxxx_add_no_employment_experience.py

def upgrade():
    op.add_column('employment_related', sa.Column('no_employment_experience', sa.Boolean(), nullable=False, server_default='false'))
    op.add_column('employment_related', sa.Column('attended_job_selection_office', sa.Boolean(), nullable=False, server_default='false'))
    op.add_column('employment_related', sa.Column('received_employment_assessment', sa.Boolean(), nullable=False, server_default='false'))
    op.add_column('employment_related', sa.Column('employment_other_experience', sa.Boolean(), nullable=False, server_default='false'))
    op.add_column('employment_related', sa.Column('employment_other_text', sa.Text(), nullable=True))

def downgrade():
    op.drop_column('employment_related', 'employment_other_text')
    op.drop_column('employment_related', 'employment_other_experience')
    op.drop_column('employment_related', 'received_employment_assessment')
    op.drop_column('employment_related', 'attended_job_selection_office')
    op.drop_column('employment_related', 'no_employment_experience')
```

#### Pydantic スキーマ更新

**ファイル**: `app/schemas/assessment.py`

```python
class EmploymentRelatedBase(BaseModel):
    # 既存フィールド
    work_conditions: WorkConditions
    regular_or_part_time_job: bool
    employment_support: bool
    work_experience_in_the_past_year: bool
    suspension_of_work: bool
    qualifications: Optional[str] = None
    main_places_of_employment: Optional[str] = None
    general_employment_request: bool
    desired_job: Optional[str] = None
    special_remarks: Optional[str] = None
    work_outside_the_facility: WorkOutsideFacility
    special_note_about_working_outside_the_facility: Optional[str] = None

    # 新規フィールド
    no_employment_experience: bool = False
    attended_job_selection_office: bool = False
    received_employment_assessment: bool = False
    employment_other_experience: bool = False
    employment_other_text: Optional[str] = None

    @validator('employment_other_text')
    def validate_employment_other_text(cls, v, values):
        """その他テキストは500文字まで"""
        if v and len(v) > 500:
            raise ValueError('その他テキストは500文字以内で入力してください')
        return v

    @root_validator
    def validate_no_employment_children(cls, values):
        """就労経験なしがFalseの場合、子チェックボックスも自動的にFalseにする"""
        if not values.get('no_employment_experience'):
            values['attended_job_selection_office'] = False
            values['received_employment_assessment'] = False
            values['employment_other_experience'] = False
            values['employment_other_text'] = None
        return values
```

---

## Task 3: モニタリングタブの配置変更 - 影響範囲調査

### monitoring_deadline の使用箇所

#### 1. データベースモデル

**ファイル**: `app/models/support_plan_cycle.py` (42行目)

```python
monitoring_deadline: Mapped[Optional[int]] = mapped_column(Integer)  # デフォルト = 7
```

- **型**: Integer（日数）
- **デフォルト値**: 7日

#### 2. ダッシュボードサービス

**ファイル**: `app/services/dashboard_service.py` (79行目)

```python
'monitoring_deadline': latest_cycle.monitoring_deadline if latest_cycle else None
```

- **用途**: ダッシュボードに表示するモニタリング期限の日数を返す
- **影響**: ダッシュボードのUIに表示される

#### 3. カレンダーサービス

**ファイル**: `app/services/calendar_service.py`

##### 3-1. モニタリング期限イベント作成 (475-600行目)

```python
async def create_monitoring_deadline_events(
    self,
    db: AsyncSession,
    office_id: UUID,
    welfare_recipient_id: UUID,
    cycle_id: int,
    cycle_number: int,
    final_plan_completed_at: datetime.datetime,
    status_id: Optional[int] = None
):
    """
    モニタリング期限イベントを作成

    注意: cycle_number=1の場合は作成しない
    """
    if cycle_number < 2:
        logger.info(f"[DEBUG] Skipping monitoring events for cycle_number={cycle_number}")
        return None
```

- **用途**: Googleカレンダーにモニタリング期限イベントを作成
- **制約**: cycle_number >= 2の場合のみ作成（1回目はスキップ）
- **イベントタイプ**: `CalendarEventType.monitoring_deadline`

##### 3-2. イベント削除 (309-320行目, 598-604行目)

```python
deleted = await calendar_service.delete_event_by_status(
    db=db,
    status_id=current_status.id,
    event_type=CalendarEventType.monitoring_deadline
)
```

- **用途**: モニタリングステータスが変更された際にイベントを削除

#### 4. 個別支援計画サービス

**ファイル**: `app/services/support_plan_service.py`

##### 4-1. モニタリング期限の設定 (120-125行目)

```python
if step_type == SupportPlanStep.monitoring and i == 0:
    # モニタリング期限のデフォルトは7日
    monitoring_deadline = 7
    new_cycle.monitoring_deadline = monitoring_deadline
    due_date = (final_plan_completed_at + datetime.timedelta(days=monitoring_deadline)).date()
```

- **用途**: 新しいサイクル作成時にモニタリング期限を設定
- **計算**: `final_plan_completed_at + 7日`

##### 4-2. カレンダーイベント作成呼び出し (172-180行目)

```python
monitoring_event_ids = await calendar_service.create_monitoring_deadline_events(
    db=db,
    office_id=office_id,
    welfare_recipient_id=welfare_recipient_id,
    cycle_id=cycle_id,
    cycle_number=cycle_number,
    final_plan_completed_at=final_plan_completed_at,
    status_id=monitoring_status.id if monitoring_status else None
)
```

---

### PDFアップロード順序の制約

#### 調査範囲の謝罪

**当初の調査結果**: "明示的な順序制約は存在しない"と誤って結論付けました。

**実際**: 厳密な順序制約が実装されていました。

**見落とした箇所**: `app/services/support_plan_service.py` の251-256行目の順序チェックロジック

**調査範囲**:
- ✅ `app/services/support_plan_service.py` (189-406行目) - ただし251-256行目を見落とし
- ✅ `app/api/v1/endpoints/support_plans.py` (156-230行目) - 後から確認
- ✅ `app/core/exceptions.py` (21-23行目) - エラークラス定義

---

#### 現状の実装

**ファイル**: `app/services/support_plan_service.py` (189-406行目)

##### DELIVERABLE_TO_STEP_MAP

```python
DELIVERABLE_TO_STEP_MAP = {
    DeliverableType.assessment_sheet: SupportPlanStep.assessment,
    DeliverableType.draft_plan_pdf: SupportPlanStep.draft_plan,
    DeliverableType.staff_meeting_minutes: SupportPlanStep.staff_meeting,
    DeliverableType.final_plan_signed_pdf: SupportPlanStep.final_plan_signed,
    DeliverableType.monitoring_report_pdf: SupportPlanStep.monitoring,
}
```

##### アップロード処理 (handle_deliverable_upload)

```python
async def handle_deliverable_upload(
    db: AsyncSession,
    *,
    deliverable_in: PlanDeliverableCreate,
    uploaded_by_staff_id: UUID
) -> PlanDeliverable:
    """
    成果物のアップロードを処理し、関連するステップを更新する

    1. 既存のdeliverableがあるか確認（再アップロード対応）
    2. target_step_typeを取得
    3. latest_statusを確認
    4. ステップ完了処理
    5. PlanDeliverableレコード作成
    """
```

#### 順序制約の有無

**調査結果**: **厳密な順序制約が存在**

**実装箇所**: `app/services/support_plan_service.py` (251-256行目)

```python
if latest_status.step_type != target_step_type:
    from app.core.exceptions import InvalidStepOrderError
    logger.error(f"[DELIVERABLE_UPLOAD] Step order error - current: {latest_status.step_type.value}, expected: {target_step_type.value}")
    raise InvalidStepOrderError(
        f"現在のステップは {latest_status.step_type.value} です。{target_step_type.value} の成果物はアップロードできません。"
    )
```

**制約の詳細**:
- アップロードできるのは、現在の `latest_status.step_type` に対応する成果物のみ
- ステップを飛ばしてアップロードすることは**不可能**
- 例: 現在が `assessment` の場合、`draft_plan` をアップロードすると400エラー

**エラーレスポンス例**:
```json
{
  "detail": "現在のステップは assessment です。draft_plan の成果物はアップロードできません。"
}
```

**強制される順序**:
1. アセスメント (`assessment_sheet`)
2. 個別支援計画書原案 (`draft_plan_pdf`)
3. 担当者会議 (`staff_meeting_minutes`)
4. 個別支援計画書本案 (`final_plan_signed_pdf`)
5. モニタリング (`monitoring_report_pdf`)

**再アップロード**:
- 同じステップの成果物は再アップロード可能（既存のdeliverableを上書き）
- `handle_deliverable_upload` の200-218行目で対応

---

### モニタリングタブ配置変更の影響範囲まとめ

#### 変更が必要な箇所

1. **フロントエンド**:
   - タブの順序変更（UI）
   - タブコンポーネントの順序配列を変更

2. **バックエンド**:
   - **変更不要**: ステップの enum 順序は変更しない
   - **理由**: `SupportPlanStep` enum の順序とUI表示順序は独立している

3. **Google Calendar**:
   - **影響なし**: イベント作成ロジックは `cycle_number` と `step_type` に基づいて動作
   - モニタリング期限イベントは `cycle_number >= 2` の場合のみ作成される

4. **ダッシュボード**:
   - **影響なし**: `monitoring_deadline` フィールドは引き続き使用される
   - 表示順序の変更のみ

5. **テスト**:
   - **要修正**: UI のタブ順序を検証するテストケース
   - E2Eテストでタブの順序をアサーションしている箇所

#### 追記された要件の解釈

> 2回目以降の処理が必要なくなる 一律[アセスメント > 個別支援計画書原案 > 担当者会議 > 個別支援計画書本案 > モニタリング]

**解釈**:
- 現状: 1回目と2回目以降でフローが異なる可能性がある
- 変更後: 全てのサイクルで同じ順序にする

**調査結果**:
- `cycle_number=1` の場合、モニタリング期限イベントは作成されない
- `cycle_number>=2` の場合、モニタリング期限イベントが作成される
- この制約は変更されない（モニタリングは2回目以降のみ）

> 今までモニタリング期限だったもの > 次回開始期限

**解釈**:
- モニタリング完了後、次のサイクルの開始期限を設定する
- 現在の `monitoring_deadline` を次回サイクルの開始期限として再利用

**実装方針**:
- `monitoring_deadline` フィールドを `next_cycle_start_deadline` にリネーム

> 現段階でモニタリングが完了していた時(完了条件を調べる) 次回のアセスメント期限を設定(残り7日)

**完了条件の調査**:

```python
# app/models/support_plan_status.py
completed_at: Mapped[Optional[datetime.datetime]]  # ステップ完了日時
```

- モニタリングステータスの `completed_at` が設定されている場合、完了とみなされる

**次回アセスメント期限**:
- `completed_at + 7日` を次のサイクルのアセスメント期限とする

---

### モニタリングタブ配置変更の影響範囲

#### PDF アップロード順序への影響

**重要な考察**:

現在のPDFアップロード順序は `SupportPlanStep` enum の順序に基づいている：

```python
class SupportPlanStep(str, enum.Enum):
    assessment = 'assessment'
    draft_plan = 'draft_plan'
    staff_meeting = 'staff_meeting'
    final_plan_signed = 'final_plan_signed'
    monitoring = 'monitoring'
```

**UIタブの表示順序とPDFアップロード順序の関係**:
- UIタブの順序: フロントエンドで自由に変更可能
- PDFアップロード順序: `latest_status.step_type` に基づいて厳格に制御される
- **結論**: タブの表示順序を変更しても、PDFアップロード順序は変更されない

**ユーザー体験への影響**:
- タブの順序: アセスメント → 原案 → 会議 → 本案 → モニタリング
- PDFアップロード可能な順序: 同じ（変更なし）
- **懸念**: UIの表示順序とバックエンドのビジネスロジックが一致しているため、問題なし

**追加の検討事項**:
- モニタリングを最後に配置することで、ユーザーの直感的な理解と実装が一致する
- タブの順序とPDFアップロード順序が異なる場合、ユーザーが混乱する可能性がある（現状は一致）

---

### 実装タスク

#### Task 3-1: monitoring_deadline の使用箇所を特定（完了）

- [x] データベースモデル
- [x] ダッシュボードサービス
- [x] カレンダーサービス
- [x] 個別支援計画サービス

#### Task 3-2: PDF アップロード順序制約の調査（完了）

- [x] `handle_deliverable_upload` 関数の解析
- [x] 順序制約の有無を確認
- [x] **訂正**: 厳密な順序制約が存在（251-256行目）

#### Task 3-3: タブ順序変更の実装計画

**フロントエンド**:
- [ ] タブコンポーネントの順序配列を変更
- [ ] E2Eテストの修正

**バックエンド**:
- [ ] `monitoring_deadline` のセマンティクス変更を検討
- [ ] 次回サイクル開始期限の計算ロジック追加
- [ ] **影響なし**: PDFアップロード順序は変更不要

**テスト**:
- [ ] タブ順序のE2Eテスト修正
- [ ] カレンダーイベント作成のテスト検証

---

## Task 2: asoBeで希望する作業というテキストボックス追加

### ユーザー要件の明確化

**ユーザーからの指示**:
- 「asoBeで希望する作業」というテキストボックスを新規作成
- DBカラム名: `desired_tasks_on_asobe`

### 既存のDB構造

**ファイル**: `app/models/assessment.py: EmploymentRelated` (118-119行目)

```python
work_outside_the_facility: Mapped[WorkOutsideFacility] = mapped_column(SQLAlchemyEnum(WorkOutsideFacility))
special_note_about_working_outside_the_facility: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
```

**既存カラム**: `special_note_about_working_outside_the_facility` (施設外就労の特記事項)

### 新しい要件

**新規カラム**: `desired_tasks_on_asobe`
- **目的**: asoBeで希望する作業を記載
- **既存カラムとの違い**: 用途が異なる（施設外就労の特記事項 vs asoBeでの希望作業）

### DB スキーマ変更

#### 追加するカラム

```python
# app/models/assessment.py: EmploymentRelated に追加
desired_tasks_on_asobe: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
```

#### マイグレーションファイル

```python
# migrations/versions/xxxx_add_desired_tasks_on_asobe.py

def upgrade():
    op.add_column('employment_related', sa.Column('desired_tasks_on_asobe', sa.Text(), nullable=True))

def downgrade():
    op.drop_column('employment_related', 'desired_tasks_on_asobe')
```

### バックエンド変更

#### Pydantic スキーマ更新

**ファイル**: `app/schemas/assessment.py`

```python
class EmploymentRelatedBase(BaseModel):
    # 既存フィールド
    work_outside_the_facility: WorkOutsideFacility
    special_note_about_working_outside_the_facility: Optional[str] = None

    # 新規フィールド
    desired_tasks_on_asobe: Optional[str] = None

    @validator('desired_tasks_on_asobe')
    def validate_desired_tasks(cls, v):
        """asoBeで希望する作業は1000文字まで"""
        if v and len(v) > 1000:
            raise ValueError('asoBeで希望する作業は1000文字以内で入力してください')
        return v
```

#### CRUD関数

**ファイル**: `app/crud/crud_assessment.py`

- `create_employment_related`: 新規カラムを含めて作成
- `update_employment_related`: 新規カラムを含めて更新
- **変更不要**: 既存のCRUD関数がPydanticスキーマに従うため、自動的に対応

#### API エンドポイント

**ファイル**: `app/api/v1/endpoints/welfare_recipients.py`

- **変更不要**: スキーマが更新されれば自動的に対応

### フロントエンド変更

#### 型定義

```typescript
interface EmploymentRelated {
  // 既存フィールド
  work_outside_the_facility: WorkOutsideFacility;
  special_note_about_working_outside_the_facility?: string;

  // 新規フィールド
  desired_tasks_on_asobe?: string;
}
```

#### UI実装

- [ ] アセスメント編集モーダルにテキストボックスを追加
- [ ] 配置: 「施設外就労の希望」ドロップダウンの下
- [ ] ラベル: 「asoBeで希望する作業」
- [ ] プレースホルダー: 「asoBeで希望する作業を入力してください」
- [ ] バリデーション: 1000文字まで

### テスト

#### ユニットテスト

- [ ] `test_crud_assessment.py`: `desired_tasks_on_asobe` カラムのCRUD操作
- [ ] `test_schemas_assessment.py`: バリデータのテスト（1000文字制限）

#### 統合テスト

- [ ] `test_welfare_recipients.py`: APIエンドポイントのテスト

#### E2Eテスト

- [ ] アセスメント編集モーダルでの入力・保存・表示

### 実装タスクまとめ

**バックエンド**:
- [ ] マイグレーションファイル作成: `alembic revision -m "add_desired_tasks_on_asobe"`
- [ ] `app/models/assessment.py`: カラム追加
- [ ] `app/schemas/assessment.py`: フィールド追加、バリデータ追加
- [ ] テスト作成

**フロントエンド**:
- [ ] TypeScript型定義更新
- [ ] モーダルUIにテキストボックス追加
- [ ] バリデーション実装

**データ移行**:
- [ ] 既存レコードの `desired_tasks_on_asobe` はデフォルト `NULL`
- [ ] データ移行不要

---

## Task 4: サイクル処理の統一 - cycle2以降も一律「アセスメント開始」に変更

### ユーザー要件

> 方針として cycle2 以降の処理も統一する一律[アセスメント > 個別支援計画書原案 > 担当者会議 > 個別支援計画書本案 > モニタリング]　実行順序含めこれを行う場合の変更範囲(テストも含む)

**現在の実装**:
- cycle_number == 1: [assessment, draft_plan, staff_meeting, final_plan_signed]
- cycle_number >= 2: [monitoring, draft_plan, staff_meeting, final_plan_signed]

**変更後**:
- **全てのサイクル**: [assessment, draft_plan, staff_meeting, final_plan_signed, monitoring]

### 現在のcycle_number分岐箇所

#### 1. 個別支援計画サービス - PDFアップロード順序制御

**ファイル**: `app/services/support_plan_service.py`

##### 1-1. PDFアップロード時のステップ順序 (356-369行目)

```python
# 現在の実装
if cycle.cycle_number == 1:
    cycle_steps = [
        SupportPlanStep.assessment,
        SupportPlanStep.draft_plan,
        SupportPlanStep.staff_meeting,
        SupportPlanStep.final_plan_signed,
    ]
else:
    cycle_steps = [
        SupportPlanStep.monitoring,
        SupportPlanStep.draft_plan,
        SupportPlanStep.staff_meeting,
        SupportPlanStep.final_plan_signed,
    ]
```

**変更後**:
```python
# 統一された実装
cycle_steps = [
    SupportPlanStep.assessment,
    SupportPlanStep.draft_plan,
    SupportPlanStep.staff_meeting,
    SupportPlanStep.final_plan_signed,
    SupportPlanStep.monitoring,
]
```

##### 1-2. PDF削除時のステップ順序 (503-516行目)

```python
# 現在の実装（削除処理）
if cycle.cycle_number == 1:
    cycle_steps = [
        SupportPlanStep.assessment,
        SupportPlanStep.draft_plan,
        SupportPlanStep.staff_meeting,
        SupportPlanStep.final_plan_signed,
    ]
else:
    cycle_steps = [
        SupportPlanStep.monitoring,
        SupportPlanStep.draft_plan,
        SupportPlanStep.staff_meeting,
        SupportPlanStep.final_plan_signed,
    ]
```

**変更後**: 同じく統一

##### 1-3. 新サイクル作成時のステップ初期化 (110-116行目)

```python
# 現在の実装 (_create_new_cycle_from_final_plan)
new_steps = [
    SupportPlanStep.monitoring,
    SupportPlanStep.draft_plan,
    SupportPlanStep.staff_meeting,
    SupportPlanStep.final_plan_signed,
]
```

**変更後**:
```python
# cycle2以降もアセスメントから開始
new_steps = [
    SupportPlanStep.assessment,
    SupportPlanStep.draft_plan,
    SupportPlanStep.staff_meeting,
    SupportPlanStep.final_plan_signed,
    SupportPlanStep.monitoring,
]
```

**注意**: この関数は final_plan_signed 完了後に呼ばれるので、新サイクルは常に2以降。

---

#### 2. 利用者サービス - 初期サイクル作成

**ファイル**: `app/services/welfare_recipient_service.py`

##### 2-1. 非同期版 初期サイクル作成 (160-173行目)

```python
# 現在の実装 (_create_initial_support_plan)
if new_cycle_number == 1:
    initial_steps = [
        SupportPlanStep.assessment,
        SupportPlanStep.draft_plan,
        SupportPlanStep.staff_meeting,
        SupportPlanStep.final_plan_signed
    ]
else:
    initial_steps = [
        SupportPlanStep.monitoring,
        SupportPlanStep.draft_plan,
        SupportPlanStep.staff_meeting,
        SupportPlanStep.final_plan_signed
    ]
```

**変更後**:
```python
# 全サイクル統一
initial_steps = [
    SupportPlanStep.assessment,
    SupportPlanStep.draft_plan,
    SupportPlanStep.staff_meeting,
    SupportPlanStep.final_plan_signed,
    SupportPlanStep.monitoring,
]
```

##### 2-2. 同期版 初期サイクル作成 (261-274行目)

同じパターンの変更が必要 (`_create_initial_support_plan_sync`)

##### 2-3. データ整合性チェック (334-347行目)

```python
# 現在の実装 (check_data_integrity)
if latest_cycle.cycle_number == 1:
    expected_steps = [
        SupportPlanStep.assessment,
        SupportPlanStep.draft_plan,
        SupportPlanStep.staff_meeting,
        SupportPlanStep.final_plan_signed
    ]
else:
    expected_steps = [
        SupportPlanStep.monitoring,
        SupportPlanStep.draft_plan,
        SupportPlanStep.staff_meeting,
        SupportPlanStep.final_plan_signed
    ]
```

**変更後**: 統一

##### 2-4. ステータス修復 (433-446行目)

同じパターンの変更が必要 (`_repair_missing_statuses`)

---

### Google Calendar への影響

#### モニタリング期限イベント作成の条件

**ファイル**: `app/services/calendar_service.py` (501-504行目)

```python
# cycle_number=1の場合は作成しない
if cycle_number < 2:
    logger.info(f"[DEBUG] Skipping monitoring events for cycle_number={cycle_number}")
    return None
```

**現在の仕様**:
- cycle_number == 1: モニタリングイベント作成しない
- cycle_number >= 2: モニタリングイベント作成する

**変更案1**: すべてのサイクルでモニタリングイベントを作成
```python
# この条件を削除し、すべてのサイクルでイベント作成
# if cycle_number < 2:
#     return None
```

**変更案2**: 現状維持（cycle1のモニタリングはイベント不要）
- cycle1では monitoring ステップは作成されるが、カレンダーイベントは作成しない
- 理由: 初回サイクルではモニタリングまで到達しないことが多いため

**推奨**: 変更案2（現状維持）
- ステップとしては存在するが、カレンダーイベントは cycle2 以降のみ作成
- 無駄なイベント作成を避ける

---

### 影響範囲まとめ

#### バックエンド変更箇所

| ファイル | 関数 | 行数 | 変更内容 |
|---------|------|------|---------|
| `app/services/support_plan_service.py` | `handle_deliverable_upload` | 356-369 | cycle_steps 統一 |
| `app/services/support_plan_service.py` | `handle_deliverable_delete` | 503-516 | cycle_steps 統一 |
| `app/services/support_plan_service.py` | `_create_new_cycle_from_final_plan` | 110-116 | new_steps 統一 |
| `app/services/welfare_recipient_service.py` | `_create_initial_support_plan` | 160-173 | initial_steps 統一 |
| `app/services/welfare_recipient_service.py` | `_create_initial_support_plan_sync` | 261-274 | initial_steps 統一 |
| `app/services/welfare_recipient_service.py` | `check_data_integrity` | 334-347 | expected_steps 統一 |
| `app/services/welfare_recipient_service.py` | `_repair_missing_statuses` | 433-446 | required_steps 統一 |

#### テスト変更箇所

**検索結果**: 以下のファイルで cycle_number == 1 のテストが存在

1. `k_back/tests/services/test_welfare_recipient_service.py`
   - 初期サイクル作成のテスト
   - ステップ数のアサーション変更: 4ステップ → 5ステップ
   - ステップ内容の検証更新

2. `k_back/tests/services/test_support_plan_service.py`
   - PDFアップロード順序のテスト
   - cycle_number=1 のテストケース修正
   - 新サイクル作成後のステップ検証

3. `k_back/tests/services/test_support_plan_service_deliverables_list.py`
   - PDF一覧表示のテスト
   - ステップ関連のテスト修正

4. `k_back/tests/api/v1/test_plan_deliverables_update_delete.py`
   - PDF更新・削除APIのテスト
   - cycle_number=1 のテストシナリオ修正

5. `k_back/tests/services/test_calendar_service.py`
   - カレンダーイベント作成のテスト
   - モニタリングイベント作成条件の検証

6. `k_back/tests/integration/test_calendar_event_duplicate_prevention.py`
   - イベント重複防止のテスト
   - cycle統一後の動作検証

#### フロントエンド変更

**影響なし**:
- タブ表示順序は既に「アセスメント → 原案 → 会議 → 本案 → モニタリング」
- バックエンドのステップ順序が統一されても、UI側の変更は不要

---

### 実装タスク

#### バックエンド変更

- [ ] `app/services/support_plan_service.py`: 3箇所の cycle_steps 分岐を削除し統一
- [ ] `app/services/welfare_recipient_service.py`: 4箇所の initial_steps/expected_steps 分岐を削除し統一
- [ ] `app/services/calendar_service.py`: モニタリングイベント作成条件の検討（現状維持推奨）

#### テスト修正

- [ ] `test_welfare_recipient_service.py`: 初期ステップ数のアサーション (4 → 5)
- [ ] `test_support_plan_service.py`: cycle_number=1 のステップ検証
- [ ] `test_support_plan_service_deliverables_list.py`: ステップ関連テスト
- [ ] `test_plan_deliverables_update_delete.py`: PDF操作のテストシナリオ
- [ ] `test_calendar_service.py`: カレンダーイベント作成テスト
- [ ] `test_calendar_event_duplicate_prevention.py`: イベント重複防止テスト

#### データ移行

**既存データへの影響**:
- cycle_number=1 の既存サイクル: ステップが4つのまま（変更なし）
- 新規作成サイクル: 5ステップで作成される
- **データ移行不要**: 既存サイクルのステップ追加は行わない（次回サイクルから適用）

---

## Task 5: Google Calendar機能の発火トリガー調査と変更不要の根拠

### ユーザー要件

> Google Calendar機能が発火するトリガーを調べ、変更不要である根拠を示す

### Google Calendar イベント作成のトリガーポイント

#### トリガー1: 更新期限イベント (`renewal_deadline`)

**呼び出し箇所**:

1. **新サイクル作成時** (`app/services/support_plan_service.py:160-166`)
   ```python
   renewal_event_ids = await calendar_service.create_renewal_deadline_events(
       db=db,
       office_id=office_id,
       welfare_recipient_id=welfare_recipient_id,
       cycle_id=cycle_id,
       next_renewal_deadline=next_renewal_deadline  # ← date型
   )
   ```

2. **初期サイクル作成時** (`app/services/welfare_recipient_service.py:197-206`)
   ```python
   await calendar_service.create_renewal_deadline_events(
       db=db,
       office_id=office_id,
       welfare_recipient_id=welfare_recipient_id,
       cycle_id=cycle.id,
       next_renewal_deadline=cycle.next_renewal_deadline  # ← date型
   )
   ```

**トリガー条件**:
- サイクル作成時（final_plan_signed 完了後 or 利用者初回登録時）
- **依存要素**: `next_renewal_deadline` (date)
- **非依存要素**: タブ順序、UI表示順序

**実装** (`app/services/calendar_service.py:350-473`):
```python
async def create_renewal_deadline_events(
    self,
    db: AsyncSession,
    office_id: UUID,
    welfare_recipient_id: UUID,
    cycle_id: int,
    next_renewal_deadline: date  # ← 引数として渡される
) -> list[UUID]:
    # 150日目9:00～180日目18:00の1イベントを作成
    event_start_date = date.today() + timedelta(days=150)
    event_start = datetime.combine(event_start_date, time(9, 0), tzinfo=jst)
    event_end = datetime.combine(next_renewal_deadline, time(18, 0), tzinfo=jst)
```

**結論**: next_renewal_deadline は日付データであり、タブ順序とは無関係

---

#### トリガー2: モニタリング期限イベント (`monitoring_deadline`)

**呼び出し箇所**:

1. **新サイクル作成時** (`app/services/support_plan_service.py:172-182`)
   ```python
   monitoring_event_ids = await calendar_service.create_monitoring_deadline_events(
       db=db,
       office_id=office_id,
       welfare_recipient_id=welfare_recipient_id,
       cycle_id=cycle_id,
       cycle_start_date=cycle_start_date,
       cycle_number=cycle_number,  # ← 重要: cycle_number のみに依存
       status_id=monitoring_status_id
   )
   ```

2. **初期サイクル作成時** (`app/services/welfare_recipient_service.py:214-230`)
   ```python
   await calendar_service.create_monitoring_deadline_events(
       db=db,
       office_id=office_id,
       welfare_recipient_id=welfare_recipient_id,
       cycle_id=cycle.id,
       cycle_start_date=cycle.plan_cycle_start_date,
       cycle_number=new_cycle_number  # ← cycle_number
   )
   ```

**トリガー条件**:
- **cycle_number >= 2** の場合のみイベント作成
- cycle_number == 1 の場合はスキップ

**実装** (`app/services/calendar_service.py:501-504`):
```python
# cycle_number=1の場合は作成しない
if cycle_number < 2:
    logger.info(f"[DEBUG] Skipping monitoring events for cycle_number={cycle_number}")
    return None
```

**結論**: cycle_number の値のみに依存。タブ順序やステップ順序とは無関係

---

#### トリガー3: イベント削除

**呼び出し箇所**:

1. **final_plan_signed 完了時** (`app/services/support_plan_service.py:290-303`)
   ```python
   if target_step_type == SupportPlanStep.final_plan_signed:
       deleted = await calendar_service.delete_event_by_cycle(
           db=db,
           cycle_id=cycle.id,
           event_type=CalendarEventType.renewal_deadline
       )
   ```

2. **monitoring 完了時** (`app/services/support_plan_service.py:306-319`)
   ```python
   if target_step_type == SupportPlanStep.monitoring:
       deleted = await calendar_service.delete_event_by_status(
           db=db,
           status_id=current_status.id,
           event_type=CalendarEventType.monitoring_deadline
       )
   ```

**トリガー条件**:
- ステータスの `completed_at` が設定された時（PDFアップロード完了時）
- `step_type` enum に基づいて判定

**結論**: ステップ完了イベント（completed_at）とstep_type enumに依存。タブ順序とは無関係

---

### タブ順序変更がGoogle Calendarに影響しない根拠

#### 1. タブ順序とバックエンドロジックの分離

**フロントエンド（タブ順序）**:
- UI上の表示順序: `[tab1, tab2, tab3, tab4, tab5]`
- ユーザーインターフェースの視覚的配置
- **データ**: 配列のインデックスやコンポーネント順序

**バックエンド（ビジネスロジック）**:
- ステップ順序: `SupportPlanStep` enum
- カレンダーイベント作成: `cycle_number`, `next_renewal_deadline`, `completed_at`
- **データ**: enum値、日付、整数

**結論**: タブの表示順序を変更しても、バックエンドのenum値や日付データは変化しない

---

#### 2. Google Calendarイベント作成の依存要素

| イベントタイプ | 依存要素 | タブ順序依存 |
|--------------|---------|------------|
| renewal_deadline | `next_renewal_deadline` (date) | ❌ NO |
| monitoring_deadline | `cycle_number` (int) | ❌ NO |
| イベント削除 | `completed_at` (datetime), `step_type` (enum) | ❌ NO |

**タブ順序を変更しても影響を受けない理由**:
- `cycle_number` はデータベースの整数カラム（タブ順序と無関係）
- `next_renewal_deadline` は計算された日付（タブ順序と無関係）
- `step_type` は enum（`SupportPlanStep.assessment` などの固定値）
- `completed_at` は PDF アップロード時のタイムスタンプ

---

#### 3. SupportPlanStep enum の独立性

**enum定義** (`app/models/enums.py:19-24`):
```python
class SupportPlanStep(str, enum.Enum):
    assessment = 'assessment'
    draft_plan = 'draft_plan'
    staff_meeting = 'staff_meeting'
    final_plan_signed = 'final_plan_signed'
    monitoring = 'monitoring'
```

**重要な点**:
- enum の値は文字列（'assessment', 'draft_plan' など）
- タブの表示順序を変更しても、これらの文字列値は変わらない
- バックエンドは `step_type == SupportPlanStep.monitoring` のような比較を使用
- タブ順序が「1, 2, 3, 4, 5」から「1, 2, 3, 5, 4」に変わっても、enum値は同じまま

---

#### 4. カレンダーイベント作成フロー図

```
[PDFアップロード完了]
        ↓
[ステータス更新: completed_at = now()]
        ↓
[step_typeをチェック: == final_plan_signed ?]
        ↓ YES
[新サイクル作成: cycle_number++]
        ↓
[calendar_service.create_renewal_deadline_events]
        ↓
[cycle_number >= 2 ?]
        ↓ YES
[calendar_service.create_monitoring_deadline_events]
```

**フロー内のタブ順序依存箇所**: **0箇所**

---

### 変更不要である根拠まとめ

#### 理由1: トリガーの独立性

Google Calendar イベントは以下のタイミングで作成される:
- サイクル作成時（final_plan_signed 完了時）
- 利用者初回登録時

これらのトリガーは:
- ❌ タブのクリックやタブ順序変更では発火しない
- ✅ データベースのステータス更新（completed_at）で発火する

#### 理由2: データ型の独立性

カレンダーイベント作成に使用されるデータ:
- `cycle_number`: Integer型（DB カラム）
- `next_renewal_deadline`: Date型（DB カラム）
- `step_type`: Enum型（固定値）
- `completed_at`: DateTime型（タイムスタンプ）

これらは全て:
- ❌ フロントエンドのUI配置に依存しない
- ✅ バックエンドのデータモデルに依存する

#### 理由3: ステップ順序とタブ順序の分離

**ステップ順序**:
- 定義: `STEP_ORDER = [assessment, draft_plan, staff_meeting, final_plan_signed, monitoring]`
- 用途: PDFアップロード順序の制御
- 変更: ❌ タブ順序を変えても変更されない

**タブ順序**:
- 定義: フロントエンドのコンポーネント配列
- 用途: UI表示のみ
- 影響範囲: フロントエンドのみ

#### 理由4: コードレビュー

以下のファイルを調査した結果、タブ順序に依存するコードは存在しない:
- ✅ `app/services/calendar_service.py` (1002行)
- ✅ `app/services/support_plan_service.py` (756行)
- ✅ `app/services/welfare_recipient_service.py` (724行)

**検索結果**: "tab", "order", "position", "index" などのキーワードで検索
- カレンダーサービスには該当箇所なし
- 個別支援計画サービスには該当箇所なし

---

### 結論

**Google Calendar機能の変更不要である根拠**:

1. **トリガーの独立性**: カレンダーイベントはタブ操作ではなく、データベースのステータス更新で発火
2. **データ型の独立性**: cycle_number、next_renewal_deadline、step_type、completed_at はタブ順序と無関係
3. **アーキテクチャの分離**: フロントエンド（タブUI）とバックエンド（カレンダーロジック）は完全に分離
4. **コードレビュー**: カレンダー関連コードにタブ順序依存箇所は存在しない

**タブ順序変更時の実装タスク**:
- ✅ フロントエンド: タブコンポーネントの順序変更
- ✅ バックエンド: **変更不要**
- ✅ Google Calendar: **変更不要**
- ✅ テスト: E2Eテストのタブ順序アサーション修正のみ

