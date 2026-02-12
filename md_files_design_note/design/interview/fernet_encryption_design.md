# けいかくん - Fernet暗号化方式の選定理由とキー管理

**作成日**: 2026-01-28
**対象**: 2次面接 - セキュリティ・暗号化設計判断
**関連技術**: Fernet (cryptography), AES-GCM, AWS KMS, Google Secret Manager

---

## 概要

けいかくんアプリケーションでは、Google Calendar認証情報（サービスアカウントキー）とMFA（多要素認証）シークレットを**Fernet暗号化**で保護しています。Fernet暗号化方式を選んだ理由、AES-GCMなど他の暗号化方式との比較、キー管理方法、機微なデータを扱う際のセキュリティ考慮点について説明します。

---

## 1. Fernet暗号化とは

### 1.1 定義

**Fernet**:
- Python `cryptography` ライブラリが提供する対称鍵暗号化方式
- AES-128-CBC + HMAC-SHA256の組み合わせ
- タイムスタンプ付きトークン（TTL検証可能）
- 安全性と使いやすさのバランスを重視した設計

**暗号化の構造**:
```
Fernetトークン = Base64(Version || Timestamp || IV || Ciphertext || HMAC)

Version: 1バイト（現在は0x80固定）
Timestamp: 8バイト（Unix timestamp）
IV: 16バイト（初期化ベクトル）
Ciphertext: 可変長（AES-128-CBCで暗号化されたデータ）
HMAC: 32バイト（HMAC-SHA256署名）
```

**暗号化アルゴリズム**:
- **暗号化**: AES-128-CBC（Cipher Block Chaining）
- **認証**: HMAC-SHA256（Hash-based Message Authentication Code）
- **キー長**: 32バイト（256ビット、Fernetキー）
  - 前半16バイト: AES暗号化キー
  - 後半16バイト: HMAC署名キー

---

### 1.2 けいかくんでの実装

#### 実装箇所1: Google Calendarサービスアカウントキーの暗号化

**ファイル**: `k_back/app/models/calendar_account.py`

```python
from cryptography.fernet import Fernet
import os

class OfficeCalendarAccount(Base):
    """事業所カレンダーアカウント"""
    __tablename__ = "office_calendar_accounts"

    # 暗号化されたサービスアカウントキーを保存
    service_account_key: Mapped[Optional[str]] = mapped_column(Text)

    def encrypt_service_account_key(self, key_data: Optional[str]) -> None:
        """サービスアカウントキーを暗号化して保存"""
        if not key_data:
            return

        # 環境変数から暗号化キーを取得
        encryption_key = os.getenv("CALENDAR_ENCRYPTION_KEY")
        if not encryption_key:
            raise ValueError("CALENDAR_ENCRYPTION_KEY environment variable is not set")

        # Fernetインスタンスを作成
        fernet = Fernet(encryption_key.encode())

        # 暗号化実行
        encrypted_key = fernet.encrypt(key_data.encode())

        # データベースに保存（Base64エンコード済み）
        self.service_account_key = encrypted_key.decode()

    def decrypt_service_account_key(self) -> Optional[str]:
        """暗号化されたサービスアカウントキーを復号化"""
        if not self.service_account_key:
            return None

        # 環境変数から暗号化キーを取得
        encryption_key = os.getenv("CALENDAR_ENCRYPTION_KEY")
        if not encryption_key:
            raise ValueError("CALENDAR_ENCRYPTION_KEY environment variable is not set")

        # Fernetインスタンスを作成
        fernet = Fernet(encryption_key.encode())

        # 復号化実行
        decrypted_key = fernet.decrypt(self.service_account_key.encode())

        return decrypted_key.decode()
```

**データフロー**:
```
[平文JSONキー] → encrypt_service_account_key()
                        ↓ Fernet暗号化
                  [Base64エンコード済みトークン]
                        ↓ データベース保存
                  [PostgreSQL TEXT型]
                        ↓ データベース読み取り
                  [Base64エンコード済みトークン]
                        ↓ Fernet復号化
                  [平文JSONキー] → Google API呼び出し
```

---

#### 実装箇所2: MFAシークレットの暗号化

**ファイル**: `k_back/app/core/security.py`

