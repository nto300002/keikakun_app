# 01-06 マスキング安全基準レビュー

作成日: 2026-07-05

## 結論

01-06 は、主要な API 表示・管理画面表示・E2E/CI ログの代表的な漏えい経路については対策が入っている。

ただし、マスキングにおける安全基準を完全に満たしているとはまだ言えない。現時点の判定は **部分達成** とする。

理由:

- 通常 API / 画面での代表的な機微情報の生返却は複数箇所で抑止済み。
- frontend / e2e 対象の危険ログ静的チェックは blocking mode で通過済み。
- backend / scripts には既存の危険ログ候補が warning mode で残っている。
- welfare recipient / assessment / support plan など、ドメイン横断の serializer 分離が未完了。
- production debug flag、ログ保存先のアクセス制御、保存期間、CI artifact 閲覧権限は運用・設定確認が未完了。

## 採用する安全基準

以下を安全基準として扱う。

- token / secret / password / MFA secret / backup code / QR code URI はログ・CIログ・監査ログ表示に出さない。
- request body / response body / raw webhook payload / raw audit details は汎用ログ・画面にそのまま出さない。
- email / name / phone / address / IP / User-Agent / Stripe ID / Push endpoint は用途別に mask / hash / present flag へ変換する。
- app-admin でも最小権限を前提にし、詳細閲覧は理由・期限・監査ログ付きの一時権限に限定する。
- ログ保存先、CI logs、CI artifacts は必要最小限の権限と短い保持期間にする。
- sanitizer を通さない危険な `logger.*` / `console.*` / `print()` を CI で検出する。
- production で request / response body や raw payload を出す debug flag を有効化できない。

参考基準:

- OWASP Logging Cheat Sheet: ログに機密情報・個人情報を含めない、またはマスク/サニタイズする。
- NIST SP 800-92: ログ管理では機密性・完全性・可用性、保存期間、アクセス制御を考慮する。
- GitHub Actions docs: artifacts / logs は repository 権限に依存するため、機微情報を含めない前提が必要。
- Google Cloud Logging docs: Data Access logs 等の閲覧は専用 IAM role で制御する。

## 01 APIレスポンス / 管理画面表示マスキング

判定: **部分達成**

達成済み:

- app-admin 監査ログ API は `details` を表示用マスクへ通す。
- app-admin 監査ログ画面は raw `JSON.stringify(log.details)` 表示を廃止。
- app-admin 問い合わせ一覧は本文全文を返さず、sender name/email をマスク。
- app-admin 問い合わせ詳細は sender name/email、IP、User-Agent、delivery_log をマスク。
- app-admin 事務所詳細は office contact と staff email を通常表示でマスク。
- Push subscription `endpoint` は通常レスポンスで `<registered>` 化。
- employee action request の `request_data` は利用者住所・電話・障害情報を表示用にマスクする代表テストあり。

未達 / 残リスク:

- welfare recipient list/detail 用 serializer 分離が未完了。
- assessment / support plan / monitoring / PDF download 周辺の list/detail serializer 分離が未完了。
- email failure details の全経路で recipient / subject / 外部エラー本文が生返却されないことの確認が不足。
- app-admin 事務所一覧の contact 表示要否は未確認。

判定理由:

代表的な app-admin 表示漏えいは抑止できているが、利用者・支援計画・PDF など業務ドメイン全体の表示面はまだ網羅できていない。

## 02 Audit Log / Webhook Payload / Request Data マスキング

判定: **部分達成**

達成済み:

- audit log API は `mask_sensitive_details_for_display()` を通す。
- webhook response schema は payload 表示時に sanitizer を通すテストあり。
- Stripe ID は `<present>` 方向へ寄せる代表テストあり。
- employee action request の `original_request_data` は welfare recipient の詳細情報をマスクする代表テストあり。
- frontend の raw details / raw payload / raw request_data の単純 JSON 表示リスクを低減。

未達 / 残リスク:

- action ごとの allowlist schema は未完成。
- audit log 保存前 sanitizer は全経路には強制されていない。
- webhook payload API が将来追加された場合に allowlist 以外を返さない強制機構は弱い。
- office update の `old_values` / `new_values` は表示時の代表確認はあるが、全 action 網羅ではない。

判定理由:

表示時マスクは進んでいるが、保存前共通 sanitizer と action 別 allowlist が未完成のため、raw details が DB に残り、将来の表示 API 追加で再露出する余地がある。

## 03 ログ / CI / 標準出力の削除・マスキング

判定: **部分達成**

達成済み:

- Stripe Customer Portal Session 作成失敗ログの `stripe_customer_id` 生値出力を抑止。
- Stripe webhook ログの Stripe object id 生値出力を抑止する代表テストあり。
- E2E `/auth/token` response body 出力を sanitizer 経由へ変更。
- E2E 利用者登録 API response body 出力を sanitizer 経由へ変更。
- E2E thrown error に raw API response body を含めない helper を追加。
- frontend Push購読解除失敗時に `apiErr` object を直接 console 出力しない。
- frontend / e2e 対象の static check は blocking mode で通過。

未達 / 残リスク:

- backend / scripts の static check は warning mode で既存検出が残る。
- `app/api/deps.py`、MFA/Auth 周辺、運用スクリプトの `print()` に危険語候補が残る。
- 一部は false positive だが、MFA初回検証の user_id ログなどは実リスクとして是正対象。
- 運用スクリプトの email/name/Stripe ID マスク標準化は未完了。
- Google Calendar 系 `str(e)` 伝播の全経路確認は未完了。

確認した warning mode 検出例:

- `app/api/deps.py`: token / payload / password 関連ログ候補。
- `app/api/v1/endpoints/auths.py`: MFA / temporary token / secret 関連ログ候補。
- `scripts/create_app_admin.py`: password / secret を含む usage / example 出力候補。
- `scripts/test_webpush_exception.py`: response object 出力候補。

判定理由:

CI/E2E の高リスクな body 出力は塞げているが、backend/scripts 全体を blocking にできないため、ログ安全基準としては未達が残る。

## 04 ドメイン別 機微情報マスキング

判定: **部分達成**

達成済み:

- Staff / Office: app-admin 事務所詳細の staff email と office contact をマスク。
- Inquiry: 一覧 summary 化、詳細の sender metadata / delivery_log マスク。
- Billing / Stripe / Webhook: 代表的な Stripe ID は present 化。
- MFA / Auth: 権限設計上は secret / QR / recovery code を初回表示に限定する方針を定義。
- Push Subscription: endpoint の通常レスポンス生返却を抑止。

未達 / 残リスク:

- staff list/detail の role 別返却項目分離が未完了。
- deleted / archived staff の匿名化優先表示が未完了。
- welfare recipient list/detail の項目別 serializer 分離が未完了。
- assessment / support plan / monitoring の医療・家族・就労詳細の最小化が未完了。
- message / notice の本文に利用者名や申請内容が含まれる前提での表示範囲確認が未完了。
- Push の `p256dh` / `auth` / `user_agent` 全経路確認が未完了。

判定理由:

代表ドメインの対策は入ったが、障害福祉ドメインとして最も機微度が高い welfare recipient / assessment / support plan の網羅が未完了。

## 05 権限設計 / マスク解除 / 監査フロー

判定: **設計・判定ロジックは達成、API統合は未達**

達成済み:

- `SensitiveFieldGroup` で機微情報グループを定義。
- `permission_matrix()` で権限別表示表を返せる。
- `TemporaryUnmaskGrant` で理由・対象・期限付き一時許可を表現。
- `can_view_unmasked()` で通常 app_admin は sensitive field を閲覧不可にする。
- `require_unmask_reason()` で理由入力を必須化。
- `create_unmask_audit_log()` で `privacy.unmask_viewed` を audit log に残せる。
- 単体テストで期限切れ後の再マスクなどを確認済み。

