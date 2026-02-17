# テストDB クリーンアップ時の事務所データ削除問題 - 調査レポート

**調査日**: 2025-11-19
**対象テスト**: `tests/api/v1/test_auth_session_persistence.py`
**報告された問題**: テスト実行時にファクトリ関数で作成した以外の事務所データが削除される（スタッフデータは残る）

---

## 📋 調査サマリー

### 結論
**test_auth_session_persistence.py 自体には問題なし**

問題の原因は `k_back/tests/utils/safe_cleanup.py` の**過度に広範囲なパターンマッチング**にあります。

---

## 🔍 詳細調査結果

### 1. test_auth_session_persistence.py の分析

#### ✅ 問題なし - 確認事項
- **事務所関連エンドポイントへのアクセス**: なし
- **直接的なDELETE/TRUNCATE操作**: なし
- **使用しているエンドポイント**:
  ```
  /api/v1/auth/token         (POST) - ログイン
  /api/v1/auth/refresh-token (POST) - トークンリフレッシュ
  /api/v1/auth/logout        (POST) - ログアウト
  /api/v1/staffs/me          (GET)  - 現在のユーザー情報取得
  ```

#### 検証コマンド
```bash
grep -n "DELETE\|TRUNCATE\|/api/v1/offices" k_back/tests/api/v1/test_auth_session_persistence.py
# → マッチなし（コメント内の "delete_cookie" のみ）
```

---

### 2. 問題の根本原因: safe_cleanup.py

**ファイル**: `k_back/tests/utils/safe_cleanup.py`

#### 🔴 問題箇所: Line 163-170

```python
# 2. テスト事業所を削除
office_result = await db.execute(
    text("""
        DELETE FROM offices
        WHERE name LIKE '%テスト事業所%'
           OR name LIKE '%test%'      # ← 問題①: 過度に広範囲
           OR name LIKE '%Test%'      # ← 問題②: 過度に広範囲
    """)
)
```

#### ❌ 問題点

| パターン | 意図 | 実際の挙動 | 影響範囲 |
|---------|------|-----------|---------|
| `'%テスト事業所%'` | ✅ ファクトリ生成データのみ削除 | ✅ 正常 | 限定的 |
| `'%test%'` | ❌ テストデータ削除 | ❌ **「test」を含むすべての事務所を削除** | **広範囲** |
| `'%Test%'` | ❌ テストデータ削除 | ❌ **「Test」を含むすべての事務所を削除** | **広範囲** |

#### 誤削除される可能性のある事務所名の例
- "Latest Technology Office" ← `test` を含む
- "Contest Center" ← `test` を含む
- "Testing Lab" ← `Test` を含む
- "Fastest Service" ← `test` を含む
- その他、「test」「Test」を含むあらゆる事務所名

---

### 3. conftest.py のファクトリ関数の命名規則

**ファイル**: `k_back/tests/conftest.py`

#### office_factory (Line 600-644)

```python
@pytest_asyncio.fixture
async def office_factory(db_session: AsyncSession):
    """事業所を作成するFactory"""
    counter = {"count": 0}

    async def _create_office(
        creator: Optional[Staff] = None,
        name: Optional[str] = None,
        type: OfficeType = OfficeType.type_A_office,
        session: Optional[AsyncSession] = None,
    ) -> Office:
        # ...
        counter["count"] += 1

        # nameが指定されていない場合、一意な名前を生成
        office_name = name or f"テスト事業所{counter['count']}"  # ← 命名規則

        new_office = Office(
            name=office_name,
            type=type,
            created_by=creator.id,
            last_modified_by=creator.id,
        )
        # ...
```

#### ファクトリが生成する事務所名のパターン
- `"テスト事業所1"`
- `"テスト事業所2"`
- `"テスト事業所3"`
- ...

**重要**: ファクトリ関数は「テスト事業所{番号}」という形式で事務所を作成するため、削除時も同じパターンで削除すべき。

---

### 4. スタッフデータが残る理由

**ファイル**: `k_back/tests/utils/safe_cleanup.py` (Line 187-238)

#### スタッフ削除時の再割当処理