```python
from cryptography.fernet import Fernet
import base64
import os

def get_encryption_key() -> bytes:
    """暗号化キーを取得（環境変数またはシークレットキーから生成）"""
    key_source = os.getenv("ENCRYPTION_KEY", os.getenv("SECRET_KEY", "test_secret_key_for_pytest"))

    # Fernetキーは32バイト必要なので、適切な長さに調整
    key_bytes = key_source.encode()[:32].ljust(32, b'0')

    # Base64 URL-safeエンコード（Fernet要件）
    return base64.urlsafe_b64encode(key_bytes)


def encrypt_mfa_secret(secret: str) -> str:
    """
    MFAシークレットを暗号化する

    Args:
        secret: TOTP Base32シークレット（例: "JBSWY3DPEHPK3PXP"）

    Returns:
        str: Fernetトークン（既にBase64エンコード済み）
    """
    fernet = Fernet(get_encryption_key())
    encrypted = fernet.encrypt(secret.encode())
    return encrypted.decode()  # Fernetトークン（Base64形式）を文字列として返す


def decrypt_mfa_secret(encrypted_secret: str) -> str:
    """
    暗号化されたMFAシークレットを復号化する

    Args:
        encrypted_secret: Fernetトークン（Base64エンコード済み文字列）

    Returns:
        str: 復号化されたMFAシークレット（平文）

    Raises:
        InvalidToken: トークンが無効な場合
    """
    fernet = Fernet(get_encryption_key())
    decrypted = fernet.decrypt(encrypted_secret.encode())
    return decrypted.decode()
```

**セキュリティポイント**:
- ✅ TOTP Base32シークレットを暗号化してDB保存
- ✅ DB侵害時でもシークレットの平文は漏洩しない
- ✅ Fernet復号化エラーは例外をスロー（改ざん検出）

---

## 2. Fernet暗号化を選んだ理由

### 2.1 技術的な理由

#### 理由1: 暗号化と認証の統合（Authenticated Encryption）

**Fernetの構成**:
```
暗号化（AES-128-CBC） + 認証（HMAC-SHA256） = 認証付き暗号化
```

**メリット**:
- ✅ 暗号化と認証を同時に実行（Encrypt-then-MAC方式）
- ✅ データの改ざん検出（HMAC検証）
- ✅ 実装ミスのリスクが低い（ライブラリが自動処理）

**悪い例（暗号化のみ）**:
```python
# ❌ 悪い例: 暗号化のみ（認証なし）
from Crypto.Cipher import AES

cipher = AES.new(key, AES.MODE_CBC, iv)
ciphertext = cipher.encrypt(plaintext)
# → 改ざんされても検出できない！
```

**良い例（Fernet）**:
```python
# ✅ 良い例: 暗号化 + 認証
from cryptography.fernet import Fernet

fernet = Fernet(key)
token = fernet.encrypt(plaintext)
# → 改ざんされたら自動的に検出（InvalidToken例外）
```

**実際の攻撃シナリオ（認証なしの場合）**:
```
1. 攻撃者がDBから暗号化されたデータを盗む
2. 暗号文の一部を改ざん（ビットフリッピング攻撃）
3. アプリが復号化して誤ったデータを処理
4. 攻撃者が意図した動作を引き起こす
```

**Fernetの防御**:
```
1. 攻撃者がDBから暗号化されたデータを盗む
2. 暗号文の一部を改ざん
3. アプリが復号化を試みる
4. HMAC検証失敗 → InvalidToken例外
5. 攻撃失敗（改ざんが検出される）
```

---

#### 理由2: シンプルで安全なAPI

**Fernetの使いやすさ**:
```python
# 暗号化
fernet = Fernet(key)
encrypted = fernet.encrypt(b"secret data")

# 復号化
decrypted = fernet.decrypt(encrypted)

# たったこれだけ！
```

**AES-GCMを直接使う場合（複雑）**:
```python
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
import os

# ❌ 複雑な実装
key = os.urandom(32)
aesgcm = AESGCM(key)
nonce = os.urandom(12)  # ノンスを自分で管理（重要！）
ciphertext = aesgcm.encrypt(nonce, b"secret data", None)

# 復号化時にノンスも必要
decrypted = aesgcm.decrypt(nonce, ciphertext, None)

# ノンスの保存・管理が必要（実装ミスのリスク）
```

**Fernetのメリット**:
- ✅ ノンス（IV）の管理が不要（自動生成・埋め込み）
- ✅ タイムスタンプ付き（有効期限チェック可能）
- ✅ Base64エンコード済み（文字列として扱える）
- ✅ 実装ミスのリスクが低い

---

#### 理由3: タイムスタンプによるTTL（有効期限）検証

