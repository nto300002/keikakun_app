```
# .env.local
# バックエンドAPIのURL
BACKEND_API_URL
DATABASE_URL

## local backend
FRONTEND_NEXT_PUBLIC_SUPABASE_URL
FRONTEND_NEXT_PUBLIC_SUPABASE_ANON_KEY
NEXT_PUBLIC_BACKEND_API_URL
SUPABASE_JWT_SECRET
GOTRUE_JWT_SECRET
NEXT_PUBLIC_GOOGLE_CLIENT_ID
NEXT_PUBLIC_GOOGLE_CLIENT_SECRET

```

### **アプリケーション技術設計書: ケイカくん**

このドキュメントは「ケイカくん」の開発における技術的な仕様と設計を定義します。

### **1. フロントエンド設計 (Next.js)**

**1.1. 主要ライブラリ**

*   **フレームワーク**: Next.js (App Router), React
*   **スタイリング**: Tailwind CSS, shadcn/ui (推奨)
*   **状態管理・データ取得**: SWR or TanStack Query (React Query)
*   **フォーム管理**: React Hook Form
*   **スキーマ検証**: Zod (フォーム入力値の検証)
*   **APIクライアント**: Axios or 標準の`fetch`
*   **日付操作**: date-fns

**1.2. 画面別コンポーネント構成・ロジック・API連携**

#### **a. ダッシュボード (`/dashboard`)**

*   **画面構成**:
    *   `DashboardHeader`: ログイン中のスタッフ名、役割、権限に応じた説明文を表示。
    *   `CreateRecipientButton`: 利用者作成ページへ遷移するボタン。
    *   `DashboardTable`: 利用者一覧を表示するメインコンポーネント。
        *   `DashboardTableRow`: 各利用者の行。`氏名`, `計画の進捗`, `次回更新日`, `モニタリング開始期限`のセルを含む。
*   **主要ロジックとAPI連携**:
    *   **ページ表示時**:
        *   `GET /api/v1/staff/me`: ログイン中のスタッフ情報を取得し、ヘッダーに表示。
        *   `GET /api/v1/dashboard/summaries`: テーブルに表示する全利用者の計画サマリーデータを取得。
    *   **モニタリング期限フォーム**: フォームの値を`PATCH /api/v1/support-statuses/{status_id}`で更新。
*   **画面遷移**:
    *   `CreateRecipientButton`クリック → `/recipients/new`へ遷移。
    *   `DashboardTableRow`の氏名セルクリック → `/recipients/{recipient_id}/plan`へ遷移。

#### **b. 個別支援計画ページ (`/recipients/{recipient_id}/plan`)**

*   **画面構成**:
    *   `RecipientInfo`: 対象利用者の基本情報を表示。
    *   `PlanCycleTable`: 計画サイクルの履歴を一覧表示するテーブル。
        *   `PlanCycleTableRow`: 各サイクルの行。回数、各ステップのセルで構成。
        *   `PlanStepCell`: 各ステップのセル。完了状態（チェック等）を表示。クリックでモーダルを開く。
    *   `PdfUploadModal`: ファイルアップロード機能を持つモーダルウィンドウ。
*   **主要ロジックとAPI連携**:
    *   **ページ表示時**: `GET /api/v1/recipients/{recipient_id}/plan`: 指定された利用者の全計画サイクル、ステータス、成果物（PDF）の情報を一括で取得。
    *   **PDFアップロード**: `PdfUploadModal`でファイルが選択されると、`POST /api/v1/plan-deliverables`を呼び出す。リクエストボディには`plan_cycle_id`と`deliverable_type`を含める。
    *   **PDF削除/再アップロード**: 同様に、`DELETE`や`PATCH`メソッドで対応するエンドポイントを呼び出す。
*   **画面遷移**:
    *   ヘッダーのダッシュボードリンク → `/dashboard`へ遷移。

*   `BillingStatusPanel`: 事業所の課金ステータス（月額プラン/無料プラン、利用者数、Stripe顧客情報）を表示するコンポーネント。
    *   `GET /api/v1/offices/{office_id}/billing`: 課金情報を取得。
*   `SubscriptionRegisterButton`: Stripe Checkoutを開始するボタン。`service_administrator`のみ表示。
    *   `POST /api/v1/offices/{office_id}/billing/session`: Stripe Checkoutセッションを作成し、返却されたURLへリダイレクト。
