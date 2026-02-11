# パフォーマンス最適化ドキュメント

**Gmail期限通知バッチ処理のスケーラビリティ改善**

---

## 📚 ドキュメント構成

このディレクトリには、Gmail期限通知バッチ処理の最適化に関する全てのドキュメントが含まれています。

| ファイル | 内容 | 対象読者 |
|---------|------|---------|
| **[issue_deadline_notification_optimization.md](./issue_deadline_notification_optimization.md)** | Issue定義、背景、目標、受け入れ基準 | 全員 |
| **[performance_requirements.md](./performance_requirements.md)** | パフォーマンス要件の詳細仕様 | 開発者、QA |
| **[implementation_plan.md](./implementation_plan.md)** | TDD実装手順（段階的な実装計画） | 開発者 |
| **[test_specifications.md](./test_specifications.md)** | テスト仕様書（全テストケース） | 開発者、QA |
| **README.md** | 本ファイル（概要とクイックスタート） | 全員 |

---

## 🎯 最適化の概要

### 課題

現在の実装では、事業所数が増加すると処理時間が線形に増加し、500事業所で25分かかる。

### 目標

**500事業所規模で5分以内**に処理を完了し、メモリ使用量を1/10に削減する。

### 改善内容

1. **N+1クエリ解消**: バッチクエリで250倍削減（1001回 → 4回）
2. **並列処理**: 事業所処理を10並列化（8倍高速化）
3. **メモリ効率化**: チャンク処理で10倍削減（500MB → 50MB）

### 期待される効果

| メトリクス | 改善前 | 改善後 | 改善率 |
|-----------|--------|--------|--------|
| 処理時間（500事業所） | 25分 | **3分** | **8倍** |
| DBクエリ数（500事業所） | 1,001回 | **4回** | **250倍** |
| メモリ使用量（500事業所） | 500MB | **35MB** | **14倍** |

---

## 🚀 クイックスタート

### 1. ドキュメントを読む順序

```
1. issue_deadline_notification_optimization.md
   └─ 背景・目標・受け入れ基準を理解

2. performance_requirements.md
   └─ 具体的な数値目標を確認

3. implementation_plan.md
   └─ 実装手順を理解（TDDアプローチ）

4. test_specifications.md
   └─ テスト仕様を確認
```

### 2. 実装を開始

```bash
# リポジトリのルートディレクトリで実行

# Phase 1: パフォーマンステスト追加
# → implementation_plan.md の Phase 1 を参照

# Phase 2: バッチクエリ実装
# → implementation_plan.md の Phase 2 を参照

# Phase 3-5: 並列処理・検証・ドキュメント更新
# → implementation_plan.md の Phase 3-5 を参照
```

### 3. テスト実行

```bash
# パフォーマンステスト実行
docker exec keikakun_app-backend-1 pytest tests/performance/ -v -m performance

# 既存テスト実行（互換性確認）
docker exec keikakun_app-backend-1 pytest tests/tasks/test_deadline_notification*.py -v

# 全テスト実行
docker exec keikakun_app-backend-1 pytest tests/ -v --cov=app
```

---

## 📖 各ドキュメントの概要

### Issue定義

**[issue_deadline_notification_optimization.md](./issue_deadline_notification_optimization.md)**

- **内容**: 課題の背景、目標、受け入れ基準、実装計画の概要
- **重要ポイント**:
  - 現状の問題点（N+1クエリ、直列処理、メモリ非効率）
  - パフォーマンス目標（5分以内、クエリ10以下、メモリ50MB以下）
  - リスクと対策
  - 実装スケジュール（5.5日）

### パフォーマンス要件

**[performance_requirements.md](./performance_requirements.md)**

- **内容**: 数値目標の詳細、測定方法、テストケース
- **重要ポイント**:
  - 処理時間要件（事業所数別の目標値）
  - DBクエリ効率要件（O(1)であること）
  - メモリ効率要件（メモリリーク検出）
  - 測定方法（コード例付き）

### 実装計画

**[implementation_plan.md](./implementation_plan.md)**

- **内容**: TDDアプローチによる段階的実装手順
- **重要ポイント**:
  - Phase 1: パフォーマンステスト追加（RED）
  - Phase 2: バッチクエリ実装（GREEN）
  - Phase 3: 既存テスト互換性確認
  - Phase 4: 並列処理実装（GREEN）
  - Phase 5: 最終検証・ドキュメント更新
  - 各フェーズのチェックリスト

### テスト仕様書

**[test_specifications.md](./test_specifications.md)**

- **内容**: 全テストケースの詳細仕様
- **重要ポイント**:
  - パフォーマンステスト（処理時間、メモリ、クエリ数）
  - 負荷テスト（スケーラビリティ、エラー耐性）
  - 回帰テスト（後方互換性）
  - 統合テスト（エンドツーエンド）
  - テストフィクスチャの実装

