# 手動SQL運用からAlembic管理へ移行する妥当性と計画

作成日: 2026-07-01

## 背景

これまでのDB変更は、基本的に手動SQLで実装・反映してきた。Alembicのmigrationファイルは存在していても、実DBの状態と直接対応していないものが多く、体感として90%以上はDB実態とAlembic履歴が一致していない前提で考える。

この状態で「DB変更は原則Alembicを正とする」方針へ移行できるかを判断し、移行する場合の現実的な進め方を整理する。

## 結論

Alembicへ移行すること自体は現実的。ただし、過去の全変更履歴を正確にAlembicで再現し直す方針は現実的ではない。

妥当な方針は、過去履歴の完全復元ではなく、現在のDB実態を基準点として固定し、その時点以降の変更をAlembicで管理する方式にすること。

つまり、目標は次の形にする。

- 過去: 手動SQLで作られた現在のDB状態を「既存の正」として扱う。
- 移行時点: DB実態とAlembicの基準revisionを照合して、現在地点を明示する。
- 今後: 新しいDB変更はAlembic migrationを正とし、手動SQLは確認用・緊急用に限定する。

## 判断の妥当性

### Alembicへ移行する価値は高い

理由:

- 本番・テスト・ローカルでDB状態の差分が見えやすくなる。
- enum、CHECK制約、index、FK、nullable変更などの反映漏れを減らせる。
- PR単位でDB変更をレビューしやすくなる。
- 手動SQLの二重適用や適用漏れを避けやすい。
- 将来的に新しい環境を作るとき、DB初期化手順を再現しやすくなる。

特に現在はNeonDBをlocal/test/prodで共通利用しているため、手動SQLの実行対象を間違えた場合の影響が大きい。Alembicに寄せる価値は十分にある。

### ただし、過去履歴の完全復元は避けるべき

理由:

- 既にDBへ直接反映済みの変更が多く、migration履歴から再現できない。
- 既存migrationを無理に実行すると、既存テーブル・enum・制約・indexの重複で失敗しやすい。
- 途中の履歴を推測で作ると、実DBとの差分がさらに分かりづらくなる。
- 本番DBに対して破壊的なmigrationを誤適用するリスクが高い。

したがって、移行方針は「履歴をきれいに作り直す」ではなく「現在地点を安全に固定する」が妥当。

## 推奨方針

### 方針A: 現在DBをbaselineとして固定する

推奨。

現在のDBスキーマを正として扱い、Alembic上に「ここから先を管理する」という基準revisionを作る。

ポイント:

- 既存DBに対して過去migrationを一括実行しない。
- まずDB実態とコード上のモデル差分を確認する。
- 既存DBには `alembic stamp` 相当で現在地点を記録する。
- 以後のDB変更は必ずAlembic migrationを作る。

メリット:

- 本番DBを壊すリスクが最も低い。
- 過去の手動SQL運用を否定せず、今後の管理だけを改善できる。
- 段階移行できる。

デメリット:

- 過去の完全な変更履歴はAlembic上には残らない。
- 新規DBをゼロから作る場合、別途schema dumpや初期化手順が必要になる可能性がある。

### 現在確認できているDBブランチ差分

2026-07-01時点の確認では、NeonDBのDBブランチごとにAlembic管理状態が揃っていない。

- `dev`
  - `alembic_version` テーブルが存在する。
  - `version_num` は `m2n3o4p5q6r7` と `n3o4p5q6r7s8` の2行が存在する。
- `main`
  - `alembic_version` テーブルが存在しない。
- `main_test`
  - `alembic_version` テーブルが存在しない。
- `dev_test`
  - `alembic_version` テーブルが存在しない。

この状態は、Alembicから見ると「devだけが途中まで管理されているように見えるが、他環境は未管理」という扱いになる。さらに、`k_back/migrations/versions` 側にも次の問題がある。

