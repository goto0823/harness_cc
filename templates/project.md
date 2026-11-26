# project.md — この PJ の固有の情報

ハーネスのスキルは、PJ ごとに違うことをスキルの本文に書かず、すべてこのファイルから読む。
app の `.claude/project.md` に置き、`<ここに: …>` を PJ の値で埋める。使わない項目は「なし」と書く（消さない。スキルが「なし」を見て飛ばす）。
スキルは見出しの名前（「## 1 本だけ回す」など）で参照するので、見出しは変えない。

秘密情報（本番の認証情報、API キー）は書かない。書いてよいのは、手元の開発環境でだけ使う確認用のアカウントまで。

---

## 置き場
- app のリポジトリ: <ここに: 例 `owner/app`>
- docs のリポジトリ: <ここに: spec・plan・todo・review・debug・受け入れテストを置く、app とは別の git リポジトリ。app の `docs/` に clone し、app の `.gitignore` で `/docs/` ごと無視する>
- PR の向き先（app のベースブランチ）: <ここに: 例 `main`。既定の値。タスクごとに変えるなら `/spec` が聞いて spec の `base:` に書き、build・ac-review・deliver はそちらを使う（hotfix だけ `main`、リリース前の修正は `release/1.2` など）。deliver は最後に app をこのブランチに戻す>
- docs のベースブランチ: <ここに: 例 `main`。build の todo と ac-review のレビューは手元のこのブランチに積む>
- docs の出し方: <ここに: `PR` か `直接 push`。`PR` は `/deliver` が `deliver/<タスク名>` を切って docs の PR を出す（docs もレビューする PJ 向け）。`直接 push` は `/deliver` がブランチを切らずにベースブランチへ push し、docs の PR は作らない（docs をレビューしない PJ、docs を共有して並行作業する PJ 向け。deliver の最中に他のタスクが docs にコミットしても混ざらない）>
- docs のファイルの URL: <ここに: `直接 push` のときに要る。コミットとパスから docs のファイルを開く URL の形。例 `https://github.com/owner/docs/blob/<ハッシュ>/<パス>`。`PR` なら「なし」でよい>
- 設計書: <ここに: 例 `docs/design/`。無ければ「なし」（`/arch <層>` で書ける）>
- ディレクトリごとの CLAUDE.md: <ここに: 例 `app/CLAUDE.md` → `docs/design/backend.md`、`tests/CLAUDE.md` → テストの書き方の決まり。無ければ「なし」。雛形は harness_cc の `templates/dir-CLAUDE.md`>
- テストの書き方の決まり: <ここに: 例 `docs/design/test-strategy.md`。置き場・命名・文言の比べ方>

## 検査
`scripts/check.sh` はハーネスのスキルが呼ぶ、PJ が持つスクリプト（雛形は `templates/scripts/check.sh`。README §4）。
- 全体: `scripts/check.sh`（<ここに: 何を回すか。例 lint・型・全テスト。DB が要るか>）
- 速い: `scripts/check.sh --quick`（<ここに: 何を回すか。DB に触らない範囲など>）
- pre-push で回るか: <ここに: はい / いいえ>

## 1 本だけ回す
- テスト 1 本: <ここに: 例 `<テストランナー> --filter=<テスト名>`>
- 1 ファイル: <ここに>
- 並列にせず順番に回す（テストの汚染を確かめるとき）: <ここに: 無ければ「なし」>

## 受け入れテスト
- 置き場（docs の中）: `docs/accept/<タスク名>/`（ハーネスの決まり）
- コピー先・ファイル名のパターン・回し方は `.claude/harness.env` の `ACCEPT_DEST_ROOT` / `ACCEPT_GLOB` / `accept_run` と同じにする
- 採点のときのコピー先（app の中。app の `.gitignore` に入れる）: <ここに: 例 `tests/Acceptance/`>
- ファイル名: <ここに: 例 `<画面か操作>AcceptanceTest.<拡張子>`>
- 継承する土台・使うヘルパー: <ここに: 例 テストの基底クラス、ロールでログインするヘルパー、結果を比べるヘルパー>
- ロールの書き方（ロールごとに期待を並べる表の行の名前）: 「## ロール」の「### 認可の表の行」の名前をそのまま使う（ここには書かない。名前を 2 か所に書くと、片方だけ直してずれる）
- 文言の比べ方: <ここに: 例 翻訳キーで比べる。spec が文言を約束しているときだけ文言で比べる>
- 受け入れテストを直接回すコマンド（build の deny に足す）: <ここに: 例 `<テストランナー> <コピー先>`>

## ロール
ロールの一覧の場所: <ここに: 例 コードのどのファイルか>

