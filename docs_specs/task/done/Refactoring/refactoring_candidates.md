# リファクタリング候補一覧

**作成日**: 2026-04-13  
**対象**: `k_back/` FastAPI バックエンド全体  
**分析方法**: コードベース全体のスタティック分析

---

## 優先度: 🔴 High

### 1. コード重複 — Office アクセス権限チェックパターン

**影響ファイル:**
- `app/api/v1/endpoints/support_plans.py` (lines 49, 185, 257, 316, 382, 423)
- `app/api/v1/endpoints/messages.py` (lines 76-78)
- `app/api/v1/endpoints/welfare_recipients.py`
- その他 8+ ファイル

**問題:**
以下のパターンがコピペで 8 回以上繰り返されている。

```python
user_office_ids = [assoc.office_id for assoc in current_staff.office_associations]
recipient_office_stmt = select(OfficeWelfareRecipient).where(
    OfficeWelfareRecipient.welfare_recipient_id == resource_id
)
recipient_office_result = await db.execute(recipient_office_stmt)
recipient_office_assoc = recipient_office_result.scalar_one_or_none()
if not recipient_office_assoc or recipient_office_assoc.office_id not in user_office_ids:
    raise ForbiddenException(...)
```

**対応方針:**
`app/api/deps.py` にヘルパー関数として集約する。

```python
async def check_office_access(
    db: AsyncSession,
    current_user: Staff,
    resource_type: type,
    resource_id: UUID
) -> None: ...
```

---

### 2. アーキテクチャ違反 — S3 ファイルアップロード処理が API 層にある

**ファイル:** `app/api/v1/endpoints/support_plans.py:200-208`

**問題:**
S3 へのアップロード処理がエンドポイント内に直接記述されており、Service 層の責務を侵食している。

```python
# ❌ API層にビジネスロジックがある
file_content = await file.read()
unique_filename = f"{uuid_lib.uuid4()}_{file.filename or 'unknown.pdf'}"
object_name = f"plan-deliverables/{plan_cycle_id}/{deliverable_type}/{unique_filename}"
file_like = io.BytesIO(file_content)
s3_url = await storage.upload_file(file=file_like, object_name=object_name)
```

**対応方針:**
`support_plan_service.handle_deliverable_upload()` に移動し、API 層はそのメソッドを呼ぶだけにする。

---

### 3. N+1 クエリリスク — `selectinload` の不統一

**ファイル:** `app/crud/crud_staff.py:17-28`

**問題:**
`get()` には `selectinload` が設定されているが、`get_by_email()` には設定されておらず、呼び出し側で予期せず N+1 クエリが発生するリスクがある。

```python
# ✅ get() — selectinload あり
async def get(self, db: AsyncSession, *, id: UUID) -> Staff | None:
    query = select(Staff).filter(Staff.id == id).options(
        selectinload(Staff.office_associations).selectinload(OfficeStaff.office),
        selectinload(Staff.mfa_backup_codes)
    )

# ❌ get_by_email() — selectinload なし
async def get_by_email(self, db: AsyncSession, *, email: str) -> Staff | None:
    query = select(Staff).filter(Staff.email == email)
```

**その他の該当箇所:**
- `support_plans.py:61` — `get_cycles_by_recipient()` 呼び出し後に `cycle.statuses` へアクセスしている可能性あり

**対応方針:**
CRUD メソッドごとに必要な `selectinload` を明示するか、呼び出し元がオプションを渡せるよう引数化する。

---

## 優先度: 🟡 Medium

### 4. デバッグ用 `print()` が本番コードに残存

**影響ファイル:**
- `app/api/deps.py` (27 箇所)
- `app/api/v1/endpoints/staffs.py` (lines 198, 204, 210)
- `app/api/v1/endpoints/assessment.py` (lines 54-68)
- `app/api/v1/endpoints/employee_action_requests.py` (lines 81-121)
- `app/api/v1/endpoints/role_change_requests.py` (lines 92-132)

**問題:**
`print()` と `logger` が混在している。`deps.py` では両方が呼ばれており冗長。

```python
# ❌ deps.py の現状
print(f"DEBUG: ...")   # 削除すべき
logger.info(f"...")    # こちらだけ残す
```

**対応方針:**
全ての `print()` を削除し、`logger` に統一する。

---

### 5. エラーハンドリングの重複パターン

**ファイル:** `app/api/v1/endpoints/staffs.py:53-69, 87-106, 164-182`