- `a1b2c3d4e5f6` のrevision IDが複数migrationファイルで重複している。
- `byddyrpnnpk5` が `su6cug3oavuk` を `down_revision` として参照しているが、Alembicが参照関係を解決できず `KeyError: 'su6cug3oavuk'` で停止している。
- そのため、現時点では `alembic heads` / `alembic branches` / `alembic current` が正常に使えない。

したがって、baseline revisionを決める前に、DB側だけでなくmigrationファイル側のrevisionグラフを修復する必要がある。

## DBブランチ間の統一方法

### 統一方針

全DBブランチを「同じbaseline revisionを指す状態」に揃える。ただし、DBスキーマ変更を伴うmigration実行で揃えるのではなく、まずは各DBブランチの実スキーマを確認し、同じ状態と判断できる範囲で `alembic_version` を揃える。

重要なのは、`alembic_version` を作ること自体ではない。各DBブランチの実スキーマが、baselineとして定義する状態と一致していることを確認すること。

### 推奨手順

1. migrationファイル側のrevisionグラフを修復する。
   - 重複しているrevision IDを解消する。
   - 存在しない、または解決不能な `down_revision` を修正する。
   - `alembic heads` が正常に返る状態にする。

2. 各DBブランチでschema snapshotを取得する。
   - `main`
   - `dev`
   - `main_test`
   - `dev_test`

3. 各DBブランチで最低限の比較対象を揃える。
   - テーブル一覧
   - enum一覧
   - CHECK制約
   - FK制約
   - index一覧
   - nullable/default
   - 重要カラム

4. `dev` の既存 `alembic_version` を評価する。
   - `m2n3o4p5q6r7`
   - `n3o4p5q6r7s8`
   - この2つが現在の実DB状態を正しく表しているか確認する。
   - 正しく表していない場合、`dev` の `alembic_version` は信頼せず、baseline移行時に整理対象とする。

5. baseline revisionを新しく定義する。
   - 過去履歴の末尾としてではなく、「現在DB状態を基準にした管理開始地点」として扱う。
   - migration内容は原則空、または確認用コメント中心にする。
   - 実DBに変更を加えない。

6. 各DBブランチにbaselineを記録する。
   - 既存の `alembic_version` がないDBブランチでは、テーブル作成または `stamp` 相当でbaselineを記録する。
   - `dev` は既存2行をどう扱うかを決めてから揃える。
   - いずれもschema snapshotと照合したうえで実施する。

7. baseline後の最初のmigrationは小さく非破壊的なものにする。
   - 例: 存在確認付きindex追加、またはコメント/軽微なnullable確認など。
   - これにより、全DBブランチでAlembic運用が機能するか検証する。

### `dev` の既存 `alembic_version` の扱い

`dev` だけに `alembic_version` が存在するため、単純に他DBブランチへ同じ値をコピーするのは避ける。

理由:

- `dev` の2つのversionが実スキーマを正しく表している保証がない。
- 他DBブランチのスキーマが `dev` と同一とは限らない。
- Alembic履歴グラフが壊れているため、その2つのrevisionをAlembicが正しく解釈できない可能性がある。

推奨:

- `dev` の `alembic_version` は「参考情報」として扱う。
- baseline決定時には、`dev` も含めて全DBブランチを同じ新baselineへ揃える。
- 既存2行を残すか削除するかは、migrationグラフ修復後に決める。
- 複数head運用を意図していないなら、最終的には1つのbaseline revisionへ統一する方が扱いやすい。

### 統一時の懸念点

- `main` / `main_test` / `dev_test` に `alembic_version` がないため、Alembic上は未管理DBに見える。
- `dev` だけに2行あるため、複数headまたは途中までのstamp状態に見える。
- migrationファイル側のrevisionグラフが壊れているため、現在のままでは `alembic stamp` や `alembic current` の信頼性が低い。
- DBブランチ間で手動SQLの適用状況が違う場合、同じbaselineを記録しても実スキーマが一致しない可能性がある。
- `alembic_version` を揃える作業はschema変更ではないが、今後のmigration適用可否に直接影響する。
- 誤ったbaselineを記録すると、後続migrationが「既に適用済み」と誤認される。

