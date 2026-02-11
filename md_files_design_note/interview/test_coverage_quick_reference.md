# テストカバレッジ - クイックリファレンス（面接用）

**プロジェクト**: Keikakun API | **総テスト数**: **1,872** | **カバレッジ**: 85%+

---

## 📊 テスト数の概要

```
総テストファイル: 178ファイル
総テスト数: 1,872テスト
カバレッジ: 85%+（主要機能は90%以上）
TDD実施率: 80%以上
```

---

## 🎯 面接での回答（30秒版）

### Q: テストはどの程度書きましたか？

> 「**1,872個のテストを178ファイル**に実装し、カバレッジは**85%以上**です。TDD開発で、API統合・認証・セキュリティを重点的にテストしています。」

---

## 1️⃣ API統合テスト（具体例3つ）

### 例1: ユーザー登録 - 正常系（201 Created）

```python
# ステータスコード: 201 Created
# レスポンス検証: email, first_name, last_name, role
# DB検証: データ保存、パスワードハッシュ化
assert response.status_code == 201
assert data["email"] == email
assert user.first_name == payload["first_name"]
```

### 例2: メールアドレス重複 - 異常系（409 Conflict）

```python
# 既存ユーザーと同じメールで登録
# ステータスコード: 409 Conflict
# エラーメッセージ: 日本語で明確
assert response.status_code == 409
assert "既に登録されています" in response.json()["detail"]
```

### 例3: パラメータ化テスト（複数ロール）

```python
@pytest.mark.parametrize("role", [StaffRole.employee, StaffRole.manager])
async def test_register_staff_success(role):
    # 1つのテストで複数ロールを検証
    assert data["role"] == role.value
```

---

## 2️⃣ 認証テスト（具体例3つ）

### 例1: JWT有効期限 - 正常系

```python
# セッション期間: 3600秒（1時間）固定
# JWTペイロード検証: exp, iat
# 有効期限計算: 発行時刻から1時間後
assert data["session_duration"] == 3600
duration = exp_timestamp - iat_timestamp
assert 3590 <= duration <= 3610  # 3600秒 ± 10秒
```

### 例2: JWT期限切れ - 異常系（401）

```python
# 1秒で期限切れのトークンを作成
expired_token = create_access_token(expires_delta_seconds=1)
time.sleep(2)  # 2秒待機

# 期限切れトークンでアクセス
response = await async_client.get("/api/v1/staffs/me")
assert response.status_code == 401  # ✅ 401 Unauthorized
```

### 例3: 無効なトークン - 異常系（401）

```python
# 不正な署名のトークン
invalid_token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.invalid.signature"
response = await async_client.get("/api/v1/staffs/me")
assert response.status_code == 401  # ✅ 401 Unauthorized
```

---

## 3️⃣ セキュリティテスト（具体例5つ）

### XSS対策（2例）

#### 例1: <script>タグのエスケープ

```python
# XSSペイロード
xss_payload = "<script>alert('XSS')</script>"

# FastAPIの自動HTMLエスケープ
assert "<script>" not in data["employment_other_text"]
assert "lt;script" in data["employment_other_text"]  # &lt;script&gt;
```

#### 例2: imgタグのonerrorハンドラ

```python
xss_payload = '<img src=x onerror="alert(1)">'
assert '<img' not in data["desired_tasks_on_asobe"]
assert 'onerror' not in data["desired_tasks_on_asobe"]
```

---

### SQLインジェクション対策（2例）

#### 例1: OR 1=1攻撃

```python
sql_injection_payload = "' OR 1=1; --"
response = await async_client.post("/api/v1/auth/token", data={
    "username": sql_injection_payload,
    "password": "any-password"
})
assert response.status_code == 401  # ✅ SQLインジェクション防止
```

#### 例2: DROP TABLE攻撃

```python
sql_injection_payload = "'; DROP TABLE employment_related; --"
response = await async_client.put(..., json={
    "employment_other_text": sql_injection_payload
})
assert response.status_code == 200  # ✅ 成功（SQLは実行されない）

# テーブルが削除されていないことを確認
check_response = await async_client.get(...)
assert check_response.status_code == 200
```

---

### CSRF対策（1例）