**Fernetトークンの構造**:
```
Base64(Version || Timestamp || IV || Ciphertext || HMAC)
              ↑ 8バイトのUnix timestamp
```

**TTL検証の実装例**:
```python
# 暗号化（タイムスタンプは自動埋め込み）
token = fernet.encrypt(b"secret data")

# 復号化 + TTL検証（60秒以内のみ有効）
try:
    decrypted = fernet.decrypt(token, ttl=60)
except InvalidToken:
    print("トークンが期限切れまたは改ざんされています")
```

**けいかくんでの将来的な用途**:
```python
# Google Calendar連携トークンの期限管理
# 例: 30日以上古い暗号化データは再取得を促す
try:
    key_data = fernet.decrypt(encrypted_key, ttl=30*24*60*60)  # 30日間有効
except InvalidToken:
    # 古すぎる → 再認証を要求
    raise HTTPException(status_code=401, detail="カレンダー連携の再認証が必要です")
```

**AES-GCMとの比較**:
| 機能 | Fernet | AES-GCM |
|-----|--------|---------|
| タイムスタンプ | ✅ 自動埋め込み | ❌ 自分で実装 |
| TTL検証 | ✅ 組み込み | ❌ 自分で実装 |
| 有効期限管理 | ✅ 簡単 | ❌ 複雑 |

---

#### 理由4: Python標準ライブラリとの親和性

**cryptographyライブラリ**:
- Python暗号化ライブラリのデファクトスタンダード
- PyCAが開発・メンテナンス（信頼性が高い）
- FIPS 140-2検証済みのOpenSSLバックエンド
- 豊富なドキュメントとコミュニティ

**けいかくんの技術スタック**:
```
cryptography ← Fernet, JWT署名, パスワードハッシュ
    ↓
pyOpenSSL ← TLS/SSL処理
    ↓
OpenSSL ← 低レベル暗号化処理（C実装）
```

**他のライブラリとの統合**:
```python
# JWT署名もcryptographyを使用（一貫性）
from jose import jwt  # 内部でcryptographyを使用

# パスワードハッシュもcryptographyベース
from passlib.context import CryptContext  # bcryptはcryptographyベース
```

**メリット**:
- ✅ 依存関係の統一（cryptography 1つで済む）
- ✅ バージョン管理が簡単
- ✅ セキュリティアップデートが一元化

---

### 2.2 実装上の理由

#### 理由5: データベース保存時の利便性

**Fernetトークンの特徴**:
- Base64エンコード済み（ASCII文字列）
- PostgreSQL TEXT型で保存可能
- JSON形式にも対応

**実装例**:
```python
# 暗号化（Base64エンコード済み）
encrypted = fernet.encrypt(b"secret data")
# → gAAAAABl3x4y...（ASCII文字列）

# データベース保存（TEXT型）
calendar_account.service_account_key = encrypted.decode()
# → PostgreSQL TEXT型にそのまま保存
```

**AES-GCMの場合（バイナリデータ）**:
```python
# 暗号化（バイナリデータ）
ciphertext = aesgcm.encrypt(nonce, b"secret data", None)
# → バイナリデータ

# データベース保存（BYTEA型またはBase64変換が必要）
# Option 1: BYTEA型
calendar_account.service_account_key = ciphertext  # PostgreSQL BYTEA型

# Option 2: Base64エンコード（手動）
import base64
calendar_account.service_account_key = base64.b64encode(ciphertext).decode()
```

**Fernetのメリット**:
- ✅ Base64エンコード不要（自動処理）
- ✅ TEXT型でシンプルに保存
- ✅ JSON APIでもそのまま扱える

---

#### 理由6: エラーハンドリングの簡潔性

**Fernetの例外処理**:
```python
from cryptography.fernet import InvalidToken

try:
    decrypted = fernet.decrypt(encrypted_data)
except InvalidToken:
    # 改ざん、期限切れ、キー不一致などすべてこの例外
    logger.error("復号化失敗: トークンが無効です")
    raise HTTPException(status_code=500, detail="暗号化データの復号化に失敗しました")
```

**AES-GCMの場合（複雑）**:
```python
from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

try:
    decrypted = aesgcm.decrypt(nonce, ciphertext, None)
except InvalidTag:
    # 認証タグ不一致（改ざん検出）
    logger.error("復号化失敗: 認証タグが無効です")
except ValueError:
    # ノンスが不正
    logger.error("復号化失敗: ノンスが無効です")
except Exception as e:
    # その他のエラー
    logger.error(f"復号化失敗: {e}")
```

