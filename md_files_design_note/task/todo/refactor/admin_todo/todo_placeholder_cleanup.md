# TODO/仮実装の利用者向け導線整理

作成日: 2026-07-01

## 目的

`maintainability_research.md` の「9. TODO/仮実装が利用者向け機能に残っている」を、実装前に扱えるタスクとして切り出す。

利用者や管理者が触れる画面・APIに、未接続API、仮待機、仮データ、未実装コメントが残っている場合、画面上は動いているように見えても実際には処理が完了していない可能性がある。まずは対象を分類し、仕様確定・実装・削除のどれで扱うかを明確にする。

## 基本方針

- 利用者向け導線にあるTODO/仮実装を優先して確認する。
- 入力欄の `placeholder` や通常の成功メッセージ用 `setTimeout` は対象外とする。
- TODOを見つけたら、少なくとも以下のいずれかに分類する。
  - `仕様未確定`: 何を実装すべきか決まっていない。
  - `未実装`: 仕様はあるが実装されていない。
  - `削除予定`: 現在の仕様では不要。
  - `確認用`: 利用者導線に出ない開発/運用確認用途。
- 利用者導線にある `未実装` は、TDDで既存挙動または期待挙動を固定してから実装する。
- 削除する場合も、呼び出し元・画面導線・APIレスポンスに影響がないことを確認する。

## 調査コマンド

TODO/仮実装候補:

```bash
rg -n "TODO|FIXME|仮|暫定|未実装|placeholder|mock|dummy|coming soon|あとで|一時的" \
  k_back/app k_front/app k_front/components k_front/lib \
  --glob '!**/__pycache__/**' \
  --glob '!**/.next/**' \
  --glob '!**/node_modules/**'
```

利用者向けコードに絞る場合:

```bash
rg -n "TODO|FIXME|仮の実装|未実装|実装後に接続|仮データ|example@example.com" \
  k_back/app k_front/app k_front/components \
  --glob '!**/__pycache__/**' \
  --glob '!**/.next/**'
```

## 現時点の候補

### P0: 問い合わせ返信モーダルの仮実装（対応済み）

該当箇所:

- `k_front/components/admin/inquiry/InquiryReplyModal.tsx`

確認された内容:

- `TODO: APIエンドポイントを実装後に接続`
- `仮の実装: 2秒待機`

リスク:

- 管理者が返信できたように見えて、実際には返信APIへ接続されていない可能性がある。
- 成功表示が出る場合、問い合わせ対応済みと誤認する。

対応方針:

- 返信APIが存在するか確認する。
- APIが存在する場合は接続する。
- APIが存在しない場合は、画面上の送信導線を非表示または明確な未対応状態にする。
- 返信成功/失敗のテストを追加する。

受け入れ要件:

- [x] 返信ボタン押下時に仮待機だけで成功扱いにならない。
- [x] API未接続の場合、利用者向けには送信成功の表示をしない。
- [x] API接続済みの場合、成功時・失敗時の表示がテストされている。

対応結果:

- `k_front/components/admin/inquiry/InquiryReplyModal.tsx` の `setTimeout(2000)` 仮待機を削除。
- 既存の `inquiryApi.replyToInquiry()` へ接続。
- バックエンドには `POST /api/v1/admin/inquiries/{inquiry_id}/reply` とAPIテストが既に存在することを確認。
- フロント側は送信情報の受け渡しを `newInquiriesTab.helpers.ts` に切り出し、Node testで固定。

### P0: 新規問い合わせタブの仮データ（対応済み）

該当箇所:

- `k_front/components/protected/app-admin/tabs/NewInquiriesTab.tsx`

確認された内容:

- `inquiryTitle="問い合わせ件名" // TODO: 実際の件名を渡す`
- `senderEmail="example@example.com" // TODO: 実際の送信者メールを渡す`

リスク:

- 管理者画面で問い合わせ本文や送信者情報が実データではなく固定値になる可能性がある。
- 返信先や問い合わせ識別を誤る。

対応方針:

- 一覧から選択した問い合わせの実データを `InquiryReplyModal` へ渡す。
- 実データがない場合は返信導線を無効化する。

受け入れ要件:

- [x] 返信モーダルに実際の問い合わせ件名が表示される。
- [x] 返信モーダルに実際の送信者メールが表示される。
- [x] 固定の `問い合わせ件名` / `example@example.com` が利用者導線に残らない。

対応結果:

- `InquiryDetail` で取得済みの `InquiryFullResponse` から返信モーダル用の `inquiryId` / `inquiryTitle` / `senderEmail` を生成。
- `NewInquiriesTab` は固定値を持たず、詳細画面から渡された実データだけを `InquiryReplyModal` に渡す。
- `senderEmail` が存在しない問い合わせでは `null` のまま渡す。

### P1: 管理者監査ログAPIの名前解決TODO（対応済み）

該当箇所:

- `k_back/app/api/v1/endpoints/admin_audit_logs.py`

確認された内容:

- `actor_name: None  # TODO: リレーションシップから取得`
- `office_name: None  # TODO: リレーションシップから取得`

リスク:

- 監査ログ画面で誰が、どの事業所で操作したかを判断しにくい。
- セキュリティ調査時の運用性が低い。

対応方針:

- 既存APIレスポンスの互換性を保ちつつ、可能なら `actor_name` / `office_name` を解決する。
- 名前解決で追加クエリが増えすぎないよう、join/eager loadを検討する。

受け入れ要件:

- [x] staffが存在する監査ログでは `actor_name` が返る。
- [x] officeが存在する監査ログでは `office_name` が返る。
- [x] staff/office削除済みの場合もAPIが500にならない。

対応結果:

