# User-Centered Design: /dashboard 視認性改善設計

## ライト / ダークモード切り替え実装メモ

実装方針:

- テーマ状態は `next-themes` の `ThemeProvider` でアプリ全体へ渡す。
- `k_front/app/layout.tsx` で `ThemeProvider` を `ToasterProvider` と protected 配下の画面より外側に配置し、`class` 属性で `html` に `dark` を付与する。
- `k_front/app/globals.css` に `@custom-variant dark (&:where(.dark, .dark *));` を定義し、Tailwind v4 の `dark:` が OS 設定ではなく `.dark` クラスに反応するようにする。
- `ThemeToggle` は `light` / `dark` のみを表示し、端末設定は削除する。
- SSR と client のテーマ判定差分で hydration mismatch が出ないように、初回 SSR では押下状態を固定し、client mount 後に `aria-pressed` と active class を反映する。

原因整理:

- ライトに切り替えてもスクロールバー以外が変わらなかった主因は、Tailwind v4 の `dark:` が既定で `@media (prefers-color-scheme: dark)` として生成され、`next-themes` が付与する `.dark` / light 切り替えと連動していなかったため。
- そのため `theme=light` にしても、OS が dark の場合は `dark:` スタイルが残り続け、画面本体は暗色のままになっていた。
- `@custom-variant dark` により、`dark:` を `.dark` クラス制御へ変更して解消する。

recipients 配下の適用範囲:

- `k_front/app/(protected)/recipients/page.tsx`
- `k_front/app/(protected)/recipients/new/page.tsx`
- `k_front/app/(protected)/recipients/[id]/page.tsx`
- `k_front/app/(protected)/recipients/[id]/edit/page.tsx`
- `k_front/components/protected/recipients/BasicInfoSection.tsx`
- `k_front/components/protected/recipients/EmploymentSection.tsx`
- `k_front/components/protected/recipients/RecipientRegistrationForm.tsx`
- `k_front/components/protected/recipients/RecipientEditForm.tsx`
- `k_front/components/protected/recipients/forms/*.tsx`

recipients での修正方針:

- ページ背景、カード背景、テーブル背景、モーダル内入力欄を `bg-white ... dark:bg[...]` の形に統一する。
- 表示値や入力値の固定 `text-white` は `text-slate-900 dark:text-white` に変更する。
- 補助テキストの固定 `text-gray-*` は `text-slate-600 dark:text-gray-400` などに変更する。
- ボタン上の `text-white` は、緑・青・赤・濃色背景との組み合わせとして残す。

## 目的

`/dashboard` を、30〜60代の福祉職員が視覚的負荷を抑えて使える画面にする。

想定ユーザーは以下。

- 福祉職員、サービス管理責任者、管理者
- 30〜60代
- ITリテラシーにばらつきがある
- 老眼、視力低下、色の見分けづらさがある職員を含む
- 業務中に短時間で「誰を、いつまでに、何をするか」を確認する

この画面では「おしゃれさ」よりも「一目で読める」「押す場所が分かる」「期限の危険度が色以外でも分かる」を優先する。

## 対象コード

- ルート: `k_front/app/(protected)/dashboard/page.tsx`
- 主要コンポーネント: `k_front/components/protected/dashboard/Dashboard.tsx`
- 選択中フィルター: `k_front/components/protected/dashboard/ActiveFilters.tsx`
- API取得: `k_front/lib/dashboard.ts`
- 型定義: `k_front/types/dashboard.ts`
- ローディング表示: `k_front/components/ui/table-loading-overlay.tsx`

`/dashboard/page.tsx` は `Dashboard` を返すだけなので、UI改善の主対象は `Dashboard.tsx`。

## 現状の主要課題

### 1. 全体が暗色グラデーション中心で、文字・境界・カードの差が弱い

該当箇所:

- `Dashboard.tsx:490` 画面背景が `bg-gradient-to-br from-[#1a1f2e] to-[#0f1419] text-white`
- `Dashboard.tsx:522`, `540`, `559`, `571` サマリーカードも暗色グラデーション
- `Dashboard.tsx:647` 一覧コンテナも `bg-[#0f1419cc]`
- `Dashboard.tsx:688` テーブルヘッダーも同系色

課題:

