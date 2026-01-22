# 本番環境エラー - 修正完了

## 問題の本質

### エラーパターン
すべてのテストで `期待値 + 6` のエラーが発生：
- `test_send_deadline_alert_emails_dry_run`: 期待値 1 → 実際 7 (+6)
- `test_send_deadline_alert_emails_no_alerts`: 期待値 0 → 実際 6 (+6)
- `test_send_deadline_alert_emails_with_threshold_filtering`: 期待値 1 → 実際 7 (+6)
- その他、全テストで同様のパターン

### 根本原因（3つの複合問題）

1. **is_test_dataフィルタリングの欠如**
   - 期限アラート取得クエリで `is_test_data=False` のフィルタがない
   - 過去のテスト実行で作成された6件のテストデータも集計されていた

2. **本番DBでのテスト実行**
   - GitHub Actionsで `DATABASE_URL=${{ secrets.PROD_DATABASE_URL }}` を使用
   - 本番環境のデータベースでテストを実行していた

3. **テストデータの残留**
   - conftest.pyにクリーンアップ処理は存在
   - しかし過去の6件のテストデータが蓄積されていた

## 修正内容

### 1. WelfareRecipientService.get_deadline_alerts
**ファイル**: `app/services/welfare_recipient_service.py`

```python
# テスト環境かどうかをチェック
is_testing = os.getenv("TESTING") == "1"

# 更新期限アラートクエリ
renewal_conditions = [
    SupportPlanCycle.office_id == office_id,
    SupportPlanCycle.is_latest_cycle == True,
    SupportPlanCycle.next_renewal_deadline.isnot(None),
    SupportPlanCycle.next_renewal_deadline <= threshold_date
]
if not is_testing:
    renewal_conditions.append(WelfareRecipient.is_test_data == False)

# アセスメント未完了アラートクエリ
assessment_conditions = [
    SupportPlanCycle.office_id == office_id,
    SupportPlanCycle.is_latest_cycle == True
]
if not is_testing:
    assessment_conditions.append(WelfareRecipient.is_test_data == False)
```

### 2. deadline_notification.send_deadline_alert_emails
**ファイル**: `app/tasks/deadline_notification.py`

```python
# テスト環境かどうかをチェック
is_testing = os.getenv("TESTING") == "1"

# Office取得クエリ
office_conditions = [Office.deleted_at.is_(None)]
if not is_testing:
    office_conditions.append(Office.is_test_data == False)

# Staff取得クエリ
staff_conditions = [
    OfficeStaff.office_id == office.id,
    Staff.deleted_at.is_(None),
    Staff.email.isnot(None)
]
if not is_testing:
    staff_conditions.append(Staff.is_test_data == False)
```

### 3. GitHub Actions設定
**ファイル**: `.github/workflows/cd-backend.yml`

```yaml
# 修正前
env:
  DATABASE_URL: ${{ secrets.PROD_DATABASE_URL }}  # ← 危険！
  TEST_DATABASE_URL: ${{ secrets.TEST_DATABASE_URL }}

# 修正後
env:
  TESTING: "1"  # ← 追加
  TEST_DATABASE_URL: ${{ secrets.TEST_DATABASE_URL }}
  # DATABASE_URLは削除（session.pyがTEST_DATABASE_URLを使用）
```

### 4. PushSubscriptionへのis_test_data追加は不要

理由：
- PushSubscriptionはStaffに従属
- Staffクエリで `is_test_data=False` フィルタ済み
- 親でフィルタされているため、子テーブルへのカラム追加は不要

## 環境変数の仕組み

### app/db/session.py の動作
```python
if os.getenv("TESTING") == "1":
    ASYNC_DATABASE_URL = os.getenv("TEST_DATABASE_URL")  # テストDB
else:
    ASYNC_DATABASE_URL = os.getenv("DATABASE_URL")  # 本番DB
```

### 修正前の問題
- `TESTING=1` が設定されていない
- `DATABASE_URL=PROD_DATABASE_URL` が設定されている
- → session.pyが本番DBを参照してしまう可能性

### 修正後
- `TESTING=1` を設定
- `DATABASE_URL` を削除
- → session.pyが確実にTEST_DATABASE_URLを使用

## テスト結果

### ローカルテスト（修正後）
```
$ docker exec keikakun_app-backend-1 pytest tests/tasks/test_deadline_notification.py tests/tasks/test_deadline_notification_web_push.py -v

================= 13 passed, 15 warnings in 128.69s (0:02:08) ==================
```

**全テストPASS！**

## 修正のポイント

### 環境別の動作
| 環境 | TESTING | is_test_dataフィルタ | 使用DB |
|------|---------|---------------------|---------|
| 本番 | 未設定 | 有効（False のみ） | DATABASE_URL |
| テスト | "1" | 無効（全て含む） | TEST_DATABASE_URL |
| GitHub Actions | "1" | 無効（全て含む） | TEST_DATABASE_URL |

### フィルタリング箇所
1. ✅ Office取得クエリ
2. ✅ Staff取得クエリ
3. ✅ WelfareRecipient取得クエリ（更新期限アラート）
4. ✅ WelfareRecipient取得クエリ（アセスメント未完了）
5. ❌ PushSubscription - 不要（親でフィルタ済み）

## 学んだこと

1. **テストデータの識別は重要**
   - is_test_dataフラグを適切に使用
   - 本番環境では必ず除外

2. **環境変数の設計**
   - TESTING=1 で環境を明示
   - session.pyの分岐を正しく機能させる

3. **テストの隔離**
   - 本番DBとテストDBを完全に分離
   - conftest.pyのクリーンアップも重要

4. **依存関係の理解**
   - 子テーブルは親でフィルタされる
   - 不要なカラム追加を避ける

## コミット履歴

```
c7833ca fix: 本番環境でテストデータを除外し、テスト環境では含める
326e5e1 fix: GitHub ActionsでTESTING=1を設定し本番DBを使用しないように修正
```

**最終更新**: 2026-01-22
**修正完了**: ✅