- `k_back/app/api/v1/endpoints/admin_audit_logs.py` で、取得ページ内の `staff_id` / `office_id` を一括収集し、`Staff.full_name` / `Office.name` を追加クエリ2本以内で解決。
- 既存レスポンスキーは変更せず、従来 `None` だった `actor_name` / `office_name` のみ可能な範囲で埋める。
- `staff_id` / `office_id` が `NULL`、または参照先が存在しない場合は `None` のまま返す。

### P1: 利用者関連データ更新の未実装TODO

該当箇所:

- `k_back/app/crud/crud_welfare_recipient.py`

確認された内容:

- `TODO: Implement full update for related data (details, contacts, etc.)`

リスク:

- 利用者本体は更新されたように見えて、詳細情報・連絡先など関連データが更新されない可能性がある。
- 編集画面の保存結果とDB状態がずれる。

対応方針:

- 現在どの画面/APIがこのCRUDを通っているか確認する。
- 既にService層で関連データ更新を担っている場合、このTODOは削除またはコメント修正する。
- 未実装の場合は、関連データ単位でTDD実装する。

確認結果:

- `PUT /api/v1/welfare-recipients/{recipient_id}` は `crud_welfare_recipient.update_comprehensive()` を通る。
- `update_comprehensive()` は基本情報と `ServiceRecipientDetail` の一部のみ更新し、緊急連絡先・障害詳細の全差し替え/同期は未実装。
- 一方で、アセスメント系の関連データには個別更新API/CRUDが既に存在する。
  - 家族構成: `GET/POST /recipients/{recipient_id}/family-members`, `PATCH/DELETE /family-members/{family_member_id}`
  - 福祉サービス利用歴: `GET/POST /recipients/{recipient_id}/service-history`, `PATCH/DELETE /service-history/{history_id}`
  - 医療基本情報: `GET/PUT /recipients/{recipient_id}/medical-info`
  - 就労関連: `GET/PUT /recipients/{recipient_id}/employment`
  - 課題分析: `GET/PUT /recipients/{recipient_id}/issue-analysis`
- したがって、このTODOは「似た機能が未実装」ではなく、「包括更新APIが個別更新APIと同等の関連データ同期を持っていない」という責務不一致。
- 安全に進める場合は、包括更新に全関連データ同期を追加する前に、フロントが現在どの保存導線で `PUT /welfare-recipients/{id}` と個別アセスメントAPIを使い分けているかを固定する必要がある。

受け入れ要件:

- [x] 利用者編集時に本体データと関連データの更新責務が明確になっている。
- [x] TODOが現行実装と矛盾していない。
- [ ] 未実装であれば、対象関連データごとのテストがある。

### P2: システムアカウントUUID TODO

該当箇所:

- `k_back/app/utils/email_utils.py`

確認された内容:

- `TODO: システムアカウントのUUIDを設定する`

リスク:

- メール送信や監査ログの作成者が曖昧になる可能性がある。
- 本番運用で「誰が実行した処理か」を追跡しづらい。

対応方針:

- システムアカウントをDBに持つ設計か、設定値として持つ設計かを確認する。
- 監査ログやメール送信履歴で必要な場合のみ対応する。

受け入れ要件:

- [ ] システム処理の実行者表現が仕様として決まっている。
- [ ] 必要な場合、環境変数またはDB上のsystem staffとして参照できる。
- [ ] 不要な場合、TODOを削除し理由をコメントまたはmdに残す。

## 対象外にするもの

以下は今回の「仮実装」整理の対象外とする。

- 入力欄の通常 `placeholder`
- UI上の短時間メッセージ表示用 `setTimeout`
- retry/backoff目的の `asyncio.sleep`
- テストコードや開発用script内のmock/dummy
- コメントとしての「一時的」が、実際には既に責務分離済みで利用者導線に出ないもの

## TDD方針

P0から順に進める。

1. 現在の仮挙動をテストで確認する。
2. 期待挙動をRedテストとして追加する。
3. API接続または導線非表示の最小実装を行う。
4. 既存画面文言・APIレスポンスの互換性を確認する。

## 優先順位

1. `InquiryReplyModal.tsx` の仮待機/未接続API
2. `NewInquiriesTab.tsx` の固定問い合わせ情報
3. `admin_audit_logs.py` の名前解決
4. `crud_welfare_recipient.py` の関連データ更新TODO
5. `email_utils.py` のsystem account UUID

## チェックリスト

- [x] TODO/仮実装候補をP0/P1/P2へ分類した。
- [x] P0の利用者導線について、実際に画面から到達できるか確認した。
- [x] 仮待機や固定データで成功扱いになっていない。
- [x] API未接続の場合は、利用者に誤解を与える成功表示をしない。
- [x] 実装する場合はRedテストを先に追加した。
- [ ] 削除する場合は呼び出し元がないことを確認した。

## 実行確認

2026-07-02:

```bash
cd k_front
./node_modules/.bin/tsc --target ES2022 --module commonjs --moduleResolution node --esModuleInterop --skipLibCheck --jsx react-jsx --outDir /tmp/new-inquiries-tests --noEmit false components/protected/app-admin/tabs/newInquiriesTab.helpers.ts components/protected/app-admin/tabs/newInquiriesTab.helpers.test.ts
NODE_PATH=$(pwd)/node_modules node --test /tmp/new-inquiries-tests/components/protected/app-admin/tabs/newInquiriesTab.helpers.test.js
npm run lint
./node_modules/.bin/tsc --noEmit

cd ..
docker compose exec backend python -m pytest tests/api/v1/test_admin_audit_logs.py -q
```

結果:

- フロント問い合わせ返信情報テスト: 2 passed
- フロント lint: pass
- フロント TypeScript: pass
- バックエンド監査ログAPIテスト: 7 passed