未達 / 残リスク:

- 一時 grant の永続テーブルがない。
- マスク解除 API がない。
- 理由入力 UI がない。
- 403 / 404 の出し分けが API に統合されていない。
- 実 API で `SensitiveFieldGroup` 単位の判定を強制する middleware / dependency は未実装。

判定理由:

安全設計の核となるロジックはあるが、実運用でマスク解除を安全に使うための API / UI / 永続化が未実装。

## 06 テスト / 静的チェック / 完了条件

判定: **部分達成**

達成済み:

- frontend / e2e の危険ログ static check を blocking mode で CI へ追加。
- backend の logger / print、frontend の console を検出する静的チェックを追加。
- sanitizer helper、権限判定、代表 API のテストを追加。
- 代表テストは通過済み。

未達 / 残リスク:

- backend / scripts は warning mode 継続。
- allowlist の理由・期限・担当者付き管理は未実装。
- production debug body 出力禁止の fail-fast は未確認。
- ログ保存先のアクセス制御、保存期間、CI artifact 閲覧権限は実環境設定確認が未完了。
- 危険ログ追加を backend / scripts まで CI で完全 blocking する段階には未到達。

判定理由:

静的チェックと代表テストは有効だが、完了条件である「全体 blocking」「実環境運用設定」「debug flag 管理」までは満たしていない。

## 実行確認

確認日: 2026-07-05

```bash
docker exec keikakun_app-backend-1 pytest \
  tests/utils/test_privacy_utils.py \
  tests/services/test_sensitive_access_service.py \
  tests/security/test_security_log_static_check.py \
  tests/api/v1/test_admin_audit_logs.py \
  tests/api/test_billing.py::test_create_portal_session_logs_safe_context_on_stripe_error \
  tests/api/test_billing.py::test_webhook_logs_mask_stripe_object_ids \
  tests/api/v1/test_employee_action_requests.py::test_get_pending_requests_masks_welfare_recipient_sensitive_request_data \
  tests/api/v1/test_inquiry_endpoints.py::TestAdminInquiryListEndpoint::test_get_inquiries_masks_sensitive_fields_in_list \
  tests/api/v1/test_inquiry_endpoints.py::TestAdminInquiryDetailEndpoint::test_get_inquiry_detail_masks_sender_metadata_and_delivery_log \
  tests/api/v1/test_admin_offices.py::test_app_admin_get_office_detail \
  tests/api/v1/test_push_subscriptions.py::TestSubscribePush::test_subscribe_success -q

# 39 passed, 2 warnings
```

```bash
docker exec keikakun_app-backend-1 python scripts/security_log_static_check.py --mode block ../k_front

# exit 0
```

```bash
docker exec keikakun_app-backend-1 python scripts/security_log_static_check.py --mode warn app scripts ../k_front

# backend / scripts に既存検出あり
```

## 合格までの必須対応

優先度高:

1. backend / scripts の static check 検出を棚卸しし、実リスクと false positive を分ける。
2. MFA/Auth 周辺ログから user_id / token / secret / temporary token 関連の生値・紐付け情報を除去する。
3. 運用スクリプトの email/name/Stripe ID/staff_id/office_id 出力を mask helper 経由にする。
4. welfare recipient list/detail serializer を分離し、住所・電話・緊急連絡先・障害詳細を通常一覧から除外する。
5. assessment / support plan / monitoring / PDF download の表示・ログ・URL出力を確認する。

優先度中:

1. audit log action 別 allowlist schema を作る。
2. audit log 保存前 sanitizer を共通化する。
3. email failure details の recipient / subject / 外部エラー本文の全経路テストを追加する。
4. Push `p256dh` / `auth` / `user_agent` のレスポンス・ログ露出確認を追加する。
5. allowlist を理由・期限・担当者付きで管理する。

運用・環境:

1. production で `DEBUG=true` / `LOG_LEVEL=DEBUG` / body dump flag を fail-fast または安全値へ丸める。
2. Cloud Logging / Cloud Build / GitHub Actions / Vercel のログ閲覧権限を棚卸しする。
3. CI artifacts の retention days と閲覧権限を明示する。
4. Playwright trace / screenshot / video が失敗時のみ短期保存になっているか確認する。
5. 既存ログに raw body / raw payload が含まれていた場合の削除・保持判断を記録する。

## 追加判断: 実装時に不明点として残った項目

判断日: 2026-07-05

他の実装者が判断保留として残した以下3点について、現状仕様・実装に基づく判断を記録する。

### Assessment の employee / owner / manager 別表示範囲

現状:

- Assessment API は `verify_recipient_access()` による同一事業所アクセス確認が中心。
- `owner` / `manager` / `employee` で `AssessmentResponse`、家族構成、医療情報、通院歴、就労情報、課題分析の返却差分はほぼない。
- 現状は「同一事業所スタッフ向け詳細業務 API」として全量返却される設計になっている。

判断:

- **現状仕様のまま employee に Assessment 詳細を全量返すのは、マスキング安全基準として許可が広すぎる。**
- `employee` は summary 表示を原則とし、医療・家族・就労・課題分析の詳細は担当者または明示権限がある場合に限定する。
- `owner` / `manager` は業務管理上の必要性が高いため、同一事業所内では詳細閲覧可とする。ただしログ出力・一覧表示・通知本文では詳細を出さない。

推奨仕様:

- `owner` / `manager`
  - Assessment 詳細を閲覧可。
  - 医療・家族・就労・課題分析の詳細を API 返却可。
  - 操作ログには詳細本文を残さず、件数・対象ID・action のみ記録する。
- `employee`
  - 通常一覧・ダッシュボードでは summary のみ。
  - 返却可: assessment の存在有無、完了状態、期限、担当タスク、最新ステップ、更新日時。
  - 通常非返却: 家族構成詳細、医療保険・通院先・通院歴、就労先・就労経験詳細、課題分析本文。
  - 詳細閲覧が必要な場合は、担当者判定または `SensitiveFieldGroup.welfare_recipient_detail` / assessment 用 group による明示権限で許可する。

実装方針:

- `AssessmentSummaryResponse` を追加する。
- `AssessmentResponse` は owner / manager / 明示権限あり employee 用に限定する。
- employee 通常取得では summary schema を返すか、詳細項目を `<redacted>` にする。
- assessment / support plan / monitoring / PDF download の file name・presigned URL はログに出さない。

### backend/scripts の静的チェック blocking 化

現状:

- `python scripts/security_log_static_check.py --mode block ../k_front` は通過する。
- `python scripts/security_log_static_check.py --mode block app scripts ../k_front` は既存検出が残るため失敗する。
- warning mode では `app/api/deps.py`、MFA/Auth 周辺、運用スクリプト、webpush 検証スクリプトなどに危険語候補が残る。
- 検出には false positive も含まれるが、MFA初回検証の user_id ログ、response object 出力候補、運用スクリプトの secret/password 文言など、実リスクも混ざっている。

判断:

- **現時点で backend/scripts 全体を blocking 化するのは早い。**
- frontend/e2e は blocking を維持し、backend/app と scripts は棚卸し後に段階的に blocking 化する。
- warning mode のまま放置するのではなく、検出結果を「実リスク」「安全だが文言で検出」「テスト専用」「削除可能な古いスクリプト」に分類する。

推奨仕様:

- CI blocking 対象:
  - 現時点: frontend/e2e。
  - 次段階: `k_back/app` の logger 検出。
  - 最終段階: `k_back/scripts` / tests の print / console 検出。
- allowlist は inline comment ではなく、理由・期限・担当者付きの管理ファイルで扱う。
- false positive でも、可能なら危険語を避ける文言へ変更する。
- `type(e).__name__`、`*_present`、`*_count`、sanitizer helper 経由のログのみ許可する。

