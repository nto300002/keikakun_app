# Stripe税務登録設定ガイド - 日本での消費税徴収

## 概要

このドキュメントでは、Keikakun APIにおけるStripe Tax（日本の消費税）の設定について、ビジネス審査への影響と実装タイミングを解説します。

**対象サービス**: Keikakun Pro Plan（月額6,000円）
**対象地域**: 日本国内
**ビジネスモデル**: BtoB SaaS（福祉事業所向け）
**最終更新**: 2025-12-29

---

## 1. 日本の消費税登録要件

### 1.1 登録が必要になる条件

Stripeによると、以下のいずれかの条件を満たす場合に日本での税務登録が必要になります:

| 条件 | 詳細 | Keikakun該当 |
|-----|------|------------|
| **課税対象売上額（基準期間）** | 前暦年の最初の6ヶ月間で1,000万円超 | ⚠️ **要確認** |
| **課税対象売上額（指定期間）** | 前々年で1,000万円超 | ⚠️ **要確認** |

**基準期間**:
- 個人事業主: 前暦年の最初の6ヶ月間
- 法人: 会計年度の最初の6ヶ月間

### 1.2 Keikakun の場合の試算

**月額6,000円プランの場合**:

| 契約数 | 月間売上（税抜） | 年間売上（税抜） | 登録要否 |
|-------|---------------|---------------|---------|
| 50件 | 30万円 | 360万円 | ❌ 不要 |
| 100件 | 60万円 | 720万円 | ❌ 不要 |
| 150件 | 90万円 | 1,080万円 | ⚠️ **要確認** |
| 200件 | 120万円 | 1,440万円 | ✅ **必要** |

**結論**:
- **サービス開始直後**: 登録不要
- **月間契約数が150件を超えた場合**: 税務登録の検討が必要
- **月間契約数が200件を超えた場合**: 税務登録が必要

---

## 2. Stripeビジネス審査への影響

### 2.1 税務登録設定の有無による審査への影響

| 項目 | 税務登録なし | 税務登録あり | 審査への影響 |
|-----|------------|------------|------------|
| **Stripe審査** | 基本的な審査のみ | 税務コンプライアンス審査が追加 | ⚠️ **審査項目増加** |
| **審査期間** | 通常1-2営業日 | 2-5営業日 | ⚠️ **若干延長** |
| **必要書類** | 基本情報のみ | 税務登録番号、事業所所在地証明 | ⚠️ **書類増加** |
| **承認難易度** | 標準 | やや高い（税務コンプライアンス確認） | ⚠️ **若干上昇** |

### 2.2 税務登録を「しない」場合の影響

**メリット**:
- ✅ 審査がシンプル（基本情報のみで承認）
- ✅ 審査期間が短い（1-2営業日）
- ✅ 初期導入が容易

**デメリット**:
- ❌ 消費税を自動徴収できない（手動対応が必要）
- ❌ 売上が1,000万円を超えた場合、後から設定変更が必要
- ❌ 税務処理の自動化ができない

### 2.3 税務登録を「する」場合の影響

**メリット**:
- ✅ 消費税を自動徴収・納税できる
- ✅ 税務処理の自動化（Stripe Taxが計算）
- ✅ 将来的なスケールに対応可能
- ✅ コンプライアンス面で安心

**デメリット**:
- ❌ 審査項目が増加（税務登録番号の確認等）
- ❌ 審査期間が若干長くなる（2-5営業日）
- ❌ 初期設定が複雑

---

## 3. 推奨実装タイミング

### 3.1 フェーズ別の推奨アプローチ

#### フェーズ1: サービスローンチ直後（契約数 0-50件）

**推奨**: **税務登録なし**

**理由**:
- 売上が1,000万円を大きく下回る
- 審査の簡素化でリリースを早められる
- 初期段階では手動での税務処理でも対応可能

**実装**:
```python
# Checkout Session作成時
session = stripe.checkout.Session.create(
    customer=customer_id,
    line_items=[{
        'price': STRIPE_PRICE_ID,  # 税込6,600円として設定
        'quantity': 1,
    }],
    mode='subscription',
    # 税務登録なし（価格に消費税を含める）
)
```

