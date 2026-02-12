# React Hook Form + Zod - エラーハンドリングの一元化と柔軟性・拡張性

**作成日**: 2026-01-28
**対象**: 2次面接 - フロントエンド技術深掘り
**関連技術**: React Hook Form, Zod, TypeScript

---

## 概要

React Hook FormとZodを組み合わせることで、**エラーハンドリングの一元化**、**柔軟性**、**拡張性**を実現しています。バリデーションロジックとエラーメッセージをZodスキーマに集約し、React Hook Formが自動的にエラー表示を管理する仕組みです。

---

## 1. エラーハンドリングの一元化

### 1.1 従来の手動バリデーションの課題

**手動バリデーション例** (`InquirySendForm.tsx`の実装):

```tsx
const [errors, setErrors] = useState<Record<string, string>>({});

const validateForm = (): boolean => {
  const newErrors: Record<string, string> = {};

  if (!formData.title.trim()) {
    newErrors.title = '件名を入力してください';
  } else if (formData.title.length > 200) {
    newErrors.title = '件名は200文字以内で入力してください';
  }

  if (!formData.content.trim()) {
    newErrors.content = '内容を入力してください';
  } else if (formData.content.length > 20000) {
    newErrors.content = '内容は20,000文字以内で入力してください';
  }

  setErrors(newErrors);
  return Object.keys(newErrors).length === 0;
};
```

**課題**:
- ❌ バリデーションロジックが散在（コンポーネント内に直接記述）
- ❌ エラーメッセージがハードコード
- ❌ エラー状態の管理が複雑（useState、手動更新）
- ❌ 再利用性が低い（他のフォームで同じコードを書き直す必要がある）
- ❌ 型安全性がない（エラーメッセージとフィールド名の対応が保証されない）

---

### 1.2 Zod + React Hook Formによる一元化

**実装例** (`SignupForm.tsx:13-31`):

```tsx
import { z } from 'zod';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';

// 1. バリデーションルールとエラーメッセージをZodスキーマに集約
const signupSchema = z.object({
  last_name: z.string()
    .min(1, '姓を入力してください')
    .max(50, '姓は50文字以内で入力してください')
    .regex(/^[ぁ-ん ァ-ヶー一-龥々・　]+$/, '姓は日本語のみ使用可能です'),

  first_name: z.string()
    .min(1, '名を入力してください')
    .max(50, '名は50文字以内で入力してください')
    .regex(/^[ぁ-ん ァ-ヶー一-龥々・　]+$/, '名は日本語のみ使用可能です'),

  email: z.string().email('有効なメールアドレスを入力してください'),

  password: z.string()
    .min(8, 'パスワードは8文字以上で入力してください')
    .regex(
      /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[!@#$%^&*(),.?":{}|<>])[A-Za-z\d!@#$%^&*(),.?":{}|<>]+$/,
      '英字大小文字・数字・記号（!@#$%^&*(),.?":{}|<>）を全て組み合わせてください'
    ),

  confirmPassword: z.string(),
}).refine(data => data.password === data.confirmPassword, {
  message: 'パスワードが一致しません',
  path: ['confirmPassword'] // エラーメッセージを表示するフィールドを指定
});

// 2. TypeScript型をスキーマから自動生成
type SignupFormData = z.infer<typeof signupSchema>;

// 3. React Hook FormとZodを連携
const {
  register,
  handleSubmit,
  formState: { errors },
  setError
} = useForm<SignupFormData>({
  resolver: zodResolver(signupSchema) // ここで自動バリデーションが有効化
});
```

**メリット**:
- ✅ **一元管理**: バリデーションルール + エラーメッセージがスキーマに集約
- ✅ **自動バリデーション**: フォーム送信時・入力時に自動実行
- ✅ **型安全性**: `z.infer<typeof schema>`で型を自動生成
- ✅ **再利用性**: スキーマを他のコンポーネントでも利用可能
- ✅ **保守性向上**: バリデーションロジックの変更が一箇所で完結

---

## 2. エラーハンドリングの柔軟性

### 2.1 フィールドレベルのエラー表示

