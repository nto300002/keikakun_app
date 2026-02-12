# Git戦略とテスト戦略

## 概要

Keikakun APIプロジェクトにおけるGitブランチ戦略、テスト方針、カバレッジについて解説します。

---

## 1. Gitブランチ戦略

### 1.1 採用戦略: **GitHub Flow（簡略版）**

小規模チーム（1-3名）かつ高速デプロイを重視するため、シンプルなブランチ戦略を採用しています。

```
main (保護ブランチ)
  ↑
  └── feature/xxx (機能開発ブランチ)
```

### 1.2 ブランチ構成

| ブランチ | 役割 | 保護設定 | デプロイ先 |
|---------|------|---------|-----------|
| **main** | 本番環境と同期 | ✅ Protected | Google Cloud Run (本番) |
| **develop** | 開発統合用（オプション） | - | なし |
| **feature/xxx** | 機能開発 | - | ローカル |
| **fix/xxx** | バグ修正 | - | ローカル |

### 1.3 ワークフロー

```bash
# 1. 機能開発開始
git checkout main
git pull origin main
git checkout -b feature/add-notification

# 2. 開発 + コミット
git add .
git commit -m "feat: Web Push通知機能追加

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
"

# 3. プッシュ前にローカルでテスト
docker exec keikakun_app-backend-1 pytest tests/ -v

# 4. プルリクエスト作成
git push origin feature/add-notification
gh pr create --title "feat: Web Push通知機能追加" --body "..."

# 5. レビュー後、mainにマージ
gh pr merge --squash

# 6. mainへのマージで自動デプロイ（GitHub Actions）
```

### 1.4 mainブランチ保護設定

**推奨設定**:
- ✅ Require pull request before merging
- ✅ Require status checks to pass (pytest, eslint)
- ✅ Require branches to be up to date before merging
- ✅ Require conversation resolution before merging

---

## 2. GitHub Actions CI/CDフロー

### 2.1 トリガー設定

#### Backend CD (.github/workflows/cd-backend.yml)

```yaml
on:
  push:
    branches:
      - main  # mainへのpushで本番デプロイ
```

**フロー**:
1. Python 3.12セットアップ
2. 依存関係インストール (`requirements.txt`, `requirements-dev.txt`)
3. **pytest実行** (全テスト155ファイル)
4. テスト成功 → Cloud Build経由でCloud Runデプロイ
5. テスト失敗 → デプロイ中断

#### Frontend CI (.github/workflows/ci-frontend.yml)

```yaml
on:
  push:
    branches: [main, develop]
    paths:
      - 'k_front/**'
  pull_request:
    branches: [main, develop]
```

**フロー**:
1. Node.js 20セットアップ
2. ESLint実行 (`npm run lint`)
3. TypeScript型チェック (`tsc --noEmit`)
4. Next.jsビルド (`npm run build`)

#### Security Check (.github/workflows/security-check.yml)

```yaml
on:
  push:
    branches: [main, develop]
  schedule:
    - cron: '0 9 * * 1'  # 毎週月曜日9時(UTC)
```

**フロー**:
- **Frontend**: OSV-Scanner (脆弱性スキャン), npm audit
- **Backend**: safety check, pip-audit

### 2.2 デプロイゲート

```
┌─────────────────┐
│ git push main   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ GitHub Actions  │
│   - pytest      │ ← テスト失敗でデプロイ中断
│   - 155 tests   │
└────────┬────────┘
         │ ✅ Pass
         ▼
┌─────────────────┐
│  Cloud Build    │
│  - Docker build │
│  - Deploy       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Cloud Run      │
│  (本番環境)      │
└─────────────────┘
```

**重要**: pytestが失敗すると、デプロイは実行されません。これにより**不具合のある状態が本番に到達するリスクを最小化**しています。

---

## 3. テスト戦略

### 3.1 テスト実行環境

**Docker環境でのテスト実行**:
```bash
docker exec keikakun_app-backend-1 pytest tests/ -v
```