**価格設定**:
- Stripe Price: **6,600円/月**（税込）
- 内訳: 本体価格6,000円 + 消費税600円
- 表示: 「月額6,600円（税込）」

---

#### フェーズ2: 成長期（契約数 50-150件）

**推奨**: **売上を監視しながら準備**

**理由**:
- 年間売上が720万円〜1,080万円になる
- 1,000万円のしきい値に近づく
- 税務登録の準備期間が必要

**実装準備**:
1. 税理士に相談して税務登録番号を取得
2. Stripe Taxの設定を検討
3. 価格表示を税抜表示に変更する準備

---

#### フェーズ3: 拡大期（契約数 150件超）

**推奨**: **税務登録を実施**

**理由**:
- 年間売上が1,000万円を超える可能性が高い
- 消費税の自動徴収・納税が効率的
- コンプライアンスリスクの低減

**実装**:
```python
# Stripe Tax有効化後のCheckout Session作成
session = stripe.checkout.Session.create(
    customer=customer_id,
    line_items=[{
        'price': STRIPE_PRICE_ID,  # 税抜6,000円として設定
        'quantity': 1,
        'tax_rates': [TAX_RATE_ID],  # 消費税10%
    }],
    mode='subscription',
    automatic_tax={'enabled': True},  # 自動税計算
)
```

**価格設定変更**:
- Stripe Price: **6,000円/月**（税抜）
- 消費税: 自動計算（600円）
- 表示: 「月額6,000円（税抜）+ 消費税10%」

---

## 4. 実装ステップ（税務登録する場合）

### 4.1 事前準備

1. **税理士への相談**
   - 適格請求書発行事業者登録の必要性を確認
   - 消費税の申告方法を決定
   - 税務登録番号（インボイス登録番号）を取得

2. **Stripeダッシュボードで税務設定**
   - Stripe Dashboard > Settings > Tax settings
   - 「日本」を追加
   - 税務登録番号を入力
   - 適格請求書発行事業者番号（T + 13桁）を登録

3. **Tax Rateの作成**
   ```bash
   # Stripe CLIまたはAPIで税率作成
   stripe tax_rates create \
     --display_name="消費税" \
     --description="日本の消費税（10%）" \
     --jurisdiction="JP" \
     --percentage=10 \
     --inclusive=false
   ```

### 4.2 価格設定の変更

**既存の税込価格から税抜価格への移行**:

1. **新しいPriceを作成**（税抜6,000円）
   ```bash
   stripe prices create \
     --unit-amount=6000 \
     --currency=jpy \
     --recurring[interval]=month \
     --product=PRODUCT_ID \
     --tax-behavior=exclusive  # 税抜価格
   ```

2. **既存顧客の移行計画**
   - 既存顧客: 税込6,600円のまま（移行不要）
   - 新規顧客: 税抜6,000円 + 消費税10% = 6,600円

### 4.3 コード実装

**app/services/billing_service.py** を修正:

```python
async def create_checkout_session(
    self,
    db: AsyncSession,
    office_id: UUID,
    success_url: str,
    cancel_url: str
) -> str:
    # Billingレコード取得
    billing = await crud.billing.get_by_office_id(db=db, office_id=office_id)

    # Checkout Session作成
    session = stripe.checkout.Session.create(
        customer=billing.stripe_customer_id,
        line_items=[{
            'price': settings.STRIPE_PRICE_ID,
            'quantity': 1,
        }],
        mode='subscription',
        success_url=success_url,
        cancel_url=cancel_url,
        # Stripe Tax有効化
        automatic_tax={'enabled': True},  # 自動税計算
        customer_update={
            'address': 'auto',  # 住所を自動更新
        },
    )

    return session.url
```

### 4.4 環境変数の追加

**production_environment_variables.md** に追加:

```bash
# Stripe Tax設定（税務登録後のみ必要）
STRIPE_TAX_ENABLED="True"
STRIPE_TAX_RATE_ID="txr_xxxxx"  # 消費税10%のTax Rate ID
```

---

## 5. BtoB取引における注意点

### 5.1 適格請求書（インボイス）制度