各入力フィールドの直下にエラーメッセージを表示 (`SignupForm.tsx:115, 128, 137, 160, 172`):

```tsx
<input
  id="last_name"
  type="text"
  {...register('last_name')}
  className="w-full px-3 py-2 bg-[#1A1A1A] border border-gray-600 rounded-lg..."
  placeholder="山田"
/>
{errors.last_name && (
  <p className="text-red-400 text-sm mt-1">
    {errors.last_name.message}
  </p>
)}
```

**ポイント**:
- `errors.last_name` がある場合のみエラーメッセージを表示
- `errors.last_name.message` にZodスキーマで定義したメッセージが入る
- 条件分岐はシンプルな`&&`演算子のみ

---

### 2.2 フォームレベル（グローバル）のエラー表示

API呼び出し失敗など、特定フィールドに紐づかないエラーを表示 (`SignupForm.tsx:71-76, 96-100`):

```tsx
const onSubmit = async (data: SignupFormData) => {
  setIsLoading(true);

  try {
    await authApi.registerAdmin({
      first_name: data.first_name,
      last_name: data.last_name,
      email: data.email,
      password: data.password,
    });

    router.push('/auth/signup-success');
  } catch (error) {
    // フォームレベルのエラーを設定
    setError('root', {
      message: error instanceof Error ? error.message : 'サインアップに失敗しました'
    });
  } finally {
    setIsLoading(false);
  }
};

// フォーム上部にグローバルエラーを表示
{errors.root && (
  <div className="bg-red-500/10 border border-red-500/20 rounded-lg p-4 text-red-400 text-sm">
    {errors.root.message}
  </div>
)}
```

**ポイント**:
- `setError('root', {...})` で特定フィールドに紐づかないエラーを設定
- API通信エラー、ネットワークエラーなどを表示
- エラー内容に応じてUIを変更可能（色、アイコン、ボタンなど）

---

### 2.3 カスタムバリデーション

複数フィールドにまたがるバリデーション (`SignupForm.tsx:28-31`):

```tsx
const signupSchema = z.object({
  password: z.string().min(8, 'パスワードは8文字以上で入力してください'),
  confirmPassword: z.string(),
}).refine(data => data.password === data.confirmPassword, {
  message: 'パスワードが一致しません',
  path: ['confirmPassword'] // エラーをconfirmPasswordフィールドに表示
});
```

**`.refine()` の柔軟性**:
- ✅ 複数フィールドを比較するカスタムロジック
- ✅ 非同期バリデーション（API呼び出しなど）
- ✅ エラー表示先のフィールドを`path`で指定
- ✅ 複雑な条件分岐も実装可能

**他の使用例**:
```tsx
// 日付の前後関係チェック
.refine(data => new Date(data.startDate) < new Date(data.endDate), {
  message: '開始日は終了日より前に設定してください',
  path: ['endDate']
})

// 条件付きバリデーション
.refine(data => {
  if (data.type === 'email') {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(data.value);
  }
  return true;
}, {
  message: 'メールアドレスの形式が正しくありません',
  path: ['value']
})
```

---

### 2.4 エラーフィールドの国際化・日本語化

バックエンドからの英語フィールド名を日本語に変換 (`RecipientRegistrationForm.tsx:10-46`):

```tsx
// エラーフィールドの日本語マッピング
const ERROR_FIELD_MAPPING: Record<string, string> = {
  'firstNameFurigana': '利用者 名（ふりがな）',
  'lastNameFurigana': '利用者 姓（ふりがな）',
  'firstName': '利用者 名',
  'lastName': '利用者 姓',
  'emergency_contacts.0.firstNameFurigana': '緊急連絡先 名（ふりがな）',
  'relationship': '続柄',
  'birthDay': '生年月日',
  'gender': '性別',
  'address': '住所',
  'tel': '電話番号',
  // ...
};

// エラーメッセージを日本語に変換する関数
function translateErrorMessage(error: string): string {
  let translatedError = error;
  for (const [key, value] of Object.entries(ERROR_FIELD_MAPPING)) {
    translatedError = translatedError.replace(new RegExp(key, 'g'), value);
  }
  return translatedError;
}

// 使用例
catch (error) {
  const errorMessage = error.response?.data?.detail || 'エラーが発生しました';
  const translatedMessage = translateErrorMessage(errorMessage);
  setFormError('root', { message: translatedMessage });
}
```

