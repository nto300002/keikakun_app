# Keikakun-API におけるインポート規約

このドキュメントでは、`keikakun_api` 内、特に `services` 層と `crud` 層におけるモジュールのインポート方法に関するベストプラクティスを定義します。

## 課題

現在、モジュールのインポート方法に一貫性がなく、以下のような問題が発生しています。

- `AttributeError: module 'app.crud' has no attribute '...'` といったエラーの発生
- 循環参照のリスク
- コードの可読性の低下

## 規約：CRUD モジュールのインポートと利用

### 1. インポートは `from app import crud` に統一する

`services` 層など、他の場所から CRUD 操作を呼び出す際は、必ずトップレベルの `crud` パッケージをインポートします。

```python
# 良い例
from app import crud

# 悪い例
from app.crud import crud_service_recipient
from app.crud.crud_staff import crud_staff
```

### 2. 利用時は `crud.オブジェクト名.メソッド` 形式で呼び出す

`app/crud/__init__.py` ファイルが、各 CRUD モジュールからインスタンス化されたオブジェクトを公開しています。このため、利用時は必ず `crud` パッケージを経由してアクセスします。

`__init__.py` で公開されているオブジェクト名（`crud_staff`, `crud_service_recipient` など）を正確に指定してください。

```python
# __init__.py の内容
# from .crud_staff import crud_staff
# from .crud_service_recipient import crud_service_recipient
# ...

# サービス層での利用例
async def some_service_function(db: AsyncSession):
    # 良い例
    recipients = await crud.crud_service_recipient.get_multi(db)
    staff_member = await crud.crud_staff.get(db, id=1)

    # 悪い例
    # 'service_recipient' という名前では公開されていないため AttributeError になる
    recipients = await crud.service_recipient.get_multi(db)
```

### 3. なぜこの規約か？

- **一元管理:** `app/crud/__init__.py` を見れば、アプリケーション全体で利用可能なすべての CRUD オブジェクトを一覧できます。これにより、コードベースの見通しが良くなります。
- **循環参照の防止:** `services` 層は `crud` パッケージのみに依存し、その逆は起こらないという一方向の依存関係を徹底することで、Python で頻発する循環参照エラーを未然に防ぎます。
- **統一性:** コードベース全体でインポートと呼び出しのスタイルを統一することで、可読性とメンテナンス性を向上させます。

---

# バックエンドにおける各層の責務再定義

## 1. はじめに

度重なる `AttributeError` や `ModuleNotFoundError` は、バックエンドの各層（api, services, crud, schemas）の役割分担が曖昧なことに起因する。
本ドキュメントでは、それぞれの責務を明確に定義し、現状のコードがどのようにその責務から逸脱しているかを具体的に指摘する。今後のリファクタリングは、この定義に基づいて進めるものとする。

## 2. 各層の責務定義

### a. `api` 層 (エンドポイント)

- **責務**:
  - HTTP リクエストの受付とレスポンスの返却。
  - パスパラメータ、クエリパラメータ、リクエストボディの検証。
  - 認証・認可（`Depends` を使用）。
  - 対応する `services` 層のメソッドを呼び出し、結果をクライアントに返す。
- **禁止事項**:
  - ビジネスロジックの実装。
  - `crud` 層の直接呼び出し（必ず `services` 層を経由する）。

### b. `services` 層 (ビジネスロジック)

- **責務**:
  - アプリケーション固有のビジネスルールやユースケースを実装する。
  - 複数の `crud` 層のメソッドを組み合わせて、一連のビジネスプロセスをオーケストレーションする。
  - トランザクション管理。
  - `api` 層や他の `services` 層に返すためのデータ構造（DTO）を生成する。
- **禁止事項**:
  - データベースのテーブル構造に直接依存した処理（SQL 文の組み立てなど）。それは `crud` 層の役割。

### c. `crud` 層 (データベースアクセス)

- **責務**:
  - **単一のモデル（テーブル）に対する**、基本的な CRUD（Create, Read, Update, Delete）操作のみを提供する。
  - データベースとのやり取りを抽象化する。
- **禁止事項**:
  - ビジネスロジック（例：「ユーザーが A プランの場合、B という関連データも作る」など）の実装。
  - 複数のモデルにまたがる複雑な更新処理。それは `services` 層の責務。

### d. `schemas` 層 (データ構造定義)

- **責務**:
  - API の入出力（`response_model`）や、リクエストボディの型定義。
  - `services` 層と `api` 層など、層間でデータをやり取りするための厳格な型定義（DTO: Data Transfer Object）を提供する。
- **禁止事項**:
  - バリデーション以外のロジックの実装。

---

## 3. 責務が曖昧なコードの具体例

### ケース 1: `crud` 層の責務逸脱

- **ファイル**: `keikakun_api/app/crud/crud_support_plan.py`
- **関数**: `create_next_cycle_with_initial_statuses`

```python
    async def create_next_cycle_with_initial_statuses(
        # ...
    ) -> SupportPlanCycle:
        # ...

        # (問題1) 現在のサイクルのis_latest_cycleをFalseに更新している
        #      -> 責務外。これは呼び出し元のservices層が担当すべき
        current_cycle.is_latest_cycle = False
        db.add(current_cycle)

        # ...

        # (問題2) 次のサイクルの初期ステップを判断するビジネスロジック
        #      -> サイクル2以降はモニタリングから、というルールはservices層にあるべき
        initial_steps = [
            SupportPlanStepTypeEnum.MONITORING,
            # ...
        ]
        for step_type in initial_steps:
            status = SupportPlanStatus(
                plan_cycle_id=new_cycle.id, step_type=step_type, completed=False
            )
            db.add(status)
```

- **曖昧さの核**:
  - この関数は「新しいサイクルを作る」という CRUD の責務を超え、「現在のサイクルを更新する」「次のサイクルの初期状態を決める」というビジネスロジックを持ってしまっている。
  - **あるべき姿**: `services` 層がこの関数を呼び出す前に、必要なデータをすべて準備し、現在のサイクルの更新も `services` 層が明示的に行うべき。`crud` 層は渡されたデータで新しいサイクルを作るだけに徹するべきである。

### ケース 2: `services` 層と `schemas` 層の連携不足

- **ファイル**: `keikakun_api/app/services/dashboard_service.py`
- **関数**: `get_summaries_for_staff_offices`
- **エラー**: `AttributeError: 'DashboardSummary' object has no attribute 'recipient_name'`

```python
async def get_summaries_for_staff_offices(
    db: AsyncSession, staff: models.Staff
) -> List[schemas.DashboardSummary]: # 戻り値の型定義
    # ...
    summaries = await asyncio.gather(*summary_tasks)

    # (問題) summaries（DashboardSummaryのリスト）に 'recipient_name' が
    #        存在すると信じ込んでソートしようとしている。
    #        しかし、DashboardSummaryスキーマにその属性は定義されていない。
    summaries.sort(key=lambda s: s.recipient_name if s.recipient_name else "")
    return summaries
```

- **曖昧さの核**:
  - `services` 層が、`schemas.DashboardSummary` というデータ構造（契約）を正しく守らずに実装を進めてしまった。
  - **あるべき姿**: `services` 層は、自らが返すデータの型（この場合は `List[schemas.DashboardSummary]`）を厳密に守る責任がある。もし利用者名が必要なら、`DashboardSummary` スキーマ自体に `recipient_name: str` を追加するか、あるいは利用者名を含む別のスキーマ（例: `DashboardData`）を定義し、それを返すように関数のシグネチャ（型定義）を変更する必要があった。
