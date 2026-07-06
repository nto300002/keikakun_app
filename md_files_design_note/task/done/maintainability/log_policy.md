# ログ出力方針

作成日: 2026-07-02

## 目的

本番コードに残すログの基準を明確にし、個人情報、認証情報、業務データ、内部IDが不要に出力されることを防ぐ。

## 原則

- 本番ログは障害調査、監査、運用判断に必要な最小情報に絞る。
- 利用者本人、スタッフ、事業所、支援計画、PDF、Google Calendar連携を特定できる情報は原則出さない。
- エラー詳細は利用者向け表示、監査ログ、開発ログを分けて扱う。
- `print()` は本番コードでは使わない。backendは `logger`、frontendはユーザー向けstate/toastまたは開発時限定の出力へ寄せる。

## 出力してよい情報

- 処理名、処理フェーズ、成功/失敗の種別。
- 件数、booleanの状態、enumの状態。
- HTTP status、例外クラス名、外部APIの失敗種別。
- 個人やデータを特定できない集計値。

例:

```text
billing transition skipped: status=active
calendar sync failed: reason=authentication_error
notices cleanup completed: deleted_count=12
```

## 出力しない情報

- token、refresh token、MFA secret、recovery code、password reset token。
- メールアドレス、氏名、電話番号、住所。
- `staff_id`、`recipient_id`、`office_id`、`google_event_id` などの内部ID。
- PDF名、ファイル名、S3 key、ファイル内容。
- 支援計画本文、アセスメント本文、問い合わせ本文、メッセージ本文。
- DB URL、secret、credential、環境変数の値。

## backend

- endpoint内の一時調査ログは残さない。
- 失敗ログは `logger.warning()` または `logger.error()` を使い、本文やIDではなく失敗種別を出す。
- `logger.debug()` は開発・調査向けに限定し、本番で有効化されても機微情報が出ない内容にする。
- 例外をログに出す場合も、利用者データやsecretを含む `str(e)` を無条件に出さない。

## frontend

- production対象コードに無条件の `console.log()` は置かない。
- `console.error()` / `console.warn()` は、業務データを含まない開発時限定の用途に限定する。
- 利用者に必要な失敗通知は、toast、画面上のerror state、フォームエラーで扱う。
- APIレスポンス全体、フォーム全体、PDF情報、利用者一覧をconsoleへ出さない。

## 判断基準

残す:

- 利用者データを含まない外部API失敗種別。
- 件数だけの運用ログ。
- セキュリティイベントの種別。

削除または置換:

- 調査時だけ使った `print()`。
- APIレスポンスやフォーム値を丸ごと出す `console.*`。
- token断片、メールアドレス、内部IDを含むログ。

別途監査ログへ移す:

- 権限変更、削除、課金状態変更など、後から追跡すべき業務イベント。

---

  残るセキュリティリスク

  - HTTPException(detail=f"...{str(e)}") 系がまだ残っています。ログではなくレス
    ポンス本文への内部情報露出リスクです。
      - 例: admin_inquiries.py, inquiries.py, offices.py,
        google_calendar_client.py 由来の例外文言など。

  - /verify-reset-token?token=... のように reset token を query string で受ける
    設計は、アクセスログ・ブラウザ履歴・プロキシログに token が残るリスクがあり
    ます。

  - MFA 初回設定レスポンスで secret_key / qr_code_uri を返す設計は仕様上必要です
    が、TLS、キャッシュ禁止、フロントログ禁止が前提です。

  - webhook_event.payload に Stripe の raw payload / customer id / subscription
    id を保存しています。ログではありませんが、DB閲覧権限や管理画面表示経由の漏
    洩リスクがあります。

  - 監査ログに email 変更の old/new email を保存しています。監査用途として妥当で
    すが、閲覧権限制御とマスキング方針が必要です。

  - 一部 scripts はまだ実行時に PII や外部IDを出す可能性があります。
      - fix_double_encoded_mfa_secrets.py: staff email、復号エラー詳細
      - verify_stripe_subscription.py: Stripe オブジェクト値
      - Stripe test/manual 系 scripts: customer/subscription id

  - Google Calendar / 支援計画 / deadline 通知系は、ログはかなり抑えましたが、イ
    ベントタイトルやメール本文には利用者名が入る設計です。外部連携先への送信デー
    タとしてのリスク評価は別途必要です。

  - logger は抑えましたが、ASGI/access log 側で URL query や status detail が出
    る設定だと、アプリログ以外から漏れる可能性があります。