- 暗い背景の中に暗いカード・暗い表が重なり、情報の区切りを認識しづらい。
- 60代前後や視力低下があるユーザーには、細い境界線 `border-[#2a3441]` だけでは区切りが弱い。
- グラデーションと hover scale が多く、業務画面としては装飾の情報量が多い。

修正方針:

- 背景は単色寄りにする。例: `bg-slate-950` または `bg-[#111827]`
- サマリーカードはグラデーションをやめ、状態別に左ボーダー・アイコン・明確な背景で区別する。
- テーブルコンテナは背景と境界のコントラストを強める。
- `transform hover:scale-105` は削除する。カードが動く必要はなく、視覚的負荷と誤認識を増やす。

実装メモ:

```tsx
// before
className="bg-gradient-to-br from-[#3d1f1f] to-[#2a1515] rounded-lg p-4 border border-[#2a3441] transform hover:scale-105 ..."

// after 案
className="rounded-lg p-4 border border-red-500/50 bg-red-950/40"
```

### 2. 文字サイズが小さい

該当箇所:

- サマリーカード見出し: `Dashboard.tsx:528`, `546`, `565`, `574` が `text-xs`
- サマリー数値: `Dashboard.tsx:529`, `547`, `566`, `575` が `text-xl`
- テーブルヘッダー: `Dashboard.tsx:690`, `700`, `710`, `743`, `746` が `text-sm`
- 更新日: `Dashboard.tsx:760` が `text-sm`
- 残り日数: `Dashboard.tsx:763` が `text-xs`
- 氏名: `Dashboard.tsx:776` が `text-base`
- ふりがな: `Dashboard.tsx:779` が `text-xs`
- 進捗の回数・next: `Dashboard.tsx:793-795` が `text-sm`, `text-xs`
- アセスメント開始期限: `Dashboard.tsx:803` が `text-sm`
- モバイル表示も `Dashboard.tsx:904`, `906`, `910`, `919`, `921`, `942`, `945`, `957`, `959` に `text-xs/text-sm` が多い

課題:

- 業務で最も重要な「氏名」「期限」「残り日数」が 12〜16px 程度に分散している。
- `text-xs` は高齢ユーザーには読みにくい。

修正方針:

- 本文の最低サイズは `text-base` にする。
- 氏名は `text-lg font-bold`、できればデスクトップでは `text-xl` も検討する。
- ふりがなは `text-sm` 以上、薄すぎる色は避ける。
- 期限・残り日数は `text-base font-semibold` 以上にする。
- テーブルヘッダーは `text-base font-semibold` に上げる。

具体修正:

| 対象 | 現在 | 修正案 |
| --- | --- | --- |
| サマリー見出し | `text-xs` | `text-base font-semibold` |
| サマリー数値 | `text-xl` | `text-2xl md:text-3xl font-bold` |
| テーブルヘッダー | `text-sm` | `text-base font-semibold` |
| 氏名 | `text-base` | `text-lg md:text-xl font-bold` |
| ふりがな | `text-xs` | `text-sm text-gray-300` |
| 日付 | `text-sm` | `text-base font-medium` |
| 残り日数 | `text-xs` | `text-base font-semibold` |

### 3. 期限表示が色依存になっている

該当箇所:

- `Dashboard.tsx:407-412` `getDaysRemainingColor`
- `Dashboard.tsx:763-768` 次回更新日の残り日数
- `Dashboard.tsx:803-813` アセスメント開始期限
- `Dashboard.tsx:910-915`, `921-931` モバイル側の期限表示

現状:

```tsx
if (days < 0) return 'text-red-500 bg-red-500/20 font-bold';
if (days < 7) return 'text-red-500';
if (days <= 30) return 'text-yellow-500';
return 'text-green-500';
```

課題:

- 赤・黄・緑だけで危険度を判別させている。
- `期限切れ` という文言はやや不自然で、業務上は `期限超過` の方が直感的。
- `残り0日` など当日対応が必要なケースの表現が弱い。

修正方針:

- 色に加えて、アイコン・文言・太字・背景ラベルで状態を示す。
- 表示文言を以下に統一する。

| 条件 | 表示 |
| --- | --- |
| `days < 0` | `! 期限超過 X日` |
| `days === 0` | `! 本日期限` |
| `1 <= days <= 7` | `! 残りX日` |
| `8 <= days <= 30` | `残りX日` |
| `31 <= days` | `余裕あり X日` または `残りX日` |
| 日付なし | `未設定` |

実装案:

- `getDaysRemainingColor` を `getDeadlineStatus` に置き換える。
- `className` だけでなく `label`, `icon`, `tone` を返す。
- 画面表示側では `<span>` でバッジ化する。

```tsx
const getDeadlineStatus = (days: number | null) => {
  if (days === null) return { label: '未設定', icon: '-', className: 'bg-gray-700 text-gray-200' };
  if (days < 0) return { label: `期限超過 ${Math.abs(days)}日`, icon: '!', className: 'bg-red-100 text-red-900 border border-red-300' };
  if (days === 0) return { label: '本日期限', icon: '!', className: 'bg-red-100 text-red-900 border border-red-300' };
  if (days <= 7) return { label: `残り${days}日`, icon: '!', className: 'bg-orange-100 text-orange-900 border border-orange-300' };
  if (days <= 30) return { label: `残り${days}日`, icon: '', className: 'bg-yellow-100 text-yellow-900 border border-yellow-300' };
  return { label: `残り${days}日`, icon: '', className: 'bg-emerald-100 text-emerald-900 border border-emerald-300' };
};
```

注: アイコンは絵文字ではなく、既存の `react-icons` または `lucide-react` の `AlertTriangle`, `Clock`, `CheckCircle` などを使う方が統一しやすい。

### 4. 進捗列の `next` が意味を持たず認知負荷になっている

該当箇所:

- `Dashboard.tsx:792-797`
- `Dashboard.tsx:956-962`

現状:

```tsx
<div className="text-gray-300 text-sm">第{recipient.current_cycle_number}回</div>
<div className="text-xs text-gray-300">next</div>
<span className={getStepBadgeStyle(recipient.latest_step)}>
  {getStepText(recipient.latest_step)}
</span>
```

課題:

- `next` が英語で、業務上の意味が分からない。
- 「第1回」「next」「アセスメント」が縦に並び、読む順序が増える。
- モバイル側には `text-gray-3000` という Tailwind に存在しないクラスがある。

修正方針:

- `next` は削除する。
- 表示を `第1回 アセスメント` のように一文で読める形にする。
- 進捗バッジは 14px 以下にしない。

修正案:

```tsx
<div className="flex flex-wrap items-center gap-2 text-base">
  <span className="text-gray-200 font-medium">第{recipient.current_cycle_number}回</span>
  <span className={getStepBadgeStyle(recipient.latest_step)}>
    {getStepText(recipient.latest_step)}
  </span>
</div>
```

`getStepBadgeStyle` の `baseStyle` も変更する。

```tsx
const baseStyle = 'inline-flex items-center px-3 py-1.5 rounded-md text-sm font-semibold';
```

### 5. 上部の操作ボタンがアイコンだけで初見理解しづらい

該当箇所:

- 利用者追加: `Dashboard.tsx:653-662`
- PDF一覧: `Dashboard.tsx:664-673`
- 表示リセット: `Dashboard.tsx:674-681`
- 旧実装では `BiUserPlus`, `BiFile`, `MdRefresh` などの `react-icons` に操作意味を依存している

課題:

- デスクトップでは右上にアイコンのみ表示される。
- `title` はマウス hover 前提なので、ITリテラシーが低い人やタブレット利用では意味が伝わりにくい。
- 視力低下があるユーザーは、アイコン形状だけでは機能を判別しづらい。

修正方針:

- ボタン内の `react-icons` 表示は使わず、文字ラベルを主表示にする。
- ボタン高さは最低 `44px`、文字は `text-base`。
- 表示文言は以下にする。

| 現在 | 修正後 |
| --- | --- |
| 人アイコンのみ | `利用者追加` |
| 紙アイコンのみ | `PDF一覧` または `帳票一覧` |
| 更新アイコンのみ | `表示リセット` |

実装案:

```tsx
className="min-h-[44px] px-4 py-2 rounded-lg text-base font-semibold flex items-center gap-2"
```

実装済み方針:

- `react-icons` の `BiUserPlus`, `BiFile`, `MdRefresh` はボタン内で使わない。
- ボタン表示は `利用者追加`, `PDF一覧`, `表示リセット` の文字にする。

### 6. 行内アクションがアイコンのみで、押し間違いが起きやすい

該当箇所:

- アセスメント: `Dashboard.tsx:824-837`
- 個別支援計画: `Dashboard.tsx:840-853`
- 編集: `Dashboard.tsx:856-867`
- 削除: `Dashboard.tsx:870-885`
- モバイル側: `Dashboard.tsx:966-1022`
- 旧実装では `FaClipboardList`, `FaFileAlt`, `FaEdit`, `FaTrash` などの `react-icons` に操作意味を依存している

課題:

- デスクトップの行内アクションはアイコンのみで、ツールチップは hover しないと見えない。
- 削除ボタンもアイコンのみで、誤操作の心理的ハードルが低い。
- アセスメントと個別支援計画はアイコンだけでは判別しにくい。

修正方針:

- デスクトップでは主要操作を「ラベル付きボタン」にする。
- ボタン内の `react-icons` は使わず、文字ラベルだけで操作内容を判断できるようにする。
- アクション列名 `詳細なアクション` は長く、意味が曖昧なので `操作` に変更する。
- 削除だけは他の操作と視覚的に分離し、赤系のアウトラインまたは薄背景を使う。
- モバイルは現在 44px を確保しているが、ラベルがない。縦幅を許容して文字ラベルを表示する。
- モバイルもアイコンではなく文字ラベルを表示する。

表示案:

```text
アセスメント
支援計画
編集
削除
```

実装案:

```tsx
<button className="min-h-[44px] px-3 py-2 text-base font-semibold rounded-md border border-gray-600 text-gray-100 flex items-center gap-2">
  <span>編集</span>
</button>
```

実装済み方針:

- `react-icons` の `FaClipboardList`, `FaFileAlt`, `FaEdit`, `FaTrash` はボタン内で使わない。
- デスクトップ、モバイルとも `アセスメント`, `支援計画`, `編集`, `削除` の文字ボタンにする。
- hover ツールチップは操作理解の主手段にしない。

### 7. 検索欄が小さく、何を検索できるか分かりづらい

該当箇所:

- `Dashboard.tsx:601-610`
- APIパラメータは `k_front/lib/dashboard.ts:10-18` の `searchTerm`

課題:

- placeholder が `検索` のみ。
- `w-48` で横幅が狭い。
- アイコンが input 内に絶対配置されているが、右 padding が不足気味。

修正方針:

- placeholder を `氏名・ふりがなで検索` にする。
- デスクトップは `w-72`、モバイルは `w-full`。
- `text-base`, `min-h-[44px]`, `pr-10` にする。
- 可能なら検索欄は総利用者数カード内ではなく、一覧見出しの近くに置く。検索は一覧に対する操作であり、総数カード内にあると関連が分かりづらい。

修正案:

```tsx
className="bg-[#111827] border border-gray-500 rounded-lg px-4 pr-10 py-2 text-base text-white placeholder-gray-300 w-full md:w-72 min-h-[44px] focus:outline-none focus:ring-2 focus:ring-cyan-400"
placeholder="氏名・ふりがなで検索"
```

### 8. サマリーカードのフィルター操作が小さいアイコンだけ

該当箇所:

- 期限切れフィルター: `Dashboard.tsx:531-536`
- 期限間近フィルター: `Dashboard.tsx:549-554`
- `アセスメント未完了` カードにはフィルターアイコンがない: `Dashboard.tsx:558-568`
- `handleFilterToggle` は `hasAssessmentDue` に対応済み: `Dashboard.tsx:220-232`
- 旧実装では `BiFilterAlt` の小さなアイコンに絞り込み操作を依存している

課題:

- フィルターアイコンだけでは、カード全体が押せるのか、アイコンだけ押せるのか分からない。
- アセスメント未完了はカウントがあるのにフィルターできない見た目になっている。ただし状態 `hasAssessmentDue` と API パラメータは実装済み。

修正方針:

- サマリーカード全体をボタン化する、またはカード下部に `この条件で絞り込む` ボタンを置く。
- `BiFilterAlt` は使わず、`絞り込み` / `解除` の文字ボタンにする。
- `アセスメント未完了` にも `handleFilterToggle('hasAssessmentDue', !activeFilters.hasAssessmentDue)` を接続する。
- 選択中カードは `aria-pressed` と強い枠線で分かるようにする。

実装案:

```tsx
<button
  type="button"
  aria-pressed={activeFilters.isOverdue}
  onClick={() => handleFilterToggle('isOverdue', !activeFilters.isOverdue)}
  className="w-full text-left rounded-lg p-4 border ..."
>
```

### 9. `ActiveFilters` のチップが小さく、クリアボタンの色が不自然