*   `StripeCustomerPortalLink`: Stripeカスタマーポータルへのリンク。支払い方法変更や請求書確認、解約などを行う。
    *   `GET /api/v1/offices/{office_id}/billing/portal`: ポータルURLを取得。
*   **主要ロジックとAPI連携**:
    *   利用者追加時に上限を超えた場合、`402 Payment Required`を受けて自動的に決済パネルへ遷移。
    *   決済完了後はWebhook経由で`billing_status`が`active`に更新される。

*   **画面構成**:
    *   `StaffList`: 事業所に所属するスタッフの一覧。権限変更や削除ボタンを含む。
    *   `RequestList`: 権限変更などの申請一覧。承認/却下ボタンを含む。
    *   `OfficeInfoForm`: 事業所情報の編集フォーム。
*   **主要ロジックとAPI連携**:
    *   `GET /api/v1/offices/{office_id}/staff`: スタッフ一覧を取得。
    *   `GET /api/v1/offices/{office_id}/role-requests`: 申請一覧を取得。
    *   `PATCH /api/v1/staff/{staff_id}/role`: スタッフの権限を変更。
    *   `PATCH /api/v1/role-requests/{request_id}`: 申請を承認または却下。
    *   `PATCH /api/v1/offices/{office_id}`: 事業所情報を更新。
*   **画面遷移**:
    *   このページは`service_administrator`のみがヘッダー等から遷移可能。

#### **d. プロフィールページ (`/profile`)**

*   **画面構成**:
    *   `ProfileForm`: 自身の名前、メールアドレスの編集フォーム。
    *   `RoleChangeRequestForm`: 権限昇格を申請するためのフォームとボタン。
    *   `LeaveOfficeButton`: 事業所からの退会を申請するボタン。
*   **主要ロジックとAPI連携**:
    *   `GET /api/v1/staff/me`: 自身の情報を取得し、フォームの初期値に設定。
    *   `PATCH /api/v1/staff/me`: 自身のプロフィール情報を更新。
    *   `POST /api/v1/role-requests`: 権限変更を申請。
*   **画面遷移**:
    *   ヘッダーのプロフィールリンクから遷移。

もちろん、承知いたしました。
フロントエンドの設計をさらに詳細化し、Next.js 14以降のApp Routerにおける**サーバーコンポーネント**と**クライアントコンポーネント**の使い分けを明確にした、より具体的な技術設計書を作成します。

---

### **フロントエンド詳細設計書: ケイカくん**

**1. サーバーコンポーネントとクライアントコンポーネントの判断基準**

Next.jsのパフォーマンスを最大化するため、以下の基準でコンポーネントの種類を判断します。これは「アイランドアーキテクチャ」の考え方に基づき、**クライアントに送信するJavaScriptの量を最小限に抑える**ことを目的とします。

*   **サーバーコンポーネント (デフォルト)**
    *   **役割**: データの取得、バックエンドAPIやデータベースへの直接アクセス、機密情報（APIキー等）の取り扱い、静的なUIの表示。
    *   **判断基準**:
        *   `async/await`を使ってデータを直接取得する必要があるか？
        *   ユーザーのインタラクション（クリック、入力など）が不要か？
        *   `useState`や`useEffect`などのフックが不要か？
        *   **→ 上記に当てはまる場合、サーバーコンポーネントとします。**

*   **クライアントコンポーネント (`'use client'`)**
    *   **役割**: ユーザーのインタラクション（イベントハンドラ）、状態（State）やライフサイクルの管理、ブラウザAPI（`localStorage`等）へのアクセス。
    *   **判断基準**:
        *   `onClick`, `onChange`などのイベントハンドラが必要か？
        *   `useState`, `useEffect`, `useContext`などのフックが必要か？
        *   ブラウザ専用のAPIを利用するか？
        *   **→ 上記のいずれか一つでも当てはまる場合、クライアントコンポーネントとします。**

**設計方針**: **可能な限りサーバーコンポーネントとし、インタラクティブ性が必要な部分のみをクライアントコンポーネントとして切り出す（コンポーネントツリーの末端に配置する）。**

---

**2. 画面別コンポーネント詳細設計**