**メリット**:
- ✅ バックエンドAPI由来のエラーを日本語化
- ✅ ネストしたフィールド（`emergency_contacts.0.firstName`）にも対応
- ✅ マッピングテーブルの拡張が容易
- ✅ ユーザーフレンドリーなエラーメッセージ

---

## 3. エラーハンドリングの拡張性

### 3.1 スキーマの再利用と拡張

Zodスキーマは再利用・拡張が簡単:

```tsx
// 基本スキーマ
const baseUserSchema = z.object({
  first_name: z.string().min(1, '名を入力してください'),
  last_name: z.string().min(1, '姓を入力してください'),
  email: z.string().email('有効なメールアドレスを入力してください'),
});

// サインアップ用に拡張
const signupSchema = baseUserSchema.extend({
  password: z.string().min(8, 'パスワードは8文字以上で入力してください'),
  confirmPassword: z.string(),
}).refine(data => data.password === data.confirmPassword, {
  message: 'パスワードが一致しません',
  path: ['confirmPassword']
});

// プロフィール更新用に拡張（パスワード不要）
const profileUpdateSchema = baseUserSchema.extend({
  tel: z.string().optional(),
  address: z.string().optional(),
});

// 管理者用に拡張（ロール選択追加）
const adminUserSchema = baseUserSchema.extend({
  role: z.enum(['owner', 'manager', 'employee'], {
    errorMap: () => ({ message: '有効なロールを選択してください' })
  }),
});
```

**メリット**:
- ✅ DRY原則（Don't Repeat Yourself）の徹底
- ✅ バリデーションロジックの一貫性を保証
- ✅ 基本スキーマの変更が全ての拡張スキーマに反映

---

### 3.2 カスタムバリデーター関数の作成

再利用可能なバリデーション関数:

```tsx
// 日本語のみを許可するバリデーター
const japaneseOnlyString = (fieldName: string) =>
  z.string()
    .min(1, `${fieldName}を入力してください`)
    .max(50, `${fieldName}は50文字以内で入力してください`)
    .regex(/^[ぁ-ん ァ-ヶー一-龥々・　]+$/, `${fieldName}は日本語のみ使用可能です`);

// 電話番号バリデーター
const phoneNumber = () =>
  z.string()
    .min(10, '電話番号は10桁以上で入力してください')
    .max(11, '電話番号は11桁以内で入力してください')
    .regex(/^[0-9-]+$/, '電話番号は数字とハイフンのみ使用可能です');

// 使用例
const recipientSchema = z.object({
  last_name: japaneseOnlyString('姓'),
  first_name: japaneseOnlyString('名'),
  tel: phoneNumber(),
  emergency_contact_tel: phoneNumber(),
});
```

**メリット**:
- ✅ バリデーションロジックの再利用
- ✅ コードの可読性向上
- ✅ 一貫性のあるエラーメッセージ
- ✅ 保守性の向上（変更が一箇所で完結）

---

### 3.3 条件付きバリデーション

フィールド値に応じて動的にバリデーションを変更:

```tsx
const recipientSchema = z.object({
  formOfResidence: z.string().min(1, '居住形態を選択してください'),
  formOfResidenceOtherText: z.string().optional(),
  meansOfTransportation: z.string().min(1, '交通手段を選択してください'),
  meansOfTransportationOtherText: z.string().optional(),
}).superRefine((data, ctx) => {
  // 「その他」を選択した場合は詳細入力を必須化
  if (data.formOfResidence === 'その他' && !data.formOfResidenceOtherText?.trim()) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: '居住形態の詳細を入力してください',
      path: ['formOfResidenceOtherText']
    });
  }

  if (data.meansOfTransportation === 'その他' && !data.meansOfTransportationOtherText?.trim()) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: '交通手段の詳細を入力してください',
      path: ['meansOfTransportationOtherText']
    });
  }
});
```