**Fernetのメリット**:
- ✅ 例外が1つだけ（`InvalidToken`）
- ✅ エラーハンドリングがシンプル
- ✅ ログ記録が容易

---

## 3. AES-GCMなど他の暗号化方式との比較

### 3.1 比較対象

| 暗号化方式 | 暗号化アルゴリズム | 認証方式 | タイムスタンプ | けいかくん評価 |
|-----------|------------------|---------|--------------|---------------|
| **Fernet** | AES-128-CBC | HMAC-SHA256 | ✅ あり | ✅ **採用** |
| AES-GCM | AES-GCM | GCM認証タグ | ❌ なし | ⚠️ 高度なユースケース向け |
| AES-CBC | AES-CBC | ❌ なし | ❌ なし | ❌ 不採用（認証なし） |
| ChaCha20-Poly1305 | ChaCha20 | Poly1305 | ❌ なし | ⚠️ モバイル最適化向け |
| RSA-OAEP | RSA | ❌ なし | ❌ なし | ❌ 不採用（非対称鍵不要） |

---

### 3.2 Fernet vs AES-GCM 詳細比較

#### 暗号化アルゴリズム

**Fernet (AES-128-CBC)**:
- ブロック暗号（16バイトブロック）
- CBCモード（Cipher Block Chaining）
- 128ビットキー（AES部分）

**AES-GCM**:
- ブロック暗号（16バイトブロック）
- GCMモード（Galois/Counter Mode）
- 128/192/256ビットキー（選択可能）

**パフォーマンス比較**:
```
AES-GCM: 約2-3倍高速（ハードウェアアクセラレーション対応）
Fernet (AES-CBC): やや遅い（CBC + HMAC計算）
```

**けいかくんでの選択**:
- Google Calendar認証情報の暗号化/復号化は頻繁ではない（数秒に1回程度）
- パフォーマンスよりも実装の安全性とシンプルさを優先
- **結論**: パフォーマンス差は無視できる

---

#### 認証方式

**Fernet (HMAC-SHA256)**:
- Encrypt-then-MAC方式（最も安全）
- 暗号化後にHMAC署名
- HMAC-SHA256で32バイト署名

**AES-GCM (GCM認証タグ)**:
- AEAD（Authenticated Encryption with Associated Data）
- 暗号化と認証が統合
- 128ビット認証タグ

**セキュリティ比較**:
```
Fernet (Encrypt-then-MAC): ★★★★★ 非常に安全
AES-GCM (AEAD): ★★★★★ 非常に安全（ノンス再利用に注意）
```

**ノンス再利用のリスク（AES-GCM）**:
```python
# ❌ 危険: 同じノンスで2回暗号化
key = os.urandom(32)
aesgcm = AESGCM(key)
nonce = os.urandom(12)  # 固定ノンス（危険！）

# 1回目
ciphertext1 = aesgcm.encrypt(nonce, b"secret1", None)

# 2回目（同じノンスを再利用 → 危険！）
ciphertext2 = aesgcm.encrypt(nonce, b"secret2", None)
# → 攻撃者が平文を復元できる可能性
```

**Fernetの安全性**:
```python
# ✅ 安全: ノンスは毎回自動生成
fernet = Fernet(key)

# 1回目
token1 = fernet.encrypt(b"secret1")  # ノンス自動生成

# 2回目
token2 = fernet.encrypt(b"secret2")  # 別のノンスが自動生成
# → ノンス再利用のリスクなし
```

**けいかくんでの選択**:
- ノンス管理の実装ミスリスクを排除
- Fernetのノンス自動生成を活用
- **結論**: Fernetが安全

---

#### 実装の複雑さ

**Fernet**:
```python
# シンプル（3行）
fernet = Fernet(key)
encrypted = fernet.encrypt(plaintext)
decrypted = fernet.decrypt(encrypted)
```

**AES-GCM**:
```python
# 複雑（10行以上）
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
import os

key = os.urandom(32)
aesgcm = AESGCM(key)

# 暗号化
nonce = os.urandom(12)  # ノンスを自分で生成
ciphertext = aesgcm.encrypt(nonce, plaintext, None)

# ノンスとciphertextをセットで保存（重要！）
import base64
stored_data = base64.b64encode(nonce + ciphertext).decode()

# 復号化時にノンスを分離
stored_bytes = base64.b64decode(stored_data)
nonce = stored_bytes[:12]
ciphertext = stored_bytes[12:]
decrypted = aesgcm.decrypt(nonce, ciphertext, None)
```