該当箇所:

- `ActiveFilters.tsx:41-43`
- `ActiveFilters.tsx:90-95`
- `ActiveFilters.tsx:111-119`

課題:

- チップが `text-xs` で小さい。
- `すべてクリア` が `text-gray-400 bg-gray-200` でコントラストと意味が不自然。
- 削除の `×` が小さく、クリック領域が狭い。

修正方針:

- チップは `text-sm` 以上、`min-h-[36px]`。
- `×` ボタンは `min-w-[32px] min-h-[32px]`。
- `すべてクリア` は `text-sm`, `min-h-[40px]`, `border-gray-500`, `bg-transparent` などにする。

修正案:

```tsx
className="inline-flex items-center gap-2 px-3 py-1.5 min-h-[36px] rounded-md border text-sm font-semibold ..."
```

### 10. ローディング表示の文字が小さい

該当箇所:

- `table-loading-overlay.tsx:16-19`

課題:

- `データを取得中...` が `text-sm`。
- 背景 blur は暗色画面では見えづらいことがある。

修正方針:

- `text-base font-semibold` 以上にする。
- 可能なら `aria-live="polite"` を付ける。
- 文言は `一覧を更新しています` の方がユーザーにとって具体的。

### 11. ライトモード・ダークモードの切り替えがなく、視認性をユーザーが調整できない

確認した実装:

- `k_front/package.json` には `next-themes` が導入済み。
- `k_front/tailwind.config.js` は `darkMode: 'class'` になっており、Tailwind の `dark:` バリアントを使える。
- `k_front/app/globals.css` は `@media (prefers-color-scheme: dark)` で CSS 変数を切り替えている。
- `k_front/app/layout.tsx` は RootLayout で `ToasterProvider` と `children` を直接描画している。
- `k_front/app/(protected)/layout.tsx` は通常ユーザーに `ProtectedLayoutClient` を使い、`app_admin` は `children` のみ返す。
- `k_front/components/protected/LayoutClient.tsx` は保護画面全体のヘッダー、メイン、フッターを持ち、現在は `bg-gray-900`, `bg-gray-800`, `text-gray-200` など暗色固定。
- `k_front/components/protected/dashboard/Dashboard.tsx` はページ背景、サマリーカード、一覧、テーブル、ボタンが暗色固定の class を直接持つ。
- `k_front/components/protected/dashboard/ActiveFilters.tsx` も暗色固定に近い色指定を持つ。

課題:

- OS 設定に追随するだけで、ユーザーが画面上でライト/ダークを切り替えられない。
- Tailwind は class ベースの dark mode 設定なのに、`globals.css` は media query ベースで CSS 変数を変更しており、切替方式が混在する。
- `Dashboard.tsx` と `LayoutClient.tsx` の固定色が多いため、Context を追加するだけでは画面色が切り替わらない。
- 高齢ユーザーや視力低下があるユーザーにとって、暗色が読みやすい場合とライト背景が読みやすい場合が分かれる。選択できること自体がアクセシビリティ改善になる。

方針:

- 新規ライブラリは追加せず、既存依存の `next-themes` を使う。
- ThemeProvider は全画面で効くように RootLayout 直下へ置く。
- 実際に `theme`, `setTheme`, `resolvedTheme` を読むコンポーネントは、原則としてテーマ切替 UI だけに限定する。
- `Dashboard.tsx`, `ActiveFilters.tsx`, 通常の UI 部品には `theme` props を渡さない。各コンポーネントは `bg-white text-gray-900 dark:bg-gray-900 dark:text-gray-100` のような class または CSS 変数で追随させる。
- ライト/ダークの状態は `next-themes` が `localStorage` と `<html class="dark">` を管理する。独自 Context と localStorage 実装は増やさない。
- 初期表示のちらつきと hydration mismatch を避けるため、`<html lang="ja" suppressHydrationWarning>` を使う。

Context の受け渡し設計:

```text
app/layout.tsx
  └─ app/theme-provider.tsx
      └─ next-themes ThemeProvider
          ├─ ToasterProvider
          └─ children
              └─ app/(protected)/layout.tsx
                  └─ ProtectedLayoutClient
                      ├─ ThemeToggle
                      │   └─ useTheme()
                      └─ Dashboard
                          └─ theme props は渡さない。dark: class / CSS 変数で表示を切替
```