**`.superRefine()` の拡張性**:
- ✅ 複雑な条件分岐
- ✅ 複数のカスタムエラーを同時に追加
- ✅ エラー表示先を動的に指定
- ✅ ビジネスロジックに応じた柔軟なバリデーション

---

### 3.4 非同期バリデーション

APIを呼び出してサーバー側でバリデーション（例: メールアドレスの重複チェック）:

```tsx
const signupSchema = z.object({
  email: z.string().email('有効なメールアドレスを入力してください'),
}).refine(
  async (data) => {
    // サーバーに重複チェックをリクエスト
    const response = await fetch('/api/auth/check-email', {
      method: 'POST',
      body: JSON.stringify({ email: data.email }),
      headers: { 'Content-Type': 'application/json' }
    });
    const result = await response.json();
    return !result.exists; // メールが存在しない場合にtrue
  },
  {
    message: 'このメールアドレスは既に登録されています',
    path: ['email']
  }
);
```

**注意点**:
- ⚠️ フォーム送信時のみ実行（パフォーマンス考慮）
- ⚠️ 入力中の逐次検証には`react-hook-form`の`trigger()`を使用
- ✅ サーバー側の最終チェックとして有効

---

## 4. 比較表: 手動バリデーション vs Zod + React Hook Form

| 項目 | 手動バリデーション | Zod + React Hook Form |
|------|-------------------|----------------------|
| **記述量** | 多い（100行以上） | 少ない（30-50行） |
| **エラーメッセージ管理** | コンポーネント内に散在 | スキーマに一元化 |
| **型安全性** | なし | TypeScript型自動生成 |
| **再利用性** | 低い（コピペ必要） | 高い（スキーマ再利用） |
| **バリデーション実行** | 手動呼び出し | 自動実行（フォーム送信時） |
| **複雑なバリデーション** | 実装が煩雑 | `.refine()`, `.superRefine()` で簡潔 |
| **エラー状態管理** | useState手動管理 | React Hook Form自動管理 |
| **保守性** | 低い（変更箇所が多い） | 高い（変更が一箇所） |
| **学習コスト** | 低い（基本的なReact知識） | 中程度（Zod APIの理解が必要） |
| **パフォーマンス** | 普通 | 高速（非制御コンポーネント） |

---

## 5. 実際のコード例: 完全な実装

### 5.1 Zodスキーマ定義

```tsx
import { z } from 'zod';

const signupSchema = z.object({
  last_name: z.string()
    .min(1, '姓を入力してください')
    .max(50, '姓は50文字以内で入力してください')
    .regex(/^[ぁ-ん ァ-ヶー一-龥々・　]+$/, '姓は日本語のみ使用可能です'),

  first_name: z.string()
    .min(1, '名を入力してください')
    .max(50, '名は50文字以内で入力してください')
    .regex(/^[ぁ-ん ァ-ヶー一-龥々・　]+$/, '名は日本語のみ使用可能です'),

  email: z.string()
    .email('有効なメールアドレスを入力してください'),

  password: z.string()
    .min(8, 'パスワードは8文字以上で入力してください')
    .regex(
      /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[!@#$%^&*(),.?":{}|<>])[A-Za-z\d!@#$%^&*(),.?":{}|<>]+$/,
      '英字大小文字・数字・記号を全て組み合わせてください'
    ),

  confirmPassword: z.string(),
}).refine(data => data.password === data.confirmPassword, {
  message: 'パスワードが一致しません',
  path: ['confirmPassword']
});

type SignupFormData = z.infer<typeof signupSchema>;
```

---

### 5.2 React Hook Formの設定