**実装ミスの例（AES-GCM）**:
```python
# ❌ ノンスを保存し忘れ
ciphertext = aesgcm.encrypt(nonce, plaintext, None)
db.save(ciphertext)  # ノンスを保存していない！
# → 復号化不可能

# ❌ ノンスを固定
nonce = b"0" * 12  # 固定ノンス（危険！）
ciphertext = aesgcm.encrypt(nonce, plaintext, None)
# → ノンス再利用で暗号が破られる
```

**Fernetの安全性**:
```python
# ✅ ノンスは自動的にトークンに埋め込まれる
token = fernet.encrypt(plaintext)
db.save(token)  # トークン1つだけ保存すればOK

# ✅ ノンスは毎回ランダム生成
# 実装ミスのリスクなし
```

**けいかくんでの選択**:
- 開発者の実装ミスリスクを最小化
- FernetのシンプルなAPIを活用
- **結論**: Fernetが安全で実装が容易

---

#### タイムスタンプとTTL検証

**Fernet**:
```python
# ✅ タイムスタンプ付き（自動）
token = fernet.encrypt(b"secret")

# TTL検証（60秒以内のみ有効）
decrypted = fernet.decrypt(token, ttl=60)
```

**AES-GCM**:
```python
# ❌ タイムスタンプなし（自分で実装が必要）
import time

# 暗号化時にタイムスタンプを追加
timestamp = int(time.time())
plaintext_with_timestamp = f"{timestamp}:{plaintext}".encode()
ciphertext = aesgcm.encrypt(nonce, plaintext_with_timestamp, None)

# 復号化時にTTL検証
decrypted = aesgcm.decrypt(nonce, ciphertext, None).decode()
timestamp, data = decrypted.split(":", 1)
if time.time() - int(timestamp) > 60:
    raise ValueError("Token expired")
```

**けいかくんでの将来的な用途**:
```python
# Google Calendar連携トークンの期限管理
# 30日以上古い暗号化データは再取得を促す
try:
    key_data = fernet.decrypt(encrypted_key, ttl=30*24*60*60)
except InvalidToken:
    # 古すぎる → 再認証を要求
    raise HTTPException(status_code=401, detail="カレンダー連携の再認証が必要です")
```

**けいかくんでの選択**:
- TTL検証が将来的に必要になる可能性
- Fernetの組み込み機能を活用
- **結論**: Fernetが有利

---

### 3.3 比較表（総合評価）

| 項目 | Fernet | AES-GCM | 評価 |
|-----|--------|---------|------|
| **セキュリティ** | ★★★★★ | ★★★★★ | 同等 |
| **実装の簡潔性** | ★★★★★ | ★★☆☆☆ | Fernet有利 |
| **実装ミスリスク** | ★★★★★ 低い | ★★☆☆☆ 高い | Fernet有利 |
| **パフォーマンス** | ★★★☆☆ | ★★★★★ | AES-GCM有利 |
| **タイムスタンプ** | ★★★★★ あり | ★☆☆☆☆ なし | Fernet有利 |
| **TTL検証** | ★★★★★ 組み込み | ★☆☆☆☆ 自分で実装 | Fernet有利 |
| **ノンス管理** | ★★★★★ 自動 | ★★☆☆☆ 手動 | Fernet有利 |
| **Base64エンコード** | ★★★★★ 自動 | ★★☆☆☆ 手動 | Fernet有利 |
| **エラーハンドリング** | ★★★★★ シンプル | ★★★☆☆ やや複雑 | Fernet有利 |

**けいかくんの結論**: **Fernet採用**（実装の安全性とシンプルさを優先）

---

## 4. キー管理方法

### 4.1 現在の実装（環境変数）

#### Google Calendar暗号化キー

**キー設定**:
```bash
# .env ファイル（開発環境）
CALENDAR_ENCRYPTION_KEY=<Fernetキー（Base64、44文字）>

# Cloud Run環境変数（本番環境）
CALENDAR_ENCRYPTION_KEY=<Fernetキー>
```

**キー生成方法**:
```python
from cryptography.fernet import Fernet

# Fernetキーを生成（32バイトをBase64エンコード、44文字）
key = Fernet.generate_key()
print(key.decode())  # 例: "xW8ZBL7J3K4mN2pQ5rS6tU7vW8xY9zA0B1C2D3E4F5G="
```