実装対象:

1. `k_front/app/theme-provider.tsx` を追加する。

```tsx
'use client';

import { ThemeProvider as NextThemesProvider } from 'next-themes';

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  return (
    <NextThemesProvider
      attribute="class"
      defaultTheme="system"
      enableSystem
      disableTransitionOnChange
    >
      {children}
    </NextThemesProvider>
  );
}
```

2. `k_front/app/layout.tsx` で `ThemeProvider` を使う。

```tsx
<html lang="ja" suppressHydrationWarning>
  <body className={`${geistSans.variable} ${geistMono.variable} antialiased`}>
    <ThemeProvider>
      <ToasterProvider />
      {children}
    </ThemeProvider>
  </body>
</html>
```

3. `k_front/components/theme/ThemeToggle.tsx` を追加する。

- `useTheme` を使うのはこのコンポーネントに閉じる。
- 表示は `ライト`, `ダーク`, `端末設定` の 3択にする。
- 視認性改善が目的なので、アイコンだけにしない。
- hydration 後に現在テーマを表示するため `mounted` state を持つ。
- ボタンサイズは最低 `min-h-[40px]`、できれば `44px` を確保する。

実装イメージ:

```tsx
'use client';

import { useEffect, useState } from 'react';
import { Monitor, Moon, Sun } from 'lucide-react';
import { useTheme } from 'next-themes';

export function ThemeToggle() {
  const { theme, setTheme } = useTheme();
  const [mounted, setMounted] = useState(false);

  useEffect(() => setMounted(true), []);

  if (!mounted) {
    return <div className="min-h-[44px] w-[220px]" aria-hidden="true" />;
  }

  return (
    <div className="inline-flex rounded-md border border-gray-300 bg-white p-1 text-sm font-semibold text-gray-800 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-100">
      <button type="button" onClick={() => setTheme('light')} aria-pressed={theme === 'light'}>ライト</button>
      <button type="button" onClick={() => setTheme('dark')} aria-pressed={theme === 'dark'}>ダーク</button>
      <button type="button" onClick={() => setTheme('system')} aria-pressed={theme === 'system'}>端末設定</button>
    </div>
  );
}
```

4. `k_front/components/protected/LayoutClient.tsx` に `ThemeToggle` を配置する。

- デスクトップはヘッダー右側の `ログアウト` 前に置く。
- モバイルはハンバーガーメニュー内の `通知/メッセージ` と `ログアウト` の間に置く。
- `ProtectedLayoutClient` が持つ `user`, `office`, `unreadCount` とは独立した UI なので、テーマ状態を親 state に持ち上げない。
- `app_admin` は `ProtectedLayoutClient` を通らないため、この対応だけでは app-admin 画面に切替 UI は出ない。全体に出したい場合は `app/(protected)/app-admin/layout.tsx` にも同じ `ThemeToggle` を置く。

5. `globals.css` のテーマ変数を class ベースにそろえる。

現在の `@media (prefers-color-scheme: dark)` は、ユーザーがライト固定を選んでも OS が dark なら CSS 変数が暗色になる可能性がある。`next-themes` の `attribute="class"` に合わせて、以下のように `.dark` を基準にする。

```css
:root {
  --background: #f8fafc;
  --foreground: #111827;
}

.dark {
  --background: #0f172a;
  --foreground: #f8fafc;
}
```

6. `LayoutClient.tsx`, `Dashboard.tsx`, `ActiveFilters.tsx` の固定色をテーマ対応 class に置き換える。

例:

```tsx
// before
className="min-h-screen bg-gray-900 text-gray-200"

// after
className="min-h-screen bg-slate-100 text-slate-900 dark:bg-gray-900 dark:text-gray-100"
```

```tsx
// before
className="bg-[#0f1419cc] rounded-lg border border-[#2a3441]"

// after
className="rounded-lg border border-slate-300 bg-white shadow-sm dark:border-slate-700 dark:bg-slate-900"
```

7. ダーク専用の半透明色は、ライト側の対応色も必ずセットにする。

| 用途 | ライト | ダーク |
| --- | --- | --- |
| 画面背景 | `bg-slate-100` | `dark:bg-slate-950` |
| メイン領域 | `bg-white text-slate-900` | `dark:bg-slate-900 dark:text-slate-100` |
| 境界線 | `border-slate-300` | `dark:border-slate-700` |
| 補助文字 | `text-slate-600` | `dark:text-slate-300` |
| テーブル hover | `hover:bg-slate-100` | `dark:hover:bg-slate-800` |
| 入力欄 | `bg-white text-slate-900 placeholder-slate-500` | `dark:bg-slate-950 dark:text-white dark:placeholder-slate-400` |

