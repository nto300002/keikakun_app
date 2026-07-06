# アプリ側パフォーマンス修正リスト

作成日: 2026-06-30

## 目的

ログイン、MFA認証、ログイン直後のダッシュボード表示で体感待ち時間が長くなる問題に対し、アプリ側でできる低リスクな改善を先行する。

## 優先度高

- [x] ログイン、MFA認証、サインアップの送信ボタン内に処理中表示を出す。
- [x] 認証処理が5秒以上続く場合、通信状況確認と更新を促す文言を出す。
- [x] 保護レイアウトの通知設定取得、期限通知、Push購読を初期描画後に遅延する。
- [x] 保護レイアウトの未読件数取得を初期描画後に遅延し、初期表示APIとの競合を減らす。
- [ ] ログイン/MFA成功後の `getCurrentUser()` 追加取得を削減する。

## 優先度中

- [ ] Dashboard初期表示で `authApi.getCurrentUser()` / `dashboardApi.getDashboardData()` / `billingApi.getBillingStatus()` の重複認証依存を減らす。
- [ ] Dashboardの `filtered_count` が初期表示に必須か見直す。
- [ ] ログイン後の通知トーストとヘッダーバッジ更新の取得タイミングをユーザー操作後に寄せるか検討する。

## 優先度低

- [ ] 本番相当環境でMFA成功後からDashboard表示までのNetwork waterfallを保存する。
- [ ] 5秒超ローディング文言の表示箇所を、他の長時間画面にも広げる。

## 今回の実装範囲

- `k_front/hooks/useSlowLoadingMessage.ts`
- `k_front/components/auth/LoginForm.tsx`
- `k_front/app/auth/mfa-verify/page.tsx`
- `k_front/components/auth/SignupForm.tsx`
- `k_front/components/auth/admin/SignupForm.tsx`
- `k_front/components/protected/LayoutClient.tsx`

## 受け入れ要件

- [x] 送信中ボタンはスピナーと文言を表示し、二重送信を防ぐ。
- [x] 5秒以上処理中の場合に、利用者向けの更新案内を表示する。
- [x] ログイン直後の非必須通知処理は初期描画後に遅延する。
- [ ] 実環境でログイン/MFA後の体感時間が改善したか確認する。
