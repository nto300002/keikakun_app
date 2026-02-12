# けいかくん - S3署名付きURLの設計判断と有効期限設定

**作成日**: 2026-01-28
**対象**: 2次面接 - セキュリティ・インフラ設計判断
**関連技術**: AWS S3, 署名付きURL (Presigned URL), boto3

---

## 概要

けいかくんアプリケーションでは、個別支援計画のPDFファイル（機密性の高い福祉関連文書）をS3に保存し、**署名付きURL（Presigned URL）**でユーザーに提供しています。有効期限は**3600秒（1時間）**に設定しています。この設計判断の理由、セキュリティ上の利点、他の方式との比較について説明します。

---

## 1. S3署名付きURLとは

### 1.1 定義

**署名付きURL（Presigned URL）**:
- S3バケットのオブジェクトに一時的にアクセスできるURL
- 有効期限付き（最大7日間）
- AWSの認証情報（Access KeyとSecret Key）で署名
- URLを知っている人だけがアクセス可能

**署名の構造**:
```
https://keikakun-bucket.s3.ap-northeast-1.amazonaws.com/pdfs/plan_123.pdf?
  X-Amz-Algorithm=AWS4-HMAC-SHA256&
  X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20260128%2Fap-northeast-1%2Fs3%2Faws4_request&
  X-Amz-Date=20260128T120000Z&
  X-Amz-Expires=3600&
  X-Amz-SignedHeaders=host&
  X-Amz-Signature=abcd1234567890efgh...
```

**署名パラメータ**:
- `X-Amz-Algorithm`: 署名アルゴリズム（AWS4-HMAC-SHA256）
- `X-Amz-Credential`: Access Key + リージョン
- `X-Amz-Date`: 署名生成日時（UTC）
- `X-Amz-Expires`: 有効期限（秒単位）
- `X-Amz-Signature`: HMAC-SHA256署名

---

### 1.2 けいかくんでの実装

**ファイル**: `k_back/app/core/storage.py`

```python
async def create_presigned_url(object_name: str, expiration: int = 3600, inline: bool = True) -> str | None:
    """
    Generate a presigned URL to share an S3 object.

    :param object_name: S3オブジェクト名（例: "pdfs/plan_123.pdf"）
    :param expiration: 有効期限（秒単位、デフォルト: 3600秒 = 1時間）
    :param inline: ブラウザプレビュー（True）またはダウンロード（False）
    :return: 署名付きURL
    """
    # S3クライアント作成
    s3_client = boto3.client(
        "s3",
        endpoint_url=settings.S3_ENDPOINT_URL,
        aws_access_key_id=settings.S3_ACCESS_KEY,
        aws_secret_access_key=secret_key,
        region_name=settings.S3_REGION,
        config=boto3.session.Config(signature_version='s3v4')  # 署名バージョン4
    )

    params = {
        'Bucket': settings.S3_BUCKET_NAME,
        'Key': object_name
    }

    # Content-Dispositionを設定（ブラウザでプレビュー表示するか、ダウンロードするか）
    if inline:
        params['ResponseContentDisposition'] = 'inline'  # ブラウザでプレビュー
    else:
        filename = object_name.split('/')[-1]
        params['ResponseContentDisposition'] = f'attachment; filename="{filename}"'  # ダウンロード

    # 署名付きURL生成
    response = s3_client.generate_presigned_url(
        'get_object',
        Params=params,
        ExpiresIn=expiration  # 3600秒（1時間）
    )
    return response
```

**ポイント**:
- ✅ 署名バージョン4（`s3v4`）を使用（最新の署名方式）
- ✅ `ExpiresIn`で有効期限を指定（デフォルト: 3600秒）
- ✅ `Content-Disposition`を動的に設定（inline/attachment）

---

### 1.3 使用箇所

#### エンドポイント1: 個別支援計画一覧取得

**ファイル**: `k_back/app/api/v1/endpoints/support_plans.py`