**メリット**:
- 本番環境と同じPython 3.12 + 依存関係
- PostgreSQL接続のテスト
- 環境変数の隔離
- CI/CD環境との一貫性

### 3.2 テスト構成

**テストファイル数**: 155ファイル

```
tests/
├── api/              # APIエンドポイントテスト (35+ tests)
│   ├── test_billing_integration.py
│   ├── test_billing.py
│   └── v1/
│       ├── test_approval_request.py
│       ├── test_auth.py
│       ├── test_calendar_events.py
│       ├── test_inquiry.py
│       ├── test_message.py
│       ├── test_push_subscription.py
│       ├── test_staff_crud.py
│       ├── test_staff_profile.py
│       └── test_support_plans.py
│
├── crud/             # CRUD層テスト (25+ tests)
│   ├── test_crud_billing.py
│   ├── test_crud_assessment.py
│   ├── test_crud_calendar_event.py
│   └── test_crud_staff.py
│
├── services/         # サービス層テスト (15+ tests)
│   ├── test_billing_service.py
│   ├── test_calendar_service.py
│   ├── test_support_plan_service.py
│   └── test_welfare_recipient_service.py
│
├── models/           # モデル層テスト (15+ tests)
│   ├── test_assessment_models.py
│   ├── test_calendar_events_model.py
│   └── test_staff_model.py
│
├── security/         # セキュリティテスト (4+ tests)
│   ├── test_assessment_security.py
│   ├── test_password_reset_security.py
│   ├── test_rate_limiting.py
│   └── test_staff_profile_security.py
│
├── integration/      # 統合テスト (8+ tests)
│   ├── test_calendar_event_auto_creation.py
│   ├── test_password_reset_flow.py
│   ├── test_role_change_flow.py
│   └── test_employee_restriction_flow.py
│
├── tasks/            # バックグラウンドタスクテスト (6+ tests)
│   ├── test_billing_check.py
│   ├── test_deadline_notification.py
│   └── test_deadline_notification_web_push.py
│
├── core/             # コア機能テスト (4+ tests)
│   ├── test_storage.py
│   ├── test_mfa_security.py
│   └── test_password_breach_check.py
│
└── performance/      # パフォーマンステスト
    └── test_staff_profile_performance.py
```

### 3.3 テストレベル別カバレッジ

| テストレベル | カバレッジ | 具体例 |
|------------|----------|--------|
| **Unit Tests** | ✅ 高い | CRUD操作、バリデーション、暗号化 |
| **Integration Tests** | ✅ 高い | API → Service → CRUD → DB の一連の流れ |
| **Security Tests** | ✅ 高い | SQL injection、XSS、認可チェック、Rate limiting |
| **End-to-End Tests** | ⚠️ 部分的 | パスワードリセットフロー、カレンダー連携 |
| **Performance Tests** | ⚠️ 最小限 | スタッフプロフィール取得のN+1問題検証 |

### 3.4 テスト設計方針

#### 3.4.1 4層アーキテクチャへの対応

```python
# ✅ Good: 各層を独立してテスト
# CRUD層テスト
async def test_crud_billing_get_by_office_id(db_session):
    billing = await crud.billing.get_by_office_id(db=db_session, office_id=office_id)
    assert billing.office_id == office_id

# Service層テスト（CRUDをモック）
@patch('app.crud.billing.get_by_office_id')
async def test_billing_service_logic(mock_get):
    # ビジネスロジックのテスト
    ...

# API層テスト（統合テスト）
async def test_get_billing_status(client, auth_headers):
    response = client.get("/api/v1/billing/status", headers=auth_headers)
    assert response.status_code == 200
```

#### 3.4.2 セキュリティテストパターン

すべてのミューテーションAPIで以下をテスト:

```python
# 1. SQL Injection防止
async def test_sql_injection_prevention():
    malicious_input = "'; DROP TABLE staffs; --"
    response = client.post("/api/v1/staff", json={"name": malicious_input})
    # Pydanticバリデーションで弾かれる、またはエスケープされる

# 2. XSS防止
async def test_xss_prevention():
    xss_payload = "<script>alert('XSS')</script>"
    response = client.post("/api/v1/staff", json={"name": xss_payload})
    # HTMLエスケープされている

# 3. 認可チェック
async def test_unauthorized_access():
    # 他の事務所のデータにアクセス
    response = client.get("/api/v1/billing/status", headers=other_office_headers)
    assert response.status_code == 403
```

#### 3.4.3 非同期テスト対応

```python
# pytest.ini設定
[pytest]
asyncio_mode = auto  # 自動でasyncio対応

# テストコード
@pytest.mark.asyncio
async def test_async_endpoint():
    async with AsyncClient(app=app, base_url="http://test") as ac:
        response = await ac.get("/api/v1/staff")
    assert response.status_code == 200
```

---

## 4. カバレッジ状況

### 4.1 現状

**カバレッジツール**: 現在は未導入

**代わりの品質保証**:
- ✅ 155テストファイルによる幅広いカバレッジ
- ✅ GitHub Actionsでの全テスト自動実行
- ✅ mainマージ前の必須チェック
- ✅ セキュリティ特化テスト（SQL injection、XSS、認可）

### 4.2 推定カバレッジ（手動評価）

| レイヤー | 推定カバレッジ | 根拠 |
|---------|--------------|------|
| **API層** | 85-90% | 主要エンドポイント（認証、課金、カレンダー、個別支援計画）は全てテスト済み |
| **Service層** | 80-85% | ビジネスロジックの複雑な部分（課金、カレンダー同期）はテスト済み |
| **CRUD層** | 90-95% | 基本的なCRUD操作は全てテスト済み |
| **Models層** | 95%+ | モデル定義、バリデーション、暗号化機能は網羅的にテスト |
| **Security** | 90%+ | 全ての認証・認可・Rate limiting・入力検証をテスト |

### 4.3 カバレッジ導入計画（将来）

**pytest-covの導入**:
```bash
# インストール
pip install pytest-cov

# 実行
docker exec keikakun_app-backend-1 pytest tests/ --cov=app --cov-report=html --cov-report=term

# カバレッジレポート
# htmlcov/index.html にブラウザでアクセス
```

**GitHub Actionsへの統合**:
```yaml
- name: Run Pytest with Coverage
  run: |
    pytest tests/ --cov=app --cov-report=xml --cov-report=term

- name: Upload coverage to Codecov
  uses: codecov/codecov-action@v3
  with:
    file: ./coverage.xml
```

**目標カバレッジ**:
- **総合カバレッジ**: 80%以上
- **重要パス（課金、認証）**: 95%以上
- **新規コード**: 85%以上（PRごとにチェック）

---

## 5. テストデータ管理

### 5.1 is_test_data フラグ

本番環境でのテストデータ混入を防ぐため、全てのモデルに`is_test_data`フラグを実装:

```python
# app/models/base.py
class Base(DeclarativeBase):
    id: Mapped[UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid4
    )
    is_test_data: Mapped[bool] = mapped_column(
        Boolean,
        default=False,
        nullable=False,
        index=True
    )
```

**テスト環境での設定**:
```python
@pytest_asyncio.fixture
async def test_office(db_session):
    office = Office(
        name="テスト事業所",
        is_test_data=True  # 必須
    )
    db_session.add(office)
    await db_session.commit()
    return office
```

**本番環境でのクリーンアップ**:
```sql
-- 誤って作成されたテストデータを削除
DELETE FROM staffs WHERE is_test_data = true;
DELETE FROM offices WHERE is_test_data = true;
```

### 5.2 テスト後のクリーンアップ

```python
# tests/conftest.py
@pytest_asyncio.fixture
async def db_session():
    async with AsyncSessionLocal() as session:
        yield session
        await session.rollback()  # 全ての変更をロールバック
```

**GitHub Actions環境**:
- テスト専用データベース (`TEST_DATABASE_URL`) を使用
- 各テストランの前にデータベースをリセット
- ステートレスなテスト実行を保証

---

## 6. テストの実行方法