#### **a. ダッシュボード (`/dashboard`)**

| コンポーネント | コンポーネント種別 | 理由・役割 | 主要ロジック・API |
| :--- | :--- | :--- | :--- |
| **`app/dashboard/page.tsx`** | **サーバー** | ページのルート。サーバーサイドで直接データを取得し、子コンポーネントに渡す責務を持つ。 | `await api.dashboard.getSummaries()`<br>`await api.staff.getMe()` |
| `DashboardHeader.tsx` | サーバー | スタッフ名や役割など、propsで渡された静的な情報を表示するだけ。 | (Propsを受け取るのみ) |
| `CreateRecipientButton.tsx`| **クライアント** | `useRouter`フックを使ってページ遷移を行うため、インタラクティブな要素。 | `router.push('/recipients/new')` |
| `DashboardTable.tsx` | サーバー | データリストの骨格を表示する。テーブル自体は静的で、インタラクティブな部分は子コンポーネントに委任。 | `summaries`データをpropsで受け取り、`map`で`DashboardTableRow`を描画。 |
| `DashboardTableRow.tsx` | サーバー | 1行分の静的なセル（氏名、進捗等）を表示。インタラクティブなフォームは更に子コンポーネント化。 | (Propsを受け取るのみ) |
| `MonitoringDeadlineForm.tsx`| **クライアント** | `useState`で入力値を管理し、`onSubmit`でAPIを呼び出すフォーム。 | `useState`, `react-hook-form`を利用。<br>`PATCH /api/v1/support-statuses/{id}` |

#### **b. 個別支援計画ページ (`/recipients/[recipient_id]/plan`)**

| コンポーネント | コンポーネント種別 | 理由・役割 | 主要ロジック・API |
| :--- | :--- | :--- | :--- |
| **`app/recipients/[id]/plan/page.tsx`** | **サーバー** | `params.id`を基に、特定の利用者の計画データをサーバーサイドで全て取得する。 | `await api.recipients.getPlanById(params.id)` |
| `PlanCycleTable.tsx` | サーバー | 全計画サイクルのテーブル構造を描画する。インタラクティブなセルは子コンポーネントに分離。 | 計画データをpropsで受け取り、`map`で`PlanCycleTableRow`を描画。 |
| `PlanStepCell.tsx` | **クライアント** | セルクリックでモーダルを開く`onClick`イベントを持つため。モーダルの開閉状態を`useState`で管理。 | `useState(false)`でモーダル表示を管理。 |
| `PdfUploadModal.tsx` | **クライアント** | ファイル選択(`onChange`)、アップロード状態(`useState`)、送信ボタン(`onClick`)など、インタラクションの塊。 | `useState`でファイルやローディング状態を管理。<br>`POST /api/v1/plan-deliverables` |

#### **c. 認証ページ (`/signin`, `/signup`)**

| コンポーネント | コンポーネント種別 | 理由・役割 | 主要ロジック・API |
| :--- | :--- | :--- | :--- |
| **`app/(auth-pages)/signin/page.tsx`** | **クライアント** | メールアドレス・パスワード入力フォーム。`useState`と`onSubmit`が必須。 | `react-hook-form`と`zod`で入力値を管理・検証。<br>`supabase.auth.signInWithPassword(...)` |
| **`app/(auth-pages)/signup/page.tsx`** | **クライアント** | 新規登録フォーム。`signin`と同様に、状態とイベントハンドラを持つ。 | `react-hook-form`と`zod`を利用。<br>`supabase.auth.signUp(...)` |

#### **d. 事務所管理ページ (`/admin/office_management`)**

| コンポーネント | コンポーネント種別 | 理由・役割 | 主要ロジック・API |
| :--- | :--- | :--- | :--- |
| **`app/admin/office_management/page.tsx`**| **サーバー** | このページで必要となる複数のデータ（スタッフ一覧、申請一覧）を`Promise.all`で並行取得する。 | `await Promise.all([api.office.getStaff(), api.office.getRequests()])` |
| `StaffList.tsx` | サーバー | スタッフ一覧の静的な部分を表示。権限変更などのボタンはクライアントコンポーネントとして分離。 | (Propsを受け取るのみ) |
| `ChangeRoleButton.tsx` | **クライアント** | クリックすると確認モーダルを開き、承認されるとAPIを叩く。`useState`, `onClick`が必須。 | `useState`でモーダル状態管理。<br>`PATCH /api/v1/staff/{id}/role` |
| `ApproveRequestButton.tsx` | **クライアント** | 「承認」「却下」ボタン。`ChangeRoleButton`と同様にインタラクティブな要素。 | `PATCH /api/v1/role-requests/{id}` |