```python
# ❌ CSRFトークンなし → 403 Forbidden
response = await async_client.put("/api/v1/offices/me",
    cookies={"access_token": token})  # Cookie認証のみ
assert response.status_code == 403

# ✅ CSRFトークンあり → 200 OK
response = await async_client.put("/api/v1/offices/me",
    cookies={"access_token": token, "fastapi-csrf-token": csrf_cookie},
    headers={"X-CSRF-Token": csrf_token})
assert response.status_code == 200

# ✅ Bearerトークン → CSRFチェックなし（安全）
response = await async_client.put("/api/v1/offices/me",
    headers={"Authorization": f"Bearer {token}"})
assert response.status_code == 200
```

---

## 📊 テスト分類と数

| カテゴリ | テスト数 | 主な内容 |
|---------|---------|---------|
| **API統合** | 900+ | エンドポイント、ステータスコード、レスポンス |
| **認証・認可** | 150+ | JWT、期限切れ、無効トークン、401エラー |
| **セキュリティ** | 150+ | XSS、SQLインジェクション、CSRF |
| **ビジネスロジック** | 300+ | サービス層、CRUD層 |
| **バッチ処理** | 200+ | 期限通知、課金チェック、リトライ |
| **パフォーマンス** | 20+ | N+1問題、並列処理、大規模データ |
| **その他** | 152+ | エラーハンドリング、バリデーション |
| **合計** | **1,872** | - |

---

## 🎯 面接での回答（詳細版 - 3分）

### Q: API統合テストの具体例は？

> 「ユーザー登録APIでは以下をテストしています：」
>
> **正常系**:
> - ステータスコード **201 Created**
> - レスポンスボディの各フィールド（email, name, role）
> - データベースへの正しい保存とパスワードのハッシュ化
>
> **異常系**:
> - メールアドレス重複時の **409 Conflict**
> - 日本語のエラーメッセージ
>
> 「**パラメータ化テスト**で複数ロール（employee, manager）を効率的にテストしています。」

---

### Q: 認証テストの具体例は？

> 「JWT認証について、正常系と異常系の両方をテストしています：」
>
> **正常系**:
> - ログイン時にJWTトークンが発行
> - 有効期限が **3600秒（1時間）** に設定
> - JWTペイロードの `exp` と `iat` フィールドを検証
>
> **異常系（401 Unauthorized）**:
> - **期限切れトークン**: 1秒で期限切れのトークンを作成し、2秒待機後にアクセス
> - **無効な署名**: 改ざんされたトークンでアクセス
> - **認証なし**: トークンなしでアクセス
>
> 「これにより、認証システムが正しく動作し、不正アクセスを防いでいます。」

---

### Q: セキュリティテストの具体例は？

> 「**XSS、SQLインジェクション、CSRF** の3つを重点的にテストしています。」
>
> **XSS対策**:
> - `<script>alert('XSS')</script>` などの攻撃ペイロードを送信
> - FastAPIの自動HTMLエスケープで `<` → `&lt;` に変換
>
> **SQLインジェクション対策**:
> - `' OR 1=1; --` や `'; DROP TABLE xxx; --` などを試行
> - SQLAlchemyのパラメータ化クエリで防御
> - テーブルが削除されないことを確認
>
> **CSRF対策**:
> - CSRFトークンなし → **403 Forbidden**
> - 有効なCSRFトークン → **200 OK**
> - Bearerトークン認証ではCSRFチェックをスキップ（安全）
>
> 「これらのテストで **OWASP Top 10** の主要な脆弱性に対する防御を保証しています。」

---

## 🔑 キーポイント（暗記用）

1. **総テスト数**: 1,872テスト（178ファイル）
2. **カバレッジ**: 85%+（セキュリティは90%+）
3. **TDD実施**: 80%以上の機能でTDD開発
4. **API統合**: 900+テスト（正常系・異常系・パラメータ化）
5. **認証**: JWT有効期限、期限切れ（401）、無効トークン（401）
6. **セキュリティ**: XSS（エスケープ）、SQLインジェクション（パラメータ化）、CSRF（トークン検証）
7. **実行時間**: 約20分（CI/CDで自動実行）

---

## 📚 詳細版ドキュメント

より詳細な説明とコード例は以下を参照:
- [テストカバレッジ詳細版](./test_coverage_interview_guide.md)

---

**最終更新**: 2026-02-10 | **総テスト数**: 1,872 | **カバレッジ**: 85%+
