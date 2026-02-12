# けいかくん - WAF実装ガイド（Google Cloud Armor）

**作成日**: 2026-02-03
**対象環境**: 本番環境（Google Cloud Run）
**前提条件**: waf_implementation_proposal.md承認済み

---

## 📋 目次

1. [事前準備](#事前準備)
2. [Phase 1: 基本設定](#phase-1-基本設定)
3. [Phase 2: 高度な設定](#phase-2-高度な設定)
4. [Phase 3: モニタリング設定](#phase-3-モニタリング設定)
5. [検証手順](#検証手順)
6. [ロールバック手順](#ロールバック手順)
7. [運用手順](#運用手順)

---

## 事前準備

### 必要な権限

```bash
# 必要なIAMロール
# - roles/compute.securityAdmin
# - roles/run.admin
# - roles/logging.viewer

# 現在のロールを確認
gcloud projects get-iam-policy PROJECT_ID \
    --flatten="bindings[].members" \
    --filter="bindings.members:user:YOUR_EMAIL"
```

### 環境変数設定

```bash
# 環境変数をエクスポート
export PROJECT_ID="your-gcp-project-id"
export REGION="asia-northeast1"
export SERVICE_NAME="k-back"
export POLICY_NAME="keikakun-waf-policy"
```

### バックアップ

```bash
# 現在のCloud Run設定をバックアップ
gcloud run services describe $SERVICE_NAME \
    --region $REGION \
    --format yaml > backup_cloud_run_config_$(date +%Y%m%d).yaml

# 現在のセキュリティポリシー一覧を確認
gcloud compute security-policies list
```

---

## Phase 1: 基本設定

### ステップ1.1: セキュリティポリシー作成

```bash
# セキュリティポリシーを作成
gcloud compute security-policies create $POLICY_NAME \
    --description "けいかくん WAFセキュリティポリシー" \
    --project $PROJECT_ID

# 作成確認
gcloud compute security-policies describe $POLICY_NAME
```

**期待される出力**:
```yaml
name: keikakun-waf-policy
description: けいかくん WAFセキュリティポリシー
fingerprint: XXXXXXXXXXXX
selfLink: https://www.googleapis.com/compute/v1/projects/PROJECT_ID/global/securityPolicies/keikakun-waf-policy
```

---

### ステップ1.2: デフォルトルール設定

```bash
# デフォルトルールを "allow" に設定（段階的に厳格化）
gcloud compute security-policies rules update 2147483647 \
    --security-policy $POLICY_NAME \
    --action allow \
    --description "デフォルト: すべて許可（Phase 1）"
```

**注**: 優先度 2147483647 は最低優先度（デフォルトルール）

---

### ステップ1.3: OWASP Top 10対策ルール

#### 1.3.1 SQLインジェクション対策

```bash
gcloud compute security-policies rules create 1000 \
    --security-policy $POLICY_NAME \
    --expression "evaluatePreconfiguredExpr('sqli-v33-stable')" \
    --action "deny-403" \
    --description "SQLインジェクション対策"
```

**検証**:
```bash
# 悪意のあるSQLインジェクションパターンをテスト
curl -X POST https://api.keikakun.com/api/v1/auth/login \
     -H "Content-Type: application/json" \
     -d '{"email":"admin@example.com OR 1=1--","password":"test"}'

# 期待される応答: 403 Forbidden
```

#### 1.3.2 XSS対策

```bash
gcloud compute security-policies rules create 1001 \
    --security-policy $POLICY_NAME \
    --expression "evaluatePreconfiguredExpr('xss-v33-stable')" \
    --action "deny-403" \
    --description "XSS対策"
```

**検証**:
```bash
# XSSパターンをテスト
curl -X GET "https://api.keikakun.com/api/v1/search?q=<script>alert('XSS')</script>"

# 期待される応答: 403 Forbidden
```

#### 1.3.3 ローカルファイルインクルージョン対策

```bash
gcloud compute security-policies rules create 1002 \
    --security-policy $POLICY_NAME \
    --expression "evaluatePreconfiguredExpr('lfi-v33-stable')" \
    --action "deny-403" \
    --description "ローカルファイルインクルージョン対策"
```

#### 1.3.4 リモートコード実行対策

```bash
gcloud compute security-policies rules create 1003 \
    --security-policy $POLICY_NAME \
    --expression "evaluatePreconfiguredExpr('rce-v33-stable')" \
    --action "deny-403" \
    --description "リモートコード実行対策"
```

#### 1.3.5 リモートファイルインクルージョン対策

```bash
gcloud compute security-policies rules create 1004 \
    --security-policy $POLICY_NAME \
    --expression "evaluatePreconfiguredExpr('rfi-v33-stable')" \
    --action "deny-403" \
    --description "リモートファイルインクルージョン対策"
```

---

### ステップ1.4: レート制限設定

#### 1.4.1 ログインエンドポイント

```bash
# ログインエンドポイントのレート制限
# 10リクエスト/分、超過時は10分間BANgcloud compute security-policies rules create 2000 \
    --security-policy $POLICY_NAME \
    --expression "request.path.matches('/api/v1/auth/login')" \
    --action "rate-based-ban" \
    --rate-limit-threshold-count 10 \
    --rate-limit-threshold-interval-sec 60 \
    --ban-duration-sec 600 \
    --conform-action "allow" \
    --exceed-action "deny-429" \
    --enforce-on-key "IP" \
    --description "ログインエンドポイントのレート制限（10req/分）"
```

**検証**:
```bash
# レート制限をテスト（11回連続アクセス）
for i in {1..11}; do
  echo "リクエスト $i"
  curl -X POST https://api.keikakun.com/api/v1/auth/login \
       -H "Content-Type: application/json" \
       -d '{"email":"test@example.com","password":"test123"}'
  sleep 1
done

# 11回目以降は 429 Too Many Requests が返ることを確認
```

#### 1.4.2 パスワードリセットエンドポイント

```bash
gcloud compute security-policies rules create 2001 \
    --security-policy $POLICY_NAME \
    --expression "request.path.matches('/api/v1/auth/forgot-password')" \
    --action "rate-based-ban" \
    --rate-limit-threshold-count 5 \
    --rate-limit-threshold-interval-sec 600 \
    --ban-duration-sec 1800 \
    --conform-action "allow" \
    --exceed-action "deny-429" \
    --enforce-on-key "IP" \
    --description "パスワードリセットのレート制限（5req/10分）"
```

#### 1.4.3 Webhookエンドポイント

```bash
gcloud compute security-policies rules create 2002 \
    --security-policy $POLICY_NAME \
    --expression "request.path.matches('/api/v1/billing/webhook')" \
    --action "rate-based-ban" \
    --rate-limit-threshold-count 100 \
    --rate-limit-threshold-interval-sec 60 \
    --ban-duration-sec 300 \
    --conform-action "allow" \
    --exceed-action "deny-429" \
    --enforce-on-key "IP" \
    --description "Webhookエンドポイントのレート制限（100req/分）"
```

---

### ステップ1.5: Cloud Runへのアタッチ

```bash
# Cloud RunサービスにCloud Armorセキュリティポリシーを適用
gcloud run services update $SERVICE_NAME \
    --region $REGION \
    --ingress all \
    --cpu-throttling \
    --args="--security-policy=$POLICY_NAME"

# 注: 2024年12月時点でCloud RunへのCloud Armor直接適用は制限あり
# 代替方法: Cloud Load Balancerを経由する必要がある場合あり
```

**重要**: Cloud RunでCloud Armorを使用するには、以下の構成が必要な場合があります：

```bash
# 1. Cloud Load Balancer (外部HTTPS LB) を作成
# 2. Cloud Runをバックエンドサービスとして設定
# 3. Cloud ArmorをLoad Balancerに適用

# 詳細は以下のドキュメント参照:
# https://cloud.google.com/armor/docs/integrating-cloud-armor
```

---

### ステップ1.6: 設定確認

```bash
# すべてのルールを確認
gcloud compute security-policies describe $POLICY_NAME

# ルール一覧を表形式で表示
gcloud compute security-policies rules list $POLICY_NAME \
    --format="table(priority, action, match.expr, description)"
```

**期待される出力**:
```
PRIORITY  ACTION          EXPR                                                    DESCRIPTION
1000      deny-403        evaluatePreconfiguredExpr('sqli-v33-stable')           SQLインジェクション対策
1001      deny-403        evaluatePreconfiguredExpr('xss-v33-stable')            XSS対策
1002      deny-403        evaluatePreconfiguredExpr('lfi-v33-stable')            ローカルファイルインクルージョン対策
1003      deny-403        evaluatePreconfiguredExpr('rce-v33-stable')            リモートコード実行対策
1004      deny-403        evaluatePreconfiguredExpr('rfi-v33-stable')            リモートファイルインクルージョン対策
2000      rate-based-ban  request.path.matches('/api/v1/auth/login')             ログインエンドポイントのレート制限
2001      rate-based-ban  request.path.matches('/api/v1/auth/forgot-password')   パスワードリセットのレート制限
2002      rate-based-ban  request.path.matches('/api/v1/billing/webhook')        Webhookエンドポイントのレート制限
2147483647 allow          true                                                    デフォルト: すべて許可
```

---

## Phase 2: 高度な設定

### ステップ2.1: 地理的制限

#### 2.1.1 管理画面への国外アクセス拒否

```bash
gcloud compute security-policies rules create 3000 \
    --security-policy $POLICY_NAME \
    --expression "origin.region_code != 'JP' && request.path.matches('/admin/.*')" \
    --action "deny-403" \
    --description "管理画面への日本国外アクセス拒否"
```

**検証**:
```bash
# VPNで海外IPからアクセスをシミュレート
# または curl --proxy プロキシ経由でテスト

curl -X GET https://api.keikakun.com/admin/dashboard \
     --proxy socks5://海外プロキシIP:PORT

# 期待される応答: 403 Forbidden
```

#### 2.1.2 例外設定（特定の国からのアクセス許可）

```bash
# 例: シンガポール（SG）からのアクセスを許可
gcloud compute security-policies rules create 3001 \
    --security-policy $POLICY_NAME \
    --expression "origin.region_code == 'SG' && request.path.matches('/admin/.*')" \
    --action "allow" \
    --description "シンガポールからの管理画面アクセス許可（例外）"
```

---

### ステップ2.2: IPホワイトリスト

#### 2.2.1 Stripe Webhook IP許可

```bash
# Stripe公式IPアドレス（2026年2月時点）
# 最新のIPレンジは https://stripe.com/docs/ips で確認

# IPレンジ1
gcloud compute security-policies rules create 100 \
    --security-policy $POLICY_NAME \
    --expression "request.path == '/api/v1/billing/webhook' && inIpRange(origin.ip, '3.18.12.63/32')" \
    --action "allow" \
    --description "Stripe Webhook IP許可 (1/4)"

# IPレンジ2
gcloud compute security-policies rules create 101 \
    --security-policy $POLICY_NAME \
    --expression "request.path == '/api/v1/billing/webhook' && inIpRange(origin.ip, '3.130.192.231/32')" \
    --action "allow" \
    --description "Stripe Webhook IP許可 (2/4)"

# IPレンジ3
gcloud compute security-policies rules create 102 \
    --security-policy $POLICY_NAME \
    --expression "request.path == '/api/v1/billing/webhook' && inIpRange(origin.ip, '13.235.14.237/32')" \
    --action "allow" \
    --description "Stripe Webhook IP許可 (3/4)"

# IPレンジ4
gcloud compute security-policies rules create 103 \
    --security-policy $POLICY_NAME \
    --expression "request.path == '/api/v1/billing/webhook' && inIpRange(origin.ip, '13.235.122.149/32')" \
    --action "allow" \
    --description "Stripe Webhook IP許可 (4/4)"
```

**注意**: Stripe IPレンジは変更される可能性があるため、定期的に確認が必要

#### 2.2.2 開発チームIP許可

```bash
# 開発チームの固定IPを許可（例）
gcloud compute security-policies rules create 110 \
    --security-policy $POLICY_NAME \
    --expression "inIpRange(origin.ip, '203.0.113.0/24')" \
    --action "allow" \
    --description "開発チームIP許可"
```

---

### ステップ2.3: カスタムルール

#### 2.3.1 業務時間外アクセス制限

```bash
# 業務時間外（22時〜6時）の管理画面アクセスを制限
gcloud compute security-policies rules create 4000 \
    --security-policy $POLICY_NAME \
    --expression "request.path.matches('/admin/.*') && (int(request.time.getHours('Asia/Tokyo')) >= 22 || int(request.time.getHours('Asia/Tokyo')) < 6)" \
    --action "deny-403" \
    --description "業務時間外の管理画面アクセス制限"
```

**例外設定**:
```bash
# 特定のIPは業務時間外でもアクセス可能（緊急対応用）
gcloud compute security-policies rules create 4001 \
    --security-policy $POLICY_NAME \
    --expression "inIpRange(origin.ip, 'EMERGENCY_IP') && request.path.matches('/admin/.*')" \
    --action "allow" \
    --description "緊急対応用IP（業務時間外も許可）"
```

#### 2.3.2 User-Agent制限

```bash
# 空のUser-Agentをブロック（ボット対策）
gcloud compute security-policies rules create 5000 \
    --security-policy $POLICY_NAME \
    --expression "!has(request.headers['user-agent'])" \
    --action "deny-403" \
    --description "User-Agentなしのリクエストをブロック"
```

#### 2.3.3 特定パスへのPOST制限

```bash
# GETのみ許可すべきエンドポイントへのPOSTをブロック
gcloud compute security-policies rules create 5001 \
    --security-policy $POLICY_NAME \
    --expression "request.method == 'POST' && request.path.matches('/api/v1/health')" \
    --action "deny-405" \
    --description "ヘルスチェックエンドポイントへのPOST禁止"
```

---

## Phase 3: モニタリング設定

### ステップ3.1: Cloud Loggingフィルター設定

```bash
# WAFログを確認するためのフィルター
gcloud logging read \
    "resource.type=http_load_balancer
     AND jsonPayload.enforcedSecurityPolicy.name=$POLICY_NAME" \
    --limit 10 \
    --format json
```

**保存済みクエリの作成**:
1. Cloud Consoleのログエクスプローラーを開く
2. 上記フィルターを入力
3. 「クエリを保存」→「WAF ブロックログ」として保存

---

### ステップ3.2: Cloud Monitoringアラート

#### 3.2.1 高頻度ブロック検知

```yaml
# alert_waf_high_block_rate.yaml
displayName: "WAF 高頻度ブロック検知"
combiner: OR
conditions:
  - displayName: "1分間に100件以上のブロック"
    conditionThreshold:
      filter: |
        resource.type="http_load_balancer"
        AND jsonPayload.enforcedSecurityPolicy.name="keikakun-waf-policy"
        AND jsonPayload.enforcedSecurityPolicy.outcome="DENY"
      aggregations:
        - alignmentPeriod: 60s
          perSeriesAligner: ALIGN_RATE
          crossSeriesReducer: REDUCE_SUM
      comparison: COMPARISON_GT
      thresholdValue: 100
      duration: 60s
notificationChannels:
  - projects/PROJECT_ID/notificationChannels/EMAIL_CHANNEL
```

**適用**:
```bash
gcloud alpha monitoring policies create --policy-from-file=alert_waf_high_block_rate.yaml
```

#### 3.2.2 誤検知検知（正規ユーザーのブロック）

```yaml
# alert_waf_false_positive.yaml
displayName: "WAF 誤検知の可能性"
combiner: OR
conditions:
  - displayName: "認証済みユーザーのブロック"
    conditionThreshold:
      filter: |
        resource.type="http_load_balancer"
        AND jsonPayload.enforcedSecurityPolicy.outcome="DENY"
        AND jsonPayload.statusDetails="authenticated_user"
      aggregations:
        - alignmentPeriod: 300s
          perSeriesAligner: ALIGN_RATE
      comparison: COMPARISON_GT
      thresholdValue: 1
      duration: 300s
notificationChannels:
  - projects/PROJECT_ID/notificationChannels/EMAIL_CHANNEL
```

---

### ステップ3.3: ダッシュボード作成

```json
{
  "displayName": "けいかくん WAF セキュリティダッシュボード",
  "mosaicLayout": {
    "columns": 12,
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "ブロックされたリクエスト数（時間別）",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"http_load_balancer\" AND jsonPayload.enforcedSecurityPolicy.outcome=\"DENY\"",
                    "aggregation": {
                      "alignmentPeriod": "3600s",
                      "perSeriesAligner": "ALIGN_RATE"
                    }
                  }
                }
              }
            ]
          }
        }
      },
      {
        "xPos": 6,
        "width": 6,
        "height": 4,
        "widget": {
          "title": "攻撃タイプ別分布",
          "pieChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"http_load_balancer\" AND jsonPayload.enforcedSecurityPolicy.outcome=\"DENY\"",
                    "aggregation": {
                      "alignmentPeriod": "86400s",
                      "perSeriesAligner": "ALIGN_SUM",
                      "groupByFields": ["jsonPayload.enforcedSecurityPolicy.name"]
                    }
                  }
                }
              }
            ]
          }
        }
      }
    ]
  }
}
```

**適用**:
```bash
gcloud monitoring dashboards create --config-from-file=waf_dashboard.json
```

---

## 検証手順

### 検証チェックリスト

- [ ] SQLインジェクション対策が機能している
- [ ] XSS対策が機能している
- [ ] レート制限が機能している
- [ ] 地理的制限が機能している（該当する場合）
- [ ] 正規ユーザーがブロックされていない（誤検知なし）
- [ ] パフォーマンスへの影響が許容範囲内（<10ms）

### 自動テストスクリプト

```bash
#!/bin/bash
# waf_validation_test.sh

set -e

BASE_URL="https://api.keikakun.com"

echo "=== WAF検証テスト開始 ==="

# テスト1: SQLインジェクション
echo "[テスト1] SQLインジェクション対策"
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$BASE_URL/api/v1/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"admin@example.com OR 1=1--","password":"test"}')

if [ "$RESPONSE" -eq 403 ]; then
    echo "✅ PASS: SQLインジェクションがブロックされました"
else
    echo "❌ FAIL: SQLインジェクションがブロックされていません (HTTP $RESPONSE)"
    exit 1
fi

# テスト2: XSS
echo "[テスト2] XSS対策"
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X GET "$BASE_URL/api/v1/search?q=<script>alert('XSS')</script>")

if [ "$RESPONSE" -eq 403 ]; then
    echo "✅ PASS: XSSがブロックされました"
else
    echo "❌ FAIL: XSSがブロックされていません (HTTP $RESPONSE)"
    exit 1
fi

# テスト3: レート制限
echo "[テスト3] レート制限"
SUCCESS_COUNT=0
for i in {1..12}; do
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "$BASE_URL/api/v1/auth/login" \
        -H "Content-Type: application/json" \
        -d '{"email":"test@example.com","password":"test"}')

    if [ "$RESPONSE" -eq 429 ]; then
        echo "✅ PASS: ${i}回目のリクエストでレート制限が発動しました"
        SUCCESS_COUNT=1
        break
    fi
    sleep 1
done

if [ "$SUCCESS_COUNT" -eq 0 ]; then
    echo "❌ FAIL: レート制限が機能していません"
    exit 1
fi

# テスト4: 正規リクエストの疎通確認
echo "[テスト4] 正規リクエストの疎通確認"
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X GET "$BASE_URL/api/v1/health")

if [ "$RESPONSE" -eq 200 ]; then
    echo "✅ PASS: 正規リクエストが正常に処理されました"
else
    echo "❌ FAIL: 正規リクエストがブロックされています (HTTP $RESPONSE)"
    exit 1
fi

echo "=== すべてのテストが成功しました ==="
```

**実行**:
```bash
chmod +x waf_validation_test.sh
./waf_validation_test.sh
```

---

## ロールバック手順

### 緊急時のロールバック

```bash
# Cloud RunからCloud Armorポリシーを解除
gcloud run services update $SERVICE_NAME \
    --region $REGION \
    --clear-security-policy

# セキュリティポリシーを削除
gcloud compute security-policies delete $POLICY_NAME

# バックアップから復元
gcloud run services replace backup_cloud_run_config_YYYYMMDD.yaml \
    --region $REGION
```

### 段階的なロールバック

```bash
# 特定のルールのみを無効化
gcloud compute security-policies rules delete RULE_PRIORITY \
    --security-policy $POLICY_NAME

# または、ルールのアクションを "allow" に変更
gcloud compute security-policies rules update RULE_PRIORITY \
    --security-policy $POLICY_NAME \
    --action allow
```

---

## 運用手順

### 月次メンテナンス

```bash
#!/bin/bash
# waf_monthly_maintenance.sh

echo "=== WAF月次メンテナンス ==="

# 1. ブロックログの確認（過去30日間）
echo "[1] ブロックログ分析"
gcloud logging read \
    "resource.type=http_load_balancer
     AND jsonPayload.enforcedSecurityPolicy.outcome=DENY
     AND timestamp >= \"$(date -d '30 days ago' --iso-8601)T00:00:00Z\"" \
    --limit 1000 \
    --format json > waf_blocked_requests_$(date +%Y%m).json

# 2. 誤検知の確認
echo "[2] 誤検知確認"
# ログファイルを手動レビュー

# 3. Stripe IPレンジの更新確認
echo "[3] Stripe IPレンジ確認"
curl -s https://stripe.com/files/ips/ips_webhooks.json | jq .

# 4. ルールの最適化
echo "[4] ルール一覧出力"
gcloud compute security-policies rules list $POLICY_NAME \
    --format="table(priority, action, match.expr, description)" \
    > waf_rules_$(date +%Y%m).txt

echo "=== メンテナンス完了 ==="
```

### インシデント対応

```bash
# 攻撃元IPを緊急ブロック
gcloud compute security-policies rules create 9999 \
    --security-policy $POLICY_NAME \
    --expression "origin.ip == 'ATTACK_IP'" \
    --action "deny-403" \
    --description "緊急ブロック: $(date +%Y-%m-%d)"
```

---

## トラブルシューティング

### よくある問題

#### 問題1: ルールが機能しない

**症状**: ルールを追加したが、攻撃がブロックされない

**原因**: 優先度の設定ミス

**解決策**:
```bash
# ルールの優先度を確認
gcloud compute security-policies rules list $POLICY_NAME

# より高い優先度（小さい数値）に変更
gcloud compute security-policies rules update PRIORITY \
    --security-policy $POLICY_NAME \
    --new-priority 100
```

#### 問題2: 正規ユーザーがブロックされる

**症状**: 403エラーが多数報告される

**原因**: ルールの式が広すぎる

**解決策**:
```bash
# 一時的にルールを無効化
gcloud compute security-policies rules update PRIORITY \
    --security-policy $POLICY_NAME \
    --action allow

# ログを分析して原因特定
gcloud logging read "jsonPayload.enforcedSecurityPolicy.outcome=DENY" \
    --limit 50 \
    --format json

# ホワイトリストで例外追加
gcloud compute security-policies rules create 50 \
    --security-policy $POLICY_NAME \
    --expression "origin.ip == 'USER_IP'" \
    --action allow
```

---

## 参考資料

- [Google Cloud Armor公式ドキュメント](https://cloud.google.com/armor/docs)
- [Cloud Armor 式言語リファレンス](https://cloud.google.com/armor/docs/rules-language-reference)
- [事前設定ルール一覧](https://cloud.google.com/armor/docs/waf-rules)
- けいかくん関連ドキュメント:
  - `waf_implementation_proposal.md` (提案書)
  - `md_files_design_note/design/technology.md` (アーキテクチャ)

---

**実装ガイドバージョン**: 1.0
**最終更新日**: 2026-02-03
**管理者**: Claude Sonnet 4.5