---

### **3. API（ロジック）と画面遷移**

**遷移の基本ルール**:
*   単純なページ移動は、Next.jsの`<Link>`コンポーネント（サーバーコンポーネントでも使用可）を利用する。
*   処理を伴うページ移動（例：ログイン成功後のダッシュボードへの移動）は、クライアントコンポーネント内で`useRouter`フックの`router.push()`または`router.replace()`を利用する。

| 起点アクション | 遷移トリガー | 遷移先URL | API連携 / 備考 |
| :--- | :--- | :--- | :--- |
| ログインフォームの送信 | `onSubmit`成功後 | `/dashboard` | `POST /api/v1/login`の成功レスポンスを受けて`router.push()` |
| 利用者作成ボタン | `onClick` | `/recipients/new` | `<Link>`コンポーネントまたは`router.push()`で遷移 |
| ダッシュボードの利用者名クリック | `onClick` | `/recipients/{id}/plan` | `<Link href={/recipients/${id}/plan}>`で遷移 |
| 権限変更の申請 | `onSubmit`成功後 | `/profile` (またはトースト通知) | `POST /api/v1/role-requests`の成功後、UIでフィードバック |


*
**
***
****
*****
******
*******

### **2. バックエンド設計 (FastAPI)**

**2.1. APIエンドポイント設計 (v1)**

| リソース | エンドポイント | メソッド | 役割 | 主な権限 |
| :--- | :--- | :--- | :--- | :--- |
| **認証** | `/api/v1/login` | `POST` | ログイン処理 | 全員 |
| | `/api/v1/signup` | `POST` | スタッフ新規登録 | 全員 |
| **スタッフ** | `/api/v1/staff/me` | `GET` `PATCH` | 自身の情報を取得・更新 | ログインユーザー |
| | `/api/v1/staff` | `GET` | (Admin用)全スタッフ一覧取得 | `service_administrator` |
| | `/api/v1/staff/{staff_id}` | `DELETE` | (Admin用)スタッフを削除 | `service_administrator` |
| **事業所** | `/api/v1/offices` | `POST` | 事業所の新規作成 | `service_administrator` |
| | `/api/v1/offices/{office_id}` | `GET` `PATCH` | 事業所情報の取得・更新 | `manager`以上 |
| **利用者** | `/api/v1/recipients` | `POST` `GET` | 利用者の新規作成・一覧取得 | `manager`以上 (作成は承認フロー) |
| | `/api/v1/recipients/{id}` | `GET` `PATCH` `DELETE` | 利用者情報の取得・更新・削除 | `manager`以上 (更新・削除は承認フロー) |
| **計画サイクル**| `/api/v1/recipients/{id}/plan`| `GET` | 利用者の全計画情報を取得 | `employee`以上 |
| | `/api/v1/plan-cycles` | `POST` | (内部用)新しい計画サイクルを作成 | - |
| **成果物(PDF)**| `/api/v1/plan-deliverables` | `POST` | PDFをアップロード | `manager`以上 (承認フロー) |
| **ダッシュボード**| `/api/v1/dashboard/summaries`| `GET` | ダッシュボード用サマリー情報取得 | `employee`以上 |
| **権限変更** | `/api/v1/role-requests` | `POST` `GET` | 権限変更の申請・一覧取得 | `employee`以上 |
| | `/api/v1/role-requests/{id}` | `PATCH` | (Admin用)申請の承認・却下 | `service_administrator` |

**2.2. サービス層・CRUD層の役割と連携**

提供された「責務再定義」に基づき、各層は以下の役割を厳格に守る。

**例：個別支援計画の「署名済みPDF」がアップロードされ、次のサイクルが作成されるケース**

