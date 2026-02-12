# けいかくん - 状態管理ライブラリを使わなかった理由

**作成日**: 2026-01-28
**対象**: 2次面接 - フロントエンド設計判断
**関連技術**: React Context API, Custom Hooks, Redux, Zustand, Recoil

---

## 概要

けいかくんフロントエンド（Next.js + React 19）では、ReduxやZustandなどの状態管理ライブラリを使用せず、**React Context APIとカスタムフック**で状態管理を実装しています。この設計判断の理由と、メリット・デメリット、将来的な移行判断基準について説明します。

---

## 1. 現在の状態管理アーキテクチャ

### 1.1 実装構成

```
k_front/
├── contexts/
│   └── BillingContext.tsx       # グローバル状態: 課金ステータス
├── hooks/
│   ├── usePushNotification.ts   # Push通知の状態管理
│   └── useStaffRole.ts          # スタッフ権限の状態管理
└── components/
    └── Dashboard.tsx            # ローカル状態: 検索/フィルター/ソート
```

---

### 1.2 グローバル状態管理（Context API）

#### BillingContext の実装

**ファイル**: `contexts/BillingContext.tsx`

```typescript
'use client';

import { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import { billingApi } from '@/lib/api/billing';
import { BillingStatusResponse } from '@/types/billing';

interface BillingContextType {
  billingStatus: BillingStatusResponse | null;
  isLoading: boolean;
  error: string | null;
  refreshBillingStatus: () => Promise<void>;
  canWrite: boolean;  // 書き込み操作が許可されているか
  isPastDue: boolean; // 支払い遅延状態か
}

const BillingContext = createContext<BillingContextType | undefined>(undefined);

export function BillingProvider({ children }: BillingProviderProps) {
  const [billingStatus, setBillingStatus] = useState<BillingStatusResponse | null>(null);
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);

  // 課金ステータスを取得
  const fetchBillingStatus = async () => {
    try {
      setIsLoading(true);
      setError(null);
      const data = await billingApi.getBillingStatus();
      setBillingStatus(data);
    } catch (err) {
      console.error('課金ステータスの取得に失敗しました:', err);
      setError(err instanceof Error ? err.message : '課金ステータスの取得に失敗しました');
    } finally {
      setIsLoading(false);
    }
  };

  // 初回マウント時に課金ステータスを取得
  useEffect(() => {
    fetchBillingStatus();

    // 10分ごとに課金ステータスを更新
    const interval = setInterval(() => {
      fetchBillingStatus();
    }, 10 * 60 * 1000); // 10分

    return () => clearInterval(interval);
  }, []);

  // 書き込み操作が許可されているかどうか
  const canWrite =
    billingStatus?.billing_status !== BillingStatus.PAST_DUE &&
    billingStatus?.billing_status !== BillingStatus.CANCELED;

  return (
    <BillingContext.Provider
      value={{
        billingStatus,
        isLoading,
        error,
        refreshBillingStatus,
        canWrite,
        isPastDue,
      }}
    >
      {children}
    </BillingContext.Provider>
  );
}

export function useBilling(): BillingContextType {
  const context = useContext(BillingContext);
  if (context === undefined) {
    throw new Error('useBilling must be used within a BillingProvider');
  }
  return context;
}
```

**使用例**:
```typescript
// components/Dashboard.tsx
import { useBilling } from '@/contexts/BillingContext';

export default function Dashboard() {
  const { billingStatus, canWrite, isPastDue } = useBilling();

  return (
    <>
      {/* 書き込み操作を制限 */}
      <button disabled={!canWrite}>利用者追加</button>

      {/* 支払い遅延モーダルを表示 */}
      {isPastDue && <PastDueModal />}
    </>
  );
}
```

---

### 1.3 カスタムフック（ローカル状態管理）

#### usePushNotification の実装

**ファイル**: `hooks/usePushNotification.ts`

```typescript
'use client';

import { useState, useEffect, useCallback } from 'react';

export function usePushNotification() {
  const [isSupported, setIsSupported] = useState(false);
  const [isSubscribed, setIsSubscribed] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Service Worker登録とPush通知購読
  const subscribe = useCallback(async () => {
    setIsLoading(true);
    try {
      const registration = await navigator.serviceWorker.register('/sw.js');
      const subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(vapidPublicKey)
      });

      await http.post('/api/v1/push-subscriptions/subscribe', subscription.toJSON());
      setIsSubscribed(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'UNKNOWN_ERROR');
      throw err;
    } finally {
      setIsLoading(false);
    }
  }, []);

  return {
    isSupported,
    isSubscribed,
    isLoading,
    error,
    subscribe,
    unsubscribe,
  };
}
```