実装方針:

1. warning mode 出力を棚卸し表にする。
2. MFA/Auth、token、secret、response body、request body、payload を最優先で修正する。
3. 運用スクリプトは本番接続可能性があるものから修正する。
4. backend/app の検出が解消された段階で `app` を blocking 化する。
5. scripts は削除・隔離・mask helper 適用後に blocking 化する。

### MFA/Auth の再取得不可・再露出防止

現状:

- 自己登録の `/mfa/enroll` は初回登録のため `secret_key` と `qr_code_uri` を返す。
- 管理者による単体 MFA 有効化は `secret_key`、`qr_code_uri`、`recovery_codes` を管理者レスポンスに返す。
- 管理者による一括 MFA 有効化は全スタッフ分の `secret_key`、`qr_code_uri`、`recovery_codes` を `staff_mfa_data` として返す。
- recovery codes は DB には hash 保存されるが、レスポンスでは平文が返る。
- MFA 初回検証ログには user_id を含むログが残っている。

判断:

- **自己登録の初回表示として `secret_key` / `qr_code_uri` を返すことは許容する。**
- **保存後・検証後の secret / QR / recovery codes 再取得は不可にする。**
- **管理者一括 MFA 有効化で全スタッフ分の secret / QR / recovery codes を返す現仕様は、開示範囲が広すぎるため変更する。**
- **管理者が所属事務所スタッフの MFA 状態を個別に変更できる機能は維持する。**
- MFA/Auth は影響範囲が大きいため、このマスキングPR内ではなく別 issue で仕様変更・テスト追加を行う。

推奨仕様:

- 自己登録:
  - `/mfa/enroll` の初回レスポンスのみ `secret_key` / `qr_code_uri` を返却可。
  - `/mfa/verify` 後は secret / QR / recovery codes を再取得不可。
- recovery codes:
  - 本人に一度だけ表示する。
  - DB は hash のみ保存する。
  - 再表示 API は作らない。必要な場合は再生成して旧コードを失効する。
- 管理者単体有効化:
  - 所属事務所スタッフの MFA 状態変更機能は維持する。
  - 推奨は、管理者が「MFA設定を要求/リセット」し、対象本人が次回ログインまたは専用セットアップ画面で初回登録する方式。
  - 管理者レスポンスは `mfa_status`、`setup_required`、`staff_id`、masked staff name 程度に留める。
  - 管理者レスポンスに secret / recovery codes を返す場合でも、単体・短時間・監査ログ付きに限定し、一括レスポンスでは禁止する。
- 管理者一括有効化:
  - secret / QR / recovery codes をレスポンスに含めない。
  - 返却は `enabled_count`、対象 staff の masked name / id suffix、`setup_required` 程度にする。
- ログ:
  - temporary token、TOTP code、recovery code、MFA secret、QR URI は出力禁止。
  - user_id は raw では出さず、必要な場合は suffix/hash/present にする。

別 issue 化:

- この項目は `keikakun_app` の別 issue として管理する。
- issue では「MFA/Auth の再取得不可・管理者一括有効化レスポンスの縮小・ログ再露出防止テスト」を扱う。

## 最終判定

現時点では **安全基準を完全には満たしていない**。

ただし、以下の範囲では安全基準を概ね満たしている。

- app-admin 問い合わせ一覧/詳細の通常表示。
- app-admin 事務所詳細の通常表示。
- Push subscription endpoint の通常レスポンス。

## 2026-07-05 再実装レビュー追記

対象:

- `04_domain_sensitive_data_masking.md`
- `05_permissions_and_unmasking_flow.md`
- `06_tests_static_checks_and_acceptance.md`

レビュー結論:

- 今回の再実装で、04 の Staff/Office、Inquiry、Push の代表経路は TDD で GREEN まで確認済み。
- 05 はサービス設計・判定ロジックに加えて、通常 API 表示でのマスク適用確認が進んだ。ただし一時マスク解除 API / UI / 永続化は未実装のため、運用機能としては未完了。
- 06 は frontend/e2e の blocking 静的チェックまで進んだ。backend/scripts は既存検出が残るため warning mode 継続が妥当。

今回確認した実装:

- `OfficeDetailResponse` / `StaffInOffice`
  - app_admin 事務所詳細の office contact と staff email を表示時にマスク。
- `InquiryListItem`
  - 問い合わせ一覧で本文全文を返さず、sender name/email をマスク。
- `InquiryDetailResponse`
  - sender name/email、IP、User-Agent、delivery_log を表示時にマスク。
- `mask_sensitive_details_for_display()`
  - `delivery_log.recipient` のメールアドレスをマスク対象に追加。
- `PushSubscriptionResponse`
  - endpoint を通常レスポンスで `<registered>` として返す既存実装をテストで確認。
- `security_log_static_check.py`
  - Python の `logger.*` / `print()` 検出に加え、frontend/e2e の `console.log/debug/warn/error` 検出を追加。
  - `--mode block` の戻り値をテストで固定。
- `.github/workflows/security-check.yml`
  - frontend/e2e 対象の blocking 静的チェック step を追加。

実行確認:

```bash
docker exec keikakun_app-backend-1 pytest \
  tests/utils/test_privacy_utils.py \
  tests/api/v1/test_inquiry_endpoints.py::TestAdminInquiryListEndpoint::test_get_inquiries_masks_sensitive_fields_in_list \
  tests/api/v1/test_inquiry_endpoints.py::TestAdminInquiryDetailEndpoint::test_get_inquiry_detail_masks_sender_metadata_and_delivery_log \
  tests/api/v1/test_admin_offices.py::test_app_admin_get_office_detail \
  tests/api/v1/test_push_subscriptions.py::TestSubscribePush::test_subscribe_success \
  tests/services/test_sensitive_access_service.py \
  tests/security/test_security_log_static_check.py -q

# 28 passed, 2 warnings
```

```bash
docker exec keikakun_app-backend-1 python scripts/security_log_static_check.py --mode block ../k_front

# exit 0
```

安全性評価:

- 通常 app_admin 表示での Staff/Office、Inquiry、Push endpoint の生値露出リスクは低下した。
- frontend/e2e で危険な `console.*` が追加された場合は CI で検出できる見通しになった。
- backend/scripts は全体 blocking にすると既存検出で落ちるため、まだ安全基準としては未達。
- Assessment / Support Plan / Welfare Recipient は仕様判断が必要で、今回の再実装では意図的に未修正。

残判断:

- Assessment の employee / owner / manager 別の表示範囲を決める必要がある。
  - 現状は同一事業所スタッフ向け詳細業務 API として全量取得される。
  - 医療・家族・就労情報を employee から隠すと既存業務フローに影響する可能性がある。
- backend/scripts の静的チェックを blocking 化するには、既存検出を実リスク / false positive に分ける必要がある。
- MFA/Auth の「初回発行後に secret / QR / recovery codes を再取得できない」ことは、追加の API テストで固定する必要がある。
- 一時マスク解除はサービス案に留まっており、API / UI / DB 永続化を実装するかどうか判断が必要。

判定:

- 04: 代表経路は改善済み。ただし welfare recipient / assessment / support plan は未完了のため **部分達成**。
- 05: 判定ロジックと通常 API 表示確認は進捗。ただしマスク解除機能としては **API統合未達**。
- 06: frontend/e2e blocking は達成。backend/scripts blocking は未達のため **部分達成**。
- frontend/e2e の response body 生ログ出力抑止。
- Stripe webhook / portal session 周辺の代表ログ。
- 一時マスク解除の設計・判定ロジック。

残る主な未達は、backend/scripts 全体のログ安全、welfare recipient / assessment / support plan のドメイン網羅、実環境のログアクセス制御・保存期間・debug flag 管理である。
