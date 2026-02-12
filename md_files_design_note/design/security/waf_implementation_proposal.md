# けいかくん - WAF実装提案書

**提案日**: 2026-02-03
**提案者**: Claude Sonnet 4.5
**対象環境**: 本番環境（Google Cloud Run）
**優先度**: High
**ステータス**: 提案段階

---

## 📋 目次

1. [エグゼクティブサマリー](#エグゼクティブサマリー)
2. [背景と目的](#背景と目的)
3. [現状のセキュリティ状況](#現状のセキュリティ状況)
4. [WAF導入の必要性](#waf導入の必要性)
5. [技術選定と比較](#技術選定と比較)
6. [推奨ソリューション](#推奨ソリューション)
7. [実装計画](#実装計画)
8. [コスト見積もり](#コスト見積もり)
9. [リスクと軽減策](#リスクと軽減策)
10. [効果測定](#効果測定)

---

## エグゼクティブサマリー

### 提案概要

けいかくんアプリケーションに**Google Cloud Armor**を導入し、Webアプリケーションファイアウォール（WAF）による多層防御を実現します。

### 期待される効果

| 項目 | 現状 | 導入後 |
|------|------|--------|
| **DDoS対策** | 基本レベル | エンタープライズレベル |
| **OWASP Top 10対策** | アプリケーション層のみ | ネットワーク層 + アプリケーション層 |
| **地理的制限** | なし | 日本国外からのアクセス制限可能 |
| **レート制限** | アプリケーション層（slowapi） | ネットワーク層 + アプリケーション層 |
| **不正アクセス検知** | ログ分析後 | リアルタイム検知・自動ブロック |

### コスト

- **初期費用**: ¥0（設定作業のみ）
- **月額運用費**: 約¥3,000〜¥8,000（トラフィック量による）
- **投資対効果**: セキュリティインシデント1件の被害額（数十万〜数百万円）を考慮すると極めて高い

### 推奨実装時期

**Phase 1（緊急）**: 2026年2月中
**Phase 2（重要）**: 2026年3月中

---

## 背景と目的

### 背景

けいかくんは福祉サービス事業所向けの個別支援計画管理システムであり、以下の特性を持ちます：

1. **機微な個人情報を扱う**
   - 利用者の個別支援計画
   - 事業所の運営情報
   - スタッフの個人情報

2. **サブスクリプション課金システム**
   - Stripe決済連携
   - Webhook処理
   - 課金ステータス管理

3. **24時間365日稼働が必要**
   - 福祉サービス事業所の業務に直結
   - ダウンタイムが事業運営に影響

### 目的

1. **セキュリティレベルの向上**
   - OWASP Top 10脆弱性への対策強化
   - DDoS攻撃への防御力向上

2. **コンプライアンス対応**
   - 個人情報保護法への準拠
   - セキュリティ監査への対応

3. **ブランド価値の保護**
   - セキュリティインシデントによる信頼失墜の防止
   - 顧客データの確実な保護

4. **運用負荷の軽減**
   - 自動的な攻撃検知・ブロック
   - セキュリティ監視の効率化

---

## 現状のセキュリティ状況

### 実装済みのセキュリティ対策

#### アプリケーション層（Layer 7）

| 対策 | 実装状況 | 実装箇所 |
|------|---------|---------|
| **JWT認証** | ✅ 実装済み | `k_back/app/core/security.py` |
| **2要素認証（TOTP）** | ✅ 実装済み | `k_back/app/api/v1/endpoints/auths.py` |
| **CSRF保護** | ✅ 実装済み | `fastapi-csrf-protect` |
| **SQL Injection対策** | ✅ 実装済み | SQLAlchemyパラメータ化クエリ |
| **XSS対策** | ✅ 実装済み | Pydantic入力検証 + HTMLエスケープ |
| **レート制限** | ✅ 実装済み | slowapi (IP/エンドポイント単位) |
| **Stripe署名検証** | ✅ 実装済み | `k_back/app/api/v1/endpoints/billing.py` |
| **監査ログ** | ✅ 実装済み | `audit_logs`テーブル |

**参考**: `md_files_design_note/design/interview/done/security_countermeasures.md`

#### ネットワーク層（Layer 3/4）

| 対策 | 実装状況 | 提供元 |
|------|---------|--------|
| **HTTPS/TLS強制** | ✅ 自動提供 | Cloud Run |
| **基本DDoS対策** | ✅ 自動提供 | Google Cloud Armor (基本レベル) |
| **ロードバランシング** | ✅ 自動提供 | Cloud Run |
| **ヘルスチェック** | ✅ 自動提供 | Cloud Run |

**参考**: `md_files_design_note/design/technology.md:791-799`

### セキュリティギャップ分析

#### 未対策のリスク

| リスク | 現状の対策 | 残存リスク | 深刻度 |
|--------|-----------|-----------|--------|
| **大規模DDoS攻撃** | 基本レベル保護のみ | アプリケーション層が停止する可能性 | 🔴 High |
| **SQLインジェクション（高度）** | ORM使用 | 生SQLやストアドプロシージャの脆弱性 | 🟡 Medium |
| **ゼロデイ攻撃** | なし | 未知の脆弱性への対応不可 | 🟡 Medium |
| **ボット攻撃** | slowapi | 分散型攻撃への対応が困難 | 🟡 Medium |
| **地理的脅威** | なし | 海外からの不正アクセス | 🟡 Medium |
| **リクエストフラッディング** | アプリレベル制限 | ネットワーク層での防御なし | 🟡 Medium |

---

## WAF導入の必要性

### ユースケース

#### 1. DDoS攻撃からの保護

**シナリオ**:
- 攻撃者が1秒間に10,000リクエストを送信
- Cloud Runインスタンスが急激にスケールアップ
- **コスト**: 数時間で数十万円の課金
- **影響**: 正規ユーザーがアクセス不可

**WAF導入後**:
- Cloud Armorがネットワーク層でブロック
- アプリケーションに到達する前に遮断
- コスト増加を防止

#### 2. SQLインジェクション攻撃

**シナリオ**:
```http
POST /api/v1/auth/login
{
  "email": "admin' OR '1'='1",
  "password": "anything"
}
```

**現状の対策**: Pydanticバリデーション
**残存リスク**: バリデーションをバイパスされた場合

**WAF導入後**:
- SQLインジェクションパターンをルールで検出
- リクエストをアプリケーションに到達させない

#### 3. ボット攻撃（アカウント列挙）

**シナリオ**:
- 攻撃者が1万個のメールアドレスでログイン試行
- 存在するアカウントを特定
- パスワードスプレー攻撃に利用

**現状の対策**: slowapi (5リクエスト/10分)
**残存リスク**: 分散IPからの攻撃

**WAF導入後**:
- ボット検出アルゴリズムで自動ブロック
- reCAPTCHAチャレンジ発動

#### 4. 地理的脅威（海外からの攻撃）

**シナリオ**:
- 日本国外からの不正アクセス試行
- 福祉事業所のターゲット顧客は日本国内のみ

**WAF導入後**:
- 日本国外のIPアドレスをブロック
- 攻撃の99%を事前に遮断

---

## 技術選定と比較

### 候補ソリューション

| WAF | メリット | デメリット | 月額コスト | 統合難易度 |
|-----|---------|-----------|-----------|-----------|
| **Google Cloud Armor** | ・Cloud Runとのネイティブ統合<br>・設定が容易<br>・GCP内で完結 | ・機能がやや限定的 | ¥3,000〜¥8,000 | ⭐ 容易 |
| **AWS WAF** | ・機能豊富<br>・きめ細かい制御 | ・GCPとの統合が複雑<br>・設定が複雑 | ¥5,000〜¥15,000 | ⭐⭐⭐ 困難 |
| **Cloudflare WAF** | ・高性能<br>・グローバルCDN統合 | ・追加のDNS設定必要<br>・Vercelとの互換性確認必要 | ¥20,000〜 | ⭐⭐ 中程度 |
| **Akamai** | ・エンタープライズ級 | ・高コスト<br>・過剰スペック | ¥100,000〜 | ⭐⭐⭐⭐ 複雑 |

### 詳細比較

#### Google Cloud Armor

**メリット**:
1. **シームレスな統合**
   - Cloud Runに直接アタッチ
   - 追加のネットワーク構成不要

2. **コスト効率**
   - 従量課金（リクエスト数ベース）
   - 小規模〜中規模に最適

3. **設定の容易さ**
   - Google Cloudコンソールで一元管理
   - 既存のIAM権限を活用

4. **基本機能の充実**
   - OWASP Top 10対策ルール（事前設定済み）
   - レート制限
   - 地理的制限
   - IP許可/拒否リスト

**デメリット**:
1. ボット対策機能が限定的（reCAPTCHAとの統合が別途必要）
2. AWS WAFと比較してカスタマイズ性が低い

**参考**: [Google Cloud Armor公式ドキュメント](https://cloud.google.com/armor/docs)

#### AWS WAF

**メリット**:
- 高度なボット対策（AWS WAF Bot Control）
- マネージドルールセットが豊富
- AWS Shieldとの統合でDDoS対策強化

**デメリット**:
- GCPとの統合に追加インフラ必要（API Gateway経由など）
- Cloud Runから直接利用不可
- 設定・運用の複雑さ

#### Cloudflare WAF

**メリット**:
- グローバルCDN統合
- 高度なボット対策
- DDoS対策が非常に強力

**デメリット**:
- DNS設定の変更が必要
- Vercel（フロントエンド）との統合確認が必要
- 月額コストが高い

---

## 推奨ソリューション

### 結論: Google Cloud Armor

**推奨理由**:

1. **技術的適合性**
   - Cloud Runとのネイティブ統合
   - 既存インフラの変更最小限
   - 設定・運用が容易

2. **コストパフォーマンス**
   - 月額¥3,000〜¥8,000（トラフィック量による）
   - 初期費用なし
   - スモールスタートに最適

3. **必要十分な機能**
   - OWASP Top 10対策
   - DDoS防御
   - レート制限
   - 地理的制限

4. **運用効率**
   - Google Cloudコンソールで一元管理
   - 既存のモニタリング（Cloud Logging）と統合

### アーキテクチャ

```
                                   インターネット
                                        ↓
                          ┌─────────────────────────┐
                          │  Google Cloud Armor     │
                          │  (WAF + DDoS Protection)│
                          └─────────────────────────┘
                                        ↓
                          ┌─────────────────────────┐
                          │  Cloud Load Balancer    │
                          │  (HTTPS ロードバランサー)│
                          └─────────────────────────┘
                                        ↓
        ┌───────────────────────────────────────────────────┐
        │              Google Cloud Run                      │
        │                                                    │
        │  ┌──────────────────────────────────────────┐    │
        │  │  FastAPI (Gunicorn + Uvicorn Worker)     │    │
        │  │  - JWT認証                                │    │
        │  │  - CSRF保護                               │    │
        │  │  - slowapi (レート制限)                    │    │
        │  └──────────────────────────────────────────┘    │
        └───────────────────────────────────────────────────┘
                                        ↓
                          ┌─────────────────────────┐
                          │  PostgreSQL (Neon)      │
                          └─────────────────────────┘
```

**多層防御アーキテクチャ**:
1. **Layer 1 (WAF)**: Cloud Armor - 悪意のあるトラフィックを遮断
2. **Layer 2 (LB)**: Cloud Load Balancer - 正規トラフィックを分散
3. **Layer 3 (App)**: FastAPI - アプリケーション層の認証・認可
4. **Layer 4 (Data)**: PostgreSQL - データベース層の保護

---

## 実装計画

### Phase 1: 基本設定（緊急）

**実装期間**: 1週間
**作業負荷**: 8時間

#### 1.1 Cloud Armorセキュリティポリシー作成

```bash
# セキュリティポリシー作成
gcloud compute security-policies create keikakun-waf-policy \
    --description "けいかくん WAFセキュリティポリシー"
```

#### 1.2 OWASP Top 10対策ルール適用

```bash
# OWASP ModSecurity Core Rule Set (事前設定ルール)
gcloud compute security-policies rules create 1000 \
    --security-policy keikakun-waf-policy \
    --expression "evaluatePreconfiguredExpr('sqli-stable')" \
    --action deny-403 \
    --description "SQLインジェクション対策"

gcloud compute security-policies rules create 1001 \
    --security-policy keikakun-waf-policy \
    --expression "evaluatePreconfiguredExpr('xss-stable')" \
    --action deny-403 \
    --description "XSS対策"

gcloud compute security-policies rules create 1002 \
    --security-policy keikakun-waf-policy \
    --expression "evaluatePreconfiguredExpr('lfi-stable')" \
    --action deny-403 \
    --description "ローカルファイルインクルージョン対策"

gcloud compute security-policies rules create 1003 \
    --security-policy keikakun-waf-policy \
    --expression "evaluatePreconfiguredExpr('rce-stable')" \
    --action deny-403 \
    --description "リモートコード実行対策"
```

#### 1.3 レート制限設定

```bash
# エンドポイント単位のレート制限
gcloud compute security-policies rules create 2000 \
    --security-policy keikakun-waf-policy \
    --expression "request.path.matches('/api/v1/auth/login')" \
    --action rate-based-ban \
    --rate-limit-threshold-count 10 \
    --rate-limit-threshold-interval-sec 60 \
    --ban-duration-sec 600 \
    --description "ログインエンドポイントのレート制限（10req/分）"

gcloud compute security-policies rules create 2001 \
    --security-policy keikakun-waf-policy \
    --expression "request.path.matches('/api/v1/billing/webhook')" \
    --action rate-based-ban \
    --rate-limit-threshold-count 100 \
    --rate-limit-threshold-interval-sec 60 \
    --ban-duration-sec 300 \
    --description "Webhookエンドポイントのレート制限（100req/分）"
```

#### 1.4 Cloud Runへのアタッチメント

```bash
# Cloud Runサービスにセキュリティポリシーを適用
gcloud run services update k-back \
    --region asia-northeast1 \
    --security-policy keikakun-waf-policy
```

**成果物**:
- ✅ WAFセキュリティポリシー適用完了
- ✅ OWASP Top 10対策ルール有効化
- ✅ レート制限設定完了

---

### Phase 2: 高度な設定（重要）

**実装期間**: 2週間
**作業負荷**: 16時間

#### 2.1 地理的制限

```bash
# 日本国外からのアクセスをブロック（管理画面のみ）
gcloud compute security-policies rules create 3000 \
    --security-policy keikakun-waf-policy \
    --expression "origin.region_code != 'JP' && request.path.matches('/admin/.*')" \
    --action deny-403 \
    --description "管理画面への日本国外アクセス拒否"
```

**例外設定**:
- API エンドポイント: 地理的制限なし（将来の国際展開を考慮）
- Stripe Webhook: IPホワイトリストで対応（後述）

#### 2.2 IPホワイトリスト（Stripe Webhook）

```bash
# Stripe WebhookのIPアドレスを許可
gcloud compute security-policies rules create 100 \
    --security-policy keikakun-waf-policy \
    --expression "request.path == '/api/v1/billing/webhook' && inIpRange(origin.ip, '54.187.174.169/32')" \
    --action allow \
    --description "Stripe Webhook IP許可（例: 54.187.174.169）"
```

**注**: Stripe公式IPレンジを定期的に更新

#### 2.3 カスタムルール（業務時間外アクセス制限）

```yaml
# 業務時間外（22時〜6時）の管理画面アクセスを制限
expression: |
  request.path.matches('/admin/.*') &&
  (int(request.time.getHours('Asia/Tokyo')) >= 22 ||
   int(request.time.getHours('Asia/Tokyo')) < 6)
action: deny-403
description: "業務時間外の管理画面アクセス制限"
```

**運用上の考慮**:
- 緊急時のアクセス手順を整備
- IPホワイトリストによる例外設定

#### 2.4 アダプティブプロテクション（推奨）

```bash
# 異常トラフィック検知時の自動ブロック
gcloud compute security-policies rules create 5000 \
    --security-policy keikakun-waf-policy \
    --expression "evaluatePreconfiguredExpr('sourceiplist-fastly')" \
    --action deny-403 \
    --description "既知の悪意あるIPからのアクセス拒否"
```

**成果物**:
- ✅ 地理的制限設定完了
- ✅ IPホワイトリスト設定完了
- ✅ カスタムルール適用完了

---

### Phase 3: モニタリング・最適化（推奨）

**実装期間**: 継続的
**作業負荷**: 月4時間

#### 3.1 ログ監視

```bash
# Cloud Armorログの確認
gcloud logging read "resource.type=http_load_balancer AND jsonPayload.enforcedSecurityPolicy.name=keikakun-waf-policy" \
    --limit 50 \
    --format json
```

**監視対象**:
- ブロックされたリクエスト数
- 攻撃パターンの分析
- 誤検知（False Positive）の検出

#### 3.2 アラート設定

```yaml
# Cloud Monitoringアラートポリシー
displayName: "WAF 高頻度ブロック検知"
conditions:
  - displayName: "1分間に100件以上のブロック"
    conditionThreshold:
      filter: |
        resource.type="http_load_balancer"
        AND jsonPayload.enforcedSecurityPolicy.outcome="DENY"
      aggregations:
        - alignmentPeriod: 60s
          perSeriesAligner: ALIGN_RATE
      comparison: COMPARISON_GT
      thresholdValue: 100
      duration: 60s
notificationChannels:
  - projects/PROJECT_ID/notificationChannels/EMAIL_CHANNEL
```

#### 3.3 定期レビュー

**月次タスク**:
- [ ] ブロックログの確認（誤検知チェック）
- [ ] ルールの最適化
- [ ] Stripe IPレンジの更新確認
- [ ] 攻撃トレンドの分析

**成果物**:
- ✅ モニタリングダッシュボード構築
- ✅ アラート通知設定完了
- ✅ 定期レビュープロセス確立

---

## コスト見積もり

### Google Cloud Armor料金体系

| 項目 | 単価 | 月間想定量 | 月額費用 |
|------|------|-----------|---------|
| **ポリシー料金** | $5/ポリシー | 1ポリシー | ¥750 |
| **ルール料金** | $1/ルール | 10ルール | ¥1,500 |
| **リクエスト処理** | $0.75/100万リクエスト | 100万リクエスト | ¥112 |
| **ログ保存** | $0.50/GB | 5GB | ¥375 |
| **合計** | - | - | **¥2,737** |

**注**: 為替レート 1 USD = ¥150 で換算

### トラフィック量による変動

| トラフィックレベル | 月間リクエスト数 | 月額コスト（概算） |
|------------------|-----------------|-------------------|
| **小規模** | 100万リクエスト | ¥2,737 |
| **中規模** | 500万リクエスト | ¥4,500 |
| **大規模** | 1,000万リクエスト | ¥7,500 |

### 費用対効果

**セキュリティインシデント1件の想定被害額**:
- データ漏洩対応費用: ¥1,000,000〜
- 信頼回復コスト: ¥5,000,000〜
- 法的対応費用: ¥500,000〜

**WAF導入コスト（年間）**: ¥32,844〜¥90,000

**ROI（投資対効果）**: インシデント1件を防げば、投資の10倍以上の価値

---

## リスクと軽減策

### 実装リスク

| リスク | 影響度 | 発生確率 | 軽減策 |
|--------|--------|---------|--------|
| **誤検知（False Positive）** | 🟡 Medium | 🟡 Medium | ・段階的なルール適用<br>・監視モードでの事前テスト<br>・ホワイトリスト設定 |
| **パフォーマンス低下** | 🟡 Medium | 🟢 Low | ・Cloud Armorは低レイテンシ（<1ms）<br>・負荷テストで事前検証 |
| **設定ミスによるサービス停止** | 🔴 High | 🟢 Low | ・ステージング環境で事前テスト<br>・段階的ロールアウト<br>・即座にロールバック可能 |
| **コスト超過** | 🟡 Medium | 🟢 Low | ・Cloud Billing Alertsで上限設定<br>・月次コストレビュー |

### 軽減策の詳細

#### 誤検知対策

**段階的ロールアウト**:
1. **Week 1**: 監視モード（`action: allow`）でルール動作確認
2. **Week 2**: ログ分析して誤検知を特定
3. **Week 3**: 誤検知をホワイトリスト化
4. **Week 4**: 本番適用（`action: deny-403`）

**例外設定例**:
```bash
# 特定のIPアドレスを常に許可（開発チーム、信頼できるパートナー）
gcloud compute security-policies rules create 10 \
    --security-policy keikakun-waf-policy \
    --expression "inIpRange(origin.ip, '203.0.113.0/24')" \
    --action allow \
    --description "開発チームIP許可"
```

#### パフォーマンス対策

**ベンチマーク**:
```bash
# WAF適用前後のレスポンスタイム比較
ab -n 1000 -c 10 https://api.keikakun.com/api/v1/health
```

**許容基準**:
- レイテンシ増加: <10ms
- スループット低下: <5%

---

## 効果測定

### KPI（重要業績評価指標）

| KPI | 目標値 | 測定方法 |
|-----|--------|---------|
| **ブロックされた攻撃数** | 月間100件以上検知 | Cloud Logging分析 |
| **誤検知率** | <1% | ブロックログのレビュー |
| **DDoS攻撃の検知・防御** | 100%防御 | インシデントレポート |
| **レイテンシ増加** | <10ms | Cloud Monitoring |
| **セキュリティスコア向上** | 8.5 → 9.5 (CVSS) | セキュリティ監査 |

### 測定ダッシュボード

```sql
-- Cloud Loggingクエリ例: ブロックされたリクエスト統計
SELECT
  jsonPayload.enforcedSecurityPolicy.name AS policy_name,
  jsonPayload.enforcedSecurityPolicy.outcome AS outcome,
  COUNT(*) AS request_count,
  TIMESTAMP_TRUNC(timestamp, HOUR) AS hour
FROM
  `PROJECT_ID.DATASET.http_load_balancer`
WHERE
  jsonPayload.enforcedSecurityPolicy.outcome = 'DENY'
  AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
GROUP BY
  policy_name, outcome, hour
ORDER BY
  hour DESC
```

### 月次レポート内容

1. **セキュリティメトリクス**
   - ブロックされた攻撃の種類・件数
   - 攻撃元IPの地理的分布
   - 最も狙われたエンドポイント

2. **パフォーマンスメトリクス**
   - 平均レイテンシ
   - スループット
   - 誤検知率

3. **コストメトリクス**
   - 月額WAFコスト
   - コストパフォーマンス分析

4. **改善提案**
   - ルールの最適化案
   - 新たな脅威への対応策

---

## 次のステップ

### 承認プロセス

1. **提案レビュー**: 2026年2月7日まで
2. **承認決定**: 2026年2月10日まで
3. **Phase 1実装開始**: 2026年2月12日

### 必要なリソース

| 役割 | 作業内容 | 工数 |
|------|---------|------|
| **インフラエンジニア** | Cloud Armor設定・デプロイ | 8時間 |
| **バックエンドエンジニア** | アプリケーション層の調整 | 4時間 |
| **QAエンジニア** | テスト・検証 | 8時間 |

### 参考資料

- [Google Cloud Armor公式ドキュメント](https://cloud.google.com/armor/docs)
- [OWASP Top 10 - 2021](https://owasp.org/www-project-top-ten/)
- [Google Cloud セキュリティベストプラクティス](https://cloud.google.com/security/best-practices)
- けいかくん既存セキュリティドキュメント:
  - `md_files_design_note/design/interview/done/security_countermeasures.md`
  - `md_files_design_note/design/technology.md`

---

## 付録

### A. Cloud Armorルール一覧（Phase 1）

| 優先度 | ルール名 | 式 | アクション | 説明 |
|--------|---------|-----|-----------|------|
| 100 | stripe-webhook-allow | `request.path == '/api/v1/billing/webhook' && inIpRange(...)` | allow | Stripe Webhook許可 |
| 1000 | sqli-protection | `evaluatePreconfiguredExpr('sqli-stable')` | deny-403 | SQLインジェクション対策 |
| 1001 | xss-protection | `evaluatePreconfiguredExpr('xss-stable')` | deny-403 | XSS対策 |
| 1002 | lfi-protection | `evaluatePreconfiguredExpr('lfi-stable')` | deny-403 | LFI対策 |
| 1003 | rce-protection | `evaluatePreconfiguredExpr('rce-stable')` | deny-403 | RCE対策 |
| 2000 | login-rate-limit | `request.path.matches('/api/v1/auth/login')` | rate-based-ban | ログインレート制限 |
| 2001 | webhook-rate-limit | `request.path.matches('/api/v1/billing/webhook')` | rate-based-ban | Webhookレート制限 |

### B. トラブルシューティングガイド

#### 問題: 正規ユーザーがブロックされる

**症状**:
- 403 Forbiddenエラー
- 特定のユーザーからの報告

**診断手順**:
```bash
# 1. ブロックログを確認
gcloud logging read "jsonPayload.enforcedSecurityPolicy.outcome=DENY AND jsonPayload.remoteIp='USER_IP'" \
    --limit 10 \
    --format json

# 2. どのルールでブロックされたか確認
# 出力の jsonPayload.enforcedSecurityPolicy.configuredAction を確認
```

**対処法**:
```bash
# 一時的にIPを許可リストに追加
gcloud compute security-policies rules create 50 \
    --security-policy keikakun-waf-policy \
    --expression "origin.ip == 'USER_IP'" \
    --action allow \
    --description "一時的な例外: ユーザーXXX"
```

#### 問題: パフォーマンス低下

**症状**:
- レスポンスタイムが通常より遅い
- タイムアウトエラー

**診断手順**:
```bash
# Cloud Monitoringでレイテンシを確認
gcloud monitoring time-series list \
    --filter='metric.type="loadbalancing.googleapis.com/https/request_latencies"' \
    --format=json
```

**対処法**:
1. ルール数を削減（最適化）
2. 式の簡略化
3. Google Cloudサポートに連絡

---

**提案書バージョン**: 1.0
**次回レビュー日**: 2026年3月3日
**文責**: Claude Sonnet 4.5