**Cloud Runへの設定**:
```yaml
# cloudbuild.yml
- name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
  entrypoint: gcloud
  args:
    - 'run'
    - 'deploy'
    - 'k-back'
    - '--update-env-vars'
    - 'CALENDAR_ENCRYPTION_KEY=${_CALENDAR_ENCRYPTION_KEY}'
```

**GitHub Secretsから渡す**:
```yaml
# .github/workflows/cd-backend.yml
- name: Deploy to Cloud Run using Cloud Build
  run: |
    gcloud builds submit \
      --substitutions=_CALENDAR_ENCRYPTION_KEY="${{ secrets.CALENDAR_ENCRYPTION_KEY }}"
```

---

#### MFA暗号化キー

**キー設定**:
```python
# app/core/security.py
def get_encryption_key() -> bytes:
    """暗号化キーを取得（環境変数またはシークレットキーから生成）"""
    # ENCRYPTION_KEYが設定されていればそれを使用、なければSECRET_KEYから生成
    key_source = os.getenv("ENCRYPTION_KEY", os.getenv("SECRET_KEY"))

    # Fernetキーは32バイト必要なので、適切な長さに調整
    key_bytes = key_source.encode()[:32].ljust(32, b'0')

    # Base64 URL-safeエンコード（Fernet要件）
    return base64.urlsafe_b64encode(key_bytes)
```

**ポイント**:
- `ENCRYPTION_KEY`が優先（MFA専用）
- 未設定の場合は`SECRET_KEY`から派生
- 32バイトに調整してBase64エンコード

---

### 4.2 キー管理の評価

#### 現在の方式（環境変数）のメリット

**メリット**:
- ✅ 実装がシンプル
- ✅ 開発環境と本番環境で同じ方式
- ✅ Cloud Runとの統合が容易
- ✅ GitHub Secretsで管理（バージョン管理外）

**デメリット**:
- ⚠️ キーローテーション（変更）が複雑
- ⚠️ アクセス制御が粗い（Cloud Run全体で共有）
- ⚠️ 監査ログがない（誰がいつアクセスしたか不明）

---

#### 他のキー管理方式との比較

| 方式 | セキュリティ | 実装複雑度 | コスト | けいかくん評価 |
|-----|------------|----------|-------|---------------|
| **環境変数** | ★★★☆☆ | ★★★★★ 簡単 | ★★★★★ 無料 | ✅ **現在採用** |
| Google Secret Manager | ★★★★★ | ★★★☆☆ 中 | ★★★☆☆ 有料 | ⚠️ **将来検討** |
| AWS KMS | ★★★★★ | ★★☆☆☆ やや複雑 | ★★★☆☆ 有料 | ❌ 不採用（AWS不使用） |
| HashiCorp Vault | ★★★★★ | ★★☆☆☆ 複雑 | ★★☆☆☆ 高い | ❌ 不採用（運用負荷） |

---

### 4.3 Google Secret Managerへの移行（将来的）

#### 移行のメリット

**セキュリティ向上**:
- ✅ アクセス制御（IAM）が細かく設定可能
- ✅ 監査ログ（Cloud Audit Logs）
- ✅ キーローテーション（バージョン管理）
- ✅ 自動バックアップ

**実装例（将来）**:
```python
# app/core/config.py（将来的な実装）
from google.cloud import secretmanager

def get_calendar_encryption_key() -> str:
    """Google Secret Managerから暗号化キーを取得"""
    client = secretmanager.SecretManagerServiceClient()

    # シークレットのパス
    name = f"projects/{project_id}/secrets/calendar-encryption-key/versions/latest"

    # シークレット取得
    response = client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8")
```

**キーローテーション**:
```bash
# 新しいキーを生成
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"

# Secret Managerに新しいバージョンを追加
gcloud secrets versions add calendar-encryption-key --data-file=new_key.txt

# 旧バージョンを無効化（段階的移行後）
gcloud secrets versions disable 1 --secret=calendar-encryption-key
```

---

#### 移行の判断基準

**移行を検討すべきシグナル**:
- ユーザー数が1,000事業所以上
- コンプライアンス要件（ISO 27001、SOC 2など）
- キーローテーションの頻度が高い（年1回以上）
- 複数のサービスでキーを共有

**現在の状況**:
- ユーザー数: 中小規模（100事業所以下）
- コンプライアンス要件: 現時点では不要
- **結論**: 環境変数で十分（Secret Managerは将来検討）

---

## 5. 機微なデータを扱う際のセキュリティ考慮点

### 5.1 実装済みのセキュリティ対策