---

## 🎯 成功基準

### 必須要件（全て満たす必要あり）

- ✅ 既存の全テストがパスする
- ✅ 500事業所・5,000スタッフで5分以内に完了
- ✅ DBクエリ数が10以下
- ✅ メモリ使用量が50MB以下
- ✅ コードカバレッジ85%以上

### パフォーマンス目標

```
処理時間: 25分 → 3分（8倍高速化）
DBクエリ数: 1,001回 → 4回（250倍削減）
メモリ使用量: 500MB → 35MB（14倍削減）
```

---

## 💡 アーキテクチャ変更の概要

### 変更前（問題あり）

```python
# N+1クエリ問題
for office in offices:  # 500回ループ
    alerts = await get_deadline_alerts(office.id)  # 500回クエリ
    staffs = await get_staffs(office.id)           # 500回クエリ

    # メール送信のみ並列（5件まで）
    for staff in staffs:
        await send_email(staff)
```

**問題点**:
- クエリ数: O(N) - 事業所数に比例
- 処理: 直列 - 1事業所ずつ順次処理
- 並列度: 5（メール送信のみ）

### 変更後（最適化済み）

```python
# バッチクエリ（O(1)）
office_ids = [office.id for office in offices]
alerts_by_office = await get_deadline_alerts_batch(office_ids)  # 2クエリ
staffs_by_office = await get_staffs_by_offices_batch(office_ids)  # 1クエリ

# 事業所処理を並列化（10並列）
async def process_office(office_id):
    alerts = alerts_by_office[office_id]
    staffs = staffs_by_office[office_id]

    # メール送信も並列（5件まで）
    for staff in staffs:
        await send_email(staff)

# 10事業所を同時処理
await asyncio.gather(*[
    process_office(office_id)
    for office_id in office_ids
])
```

**改善点**:
- クエリ数: O(1) - 定数（4回）
- 処理: 並列 - 10事業所を同時処理
- 並列度: 50（10事業所 × 5メール）

---

## 📊 実装進捗トラッキング

### マイルストーン

- [ ] M1: パフォーマンステスト完成（Day 1）
- [ ] M2: バッチクエリ実装完成（Day 3）
- [ ] M3: 並列処理実装完成（Day 4）
- [ ] M4: 最終検証・リリース準備完了（Day 5）

### 時間見積もり

| フェーズ | 見積もり | 説明 |
|---------|---------|------|
| Phase 1 | 1日 | パフォーマンステスト追加 |
| Phase 2 | 2日 | バッチクエリ実装 |
| Phase 3 | 0.5日 | 既存テスト互換性確認 |
| Phase 4 | 1日 | 並列処理実装 |
| Phase 5 | 0.5日 | 最終検証・ドキュメント |
| **合計** | **5日** | - |

---

## 🔍 関連リソース

### コードファイル

- **メインバッチ処理**: `k_back/app/tasks/deadline_notification.py`
- **サービス層**: `k_back/app/services/welfare_recipient_service.py`
- **スケジューラー**: `k_back/app/scheduler/deadline_notification_scheduler.py`

### テストファイル

- **既存テスト**: `k_back/tests/tasks/test_deadline_notification*.py`
- **パフォーマンステスト**: `k_back/tests/performance/test_deadline_notification_performance.py`

### ドキュメント

- **プロジェクト全体**: `/.claude/CLAUDE.md`
- **カレンダー連携**: `/md_files_design_note/task_done/google_calendar.md`
- **アーキテクチャ**: `/.claude/rules/architecture.md`

---

## 🚨 注意事項

### 実装時の注意

1. **TDDアプローチを厳守**: テストを先に書いてから実装
2. **段階的な実装**: 一度に全て変更しない
3. **既存テストを常に実行**: 互換性を維持

### テスト実行の注意

1. **パフォーマンステストは時間がかかる**: 500事業所で5-10分
2. **CI/CDで自動実行**: PR作成時に自動実行される
3. **ローカルでも定期的に実行**: 性能劣化を早期発見

### リリース時の注意

1. **カナリアデプロイ推奨**: 段階的にロールアウト
2. **モニタリング設定**: 処理時間・メモリ・エラー率を監視
3. **ロールバック手順確認**: 問題発生時の切り戻し手順

---

## 📞 問い合わせ

### 質問・相談

- **担当チーム**: Backend Team
- **レビュワー**: Tech Lead, SRE Team
- **承認者**: CTO

### 関連Issue

- **GitHub Issue**: #XXX
- **Slack**: #backend-performance

---

## 📝 変更履歴

| 日付 | 変更内容 | 担当者 |
|------|---------|--------|
| 2026-02-08 | ドキュメント初版作成 | Claude |
| - | - | - |

---

**最終更新日**: 2026-02-08
**作成者**: Claude Sonnet 4.5
**バージョン**: 1.0.0