実装上の注意:

- `useTheme` を `Dashboard.tsx` に直接入れない。Dashboard は既に大きく、テーマ制御まで持たせると責務が増える。
- `theme` props を `Dashboard`, `ActiveFilters`, `TableLoadingOverlay` に渡さない。色は class で追随させる。
- `next-themes` はクライアント専用なので、Provider ファイルには `'use client'` を付ける。
- `metadata.themeColor` は静的値のままでよい。PWA のブラウザバー色までテーマ連動させる場合は別タスクにする。
- `sonner` の Toast は画面テーマとズレる可能性がある。必要なら `ToasterProvider` 側で `useTheme` を読み、`theme={resolvedTheme}` を渡す。ただし今回の主対象は `/dashboard` の視認性。

## 実装タスク

### Phase 1: 表示文言と文字サイズの改善

- [x] `Dashboard.tsx` の `text-xs` を棚卸しし、本文・ラベルは原則 `text-base` 以上にする。
- [x] 氏名を `text-lg md:text-xl font-bold` に変更する。
- [x] ふりがなを `text-sm text-gray-300` に変更する。
- [x] 日付・残り日数を `text-base` 以上にする。
- [x] `期限切れ` を `期限超過` に変更する。
- [x] `next` 表示を削除する。
- [x] `詳細なアクション` を `操作` に変更する。

### Phase 2: 期限表示を色依存から脱却する

- [ ] `getDaysRemainingColor` を `getDeadlineStatus` に置き換える。
- [ ] `days < 0`, `days === 0`, `days <= 7`, `days <= 30`, `days > 30`, `null` の表示を定義する。
- [ ] 次回更新日とアセスメント開始期限の両方で同じ表示ロジックを使う。
- [ ] desktop と mobile の表示差分をなくす。
- [ ] 色だけでなく、文言・アイコン・太字・背景で状態を伝える。

### Phase 3: 操作ボタンの分かりやすさ改善

- [x] 上部ボタンをアイコンのみから文字ラベルに変更する。
- [x] 行内アクションを `アセスメント`, `支援計画`, `編集`, `削除` のラベル付きにする。
- [x] ボタン内の `react-icons` 表示をやめ、文字だけで操作意味が分かるようにする。
- [x] ボタンは最低 `min-h-[44px]` を確保する。
- [x] 削除ボタンは他操作と距離または色で分離する。
- [x] hover ツールチップに依存しない。

### Phase 4: サマリーカードとフィルターの改善

- [x] サマリーカードの `hover:scale-105` を削除する。
- [x] サマリーカードの見出しを `text-base` 以上にする。
- [x] フィルターアイコンだけでなく、カード全体または明示ボタンで絞り込みできるようにする。
- [x] サマリーカードの絞り込み操作は `react-icons` ではなく `絞り込み` / `解除` の文字ボタンにする。
- [x] `アセスメント未完了` カードに `hasAssessmentDue` のフィルター操作を追加する。
- [x] 選択中のカードは `aria-pressed` と枠線で分かるようにする。

### Phase 5: 検索と選択中フィルターの改善

- [x] 検索欄 placeholder を `氏名・ふりがなで検索` にする。
- [x] 検索欄を `w-full md:w-72`, `min-h-[44px]`, `text-base` にする。
- [ ] 検索欄の配置を一覧見出し近くへ移すことを検討する。
- [x] `ActiveFilters` のチップを `text-sm`, `min-h-[36px]` にする。
- [x] `すべてクリア` ボタンを読みやすい色とサイズにする。

### Phase 6: レスポンシブ表示の整理

- [x] モバイルカード内の `text-xs` を原則なくす。
- [ ] モバイルでも氏名を最優先表示にする。現在は期限情報が先に出るため、氏名をカード先頭に移すことを検討する。
- [x] モバイルの操作ボタンにもラベルを付ける。
- [x] `text-gray-3000` を修正する。

### Phase 7: ライトモード・ダークモード切り替え

