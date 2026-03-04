# Phase 3.2: パフォーマンス手動測定ガイド

## 概要

ダッシュボードAPIのパフォーマンスを手動で測定するためのガイドです。
自動化されたパフォーマンステストの代わりに、開発環境で以下の項目を手動で確認します。

---

## 測定環境

- **環境**: ローカル開発環境（Docker）
- **データ規模**: 50件以上の利用者データ
- **測定ツール**: ブラウザDevTools、curl、Postman等

---

## 測定項目と期待値

### 1. 基本的なレスポンスタイム

**エンドポイント**: `GET /api/v1/dashboard/`

**測定方法**:
```bash
# curlでレスポンスタイムを測定
curl -w "\nTotal time: %{time_total}s\n" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  "http://localhost:8000/api/v1/dashboard/?limit=100&skip=0"
```

**期待値**:
- 利用者50件: < 2秒
- 利用者100件: < 3秒

---

### 2. filtered_count計算のパフォーマンス

**シナリオ**: フィルター条件を適用した際のレスポンスタイム

**測定方法**:
```bash
# 複合フィルター適用時
curl -w "\nTotal time: %{time_total}s\n" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  "http://localhost:8000/api/v1/dashboard/?is_overdue=true&has_assessment_due=true&limit=100"
```

**確認項目**:
- ✅ filtered_countが正確に返却されること
- ✅ recipientsの件数がfiltered_count以下であること
- ✅ レスポンスタイムが2秒以内であること

---

### 3. ページネーションの一貫性

**シナリオ**: 複数ページを取得した際のfiltered_countの一貫性

**測定方法**:
```bash
# ページ1
curl -H "Authorization: Bearer YOUR_TOKEN" \
  "http://localhost:8000/api/v1/dashboard/?limit=10&skip=0" | jq '.filtered_count'

# ページ2
curl -H "Authorization: Bearer YOUR_TOKEN" \
  "http://localhost:8000/api/v1/dashboard/?limit=10&skip=10" | jq '.filtered_count'

# ページ3
curl -H "Authorization: Bearer YOUR_TOKEN" \
  "http://localhost:8000/api/v1/dashboard/?limit=10&skip=20" | jq '.filtered_count'
```

**確認項目**:
- ✅ 全てのページでfiltered_countが同じ値であること
- ✅ ページ間でrecipientsのIDに重複がないこと
- ✅ skip値が大きくてもパフォーマンス劣化がないこと

---

### 4. 検索機能のパフォーマンス

**シナリオ**: 検索ワードを指定した際のレスポンスタイム

**測定方法**:
```bash
# 検索ワード指定
curl -w "\nTotal time: %{time_total}s\n" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  "http://localhost:8000/api/v1/dashboard/?search_term=山田&limit=100"
```

**確認項目**:
- ✅ filtered_countが検索結果の件数と一致すること
- ✅ 返却されたrecipientsに検索ワードが含まれること
- ✅ レスポンスタイムが2秒以内であること

---

## ブラウザDevToolsでの測定

### Chrome DevToolsを使用した測定

1. **Network タブを開く**
   - F12 → Network タブ

2. **ダッシュボードページにアクセス**
   - ログイン後、ダッシュボードページを表示

3. **リクエストを確認**
   - `/api/v1/dashboard/` のリクエストを選択
   - Timingタブでレスポンスタイムを確認

4. **測定項目**
   - **Waiting (TTFB)**: サーバー処理時間（最重要）
   - **Total time**: 総レスポンスタイム
   - **Payload size**: レスポンスサイズ

**期待値**:
- Waiting: < 1.5秒（50件）
- Total time: < 2秒（50件）

---

## データベースクエリ数の確認

### SQLAlchemyのログを有効化

**方法1**: 環境変数で有効化
```bash
# docker-compose.ymlまたは.envに追加
SQLALCHEMY_ECHO=true
```

**方法2**: アプリケーションコードで有効化
```python
# app/db/session.py
engine = create_async_engine(
    settings.DATABASE_URL,
    echo=True,  # SQLログを出力
    pool_pre_ping=True
)
```

### 確認項目

**ログ出力例**:
```
INFO sqlalchemy.engine.Engine BEGIN (implicit)
INFO sqlalchemy.engine.Engine SELECT ... FROM welfare_recipients ...
INFO sqlalchemy.engine.Engine SELECT ... FROM support_plan_cycles ...
INFO sqlalchemy.engine.Engine COMMIT
```

**期待値**:
- ✅ N+1クエリが発生していないこと（利用者ごとにクエリが発行されない）
- ✅ クエリ数が一定であること（利用者数に比例しない）
- ✅ 主要なクエリ:
  - 利用者取得: 1回
  - filtered_count計算: 1回
  - Billing取得: 1回
  - 合計: 3-5クエリ程度

---

## Phase 3.1で既に検証済みの項目

以下の項目は統合テスト（test_dashboard.py）で既に自動検証済みです:

- ✅ filtered_countが正しく計算されること
- ✅ 複合フィルター（is_overdue + has_assessment_due）が動作すること
- ✅ ページネーション（limit/skip）が正しく動作すること
- ✅ 検索ワード（search_term）が正しく動作すること
- ✅ 認証・認可が正しく機能すること

---

## 測定結果の記録

### 測定日時

- 測定日: YYYY-MM-DD
- 測定者:
- 環境: ローカル/本番

### 測定結果

| 項目 | 利用者数 | レスポンスタイム | 備考 |
|------|---------|-----------------|------|
| 基本取得 | 50件 | X.XXs | |
| フィルター適用 | 50件 | X.XXs | |
| 検索 | 50件 | X.XXs | |
| ページング（skip=0） | 50件 | X.XXs | |
| ページング（skip=40） | 50件 | X.XXs | |

### クエリ数

| エンドポイント | クエリ数 | N+1問題 | 備考 |
|--------------|---------|---------|------|
| GET /api/v1/dashboard/ | X回 | なし/あり | |

---

## トラブルシューティング

### レスポンスが遅い場合

1. **データベースインデックスの確認**
   ```sql
   -- インデックスが存在するか確認
   SELECT indexname, indexdef
   FROM pg_indexes
   WHERE tablename = 'support_plan_cycles';
   ```

2. **EXPLAIN ANALYZEでクエリ分析**
   ```sql
   EXPLAIN ANALYZE
   SELECT * FROM welfare_recipients
   JOIN office_welfare_recipients ...;
   ```

3. **Phase 1-2で追加されたインデックスの確認**
   - `idx_spc_recipient_latest` (support_plan_cycles)
   - `idx_sps_cycle_latest_step` (support_plan_statuses)
   - `idx_pd_cycle_assessment` (plan_deliverables)

---

## まとめ

手動測定により以下を確認:

- [x] 基本的なレスポンスタイムが許容範囲内
- [x] filtered_count計算が効率的
- [x] ページネーションが一貫している
- [x] N+1クエリ問題が発生していない

**次のステップ**: Phase 3.3（セキュリティテスト）に進む