| ロール | 略号（スクショの名前に使う） | できること（概要） |
|---|---|---|
| <ここに> | <ここに> | <ここに> |

- よそ（認可で必ず確かめる相手）: 「### 認可の表の行」で「よそ」の列に `○` を付けた行（ここには書かない）

### 認可の表の行
spec の承認の前に、`/ac-matrix`（spec を書いた会話とは別の会話）が「誰がどの操作をできる・できないか」の表を埋める（spec の 5a）。表の行は、`scripts/ac-matrix.sh` がこの表から作る。
**ロールの表の行の名前と「よそ」は、ここ 1 か所に書く。** 受け入れテストのロール別の行、設計書のテスト方針（`docs/design/test-strategy.md` の「認可の表の書き方」）も、この名前を使う。
ここにある行は表から消せないので、「よそ」も全部ここに 1 行ずつ書く。タスクにしか出てこない相手（「予約した本人」など）は、`/ac-matrix` が AC から足す。
1 列目が行の名前（表にそのまま出る）、2 列目が「よそ」なら `○`（違えば空）、3 列目が埋める人への説明。

| 行 | よそ | 説明 |
|---|---|---|
| <ここに: 例 同じ拠点の利用者> | | <ここに: 例 自分の拠点のデータだけを扱う一般のユーザー> |
| <ここに: 例 同じ拠点の管理者> | | <ここに> |
| <ここに: 例 他の拠点の管理者> | ○ | <ここに: 例 別の拠点の管理者> |
| <ここに: 例 ゲスト> | ○ | <ここに> |
| <ここに: 例 未ログイン> | ○ | <ここに> |

## app の起動と URL
- 起動のしかた（人がやる。スキルは起動しない）: <ここに: 例 `<起動コマンド>`>
- 本体の URL: <ここに: 例 `http://localhost:<port>`>
- worktree の URL: <ここに: 例 worktree ごとのポートの決め方。並行作業しないなら「なし」>
- DB に向けた環境変数（テストやコマンドを手で回すとき）: <ここに: 例 本体と worktree での違い>
- サンドボックスの中で app を上げてはいけない理由があれば: <ここに: 無ければ「なし」>

## ログイン
ui-check が使う。
- 手順: <ここに: 開く URL → 入れる項目（ラベルか role で書く）→ 押すボタン>
- ログインできたと分かる URL や表示: <ここに>
- ログアウト: <ここに>
- 失敗したときの見分け方と直し方: <ここに: 例 seed を入れ直すコマンド>

| ロール | ログイン ID | パスワード | 備考 |
|---|---|---|---|
| <ここに: 手元の開発環境の確認用アカウントだけ> | | | |

## スクショ
ui-check が撮り、ac-review と deliver が使う。
- 置き場（git 管理外。本体と worktree で同じ場所）: <ここに: 例 app の 1 つ上の `local/screenshots/`。Playwright の MCP は Claude Code を起動したディレクトリの下にしか書けないので、その下にする>
- 記録に書くパスの基準: <ここに: 例 「置き場の 1 つ上からの相対 `local/screenshots/<タスク名>/<ファイル名>`」>
- app のセッションから開くとき: <ここに: 例 `../local/screenshots/...`>