**特徴**:
- Service Worker APIとの連携
- 非同期処理の状態管理（loading、error、success）
- useCallbackでメモ化

---

### 1.4 ローカル状態管理（useState）

#### Dashboardコンポーネント

**ファイル**: `components/protected/dashboard/Dashboard.tsx`

```typescript
export default function Dashboard() {
  // 複数のローカル状態
  const [dashboardData, setDashboardData] = useState<DashboardData | null>(null);
  const [staff, setStaff] = useState<StaffResponse | null>(null);
  const [billingStatus, setBillingStatus] = useState<BillingStatusResponse | null>(null);
  const [sortOrder, setSortOrder] = useState<'asc' | 'desc'>('asc');
  const [sortBy, setSortBy] = useState('next_renewal_deadline');
  const [searchTerm, setSearchTerm] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [debouncedSearchTerm, setDebouncedSearchTerm] = useState('');
  const [activeFilters, setActiveFilters] = useState({ ... });

  // useMemo、useCallbackで最適化
  const canEdit = useMemo(() => {
    return staff?.is_mfa_enabled && isActiveBilling;
  }, [staff, billingStatus]);

  const handleSearch = useCallback(async (term: string) => {
    setSearchTerm(term);
  }, []);

  // ...
}
```

**問題点**:
- ✅ useState が10個以上ある（複雑化）
- ✅ useEffect、useCallback、useMemoが多数（パフォーマンス最適化が必要）
- ✅ 状態更新ロジックがコンポーネントに散在

---

## 2. 状態管理ライブラリを使わなかった理由

### 2.1 技術的な理由

#### 理由1: アプリケーションの規模が小さい

**けいかくんの規模**:
- ページ数: 約20ページ
- グローバル状態: 1つ（課金ステータス）
- ユーザー数: 中小規模の福祉事業所（1事業所あたり5-20人）

**状態管理ライブラリが必要な規模の目安**:
- ページ数: 50ページ以上
- グローバル状態: 5個以上
- 複雑なデータフロー（深いコンポーネントツリー）

**判断**:
- けいかくんはContext API + カスタムフックで十分管理可能
- 状態管理ライブラリは**オーバーエンジニアリング**になる可能性

---

#### 理由2: React 19のネイティブ機能が強力

**React 19の改善点**:
- `use()` フック: Context APIがより使いやすく
- Server Componentsとの統合
- 自動バッチング（複数のsetStateを1回でレンダリング）

**Context APIのパフォーマンス改善**:
```typescript
// React 19では、Context APIのパフォーマンスが向上
// 不要な再レンダリングが自動的に最適化される
```

**Next.js 15 + React 19の組み合わせ**:
- Server Components（状態なし）とClient Components（状態あり）の分離
- Server Componentsでデータフェッチ → Client Componentsで状態管理
- 状態管理ライブラリのメリットが減少

---

#### 理由3: Server Componentsとの互換性

**Next.js App Routerの特徴**:
- Server Components（デフォルト）
- Client Components（`'use client'` directive）

**状態管理ライブラリの問題**:
```typescript
// ❌ ReduxはServer Componentsで使用不可
'use server';  // Server Component
import { useSelector } from 'react-redux';  // Error!

// ✅ Context APIはClient Componentsで明示的に使用
'use client';  // Client Component
import { useBilling } from '@/contexts/BillingContext';  // OK
```

**Server Components優先のアーキテクチャ**:
```
Server Component (データフェッチ)
    ↓
Client Component (状態管理)
    ↓
Server Component (表示)
```

**けいかくんの方針**:
- Server Componentsでできる限りデータフェッチ
- Client Componentsは必要最小限（Dashboardなど）
- Context APIはClient Componentsのみで使用

---

#### 理由4: 学習コストと開発速度

**状態管理ライブラリの学習コスト**:

| ライブラリ | 学習時間 | 複雑度 | ボイラープレート |
|-----------|---------|-------|----------------|
| Redux | 3-5日 | 高 | 多い（actions, reducers, store） |
| Zustand | 1-2日 | 低 | 少ない |
| Recoil | 2-3日 | 中 | 中 |
| Context API | 0.5-1日 | 低 | 少ない |