1.  **`api`層 (エンドポイント)**
    *   `POST /api/v1/plan-deliverables` がリクエストを受け取る。
    *   認証・認可をチェックし、リクエストボディ（ファイル、`plan_cycle_id`, `deliverable_type`）を検証する。
    *   **`services.support_plan.handle_final_plan_upload(...)`** を呼び出す。

2.  **`services`層 (ビジネスロジック)**
    *   `handle_final_plan_upload(db, ...)` が実行される。
    *   **トランザクションを開始する。**
    *   ① **ファイルの永続化**: アップロードされたPDFをS3等に保存する。
    *   ② **CRUD層呼び出し (成果物作成)**: `crud.plan_deliverable.create(db, ...)` を呼び出し、成果物レコードを作成。
    *   ③ **CRUD層呼び出し (ステータス更新)**: `crud.support_plan_status.update_to_completed(db, ...)` で、対応する`final_plan_signed`ステップを完了にする。
    *   ④ **ビジネスロジック**: ここで「次のサイクルを作成する」という判断を行う。
    *   ⑤ **CRUD層呼び出し (現サイクル更新)**: `crud.support_plan_cycle.update(db, current_cycle, {"is_latest_cycle": False})` で、現在のサイクルを「最新ではない」状態に更新。
    *   ⑥ **次のサイクルの初期状態を準備**: 次のサイクル（`cycle_count + 1`）のデータと、初期ステップ（`monitoring`から始まるリスト）を準備する。
    *   ⑦ **CRUD層呼び出し (次サイクル作成)**: `crud.support_plan_cycle.create_with_statuses(db, ...)` のような、**単純なデータ作成のみを行うCRUD関数**を呼び出す。
    *   **トランザクションをコミットする。**
    *   成功レスポンスを`api`層に返す。

3.  **`crud`層 (データベースアクセス)**
    *   `crud.plan_deliverable.create`: 受け取ったデータで`PlanDeliverable`レコードを1件作成するだけ。
    *   `crud.support_plan_status.update_to_completed`: 特定の`SupportPlanStatus`レコードの`completed`フラグを`True`にするだけ。
    *   `crud.support_plan_cycle.create_with_statuses`: **ビジネスロジックを持たない。** `services`層から渡されたサイクルデータとステータスのリストを、単純にDBにINSERTする処理だけを行う。

この構造により、ビジネス上の複雑なルールはすべて`services`層に集約され、`crud`層は再利用可能な単純なDB操作部品に徹することができる。


### **1. FastAPIの依存性注入(DI)が必要な箇所**

FastAPIの依存性注入（`Depends`）は、コードの再利用性を高め、ロジックを分離し、テストを容易にするための強力な機能です。主に以下の箇所で必須級となります。

#### **a. データベースセッションの取得 (`db: AsyncSession = Depends(get_db)`)**

*   **目的**: 全てのエンドポイントで、リクエストごとにデータベース接続（セッション）を払い出し、処理が終わったら確実にクローズするため。
*   **なぜ必要か**:
    *   APIのリクエストごとに独立したトランザクションを保証します。
    *   接続の開始と終了（`try...finally`での`close()`）のロジックを`get_db`関数に一元化でき、各エンドポイントのコードをクリーンに保てます。
    *   テスト時に、この`get_db`をモックのDBセッションに差し替えることが容易になります。

#### **b. 認証とユーザー情報の取得 (`current_user: models.Staff = Depends(get_current_staff)`)**

*   **目的**: エンドポイントが「ログインしているユーザー」を必要とする場合に、ヘッダーのJWTトークンなどを検証し、対応するユーザーのDBモデルを取得するため。
*   **なぜ必要か**:
    *   「トークンをデコードし、ユーザーIDを抽出し、DBからユーザー情報を取得する」という一連の認証ロジックを、全ての保護されたエンドポイントで再利用できます。
    *   エンドポイントのビジネスロジックは、「有効なユーザーが既に取得されている」という前提で処理を開始できます。

#### **c. 権限（ロール）の検証 (`current_user: models.Staff = Depends(get_current_manager_or_above)`)**

*   **目的**: 特定の役割（例: `manager`や`service_administrator`）を持つユーザーのみがアクセスできるエンドポイントを保護するため。
*   **なぜ必要か**:
    *   `get_current_manager_or_above`という依存関数は、内部で`get_current_staff`を呼び出し、取得したユーザーの`role`属性をチェックします。権限が不足していれば`HTTPException`を発生させます。
    *   これにより、各エンドポイントの内部に`if user.role != 'admin': ...`のような権限チェックのコードが散らばるのを防ぎます。