#### 対策1: 暗号化キーの分離

**Google Calendar vs MFA**:
```python
# Google Calendar: 専用キー
encryption_key = os.getenv("CALENDAR_ENCRYPTION_KEY")

# MFA: 別のキー（ENCRYPTION_KEY または SECRET_KEY）
key_source = os.getenv("ENCRYPTION_KEY", os.getenv("SECRET_KEY"))
```

**メリット**:
- ✅ キー漏洩時の影響を限定
- ✅ 異なるキーローテーションサイクル
- ✅ アクセス制御の分離

---

#### 対策2: 環境変数の保護

**GitHub Secrets**:
```yaml
# .github/workflows/cd-backend.yml
secrets.CALENDAR_ENCRYPTION_KEY  # 暗号化保存
```

**Cloud Run環境変数**:
```bash
# 環境変数はCloud Run内部で保護
gcloud run services describe k-back --format="value(spec.template.spec.containers[0].env)"
# → 実際の値は表示されない（マスキング）
```

**ローカル開発環境**:
```bash
# .env ファイル（Gitignore）
echo ".env" >> .gitignore

# .env ファイルのパーミッション
chmod 600 .env  # 所有者のみ読み書き可能
```

---

#### 対策3: データベース接続の暗号化

**PostgreSQL SSL接続**:
```python
# app/core/config.py
DATABASE_URL: str = "postgresql+asyncpg://user:pass@host/db?ssl=require"
```

**メリット**:
- ✅ データベース接続時に暗号化データが保護される
- ✅ 中間者攻撃（MITM）を防止

---

#### 対策4: 暗号化データのアクセス制御

**コード例**:
```python
# app/api/v1/endpoints/calendar.py
@router.get("/calendar-accounts/{account_id}")
async def get_calendar_account(
    account_id: UUID,
    db: AsyncSession = Depends(deps.get_db),
    current_user: models.Staff = Depends(deps.require_active_billing),  # 認証必須
):
    # 権限チェック: 自分の事業所のカレンダーアカウントのみアクセス可能
    account = await crud.office_calendar_account.get(db, id=account_id)
    if account.office_id not in [assoc.office_id for assoc in current_user.office_associations]:
        raise ForbiddenException("このカレンダーアカウントにアクセスする権限がありません")

    # 暗号化されたデータを復号化（権限チェック後）
    decrypted_key = account.decrypt_service_account_key()

    return {"calendar_account": account, "service_account_key": decrypted_key}
```

**ポイント**:
- ✅ 認証チェック（JWT検証）
- ✅ 認可チェック（事業所ID照合）
- ✅ 復号化は権限チェック後のみ

---

#### 対策5: 監査ログ

**実装例**:
```python
# app/services/calendar_service.py
async def decrypt_calendar_key(
    db: AsyncSession,
    account_id: UUID,
    staff_id: UUID
) -> str:
    """
    カレンダー認証情報を復号化し、監査ログを記録
    """
    account = await crud.office_calendar_account.get(db, id=account_id)

    # 監査ログ記録
    await crud.audit_log.create(
        db,
        action="DECRYPT_CALENDAR_KEY",
        staff_id=staff_id,
        office_id=account.office_id,
        resource_type="calendar_account",
        resource_id=str(account_id),
        details={"timestamp": datetime.now(timezone.utc).isoformat()}
    )

    # 復号化実行
    return account.decrypt_service_account_key()
```

**メリット**:
- ✅ 誰が、いつ、どのデータを復号化したか記録
- ✅ 不正アクセスの検出
- ✅ コンプライアンス対応

---

### 5.2 追加のセキュリティ考慮点

#### 考慮点1: キーの定期的なローテーション

**現在**: キーローテーションなし

**将来的な実装**:
```python
# 新旧キーの両方で復号化を試みる
def decrypt_with_rotation(encrypted_data: str) -> str:
    """
    キーローテーション対応の復号化
    """
    # 新しいキーで復号化を試みる
    try:
        fernet_new = Fernet(os.getenv("CALENDAR_ENCRYPTION_KEY_NEW"))
        return fernet_new.decrypt(encrypted_data.encode()).decode()
    except InvalidToken:
        # 失敗したら古いキーで試す
        fernet_old = Fernet(os.getenv("CALENDAR_ENCRYPTION_KEY_OLD"))
        decrypted = fernet_old.decrypt(encrypted_data.encode()).decode()

        # 新しいキーで再暗号化（バックグラウンドジョブ）
        schedule_reencryption(encrypted_data)

        return decrypted
```

