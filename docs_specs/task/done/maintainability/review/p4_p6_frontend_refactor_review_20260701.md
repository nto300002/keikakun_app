# P4-P6 フロントエンド保守性リファクタリングレビュー

作成日: 2026-07-01

## 対象

- P4: `k_front/components/protected/dashboard/Dashboard.tsx` のhook/表示分離
- P5: `k_front/components/protected/recipients/RecipientRegistrationForm.tsx` / `RecipientEditForm.tsx` の共通form分離
- P6: `k_front/components/protected/admin/AdminMenu.tsx` のtab単位分離

参照:

- `md_files_design_note/task/todo/refactor/maintainability/maintainability_research.md`
- `k_front/components/protected/dashboard/Dashboard.tsx`
- `k_front/components/protected/recipients/RecipientRegistrationForm.tsx`
- `k_front/components/protected/recipients/RecipientEditForm.tsx`
- `k_front/components/protected/recipients/forms/*`
- `k_front/components/protected/admin/AdminMenu.tsx`
- `k_front/components/protected/admin/*Tab.tsx`
- `k_front/components/protected/admin/OfficeEditModal.tsx`

## 総評

P5とP6は、既存の画面文言・submit処理・API呼び出し契約を大きく変えずに、表示と共通ロジックを段階的に分離できている。特にP5は、型、初期値、選択肢、validation、mapper、form state、section描画まで分割され、巨大フォームの変更リスクはかなり下がった。

P4は検索・filter・sort状態管理の抽出まで進んだ。ログイン後の主要画面であり、初期取得、削除、課金制限表示、一覧描画はまだ同居しているため、残タスクは段階的に進める必要がある。

P6はtab表示分離と安全範囲の追加リファクタまで完了しているが、Google Calendar/MFA/事業所編集保存処理のhook化は副作用を含むため、現時点で無理に進めない判断は妥当。

## P4レビュー: Dashboard hook/表示分離

状態:

- 一部実施済み。
- `Dashboard.tsx` は約1165行から約999行へ縮小。
- `useDashboardFilters.ts` を追加し、検索語、sort、filter状態、debounce、API params生成を分離。
- `ActiveFilters.tsx` は既存のまま利用。
- `useDashboardData` / `DashboardRecipientTable` は未実装。

評価:

- 低リスクな検索・sort・filter状態管理から着手しており、P4の最初の分割として妥当。
- API取得、削除、課金制限表示、一覧描画は親に残っているため、主要導線の副作用は動かしていない。
- `buildDashboardParams()` / `getNextDashboardSortOrder()` / `getDashboardSortButtonLabel()` / `hasDashboardFilter()` が純粋関数化され、単体テスト可能になった。

推奨する次の最小タスク:

1. `useDashboardData` を追加する前に、初期取得、filter再取得、reset取得の現在のloading/error挙動をチェックリスト化する。
2. 一覧描画切り出しは `DashboardRecipientTable` より先に、PC tableとmobile cardの共通表示判断を整理する。
3. 課金制限表示判定は `billingRestrictionWarning` を小さな純粋関数へ移すところから始める。

残リスク:

- `useDashboardData` 抽出はAPI再取得やloading/error状態の責務が動くため、次に進める場合はテストまたは手動確認観点が必要。
- `filter=deadline_alert` query は現時点で初期filter状態だけを変えており、初期API取得条件までは変えていない。この既存挙動を変える場合は別タスクにする。
- 一覧描画はPC/mobileで重複が大きいが、リンク、削除、employee申請、課金制限が絡むため一括分離は避ける。

## P5レビュー: 利用者登録/編集フォーム共通化

状態:

- 実施済み。
- `RecipientRegistrationForm.tsx`: 約340行。
- `RecipientEditForm.tsx`: 約297行。
- `components/protected/recipients/forms/` に共通定義、mapper、state、section component、テストが追加済み。

実施内容の評価:

- `recipientFormTypes.ts` にフォームデータ型を集約したことで、登録/編集間の構造差分が読みやすくなった。
- `recipientFormDefaults.ts` / `recipientFormOptions.ts` に初期値と選択肢を寄せたことで、選択肢追加時の二重修正リスクが下がった。
- `recipientFormValidation.ts` は `mode` で登録/編集差分を明示しており、既存挙動を隠していない点がよい。
- `recipientFormMapper.ts` で編集フォームの `initialData` 変換を分離したため、APIレスポンスのsnake_case/camelCase混在を局所化できている。
- `useRecipientFormState.ts` と `recipientFormState.ts` の分離により、React hookと純粋なstate操作を分けてテストしやすくなっている。
- section component分割により、フォーム本体はsubmit処理とemployee申請modal中心のcontainerになっている。

確認済み事項:

- `npm run lint`: 成功。
- `./node_modules/.bin/tsc --noEmit`: 成功。
- `recipientFormValidation.test.ts` / `recipientFormMapper.test.ts` / `recipientFormState.test.ts` / `recipientFormSections.test.ts` の実行記録あり。

残リスク:

- section componentのpropsが増えやすいため、今後入力項目を追加する場合は `recipientFormSectionProps.ts` を先に確認する必要がある。
- 登録/編集固有のsubmit処理とemployee申請modalは各コンテナに残っている。これは現時点では妥当だが、申請modal側の仕様変更が続くなら次の分離候補になる。
- UIの視覚回帰はlint/tscだけでは検出できない。大きな項目追加時は登録/編集画面の手動確認またはE2E確認が必要。

追加リファクタ判断:

- P5は現時点で一区切りとしてよい。
- 追加で触るなら、submit前payload生成の純粋関数化が候補。ただし挙動差分が出やすいため、次PR以降に分ける。

## P6レビュー: AdminMenu tab単位分離

状態:

- 安全範囲まで実施済み。
- `AdminMenu.tsx`: 1526行から985行、追加リファクタ後に約881行。
- 追加済み:
  - `OfficeInfoTab.tsx`
  - `StaffManagementTab.tsx`
  - `GoogleIntegrationTab.tsx`
  - `BillingPlanTab.tsx`
  - `OfficeEditModal.tsx`

実施内容の評価:

- tab表示を `OfficeInfoTab` / `StaffManagementTab` / `GoogleIntegrationTab` / `BillingPlanTab` に分けたことで、`AdminMenu.tsx` の読み込み範囲は明確に狭くなった。
- `BillingPlanTab.tsx` は既存 `PlanTab` を再exportしており、破壊的なリネームを避けている。安全性を優先した判断として妥当。
- `OfficeEditModal.tsx` は表示だけを分離し、保存処理、入力state、差分生成、保存後reloadを親に残している。今回の「リスクあるものは変更しない」方針に合っている。
- Google CalendarとMFAの状態管理はまだ親に残っているが、API副作用とスタッフ再取得が絡むため、現時点では残す判断が安全。

確認済み事項:

- `npm run lint`: 成功。
- `./node_modules/.bin/tsc --noEmit`: 成功。
- `git diff --check`: 問題なし。

残リスク:

- `AdminMenu.tsx` はまだ約881行あり、modal状態、Google Calendar状態、MFA状態、スタッフ削除状態が同居している。
- `StaffManagementTab.tsx` は約310行で、表示コンポーネントとしてはやや大きい。MFAヘルプ、bulk操作、一覧table、行操作が同居している。
- `GoogleIntegrationTab.tsx` は約277行で許容範囲だが、接続ステータス表示、upload form、削除confirmをさらに分ける余地はある。
- `OfficeEditModal.tsx` は表示分離済みだが、`useOfficeEditForm` 未実装のため、差分生成と保存処理はまだ親に残っている。

今後の推奨順:

1. `useOfficeEditForm` 抽出
   - 入力stateと差分生成だけをhookへ移す。
   - 保存API呼び出しとreload挙動は最初は親に残してもよい。
2. `useOfficeCalendarSettings` 抽出
   - 既存設定取得、upload、delete、status label/colorをまとめる。
   - 先に成功/404/失敗時の表示状態をチェックリスト化する。
3. `useOfficeStaffMfaManagement` 抽出
   - MFA個別操作、一括操作、スタッフ再取得、モーダル表示データが絡むため最後に回す。

変更しない方がよい範囲:

- Google Calendar upload/deleteのAPI呼び出し順序。
- MFA有効化後のQR表示とスタッフ再取得。
- 事業所編集保存後の `window.location.reload()`。
- スタッフ削除後の成功メッセージ自動clear。

## 横断レビュー

良い点:

- P5/P6ともに、既存のcontainerを残しつつ内部を分離しているため、呼び出し元への影響が小さい。
- UI文言やAPI契約を同時に変えていない。
- テスト可能な純粋ロジックから切り出す方針が守られている。
- リスクの高い副作用hook化を急がず、安全範囲に留めている。

注意点:

- 新規ファイルが増えたため、今後は「どこに何を書くか」のルールを守らないと逆に追跡しづらくなる。
- 表示componentにAPI呼び出しを戻さない。
- `index.ts` による過剰な再exportは避け、依存方向が読めるimportを維持する。
- P5のフォームsectionは今後もprops肥大化に注意する。

## 推奨アクション

短期:

- P4は次に `useDashboardData` ではなく、課金制限表示判定の純粋関数化を先に検討する。
- P5は一旦完了扱いにし、追加変更は仕様変更時に限定する。
- P6は `useOfficeEditForm` のうち、入力stateと差分生成だけを抽出するか検討する。

中期:

- Dashboardのデータ取得を `useDashboardData` に分ける。
- P6のGoogle Calendar/MFA hook化は、現行挙動チェックリストを作ってから行う。
- admin/recipient/dashboardの主要画面について、最低限の表示回帰確認手順をmd化する。

## 判定

- P4: 一部完了。検索・filter・sort抽出は完了、data取得/課金制限/一覧描画は未完了。
- P5: 完了扱いでよい。追加リファクタは低優先。
- P6: 安全範囲は完了。副作用を含むhook化は保留が妥当。