#### **d. 共有のクエリパラメータ (`pagination: dict = Depends(common_parameters)`)**

*   **目的**: 多くのエンドポイントで共通して使われるクエリパラメータ（例: `skip: int = 0`, `limit: int = 100`）の処理を共通化するため。
*   **なぜ必要か**: 一覧取得系のAPIで必須となるページネーションのロジックを、一つの依存関数にまとめることができます。

---

### **2. `__init__.py`の内容の例**

ご提示の要件定義書にある通り、`__init__.py`は、パッケージ内の各モジュールを「公開」し、クリーンな名前空間を提供するために非常に有効です。

#### **`app/crud/__init__.py` の例**

このファイルは、各CRUDモジュールで**インスタンス化されたCRUDオブジェクト**をインポートし、集約します。

```python
# app/crud/__init__.py

from .crud_staff import crud_staff
from .crud_office import crud_office
from .crud_welfare_recipient import crud_welfare_recipient
from .crud_support_plan_cycle import crud_support_plan_cycle
from .crud_support_plan_status import crud_support_plan_status
from .crud_plan_deliverable import crud_plan_deliverable

# これにより、他の場所からは `from app import crud` とインポートし、
# `crud.crud_staff` や `crud.crud_welfare_recipient` のようにアクセスできる。
```

#### **上記の`__init__.py`が参照するCRUDモジュールの例**

`crud_staff`オブジェクトは、具体的には以下のように定義され、インスタンス化されています。

```python
# app/crud/crud_staff.py

from app.crud.base import CRUDBase  # 汎用的なCRUD操作を持つ基本クラス
from app.models import Staff
from app.schemas import StaffCreate, StaffUpdate

class CRUDStaff(CRUDBase[Staff, StaffCreate, StaffUpdate]):
    # Staffモデルに特化したメソッドがあればここに定義
    pass

# このファイルでインスタンスを作成し、__init__.pyで公開する
crud_staff = CRUDStaff(Staff)
```

このパターンを`services`層にも適用することで、アプリケーション全体の依存関係が非常に見通し良く整理されます。

---

### **3. バックエンドの非同期処理は全て統一するかどうか**

**結論: 原則として、非同期処理（`async def`）に統一することを強く推奨します。**

FastAPIはASGIフレームワークであり、そのパフォーマンスは非同期I/Oによって最大限に引き出されます。中途半端に同期・非同期が混在すると、性能低下や予期せぬブロッキングの原因となります。

#### **判断基準**

*   **`async def` を使うべきケース（ほぼ全て）**:
    *   **I/Oバウンドな処理**: 処理の大部分が「待ち時間」であるもの。これらを`await`で待つことで、サーバーはその間に他のリクエストを処理できます。
        *   **データベースアクセス**: `await db.execute(...)`
        *   **外部API呼び出し**: `await client.get(...)` (例: GoogleカレンダーAPI)
        *   **ファイル読み書き**: `await aiofiles.open(...)`
    *   **必須要件**: データベースドライバは必ず**非同期対応のもの**（例: PostgreSQLなら`asyncpg`）を使用する必要があります。

*   **通常の`def`を使うべき例外的なケース**:
    *   **CPUバウンドな処理**: 「待ち時間」がなく、純粋にCPUの計算能力を長時間使用する処理。
        *   重い計算、複雑なデータ変換、画像の圧縮・リサイズなど。
    *   もしこのような処理を`async def`内で実行すると、イベントループ全体をブロックしてしまい、サーバー全体が応答不能になります。
    *   **解決策**: FastAPIでは、このような重い同期処理を`async def`内から安全に呼び出すための`run_in_threadpool`という仕組みが用意されています。

```python
from fastapi.concurrency import run_in_threadpool

def heavy_cpu_bound_task(data):
    # 時間のかかる計算処理
    return "result"

@router.post("/process")
async def process_data(data: dict):
    # CPUバウンドな処理を別スレッドで実行し、イベントループをブロックしない
    result = await run_in_threadpool(heavy_cpu_bound_task, data)
    return {"result": result}
```

