# Phase 2: イベント駆動通知のWeb Push化 - 影響範囲分析

## 目次
1. [現状の通知システム概要](#1-現状の通知システム概要)
2. [Web Push導入の方針](#2-web-push導入の方針)
3. [実装パターンの比較](#3-実装パターンの比較)
4. [推奨アーキテクチャ](#4-推奨アーキテクチャ)
5. [影響を受けるファイル](#5-影響を受けるファイル)
6. [実装ステップ](#6-実装ステップ)
7. [リスク分析](#7-リスク分析)

---

## 1. 現状の通知システム概要

### 1.1 通知の種類（イベント駆動）

| 通知タイプ | トリガー | 受信者 | 内容 |
|-----------|---------|--------|------|
| `role_change_pending` | Role変更リクエスト作成 | 承認者（manager/owner） | 承認待ち通知 |
| `role_change_approved` | Role変更リクエスト承認 | リクエスト作成者 + 承認者 | 承認完了通知 |
| `role_change_rejected` | Role変更リクエスト却下 | リクエスト作成者 + 承認者 | 却下通知 |
| `employee_action_pending` | Employee操作リクエスト作成 | 承認者（manager/owner） | 承認待ち通知 |
| `employee_action_approved` | Employee操作リクエスト承認 | リクエスト作成者 + 承認者 | 承認完了通知 |
| `employee_action_rejected` | Employee操作リクエスト却下 | リクエスト作成者 + 承認者 | 却下通知 |

### 1.2 現在の通知フロー

```
┌──────────────────────────────────────────────────────────────────┐
│ 1. リクエスト作成（employee_action_service.py:create_request）   │
│    ├─ approval_requests テーブルにレコード作成                    │
│    ├─ Noticeテーブルに通知作成                                    │
│    │   ├─ 承認者全員に "pending" 通知                             │
│    │   └─ リクエスト作成者に "request_sent" 通知                  │
│    └─ DB commit                                                   │
└──────────────────────────────────────────────────────────────────┘
                           ↓
┌──────────────────────────────────────────────────────────────────┐
│ 2. フロントエンド（ポーリング）                                   │
│    ├─ 30秒ごとに GET /api/v1/notices/unread-count                │
│    ├─ 未読件数をヘッダーのベルアイコンに表示                      │
│    └─ ユーザーがベルをクリック → 通知一覧ページへ                │
└──────────────────────────────────────────────────────────────────┘
                           ↓
┌──────────────────────────────────────────────────────────────────┐
│ 3. 承認/却下（employee_action_service.py:approve/reject_request）│
│    ├─ 既存の "pending" と "request_sent" 通知を削除              │
│    ├─ 新しい "approved/rejected" 通知を作成                      │
│    │   ├─ リクエスト作成者に通知                                 │
│    │   └─ 承認者全員に通知                                       │
│    └─ DB commit                                                   │
└──────────────────────────────────────────────────────────────────┘
```

### 1.3 技術スタック

- **DB**: `notices`テーブル（PostgreSQL）
- **Backend**: FastAPI + SQLAlchemy（CRUD: `crud_notice.py`）
- **Frontend**: Next.js + 30秒ポーリング（`LayoutClient.tsx`）
- **通知上限**: 事業所あたり50件（超過時に古い通知を自動削除）

---

## 2. Web Push導入の方針

### 2.1 設計方針の選択肢

#### オプションA: **完全置き換え**
- Noticeテーブルを削除し、Web Push通知のみにする
- **メリット**: シンプル、DBの肥大化防止
- **デメリット**:
  - 通知履歴が消える（ブラウザを閉じたら見れない）
  - Push未購読ユーザーは通知を受け取れない
  - 過去の通知を遡れない

#### オプションB: **完全共存（両方維持）**
- Noticeテーブルは残し、Web Pushを追加で送信
- **メリット**:
  - 通知履歴が残る
  - Push未購読でも既存通知で補完
  - ユーザー体験の向上（リアルタイム + 履歴）
- **デメリット**:
  - 実装が複雑
  - Noticeテーブルの肥大化

#### オプションC: **段階的移行（ハイブリッド）**
- 最初は共存、将来的にNoticeテーブルを削除
- **メリット**: リスク低減、段階的な移行
- **デメリット**: 移行期間中のメンテナンスコスト

---

## 3. 実装パターンの比較

### 3.1 パターン1: 通知作成時にPushも同時送信

```python
# employee_action_service.py - _create_request_notification()

async def _create_request_notification(...):
    # 1. Noticeテーブルに通知作成（既存）
    notice = await crud.notice.create(db, obj_in=notice_data)

    # 2. Web Push送信（新規追加）★
    await _send_push_for_notice(db, notice, approver_id)

    await db.commit()

async def _send_push_for_notice(db, notice, staff_id):
    """通知のWeb Push送信"""
    # スタッフの全デバイスを取得
    subscriptions = await crud.push_subscription.get_by_staff_id(db, staff_id)

    # 各デバイスにPush送信
    for sub in subscriptions:
        await send_push_notification(
            subscription_info=PushSubscriptionInfo.from_db_model(sub),
            title=notice.title,
            body=notice.content or "",
            data={
                "type": "approval_request",
                "notice_id": str(notice.id),
                "link_url": notice.link_url
            }
        )
```

**影響範囲:**
- ✅ `employee_action_service.py` - `_create_request_notification()` 修正
- ✅ `role_change_service.py` - `_create_request_notification()` 修正
- ✅ 新規ヘルパー関数 `_send_push_for_notice()` 追加

**メリット:**
- 既存コードの変更が最小限
- Notice作成とPush送信が同じトランザクション内

**デメリット:**
- Push送信失敗時にNotice作成もロールバックされる可能性

---

### 3.2 パターン2: 通知作成後にバックグラウンドでPush送信

```python
# employee_action_service.py - _create_request_notification()

async def _create_request_notification(...):
    # 1. Noticeテーブルに通知作成
    notice = await crud.notice.create(db, obj_in=notice_data)
    await db.commit()

    # 2. バックグラウンドタスクでPush送信（新規追加）★
    background_tasks.add_task(
        send_push_for_notice,
        notice_id=notice.id,
        staff_id=approver_id
    )

# background_tasks.py（新規ファイル）
async def send_push_for_notice(notice_id: UUID, staff_id: UUID):
    """バックグラウンドでPush送信"""
    async with AsyncSessionLocal() as db:
        # Noticeを取得
        notice = await crud.notice.get(db, id=notice_id)

        # スタッフの全デバイスを取得
        subscriptions = await crud.push_subscription.get_by_staff_id(db, staff_id)

        # Push送信
        for sub in subscriptions:
            await send_push_notification(...)
```

**影響範囲:**
- ✅ `employee_action_service.py` - `_create_request_notification()` 修正
- ✅ `role_change_service.py` - `_create_request_notification()` 修正
- ✅ `app/background_tasks.py` - 新規ファイル作成
- ✅ エンドポイント層 - `background_tasks` パラメータ追加

**メリット:**
- Push送信失敗してもNotice作成は成功する
- API応答時間が短縮される

**デメリット:**
- バックグラウンドタスクの管理が必要
- デバッグが複雑

---

### 3.3 パターン3: 専用のPush通知サービス層を作成

```python
# app/services/push_notification_service.py（新規ファイル）

class PushNotificationService:
    """Push通知送信サービス"""

    @staticmethod
    async def send_approval_request_notification(
        db: AsyncSession,
        notice: Notice,
        staff_ids: List[UUID]
    ) -> int:
        """承認リクエスト通知を送信"""
        sent_count = 0

        for staff_id in staff_ids:
            subscriptions = await crud.push_subscription.get_by_staff_id(db, staff_id)

            for sub in subscriptions:
                success = await send_push_notification(
                    subscription_info=PushSubscriptionInfo.from_db_model(sub),
                    title=notice.title,
                    body=notice.content or "",
                    data={
                        "type": "approval_request",
                        "notice_id": str(notice.id),
                        "link_url": notice.link_url
                    }
                )
                if success:
                    sent_count += 1
                else:
                    # 購読期限切れの場合は削除
                    await crud.push_subscription.delete_by_endpoint(db, sub.endpoint)

        return sent_count

# employee_action_service.py での利用
async def _create_request_notification(...):
    # Notice作成（既存）
    notice = await crud.notice.create(db, obj_in=notice_data)

    # Push送信（新規）★
    await PushNotificationService.send_approval_request_notification(
        db=db,
        notice=notice,
        staff_ids=[approver_id]
    )

    await db.commit()
```

**影響範囲:**
- ✅ `app/services/push_notification_service.py` - 新規ファイル作成
- ✅ `employee_action_service.py` - `_create_request_notification()` 修正
- ✅ `role_change_service.py` - `_create_request_notification()` 修正

**メリット:**
- 責任の分離（Single Responsibility Principle）
- テストしやすい
- 再利用可能

**デメリット:**
- ファイル数が増える

---

## 4. 推奨アーキテクチャ

### 4.1 推奨: **オプションB（完全共存） × パターン3（専用サービス層）**

#### 理由

1. **ユーザー体験の最大化**
   - リアルタイム通知（Web Push） + 履歴（Noticeテーブル）
   - Push未購読ユーザーも既存通知で補完

2. **段階的な移行が可能**
   - 最初は共存、データ分析後にNotice削除を検討

3. **保守性の向上**
   - 専用サービス層でPush送信ロジックを集約
   - テストしやすい

4. **リスク低減**
   - 既存の通知システムは変更しない
   - Push送信失敗しても通知は届く

#### アーキテクチャ図

```
┌─────────────────────────────────────────────────────────────────┐
│ API Layer (employee_action_requests.py)                         │
│   POST /approve                                                 │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ Service Layer (employee_action_service.py)                      │
│   approve_request()                                             │
│     ├─ CRUD: 承認処理                                            │
│     ├─ CRUD: Notice作成                                         │
│     ├─ PushNotificationService.send_approval_request()  ← 追加 │
│     └─ commit()                                                 │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ Push Notification Service (push_notification_service.py) ← 新規 │
│   send_approval_request_notification()                          │
│     ├─ crud.push_subscription.get_by_staff_id()                 │
│     └─ send_push_notification() × N devices                     │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ Core Layer (push.py)                                            │
│   send_push_notification()                                      │
│     └─ pywebpush.webpush()                                      │
└─────────────────────────────────────────────────────────────────┘
```

---

## 5. 影響を受けるファイル

### 5.1 新規作成ファイル

| ファイルパス | 目的 | 行数見積 |
|-------------|------|---------|
| `k_back/app/services/push_notification_service.py` | Push送信サービス層 | 150-200行 |
| `k_back/tests/services/test_push_notification_service.py` | サービス層のテスト | 200-300行 |

### 5.2 修正が必要なファイル

| ファイルパス | 修正箇所 | 修正内容 | 影響度 |
|-------------|---------|---------|-------|
| `k_back/app/services/employee_action_service.py` | `_create_request_notification()` | Push送信呼び出し追加 | 小 |
| `k_back/app/services/employee_action_service.py` | `approve_request()` | Push送信呼び出し追加 | 小 |
| `k_back/app/services/employee_action_service.py` | `reject_request()` | Push送信呼び出し追加 | 小 |
| `k_back/app/services/role_change_service.py` | `_create_request_notification()` | Push送信呼び出し追加 | 小 |
| `k_back/app/services/role_change_service.py` | `approve_request()` | Push送信呼び出し追加 | 小 |
| `k_back/app/services/role_change_service.py` | `reject_request()` | Push送信呼び出し追加 | 小 |
| `k_back/tests/services/test_employee_action_service.py` | 各テスト | Push送信のモック追加 | 中 |
| `k_back/tests/services/test_role_change_service.py` | 各テスト | Push送信のモック追加 | 中 |

### 5.3 修正不要なファイル

- ✅ `k_back/app/models/notice.py` - そのまま使用
- ✅ `k_back/app/crud/crud_notice.py` - そのまま使用
- ✅ `k_back/app/api/v1/endpoints/notices.py` - そのまま使用
- ✅ `k_back/app/api/v1/endpoints/employee_action_requests.py` - サービス層経由なので影響なし
- ✅ `k_back/app/api/v1/endpoints/role_change_requests.py` - サービス層経由なので影響なし
- ✅ `k_front/*` - Phase 4（Frontend実装）で対応

---

## 6. 実装ステップ

### Step 1: Push通知サービス層の作成（3-4時間）

**実装内容:**
```python
# k_back/app/services/push_notification_service.py

class PushNotificationService:
    """承認リクエスト通知のPush送信サービス"""

    @staticmethod
    async def send_approval_request_notification(
        db: AsyncSession,
        notice_type: str,
        title: str,
        body: str,
        link_url: str,
        staff_ids: List[UUID]
    ) -> Dict[str, int]:
        """
        承認リクエスト通知を複数のスタッフに送信

        Returns:
            {"sent": 成功件数, "failed": 失敗件数, "removed": 期限切れ購読削除件数}
        """
        sent = 0
        failed = 0
        removed = 0

        for staff_id in staff_ids:
            subscriptions = await crud.push_subscription.get_by_staff_id(db, staff_id)

            for sub in subscriptions:
                success = await send_push_notification(
                    subscription_info=PushSubscriptionInfo.from_db_model(sub),
                    title=title,
                    body=body,
                    data={
                        "type": "approval_request",
                        "notice_type": notice_type,
                        "link_url": link_url
                    },
                    actions=[
                        {"action": "view", "title": "確認する"},
                        {"action": "close", "title": "閉じる"}
                    ]
                )

                if success:
                    sent += 1
                else:
                    # 購読期限切れ（404/410）の場合は削除
                    deleted = await crud.push_subscription.delete_by_endpoint(db, sub.endpoint)
                    if deleted:
                        removed += 1
                    failed += 1

        logger.info(
            f"[PUSH] Approval request notification sent: "
            f"sent={sent}, failed={failed}, removed={removed}"
        )

        return {"sent": sent, "failed": failed, "removed": removed}
```

**チェックリスト:**
- [ ] `PushNotificationService` クラス作成
- [ ] `send_approval_request_notification()` メソッド実装
- [ ] エラーハンドリング（購読期限切れ削除）
- [ ] ログ出力
- [ ] 型ヒント完備

---

### Step 2: employee_action_service.pyの修正（2-3時間）

**修正箇所1: `_create_request_notification()`**

```python
async def _create_request_notification(
    db: AsyncSession,
    request: ApprovalRequest,
    approvers: List[Staff]
) -> None:
    """リクエスト作成時の通知（既存ロジック + Push送信追加）"""

    # 既存: Notice作成（承認者向け）
    for approver in approvers:
        notice_data = NoticeCreate(...)
        await crud.notice.create(db, obj_in=notice_data)

    # 既存: Notice作成（リクエスト作成者向け）
    requester_notice = NoticeCreate(...)
    await crud.notice.create(db, obj_in=requester_notice)

    # 🆕 追加: Web Push送信
    approver_ids = [approver.id for approver in approvers]
    await PushNotificationService.send_approval_request_notification(
        db=db,
        notice_type=NoticeType.employee_action_pending.value,
        title=f"{requester.full_name}さんが{detail_info}リクエストしました。",
        body=f"{requester.full_name}さんが{detail_info}リクエストしました。",
        link_url=f"/approval-requests/{request.id}",
        staff_ids=approver_ids
    )

    # 既存: 通知上限チェック
    await crud.notice.delete_old_notices_over_limit(db, office_id, limit=50)
```

**修正箇所2: `approve_request()`**

```python
async def approve_request(...) -> ApprovalRequest:
    """リクエスト承認時の通知（既存ロジック + Push送信追加）"""

    # 既存: 承認処理
    request.status = RequestStatus.approved
    ...

    # 既存: 古い通知削除
    await _delete_old_notices(db, link_url)

    # 既存: 新しい通知作成（承認完了）
    await crud.notice.create(db, obj_in=requester_notice)
    for approver in approvers:
        await crud.notice.create(db, obj_in=approver_notice)

    # 🆕 追加: Web Push送信
    all_staff_ids = [request.requester_staff_id] + [a.id for a in approvers]
    await PushNotificationService.send_approval_request_notification(
        db=db,
        notice_type=NoticeType.employee_action_approved.value,
        title="作成、編集、削除リクエストが承認されました",
        body=f"あなたの{detail_info}リクエストが承認されました。",
        link_url=f"/approval-requests/{request.id}",
        staff_ids=all_staff_ids
    )

    await db.commit()
    return request
```

**修正箇所3: `reject_request()`**

同様にPush送信を追加

**チェックリスト:**
- [ ] `_create_request_notification()` 修正
- [ ] `approve_request()` 修正
- [ ] `reject_request()` 修正
- [ ] import文追加（`PushNotificationService`）
- [ ] 既存コードは変更しない（追加のみ）

---

### Step 3: role_change_service.pyの修正（2-3時間）

**修正内容:**
- employee_action_service.py と同じパターンで修正
- `_create_request_notification()`, `approve_request()`, `reject_request()` にPush送信追加

**チェックリスト:**
- [ ] `_create_request_notification()` 修正
- [ ] `approve_request()` 修正
- [ ] `reject_request()` 修正
- [ ] import文追加

---

### Step 4: テストコード作成（4-6時間）

**4.1 サービス層のテスト**

```python
# tests/services/test_push_notification_service.py

@pytest.mark.asyncio
async def test_send_approval_request_notification_success(
    db_session,
    office_factory,
    staff_factory,
    mocker
):
    """Push送信が成功するテスト"""
    office = await office_factory()
    staff = await staff_factory(office_id=office.id)

    # Push購読登録
    subscription = await crud.push_subscription.create(
        db=db_session,
        obj_in=PushSubscriptionInDB(
            staff_id=staff.id,
            endpoint="https://fcm.googleapis.com/fcm/send/test",
            p256dh_key="key",
            auth_key="auth"
        )
    )
    await db_session.commit()

    # send_push_notification をモック
    mock_send = mocker.patch(
        "app.services.push_notification_service.send_push_notification",
        return_value=True
    )

    # Push送信
    result = await PushNotificationService.send_approval_request_notification(
        db=db_session,
        notice_type="employee_action_pending",
        title="テスト通知",
        body="テスト本文",
        link_url="/approval-requests/123",
        staff_ids=[staff.id]
    )

    assert result["sent"] == 1
    assert result["failed"] == 0
    assert mock_send.called
```

**4.2 既存テストの修正**

```python
# tests/services/test_employee_action_service.py

@pytest.mark.asyncio
async def test_create_request_success(
    db_session,
    office_factory,
    staff_factory,
    mocker  # 追加
):
    """リクエスト作成テスト（Push送信をモック）"""

    # Push送信をモック（追加）
    mock_push = mocker.patch(
        "app.services.push_notification_service.PushNotificationService.send_approval_request_notification",
        return_value={"sent": 1, "failed": 0, "removed": 0}
    )

    # 既存のテストロジック
    ...

    # Push送信が呼ばれたことを確認（追加）
    assert mock_push.called
```

**チェックリスト:**
- [ ] `test_push_notification_service.py` 作成（10テスト）
- [ ] `test_employee_action_service.py` 修正（Push送信モック追加）
- [ ] `test_role_change_service.py` 修正（Push送信モック追加）
- [ ] 全テスト実行（pytest）

---

## 7. リスク分析

### 7.1 技術リスク

| リスク | 影響度 | 発生確率 | 対策 |
|-------|-------|---------|-----|
| Push送信失敗でNotice作成がロールバック | 高 | 中 | Push送信をtry-catchで囲み、失敗してもNoticeは作成 |
| 購読期限切れで通知が届かない | 中 | 高 | 期限切れ購読を自動削除、Noticeで補完 |
| 複数デバイスへの送信でパフォーマンス低下 | 中 | 低 | 非同期送信、バックグラウンドタスク化を検討 |
| Push未購読ユーザーに通知が届かない | 低 | 高 | Noticeシステムで補完（共存アーキテクチャ） |

### 7.2 運用リスク

| リスク | 影響度 | 発生確率 | 対策 |
|-------|-------|---------|-----|
| ユーザーがPush許可を拒否 | 低 | 高 | Noticeシステムで補完、Frontend実装時にUI誘導 |
| 通知が多すぎてユーザーが無効化 | 中 | 低 | 通知頻度の分析、設定でON/OFF可能に（Phase 6） |
| Push送信コストの増加 | 低 | 低 | FCMは無料、帯域コストは誤差範囲 |

### 7.3 後方互換性リスク

| リスク | 影響度 | 発生確率 | 対策 |
|-------|-------|---------|-----|
| 既存のNoticeシステムとの競合 | 低 | 極低 | Noticeは変更しない、追加のみ |
| 既存テストの失敗 | 中 | 中 | Push送信をモック化、テストは全て通過させる |

---

## 8. 結論

### 8.1 推奨実装方針

**✅ オプションB（完全共存） × パターン3（専用サービス層）**

**理由:**
1. ユーザー体験の最大化（リアルタイム + 履歴）
2. リスク低減（既存システムは変更しない）
3. 保守性向上（責任の分離）

### 8.2 実装見積

| フェーズ | 作業内容 | 見積時間 |
|---------|---------|---------|
| Step 1 | Push通知サービス層の作成 | 3-4時間 |
| Step 2 | employee_action_service.py修正 | 2-3時間 |
| Step 3 | role_change_service.py修正 | 2-3時間 |
| Step 4 | テストコード作成 | 4-6時間 |
| **合計** | | **11-16時間** |

### 8.3 次のステップ

Phase 2実装後のチェックリスト:
- [ ] すべてのテストが通過
- [ ] Push送信ログが正常に出力される
- [ ] 購読期限切れが自動削除される
- [ ] Noticeシステムが既存通り動作する
- [ ] ドキュメント更新（このmdファイル）

---

**作成日**: 2026-01-13
**最終更新**: 2026-01-13
**作成者**: Claude Sonnet 4.5