```python
@router.get("/welfare-recipients/{recipient_id}/support-plan-cycles")
async def get_support_plan_cycles(
    recipient_id: UUID,
    db: AsyncSession = Depends(deps.get_db),
    current_user: models.Staff = Depends(deps.require_active_billing),
):
    # ... 権限チェック ...

    # 各サイクルのステータスに署名付きURLを追加
    for status in cycle.statuses:
        if status.completed and deliverable.file_path:
            # S3パスから署名付きURLを生成
            object_name = deliverable.file_path.replace(f"s3://{settings.S3_BUCKET_NAME}/", "")
            pdf_url = await storage.create_presigned_url(
                object_name=object_name,
                expiration=3600,  # 1時間
                inline=True       # ブラウザでプレビュー
            )
            status_response.pdf_url = pdf_url

    return cycles_response
```

**フロー**:
```
[クライアント] → GET /welfare-recipients/{id}/support-plan-cycles
                    ↓
              [バックエンド]
                    ↓ 認証・認可チェック
                    ↓ データベースクエリ
                    ↓ S3署名付きURL生成（有効期限: 1時間）
                    ↓
[クライアント] ← JSON（署名付きURLを含む）
                    ↓
              [ブラウザ]
                    ↓ 署名付きURLに直接アクセス
                    ↓
              [S3] → PDFファイルを返す
```

---

#### エンドポイント2: PDFアップロード

**ファイル**: `k_back/app/api/v1/endpoints/support_plans.py`

```python
@router.post("/plan-deliverables")
async def upload_plan_deliverable(
    plan_cycle_id: int = Form(...),
    deliverable_type: str = Form(...),
    file: UploadFile = File(...),
    db: AsyncSession = Depends(deps.get_db),
    current_user: models.Staff = Depends(deps.require_active_billing),
):
    # 1. 権限チェック（Employee権限では不可）
    if current_user.role == StaffRole.employee:
        raise ForbiddenException(ja.SUPPORT_PLAN_EMPLOYEE_CANNOT_UPLOAD)

    # 2. S3にアップロード
    file_path = await storage.upload_file(file.file, object_name)

    # 3. データベースに記録
    deliverable = await support_plan_service.create_plan_deliverable(
        db, plan_cycle_id, deliverable_type, file_path, file.filename
    )

    return deliverable
```

**セキュリティポイント**:
- ✅ バックエンドで権限チェック（Employee権限は拒否）
- ✅ S3へのアップロードもバックエンド経由
- ✅ 直接S3にアクセスさせない

---

## 2. 署名付きURLを使った理由

### 2.1 セキュリティ理由

#### 理由1: S3バケットを完全非公開にできる

**署名付きURLを使わない場合（パブリックURL）**:
```python
# ❌ 悪い例: S3バケットをパブリックに設定
s3_url = f"https://keikakun-bucket.s3.amazonaws.com/pdfs/plan_123.pdf"
# → 誰でもアクセス可能（URLが漏洩したら終わり）
```

**署名付きURLを使う場合**:
```python
# ✅ 良い例: S3バケットはプライベート
presigned_url = await storage.create_presigned_url(
    object_name="pdfs/plan_123.pdf",
    expiration=3600
)
# → 有効期限付きのURLのみアクセス可能
```

