# ケイカくん LP デザイン添削・改善提案

## 1. 現状の課題分析

### 良い点
- キャッチコピー「計画の『うっかり』を、確実な『あんしん』に。」は福祉現場の課題を的確に表現
- 3つのポイントで価値提案が明確
- CTAボタンが目立つ緑色で配置

### 改善が必要な点

| 項目 | 現状の問題 | 理想（ニッタ・デュポン参考） |
|------|----------|------------------------|
| **余白** | 要素が詰まっている | 十分な余白で高級感・信頼感 |
| **タイポグラフィ** | フォントサイズの強弱が弱い | 大胆なサイズ差でメリハリ |
| **視覚的フォーカス** | 3つのアイコンに視線が分散 | 右側にビジュアル要素を集約 |
| **ストーリー性** | 情報の羅列感 | スクロールで物語が展開 |
| **ロゴの活用** | ロゴが不在 | ブランド要素を効果的に配置 |

---

## 2. 改善後のLP構成案

### ファーストビュー（Above the Fold）

```
┌─────────────────────────────────────────────────────────────┐
│  [ロゴ: けいかくん]                    [ログイン] [新規登録] │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│     計画の「うっかり」を、              ┌─────────────┐    │
│                                        │             │    │
│     確実な「あんしん」に。              │  ロゴ       │    │
│                                        │  アニメ     │    │
│     福祉サービス事業所の                │  ーション   │    │
│     個別支援計画をかんたんに。          │             │    │
│                                        └─────────────┘    │
│                                                             │
│         [始める]  [詳しく見る]                        │
│                                                             │
│                         ∨ Scroll                           │
└─────────────────────────────────────────────────────────────┘
```

### 表示すべき要素（セクション順）

**セクション1: ヒーロー（ファーストビュー）**
- キャッチコピー（大）
- サブコピー（ターゲット明示）
- ロゴアニメーション
- CTAボタン×2

**セクション2: 課題提起**
- 「こんなお悩みありませんか？」
- 計画更新の漏れ: 通知がこない
- 書類管理の煩雑さ: GoogleDriveでの管理,フォルダ　各々が管理しているとどこに何があるかわからない
- 更新期限がわかりにくい: 残り期限をいちいち管理するのが面倒

**セクション3: 3つの特徴**
- 現在の3ポイントを洗練させて表示
- アイコン＋見出し＋説明文の構成

**セクション4: 機能紹介**
- スクリーンショットまたはモックアップ
- ダッシュボード、計画管理画面など

**セクション5: 料金**
- 半年まで無料
- それ以降は月6000円

**セクション6: CTA**
- 「まずは無料でお試しください」
- 登録ボタン

**フッター**
- 運営情報、利用規約、プライバシーポリシー

---

## 3. ロゴアニメーション提案

### 設計意図の確認
「違う個性を持った人が手を取り合う」→ 支援者と利用者、または異なる専門職の協働を表現

### アニメーション案



#### 案B: イージング付きバウンス（CSS推奨）

```
[開始]        [接近]        [衝突]        [バウンス]      [静止]
                                         
○      ○  →  ○   ○   →   ○○    →    ○ ○      →    ○○
              加速          接触         少し離れる       最終位置
```

**実装: CSS cubic-bezier**
```css
@keyframes bounceIn {
  0% { transform: translateX(-100vw); }
  70% { transform: translateX(10px); }  /* オーバーシュート */
  85% { transform: translateX(-5px); }  /* バウンスバック */
  100% { transform: translateX(0); }
}

.blue-circle {
  animation: bounceIn 1.2s cubic-bezier(0.68, -0.55, 0.27, 1.55);
}
```

**メリット**: 「出会い」の瞬間を強調、印象的


## 4. 実装サンプル（案B: バウンス）

```tsx
// components/LogoAnimation.tsx
'use client';
import { useEffect, useState } from 'react';

export function LogoAnimation() {
  const [isVisible, setIsVisible] = useState(false);

  useEffect(() => {
    // ページ読み込み後にアニメーション開始
    const timer = setTimeout(() => setIsVisible(true), 300);
    return () => clearTimeout(timer);
  }, []);

  return (
    <div className="relative w-80 h-80 flex items-center justify-center">
      {/* 青い円（左から） */}
      <div
        className={`absolute w-32 h-32 rounded-full bg-cyan-400 
          transition-transform duration-1000 ease-[cubic-bezier(0.68,-0.55,0.27,1.55)]
          ${isVisible ? 'translate-x-4' : '-translate-x-[50vw]'}`}
      />
      {/* 緑の円（右から） */}
      <div
        className={`absolute w-32 h-32 rounded-full bg-lime-500 
          transition-transform duration-1000 ease-[cubic-bezier(0.68,-0.55,0.27,1.55)]
          ${isVisible ? '-translate-x-4' : 'translate-x-[50vw]'}`}
        style={{ transitionDelay: '0.1s' }}
      />
      {/* 中間色の円（オーバーラップ部分） */}
      <div
        className={`absolute w-20 h-20 rounded-full bg-teal-400 opacity-0
          transition-opacity duration-500
          ${isVisible ? 'opacity-70' : ''}`}
        style={{ transitionDelay: '0.8s' }}
      />
    </div>
  );
}
```

この実装をファーストビューの右側に配置することで、ニッタ・デュポンのような洗練されたビジュアル効果を実現できます。