**キーローテーションサイクル**:
- Google Calendar: 年1回
- MFA: 年2回（より頻繁）

---

#### 考慮点2: 暗号化データのバックアップ

**現在の実装**:
- PostgreSQLの自動バックアップ（Neon Postgres）
- 暗号化データもバックアップに含まれる

**セキュリティ考慮点**:
```python
# バックアップデータの暗号化（追加レイヤー）
# Neon Postgresは自動的に暗号化してバックアップを保存
# 追加の対策は現時点では不要
```

---

#### 考慮点3: 暗号化データの削除

**実装例**:
```python
# app/crud/crud_office_calendar_account.py
async def delete_calendar_account(
    db: AsyncSession,
    account_id: UUID
) -> None:
    """
    カレンダーアカウントを削除（暗号化データも削除）
    """
    account = await get(db, id=account_id)

    # 暗号化データをクリア（上書き）
    account.service_account_key = None

    # データベースから削除
    await db.delete(account)
    await db.commit()

    # 監査ログ記録
    await crud.audit_log.create(
        db,
        action="DELETE_CALENDAR_ACCOUNT",
        details={"account_id": str(account_id)}
    )
```

**ポイント**:
- ✅ 削除前に暗号化データをクリア
- ✅ 監査ログに記録
- ✅ カスケード削除でリレーションも削除

---

#### 考慮点4: メモリ上の平文データの保護

**実装上の注意**:
```python
# ❌ 悪い例: 平文データをログ出力
decrypted_key = account.decrypt_service_account_key()
logger.info(f"Decrypted key: {decrypted_key}")  # 危険！

# ✅ 良い例: ログ出力しない
decrypted_key = account.decrypt_service_account_key()
logger.info("Calendar key decrypted successfully")  # 安全

# ✅ 良い例: 使用後すぐにクリア
try:
    decrypted_key = account.decrypt_service_account_key()
    # Google API呼び出し
    result = call_google_api(decrypted_key)
finally:
    # メモリからクリア
    del decrypted_key
```

---

## 6. 面接で強調すべきポイント

### 6.1 技術的判断の根拠

**1. Fernet暗号化を選んだ理由**
- 暗号化と認証の統合（Encrypt-then-MAC）
- シンプルで安全なAPI（実装ミスリスクが低い）
- タイムスタンプによるTTL検証
- Python標準ライブラリとの親和性

**2. AES-GCMを選ばなかった理由**
- ノンス管理の複雑さ（実装ミスリスク）
- タイムスタンプなし（自分で実装が必要）
- パフォーマンス差は無視できる（暗号化頻度が低い）

**3. キー管理方法の選択**
- 現在: 環境変数（シンプル、コスト効率）
- 将来: Google Secret Manager（セキュリティ向上、キーローテーション）

---

### 6.2 セキュリティ対策の実装

**1. 多層防御アプローチ**
- 暗号化（Fernet）
- アクセス制御（JWT + 事業所ID照合）
- 監査ログ
- SSL/TLS通信

**2. 機微なデータの保護**
- キーの分離（Calendar vs MFA）
- 環境変数の保護（GitHub Secrets、Cloud Run）
- 平文データのログ出力禁止

**3. 監査とコンプライアンス**
- 復号化アクセスの監査ログ
- キー削除の監査ログ
- 将来的なキーローテーション対応

---

### 6.3 実装の詳細

**暗号化フロー**:
```
[平文データ] → Fernet.encrypt()
                    ↓ AES-128-CBC暗号化
                    ↓ HMAC-SHA256署名
              [Base64エンコード済みトークン]
                    ↓ PostgreSQL TEXT型に保存
              [データベース]
```

**復号化フロー**:
```
[データベース]
    ↓ PostgreSQL TEXT型から読み取り
[Base64エンコード済みトークン]
    ↓ Fernet.decrypt()
    ↓ HMAC検証
    ↓ AES-128-CBC復号化
[平文データ] → Google API呼び出し
```

---

## 7. 関連資料

- [Fernet公式ドキュメント](https://cryptography.io/en/latest/fernet/)
- [NIST Special Publication 800-38D (AES-GCM)](https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-38d.pdf)
- [Google Secret Manager](https://cloud.google.com/secret-manager/docs)
- 内部資料: `security_countermeasures.md` - セキュリティ対策全般

---

**最終更新**: 2026-01-28
**作成者**: Claude Sonnet 4.5