**けいかくんの開発状況**:
- 初期開発段階（MVP構築中）
- 開発者数: 1-2人
- 開発スピード重視

**判断**:
- Context APIは学習コストが低く、即座に実装可能
- Redux導入で開発速度が低下するリスク

---

#### 理由5: バンドルサイズの削減

**状態管理ライブラリのバンドルサイズ**:

```bash
# パッケージサイズ比較（gzip圧縮後）
Redux + React-Redux: ~15KB
Zustand: ~1.2KB
Recoil: ~14KB
Context API: 0KB（React組み込み）
```

**けいかくんの方針**:
- 初期ロードを高速化
- モバイル対応（3G回線でも快適に）
- バンドルサイズを最小化

**実際のバンドルサイズ**:
```bash
# 現在のk_front（Context APIのみ）
npm run build
Route (app)                    Size     First Load JS
┌ ○ /                         1.2 kB         100 kB
├ ○ /dashboard                15.3 kB        120 kB
└ ○ /recipients/new           8.5 kB         110 kB

# Redux導入後の予測
Route (app)                    Size     First Load JS
┌ ○ /                         1.2 kB         115 kB (+15KB)
├ ○ /dashboard                15.3 kB        135 kB (+15KB)
└ ○ /recipients/new           8.5 kB         125 kB (+15KB)
```

**トレードオフ**:
- Context APIで15KBのバンドルサイズ削減
- パフォーマンス（初期ロード速度）を優先

---

### 2.2 ビジネス的な理由

#### 理由1: 初期開発スピードの優先

**MVPの要件**:
- 3ヶ月以内にリリース
- 最小限の機能で市場検証
- 状態管理の複雑度は低い

**判断**:
- Context APIで十分
- 状態管理ライブラリの導入は将来的に検討

---

#### 理由2: コストとリスクのバランス

**Context APIのメリット**:
- ✅ 追加コストなし
- ✅ React標準機能（安定性が高い）
- ✅ 学習リソースが豊富

**状態管理ライブラリのリスク**:
- ❌ メンテナンスコスト（ライブラリの更新）
- ❌ 将来的な破壊的変更
- ❌ チーム拡大時の学習コスト

---

## 3. 状態管理ライブラリとの比較

### 3.1 Redux vs Context API

#### Redux

**メリット**:
- ✅ 大規模アプリケーションに適している
- ✅ タイムトラベルデバッグ（Redux DevTools）
- ✅ ミドルウェア（Redux Thunk、Saga）で非同期処理を体系化
- ✅ コミュニティが大きい

**デメリット**:
- ❌ ボイラープレートが多い（actions、reducers、store）
- ❌ 学習コストが高い
- ❌ バンドルサイズが大きい（15KB）
- ❌ Redux Toolkitでも複雑

**コード例（Redux）**:
```typescript
// store/billingSlice.ts
import { createSlice, createAsyncThunk } from '@reduxjs/toolkit';

export const fetchBillingStatus = createAsyncThunk(
  'billing/fetchStatus',
  async () => {
    const response = await billingApi.getBillingStatus();
    return response;
  }
);

const billingSlice = createSlice({
  name: 'billing',
  initialState: { status: null, loading: false, error: null },
  reducers: {},
  extraReducers: (builder) => {
    builder
      .addCase(fetchBillingStatus.pending, (state) => {
        state.loading = true;
      })
      .addCase(fetchBillingStatus.fulfilled, (state, action) => {
        state.status = action.payload;
        state.loading = false;
      })
      .addCase(fetchBillingStatus.rejected, (state, action) => {
        state.error = action.error.message;
        state.loading = false;
      });
  },
});

export default billingSlice.reducer;

// store/index.ts
import { configureStore } from '@reduxjs/toolkit';
import billingReducer from './billingSlice';

export const store = configureStore({
  reducer: {
    billing: billingReducer,
  },
});

// 使用側
import { useDispatch, useSelector } from 'react-redux';
import { fetchBillingStatus } from '@/store/billingSlice';

const Dashboard = () => {
  const dispatch = useDispatch();
  const { status, loading, error } = useSelector((state) => state.billing);

  useEffect(() => {
    dispatch(fetchBillingStatus());
  }, [dispatch]);

  // ...
};
```