#### **まとめ**

| 処理の種類 | 関数の定義 | 理由 |
| :--- | :--- | :--- |
| **APIエンドポイント** | `async def` | FastAPIの基本。I/O処理を待つため。 |
| **DBアクセス、外部API呼び出し** | `async def` | 典型的なI/Oバウンド処理。`await`が必須。 |
| **純粋な計算、データ加工** | `def` | CPUバウンド処理。イベントループをブロックしないため。 |
| **CPUバウンド処理の呼び出し** | `await run_in_threadpool(func, ...)` | `async`の世界から`def`の処理を安全に呼び出す。 |

したがって、あなたのアプリケーションのほとんどの関数（エンドポイント、サービス、CRUD）は`async def`で定義し、データベースアクセスは`await`を使って行う、という方針で統一するのが最もクリーンで高性能な設計となります。


### **根本的な課題：N+1クエリ問題**

まず、なぜローディング戦略が必要なのかを理解することが重要です。それは**「N+1クエリ問題」**を解決するためです。

**例：悪いコード（Lazy Loadの罠）**
ダッシュボードで、全利用者の名前とその最新の計画サイクルの開始日を表示したいとします。

```python
# services/dashboard_service.py (悪い例)
async def get_dashboard_summary(db: AsyncSession):
    # 1. まず全利用者のリストを取得する (★クエリ1回目)
    recipients = await crud.welfare_recipient.get_multi(db)
    
    summaries = []
    for r in recipients:
        # 2. ループの中で、各利用者の計画サイクルにアクセスする
        #    -> この瞬間に、利用者ごとに追加のクエリが発行されてしまう！(★クエリN回)
        latest_cycle = r.support_plan_cycles[0] if r.support_plan_cycles else None
        summaries.append({"name": r.full_name, "start_date": latest_cycle.plan_cycle_start_date})
    return summaries
```

このコードでは、50人の利用者がいれば、合計で **1 + 50 = 51回** のクエリがデータベースに発行されます。これは非常に非効率で、パフォーマンスのボトルネックとなります。

### **ローディング戦略の種類と設計パターン**

このN+1問題を解決するために、主に以下の**Eager Loading（即時読み込み）**戦略を使い分けます。

#### **1. `selectinload` 戦略**

*   **仕組み**: 2回の`SELECT`文を発行します。1回目で主となるモデル（例: `WelfareRecipient`）を全て取得し、2回目のクエリで、1回目で取得した全IDを使い`WHERE IN (...)`句で関連モデル（例: `SupportPlanCycle`）を全て一括で取得します。
*   **得意な状況**: **一対多 (one-to-many) / 多対多 (many-to-many)** のリレーションシップ。
*   **メリット**:
    *   N+1問題を効率的に解決する、最も一般的で推奨される方法です。
    *   発行されるSQLがシンプルで、データベースへの負荷も予測しやすいです。

**設計パターン：一覧表示画面（ダッシュボードなど）**

**状況**: 複数の親オブジェクトと、それぞれに紐づく子オブジェクトのリストを表示する。

**例**: `crud_welfare_recipient.py`
```python
# app/crud/crud_welfare_recipient.py
from sqlalchemy.orm import selectinload

class CRUDWelfareRecipient(Base):
    async def get_multi_with_latest_cycle(self, db: AsyncSession) -> List[WelfareRecipient]:
        result = await db.execute(
            select(self.model)
            .options(
                # WelfareRecipientに紐づくsupport_plan_cyclesをまとめて読み込む
                selectinload(self.model.support_plan_cycles)
            )
            .order_by(self.model.id)
        )
        return result.scalars().all()
```
この`get_multi_with_latest_cycle`を使えば、DBへのクエリは**常に2回**で済み、N+1問題は完全に解決します。

#### **2. `joinedload` 戦略**

*   **仕組み**: `LEFT OUTER JOIN`を使って、主となるモデルと関連モデルを**1回の`SELECT`文**でまとめて取得します。
*   **得意な状況**: **多対一 (many-to-one) / 一対一 (one-to-one)** のリレーションシップ。
*   **メリット**:
    *   DBへのラウンドトリップが1回で済むため、レイテンシが低い。
    *   `JOIN`したテーブルのカラムで`filter`や`order_by`をしたい場合に非常に有効。