**問題:**
3 つの関数でほぼ同一の try/except ブロックが繰り返されている。

```python
try:
    result = await service.method(...)
    return result
except HTTPException:
    raise
except SpecificError as e:
    raise HTTPException(status_code=429, ...)
except Exception as e:
    raise HTTPException(status_code=500, ...)
```

**対応方針:**
デコレータまたはコンテキストマネージャに共通処理を抽出する。

---

### 6. 長大な関数

| ファイル | 関数 | 行数 | 問題点 |
|---|---|---|---|
| `endpoints/support_plans.py` | `get_support_plan_cycles()` | ~122行 | 権限チェック・データ取得・URL生成・レスポンス構築が混在 |
| `endpoints/welfare_recipients.py` | `create_welfare_recipient()` | ~111行 | バリデーション・サービス呼び出し・レスポンスマッピングが混在 |
| `endpoints/staffs.py` | delete 系エンドポイント | ~80行 | バリデーションチェックが 10 連続 |
| `services/welfare_recipient_service.py` | クラス全体 | 1004行 | 受給者作成・支援計画初期化・カレンダー操作が 1 クラスに集中 |

**対応方針 (support_plans.py の例):**

```python
# 以下に分割する
async def validate_recipient_access(...)
async def build_cycles_with_deliverables(...)
async def generate_presigned_urls(...)
```

**`welfare_recipient_service.py` の分割案:**
- `WelfareRecipientService` — 受給者 CRUD
- `SupportPlanInitializationService` — 計画の初期作成
- `CalendarEventService` — カレンダー連携

---

### 7. トランザクション管理の不統一

**問題のある箇所:**
- `endpoints/support_plans.py:436-437`
- `endpoints/messages.py:96-98`
- `endpoints/staffs.py:383-384`

```python
# ❌ API層で直接 commit している
await db.commit()
await db.refresh(cycle)
```

**対応方針:**
アーキテクチャルール「Service 層が `flush()`/`commit()` を担当し、API 層はコミットしない」を徹底する。ルールを `CLAUDE.md` に明記し統一する。

---

## 優先度: 🟢 Low

### 8. Import の重複・整理不足

**ファイル:** `app/api/v1/endpoints/auths.py:18-28`

```python
# ❌ 同一モジュールから2回インポートされている
from app.core.security import verify_password, create_access_token, ...
# ...
from app.core.security import verify_password, create_access_token, ..., create_email_verification_token
```

**その他:**
- `support_plans.py:39` — トップレベルにあるべき import が関数内にある
- `deps.py:109-111` — 関数内 import

---

### 9. 未使用のデッドコード

**ファイル:** `app/services/welfare_recipient_service.py:123-130`

```python
@staticmethod
def _validate_registration_data(registration_data: UserRegistrationRequest) -> None:
    """
    登録データのバリデーション (Pydanticに移行したため、現在は未使用)
    """
    pass
```

コメントに「現在は未使用」と明記されているが削除されていない。

---

### 10. レスポンスマッピングの不統一

**問題:**
- `calendar.py` — 8 フィールドを手動コピー
- `messages.py` — `model_validate()` を使用

```python
# ❌ calendar.py の手動マッピング
account_response = OfficeCalendarAccountResponse(
    id=account.id,
    office_id=account.office_id,
    google_calendar_id=account.google_calendar_id,
    # ... 5 フィールド続く
)

# ✅ messages.py の model_validate
response_data = MessageDetailResponse.model_validate(message)
```

**対応方針:** `model_validate()` に統一する。

---

### 11. マジックストリング・ハードコード値

- `support_plans.py:201` — `chunk_size = 500`
- `messages.py` — limit パラメータのデフォルト値
- `auths.py` — レート制限の閾値

**対応方針:** `app/core/config.py` または `app/core/constants.py` に集約する。

---

## 着手ロードマップ

| Phase | 内容 | 推定工数 |
|---|---|---|
| 1 | `print()` 削除・`logger` 統一 | 1-2h |
| 2 | Office 権限チェックヘルパー抽出 | 4-6h |
| 3 | `selectinload` 統一 | 4-6h |
| 4 | S3 処理を Service 層へ移動 | 4-8h |
| 5 | 長大な関数の分割 | 8-12h |
| 6 | トランザクション管理ルール統一 | 6-8h |
| 7 | Import 整理・デッドコード削除 | 2-3h |
| 8 | レスポンスマッピング統一 | 3-4h |

**合計見積もり:** 32〜49h

---

*最終更新: 2026-04-13*