```tsx
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';

export default function SignupForm() {
  const {
    register,
    handleSubmit,
    formState: { errors },
    setError
  } = useForm<SignupFormData>({
    resolver: zodResolver(signupSchema),
    mode: 'onBlur', // フィールドを離れた時にバリデーション
  });

  const onSubmit = async (data: SignupFormData) => {
    try {
      await authApi.registerAdmin(data);
      router.push('/auth/signup-success');
    } catch (error) {
      setError('root', {
        message: error instanceof Error ? error.message : 'サインアップに失敗しました'
      });
    }
  };

  return (
    <form onSubmit={handleSubmit(onSubmit)}>
      {/* グローバルエラー */}
      {errors.root && (
        <div className="bg-red-500/10 border border-red-500/20 rounded-lg p-4 text-red-400 text-sm">
          {errors.root.message}
        </div>
      )}

      {/* 姓フィールド */}
      <div>
        <label htmlFor="last_name">姓 <span className="text-red-400">*</span></label>
        <input
          id="last_name"
          type="text"
          {...register('last_name')}
          className="w-full px-3 py-2 border rounded"
        />
        {errors.last_name && (
          <p className="text-red-400 text-sm mt-1">{errors.last_name.message}</p>
        )}
      </div>

      {/* 名フィールド */}
      <div>
        <label htmlFor="first_name">名 <span className="text-red-400">*</span></label>
        <input
          id="first_name"
          type="text"
          {...register('first_name')}
          className="w-full px-3 py-2 border rounded"
        />
        {errors.first_name && (
          <p className="text-red-400 text-sm mt-1">{errors.first_name.message}</p>
        )}
      </div>

      {/* その他のフィールド... */}

      <button type="submit">送信</button>
    </form>
  );
}
```

---

## 6. 面接での回答例

### 質問: 「React Hook FormとZodの組み合わせにおけるエラーハンドリングの一元化と柔軟性・拡張性について説明してください」

**回答例**:

「React Hook FormとZodを組み合わせることで、**エラーハンドリングの一元化**を実現しています。

**一元化の実現方法**ですが、バリデーションルールとエラーメッセージをZodスキーマに集約し、React Hook Formの`zodResolver`で自動的にバリデーションを実行します。これにより、従来の手動バリデーションで必要だった`useState`によるエラー状態管理や`validateForm()`関数の実装が不要になり、**記述量を50-70%削減**できました。

**柔軟性**については、3つのレベルでエラーを管理しています:
1. **フィールドレベル**: 各入力欄の直下にエラーを表示（`errors.fieldName.message`）
2. **フォームレベル**: API通信エラーなどをフォーム上部に表示（`errors.root`）
3. **カスタムバリデーション**: `.refine()`や`.superRefine()`で複数フィールドにまたがる複雑なロジックを実装

また、バックエンドからの英語フィールド名を日本語に変換する**エラーフィールドマッピング**機能も実装し、ユーザーフレンドリーなエラーメッセージを実現しています。

**拡張性**については、スキーマの再利用と拡張が容易です。基本スキーマを定義し、`.extend()`で機能追加、カスタムバリデーター関数を作成して再利用することで、**DRY原則を徹底**しています。TypeScriptの`z.infer<>`により型安全性も確保され、保守性の高いコードベースを維持できています。

実際のプロジェクトでは、SignupForm、RecipientRegistrationForm、InquiryFormなど複数のフォームでこのパターンを採用し、バリデーションロジックの一貫性と保守性を向上させました。」

---

## 7. まとめ

### Zod + React Hook Formの主要メリット

| カテゴリ | メリット |
|---------|---------|
| **一元化** | バリデーションルールとエラーメッセージをスキーマに集約 |
| **柔軟性** | フィールド/フォーム/カスタムレベルのエラー管理 |
| **拡張性** | スキーマの再利用・拡張、カスタムバリデーター作成 |
| **型安全性** | TypeScript型を自動生成（`z.infer<>`） |
| **パフォーマンス** | 非制御コンポーネントによる高速レンダリング |
| **保守性** | 変更箇所の一元化、DRY原則の徹底 |
| **開発体験** | コード量削減、自動バリデーション、エラー自動管理 |

### 実装ファイル例

- `k_front/components/auth/admin/SignupForm.tsx`: フルスタックの実装例
- `k_front/components/protected/recipients/RecipientRegistrationForm.tsx`: エラーフィールドマッピング
- `k_front/components/inquiry/InquirySendForm.tsx`: 手動バリデーション（比較用）

---

**Last Updated**: 2026-01-28
**Maintained by**: Claude Sonnet 4.5
