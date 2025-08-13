フロントエンドのコーディング規約を確認するため、まずlib配下のファイル構造とコードを詳しく調べてみます。

# keikakun_front のコーディング規約（主にlib配下）

## 1. ファイル構造と命名規則

### ディレクトリ構造
```
lib/
├── api/           # API通信関連
│   ├── auth/      # 認証関連API
│   └── *.ts       # 機能別API
├── transformers/  # データ変換処理
├── utils.ts       # 汎用ユーティリティ
├── validate.ts    # バリデーション定義
├── errorMessages.ts # エラーメッセージ管理
└── supportPlanUtils.ts # 支援計画関連ユーティリティ
```

### ファイル命名規則
- **キャメルケース**: `supportPlanUtils.ts`
- **機能別**: 機能名を明確に表現（例：`dashboard.ts`, `recipient.ts`）

## 2. インポート・エクスポート規則

### インポート順序
```typescript
// 1. 外部ライブラリ
import { z } from 'zod';
import { createClient } from '@/utils/supabase/client';

// 2. 内部型定義
import { SupportPlanCycleRead } from '@/types/backend_api';
import { DashboardData } from '@/types/dashboard';

// 3. 内部モジュール
import { ServiceRecipientDashboardRead } from '@/lib/api/dashboard';
```

### エクスポート規則
- **関数**: `export function` または `export const`
- **型・インターフェース**: `export interface` または `export type`
- **定数**: `export const`
- **Enum**: `export enum`

## 3. 関数定義とコメント

### JSDocコメント
```typescript
/**
 * 指定された利用者の個別支援計画サイクル一覧を取得する
 * @param recipientId 利用者ID
 * @returns 支援計画サイクルのリスト
 */
export const getSupportPlanCycles = async (
  recipientId: string
): Promise<SupportPlanCycleRead[]> => {
  // 実装
};
```

### 関数命名規則
- **取得系**: `get*`, `fetch*`
- **作成系**: `create*`
- **更新系**: `update*`
- **削除系**: `delete*`
- **変換系**: `transform*`

## 4. 型定義規則

### インターフェース命名
```typescript
// バックエンドAPIレスポンス用
export interface ServiceRecipientDashboardRead {
  id: string;
  first_name: string;
  // ...
}

// フロントエンド表示用
export interface DashboardData {
  recipient: {
    id: string;
    name: string;
  };
  // ...
}
```

### Enum定義
```typescript
export enum StaffRole {
  EMPLOYEE = 'employee',
  MANAGER = 'manager',
  ADMIN = 'admin',
}
```

## 5. エラーハンドリング

### エラーメッセージ管理
```typescript
// エラーメッセージの日英マッピング
export const errorMessages: { [key: string]: string } = {
  'Invalid login credentials': 'メールアドレスまたはパスワードが間違っています。',
  'Email not confirmed': 'メールアドレスが確認されていません。確認メールをご確認ください。',
};

// エラーメッセージ変換関数
export const translateError = (error: Error | AuthError): string => {
  if (error instanceof AuthError || (error && error.message)) {
    return errorMessages[error.message] || defaultErrorMessage;
  }
  return errorMessages[error.toString()] || defaultErrorMessage;
};
```

### API呼び出し時のエラーハンドリング
```typescript
if (!response.ok) {
  const errorText = await response.text();
  console.error(`Failed to fetch data. Status: ${response.status}`);
  console.error("Response body:", errorText);
  throw new Error(`データの取得に失敗しました。 Status: ${response.status}`);
}
```

## 6. バリデーション規則

### Zodスキーマ定義
```typescript
export const authFormValidate = z.object({
  email: z
    .string()
    .email({ message: 'メールアドレスが不正です' })
    .min(1, { message: 'メールアドレスは必須です' }),
  password: z
    .string()
    .min(8, { message: 'パスワードは8文字以上で入力してください' })
    .regex(/[a-z]/, { message: 'パスワードは小文字を含める必要があります' }),
});
```

## 7. データ変換規則

### バックエンド→フロントエンド変換
```typescript
export function transformBackendToFrontend(
  backendData: ServiceRecipientDashboardRead[]
): DashboardData[] {
  return backendData.map((item) => ({
    recipient: {
      id: item.id,
      name: `${item.last_name} ${item.first_name}`,
      name_phonetic: `${item.last_name_furigana} ${item.first_name_furigana}`,
    },
    dashboard_summary: item.dashboard_summary,
  }));
}
```

## 8. 認証・セッション管理

### 認証ヘッダー取得
```typescript
async function getAuthHeaders() {
  const {
    data: { session },
  } = await supabase.auth.getSession();

  if (!session) {
    throw new Error("Not authenticated");
  }
  
  return {
    "Content-Type": "application/json",
    Authorization: `Bearer ${session.access_token}`,
  };
}
```

## 9. 環境変数使用規則

### API URL取得
```typescript
const apiUrl = process.env.NEXT_PUBLIC_BACKEND_API_URL;

if (!apiUrl) {
  throw new Error("API URL is not configured.");
}
```

## 10. ログ出力規則

### デバッグログ
```typescript
console.log("Fetching support plan cycles from:", apiUrl);
console.log("Request sent. Response status:", response.status);
console.log("Recipient created successfully:", result);
```

### エラーログ
```typescript
console.error("Error in createRecipient:", error);
console.error("API Error:", errorData);
```

## 11. 定数定義規則

### マッピング定数
```typescript
export const stepToDeliverableTypeMap: {
  [key in SupportPlanStepTypeEnum]?: string;
} = {
  [SupportPlanStepTypeEnum.ASSESSMENT]: "assessment_sheet",
  [SupportPlanStepTypeEnum.DRAFT_PLAN]: "draft_plan_pdf",
};
```

### 表示名マッピング
```typescript
export const officeTypeDisplayNames: { [key in OfficeType]: string } = {
  [OfficeType.TYPE_A_OFFICE]: 'A型事業所',
  [OfficeType.TYPE_B_OFFICE]: 'B型事業所',
};
```

これらの規約により、保守性が高く、一貫性のあるコードベースが維持されています。