**Context APIとの比較**:
```typescript
// Context API（現在の実装）
const { billingStatus, isLoading, error } = useBilling();

// Redux（仮に導入した場合）
const dispatch = useDispatch();
const { status, loading, error } = useSelector((state) => state.billing);
useEffect(() => {
  dispatch(fetchBillingStatus());
}, [dispatch]);
```

**結論**: けいかくんの規模ではContext APIの方がシンプル

---

#### Zustand

**メリット**:
- ✅ 軽量（1.2KB）
- ✅ ボイラープレートが少ない
- ✅ 学習コストが低い
- ✅ TypeScript対応が優秀

**デメリット**:
- ⚠️ コミュニティがReduxより小さい
- ⚠️ 歴史が浅い（破壊的変更のリスク）

**コード例（Zustand）**:
```typescript
// store/billingStore.ts
import { create } from 'zustand';

interface BillingState {
  billingStatus: BillingStatusResponse | null;
  isLoading: boolean;
  error: string | null;
  fetchBillingStatus: () => Promise<void>;
}

export const useBillingStore = create<BillingState>((set) => ({
  billingStatus: null,
  isLoading: false,
  error: null,
  fetchBillingStatus: async () => {
    set({ isLoading: true });
    try {
      const data = await billingApi.getBillingStatus();
      set({ billingStatus: data, isLoading: false });
    } catch (err) {
      set({ error: err.message, isLoading: false });
    }
  },
}));

// 使用側
const Dashboard = () => {
  const { billingStatus, isLoading, fetchBillingStatus } = useBillingStore();

  useEffect(() => {
    fetchBillingStatus();
  }, [fetchBillingStatus]);

  // ...
};
```

**Context APIとの比較**:
- Zustandの方がやや簡潔
- けいかくんではContext APIで十分（グローバル状態が1つのみ）

---

#### Recoil

**メリット**:
- ✅ Atom（最小状態単位）とSelector（派生状態）の分離
- ✅ 細粒度の状態管理
- ✅ Facebook（Meta）開発

**デメリット**:
- ❌ まだ実験的（Experimental）
- ❌ バンドルサイズが大きい（14KB）
- ❌ 学習コストがやや高い

**コード例（Recoil）**:
```typescript
// atoms/billingState.ts
import { atom, selector } from 'recoil';

export const billingStatusState = atom<BillingStatusResponse | null>({
  key: 'billingStatus',
  default: null,
});

export const canWriteSelector = selector({
  key: 'canWrite',
  get: ({ get }) => {
    const billingStatus = get(billingStatusState);
    return billingStatus?.billing_status !== BillingStatus.PAST_DUE;
  },
});

// 使用側
const Dashboard = () => {
  const [billingStatus, setBillingStatus] = useRecoilState(billingStatusState);
  const canWrite = useRecoilValue(canWriteSelector);

  // ...
};
```

**Context APIとの比較**:
- Recoilは派生状態の管理が優れている
- けいかくんでは派生状態が少ない（canWrite、isPastDue程度）

---

### 3.2 比較表

| 項目 | Context API | Redux | Zustand | Recoil |
|-----|-----------|-------|---------|--------|
| **バンドルサイズ** | 0KB | ~15KB | ~1.2KB | ~14KB |
| **学習コスト** | 低 | 高 | 低 | 中 |
| **ボイラープレート** | 少ない | 多い | 少ない | 中 |
| **パフォーマンス** | 中（最適化が必要） | 高 | 高 | 高 |
| **DevTools** | React DevTools | Redux DevTools | 基本的なツール | Recoil DevTools |
| **TypeScript対応** | 良好 | 優秀 | 優秀 | 良好 |
| **コミュニティ** | 大 | 非常に大 | 中 | 中 |
| **React 19対応** | ✅ ネイティブ | ✅ 対応 | ✅ 対応 | ⚠️ 実験的 |
| **Server Components対応** | ✅ 良好 | ⚠️ 制限あり | ⚠️ 制限あり | ⚠️ 制限あり |

**けいかくんの選択**: Context API（現段階では最適）

---

## 4. Context APIの課題と対策

### 4.1 現在の課題

#### 課題1: パフォーマンス最適化の手動管理

**問題**:
```typescript
// Dashboard.tsx
const canEdit = useMemo(() => {
  return staff?.is_mfa_enabled && isActiveBilling;
}, [staff, billingStatus]);

const handleSearch = useCallback(async (term: string) => {
  setSearchTerm(term);
}, []);
```