```python
# 3. テストスタッフの削除
staff_query = text("""
    SELECT id FROM staffs
    WHERE email LIKE '%@test.com'
       OR email LIKE '%@example.com'
       OR last_name LIKE '%テスト%'
       OR full_name LIKE '%テスト%'
""")
staff_result = await db.execute(staff_query)
target_staff_ids = [row[0] for row in staff_result.fetchall()]

if target_staff_ids:
    # 再割当が必要な場合の処理（削除対象外のownerを取得）
    replacement_query = text("""
        SELECT s.id FROM staffs s
        INNER JOIN office_staffs os ON s.id = os.staff_id
        WHERE s.role = 'owner'
          AND s.id != ALL(:target_ids)
          AND s.email NOT LIKE '%@test.com'
          AND s.email NOT LIKE '%@example.com'
        LIMIT 1
    """)
    replacement_result = await db.execute(
        replacement_query,
        {"target_ids": list(target_staff_ids)}
    )
    replacement_staff = replacement_result.fetchone()

    if replacement_staff:
        replacement_id = replacement_staff[0]

        # offices.created_by を再割当
        await db.execute(
            text("""
                UPDATE offices
                SET created_by = :replacement_id
                WHERE created_by = ANY(:target_ids)
            """),
            {
                "replacement_id": replacement_id,
                "target_ids": list(target_staff_ids)
            }
        )

        # offices.last_modified_by を再割当
        await db.execute(
            text("""
                UPDATE offices
                SET last_modified_by = :replacement_id
                WHERE last_modified_by = ANY(:target_ids)
            """),
            {
                "replacement_id": replacement_id,
                "target_ids": list(target_staff_ids)
            }
        )

    # スタッフを削除
    delete_staff_result = await db.execute(
        text("DELETE FROM staffs WHERE id = ANY(:target_ids)"),
        {"target_ids": list(target_staff_ids)}
    )
```

#### なぜスタッフデータが残るのか

1. **削除対象のスタッフがofficesテーブルのcreated_by/last_modified_byで参照されている場合**:
   - 削除前に別のowner（削除対象外）に再割当される
   - その後、スタッフ自体は削除される

2. **しかし、事務所が先に削除されている場合**:
   - 事務所の削除により、office_staffs（中間テーブル）も削除される
   - スタッフは事務所との関連が切れる
   - 再割当の対象にならず、スタッフレコード自体が残る可能性がある

3. **削除順序の問題**:
   ```python
   # 1. テスト事務所のIDを取得 (Line 70-77)
   # 2. テスト事務所を削除 (Line 163-172)  ← 先に削除
   # 3. テストスタッフを削除 (Line 174-238) ← 後から削除
   ```
   - 事務所が先に削除されると、そのスタッフは「どの事務所にも属さない」状態になる
   - 再割当処理の条件（`INNER JOIN office_staffs`）に該当せず、削除されない可能性がある

---

## 🔧 推奨される修正

### 修正箇所: `k_back/tests/utils/safe_cleanup.py`

#### 修正前 (Line 163-170)

```python
# ❌ 問題のあるコード
office_result = await db.execute(
    text("""
        DELETE FROM offices
        WHERE name LIKE '%テスト事業所%'
           OR name LIKE '%test%'      # ← 削除
           OR name LIKE '%Test%'      # ← 削除
    """)
)
```

#### 修正後（推奨案1: 先頭一致）

```python
# ✅ 推奨: 先頭一致で限定的に削除
office_result = await db.execute(
    text("""
        DELETE FROM offices
        WHERE name LIKE 'テスト事業所%'  -- 先頭一致に変更
    """)
)
```

#### 修正後（推奨案2: より安全な部分一致）

```python
# ✅ 代替案: 部分一致だがより限定的
office_result = await db.execute(
    text("""
        DELETE FROM offices
        WHERE name LIKE '%テスト事業所%'  -- 部分一致だが日本語で限定
    """)
)
```

#### 修正後（推奨案3: 複数パターン - より厳密）

```python
# ✅ 最も安全: ファクトリの命名規則に完全一致
office_result = await db.execute(
    text("""
        DELETE FROM offices
        WHERE name ~ '^テスト事業所[0-9]+$'  -- 正規表現: 「テスト事業所」+ 数字のみ
           OR name LIKE 'テスト事業所%'      -- 後方互換性のため
    """)
)
```

---

### 同様の問題が存在する箇所

#### Line 70-77 (テスト事務所ID取得)

```python
# 同じパターンを使用しているため、併せて修正が必要
office_ids_query = text("""
    SELECT id FROM offices
    WHERE name LIKE '%テスト事業所%'
       OR name LIKE '%test%'      # ← 削除推奨
       OR name LIKE '%Test%'      # ← 削除推奨
""")
```

#### 修正後

```python
office_ids_query = text("""
    SELECT id FROM offices
    WHERE name LIKE 'テスト事業所%'  -- 先頭一致
""")
```

---

## 📊 影響範囲の検証

### safe_cleanup.py が使用されている箇所

**ファイル**: `k_back/tests/conftest.py`

```python
# Line 45-88: safe_cleanup_test_database 関数
# Line 90-170: cleanup_database_session フィクスチャ (autouse=True)
```

#### 実行タイミング
1. **テストセッション開始前** (Line 102-151)
2. **テストセッション終了後** (Line 156-170)

#### autouse=True の影響
- すべてのテスト実行時に自動的にクリーンアップが実行される
- 修正しなければ、**すべてのテスト実行時に誤削除が発生する可能性がある**

---

## 🎯 修正の優先度

### 🔴 高優先度（即座に修正すべき）