### 統一の受け入れ要件

- [ ] migrationファイル側のrevisionグラフが修復され、`alembic heads` が成功する。
- [ ] 各DBブランチのschema snapshotが保存されている。
- [ ] `dev` の既存 `alembic_version` 2行の意味が確認されている。
- [ ] baseline対象revisionが1つに決まっている。
- [ ] `main` / `dev` / `main_test` / `dev_test` のbaseline記録方針が同じである。
- [ ] baseline記録前後でDBスキーマが変化しないことを確認している。

### 方針B: 過去の全migrationを再構築する

非推奨。

理論上は可能だが、現状の前提では工数とリスクが大きすぎる。

問題:

- 実DBとの差分確認に時間がかかる。
- 手動SQLの適用順序が完全に追えない可能性が高い。
- migrationを実行しても既存DBでは重複エラーが起きやすい。
- 履歴再現に集中しすぎて、実際の機能改善が止まる。

採用する場合でも、新規環境構築が必須要件になった後でよい。

### 方針C: 手動SQL運用を継続する

短期的には可能だが、中長期では非推奨。

問題:

- DB変更の正がSQLファイル、実DB、コード、ドキュメントに分散する。
- 本番反映漏れ・二重反映・環境差分が起きやすい。
- enumやCHECK制約のようなアプリ挙動に直結する変更で事故が起きやすい。

緊急修正では手動SQLを許容してもよいが、その場合も後追いでAlembic migrationへ反映する運用が必要。

## 移行プラン

### Phase 0: 移行前の棚卸し

目的:

- 現在のDB実態、Alembic履歴、SQLドキュメントの差分を把握する。

確認対象:

- 実DBのテーブル一覧
- enum一覧
- CHECK制約
- FK制約
- index一覧
- nullable/default
- `alembic_version` テーブルの有無と値
- `k_back/migrations/versions` のrevision一覧
- 手動SQLドキュメント

実施内容:

- 本番相当DBのschema-only dumpを取得する。
- Alembic current/headを確認する。
- SQLドキュメントに残っている変更とDB実態を照合する。
- 重要テーブルから優先して差分表を作る。

完了条件:

- [ ] 現在DBのschema snapshotが保存されている。
- [ ] Alembicが現在どのrevisionを指しているか確認できている。
- [ ] enum、制約、indexの主要差分が一覧化されている。
- [ ] 既存migrationを本番DBへそのまま流してよい状態ではないことを確認している。

### Phase 1: baseline方針を決める

目的:

- Alembic上の「現在地点」を決める。

実施内容:

- 既存migrationの最新headを確認する。
- 既存migrationが実DBと大きく乖離している場合、現在DBを基準にしたbaseline revisionを作る。
- 既存DBにはmigrationを実行せず、検証後に `stamp` で現在地点を記録する。

注意:

- `stamp` はDBスキーマを変更しない。Alembicの管理上の現在revisionだけを記録する。
- そのため、stamp前に「現在のDBがそのrevision相当である」と判断できる照合資料が必要。
- 判断できない場合は、無理にstampせず、差分確認を優先する。

完了条件:

- [ ] baseline revision名が決まっている。
- [ ] stamp対象のDB環境が明確になっている。
- [ ] stamp前後でDBスキーマが変わらないことを確認している。
- [ ] rollback方針がある。

### Phase 2: 以後のDB変更ルールを固定する

目的:

- 新規DB変更の正をAlembicへ寄せる。

ルール:

- DB変更は必ずAlembic migrationを作る。
- 手動SQLを実行した場合は、同じ内容をAlembicへ後追い反映する。
- migrationにはupgradeだけでなく、可能な範囲でdowngradeまたは復旧手順を書く。
- enum変更、CHECK制約、index追加は確認SQLをセットにする。
- 本番適用前に、対象DBの現在revisionと差分確認SQLを記録する。

完了条件:

- [ ] PRテンプレートにmigration確認項目がある。
- [ ] 手動SQLだけで完了するDB変更がなくなる。
- [ ] migration適用前後の確認SQLがmdに残る。