**対策**:
- useMemo、useCallbackを適切に使用
- React 19の自動バッチングを活用

---

#### 課題2: Context Providerのネスト

**問題**:
```typescript
// app/layout.tsx（将来的に増える可能性）
<BillingProvider>
  <AuthProvider>
    <ThemeProvider>
      <NotificationProvider>
        {children}
      </NotificationProvider>
    </ThemeProvider>
  </AuthProvider>
</BillingProvider>
```

**対策（Providerの合成）**:
```typescript
// providers/AppProviders.tsx
export function AppProviders({ children }: { children: ReactNode }) {
  return (
    <BillingProvider>
      <AuthProvider>
        {children}
      </AuthProvider>
    </BillingProvider>
  );
}
```

---

#### 課題3: Dashboardコンポーネントの状態複雑化

**問題**:
- useStateが10個以上
- useEffectが5個以上
- コンポーネントが960行と巨大化

**対策（useReducer導入）**:
```typescript
// hooks/useDashboard.ts
type DashboardState = {
  dashboardData: DashboardData | null;
  sortOrder: 'asc' | 'desc';
  sortBy: string;
  searchTerm: string;
  isLoading: boolean;
  activeFilters: FilterState;
};

type DashboardAction =
  | { type: 'SET_DASHBOARD_DATA'; payload: DashboardData }
  | { type: 'SET_SORT'; payload: { sortBy: string; sortOrder: 'asc' | 'desc' } }
  | { type: 'SET_SEARCH_TERM'; payload: string }
  | { type: 'SET_LOADING'; payload: boolean };

function dashboardReducer(state: DashboardState, action: DashboardAction): DashboardState {
  switch (action.type) {
    case 'SET_DASHBOARD_DATA':
      return { ...state, dashboardData: action.payload };
    case 'SET_SORT':
      return { ...state, sortBy: action.payload.sortBy, sortOrder: action.payload.sortOrder };
    case 'SET_SEARCH_TERM':
      return { ...state, searchTerm: action.payload };
    case 'SET_LOADING':
      return { ...state, isLoading: action.payload };
    default:
      return state;
  }
}

export function useDashboard() {
  const [state, dispatch] = useReducer(dashboardReducer, initialState);

  // アクションクリエーター
  const setDashboardData = (data: DashboardData) => {
    dispatch({ type: 'SET_DASHBOARD_DATA', payload: data });
  };

  return { state, setDashboardData, ... };
}

// Dashboard.tsx（簡潔に）
const { state, setDashboardData } = useDashboard();
```

---

## 5. 将来的に状態管理ライブラリを導入する判断基準

### 5.1 導入を検討すべきシグナル

#### シグナル1: グローバル状態が5個以上

**現在**: 1個（課金ステータス）

**将来的に増える可能性**:
- 認証状態（現在はローカル管理）
- 通知状態（未読件数など）
- テーマ設定（ダークモード）
- ユーザー設定（言語、タイムゾーン）

**判断基準**: グローバル状態が5個以上になったら**Zustand**を検討

---

#### シグナル2: コンポーネントツリーが深くなる（Prop Drilling）

**問題（Prop Drilling）**:
```typescript
<Dashboard>
  <Sidebar billingStatus={billingStatus}>
    <SidebarMenu billingStatus={billingStatus}>
      <MenuItem billingStatus={billingStatus}>
        {billingStatus.canWrite && <CreateButton />}
      </MenuItem>
    </SidebarMenu>
  </Sidebar>
</Dashboard>
```

**現状**: けいかくんはコンポーネントツリーが浅い（3-4階層）

**判断基準**: 6階層以上になったら状態管理ライブラリを検討

---

#### シグナル3: 複雑な非同期処理が増える

**現在の非同期処理**:
- 課金ステータス取得（10分ごとに更新）
- Push通知購読/解除

**将来的に増える可能性**:
- リアルタイム通知（WebSocket）
- オプティミスティックUI（楽観的更新）
- ページネーション/無限スクロール
- キャッシュ管理

**判断基準**: 非同期処理が複雑化したら**Redux Toolkit（RTK Query）**または**TanStack Query**を検討

---

#### シグナル4: 開発チームが3人以上に拡大

**現在**: 1-2人

