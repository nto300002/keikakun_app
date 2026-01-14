# 残り期限通知のWeb Push実装 - 要件定義書（PWA対応含む）

**作成日**: 2026-01-14
**ステータス**: 要件確定（PWA対応追加済み）
**Phase**: Phase 3（期限アラートのWeb Push化 + PWA化）
**対応プラットフォーム**: Webブラウザ（デスクトップ・モバイル）、PWA（iOS Safari対応）
**関連ドキュメント**:
- [deadline_alerts_web_push_analysis.md](./deadline_alerts_web_push_analysis.md) - メリット・デメリット分析
- [implementation_plan.md](./implementation_plan.md) - 全体設計
- [TODO.md](../TODO.md) - タスクリスト

---

## 目次

1. [要件概要](#1-要件概要)
2. [現状システムの分析](#2-現状システムの分析)
3. [機能要件](#3-機能要件)
4. [技術要件](#4-技術要件)
5. [実装範囲](#5-実装範囲)
6. [影響を受けるファイル](#6-影響を受けるファイル)
7. [データモデル](#7-データモデル)
8. [API設計](#8-api設計)
9. [フロントエンド設計](#9-フロントエンド設計)
10. [工数見積](#10-工数見積)
11. [実装ステップ](#11-実装ステップ)
12. [テスト計画](#12-テスト計画)

---

## 1. 要件概要

### 1.1 背景

現在の期限アラートシステムは以下の3つの通知チャネルで構成されています：

| チャネル | トリガー | 対象 | 問題点 |
|---------|---------|------|-------|
| **アプリ内トースト** | ログイン時 | 全アラート | ログインしないと気づかない |
| **アプリ内ポップオーバー** | ベルアイコンホバー | 全アラート | 能動的アクション必要 |
| **バッチメール** | 毎日9:00 JST（平日のみ） | 全アラート | 1日1回のみ、メールに埋もれる |

これらに加えて、**システム通知（Web Push）** を実装し、ブラウザ閉じている状態でもリアルタイムに期限アラートを受け取れるようにします。

### 1.2 目的

1. **見逃し防止**: ログインしていなくてもOS通知で期限を知らせる
2. **緊急度の明確化**: 残り日数が少ないアラートのみをプッシュ通知
3. **ユーザーコントロール**: 通知種別ごとにON/OFF設定可能
4. **既存実装との共存**: アプリ内通知・メール通知と併用し、相互補完

---

## 2. 現状システムの分析

### 2.1 期限アラートの種類

| アラートタイプ | 判定条件 | 表示内容 | 優先度 |
|--------------|---------|---------|-------|
| **renewal_deadline** | 更新期限が30日以内 | 「{利用者名}の更新期限が{X}日後に迫っています」 | 残り日数の昇順 |
| **assessment_incomplete** | 期限到達済み & アセスメントPDF未作成 | 「{利用者名}のアセスメントが未完了です」 | - |

### 2.2 現在のデータフロー

```
┌─────────────────────────────────────────────────────────────┐
│ 1. バッチ処理（毎日9:00 JST、平日のみ）                      │
│    deadline_notification.py: send_deadline_alert_emails()    │
│    ├─ 全事業所をループ                                       │
│    ├─ 各事業所で期限アラート取得                             │
│    │   ├─ renewal_deadline: 30日以内の利用者                │
│    │   └─ assessment_incomplete: PDF未作成の利用者           │
│    ├─ 事業所内の全スタッフにメール送信                       │
│    └─ 送信ログ出力                                           │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. フロントエンド（ログイン時）                              │
│    LayoutClient.tsx: useEffect(() => {                       │
│    ├─ GET /api/v1/welfare-recipients/deadline-alerts         │
│    ├─ アラート取得成功                                       │
│    │   ├─ トースト表示（5秒、全アラート）                    │
│    │   └─ ポップオーバーに格納                               │
│    └─ 30秒ポーリングで未読カウント更新                       │
└─────────────────────────────────────────────────────────────┘
```

### 2.3 実装ファイル

**Backend**:
- `app/tasks/deadline_notification.py` - バッチ処理（メール送信）
- `app/services/welfare_recipient_service.py` - `get_deadline_alerts()` メソッド
- `app/api/v1/endpoints/welfare_recipients.py` - `GET /deadline-alerts` エンドポイント

**Frontend**:
- `components/protected/LayoutClient.tsx` - トースト表示、ポーリング
- `lib/assessment.ts` - アラート判定ロジック（フロント側）

---

## 3. 機能要件

### 3.1 Web Push通知の対象範囲

**メール通知は既存実装を維持**し、Web Pushは**緊急度の高いアラートのみ**を配信します。

| アラートタイプ | メール通知範囲<br>（既存実装維持） | Web Push通知範囲<br>（新規実装） | 理由 |
|--------------|---------------------------|--------------------------|------|
| **renewal_deadline** | **残り30日以内全て** | **残り10日以内のみ** | メール: 早期警告、Web Push: 真に緊急のみ |
| **assessment_incomplete** | **期限到達済み全て** | **残り5日以内のみ** | メール: 全件通知、Web Push: 期限超過直前の強調 |

**重要**:
- メール通知は既存のユーザー体験を維持するため、**閾値変更なし（30日以内全て）**
- Web Pushは新機能のため、通知疲労を防ぐために**緊急度の高いもののみ（10日/5日以内）**に限定

### 3.2 通知タイミング

| 項目 | 仕様 |
|-----|------|
| **頻度** | 毎日1回 |
| **時刻** | 9:00 JST（既存のバッチメールと同じ） |
| **曜日** | 平日のみ（休日・祝日を除く） |
| **送信タイミング** | アラートが通知範囲（renewal_deadline: 10日以内、assessment_incomplete: 5日以内）に入っている場合、毎日送信 |

**例**:
```
利用者Aさんの更新期限が12日後の場合:
  → Web Pushなし（10日以内に入っていない）
  → バッチメールは送信される（30日以内）

利用者Aさんの更新期限が9日後の場合:
  → Web Push送信（10日以内）
  → バッチメールも送信される（30日以内）

利用者Bさんのアセスメント期限が7日後の場合:
  → Web Pushなし（5日以内に入っていない）
  → バッチメールは送信される

利用者Bさんのアセスメント期限が3日後の場合:
  → Web Push送信（5日以内）
  → バッチメールも送信される
```

### 3.3 通知内容

#### 通知フォーマット

```javascript
{
  "title": "🚨 緊急：期限アラート（{事業所名}）",
  "body": "更新期限: {count}件、アセスメント未完了: {count}件",
  "icon": "/logo.png",
  "badge": "/badge.png",
  "data": {
    "type": "deadline_alert",
    "office_id": "{UUID}",
    "renewal_count": 2,
    "assessment_count": 1,
    "alerts": [
      {
        "type": "renewal_deadline",
        "welfare_recipient_id": "{UUID}",
        "name": "山田太郎",
        "days_remaining": 5,
        "message": "山田太郎の更新期限が5日後に迫っています"
      },
      {
        "type": "assessment_incomplete",
        "welfare_recipient_id": "{UUID}",
        "name": "佐藤花子",
        "days_remaining": 2,
        "message": "佐藤花子のアセスメントが未完了です（残り2日）"
      }
    ]
  },
  "requireInteraction": true,
  "actions": [
    {
      "action": "view",
      "title": "詳細を見る"
    },
    {
      "action": "close",
      "title": "閉じる"
    }
  ]
}
```

#### 通知クリック時の動作

| アクション | 遷移先 |
|----------|--------|
| **「詳細を見る」クリック** | `/recipients?filter=deadline` （期限絞り込み一覧） |
| **通知本体クリック** | `/dashboard` （ダッシュボード） |
| **「閉じる」クリック** | 通知を閉じるのみ |

### 3.4 通知設定機能

ユーザーはプロフィール画面で**3種類の通知チャネル**をそれぞれON/OFF設定できます。

| 設定項目 | デフォルト | 説明 | 制御対象 |
|---------|----------|------|---------|
| **アプリ内通知** | ON | ログイン時のトースト + ベルアイコンポップオーバー | フロントエンドのトースト表示 |
| **メール通知** | ON | 毎日9:00の期限アラートメール | バッチ処理のメール送信 |
| **システム通知** | OFF | Web Push通知（OS通知） | バッチ処理のプッシュ送信 |

#### 設定画面UI（プロフィールページ）

```tsx
<section className="space-y-4">
  <h2 className="text-xl font-semibold">通知設定</h2>
  <p className="text-sm text-gray-600">
    期限アラートやアクション承認の受信方法を設定できます
  </p>

  {/* アプリ内通知 */}
  <div className="flex items-center justify-between">
    <div>
      <Label>アプリ内通知</Label>
      <Description>ログイン時のトースト通知とベルアイコンのポップオーバー</Description>
    </div>
    <Switch checked={inAppNotification} onChange={toggleInAppNotification} />
  </div>

  {/* メール通知 */}
  <div className="flex items-center justify-between">
    <div>
      <Label>メール通知</Label>
      <Description>毎朝9時の期限アラートメール（平日のみ）</Description>
    </div>
    <Switch checked={emailNotification} onChange={toggleEmailNotification} />
  </div>

  {/* システム通知（Web Push） */}
  <div className="flex items-center justify-between">
    <div>
      <Label>システム通知</Label>
      <Description>
        ブラウザ閉じていても受信できるプッシュ通知
        {!isSupported && <span className="text-red-500 ml-2">（非対応ブラウザ）</span>}
      </Description>
    </div>
    <Switch
      checked={systemNotification}
      onChange={toggleSystemNotification}
      disabled={!isSupported}
    />
  </div>
</section>
```

---

## 4. 技術要件

### 4.1 対応ブラウザ

| ブラウザ | バージョン | 対応状況 | 備考 |
|---------|----------|---------|------|
| Chrome/Edge | 最新版 | ✅ 完全対応 | デスクトップ・Android両対応 |
| Firefox | 最新版 | ✅ 完全対応 | デスクトップ・Android両対応 |
| Safari (macOS) | 16.4+ | ✅ 対応 | 通常のWebページから利用可能 |
| Safari (iOS) | 16.4+ | ✅ 対応（PWA化必須） | **ホーム画面追加後のみ利用可能** |

#### iOS Safari固有の制約事項

iOS SafariでWeb Push通知を利用するには、**PWA（Progressive Web App）化が必須**です：

```
【iOS Safari（16.4+）の要件】

1. ホーム画面に追加（PWA化）が必須
   ✗ 通常のブラウザタブでは Web Push 使用不可
   ✅ ホーム画面追加後のみ使用可能

2. manifest.jsonが必要
   ✅ アプリ名、アイコン、start_urlの定義必須

3. Service Workerのスコープ
   ✅ PWAとして起動したときのみ有効

4. ユーザー操作が必要
   ✅ 自動的な通知許可リクエストは不可
   ✅ ボタンクリック等のユーザーアクション必須
```

**対応方針**: manifest.json作成、PWAメタタグ追加、iOSユーザー向けガイダンス表示

### 4.2 必要なライブラリ

**Backend**:
- `pywebpush>=1.14.0` - Web Push送信ライブラリ
- `py-vapid>=1.9.0` - VAPID鍵生成・管理
- `jpholiday>=0.1.8` - 祝日判定（既存）

**Frontend**:
- Web Push API（標準API、追加ライブラリ不要）
- Service Worker（PWA標準機能）

### 4.3 環境変数

**k_back/.env**:
```bash
# Web Push通知設定（VAPID）
VAPID_PRIVATE_KEY=<秘密鍵（PEM形式）>
VAPID_PUBLIC_KEY=<公開鍵（Base64 URL-safe）>
VAPID_SUBJECT=mailto:support@keikakun.com
```

**k_front/.env.local**:
```bash
# VAPID公開鍵（フロントエンドで使用）
NEXT_PUBLIC_VAPID_PUBLIC_KEY=<公開鍵（Base64 URL-safe）>
```

### 4.4 セキュリティ要件

1. **HTTPS必須**: Cloud Runで既に対応済み ✅
2. **VAPID認証**: RFC 8292準拠のVAPID鍵ペアを使用
3. **購読情報の保護**: p256dh_key/auth_keyはDBに暗号化せずに保存（ブラウザ生成の公開鍵のため問題なし）
4. **認証**: Push購読登録/解除はJWT認証必須
5. **権限チェック**: 自分の購読情報のみアクセス可能

---

## 5. 実装範囲

### 5.1 Phase 1（基盤構築）- 既に完了 ✅

以下の実装は既に完了しています（前回の実装で完了）：

- [x] push_subscriptionsテーブル作成
- [x] PushSubscriptionモデル・スキーマ定義
- [x] CRUD操作実装
- [x] Push通知サービス実装（`app/core/push.py`）
- [x] Push購読API実装（subscribe/unsubscribe/my-subscriptions）
- [x] テストコード作成（22テスト全てパス）

### 5.2 Phase 3（期限アラートのWeb Push化）- 今回の実装範囲

#### 5.2.1 Backend実装

| タスク | ファイル | 内容 |
|-------|---------|------|
| **1. 通知設定モデル追加** | `app/models/staff.py` | `notification_preferences`カラム追加（JSONB型） |
| **2. DBマイグレーション** | `migrations/versions/xxx_add_notification_preferences.py` | staffsテーブルにnotification_preferencesカラム追加 |
| **3. バッチ処理修正** | `app/tasks/deadline_notification.py` | Web Push送信ロジック追加 |
| **4. 通知設定API実装** | `app/api/v1/endpoints/staffs.py` | 通知設定取得/更新エンドポイント追加 |
| **5. スキーマ定義** | `app/schemas/staff.py` | NotificationPreferences スキーマ追加 |

#### 5.2.2 Frontend実装

| タスク | ファイル | 内容 |
|-------|---------|------|
| **0. PWA化対応（iOS対応）** | `public/manifest.json`、`app/layout.tsx` | PWA manifest、メタタグ、アイコン準備 |
| **1. Service Worker作成** | `public/sw.js` | Push通知受信・表示ハンドラー |
| **2. Push購読Hook** | `hooks/usePushNotification.ts` | 購読/購読解除ロジック、iOS判定 |
| **3. 通知設定UI** | `components/protected/profile/NotificationSettings.tsx` | 3種類の通知ON/OFF設定画面、iOSガイダンス |
| **4. プロフィール画面統合** | `app/(protected)/profile/page.tsx` | NotificationSettingsコンポーネント組み込み |
| **5. 通知ハンドラー** | `public/sw.js` | 通知クリック時の遷移処理 |

---

## 6. 影響を受けるファイル

### 6.1 Backend（k_back）

#### 新規作成ファイル

```
app/
├── migrations/
│   └── versions/
│       └── xxx_add_notification_preferences.py  # 新規マイグレーション
```

#### 修正ファイル

```
app/
├── models/
│   └── staff.py                                 # notification_preferencesカラム追加
├── schemas/
│   └── staff.py                                 # NotificationPreferencesスキーマ追加
├── api/v1/endpoints/
│   └── staffs.py                                # 通知設定API追加
└── tasks/
    └── deadline_notification.py                 # Web Push送信ロジック追加
```

### 6.2 Frontend（k_front）

#### 新規作成ファイル

```
k_front/
├── public/
│   ├── manifest.json                            # PWA manifest（iOS対応）
│   ├── sw.js                                    # Service Worker
│   ├── icon-192.png                             # PWAアイコン（192x192）
│   └── icon-512.png                             # PWAアイコン（512x512）
├── hooks/
│   └── usePushNotification.ts                   # Push購読Hook
└── components/protected/profile/
    └── NotificationSettings.tsx                 # 通知設定UI
```

#### 修正ファイル

```
k_front/
├── app/
│   └── layout.tsx                               # PWAメタタグ追加
└── app/(protected)/profile/
    └── page.tsx                                 # NotificationSettings組み込み
```

---

## 7. データモデル

### 7.1 staffsテーブル修正

#### 追加カラム

```sql
ALTER TABLE staffs ADD COLUMN notification_preferences JSONB DEFAULT '{
  "in_app_notification": true,
  "email_notification": true,
  "system_notification": false,
  "email_threshold_days": 30,
  "push_threshold_days": 10
}'::jsonb;
```

#### notification_preferences構造（Phase 3 + 閾値カスタマイズ対応）

```json
{
  "in_app_notification": true,       // アプリ内通知（トースト・ポップオーバー）
  "email_notification": true,         // メール通知（バッチメール）
  "system_notification": false,       // システム通知（Web Push）
  "email_threshold_days": 30,         // メール通知開始日数（5, 10, 20, 30から選択可能）
  "push_threshold_days": 10           // Web Push通知開始日数（5, 10, 20, 30から選択可能）
}
```

#### デフォルト値の理由

- **in_app_notification**: `true` - 既存動作を維持
- **email_notification**: `true` - 既存動作を維持
- **system_notification**: `false` - 新機能のため明示的な許可が必要
- **email_threshold_days**: `30` - 既存実装を維持（30日以内全て）
- **push_threshold_days**: `10` - 緊急度の高いアラートのみ、通知疲労防止

#### 閾値の選択肢

| 閾値 | 用途 | 推奨ユーザー |
|-----|------|----------|
| **5日前** | 直前の緊急アラートのみ | 通知疲労が気になる人 |
| **10日前** | 緊急度の高いアラート | バランス重視（Web Pushデフォルト） |
| **20日前** | 中期的な警告 | 余裕を持って対応したい人 |
| **30日前** | 早期警告（全アラート） | 見逃したくない人（メールデフォルト） |

### 7.2 push_subscriptionsテーブル（既存）

既にPhase 1で作成済み。変更なし。

```sql
CREATE TABLE push_subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id UUID NOT NULL REFERENCES staffs(id) ON DELETE CASCADE,
    endpoint TEXT NOT NULL UNIQUE,
    p256dh_key TEXT NOT NULL,
    auth_key TEXT NOT NULL,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

---

## 8. API設計

### 8.1 通知設定API（新規）

#### GET /api/v1/staffs/me/notification-preferences

現在ログイン中のスタッフの通知設定を取得します。

**認証**: JWT必須

**リクエスト**:
```http
GET /api/v1/staffs/me/notification-preferences
Authorization: Bearer <JWT_TOKEN>
```

**レスポンス**:
```json
{
  "in_app_notification": true,
  "email_notification": true,
  "system_notification": false,
  "email_threshold_days": 30,
  "push_threshold_days": 10
}
```

**ステータスコード**:
- `200 OK`: 取得成功
- `401 Unauthorized`: 認証エラー

---

#### PUT /api/v1/staffs/me/notification-preferences

通知設定を更新します（閾値カスタマイズ対応）。

**認証**: JWT必須

**リクエスト**:
```http
PUT /api/v1/staffs/me/notification-preferences
Authorization: Bearer <JWT_TOKEN>
Content-Type: application/json

{
  "in_app_notification": true,
  "email_notification": false,
  "system_notification": true,
  "email_threshold_days": 20,
  "push_threshold_days": 30
}
```

**レスポンス**:
```json
{
  "in_app_notification": true,
  "email_notification": false,
  "system_notification": true,
  "email_threshold_days": 20,
  "push_threshold_days": 30
}
```

**ステータスコード**:
- `200 OK`: 更新成功
- `400 Bad Request`: バリデーションエラー
- `401 Unauthorized`: 認証エラー
- `422 Unprocessable Entity`: 不正なJSON形式

**バリデーション**:
- **boolean型フィールド**: `in_app_notification`, `email_notification`, `system_notification`
- **整数型フィールド**: `email_threshold_days`, `push_threshold_days`
- 少なくとも1つの通知チャネルはONである必要がある（全てfalseは不可）
- **閾値の有効値**: `5`, `10`, `20`, `30`のいずれか（それ以外はエラー）
- `email_threshold_days`は`email_notification=true`の場合のみ有効
- `push_threshold_days`は`system_notification=true`の場合のみ有効

---

### 8.2 既存API修正

#### GET /api/v1/push-subscriptions/my-subscriptions

変更なし。既にPhase 1で実装済み。

#### POST /api/v1/push-subscriptions/subscribe

変更なし。既にPhase 1で実装済み。

#### DELETE /api/v1/push-subscriptions/unsubscribe

変更なし。既にPhase 1で実装済み。

---

## 9. フロントエンド設計

### 9.0 PWA化対応（iOS Safari対応）

#### 9.0.1 manifest.json作成

**public/manifest.json**:
```json
{
  "name": "個別支援計画くん",
  "short_name": "計画くん",
  "description": "個別支援計画管理システム",
  "start_url": "/dashboard",
  "display": "standalone",
  "background_color": "#ffffff",
  "theme_color": "#3b82f6",
  "orientation": "portrait-primary",
  "icons": [
    {
      "src": "/icon-192.png",
      "sizes": "192x192",
      "type": "image/png",
      "purpose": "any maskable"
    },
    {
      "src": "/icon-512.png",
      "sizes": "512x512",
      "type": "image/png",
      "purpose": "any maskable"
    }
  ]
}
```

#### 9.0.2 HTMLヘッダー修正

**app/layout.tsx**:
```tsx
import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: '個別支援計画くん',
  description: '個別支援計画管理システム',
  manifest: '/manifest.json',
  appleWebApp: {
    capable: true,
    statusBarStyle: 'default',
    title: '計画くん',
  },
  themeColor: '#3b82f6',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="ja">
      <head>
        {/* PWA manifest */}
        <link rel="manifest" href="/manifest.json" />

        {/* iOS用アイコン */}
        <link rel="apple-touch-icon" href="/icon-192.png" />

        {/* Android/Chrome用 */}
        <meta name="mobile-web-app-capable" content="yes" />
        <meta name="theme-color" content="#3b82f6" />
      </head>
      <body>{children}</body>
    </html>
  );
}
```

#### 9.0.3 アイコン準備

以下のPNGアイコンを準備します：

- **icon-192.png**: 192x192ピクセル（Android/iOS用）
- **icon-512.png**: 512x512ピクセル（高解像度デバイス用）

**デザイン要件**:
- 背景色: 白（#ffffff）
- ロゴ: 中央配置、余白20%
- フォーマット: PNG（透過なし）
- 角丸: なし（OSが自動で適用）

### 9.1 Service Worker実装

#### public/sw.js

```javascript
/**
 * Service Worker - Web Push通知ハンドラー
 */

// Push通知受信時
self.addEventListener('push', (event) => {
  if (!event.data) {
    console.log('[SW] Push event but no data');
    return;
  }

  const data = event.data.json();
  console.log('[SW] Push received:', data);

  const options = {
    body: data.body,
    icon: data.icon || '/logo.png',
    badge: data.badge || '/badge.png',
    data: data.data || {},
    requireInteraction: data.requireInteraction || true,
    tag: 'keikakun-deadline-alert',
    actions: data.actions || [
      { action: 'view', title: '詳細を見る' },
      { action: 'close', title: '閉じる' }
    ]
  };

  event.waitUntil(
    self.registration.showNotification(data.title, options)
  );
});

// 通知クリック時
self.addEventListener('notificationclick', (event) => {
  console.log('[SW] Notification click:', event.action);
  event.notification.close();

  if (event.action === 'view') {
    // 「詳細を見る」クリック時
    const alertData = event.notification.data;
    const url = alertData.type === 'deadline_alert'
      ? '/recipients?filter=deadline'
      : '/dashboard';

    event.waitUntil(
      clients.openWindow(url)
    );
  } else if (event.action === 'close') {
    // 「閉じる」クリック時（何もしない）
    return;
  } else {
    // 通知本体クリック時
    event.waitUntil(
      clients.openWindow('/dashboard')
    );
  }
});
```

### 9.2 Push購読Hook

#### hooks/usePushNotification.ts

```typescript
import { useState, useEffect } from 'react';
import { useSession } from 'next-auth/react';

interface UsePushNotificationReturn {
  isSupported: boolean;
  isSubscribed: boolean;
  isPWA: boolean;              // PWAとして起動しているか（iOS判定用）
  isIOS: boolean;              // iOSデバイスか
  subscribe: () => Promise<void>;
  unsubscribe: () => Promise<void>;
  loading: boolean;
  error: string | null;
}

export const usePushNotification = (): UsePushNotificationReturn => {
  const { data: session } = useSession();
  const [isSupported, setIsSupported] = useState(false);
  const [isSubscribed, setIsSubscribed] = useState(false);
  const [isPWA, setIsPWA] = useState(false);
  const [isIOS, setIsIOS] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // デバイス・ブラウザ判定
  useEffect(() => {
    // iOS判定
    const isIOSDevice = /iPhone|iPad|iPod/.test(navigator.userAgent);
    setIsIOS(isIOSDevice);

    // PWA判定（standalone mode）
    const isPWAMode = window.matchMedia('(display-mode: standalone)').matches ||
                      (window.navigator as any).standalone === true;
    setIsPWA(isPWAMode);

    // ブラウザサポート判定
    const hasAPISupport =
      'serviceWorker' in navigator &&
      'PushManager' in window &&
      'Notification' in window;

    // iOSの場合はPWAモードでのみサポート
    const supported = isIOSDevice ? (hasAPISupport && isPWAMode) : hasAPISupport;
    setIsSupported(supported);
  }, []);

  // 購読状態確認
  useEffect(() => {
    if (!isSupported || !session) return;

    const checkSubscription = async () => {
      try {
        const registration = await navigator.serviceWorker.getRegistration();
        const subscription = await registration?.pushManager.getSubscription();
        setIsSubscribed(!!subscription);
      } catch (err) {
        console.error('[Push] Failed to check subscription:', err);
      }
    };

    checkSubscription();
  }, [isSupported, session]);

  // 購読登録
  const subscribe = async () => {
    if (!isSupported) {
      setError('お使いのブラウザはプッシュ通知をサポートしていません');
      return;
    }

    if (!session?.accessToken) {
      setError('ログインが必要です');
      return;
    }

    setLoading(true);
    setError(null);

    try {
      // 通知許可リクエスト
      const permission = await Notification.requestPermission();
      if (permission !== 'granted') {
        throw new Error('通知が拒否されました');
      }

      // Service Worker登録
      const registration = await navigator.serviceWorker.register('/sw.js');
      await navigator.serviceWorker.ready;

      // Push購読
      const subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(
          process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY!
        )
      });

      // Backend登録
      const response = await fetch('/api/v1/push-subscriptions/subscribe', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${session.accessToken}`
        },
        body: JSON.stringify(subscription.toJSON())
      });

      if (!response.ok) {
        throw new Error('購読登録に失敗しました');
      }

      setIsSubscribed(true);
    } catch (err: any) {
      console.error('[Push] Subscribe error:', err);
      setError(err.message || '購読登録に失敗しました');
    } finally {
      setLoading(false);
    }
  };

  // 購読解除
  const unsubscribe = async () => {
    if (!session?.accessToken) {
      setError('ログインが必要です');
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const registration = await navigator.serviceWorker.getRegistration();
      const subscription = await registration?.pushManager.getSubscription();

      if (!subscription) {
        setIsSubscribed(false);
        return;
      }

      // Backend削除
      const response = await fetch(
        `/api/v1/push-subscriptions/unsubscribe?endpoint=${encodeURIComponent(subscription.endpoint)}`,
        {
          method: 'DELETE',
          headers: {
            'Authorization': `Bearer ${session.accessToken}`
          }
        }
      );

      if (!response.ok) {
        throw new Error('購読解除に失敗しました');
      }

      // ブラウザ側購読解除
      await subscription.unsubscribe();
      setIsSubscribed(false);
    } catch (err: any) {
      console.error('[Push] Unsubscribe error:', err);
      setError(err.message || '購読解除に失敗しました');
    } finally {
      setLoading(false);
    }
  };

  return {
    isSupported,
    isSubscribed,
    isPWA,
    isIOS,
    subscribe,
    unsubscribe,
    loading,
    error
  };
};

/**
 * Base64 URL-safe文字列をUint8Arrayに変換
 */
function urlBase64ToUint8Array(base64String: string): Uint8Array {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding)
    .replace(/\-/g, '+')
    .replace(/_/g, '/');

  const rawData = window.atob(base64);
  const outputArray = new Uint8Array(rawData.length);

  for (let i = 0; i < rawData.length; ++i) {
    outputArray[i] = rawData.charCodeAt(i);
  }
  return outputArray;
}
```

### 9.3 通知設定UI

#### components/protected/profile/NotificationSettings.tsx

```tsx
'use client';

import { useState, useEffect } from 'react';
import { useSession } from 'next-auth/react';
import { usePushNotification } from '@/hooks/usePushNotification';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';
import { toast } from 'sonner';

interface NotificationPreferences {
  in_app_notification: boolean;
  email_notification: boolean;
  system_notification: boolean;
}

export default function NotificationSettings() {
  const { data: session } = useSession();
  const { isSupported, isSubscribed, isPWA, isIOS, subscribe, unsubscribe } = usePushNotification();

  const [preferences, setPreferences] = useState<NotificationPreferences>({
    in_app_notification: true,
    email_notification: true,
    system_notification: false
  });
  const [loading, setLoading] = useState(false);

  // 設定読み込み
  useEffect(() => {
    if (!session?.accessToken) return;

    const fetchPreferences = async () => {
      try {
        const response = await fetch('/api/v1/staffs/me/notification-preferences', {
          headers: {
            'Authorization': `Bearer ${session.accessToken}`
          }
        });

        if (response.ok) {
          const data = await response.json();
          setPreferences(data);
        }
      } catch (error) {
        console.error('[NotificationSettings] Failed to fetch preferences:', error);
      }
    };

    fetchPreferences();
  }, [session]);

  // 設定更新
  const updatePreferences = async (newPreferences: NotificationPreferences) => {
    if (!session?.accessToken) return;

    // 全てfalseは許可しない
    if (!newPreferences.in_app_notification &&
        !newPreferences.email_notification &&
        !newPreferences.system_notification) {
      toast.error('少なくとも1つの通知チャネルをONにしてください');
      return;
    }

    setLoading(true);

    try {
      const response = await fetch('/api/v1/staffs/me/notification-preferences', {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${session.accessToken}`
        },
        body: JSON.stringify(newPreferences)
      });

      if (!response.ok) {
        throw new Error('設定の更新に失敗しました');
      }

      setPreferences(newPreferences);
      toast.success('通知設定を更新しました');
    } catch (error: any) {
      console.error('[NotificationSettings] Failed to update preferences:', error);
      toast.error(error.message || '設定の更新に失敗しました');
    } finally {
      setLoading(false);
    }
  };

  // アプリ内通知トグル
  const toggleInAppNotification = async () => {
    await updatePreferences({
      ...preferences,
      in_app_notification: !preferences.in_app_notification
    });
  };

  // メール通知トグル
  const toggleEmailNotification = async () => {
    await updatePreferences({
      ...preferences,
      email_notification: !preferences.email_notification
    });
  };

  // システム通知トグル
  const toggleSystemNotification = async () => {
    const newValue = !preferences.system_notification;

    // Push購読/購読解除
    if (newValue && !isSubscribed) {
      await subscribe();
    } else if (!newValue && isSubscribed) {
      await unsubscribe();
    }

    // 設定更新
    await updatePreferences({
      ...preferences,
      system_notification: newValue
    });
  };

  return (
    <section className="space-y-6">
      <div>
        <h2 className="text-xl font-semibold">通知設定</h2>
        <p className="text-sm text-gray-600 mt-1">
          期限アラートやアクション承認の受信方法を設定できます
        </p>
      </div>

      <div className="space-y-4">
        {/* アプリ内通知 */}
        <div className="flex items-center justify-between p-4 border rounded-lg">
          <div className="flex-1">
            <Label className="text-base font-medium">アプリ内通知</Label>
            <p className="text-sm text-gray-600 mt-1">
              ログイン時のトースト通知とベルアイコンのポップオーバー
            </p>
          </div>
          <Switch
            checked={preferences.in_app_notification}
            onCheckedChange={toggleInAppNotification}
            disabled={loading}
          />
        </div>

        {/* メール通知 */}
        <div className="flex items-center justify-between p-4 border rounded-lg">
          <div className="flex-1">
            <Label className="text-base font-medium">メール通知</Label>
            <p className="text-sm text-gray-600 mt-1">
              毎朝9時の期限アラートメール（平日のみ）
            </p>
          </div>
          <Switch
            checked={preferences.email_notification}
            onCheckedChange={toggleEmailNotification}
            disabled={loading}
          />
        </div>

        {/* システム通知 */}
        <div className="flex items-center justify-between p-4 border rounded-lg">
          <div className="flex-1">
            <Label className="text-base font-medium">システム通知</Label>
            <p className="text-sm text-gray-600 mt-1">
              ブラウザを閉じていても受信できるプッシュ通知（緊急アラートのみ）
            </p>
            {!isSupported && !isIOS && (
              <p className="text-sm text-red-500 mt-1">
                お使いのブラウザはプッシュ通知をサポートしていません
              </p>
            )}
            {isIOS && !isPWA && (
              <p className="text-sm text-amber-600 mt-1">
                ⚠️ iPhoneではホーム画面への追加が必要です（下記の手順参照）
              </p>
            )}
          </div>
          <Switch
            checked={preferences.system_notification}
            onCheckedChange={toggleSystemNotification}
            disabled={loading || !isSupported}
          />
        </div>
      </div>

      {/* iOS用ガイダンス */}
      {isIOS && !isPWA && (
        <div className="p-4 bg-blue-50 border border-blue-200 rounded-lg">
          <p className="text-sm font-medium text-blue-900 mb-2">
            📱 iPhoneでシステム通知を有効にする方法
          </p>
          <ol className="text-xs text-blue-800 space-y-1 ml-4 list-decimal">
            <li>Safariで画面下部の「共有」ボタン（□に↑マーク）をタップ</li>
            <li>「ホーム画面に追加」を選択</li>
            <li>「追加」をタップしてアイコンを作成</li>
            <li>ホーム画面の「計画くん」アイコンからアプリを開く</li>
            <li>この画面でシステム通知をONにする</li>
          </ol>
          <p className="text-xs text-blue-700 mt-2">
            ※ 通常のSafariブラウザではシステム通知は利用できません
          </p>
        </div>
      )}

      {/* PWA化成功メッセージ */}
      {isIOS && isPWA && (
        <div className="p-4 bg-green-50 border border-green-200 rounded-lg">
          <p className="text-sm font-medium text-green-900">
            ✅ PWAとして起動中 - システム通知が利用可能です
          </p>
        </div>
      )}

      <div className="text-xs text-gray-500 p-4 bg-gray-50 rounded-lg">
        <p className="font-medium mb-2">📌 システム通知について</p>
        <ul className="space-y-1 ml-4 list-disc">
          <li>更新期限が10日以内、またはアセスメント未完了が5日以内の場合に送信されます</li>
          <li>毎朝9時に送信されます（平日のみ、休日・祝日を除く）</li>
          <li>ブラウザの通知許可が必要です</li>
        </ul>
      </div>
    </section>
  );
}
```

---

## 10. 工数見積

### 10.1 Backend実装

| タスク | 内容 | 工数 |
|-------|------|------|
| **1. DBマイグレーション** | notification_preferencesカラム追加（閾値フィールド含む） | 1時間 |
| **2. モデル修正** | Staffモデルにnotification_preferences追加 | 0.5時間 |
| **3. スキーマ定義** | NotificationPreferencesスキーマ作成（閾値バリデーション含む） | 1時間 |
| **4. 通知設定API** | GET/PUT エンドポイント実装（閾値対応） | 2.5時間 |
| **5. バッチ処理修正** | deadline_notification.py修正（Web Push送信 + 閾値反映） | 5-7時間 |
| **6. テストコード** | 通知設定API、バッチ処理のテスト（閾値テスト含む） | 4-5時間 |
| **小計** | - | **14-17時間** |

### 10.2 Frontend実装

| タスク | 内容 | 工数 |
|-------|------|------|
| **0. PWA化対応** | manifest.json、アイコン準備、layout.tsx修正 | 2-3時間 |
| **1. Service Worker作成** | sw.js実装（Push受信・通知表示） | 3-4時間 |
| **2. Push購読Hook** | usePushNotification.ts実装（iOS判定含む） | 3-4時間 |
| **3. 通知設定UI** | NotificationSettings.tsx実装（閾値セレクトボックス + iOSガイダンス） | 5-6時間 |
| **4. プロフィール画面統合** | page.tsx修正、デザイン調整 | 1-2時間 |
| **5. テスト・動作確認** | ブラウザ別テスト、iOS実機テスト、閾値変更テスト | 4-5時間 |
| **小計** | - | **18-24時間** |

### 10.3 総工数（閾値カスタマイズ機能含む）

| カテゴリ | 最小 | 最大 | 平均 |
|---------|------|------|------|
| **Backend** | 14時間 | 17時間 | 15.5時間 |
| **Frontend（PWA + 閾値UI）** | 18時間 | 24時間 | 21時間 |
| **総工数** | **32時間** | **41時間** | **36.5時間** |

**実装期間**: 約4-5日（1日7-8時間作業想定）

**内訳**:
- PWA対応追加工数: +5-6時間（manifest.json、アイコン、iOS判定、ガイダンスUI、iOS実機テスト）
- **閾値カスタマイズ追加工数**: +5-6時間（DBマイグレーション、スキーマバリデーション、UI実装、テスト）

---

## 11. 実装ステップ

### Step 0: PWA化対応（2-3時間）

#### 0.1 manifest.json作成（0.5時間）

```bash
cd k_front/public
touch manifest.json
```

**public/manifest.json**:
```json
{
  "name": "個別支援計画くん",
  "short_name": "計画くん",
  "description": "個別支援計画管理システム",
  "start_url": "/dashboard",
  "display": "standalone",
  "background_color": "#ffffff",
  "theme_color": "#3b82f6",
  "orientation": "portrait-primary",
  "icons": [
    {
      "src": "/icon-192.png",
      "sizes": "192x192",
      "type": "image/png",
      "purpose": "any maskable"
    },
    {
      "src": "/icon-512.png",
      "sizes": "512x512",
      "type": "image/png",
      "purpose": "any maskable"
    }
  ]
}
```

#### 0.2 アイコン準備（1-1.5時間）

既存のロゴファイルから以下のサイズを生成：

```bash
# 既存ロゴ確認
ls k_front/public/logo.*

# ImageMagick等で192x192と512x512を生成
convert logo.png -resize 192x192 icon-192.png
convert logo.png -resize 512x512 icon-512.png
```

**デザイン要件**:
- 背景: 白（#ffffff）
- ロゴ中央配置、余白20%
- PNG形式（透過なし）

#### 0.3 layout.tsx修正（0.5時間）

```tsx
// app/layout.tsx

import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: '個別支援計画くん',
  description: '個別支援計画管理システム',
  manifest: '/manifest.json',
  appleWebApp: {
    capable: true,
    statusBarStyle: 'default',
    title: '計画くん',
  },
  themeColor: '#3b82f6',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="ja">
      <head>
        <link rel="manifest" href="/manifest.json" />
        <link rel="apple-touch-icon" href="/icon-192.png" />
        <meta name="mobile-web-app-capable" content="yes" />
        <meta name="theme-color" content="#3b82f6" />
      </head>
      <body>{children}</body>
    </html>
  );
}
```

#### 0.4 動作確認（0.5時間）

```bash
# 開発サーバー起動
npm run dev

# Chrome DevToolsで確認
# Application > Manifest > manifest.jsonが読み込まれているか確認
# Application > Service Workers > 準備完了（Step 4実装後）

# iOS Safari実機テスト（Step 4実装後）
# 共有 > ホーム画面に追加 > アイコン確認
```

---

### Step 1: DBマイグレーション（1時間）

1. マイグレーションファイル作成
   ```bash
   cd k_back
   docker exec keikakun_app-backend-1 alembic revision -m "add_notification_preferences_to_staffs"
   ```

2. マイグレーション実装
   ```python
   # migrations/versions/xxx_add_notification_preferences_to_staffs.py

   def upgrade() -> None:
       op.add_column(
           'staffs',
           sa.Column(
               'notification_preferences',
               postgresql.JSONB(),
               nullable=False,
               server_default=sa.text("'{\"in_app_notification\": true, \"email_notification\": true, \"system_notification\": false}'::jsonb")
           )
       )

   def downgrade() -> None:
       op.drop_column('staffs', 'notification_preferences')
   ```

3. マイグレーション実行
   ```bash
   docker exec keikakun_app-backend-1 alembic upgrade head
   ```

4. 確認
   ```sql
   SELECT id, email, notification_preferences FROM staffs LIMIT 5;
   ```

---

### Step 2: Backend API実装（2.5時間）

#### 2.1 モデル修正（0.5時間）

```python
# app/models/staff.py

from sqlalchemy.dialects.postgresql import JSONB

class Staff(Base):
    __tablename__ = "staffs"

    # 既存フィールド...

    # 通知設定
    notification_preferences: Mapped[dict] = mapped_column(
        JSONB,
        nullable=False,
        server_default=text("'{\"in_app_notification\": true, \"email_notification\": true, \"system_notification\": false}'::jsonb")
    )
```

#### 2.2 スキーマ定義（0.5時間）

```python
# app/schemas/staff.py

class NotificationPreferences(BaseModel):
    """通知設定"""
    in_app_notification: bool = True
    email_notification: bool = True
    system_notification: bool = False

    @validator('*')
    def at_least_one_enabled(cls, v, values):
        """少なくとも1つの通知チャネルがONである必要がある"""
        if not any([
            values.get('in_app_notification'),
            values.get('email_notification'),
            values.get('system_notification')
        ]):
            raise ValueError('少なくとも1つの通知チャネルをONにしてください')
        return v
```

#### 2.3 API実装（1.5時間）

```python
# app/api/v1/endpoints/staffs.py

@router.get("/me/notification-preferences", response_model=NotificationPreferences)
async def get_my_notification_preferences(
    current_user: Staff = Depends(deps.get_current_user)
):
    """自分の通知設定を取得"""
    return NotificationPreferences(**current_user.notification_preferences)

@router.put("/me/notification-preferences", response_model=NotificationPreferences)
async def update_my_notification_preferences(
    preferences: NotificationPreferences,
    current_user: Staff = Depends(deps.get_current_user),
    db: AsyncSession = Depends(deps.get_db)
):
    """自分の通知設定を更新"""
    current_user.notification_preferences = preferences.dict()
    db.add(current_user)
    await db.commit()
    await db.refresh(current_user)

    return NotificationPreferences(**current_user.notification_preferences)
```

---

### Step 3: バッチ処理修正（4-6時間）

#### 3.1 期限アラート判定ロジック修正

```python
# app/tasks/deadline_notification.py

import jpholiday
from datetime import datetime, timedelta, timezone
from app.core.push import send_push_notification
from app import crud

async def send_deadline_alert_emails(
    db: AsyncSession,
    dry_run: bool = False
) -> dict:
    """
    期限アラート送信（メール + Web Push）

    Returns:
        {"email_sent": int, "push_sent": int, "push_failed": int}
    """
    # 平日判定（休日・祝日を除く）
    now = datetime.now(timezone.utc)
    jst_now = now.astimezone(timezone(timedelta(hours=9)))

    if jst_now.weekday() >= 5:  # 土日
        logger.info("[DEADLINE] Skipped: Weekend")
        return {"email_sent": 0, "push_sent": 0, "push_failed": 0}

    if jpholiday.is_holiday(jst_now.date()):  # 祝日
        logger.info("[DEADLINE] Skipped: Holiday")
        return {"email_sent": 0, "push_sent": 0, "push_failed": 0}

    # 全事業所をループ
    offices = await crud.office.get_multi(db=db)

    email_count = 0
    push_sent_count = 0
    push_failed_count = 0

    for office in offices:
        # 期限アラート取得（既存実装維持: threshold_days=30で全アラート取得）
        welfare_recipient_service = WelfareRecipientService()
        alert_response = await welfare_recipient_service.get_deadline_alerts(
            db=db,
            office_id=office.id,
            threshold_days=30,  # ← 既存実装維持（メール通知用）
            limit=None,
            offset=0
        )

        if alert_response.total == 0:
            continue

        # 全アラート（30日以内）をメール送信用に保持
        all_alerts = alert_response.alerts

        # Web Push対象アラートのみフィルタリング（残り10日以内 or 残り5日以内）
        push_alerts = [
            alert for alert in all_alerts
            if (
                (alert.alert_type == 'renewal_deadline' and alert.days_remaining <= 10) or
                (alert.alert_type == 'assessment_incomplete' and alert.days_remaining <= 5)
            )
        ]

        # 事業所内の全スタッフを取得
        staffs = await crud.staff.get_by_office_id(db=db, office_id=office.id)

        for staff in staffs:
            # 通知設定を取得
            prefs = NotificationPreferences(**staff.notification_preferences)

            # メール送信（email_notification=trueの場合）
            # ⚠️ 既存実装維持: 30日以内全てのアラートを送信（閾値変更なし）
            if prefs.email_notification:
                if not dry_run:
                    await send_deadline_alert_email(
                        staff=staff,
                        office=office,
                        alerts=all_alerts  # ← 30日以内全て（既存実装維持）
                    )
                email_count += 1

            # Web Push送信（system_notification=true かつ push_alerts存在する場合）
            if prefs.system_notification and push_alerts:
                # スタッフの全購読デバイスを取得
                subscriptions = await crud.push_subscription.get_by_staff_id(
                    db=db,
                    staff_id=staff.id
                )

                if subscriptions:
                    # Push通知ペイロード作成
                    renewal_count = len([a for a in push_alerts if a['type'] == 'renewal_deadline'])
                    assessment_count = len([a for a in push_alerts if a['type'] == 'assessment_incomplete'])

                    payload_data = {
                        "type": "deadline_alert",
                        "office_id": str(office.id),
                        "renewal_count": renewal_count,
                        "assessment_count": assessment_count,
                        "alerts": push_alerts
                    }

                    # 各デバイスにPush送信
                    for sub in subscriptions:
                        try:
                            if not dry_run:
                                success = await send_push_notification(
                                    subscription_info={
                                        "endpoint": sub.endpoint,
                                        "keys": {
                                            "p256dh": sub.p256dh_key,
                                            "auth": sub.auth_key
                                        }
                                    },
                                    title=f"🚨 緊急：期限アラート（{office.name}）",
                                    body=f"更新期限: {renewal_count}件、アセスメント未完了: {assessment_count}件",
                                    icon="/logo.png",
                                    badge="/badge.png",
                                    data=payload_data
                                )

                                if success:
                                    push_sent_count += 1
                                else:
                                    push_failed_count += 1
                                    # 購読期限切れの場合は削除
                                    await crud.push_subscription.delete_by_endpoint(
                                        db=db,
                                        endpoint=sub.endpoint
                                    )
                            else:
                                push_sent_count += 1

                        except Exception as e:
                            logger.error(f"[PUSH] Failed to send deadline alert: {e}")
                            push_failed_count += 1

    logger.info(
        f"[DEADLINE] Sent: email={email_count}, push_sent={push_sent_count}, push_failed={push_failed_count}"
    )

    return {
        "email_sent": email_count,
        "push_sent": push_sent_count,
        "push_failed": push_failed_count
    }
```

---

### Step 4: Frontend実装（11-16時間）

#### 4.1 Service Worker作成（3-4時間）

前述の`public/sw.js`を実装

#### 4.2 Push購読Hook作成（2-3時間）

前述の`hooks/usePushNotification.ts`を実装

#### 4.3 通知設定UI作成（3-4時間）

前述の`components/protected/profile/NotificationSettings.tsx`を実装

#### 4.4 プロフィール画面統合（1-2時間）

```tsx
// app/(protected)/profile/page.tsx

import NotificationSettings from '@/components/protected/profile/NotificationSettings';

export default function ProfilePage() {
  return (
    <div className="container mx-auto p-6 space-y-8">
      <h1 className="text-2xl font-bold">プロフィール設定</h1>

      {/* 既存のプロフィール設定... */}

      {/* 通知設定（新規追加） */}
      <NotificationSettings />
    </div>
  );
}
```

---

### Step 5: テスト・動作確認（5-7時間）

#### 5.1 Backendテスト（3-4時間）

```python
# tests/api/v1/test_staff_notification_preferences.py

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.security import create_access_token

@pytest.mark.asyncio
async def test_get_notification_preferences(
    async_client: AsyncClient,
    db_session: AsyncSession,
    office_factory,
    staff_factory
):
    """通知設定取得テスト"""
    office = await office_factory()
    staff = await staff_factory(office_id=office.id)
    await db_session.commit()

    token = create_access_token(subject=str(staff.id))
    headers = {"Authorization": f"Bearer {token}"}

    response = await async_client.get(
        "/api/v1/staffs/me/notification-preferences",
        headers=headers
    )

    assert response.status_code == 200
    data = response.json()
    assert data["in_app_notification"] is True
    assert data["email_notification"] is True
    assert data["system_notification"] is False

@pytest.mark.asyncio
async def test_update_notification_preferences(
    async_client: AsyncClient,
    db_session: AsyncSession,
    office_factory,
    staff_factory
):
    """通知設定更新テスト"""
    office = await office_factory()
    staff = await staff_factory(office_id=office.id)
    await db_session.commit()

    token = create_access_token(subject=str(staff.id))
    headers = {"Authorization": f"Bearer {token}"}

    response = await async_client.put(
        "/api/v1/staffs/me/notification-preferences",
        headers=headers,
        json={
            "in_app_notification": True,
            "email_notification": False,
            "system_notification": True
        }
    )

    assert response.status_code == 200
    data = response.json()
    assert data["email_notification"] is False
    assert data["system_notification"] is True

@pytest.mark.asyncio
async def test_update_all_false_should_fail(
    async_client: AsyncClient,
    db_session: AsyncSession,
    office_factory,
    staff_factory
):
    """全てfalseの場合はエラーになるテスト"""
    office = await office_factory()
    staff = await staff_factory(office_id=office.id)
    await db_session.commit()

    token = create_access_token(subject=str(staff.id))
    headers = {"Authorization": f"Bearer {token}"}

    response = await async_client.put(
        "/api/v1/staffs/me/notification-preferences",
        headers=headers,
        json={
            "in_app_notification": False,
            "email_notification": False,
            "system_notification": False
        }
    )

    assert response.status_code == 422  # Validation error
```

```python
# tests/tasks/test_deadline_notification_with_push.py

import pytest
from app.tasks.deadline_notification import send_deadline_alert_emails

@pytest.mark.asyncio
async def test_deadline_notification_with_push(
    db_session,
    office_factory,
    staff_factory,
    welfare_recipient_factory
):
    """期限アラート送信（Web Push含む）テスト"""
    # テストデータ作成
    office = await office_factory()
    staff = await staff_factory(
        office_id=office.id,
        notification_preferences={
            "in_app_notification": True,
            "email_notification": True,
            "system_notification": True
        }
    )

    # Push購読登録
    subscription = await push_subscription_factory(staff_id=staff.id)

    # 期限間近の利用者作成（残り5日）
    recipient = await welfare_recipient_factory(
        office_id=office.id,
        renewal_date=(datetime.now(timezone.utc) + timedelta(days=5)).date()
    )

    await db_session.commit()

    # バッチ実行（dry_run=True）
    result = await send_deadline_alert_emails(db=db_session, dry_run=True)

    # アサーション
    assert result["email_sent"] >= 1
    assert result["push_sent"] >= 1
    assert result["push_failed"] == 0
```

#### 5.2 Frontendテスト（2-3時間）

**手動テスト項目**:

| テスト項目 | 確認内容 | 期待結果 |
|----------|---------|---------|
| **ブラウザサポート判定** | Chrome/Firefox/Safariで開く | isSupported=trueが表示される |
| **通知許可リクエスト** | システム通知をON | ブラウザ通知許可ダイアログが表示 |
| **購読登録成功** | 許可後、設定が保存される | トースト「通知設定を更新しました」 |
| **購読解除成功** | システム通知をOFF | 購読解除完了、設定が保存される |
| **全てOFF禁止** | 3つ全てOFF | エラー「少なくとも1つ...」 |
| **設定永続化** | ページリロード | 設定が保持されている |
| **Push通知受信** | バッチ実行後 | OS通知が表示される |
| **通知クリック** | 「詳細を見る」クリック | /recipients?filter=deadlineに遷移 |

---

## 12. テスト計画

### 12.1 単体テスト

| カテゴリ | テスト数 | 内容 |
|---------|---------|------|
| **Backend API** | 4テスト | 通知設定取得/更新、バリデーション |
| **Backend バッチ** | 3テスト | 期限アラート送信、Push送信、設定反映 |
| **Frontend Hook** | - | 手動テスト（Jest未導入のため） |
| **合計** | **7テスト** | - |

### 12.2 結合テスト

| テストケース | 手順 | 期待結果 |
|------------|------|---------|
| **E2E: 購読〜通知受信** | 1. プロフィール画面でシステム通知ON<br>2. バッチ実行<br>3. 通知受信確認 | OS通知が表示される |
| **設定反映** | 1. メール通知OFF<br>2. バッチ実行 | メール送信されない、Push送信される |
| **購読期限切れ** | 1. 無効なendpointでPush送信<br>2. バッチ実行後確認 | 購読レコードが削除される |

### 12.3 ブラウザテスト

| ブラウザ | バージョン | テスト項目 | 担当者 |
|---------|----------|----------|-------|
| Chrome (Desktop) | 最新版 | 全機能（PWA化なしでOK） | - |
| Firefox (Desktop) | 最新版 | 全機能（PWA化なしでOK） | - |
| Safari (macOS) | 16.4+ | 全機能（PWA化なしでOK） | - |
| Chrome (Android) | 最新版 | 全機能、ホーム画面追加テスト | - |
| Safari (iOS) | 16.4+ | **PWA化必須**、ホーム画面追加後の動作 | - |

#### iOS Safari専用テスト項目

| テスト項目 | 確認内容 | 期待結果 |
|----------|---------|---------|
| **PWA判定** | 通常のSafariでアクセス | システム通知が無効、iOSガイダンス表示 |
| **ホーム画面追加** | 共有 > ホーム画面に追加 | アイコン作成、「計画くん」と表示 |
| **PWA起動** | ホーム画面アイコンからアプリ起動 | スタンドアロンモードで起動 |
| **PWA判定（起動後）** | システム通知設定確認 | システム通知が有効、PWA成功メッセージ表示 |
| **通知許可** | システム通知ON | iOS通知許可ダイアログ表示 |
| **Push受信** | バッチ実行後 | ロック画面に通知表示 |
| **通知クリック** | 通知タップ | アプリ起動、該当ページに遷移 |

---

## 13. リスク分析

### 13.1 技術リスク

| リスク | 発生確率 | 影響度 | 対策 |
|-------|---------|-------|------|
| **iOS Safari対応** | 中 | 高 | ホーム画面追加必須の仕様を明示、サポートページ作成 |
| **通知許可拒否** | 高 | 中 | システム通知OFF時はメール・アプリ内通知で補完 |
| **購読期限切れ** | 中 | 低 | バッチ処理で自動削除、エラーログ監視 |
| **バッチ処理遅延** | 低 | 中 | タイムアウト設定、リトライロジック追加 |

### 13.2 運用リスク

| リスク | 発生確率 | 影響度 | 対策 |
|-------|---------|-------|------|
| **通知疲労** | 中 | 中 | 緊急のみプッシュ（10日以内、5日以内）に制限 |
| **通知が届かない** | 中 | 高 | トラブルシューティングガイド作成、サポート体制強化 |
| **VAPID鍵漏洩** | 低 | 高 | 環境変数管理徹底、定期ローテーション |

---

## 14. 今後の拡張

### 14.1 Phase 4: 通知カスタマイズ（オプション）

- 通知タイプ別ON/OFF（renewal_deadline/assessment_incomplete個別設定）
- 通知時間帯設定（DND機能：夜間は通知しない）
- 通知音・バイブレーション設定

### 14.2 Phase 5: 通知履歴機能（オプション）

- `push_notification_logs`テーブル作成
- 送信履歴表示UI
- 再送機能

---

## 15. まとめ

本要件定義書では、残り期限通知のWeb Push実装について以下を定義しました：

### ✅ 実装範囲

- **対象アラート**: renewal_deadline（残り10日以内）、assessment_incomplete（残り5日以内）
- **通知タイミング**: 毎日9:00 JST（平日のみ）
- **設定機能**: プロフィール画面で3種類の通知ON/OFF

### 📊 工数見積

- **Backend**: 11-14時間
- **Frontend（PWA対応含む）**: 16-22時間
- **総工数**: 27-36時間（約3.5-4.5日）
- **PWA対応追加工数**: +5-6時間

### 🎯 期待効果

1. **見逃し防止**: ブラウザ閉じていても期限アラートを受信
2. **通知疲労軽減**: 緊急度の高いアラートのみプッシュ
3. **ユーザーコントロール**: 通知チャネルを自由に選択可能
4. **既存実装との共存**: アプリ内通知・メールと相互補完

### 🚀 次のアクション

1. ステークホルダー承認取得
2. アイコン素材準備（デザイナー依頼）
3. 実装開始
   - Step 0: PWA化対応（manifest.json、アイコン、layout.tsx）
   - Step 1: DBマイグレーション
   - Step 2-5: Backend/Frontend実装
4. テスト実施（iOS実機テスト含む）
5. ステージング環境デプロイ
6. 本番環境リリース

---

**最終更新**: 2026-01-14（PWA対応追加）
**承認者**: -
**次回レビュー**: 実装完了後

**変更履歴**:
- 2026-01-14: PWA化対応を追加（iOS Safari対応のため）
  - manifest.json作成
  - PWAメタタグ追加
  - iOS判定ロジック追加
  - iOSガイダンスUI追加
  - 工数見積更新（+5-6時間）