**2023年10月1日以降の日本の制度**:

| 顧客タイプ | 適格請求書必要 | 消費税徴収 | 備考 |
|-----------|--------------|----------|------|
| 適格請求書発行事業者 | ✅ 必要 | ✅ 徴収 | 税務登録番号を記載 |
| 免税事業者 | ❌ 不要 | ✅ 徴収 | 簡易課税で処理 |
| 個人事業主（小規模） | ⚠️ ケースバイケース | ✅ 徴収 | 顧客の登録状況による |

**Keikakun の場合**:
- 福祉事業所は通常、適格請求書発行事業者
- Stripe Taxは自動的に適格請求書を生成
- 顧客の税務登録番号を収集する必要はない（Stripeが処理）

### 5.2 Stripe Invoiceの自動生成

Stripe Taxを有効化すると:
- ✅ 適格請求書フォーマットで自動生成
- ✅ 税務登録番号（T番号）が自動記載
- ✅ 消費税の内訳が明記される
- ✅ PDFダウンロード可能

---

## 6. 推奨アクション

### 6.1 現段階（サービスローンチ前）

**推奨**: **税務登録なしでスタート**

**理由**:
1. ✅ 初期段階では売上が1,000万円を大きく下回る
2. ✅ Stripe審査を簡素化し、リリースを早められる
3. ✅ 税込価格（6,600円/月）で設定すれば顧客への影響なし
4. ✅ 将来的な移行も可能（税抜価格への変更）

**実装**:
- Stripe Priceを**税込6,600円/月**で作成
- `tax_behavior=inclusive`（税込価格）
- Checkout Sessionで`automatic_tax`を無効化

### 6.2 将来（契約数150件到達時）

**推奨**: **税務登録を実施**

**タイミング**:
- 月間契約数が100件を超えた時点で準備開始
- 150件に到達する前に完了

**準備期間**:
- 税理士相談: 1-2週間
- 税務登録番号取得: 2-4週間
- Stripe設定変更: 1-2日
- **合計**: 約1.5-2ヶ月

---

## 7. まとめ

### 7.1 結論

| 項目 | 推奨 |
|-----|------|
| **現段階（ローンチ時）** | ❌ 税務登録なし |
| **将来（契約数150件超）** | ✅ 税務登録あり |
| **Stripe審査への影響** | ⚠️ わずかにあり（審査期間+1-3日） |
| **初期価格設定** | 税込6,600円/月 |
| **将来価格設定** | 税抜6,000円/月 + 消費税10% |

### 7.2 実装チェックリスト

#### フェーズ1: ローンチ時（税務登録なし）

- [ ] Stripe Priceを税込6,600円/月で作成
- [ ] `tax_behavior=inclusive`を設定
- [ ] `automatic_tax`を無効化
- [ ] 価格表示: 「月額6,600円（税込）」
- [ ] 環境変数: `STRIPE_PRICE_ID`のみ

#### フェーズ2: 拡大期（税務登録あり）

- [ ] 税理士に相談
- [ ] 適格請求書発行事業者登録
- [ ] 税務登録番号（T番号）取得
- [ ] Stripe Dashboardで税務設定
- [ ] Tax Rateを作成（消費税10%）
- [ ] 新しいPriceを作成（税抜6,000円/月）
- [ ] `automatic_tax`を有効化
- [ ] 価格表示: 「月額6,000円（税抜）+ 消費税10%」
- [ ] 環境変数: `STRIPE_TAX_ENABLED`, `STRIPE_TAX_RATE_ID`を追加

---

## 8. 参考リンク

- [Stripe Tax - 日本](https://stripe.com/docs/tax/japan)
- [適格請求書等保存方式（インボイス制度）](https://www.nta.go.jp/taxes/shiraberu/zeimokubetsu/shohi/keigenzeiritsu/invoice.htm)
- [Stripe Tax Rateの作成](https://stripe.com/docs/api/tax_rates/create)
- [Stripe Checkout Session - Automatic Tax](https://stripe.com/docs/api/checkout/sessions/create#create_checkout_session-automatic_tax)

---

**最終更新**: 2025-12-29
**作成者**: Claude Sonnet 4.5