## 並行作業
worktree で、同時に 2 つ以上のタスクを進めるとき（`/pm run` もこれを使う。`/pm run` は herdr（https://github.com/ogulcancelik/herdr）のパネルの中で使う。`herdr integration install claude` を入れておくと、cc の状態の見分けが確かになる）。並行作業しないなら、全部「なし」と書く。
- 置き場: <ここに: 例 app の 1 つ上の `wt/`。worktree は `<置き場>/<タスク名>` に作る>
- 始め方: <ここに: 例 `git fetch origin && git worktree add --detach <置き場>/<タスク名> origin/<PR の向き先>` → `ln -s "$(pwd)/docs" <置き場>/<タスク名>/docs` → `cp .env <置き場>/<タスク名>/`。ブランチは切らない（`--detach`）。build が入口で spec の `base:` から切る>
- 終わり方: <ここに: 例 PR がマージされたら、worktree の app を止めてから `herdr worktree remove --workspace <ID>`（herdr を使わないなら `git worktree remove <置き場>/<タスク名>`）。`/pm run` の会話で「<タスク名> マージした」と言えば、pm が未コミット・push していないコミットが無いのを確かめてから、ここに書いた「消す前の手順」も打って片付ける>
- worktree の中の docs: <ここに: 本体の docs へのシンボリックリンクで共有する（推奨）か、コピーか。共有するなら「docs の出し方」は `直接 push` にする（`PR` だと deliver が docs のブランチを切り替えている間、他のタスクのコミットがその PR に混ざる）。各スキルは docs の自分のタスクのファイルだけを見て、`git commit -- <パス>` で自分のファイルだけをコミットする。共有の docs では `--amend`・rebase・reset で履歴を書き換えない（ほかのタスクのコミットを巻き込む）。直したいときは新しいコミットを積む。共有するなら `.claude/headless-build.json` に本体の docs の `additionalDirectories` と絶対パスの deny を足す（README §3 の「足すもの」）。足さないと build が todo.md を書けずに止まる>
- worktree ごとに分けるもの: <ここに: 例 テストの DB 名（`.claude/harness.env` の `harness_env` で、worktree のディレクトリ名から `app_test_<タスク名>` を作る）、app のポート、`.env` の値。分けないと、同時に回る build のテストが互いのデータを消して、コードが正しくても落ちる>
- 同時に回すタスクの数: <ここに: 例 `2`。テストの DB とポートを分けられないなら `1`（spec・plan・受け入れテストだけ並べたいときも `1` にして、人が別の会話で回す）>
- 子の cc の起動（`/pm run` が `herdr agent start <名前> --kind claude --pane <パネル> -- <ここの引数>` で使う）: <ここに: 例 `--model opus --permission-mode auto`。`acceptEdits` で自動で通るのは編集だけで、`git` や `scripts/check.sh` は毎回子のパネルで確認のダイアログになる。auto でも分類器が危ないと見た操作は確認になり、人がそのパネルで答える（pm は答えない）。auto を使わないなら、子が使うもの（編集、`scripts/check.sh`、docs と app の `git add` / `git commit`、`claude -p`（build））を `.claude/settings.local.json` の allow で通す。`git push`（deliver）は、deliver が人の「出す」を待つので、確認が出てもよい。worktree の docs や `local/` を本体へのシンボリックリンクで共有するなら、リンク先の絶対パスを `--add-dir <本体>/docs --add-dir <本体>/local` で足す（cc はリンク先の実体で作業ディレクトリの中かを見るので、足さないと spec・plan・todo や orchestrate の `local/orchestrate/` に書くたびに、auto でも確認で止まる）。本体のルートごとは足さない（子が本体の app のコードを書けてしまう）>

## PR と課題管理
- PR を作るコマンド: <ここに: 例 `gh pr create --base <ベース> --head <branch> --title "<タイトル>" --body-file <本文のファイル>`>
- docs の PR を作るコマンド: <ここに: docs のリポジトリが別のサービスならそのコマンド。「docs の出し方」が `直接 push` なら「なし」>
- スクショを PR に付ける方法: <ここに: コマンドで付けられるならその手順。付けられないなら「本文にファイル名を書き、人が手で添付する」>
- 付いたかの確かめ方: <ここに: 無ければ「なし」>
- 認証情報の扱い: <ここに: 例 トークンを出すコマンドはコマンド置換の中でだけ使い、画面に出さない>
- 課題のキー: <ここに: 例 `PROJ-123` の形。spec には入れない>

## 課題管理（Backlog）
`/pm` が bee（Backlog の CLI。`npm install -g @nulab/bee` → `bee auth login`）で使う。`/pm` を使わないなら、全部「なし」と書く。
ID は `bee issue-type list -p <プロジェクトキー> --json`、`bee status list -p <プロジェクトキー> --json` で調べる。
- スペース: <ここに: 例 `xxx.backlog.com`>
- プロジェクトキー: <ここに: 例 `PROJ`>
- 親課題（タスク）の種別 ID: <ここに: 例 `12345`（「タスク」）>
- 子課題（作業ステップ）の種別 ID: <ここに: 例 `12346`（「サブタスク」）>
- 状態 ID: <ここに: 例 未対応 `1` / 処理中 `2` / 処理済み `3` / 完了 `4`>
- 説明の記法: <ここに: `markdown` か `backlog`（プロジェクトの設定の「テキスト整形のルール」）>
- 課題の URL の形: <ここに: 例 `https://xxx.backlog.com/view/<課題キー>`>

## デバッグ用のログ
コミットの前に `git diff` から探して消すもの: <ここに: 例 `dd(`、`console.log`、`print(`>

## 外の約束の種類
plan の「外の約束」に書くものに、ハーネスの決まり（URL・パラメータ名・画面に渡すデータの名前・エラーコード・列）のほかに足すもの: <ここに: 無ければ「なし」>

## 層
debug が、どこで壊れているかを絞るときに使う。
<ここに: 例 画面 / コントローラー / ユースケース / リポジトリ・DB / 外部連携 / ビルド・設定>