### Phase 3: 重要領域から差分を吸収する

目的:

- 既存DBとモデル・migrationの差分を、リスクの高い順に解消する。

優先順位:

1. 課金関連
   - `billings`
   - `webhook_events`
   - billing status enum
   - subscription/customer関連カラム
2. 認証・スタッフ関連
   - `staffs`
   - MFA関連
   - password reset関連
3. 事業所・利用者・支援計画関連
   - `offices`
   - `welfare_recipients`
   - support plan関連
4. 通知・メッセージ・申請関連
   - `notices`
   - `messages`
   - approval/action request関連
5. Google Calendar縮退対象
   - `calendar_events`
   - Google連携設定関連

進め方:

- 1領域ずつ実DB、SQLAlchemy model、Alembic、手動SQLを比較する。
- 差分がある場合、既存DBを壊さない補正migrationを作る。
- 既にDBに存在する制約やindexは、重複作成しないように存在確認付きで扱う。
- destructiveな変更は別PRに分ける。

完了条件:

- [ ] 重要領域ごとにDB実態とモデルの差分が確認されている。
- [ ] 補正migrationは既存DBに対して冪等性または事前確認手順を持つ。
- [ ] 本番適用前にschema-only backupまたは復旧手順がある。

### Phase 4: 新規環境構築の再現性を整える

目的:

- 将来的に新しいDBを作る必要が出たときに、手順が破綻しないようにする。

実施内容:

- baseline後のmigrationだけで足りない場合、schema dumpを初期化資材として管理する。
- ある程度整理できた段階で、初期schema migrationを作り直すか判断する。
- seedデータ、enum、extension、初期管理者作成手順を分ける。

完了条件:

- [ ] 新規DBを作るための暫定手順がある。
- [ ] Alembicだけで作れる範囲と、別途必要な初期化SQLが分かれている。
- [ ] 本番DBの履歴管理と新規DB構築手順が混同されていない。

## 最初にやるべきこと

まずはmigrationを実行しない。確認だけ行う。

最初のタスク:

- [ ] `alembic_version` テーブルの有無と値を確認する。
- [ ] `alembic current` と `alembic heads` を確認する。
- [ ] 本番相当DBのschema-only dumpを取得する。
- [ ] 既存migration一覧を作る。
- [ ] `billings` / `webhook_events` / billing status enum から差分確認を始める。
- [ ] Alembic移行のbaseline候補revisionを決める。

## リスク

### 既存migrationを誤って実行するリスク

最も避けるべき。

既に存在するテーブル、enum、制約、indexを再作成しようとして失敗するだけでなく、途中まで適用されると復旧が難しくなる可能性がある。

対策:

- 本番DBに対して `upgrade head` をいきなり実行しない。
- 先にschema dumpと照合資料を作る。
- 必要なら読み取り専用の確認から始める。

### stampの誤用リスク

`stamp` はDBを変更しないため、実DBがそのrevision相当でなくても記録だけ進められてしまう。

対策:

- stamp前に照合資料を作る。
- stamp対象のrevisionが何を意味するかmdに残す。
- stamp後の最初のmigrationは小さく、非破壊的な変更で検証する。

### 手動SQLとの二重管理リスク

移行期間中は、手動SQLとAlembicが併存する。

対策:

- 手動SQLを実行したら、必ずAlembic反映予定を作る。
- 「確認SQL」と「変更SQL」をmd上で明確に分ける。
- DB変更PRでは、実行済み手動SQLの有無を書く。

## 採用判断

採用すべき。

ただし、採用条件は次の通り。

- 過去履歴の完全復元を目標にしない。
- 現在DBをbaselineとして固定する。
- 既存DBに対してmigrationをいきなり実行しない。
- 重要領域から差分確認し、以後の変更だけAlembicを正にする。
- 手動SQLは当面残すが、役割を確認用・緊急用に限定していく。

この方針であれば、リスクを抑えながらAlembic管理へ移行できる。