- [x] `app/theme-provider.tsx` を追加し、`next-themes` の `ThemeProvider` を RootLayout 直下に置く。
- [x] `app/layout.tsx` の `<html>` に `suppressHydrationWarning` を追加する。
- [x] `globals.css` のテーマ変数を `@media (prefers-color-scheme: dark)` から `.dark` class ベースへ変更する。
- [ ] `components/theme/ThemeToggle.tsx` を追加し、`ライト` / `ダーク` / `端末設定` を切り替えられるようにする。
- [x] `ThemeToggle` を `ProtectedLayoutClient` のデスクトップヘッダーとモバイルメニューに配置する。
- [x] `LayoutClient.tsx` の暗色固定 class を `light + dark:` の組み合わせに置き換える。
- [x] `Dashboard.tsx` の背景、カード、一覧、テーブル、入力欄、操作ボタンを `light + dark:` の組み合わせに置き換える。
- [x] `ActiveFilters.tsx` のチップ、コンテナ、クリアボタンを `light + dark:` の組み合わせに置き換える。
- [x] `Dashboard.tsx`, `ActiveFilters.tsx` へ `theme` props を渡していないことを確認する。
- [x] app-admin 画面にも切替 UI を出すかを別途判断する。出す場合は `app/(protected)/app-admin/layout.tsx` にも `ThemeToggle` を配置する。

## 受け入れ基準

- [x] 氏名、期限、残り日数が 100% 表示倍率のブラウザで無理なく読める。
- [x] `text-xs` は補助的な情報に限定され、主要情報には使われていない。
- [ ] 期限状態が色だけでなく文言・アイコン・太字・背景でも判別できる。
- [x] `期限切れ` ではなく `期限超過` を使っている。
- [x] `next` が画面に表示されない。
- [x] 上部操作と行内操作が hover なしで意味を理解できる。
- [x] ボタンの主表示に `react-icons` を使っていない。
- [x] すべてのボタンのクリック領域が最低 44px 相当ある。
- [x] サマリーカードのフィルター操作が、初見でも押せると分かる。
- [x] アセスメント未完了カードからも絞り込みできる。
- [x] モバイル表示で氏名・期限・操作が小さすぎない。
- [ ] ユーザーが画面上で `ライト`, `ダーク`, `端末設定` を切り替えられる。
- [x] 選択したテーマがページ遷移・リロード後も維持される。
- [x] OS が dark でも、ユーザーがライト固定を選んだ場合はライト表示になる。
- [x] `Dashboard.tsx` と `ActiveFilters.tsx` はテーマ Context を props で受け取らず、class/CSS 変数で表示が切り替わる。
- [x] ライトモードでもテーブル境界、サマリーカード、期限ラベル、操作ボタンのコントラストが十分にある。
- [x] ダークモードでも現在の暗色固定 UI より情報の区切りが分かりやすい。
- [x] 既存の `/dashboard` API パラメータ仕様は変えない。

## テスト観点

- `npm run lint`
- 既存 E2E: `npx playwright test e2e/dashboard-filtering.spec.ts`
- 手動確認:
  - `/dashboard` 初期表示
  - 氏名検索
  - 期限切れフィルター
  - 期限間近フィルター
  - アセスメント未完了フィルター
  - 進捗ステータスフィルター
  - 表示リセット
  - 利用者追加、PDF一覧、各行のアセスメント・支援計画・編集・削除
  - desktop 幅 1280px
  - tablet 幅 768px
  - mobile 幅 390px
  - ライト固定で `/dashboard` を表示
  - ダーク固定で `/dashboard` を表示
  - 端末設定で OS テーマに追随することを確認
  - ライト/ダーク切替後、ページリロードして選択が維持されることを確認
  - モバイルメニュー内のテーマ切替がタップ操作で使えることを確認

## 実装時の注意

- 今回は UI 改善が目的なので、バックエンド API 仕様は変更しない。
- `Dashboard.tsx` が大きくなっているため、実装時に必要なら小さな表示コンポーネントへ分割する。ただし大きなリファクタは UI 改善後に分けてもよい。
- 削除などの権限・MFA・課金状態判定 `canEdit` は変えない。
- `EmployeeActionRequestModal` の挙動は維持する。
- 表示文言は福祉職員向けに日本語で統一し、英語ラベルを増やさない。
- テーマ切替は UI 表示の責務なので、バックエンドや認証セッションには保存しない。
- `next-themes` の `localStorage` 管理に任せ、独自のテーマ Context は追加しない。
