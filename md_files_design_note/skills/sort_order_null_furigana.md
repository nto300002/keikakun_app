# Skill: ソート順の不定問題（NULLふりがな）

**スキルID**: `sort-null-furigana`
**カテゴリ**: バグパターン / テスト品質 / SQLAlchemy
**作成日**: 2026-02-19

---

## 問題パターン

### 症状

テストが `assert 3 == 1` のような「ランダムに見える」失敗をする。
`sort_by="furigana"` でソートしているが、結果の順番が期待と異なる。

### 根本原因 1: テストデータに furigana が設定されていない

```python
# ❌ 悪い例: last_name_furigana がNULL → ソート順が不定
recipient_a = await create_test_recipient(
    db_session,
    office_id=office.id,
    last_name="あいうえお",  # last_nameはあるが...
    first_name="A"           # furigana未設定 → NULL
)
```

`concat(NULL, NULL)` はデータベース実装によって異なる順序で並ぶ。
PostgreSQLでは NULL は `NULLS LAST` や `NULLS FIRST` の挙動が不確定になる場合がある。

```python
# ✅ 良い例: furigana を明示的に設定
recipient_a = await create_test_recipient(
    db_session,
    office_id=office.id,
    last_name="あいうえお",
    first_name="A",
    last_name_furigana="あいうえお",   # ← 必須
    first_name_furigana="えー"         # ← 必須
)
```

### 根本原因 2: CRUD の sort_by ハンドリングに値が存在しない

```python
# ❌ 悪い例: "furigana" のcaseがないためデフォルト（常にASC）にフォールバック
if sort_by == "name_phonetic":
    order_func = sort_column.desc() if sort_order == "desc" else sort_column.asc()
elif sort_by == "next_renewal_deadline":
    ...
# sort_by="furigana" はどのcaseにも一致しない！
# → else（デフォルト）は常に .asc() → desc指定が無視される
```

**症状**: `sort_order="desc"` を指定しても昇順になる。

```python
# ✅ 良い例: 使用する値をすべてcaseに追加
if sort_by in ("furigana", "name_phonetic"):  # ← エイリアスも含める
    sort_column = func.concat(WelfareRecipient.last_name_furigana, ...)
    order_func = sort_column.desc() if sort_order == "desc" else sort_column.asc()
```

---

## 発生箇所（2026-02-19 修正済み）

| ファイル | 問題 | 修正内容 |
|---|---|---|
| `app/crud/crud_dashboard.py:189` | `"furigana"` のcaseなし → 常にASC | `"furigana"` を `"name_phonetic"` と同じcaseに追加 |
| `tests/crud/test_crud_dashboard_subquery.py:270-316` | テストデータに `last_name_furigana` なし → ソート不定 | `last_name_furigana` / `first_name_furigana` を追加 |

---

## チェックリスト（ソート関連テストを書く際）

- [ ] テストデータに `last_name_furigana` と `first_name_furigana` が設定されているか？
- [ ] テストで使用する `sort_by` の値が CRUD のハンドリングに存在するか？
- [ ] `sort_order="desc"` のテストケースが通るか確認したか？
- [ ] 複数件の結果をソート順でassertする場合、全データのソートキーに重複がないか？

---

## 関連する一般パターン

```
sort_by のstring値 → CRUDのif/elif分岐に追加し忘れ
→ デフォルトブランチ（常にASC）にフォールバック
→ descテストがASCの結果を返して失敗
```

この問題はダッシュボード以外でも発生しうる。ソートパラメータを追加した際は必ず：
1. フロントエンドが送る値と CRUD のcase値が一致しているか確認
2. desc/asc 両方のテストケースを作成

---

**更新日**: 2026-02-19
**メンテナー**: Claude Sonnet 4.6