1. **safe_cleanup.py Line 165-168**: 事務所削除の条件修正
   - `'%test%'` と `'%Test%'` のパターンを削除
   - `'テスト事業所%'` (先頭一致) に変更

2. **safe_cleanup.py Line 70-77**: 事務所ID取得の条件修正
   - 同じパターンを使用しているため併せて修正

### ⚠️ 中優先度（検討すべき）

3. **削除順序の見直し**:
   - 現在: 事務所 → スタッフ
   - 推奨: スタッフ → 事務所（外部キー制約を考慮）

4. **より安全な識別方法の導入**:
   - `is_test_data` フラグカラムの追加（Officeテーブル）
   - ファクトリ関数でフラグを設定
   - クリーンアップ時はフラグで判定

---

## 🧪 テスト環境での検証方法

### 1. 修正前の状態確認

```bash
# Dockerコンテナに接続
docker exec -it keikakun_app-backend-1 bash

# PostgreSQLに接続
psql $DATABASE_URL

# 事務所データの確認
SELECT id, name, created_at
FROM offices
WHERE name LIKE '%test%' OR name LIKE '%Test%'
ORDER BY created_at DESC;
```

### 2. 修正後のテスト実行

```bash
# テスト実行
docker exec keikakun_app-backend-1 pytest tests/api/v1/test_auth_session_persistence.py -v

# クリーンアップログの確認
# → "Deleted X factory-generated records" の出力を確認
```

### 3. 修正後の状態確認

```bash
# 再度PostgreSQLで確認
SELECT id, name, created_at
FROM offices
ORDER BY created_at DESC
LIMIT 20;

# ファクトリ生成以外の事務所が残っているか確認
```

---

## 📝 その他の調査結果

### db_cleanup.py との違い

**ファイル**: `k_back/tests/utils/db_cleanup.py`

- このファイルも同様の問題を持つが、**現在は使用されていない**
- conftest.py では `SafeTestDataCleanup` (safe_cleanup.py) が使用されている
- db_cleanup.py は古いコードと思われる

#### db_cleanup.py Line 192-195

```python
# 使用されていないが、同様の問題あり
office_query = text("""
    DELETE FROM offices
    WHERE name LIKE '%テスト%'
       OR name LIKE '%test%'
       OR name LIKE '%Test%'
    RETURNING id
""")
```

**推奨**: 混乱を避けるため、db_cleanup.py を削除またはdeprecated マークを追加

---

## 🔒 本番環境への影響

### 安全性の確認

**ファイル**: `k_back/tests/utils/safe_cleanup.py` (Line 19-48)

```python
@staticmethod
def verify_test_environment() -> bool:
    """
    テスト環境であることを確認

    Returns:
        テスト環境の場合True、それ以外False
    """
    db_url = os.getenv("TEST_DATABASE_URL")

    # TEST_DATABASE_URLが設定されていることを確認
    if not db_url:
        logger.warning("TEST_DATABASE_URL not set - assuming not in test environment")
        return False

    db_url_lower = db_url.lower()

    # テスト環境のキーワードがあればOK
    test_keywords = ['test', '_test', '-test', 'testing', 'dev', 'development']
    if any(keyword in db_url_lower for keyword in test_keywords):
        logger.info(f"Test environment confirmed (contains test keyword): {db_url}")
        return True

    # テストキーワードがなく、本番環境のキーワードがある場合はNG
    production_keywords = ['prod', 'production', 'main', 'live']
    if any(keyword in db_url_lower for keyword in production_keywords):
        logger.error(f"Production database detected in URL without test keyword: {db_url}")
        return False

    return True
```

#### ✅ 本番環境での誤実行は防止されている
- `TEST_DATABASE_URL` 環境変数の確認
- 本番環境キーワードの検出
- ただし、**パターンマッチングの問題は修正すべき**

---

## 🎯 まとめ

### 原因
`k_back/tests/utils/safe_cleanup.py` の事務所削除条件が過度に広範囲

### 影響
- `'%test%'` や `'%Test%'` を含むすべての事務所が削除される
- ファクトリ関数で作成した以外の事務所も削除される可能性がある

### 解決策
1. 削除条件を `name LIKE 'テスト事業所%'` (先頭一致) に変更
2. `'%test%'` と `'%Test%'` のパターンを削除

### test_auth_session_persistence.py について
- **問題なし**: 事務所データへの操作は一切行っていない
- 問題の原因は safe_cleanup.py にある

---

## 📅 次のアクション

### 即座に実施
- [ ] `safe_cleanup.py` Line 165-168 の修正
- [ ] `safe_cleanup.py` Line 70-77 の修正
- [ ] 修正後のテスト実行と検証

### 検討事項
- [ ] `db_cleanup.py` の削除または非推奨化
- [ ] `is_test_data` フラグの導入検討
- [ ] 削除順序の見直し（スタッフ → 事務所）

---

**調査担当**: Claude Code
**レポート作成日**: 2025-11-19