### 6.1 ローカル開発

```bash
# 全テスト実行
docker exec keikakun_app-backend-1 pytest tests/ -v

# 特定のテストファイル実行
docker exec keikakun_app-backend-1 pytest tests/api/test_billing.py -v

# 特定のテスト関数実行
docker exec keikakun_app-backend-1 pytest tests/api/test_billing.py::test_get_billing_status -v

# キーワードでフィルタ（例: billingを含むテストのみ）
docker exec keikakun_app-backend-1 pytest tests/ -k "billing" -v

# 失敗したテストのみ再実行
docker exec keikakun_app-backend-1 pytest tests/ --lf -v

# 最も遅いテスト10個を表示
docker exec keikakun_app-backend-1 pytest tests/ --durations=10
```

### 6.2 CI/CD環境

**GitHub Actions (.github/workflows/cd-backend.yml:38-65)**:
```yaml
- name: Run Pytest
  working-directory: ./k_back
  env:
    TESTING: "1"
    ENVIRONMENT: "test"
    TEST_DATABASE_URL: ${{ secrets.TEST_DATABASE_URL }}
    SECRET_KEY: ${{ secrets.TEST_SECRET_KEY }}
    # ... その他の環境変数
  run: pytest
```

**実行時間**: 通常2-3分（155テストファイル）

---

## 7. テストの品質を保つルール

### 7.1 プルリクエスト時のチェックリスト

- [ ] 新機能には対応するテストを追加
- [ ] 全てのテストがパス (`pytest tests/ -v`)
- [ ] セキュリティテスト（SQL injection、XSS、認可）を追加
- [ ] `is_test_data=True` をテストデータに設定
- [ ] GitHub Actionsが全てグリーン
- [ ] ESLint、TypeScript型チェックがパス（Frontend）

### 7.2 テストコードのベストプラクティス

```python
# ✅ Good: 明確なテスト名、Arrange-Act-Assert構造
async def test_get_billing_status_returns_active_for_paid_subscription():
    # Arrange: テストデータ準備
    office = await create_test_office(db_session)
    billing = await create_billing(office_id=office.id, status="active")

    # Act: 実行
    response = await client.get("/api/v1/billing/status", headers=auth_headers)

    # Assert: 検証
    assert response.status_code == 200
    assert response.json()["billing_status"] == "active"

# ❌ Bad: テスト名が曖昧、検証が不十分
async def test_billing():
    response = await client.get("/api/v1/billing/status")
    assert response.status_code == 200
```

### 7.3 テストが失敗したときの対応

```bash
# 1. ローカルで再現
docker exec keikakun_app-backend-1 pytest tests/api/test_billing.py::test_failed -v

# 2. ログを確認
docker exec keikakun_app-backend-1 cat tests.log

# 3. デバッグモードで実行
docker exec keikakun_app-backend-1 pytest tests/api/test_billing.py::test_failed -v -s --pdb

# 4. データベース状態を確認
docker exec keikakun_app-backend-1 python -c "
from app.db.session import AsyncSessionLocal
# データベースの状態を確認
"
```

---

## 8. 他のブランチ戦略との比較

### 8.1 なぜGit Flowを採用しなかったか

| 項目 | Git Flow | GitHub Flow (採用) | 理由 |
|------|---------|-------------------|------|
| ブランチ数 | 5+ (main, develop, release, hotfix, feature) | 2 (main, feature) | **チーム規模が小さい**（1-3名）ため、複雑性は不要 |
| リリース頻度 | 週次/月次 | デイリー/時間単位 | **高速デプロイ**を重視（Cloud Runで即座にロールバック可能） |
| リリースブランチ | あり | なし | **リリース準備期間が不要**（常時リリース可能な状態を維持） |
| Hotfix対応 | 専用ブランチ | mainから直接 | **緊急修正が少ない**（テストゲートで品質担保） |
| 学習コスト | 高い | 低い | **新メンバーのオンボーディングが容易** |

### 8.2 GitHub Flowの利点