**S3バケットポリシー**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::keikakun-bucket/*",
      "Condition": {
        "StringNotEquals": {
          "aws:PrincipalArn": "arn:aws:iam::ACCOUNT_ID:user/keikakun-service"
        }
      }
    }
  ]
}
```

**メリット**:
- ✅ S3バケット全体を非公開に設定
- ✅ URLが漏洩しても有効期限後は無効
- ✅ AWS IAMで細かくアクセス制御

---

#### 理由2: バックエンドで認証・認可を一元管理

**署名付きURLのフロー**:
```
[クライアント] → GET /support-plan-cycles（JWT Token付き）
                    ↓
              [バックエンド]
                    ↓ JWT検証（認証）
                    ↓ 事業所権限チェック（認可）
                    ↓ 課金ステータスチェック（past_dueは拒否）
                    ↓ スタッフ役割チェック（Employeeは制限）
                    ↓ 署名付きURL生成
                    ↓
[クライアント] ← 署名付きURL
                    ↓
[S3] ← 署名検証 → PDFファイル
```

**パブリックURLのリスク**:
```
[クライアント] → https://keikakun-bucket.s3.amazonaws.com/pdfs/plan_123.pdf
                    ↓
[S3] → PDFファイル（認証なし）
```

**メリット**:
- ✅ 認証・認可をバックエンドで一元管理
- ✅ 課金ステータスに応じたアクセス制御
- ✅ 役割ベースアクセス制御（RBAC）

---

#### 理由3: アクセスログの記録

**CloudWatch Logsへの記録**:
```python
# app/api/v1/endpoints/support_plans.py
logger.info(f"Staff {current_user.id} accessed plan deliverable {deliverable.id}")
```

**記録される情報**:
- 誰が（スタッフID）
- いつ（タイムスタンプ）
- どのファイルに（PDF ID）
- どの事業所から（Office ID）

**S3アクセスログとの連携**:
```
[バックエンドログ] + [S3アクセスログ] = 完全な監査証跡
```

**メリット**:
- ✅ 不正アクセスの検出
- ✅ 監査証跡の保持
- ✅ コンプライアンス対応

---

#### 理由4: Content-Dispositionの柔軟な制御

**ブラウザでプレビュー表示（inline）**:
```python
presigned_url = await storage.create_presigned_url(
    object_name="pdfs/plan_123.pdf",
    expiration=3600,
    inline=True  # ブラウザでプレビュー
)

# 生成されるURL:
# https://...?ResponseContentDisposition=inline
```

**ダウンロードを強制（attachment）**:
```python
presigned_url = await storage.create_presigned_url(
    object_name="pdfs/plan_123.pdf",
    expiration=3600,
    inline=False  # ダウンロード
)

# 生成されるURL:
# https://...?ResponseContentDisposition=attachment; filename="plan_123.pdf"
```

**けいかくんの使い分け**:
| 用途 | inline | 理由 |
|-----|--------|------|
| 個別支援計画一覧 | ✅ True | ブラウザでプレビュー表示 |
| PDFダウンロード | ❌ False | ファイルとしてダウンロード |

**メリット**:
- ✅ ユーザー体験の向上（ブラウザでプレビュー）
- ✅ ファイル名の制御（ダウンロード時）
- ✅ バックエンドで動的に切り替え可能

---

### 2.2 運用上の理由

#### 理由5: URLの再利用防止

**問題（パブリックURL）**:
```
https://keikakun-bucket.s3.amazonaws.com/pdfs/plan_123.pdf

→ このURLが一度漏洩したら永久にアクセス可能
→ メール、Slack、チャットツールに貼り付けられたら拡散
```

**署名付きURLの解決**:
```
https://keikakun-bucket.s3.amazonaws.com/pdfs/plan_123.pdf?
  X-Amz-Expires=3600&
  X-Amz-Signature=abcd1234...

→ 1時間後に自動的に無効化
→ URLが漏洩しても被害を最小化
```

**実例シナリオ**:
1. スタッフAが個別支援計画PDFのURLをコピー
2. 誤ってSlackのパブリックチャンネルに貼り付け
3. 1時間後、URLは自動的に無効化
4. 被害は1時間分のみ（早期発見で最小化）

**メリット**:
- ✅ URL漏洩時の被害を時間的に制限
- ✅ 自動的に無効化（手動削除不要）
- ✅ セキュリティインシデントの影響を最小化

---

#### 理由6: スケーラビリティ

**署名付きURLのトラフィックフロー**:
```
[クライアント] → [バックエンド] → 署名付きURL生成（軽量）
                                       ↓
[クライアント] → [S3] → PDFダウンロード（直接）
```

**バックエンド経由の場合**:
```
[クライアント] → [バックエンド] → S3からPDF取得
                                 ↓
                              PDFデータを中継
                                 ↓
                 ← [クライアント] ← PDFダウンロード
```

**比較**:
| 方式 | バックエンド負荷 | ネットワーク帯域 | スケーラビリティ |
|-----|----------------|----------------|----------------|
| 署名付きURL | 軽量（URL生成のみ） | S3が直接配信 | ✅ 高 |
| バックエンド経由 | 重い（PDFデータ中継） | 2倍の帯域消費 | ❌ 低 |

**メリット**:
- ✅ バックエンドの負荷を軽減
- ✅ S3の高速ダウンロードを活用
- ✅ 大量ダウンロードにも対応可能

---

## 3. 有効期限3600秒（1時間）に設定した根拠

### 3.1 セキュリティリスクとのバランス

#### 有効期限の選択肢

| 有効期限 | セキュリティ | ユーザー体験 | けいかくんでの評価 |
|---------|------------|------------|------------------|
| **5分** | ★★★★★ 非常に高い | ★☆☆☆☆ 悪い | ❌ 短すぎる |
| **15分** | ★★★★☆ 高い | ★★☆☆☆ やや不便 | ⚠️ やや短い |
| **1時間** | ★★★☆☆ 中 | ★★★★☆ 良好 | ✅ 最適 |
| **6時間** | ★★☆☆☆ やや低い | ★★★★★ 非常に良い | ⚠️ やや長い |
| **24時間** | ★☆☆☆☆ 低い | ★★★★★ 非常に良い | ❌ 長すぎる |

---

#### 1時間を選んだ理由

**理由1: 福祉事業所の業務フローに適合**

**典型的な業務フロー**:
```
10:00 - スタッフがダッシュボードにログイン
10:05 - 個別支援計画一覧を表示（署名付きURL生成）
10:10 - PDFをブラウザでプレビュー
10:15 - 内容を確認して編集が必要か判断
10:30 - 別の利用者のPDFも確認
10:45 - 担当者会議で使用するためPDFをダウンロード
11:00 - ログアウト（1時間以内に完了）
```

**1時間で十分なケース**:
- ✅ PDFのプレビュー・確認（5-10分）
- ✅ 複数のPDFを順番に確認（30分）
- ✅ 担当者会議での使用（30-45分）

**1時間では不足するケース**:
- ❌ PDFをダウンロードして長時間オフライン作業
- ❌ URLをメールで共有して後で確認
- ❌ ブラウザタブを開きっぱなしで放置

**対策**: 必要に応じて再度一覧ページにアクセスすれば新しい署名付きURLを取得可能

---

**理由2: URL漏洩時の被害を最小化**

**漏洩シナリオ1: 誤送信**
```
10:00 - スタッフAがPDFのURLをコピー
10:05 - 誤って外部メールアドレスに送信
11:05 - 1時間後、URLは自動的に無効化
      → 被害は1時間分のみ
```

**漏洩シナリオ2: ブラウザ履歴**
```
10:00 - スタッフAがPDFを閲覧
10:10 - ブラウザ履歴にURLが残る
11:10 - 1時間後、URLは自動的に無効化
      → 他のスタッフがブラウザ履歴からアクセスしても無効
```

**漏洩シナリオ3: 悪意のある攻撃**
```
10:00 - 攻撃者がスタッフAのブラウザからURLを盗む
10:30 - 攻撃者がURLにアクセスしてPDFをダウンロード
11:00 - 1時間後、URLは自動的に無効化
      → 被害は1時間分のみ（継続的なアクセスは不可）
```

**メリット**:
- ✅ URL漏洩時の被害を時間的に制限
- ✅ 長期的な不正アクセスを防止
- ✅ セキュリティインシデントの影響を最小化

---

**理由3: 業界標準とのバランス**

**他サービスの有効期限設定**:

| サービス | 用途 | 有効期限 |
|---------|-----|---------|
| **Google Drive共有リンク** | ファイル共有 | 無期限（削除するまで有効） |
| **Dropbox共有リンク** | ファイル共有 | 無期限 |
| **AWS CloudFront署名付きURL** | 動画配信 | 1-24時間（推奨） |
| **GitHub Releases** | ソフトウェア配布 | 無期限 |
| **医療系SaaS** | 診療記録 | 15分-1時間 |
| **けいかくん** | 個別支援計画 | **1時間** |

**けいかくんの位置づけ**:
- 医療系SaaSに近いセキュリティレベル
- Google DriveやDropboxより厳格
- AWS CloudFrontの推奨範囲内

---

**理由4: パフォーマンスとコストの最適化**

**署名付きURL生成のコスト**:
```python
# 1回の署名付きURL生成
# - 計算時間: 約1-2ms
# - AWS APIコール: 0回（ローカルで署名生成）
# - コスト: 実質無料
```

**1時間有効期限のメリット**:
- ✅ 同じPDFに何度もアクセスしても再生成不要
- ✅ ブラウザキャッシュと組み合わせて高速化
- ✅ バックエンドへのAPIコール削減

**5分有効期限のデメリット**:
- ❌ 頻繁に再生成が必要
- ❌ バックエンドへのAPIコールが増加
- ❌ ユーザー体験の悪化（頻繁なリロード）

---

### 3.2 ユーザー体験（UX）の考慮

#### 良好なUXを実現する設計

**シナリオ1: 個別支援計画の確認**
```
10:00 - スタッフがダッシュボードにアクセス
10:05 - 個別支援計画一覧を表示
10:10 - PDFをブラウザでプレビュー（署名付きURL有効）
10:15 - 別のタブで他の作業
10:30 - 再度PDFタブに戻る（まだ有効）
10:45 - 内容を確認して終了
      → 1時間以内なので再アクセス不要
```

**シナリオ2: 担当者会議での使用**
```
10:00 - スタッフA、B、Cが会議室に集まる
10:05 - スタッフAがPDFを画面共有
10:10 - PDFを見ながらディスカッション
10:45 - 会議終了
      → 1時間以内なので問題なし
```

**シナリオ3: 長時間作業（1時間超過）**
```
10:00 - スタッフがPDFをプレビュー
11:05 - 1時間後、別のPDFにアクセスしようとする
      → 署名付きURLが期限切れ
      → 自動的にダッシュボードにリダイレクト
      → 再度一覧ページにアクセス（新しい署名付きURL取得）
      → PDFプレビュー再開
```

**対策（フロントエンド）**:
```typescript
// k_front/components/PDFViewer.tsx（将来的に実装）
useEffect(() => {
  // 50分後（3000秒）に警告表示
  const warningTimer = setTimeout(() => {
    toast.warning('PDFのリンクが間もなく期限切れになります。ページを再読み込みしてください。');
  }, 50 * 60 * 1000);

  return () => clearTimeout(warningTimer);
}, [pdfUrl]);
```

**メリット**:
- ✅ ほとんどの業務フローで1時間以内に完了
- ✅ 期限切れ時の対応が明確（再アクセス）
- ✅ 警告表示でユーザーに事前通知

---

## 4. 他の方式との比較

### 4.1 パブリックURL（S3バケットを公開）

**実装例**:
```python
# ❌ 悪い例
s3_url = f"https://keikakun-bucket.s3.ap-northeast-1.amazonaws.com/pdfs/plan_123.pdf"
```

**メリット**:
- ✅ 実装が簡単
- ✅ 有効期限なし（永続的）
- ✅ 追加のAPIコール不要

**デメリット**:
- ❌ S3バケット全体が公開される
- ❌ URLが漏洩したら永久にアクセス可能
- ❌ 認証・認可が不可能
- ❌ アクセスログの記録が困難
- ❌ 課金ステータスに応じた制御ができない

**けいかくんでの評価**: ❌ **不採用**（セキュリティリスクが高すぎる）

---

### 4.2 CloudFront署名付きURL（CDN経由）

**実装例**:
```python
import boto3
from botocore.signers import CloudFrontSigner

cloudfront_signer = CloudFrontSigner(key_id, private_key_pem)
signed_url = cloudfront_signer.generate_presigned_url(
    url="https://d111111abcdef8.cloudfront.net/pdfs/plan_123.pdf",
    date_less_than=datetime.now() + timedelta(hours=1)
)
```

**メリット**:
- ✅ CDNによる高速配信（エッジロケーション）
- ✅ 署名付きURLでセキュリティ確保
- ✅ S3と同等のアクセス制御

**デメリット**:
- ❌ 追加コスト（CloudFront利用料）
- ❌ 設定が複雑（署名キーペアの管理）
- ❌ けいかくんの規模では不要（ファイルサイズが小さい）

**コスト比較**:
```
S3署名付きURL:
- ストレージ: 0.025 USD/GB/月
- データ転送: 0.114 USD/GB（東京リージョン）
- 合計: 約3,000円/月（100GB、10,000ダウンロード）

CloudFront署名付きURL:
- ストレージ: 0.025 USD/GB/月（S3と同じ）
- データ転送: 0.114 USD/GB（S3→CloudFront）
- データ転送: 0.114 USD/GB（CloudFront→ユーザー）
- リクエスト: 0.0075 USD/10,000リクエスト
- 合計: 約6,000円/月（2倍のコスト）
```

**けいかくんでの評価**: ⚠️ **将来的に検討**（現時点では不要）

---

### 4.3 バックエンド経由のダウンロード

**実装例**:
```python
@router.get("/plan-deliverables/{deliverable_id}/download")
async def download_plan_deliverable(
    deliverable_id: UUID,
    db: AsyncSession = Depends(deps.get_db),
    current_user: models.Staff = Depends(deps.require_active_billing),
):
    # 1. 権限チェック
    deliverable = await crud.plan_deliverable.get(db, id=deliverable_id)

    # 2. S3からPDFを取得
    object_name = deliverable.file_path.replace(f"s3://{settings.S3_BUCKET_NAME}/", "")
    pdf_data = s3_client.get_object(Bucket=settings.S3_BUCKET_NAME, Key=object_name)

    # 3. PDFデータをクライアントに返す
    return StreamingResponse(
        pdf_data['Body'],
        media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename={deliverable.original_filename}"}
    )
```

**メリット**:
- ✅ 完全なアクセス制御
- ✅ S3署名付きURLの設定不要
- ✅ リアルタイムの権限チェック

**デメリット**:
- ❌ バックエンドの負荷が高い（PDFデータを中継）
- ❌ ネットワーク帯域の2倍消費（S3→バックエンド→クライアント）
- ❌ スケーラビリティが低い
- ❌ Cloud Runのタイムアウト制限（最大60秒）

**パフォーマンス比較**:
```
署名付きURL:
- クライアント → バックエンド: 署名付きURL取得（10ms）
- クライアント → S3: PDFダウンロード（500ms、10MB）
- 合計: 510ms

バックエンド経由:
- クライアント → バックエンド: リクエスト（10ms）
- バックエンド → S3: PDFダウンロード（500ms、10MB）
- バックエンド → クライアント: PDFアップロード（500ms、10MB）
- 合計: 1010ms（約2倍遅い）
```

**けいかくんでの評価**: ❌ **不採用**（パフォーマンスとスケーラビリティの問題）

---

### 4.4 比較表

| 方式 | セキュリティ | パフォーマンス | コスト | スケーラビリティ | けいかくん評価 |
|-----|------------|--------------|-------|----------------|---------------|
| **S3署名付きURL** | ★★★★☆ 高 | ★★★★★ 非常に高 | ★★★★★ 安い | ★★★★★ 非常に高 | ✅ **採用** |
| パブリックURL | ★☆☆☆☆ 非常に低 | ★★★★★ 非常に高 | ★★★★★ 安い | ★★★★★ 非常に高 | ❌ 不採用 |
| CloudFront署名付きURL | ★★★★★ 非常に高 | ★★★★★ 非常に高 | ★★☆☆☆ やや高い | ★★★★★ 非常に高 | ⚠️ 将来検討 |
| バックエンド経由 | ★★★★★ 非常に高 | ★★☆☆☆ やや低い | ★★★☆☆ 中 | ★★☆☆☆ やや低い | ❌ 不採用 |

**けいかくんの選択**: **S3署名付きURL**（セキュリティ・パフォーマンス・コストのバランスが最適）

---

## 5. セキュリティ上の考慮事項

### 5.1 実装済みのセキュリティ対策

#### 対策1: S3バケットのプライベート設定

**S3バケットポリシー**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyPublicAccess",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::keikakun-bucket/*"
    },
    {
      "Sid": "AllowServiceAccountAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNT_ID:user/keikakun-service"
      },
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::keikakun-bucket/*"
    }
  ]
}
```

**ポイント**:
- ✅ パブリックアクセスを完全拒否
- ✅ サービスアカウントのみアクセス可能
- ✅ IAM認証が必須

---

#### 対策2: 署名バージョン4（s3v4）の使用

**実装**:
```python
s3_client = boto3.client(
    "s3",
    config=boto3.session.Config(signature_version='s3v4')  # 最新の署名方式
)
```

**署名バージョン4の特徴**:
- ✅ HMAC-SHA256（強力なハッシュアルゴリズム）
- ✅ リプレイ攻撃に耐性（タイムスタンプベース）
- ✅ リージョン情報を含む（グローバルな署名検証）

**旧バージョン（v2）との比較**:
| 項目 | v2（非推奨） | v4（推奨） |
|-----|------------|----------|
| ハッシュアルゴリズム | HMAC-SHA1 | HMAC-SHA256 |
| リプレイ攻撃耐性 | 弱い | 強い |
| リージョン対応 | なし | あり |
| AWSの推奨 | ❌ 非推奨 | ✅ 推奨 |

---

#### 対策3: Content-Typeの明示的設定

**実装**:
```python
s3_client.upload_fileobj(
    file,
    settings.S3_BUCKET_NAME,
    object_name,
    ExtraArgs={
        'ContentType': 'application/pdf',  # PDFとして明示
        'ContentDisposition': 'inline'     # ブラウザでプレビュー
    }
)
```

**セキュリティ上の理由**:
- ✅ ブラウザがファイルを正しく解釈（XSS防止）
- ✅ Content-Type Sniffingを防止
- ✅ 意図しないスクリプト実行を防止

**悪用例（Content-Typeなし）**:
```
1. 攻撃者が悪意のあるHTMLファイルをPDFとして偽装
2. Content-Typeが未設定の場合、ブラウザが自動判定
3. HTMLとして解釈されてスクリプトが実行される
```

**対策（Content-Type設定済み）**:
```
1. Content-Type: application/pdf が設定済み
2. ブラウザは必ずPDFとして解釈
3. HTMLやJavaScriptは実行されない
```

---

#### 対策4: オブジェクト名のサニタイゼーション

**実装**:
```python
# app/services/support_plan_service.py
import uuid

object_name = f"pdfs/{uuid.uuid4()}.pdf"  # UUIDで一意性を保証
```

**セキュリティ上の理由**:
- ✅ ディレクトリトラバーサル攻撃を防止
- ✅ 予測不可能なファイル名
- ✅ 衝突の回避

**攻撃例（サニタイゼーションなし）**:
```python
# ❌ 悪い例
filename = user_input  # "../../etc/passwd"
object_name = f"pdfs/{filename}"  # "pdfs/../../etc/passwd"
```

**対策（UUIDを使用）**:
```python
# ✅ 良い例
object_name = f"pdfs/{uuid.uuid4()}.pdf"  # "pdfs/3f8d9e2a-1b4c-4d5e-6f7g-8h9i0j1k2l3m.pdf"
```

---

### 5.2 将来的な改善案

#### 改善案1: 有効期限の動的調整

**現在**: 固定1時間

**将来的な実装**:
```python
async def create_presigned_url_dynamic(
    object_name: str,
    user_role: StaffRole,
    billing_status: BillingStatus
) -> str:
    # 役割に応じて有効期限を調整
    if user_role == StaffRole.owner:
        expiration = 3600  # 1時間（Owner）
    elif user_role == StaffRole.manager:
        expiration = 3600  # 1時間（Manager）
    else:  # employee
        expiration = 1800  # 30分（Employee）

    # 課金ステータスに応じて調整
    if billing_status == BillingStatus.past_due:
        expiration = 900  # 15分（支払い遅延時は短縮）

    return await storage.create_presigned_url(object_name, expiration)
```

**メリット**:
- ✅ 役割に応じたセキュリティレベル
- ✅ 課金ステータスに応じた制御
- ✅ よりきめ細かいアクセス制御

---

#### 改善案2: CloudFront署名付きURL（将来的）

**導入条件**:
- ユーザー数が1,000事業所以上
- 月間ダウンロード数が100,000件以上
- グローバル展開（海外からのアクセス）

**導入時のメリット**:
- ✅ エッジロケーションで高速配信
- ✅ DDoS攻撃への耐性
- ✅ より細かいアクセス制御

---

#### 改善案3: 署名付きURL再生成APIの追加

**現在**: 一覧ページに戻って再生成

**将来的な実装**:
```python
@router.post("/plan-deliverables/{deliverable_id}/refresh-url")
async def refresh_presigned_url(
    deliverable_id: UUID,
    db: AsyncSession = Depends(deps.get_db),
    current_user: models.Staff = Depends(deps.require_active_billing),
):
    """署名付きURLを再生成"""
    # 権限チェック
    deliverable = await crud.plan_deliverable.get(db, id=deliverable_id)

    # 新しい署名付きURLを生成
    object_name = deliverable.file_path.replace(f"s3://{settings.S3_BUCKET_NAME}/", "")
    new_url = await storage.create_presigned_url(object_name, expiration=3600)

    return {"presigned_url": new_url}
```

**メリット**:
- ✅ ページ遷移なしでURL更新
- ✅ ユーザー体験の向上
- ✅ 長時間作業への対応

---

## 6. 面接で強調すべきポイント

### 6.1 技術的判断の根拠

**1. セキュリティファースト**
- S3バケットを完全非公開に設定
- 署名付きURLで時間的制限を設ける
- バックエンドで認証・認可を一元管理

**2. パフォーマンスとスケーラビリティ**
- S3の高速配信を直接活用
- バックエンドの負荷を最小化
- 大量ダウンロードにも対応可能

**3. コスト効率**
- CloudFront不要（現時点）
- S3署名付きURLは追加コストなし
- バックエンドのネットワーク帯域を節約

---

### 6.2 有効期限設定の根拠

**1時間を選んだ理由**:
- ✅ 福祉事業所の業務フローに適合（ほとんどの作業は1時間以内）
- ✅ URL漏洩時の被害を時間的に制限
- ✅ 業界標準（医療系SaaS）とのバランス
- ✅ ユーザー体験を損なわない範囲で最短

**他の選択肢を排除した理由**:
- 5分: 短すぎてUXが悪化
- 6時間: URL漏洩時のリスクが高い
- 24時間: セキュリティリスクが高すぎる

---

### 6.3 実装の詳細

**署名バージョン4（s3v4）の使用**:
- HMAC-SHA256で強力な署名
- リプレイ攻撃に耐性
- AWSの推奨方式

**Content-Dispositionの柔軟な制御**:
- inline: ブラウザでプレビュー
- attachment: ファイルとしてダウンロード
- ユーザー体験の最適化

**オブジェクト名のサニタイゼーション**:
- UUIDで一意性を保証
- ディレクトリトラバーサル攻撃を防止

---

## 7. 関連資料

- [AWS S3署名付きURL公式ドキュメント](https://docs.aws.amazon.com/AmazonS3/latest/userguide/ShareObjectPreSignedURL.html)
- [boto3 generate_presigned_url](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/s3/client/generate_presigned_url.html)
- 内部資料: `security_countermeasures.md` - セキュリティ対策全般
- 内部資料: `io_operations_and_await.md` - 非同期I/O処理

---

**最終更新**: 2026-01-28
**作成者**: Claude Sonnet 4.5