**状態管理ライブラリのメリット（チーム拡大時）**:
- コードの一貫性
- 状態更新ロジックの標準化
- デバッグツール（Redux DevTools）

**判断基準**: チームが3人以上になったら**Redux Toolkit**を検討

---

### 5.2 移行戦略

#### ステップ1: Zustandへの部分移行（推奨）

**理由**:
- 軽量（1.2KB）
- 学習コストが低い
- Context APIと併用可能

**移行例**:
```typescript
// 1. BillingContextをZustandに移行
import { create } from 'zustand';

export const useBillingStore = create<BillingState>((set) => ({
  billingStatus: null,
  isLoading: false,
  fetchBillingStatus: async () => { ... },
}));

// 2. 他のContextは残す（段階的移行）
<AuthProvider>
  {children}
</AuthProvider>
```

---

#### ステップ2: Redux Toolkitへの完全移行（将来的）

**条件**:
- グローバル状態が10個以上
- チームが5人以上
- 複雑な非同期処理が多数

**移行コスト**: 高（全体的なリファクタリングが必要）

---

## 6. 面接で強調すべきポイント

### 6.1 技術的判断の根拠

**1. アプリケーションの規模を考慮**
- グローバル状態が1つ（課金ステータス）のみ
- Context APIで十分管理可能
- 状態管理ライブラリは**オーバーエンジニアリング**になる

**2. React 19 + Next.js 15の特性を活用**
- Context APIのパフォーマンスが向上
- Server Componentsとの親和性
- 状態管理ライブラリのメリットが相対的に減少

**3. バンドルサイズとパフォーマンスの優先**
- Context API使用で15KB削減
- 初期ロード速度を重視（モバイル対応）

---

### 6.2 ビジネス判断の根拠

**1. 開発スピードの優先**
- MVP構築フェーズ
- 学習コストの削減
- 3ヶ月以内のリリース

**2. コストとリスクのバランス**
- Context APIは追加コストなし
- React標準機能で安定性が高い
- 将来的な移行も可能（柔軟性）

---

### 6.3 将来的な拡張性の考慮

**1. 明確な移行判断基準**
- グローバル状態が5個以上 → Zustand
- 非同期処理が複雑化 → RTK Query / TanStack Query
- チームが3人以上 → Redux Toolkit

**2. 段階的移行戦略**
- Context APIとZustandの併用が可能
- 部分的な移行でリスクを最小化
- 全面的なリファクタリングは避ける

---

## 7. 実装例: 状態管理ライブラリ導入後の比較

### 7.1 Zustandに移行した場合

**Before（Context API）**:
```typescript
// contexts/BillingContext.tsx（122行）
export function BillingProvider({ children }: BillingProviderProps) {
  const [billingStatus, setBillingStatus] = useState<BillingStatusResponse | null>(null);
  const [isLoading, setIsLoading] = useState<boolean>(true);
  // ... 省略 ...
}
```

**After（Zustand）**:
```typescript
// store/billingStore.ts（約50行）
export const useBillingStore = create<BillingState>((set) => ({
  billingStatus: null,
  isLoading: false,
  error: null,
  fetchBillingStatus: async () => {
    set({ isLoading: true });
    try {
      const data = await billingApi.getBillingStatus();
      set({ billingStatus: data, isLoading: false });
    } catch (err) {
      set({ error: err.message, isLoading: false });
    }
  },
}));
```

**メリット**:
- コード量が約60%削減
- Provider不要（ネストが減る）
- TypeScript型推論が優秀

---

### 7.2 Redux Toolkitに移行した場合

**Before（Context API）**:
```typescript
// contexts/BillingContext.tsx（122行）
```

**After（Redux Toolkit）**:
```typescript
// store/billingSlice.ts（約80行）
// store/index.ts（約20行）
// 合計: 約100行 + ボイラープレート
```

**デメリット**:
- コード量が増加
- ボイラープレートが必要
- けいかくんの規模では不要

---

## 8. 関連資料

- [React Context API公式ドキュメント](https://react.dev/reference/react/createContext)
- [Redux公式ドキュメント](https://redux.js.org/)
- [Zustand公式ドキュメント](https://github.com/pmndrs/zustand)
- [Recoil公式ドキュメント](https://recoiljs.org/)
- 内部資料: `nextjs_frontend_implementation.md` - Next.js実装指針

---

**最終更新**: 2026-01-28
**作成者**: Claude Sonnet 4.5
