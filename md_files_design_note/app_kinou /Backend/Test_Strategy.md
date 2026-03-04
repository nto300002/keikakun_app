# Test Strategy（テスト戦略）

## テストディレクトリ構成

```
tests/
├── conftest.py                          # 共通フィクスチャ・セッション管理
├── api/
│   └── v1/                             # APIエンドポイントテスト
├── crud/                               # CRUD操作テスト
├── models/                             # モデルテスト
├── schemas/                            # スキーマバリデーションテスト
├── security/                           # セキュリティテスト
│   ├── test_rate_limiting.py
│   ├── test_password_reset_security.py
│   └── test_staff_profile_security.py
├── integration/                        # 統合テスト（フロー全体）
│   ├── test_password_reset_flow.py
│   ├── test_role_change_flow.py
│   └── test_employee_restriction_flow.py
├── core/                               # コア機能テスト
│   ├── test_mfa_security.py
│   └── test_password_breach_check.py
└── tasks/                              # バックグラウンドタスクテスト
```

---

## テスト実行コマンド

```bash
# 全テスト実行（Dockerコンテナ内）
docker exec keikakun_app-backend-1 pytest tests/ -v

# 特定ディレクトリのみ
docker exec keikakun_app-backend-1 pytest tests/security/ -v

# 特定ファイルのみ
docker exec keikakun_app-backend-1 pytest tests/api/v1/test_staffs.py -v
```

---

## テストDB設定

**ファイル**: `app/db/session.py`

```python
if os.getenv("TESTING") == "1":
    ASYNC_DATABASE_URL = os.getenv("TEST_DATABASE_URL")
else:
    ASYNC_DATABASE_URL = os.getenv("DATABASE_URL")
```

- `TESTING=1` 環境変数でテスト用DBに切り替え
- 本番DBとテストDBは完全に分離

---

## フィクスチャ設計（pytest-asyncio）

**ファイル**: `tests/conftest.py`

### セッション全体のクリーンアップ
```python
@pytest_asyncio.fixture(scope="session", autouse=True)
async def cleanup_database_session():
    """全テストセッションの前後でファクトリ生成データをクリーンアップ"""
    # テスト前: 過去のテストデータを削除
    yield
    # テスト後: 生成したデータを削除
```

### DBセッションフィクスチャ
```python
@pytest_asyncio.fixture
async def db_session():
    async with AsyncSessionLocal() as session:
        yield session
        await session.rollback()  # 各テスト後にロールバック
```

### テストデータ作成パターン
```python
# ID取得のために flush() を使用
async def create_test_staff(db, office_id, **kwargs) -> Staff:
    staff = Staff(office_id=office_id, **kwargs)
    db.add(staff)
    await db.flush()   # IDを確定
    await db.refresh(staff)
    return staff
```

---

## テスト実装パターン

### セキュリティテスト
**ファイル**: `tests/security/test_rate_limiting.py`

```python
class TestRateLimiting:
    def test_limiter_instance(self):
        """Limiterインスタンスが正しく作成されていることを確認"""
        assert limiter is not None

    def test_get_remote_address(self):
        """リモートアドレス取得ロジックのテスト"""
        mock_request = MagicMock()
        mock_request.client.host = "127.0.0.1"
        assert get_remote_address(mock_request) == "127.0.0.1"
```

### 認可テスト（必須）
すべてのエンドポイントに対して以下を確認する:
- 未認証アクセス → 401 Unauthorized
- 権限不足アクセス → 403 Forbidden
- 他事業所データへのアクセス → 403 または 404

```python
async def test_unauthorized_access(client):
    response = await client.get("/api/v1/staffs/")
    assert response.status_code == 401

async def test_employee_cannot_delete(client, employee_token):
    response = await client.delete(
        "/api/v1/staffs/some-id",
        headers={"Authorization": f"Bearer {employee_token}"},
    )
    assert response.status_code == 403
```

### SQLインジェクション防止テスト
```python
async def test_sql_injection_prevention(client, auth_headers):
    malicious_input = "'; DROP TABLE staffs; --"
    response = await client.get(
        f"/api/v1/staffs/?search={malicious_input}",
        headers=auth_headers,
    )
    # クラッシュせずに正常レスポンスを返すことを確認
    assert response.status_code in (200, 422)
```

### ソートテスト（フリガナ等）
```python
# ❌ furigana未設定 → NULL でソート順が不定になる
recipient = await create_test_recipient(db, office_id=office_id)

# ✅ furigana を必ず設定してソートテストを安定させる
recipient = await create_test_recipient(
    db,
    office_id=office_id,
    last_name_furigana="あ",
    first_name_furigana="えー",
)
```

---

## テスト品質基準

### 必須テスト項目（全エンドポイント）
- [ ] 正常系: 期待するレスポンスが返ること
- [ ] 未認証: 401 が返ること
- [ ] 権限不足: 403 が返ること
- [ ] バリデーションエラー: 422 が返ること
- [ ] 他テナントデータへのアクセス: 403 または 404

### セキュリティテスト項目
- [ ] SQLインジェクション入力でクラッシュしないこと
- [ ] XSS文字列がエスケープされること
- [ ] レート制限が機能すること
- [ ] MFAが正しく検証されること

### リレーションテスト
```python
# selectinload を使用してリレーションを検証
stmt = select(Staff).where(Staff.id == staff_id).options(
    selectinload(Staff.office_associations).selectinload(OfficeStaff.office)
)
result = await db.execute(stmt)
staff = result.scalar_one()
assert staff.office_associations[0].office.name == "テスト事業所"
```

---

## 並列テストの注意点

- 並列テスト実行（`pytest-xdist`）ではトランザクション分離に注意
- ネストされたトランザクション（`SAVEPOINT`）が使用される場合の対処
- 詳細: `md_files_design_note/task/done/investigation/` 参照
