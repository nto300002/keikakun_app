# 05 権限設計 / マスク解除 / 監査フロー

作成日: 2026-07-04

## 対象

マスク済み情報を誰がどの条件で閲覧できるか、またマスク解除が必要な運用時のフローを定義する。

## 権限レベル案

- `self`: 自分自身の情報。
- `same_office_admin`: 同一事業所の owner / manager。
- `same_office_employee`: 同一事業所の employee。
- `app_admin_support`: サポート対応に必要な最小情報。
- `app_admin_sensitive`: 本人確認や障害対応で一時的に詳細閲覧が必要な情報。
- `system`: batch / webhook / internal のみ。

## 実装タスク

- [x] app-admin の監査ログ閲覧権限を定義する。
- [x] app-admin の問い合わせ詳細閲覧権限を定義する。
- [x] billing / webhook 詳細閲覧権限を定義する。
- [x] owner / manager / employee の一覧・詳細・API権限を表にする。
- [ ] employee が閲覧できる利用者詳細・アセスメント・支援計画項目を owner/manager と分けるか決める。
- [x] app-admin が閲覧できる事務所スタッフ email / office contact / billing identifiers を用途別に分ける。
- [x] approval request の `request_data` 詳細閲覧権限を owner/manager/employee/app_admin で分ける。
- [x] Push購読 `endpoint` の生値閲覧を本人または system のみに制限する。
- [x] メール送信失敗 details の生値閲覧を system / app_admin_sensitive に限定する。
- [x] MFA secret / QR code / backup codes は発行直後の対象者または owner/manager の一時表示に限定する。

## 実装メモ

実装日: 2026-07-05

追加:

- `k_back/app/services/sensitive_access_service.py`
- `k_back/tests/services/test_sensitive_access_service.py`

実装内容:

- `SensitiveFieldGroup` で機微情報グループを定義。
- `permission_matrix()` で権限別表示表を返す。
- `TemporaryUnmaskGrant` で理由・対象・期限付きの一時マスク解除許可を表現。
- `can_view_unmasked()` で通常 app_admin は sensitive field を閲覧不可にし、対象一致・期限内の一時許可がある場合のみ閲覧可にする。
- Push購読 endpoint は `self` または `system` のみ生値閲覧可。
- MFA secret / QR code / recovery codes は本人または同一事業所 owner/manager の初回発行文脈のみ閲覧可として判定。
- `require_unmask_reason()` で理由入力を必須化。
- `create_unmask_audit_log()` で `privacy.unmask_viewed` を既存 `audit_logs` に記録。

今回の境界:

- 一時権限の永続テーブルは未作成。現時点ではDTOで判定ロジックを固定。
- app_admin問い合わせ一覧/詳細、app_admin事務所詳細、Push購読レスポンスの通常API表示ではマスク済みであることを確認。
- 一時マスク解除の実API、403/404の出し分け、画面での理由入力UIは未実装。
- 永続的な一時権限管理を行う場合は、別途マイグレーションとSQLファイルが必要。

## マスク解除フロー

1. 詳細閲覧が必要な理由を入力する。
2. 対象リソースと閲覧項目を選ぶ。
3. 一時権限を付与する。
4. マスク解除済みの閲覧イベントを監査ログに残す。
5. 一定時間後に一時権限を失効する。
6. incident 終了後に閲覧履歴を確認する。

## 監査ログに残す項目

- actor id
- actor role
- target type
- target id
- unmasked field group
- reason
- approval id
- timestamp
- expiry
- result

## 受け入れ要件

- [x] 権限別表示表がある。
- [x] 通常 app-admin では sensitive field がマスクされる。
- [x] app_admin_sensitive 等の追加権限がある場合だけ詳細を見られる。
- [x] マスク解除には理由入力が必要。
- [x] マスク解除イベントが監査ログに残る。
- [x] 一時権限には期限がある。
- [x] 期限切れ後は再びマスクされる。
- [ ] 権限不足時は 403、存在秘匿が必要な場合は 404 を使い分ける。

## 2026-07-05 API統合確認

確認済み:

- app_admin問い合わせ一覧: 本文全文・sender name/email をマスク。
- app_admin問い合わせ詳細: sender name/email、IP、User-Agent、delivery_log をマスク。
- app_admin事務所詳細: staff email、office address/phone/email をマスク。
- Push購読通常レスポンス: endpoint を `<registered>` として返す。

未実装:

- 一時マスク解除 grant を受け付ける API。
- マスク解除理由入力 UI。
- 一時 grant の永続化テーブル。
- 403/404 の出し分けを `SensitiveFieldGroup` 単位で API に適用する処理。

## 確認済みテスト

```bash
docker exec keikakun_app-backend-1 pytest tests/services/test_sensitive_access_service.py -q
# 6 passed

docker exec keikakun_app-backend-1 pytest tests/utils/test_privacy_utils.py tests/services/test_sensitive_access_service.py -q
# 19 passed

docker exec keikakun_app-backend-1 pytest tests/services/test_sensitive_access_service.py tests/security/test_security_log_static_check.py -q
# 11 passed
```