1. **シンプルさ**: ブランチが2種類のみ（main + feature）
2. **高速デプロイ**: mainへのマージ = 即本番デプロイ
3. **ロールバック容易**: Cloud Runのリビジョン切り替えで1-2分で戻せる
4. **CI/CDとの相性**: 単一の本番ブランチでパイプラインが明確

---

## 9. 面接で強調すべきポイント

### 9.1 Git戦略の意思決定

**質問**: 「Gitのブランチ戦略はどうしていますか？」

**回答例**:
> 「GitHub Flowを採用しています。理由は3つあります。1つ目は、チーム規模が1-3名と小さいため、Git Flowの複雑さは不要だと判断しました。2つ目は、Cloud Runの高速デプロイとロールバック機能により、mainブランチを常時デプロイ可能な状態に保つことが可能です。3つ目は、GitHub Actionsでpytestを必須ゲートとすることで、mainブランチの品質を担保しています。mainへのマージ前に155個のテストが自動実行され、失敗すればデプロイがブロックされます。」

**深掘り対応**:
- Git Flowとの比較表を説明できる
- 「なぜdevelopブランチを使わないのか」→ 小規模チームでは統合の必要性が低い
- 「Hotfixはどうするのか」→ mainから直接修正 + 高速ロールバック

### 9.2 テスト戦略の説明

**質問**: 「テストはどの程度書いていますか？カバレッジは？」

**回答例**:
> 「155個のテストファイルで、API層、Service層、CRUD層、Security層を網羅的にテストしています。特に重視しているのはセキュリティテストで、全てのミューテーションAPIに対してSQL injection、XSS、認可チェックのテストを実装しています。カバレッジツールは現在未導入ですが、手動評価では全体で85%程度、重要パス（課金、認証）では95%以上をカバーしていると推定しています。Docker環境でテストを実行することで、本番環境と同じPython 3.12 + PostgreSQLの環境を再現し、CI/CDとの一貫性を保っています。」

**技術的深さ**:
- 「pytest.iniの`asyncio_mode = auto`設定で非同期テストに対応」
- 「`is_test_data`フラグで本番環境へのテストデータ混入を防止」
- 「GitHub Actionsのデプロイゲートで、テスト失敗時は自動的にデプロイ中断」

### 9.3 品質保証の姿勢

**アピールポイント**:
1. **テストファースト**: 新機能開発時は必ずテストを追加
2. **セキュリティ重視**: OWASP Top 10を意識したテスト設計
3. **自動化**: 手動テストに頼らず、CI/CDで全自動化
4. **将来への拡張性**: pytest-cov導入計画、目標カバレッジ80%

---

## 10. 今後の改善計画

### 10.1 短期（1-3ヶ月）

- [ ] **pytest-cov導入**: カバレッジ可視化
- [ ] **Codecov連携**: PRごとのカバレッジ差分表示
- [ ] **E2Eテスト追加**: Playwright/Cypressでフロントエンド統合テスト

### 10.2 中期（3-6ヶ月）

- [ ] **カバレッジ80%達成**: 未テストのエッジケースを追加
- [ ] **パフォーマンステスト拡充**: Locustで負荷テスト
- [ ] **Mutation Testing**: mutmutで「テストの品質」をテスト

### 10.3 長期（6ヶ月以上）

- [ ] **Contract Testing**: PactでAPI契約テスト（フロントエンド連携）
- [ ] **Visual Regression Testing**: Percy/Chromatic導入
- [ ] **Chaos Engineering**: 本番障害シミュレーション

---

## 11. 参考資料

- [GitHub Flow (GitHub Docs)](https://docs.github.com/en/get-started/quickstart/github-flow)
- [pytest Documentation](https://docs.pytest.org/)
- [pytest-asyncio](https://pytest-asyncio.readthedocs.io/)
- [OWASP Testing Guide](https://owasp.org/www-project-web-security-testing-guide/)

---

**作成日**: 2026-01-29
**対象面接**: Web受託系アプリ開発 2次面接
**カテゴリ**: Git戦略 / テスト / CI/CD / 品質保証