**設計パターン：詳細表示画面 / 関連データでの絞り込み**

**状況**:
A. 1つの子オブジェクトとその親オブジェクトの情報を同時に取得したい。
B. 親オブジェクトの属性で絞り込みを行いたい。

**例 A**: `crud_support_plan_cycle.py`
```python
# app/crud/crud_support_plan_cycle.py
from sqlalchemy.orm import joinedload

class CRUDSupportPlanCycle(Base):
    async def get_with_recipient(self, db: AsyncSession, cycle_id: int) -> Optional[SupportPlanCycle]:
        result = await db.execute(
            select(self.model)
            .where(self.model.id == cycle_id)
            .options(
                # SupportPlanCycleに紐づくWelfareRecipientをJOINして取得
                joinedload(self.model.welfare_recipient)
            )
        )
        return result.scalars().first()
```

**例 B**: `crud_support_plan_cycle.py`
```python
# app/crud/crud_support_plan_cycle.py
class CRUDSupportPlanCycle(Base):
    async def get_cycles_for_recipient_name(self, db: AsyncSession, name: str) -> List[SupportPlanCycle]:
        result = await db.execute(
            select(self.model)
            .join(self.model.welfare_recipient) # 明示的にJOIN
            .where(WelfareRecipient.last_name == name)
            # joinedloadでもOK
            # .options(joinedload(self.model.welfare_recipient))
            # .where(WelfareRecipient.last_name == name)
        )
        return result.scalars().all()
```

#### **3. `raiseload` 戦略**

*   **仕組み**: 意図しないLazy Load（N+1問題を引き起こすアクセス）が発生した場合に、クエリを発行するのではなく**例外を発生**させます。
*   **得意な状況**: パフォーマンスが重要なAPIで、開発者に明示的なEager Loadを強制したい場合。
*   **メリット**:
    *   開発段階でパフォーマンス問題を確実に検知できます。
    *   APIのデータ取得の仕様を厳格に管理できます。

**設計パターン：パフォーマンスが重要なAPIの防衛策**

**状況**: ダッシュボードAPIなどで、意図せず関連オブジェクトにアクセスしてN+1問題が再発するのを防ぎたい。

**例**: `crud_welfare_recipient.py`
```python
# app/crud/crud_welfare_recipient.py
from sqlalchemy.orm import raiseload, selectinload

class CRUDWelfareRecipient(Base):
    async def get_multi_for_dashboard(self, db: AsyncSession) -> List[WelfareRecipient]:
        result = await db.execute(
            select(self.model)
            .options(
                # 計画サイクルとステータスは明確に読み込む
                selectinload(self.model.support_plan_cycles).selectinload(SupportPlanCycle.statuses),
                # それ以外の全ての関連オブジェクトへのアクセスは禁止
                raiseload("*")
            )
        )
        return result.scalars().all()
```
このコードでは、もしサービス層などで誤って`recipient.family_members`にアクセスしようとすると、DBにクエリが発行される代わりにエラーが発生し、問題をすぐに修正できます。

### **まとめ：『ケイカくん』におけるローディング戦略 設計指針**

| ユースケース | 推奨戦略 | 具体的な適用箇所 |
| :--- | :--- | :--- |
| **一覧表示** (ダッシュボード、利用者一覧) | `selectinload` | `WelfareRecipient`とその`support_plan_cycles`を取得する場合など、**一対多**のリスト表示。 |
| **詳細表示** (個別支援計画ページ) | `joinedload` | `SupportPlanCycle`とその親である`WelfareRecipient`を取得する場合など、**多対一**の同時取得。 |
| **関連データでの絞り込み** | `joinedload` or `join()` | 「特定の名前の利用者の計画サイクルを検索」など、JOIN先のテーブル情報で絞り込む場合。 |
| **パフォーマンス最優先のAPI** | `raiseload('*')` + 明示的な`selectinload`/`joinedload` | ダッシュボードAPIなど、レスポンス速度が重要で、かつ意図しないDBアクセスを防ぎたい場合。 |
| **単一オブジェクトの操作** | **指定なし (Lazy Load)** | 1つの`Staff`オブジェクトを更新するなど、関連データへのアクセスが不要な場合。戦略を指定する必要はない。 |