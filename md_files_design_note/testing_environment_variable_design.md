# テスト環境変数の設計 - TESTING=1とDATABASE_URL

## 問題の経緯

### 初期の問題
GitHub Actionsで以下の設定を使用していた：
```yaml
env:
  DATABASE_URL: ${{ secrets.PROD_DATABASE_URL }}  # 本番DB
  TEST_DATABASE_URL: ${{ secrets.TEST_DATABASE_URL }}
```

**問題点**:
- `TESTING=1`が設定されていない
- `session.py`が`DATABASE_URL`（本番DB）を参照する可能性

### 最初の修正（誤り）
```yaml
env:
  TESTING: "1"
  TEST_DATABASE_URL: ${{ secrets.TEST_DATABASE_URL }}
  # DATABASE_URLを削除
```

**新たな問題**:
```
pydantic_core._pydantic_core.ValidationError: 1 validation error for Settings
DATABASE_URL
  Field required [type=missing]
```

### 正しい修正
```yaml
env:
  TESTING: "1"
  DATABASE_URL: ${{ secrets.TEST_DATABASE_URL }}  # Settings検証用
  TEST_DATABASE_URL: ${{ secrets.TEST_DATABASE_URL }}
```

## なぜDATABASE_URLが必要か

### 1. Settingsクラスの必須フィールド

**app/core/config.py**:
```python
class Settings(BaseSettings):
    DATABASE_URL: str  # 必須フィールド（Optional[str]ではない）
```

### 2. Settingsの初期化タイミング
```python
# app/core/config.py（最後の行）
settings = Settings()  # アプリ起動時に必ず実行される
```

アプリケーション起動時（テスト実行開始前）に`Settings`が初期化されるため、`DATABASE_URL`が環境変数に存在しないとValidationErrorが発生します。

### 3. session.pyの分岐ロジック

**app/db/session.py**:
```python
if os.getenv("TESTING") == "1":
    ASYNC_DATABASE_URL = os.getenv("TEST_DATABASE_URL")  # ← これを使用
else:
    ASYNC_DATABASE_URL = os.getenv("DATABASE_URL")  # ← 使用されない
```

`TESTING=1`が設定されている場合、`session.py`は`TEST_DATABASE_URL`を使用するため、`DATABASE_URL`の値は実際には参照されません。

## 正しい設計

### GitHub Actions（テスト環境）
```yaml
env:
  TESTING: "1"                                      # session.pyの分岐制御
  DATABASE_URL: ${{ secrets.TEST_DATABASE_URL }}   # Settings検証用（形式的）
  TEST_DATABASE_URL: ${{ secrets.TEST_DATABASE_URL }}  # 実際に使用される
```

### ローカル開発環境
```bash
# .env
DATABASE_URL=postgresql+asyncpg://localhost/keikakun_dev
TEST_DATABASE_URL=postgresql+asyncpg://localhost/keikakun_dev_test
```

```bash
# テスト実行時
TESTING=1 pytest
```

### 本番環境
```bash
# 環境変数
DATABASE_URL=postgresql+asyncpg://prod_db_url  # 本番DB
# TEST_DATABASE_URLは不要
# TESTINGは未設定
```

## 環境変数の優先順位

| 環境 | TESTING | DATABASE_URL | TEST_DATABASE_URL | 実際に使用されるDB |
|------|---------|--------------|-------------------|-------------------|
| 本番 | 未設定 | 本番DB | - | DATABASE_URL（本番DB） |
| ローカル開発 | 未設定 | 開発DB | テストDB | DATABASE_URL（開発DB） |
| ローカルテスト | "1" | 開発DB | テストDB | TEST_DATABASE_URL |
| GitHub Actions | "1" | テストDB | テストDB | TEST_DATABASE_URL |

## なぜこの設計なのか

### 1. Settings検証の要件
Pydanticの`BaseSettings`は、必須フィールドが環境変数に存在しない場合、アプリ起動時に即座にエラーを発生させます。これは安全機構として設計されています。

### 2. 後方互換性
既存のコードが`settings.DATABASE_URL`を参照している可能性があるため、フィールドを`Optional[str]`に変更すると影響範囲が大きくなります。

### 3. テスト環境の明示
`TESTING=1`という明示的なフラグにより、テスト環境であることが一目瞭然になります。

## 影響範囲の分析

### DATABASE_URLをOptional[str]に変更した場合

**変更が必要な箇所**:
1. `app/core/config.py` - `DATABASE_URL: Optional[str] = None`
2. `app/db/session.py` - Noneチェック追加
3. すべての`settings.DATABASE_URL`参照箇所 - Noneチェック追加
4. Alembicの設定 - フォールバック処理追加

**リスク**:
- 本番環境で`DATABASE_URL`が未設定の場合、起動時ではなく実行時にエラー
- 設定ミスの早期発見が困難になる
- 既存コードへの影響が広範囲

### 現在の設計（DATABASE_URL必須 + TESTING分岐）

**メリット**:
- 設定ミスを起動時に即座に検出
- 既存コードへの影響なし
- テスト環境の明示的な区別

**デメリット**:
- GitHub Actionsで`DATABASE_URL`を形式的に設定する必要がある

## 結論

**現在の設計（DATABASE_URL必須 + TESTING=1分岐）が最適です。**

理由:
1. 変更範囲が最小（GitHub Actionsの設定のみ）
2. 既存コードへの影響なし
3. 設定ミスの早期検出が可能
4. テスト環境の明示的な区別

GitHub Actionsで`DATABASE_URL`を形式的に設定する必要はありますが、これは小さなコストです。`TESTING=1`により`session.py`が確実に`TEST_DATABASE_URL`を使用するため、安全性も担保されています。

## ベストプラクティス

### GitHub Actionsでテスト実行する場合
```yaml
env:
  TESTING: "1"                                   # 必須
  DATABASE_URL: ${{ secrets.TEST_DATABASE_URL }} # Settings検証用
  TEST_DATABASE_URL: ${{ secrets.TEST_DATABASE_URL }}  # 実際に使用
```

### ローカルでテスト実行する場合
```bash
TESTING=1 pytest
```

### 本番デプロイ
```bash
# TESTINGは設定しない
# DATABASE_URLに本番DBのURLを設定
```

**最終更新**: 2026-01-22
**設計確定**: ✅
