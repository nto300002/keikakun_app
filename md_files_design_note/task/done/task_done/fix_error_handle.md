Failed to load resource: the server responded with a status of 422 (Unprocessable Entity)
name: String should have at least 5 characters

> @todo/task/fix_error_handle.md 
office_setupにて事務所名が5文字以上でなくてはいけないという制約があるが 
i18n対応しているにも関わらずそのエラーメッセージが英語になっていたこの原因 
  ⎿  Read todo/task/fix_error_handle.md (3 lines)

⏺ エラーメッセージがi18n対応しているにも関わらず英語になっている原因を調査します。まず、office_setup関
  連のファイルとバリデーションロジックを探してみましょう。

⏺ Search(pattern: "office_setup")
  ⎿  Found 1 file (ctrl+o to expand)

⏺ Search(pattern: "String should have at least 5 characters", output_mode: "content")
  ⎿  Found 2 lines (ctrl+o to expand)

⏺ Search(pattern: "name.*5.*character", output_mode: "content")
  ⎿  Found 2 lines (ctrl+o to expand)

⏺ Search(pattern: "k_back/**/*office*.py")
  ⎿  Found 13 files (ctrl+o to expand)

⏺ Search(pattern: "k_front/**/*office*.{ts,tsx}")
  ⎿  Found 19 files (ctrl+o to expand)

⏺ Read(k_back/tests/api/v1/test_office.py)
  ⎿  Read 89 lines

⏺ Read(k_back/app/schemas/office.py)
  ⎿  Read 36 lines

⏺ Read(k_front/components/OfficeSetup.tsx)
  ⎿  Read 154 lines

⏺ Read(k_front/lib/auth.ts)
  ⎿  Read 85 lines

⏺ Search(pattern: "setupOffice", output_mode: "content")
  ⎿  Found 20 lines (ctrl+o to expand)

⏺ Read(k_front/lib/http.ts)
  ⎿  Read 142 lines

⏺ 原因が特定できました。この問題は3つの要因が重なって発生しています：

  問題の原因

  1. フロントエンドとバックエンドのバリデーションルール不一致（主要因）

  フロントエンド (k_front/components/OfficeSetup.tsx:12):
  name: z.string().min(1, '事業所名を入力してください'),
  - 1文字以上の制約のみ

  バックエンド (k_back/app/schemas/office.py:10):
  name: str = Field(..., min_length=5, max_length=100)
  - 5文字以上の制約

  → フロントエンドのバリデーションでは1~4文字の事務所名が通過してしまい、バックエンドで422エラーになる

  2. バックエンドのPydanticエラーメッセージが英語

  k_back/app/schemas/office.py:10では、カスタムエラーメッセージが設定されていないため、Pydanticのデフォ
  ルトの英語メッセージ "String should have at least 5 characters" が返される

  3. フロントエンドでバックエンドのエラーを日本語化する仕組みがない

  k_front/lib/http.ts:15-31のformatErrorMessage関数では、バックエンドから返されたerr.msgをそのまま表示
  しているため、英語メッセージがそのままユーザーに表示される

  return errorData.detail
    .map((err: ValidationError) => {
      const field = err.loc[err.loc.length - 1];
      return `${field}: ${err.msg}`;  // ← err.msgが英語のまま
    })
    .join('\n');

  解決策の選択肢

  この問題を解決するには、以下のいずれかまたは組み合わせが必要です：

  1. フロントエンドのバリデーションをバックエンドに合わせる（推奨）
    - z.string().min(5, '事業所名は5文字以上で入力してください') に変更
  2. バックエンドにカスタム日本語エラーメッセージを追加
    - PydanticのFieldに日本語のエラーメッセージを設定
  3. フロントエンドでバックエンドのエラーを日本語化
    - formatErrorMessage関数でエラーメッセージをマッピング

  どの方法で修正しますか？

1