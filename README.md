# harness_cc — Claude Code の開発ハーネス

spec から PR までを、Claude Code のスキルで 1 本の流れにするハーネス。
「書く人と採点する人を分ける」「判断が要ったら止まる」「取り返しのつかない操作は設定で止める」の 3 つを軸にしている。

PJ ごとに違うこと（テストのコマンド、起動のしかた、ログイン、PR の作り方など）は、スキルの本文には書かない。
すべて app の `.claude/project.md` に書き、スキルはそこを読む。

## 1. スキルの流れ

```
/arch（最初に 1 回。設計の規約を変えるとき）

/spec → /plan → /accept-test → /build → /ui-check → /ac-review → /ship
                                   ↓ 壊れたら
                                /debug
```

| スキル | やること | どのセッションで |
|---|---|---|
| `/arch` | コードを数えて層の構成と依存の向きを出し、規約にするかを人に確かめながら、設計書（`docs/design/`）を書く | 人と対話 |
| `/spec` | 対話で前提と受け入れ条件（AC）を固め、`docs/spec/<タスク名>-spec.md` に書く | 人と対話 |
| `/plan` | approved な spec から、作業の順番と AC → テストの一覧を書く（中以上だけ） | 新しいセッション |
| `/accept-test` | AC から、build が読めない受け入れテストを書き、「今は落ちる」を確かめる | **build と別のモデル** |
| `/build` | plan の順に 1 ステップずつ red → green → 確認 → コミット。判断が要ったら止まる | 新しいセッション |
| `/debug` | 再現テストで red を見て、根本原因を書いて止まり、「直して」で直す | 新しいセッション |
| `/ui-check` | 動いている app を Playwright で開いて、画面の AC を確かめ、スクショを残す | 新しいセッション |
| `/ac-review` | spec と plan に照らして採点し、`docs/review/` に書く。受け入れテストもここで回す | **build と別のモデル** |
| `/ship` | レビューが pass のものを、docs と app の PR にして出す | 人と対話 |

規模で入口が変わる（`templates/CLAUDE.md` の「規模と進め方」）。
- 軽微（typo・文言・lint）はスキルを通さず直す。既存のテストで再現できるバグは `/debug`
- 小は `/plan` を飛ばす（`/accept-test` は spec の直後。任意）
- 中以上は全部通す

### 設計書を先に書く理由
ac-review は、設計書に書かれた規約に反するものを**必須**にし、設計書に根拠を書けない設計の指摘は**任意**にしかできない。
だから、大事な決まりが設計書に無いと、レビューで止められない。設計書が無い PJ では、`/arch <層>` から始める。
`/arch` は今のコードを数と根拠つきで出すだけで、規約にするかどうかは人が決める（コードは今の姿で、決まりかどうかはコードに書いていないから）。

### 別のセッション・別のモデルにする理由
同じ文脈で見ると、書いた理由がそのまま正しさに見える。受け入れテストを書くのと採点するのは、build と別のモデルで、build の会話の続きではないセッションで動かす。
build は受け入れテストを読まない・回さない（§3 の deny と build の Red Flags）。採点のときだけ ac-review が `scripts/accept.sh` で回す。

### 外の約束
新しい URL・パラメータ名・画面に渡すデータの名前・エラーコード・列は、plan.md の「外の約束」に番号付きで置く。build と accept-test はそこだけを使う。
accept-test が勝手に決めた URL に頼ると、build が別の正しい作り方をしたときに、build のせいではないのに落ちるから。

### 採点が成り立たないとき
差分に受け入れテストの写し（同じ Given / When / Then、同じロールの表、同じケース名）があれば、build が受け入れテストを読んだことになり、その回の結果は無効。
ac-review は `result: fail` にして 2 行目に「採点が成り立たない」と書いて止まり、build fix はその行を見て直さずに止まる。

## 2. 入れ方

harness_cc を clone して、app のルートを渡す:

    ./install.sh <app のルート> --dry-run   # 何をするかだけ見る
    ./install.sh <app のルート>

ファイルは 2 種類に分けて扱う。

| 種類 | ファイル | install.sh の扱い |
|---|---|---|
| **上流が持つ**（ハーネスの更新で変わる。app では書き換えない） | `.claude/skills/*`、`scripts/accept.sh`、`scripts/lib/check-lib.sh` | いつも上書き。ハーネスを更新したら、もう一度 install.sh を回す |
| **PJ が持つ**（最初に 1 回作ったら、あとは PJ が書き換える） | `.claude/project.md`、`.claude/harness.env`、`.claude/headless-build.json`、`scripts/check.sh` | 無いときだけ作る。あれば触らない |
| **app にもう設定がある** | `.claude/settings.json`、`CLAUDE.md`、`.gitignore` | 触らない。足りないものを出すので、手で足す |

入れたあとにやること（install.sh も最後に出す）:
1. `.claude/project.md` と `.claude/harness.env` の `<ここに: …>` を埋める
2. `scripts/check.sh` の `todo "…"` を、PJ のコマンドにする（§4。見本は `examples/`）
3. `.claude/headless-build.json` に、受け入れテストを直接回すコマンドの deny を足す（§3）
4. `CLAUDE.md` に `templates/CLAUDE.md` の 2 節を足す
5. docs のリポジトリを app の `docs/` に clone し、`.gitignore` に `/docs/`・受け入れテストのコピー先・`.playwright-mcp/` を足す（§5）
6. ui-check を使うなら Playwright の MCP を入れる（§6）
7. 設計書（`docs/design/`）が無ければ、`/arch <層>` で書く。`/arch` は確定のあとに、層のディレクトリに設計書の節を指す CLAUDE.md を自動で置く（人が書いた CLAUDE.md があれば、差分を見せて聞く）
8. 任意: 決まりが違う層のディレクトリ（バックエンド、テスト、フロントエンドなど）に、設計書のどの節を読むかだけを指す CLAUDE.md を置く（雛形は `templates/dir-CLAUDE.md`）。Claude Code は、そのディレクトリのファイルを読んだときにだけ読み込むので、その層を触るときにだけ決まりが入る

Claude Code は app のルートで起動する。`headless-build.json` のパス（`docs/spec/**` など）は起動したディレクトリが基準だから。

## 3. 設定で止めるもの

2 段構え。対話の Claude Code には git 操作と PR を任せるので、対話では「取り返しがつかないもの」だけを設定で止め、残りはスキルのルールで守る。
ヘッドレス（`claude -p`）では両方を設定で止める。

### いつでも禁止（`settings.json`）
- force push（`--force`、`-f`、`--force-with-lease`、`+refspec`。フラグが後ろに来る形も）
- `git reset --hard`（後ろに来る形も）
- `git clean -f`（`-fd`、`-fdx`、`-df` など f を含む組み合わせと `--force`。`-n` は通る）
- `git restore .`、`git checkout .`、`git checkout -- .`（`./` も）

deny は allow より先に評価されるので、`settings.local.json` の allow が広くても効く。
「Claude が普段書く形」に一致するだけで、`git -C . push --force` のような別の書き方は止まらない（公式の制限）。そこはスキルの「回避しない」で補う。

### build のときだけ禁止（`headless-build.json`）
呼ぶときに `--settings` で読み込ませる。

    claude -p "<指示>" --settings .claude/headless-build.json

入っているもの:
- `git add -A` / `--all` / `.` / `-u` / `--update`（後ろに来る形も）
- `git commit -a` / `-am` / `--all` / `--amend`（後ろに来る形も。メッセージ中の `" -a"` で止まるのは許容）
- `git rebase`、`git stash`、`git push`（全部）
- PR の作成: `gh pr create`
- spec と plan の書き換え: `Edit(docs/spec/**)`、`Edit(docs/plan/*-plan.md)`。todo.md は build が更新するので止めない
- 受け入れテストの読み書きと実行: `Read(docs/accept/**)`、`Edit(docs/accept/**)`、`Read(tests/Acceptance/**)`、`Edit(tests/Acceptance/**)`、`scripts/accept.sh`（4 つの呼び方）

**足すもの（PJ ごと。ここを忘れると、受け入れテストの守りが黙って空く）**
- 受け入れテストを直接回すコマンド（project.md の「受け入れテスト」）。例: `"Bash(<テストランナー> tests/Acceptance*)"` と `"Bash(<テストランナー> * tests/Acceptance*)"`
- 受け入れテストのコピー先を `tests/Acceptance/` から変えたなら、`Read` と `Edit` のパスも変える
- `gh` 以外で PR を作るなら、そのコマンドと MCP のツール名（例: `"Bash(<PR のコマンド>*)"`、`"mcp__<サーバー>__<PR を作るツール>"`）

deny は**コマンドの文字列の形**で照合する。意味で止めているわけではない。だから PJ のテストのコマンドに合わせて書かないと、何も止めないルールが残るだけで、エラーも出ない。

対話では、同じことをスキルのルール（build の Red Flags）として守る。設定では止めない。

### パスの書き方の注意（公式ドキュメントで確認）
- ファイルの権限は `Edit(path)` と `Read(path)` だけで照合される。`Write(path)` のルールは受け付けられるが一致しない。`Edit(...)` が Write・Edit・NotebookEdit をまとめて止める
- `--settings` で渡したファイルの中では、先頭 `/` のパスは「そのファイルのディレクトリ」基準になる（`/docs/spec/**` は `.claude/docs/spec/**` を指す）。
  先頭に `/` を付けない `docs/spec/**` は「現在ディレクトリ」基準なので、**必ず app のルートで起動する**
- `*` は 1 階層内だけに一致する。`docs/plan/*-plan.md` は `-todo.md` に当たらない
- `Read` の deny は Read・Grep・Glob と Bash の `cat` `head` `sed` などに効く。git の履歴（`show`、`log -p`）には効かないので、受け入れテストは app の履歴に入れない
- Bash で書く（`cat > docs/spec/x.md`、`sed -i`）経路は `Edit` ルールでは止まらない。build スキルの「spec か plan を書き換えた」の Red Flag で補う

`--restricted` を付けると project の settings.json は読まれないので、そのときは `settings.json` の内容もこのファイルに足す。
`--settings` が使えない版では、同じ内容を `--disallowedTools` に空白区切りで並べる。

### 効いているかの確かめ方
空の作業ツリーで、app のルートから:

    claude -p "次を順に実行し、各操作の結果を 1 行ずつ報告して: git status --short / git add -A / git stash list / git push --dry-run / Edit ツールで docs/spec/ にある spec の末尾に空行を 1 つ足す / Edit ツールで docs/plan/ にある todo.md の末尾に空行を 1 つ足す" --settings .claude/headless-build.json

期待: `git status --short` と todo.md の編集は通る。`git add -A`・`git stash list`・`git push --dry-run`・spec の編集は「denied」と報告される。
終わったあと todo.md の空行を戻し、`git status --porcelain` が空のままであること。`--dry-run` は、万一 deny が効かなくても push しないための保険。

## 4. 検査と採点のスクリプト

スキルは `scripts/check.sh` と `scripts/accept.sh` を名前で呼ぶ。PJ ごとのことは `.claude/harness.env` に書く。

### `.claude/harness.env`（PJ が持つ）
`accept.sh` と `check.sh` が `. .claude/harness.env` で読み込む、bash の設定ファイル。雛形は `templates/harness.env`。
中身はそのままシェルとして実行されるので、信頼できる人だけが書き換えるファイルにし、秘密情報は書かない（`.env` から読む）。

| 名前 | 種類 | 中身 |
|---|---|---|
| `accept_run` | 関数（必須） | 渡されたディレクトリのテストだけを回す。終了コードをそのまま返す |
| `harness_env` | 関数（任意） | 環境変数だけを決める（DB の向き先など）。軽いので毎回呼ばれる |
| `harness_prepare` | 関数（任意） | DB が起きているか、ビルドの生成物があるか。DB を使うテストの前にだけ呼ばれる。DB は起動しない（人がやる） |
| `ACCEPT_DEST_ROOT` | 変数 | 受け入れテストのコピー先（既定 `tests/Acceptance`） |
| `ACCEPT_GLOB` | 変数 | コピーするファイル（既定 `*`。`accept.md` はいつも除く） |
| `ACCEPT_DIR_NAME` | 変数 | コピー先のディレクトリ名: `as-is` / `studly` / `snake` |
| `CHECK_BASE` | 変数 | `check.sh --changed` の基準（既定 `origin/main`） |

`harness_env` と `harness_prepare` を分けているのは、`check.sh --quick` のように DB を使わない検査を、DB が起きていなくても回せるようにするため。

### `scripts/accept.sh <タスク名> [--keep]`（上流が持つ）
1. `docs/accept/<タスク名>/` のテストを、コピー先にコピーする
2. `harness_env` → `harness_prepare` → `accept_run <コピー先>`
3. 結果を出し、終了コードをそのまま返す（0 = 通った、1 = 落ちた・準備に失敗、2 = 使い方の誤り・設定が無い）
4. コピーを消す。落ちても、Ctrl-C や TERM で止められても消す（`--keep` なら残す）

タスク名は英小文字・数字・ハイフンだけを受け付ける。コピー先のパスに入れて `rm -rf` するので、`../` を含む名前で app の外を消さないため。
コピー先は app の `.gitignore` に入れ、普段のテストの対象（テストランナーの設定、`check.sh`）には入れない。

### `scripts/check.sh [--quick | --changed [<base>]] [--dry-run]`（PJ が持つ）
- 引数なし: 全体の検査。`--quick`: 速い検査（build が 1 ステップごとに回す）。通れば終了コード 0、1 つでも落ちれば 1
- `--changed` と `--dry-run` は任意。変更分の判定を書いた PJ だけが使う（pre-push で変更分だけを回すときなど）
- 枠組み（オプションの解析、回す／回さないの計画、`run` / `skip`、集計）は `scripts/lib/check-lib.sh`。`check.sh` にはゲートだけを書く

```bash
set -uo pipefail
cd "$(dirname "$0")/.."
. scripts/lib/check-lib.sh "$@"

GATES=("lint" "unit" "integration")
[ "$MODE" = quick ] && plan_skip "integration" "--quick"
[ "$DRY_RUN" = 1 ] && plan_print

run "lint（静的検査）" <lint のコマンド>
run "unit（DB なし）"  <unit テストのコマンド>
if planned_skip "integration" || prepare_or_fail; then
  run "integration（DB あり）" <DB を使うテストのコマンド>
fi
finish
```

check-lib.sh の決まり:
- `run "<鍵>（<説明>）" <コマンド>`: 鍵（全角の括弧より前）が計画の単位。計画で回さないなら `SKIP: <理由>` を出して飛ばす。落ちても止めず、最後に `finish` がまとめて終了コードを返す（だから `set -e` は使わない）
- `plan_skip "<鍵>" "<理由>"`: 回さない計画を積む。`--dry-run` の表示と実際の実行が、同じ計画から決まる
- `switch_full "<理由>"`: 変更分の判定ができないとき、全量に倒す。それまでに積んだ「回さない」は捨てる。判定のループは break する
- `todo "<何を書くか>"`: 雛形の埋め忘れ。回すと NG になる（埋め忘れたまま ALL GREEN にしないため）
- `port_up <ホスト> <ポート>`: bash の `/dev/tcp` でポートが開いているかを見る。DB のクライアントが無くても使える
- bash 3.2（macOS の既定）でも動くように書く。連想配列を使わない。空の配列は `${a[@]+"${a[@]}"}` で展開する

### 見本（`examples/`）
- `examples/laravel-vue/`: Laravel + Inertia + Vue（PHPUnit / phpstan / pint、vue-tsc / oxlint / vitest、PostgreSQL）。`--changed` の判定表つき。実際の PJ で使っていたものから、その PJ だけの事情を抜いた形

## 5. docs のリポジトリ

spec・plan・todo・review・debug・受け入れテストは、app とは別の git リポジトリに置き、app の `docs/` に clone する。app の `.gitignore` で `/docs/` ごと無視する。

```
docs/
  spec/<タスク名>-spec.md
  plan/<タスク名>-plan.md, <タスク名>-todo.md
  accept/<タスク名>/accept.md と受け入れテスト
  review/<タスク名>-review-<n>.md
  debug/<YYYY-MM-DD>-<短い名前>.md
```

- **git 操作の書き方。** スキル内の docs の git 操作は `(cd docs && git add <path> && git commit -m "...")` の形で書く。
  `-C docs` を付けた git は deny のパターン（`Bash(git add -A*)` など）に一致しないため使わない。deny はサブシェルや `cd docs && ...` の中にも効く（公式ドキュメントで確認）
- **ブランチ。** build の todo と ac-review のレビューは、手元の docs のベースブランチに積む。`/ship` が `ship/<タスク名>` を切って PR にする。docs の remote のベースブランチに直接 push はしない
- **スクショ。** docs には入れない。project.md の「スクショ」の置き場（git 管理外）に置き、PR に要るものは `/ship` が project.md の方法で付ける
- **受け入れテスト。** `docs/accept/<タスク名>/`。app の履歴には入れない。採点のときだけ `scripts/accept.sh` が app にコピーして回す

### PJ で決めておくこと
- **worktree で並行作業するとき、docs をどう見せるか。** worktree ごとに docs をコピーするなら、そこで積んだコミットは自動では本体に届かない。`/ship` の docs の PR で戻す形にすると、worktree を消す前に回収できる。project.md の「並行作業」に書く
- **docs の PR のマージのしかた。** squash マージにすると、手元の docs のベースブランチに積んだ todo・review のコミットと、remote のコミットが別物になって分かれる。普通のマージなら `git pull` でそろう

## 6. Playwright の MCP（ui-check 用）

ui-check は Playwright の MCP サーバーで動いている app を開く。Claude in Chrome は使わない（人のログイン済みブラウザを触るので、結果が揺れる）。

Claude Code の中で:

    /plugin install playwright@claude-plugins-official

プラグインを使わずに入れるなら `claude mcp add playwright -- npx @playwright/mcp@latest`（user スコープなら `-s user`）。
ツール名の接頭辞は入れ方で変わる（プラグイン経由は `mcp__plugin_playwright_playwright__browser_*`、直接なら `mcp__playwright__browser_*`）が、
ui-check は `browser_navigate` のような短い名前で指しているので、どちらでも動く。ブラウザが無いというエラーが出たら `npx playwright install chromium`。

気をつけること:
- **ファイルを書けるのは、Claude Code を起動したディレクトリ（workspace root）の下だけ。** スクショの置き場はその下にし、絶対パスで指定する
- 既定の出力先は root 直下の `.playwright-mcp/`（console のログや snapshot が溜まる）。`.gitignore` に入れる
- MCP サーバーは Bash のサンドボックスの外で動く。逆に、サンドボックスの中で上げた app は外への通信が通らないことがある。app は人が上げる（ui-check の前提）
- Playwright が開くのは自前の Chromium で、人のブラウザのセッションとは別。ログインは毎回 ui-check がやる
- ヘッドレス（`claude -p`）で ui-check を回すなら、Playwright のツールを許可する設定（`--allowedTools` など）が要る

## 7. このリポジトリの中身

```
README.md                  この説明
install.sh                 app に入れる・更新する
settings.json              いつでも禁止（app の .claude/settings.json へ）
headless-build.json        build のときだけ禁止（app の .claude/ へ。PJ ごとに足す）
skills/                    9 つのスキル（app の .claude/skills/ へ。arch は設計書のテンプレートつき）
scripts/accept.sh          受け入れテストを採点のときだけ回す（app の scripts/ へ）
scripts/lib/check-lib.sh   check.sh の枠組み（app の scripts/lib/ へ）
templates/project.md       PJ ごとの値を書く雛形（app の .claude/project.md へ）
templates/harness.env      スクリプトが読む PJ ごとの設定の雛形（app の .claude/harness.env へ）
templates/scripts/check.sh 検査の雛形（app の scripts/check.sh へ）
templates/CLAUDE.md        規模と進め方・3 段階の雛形（app の CLAUDE.md へ足す）
templates/dir-CLAUDE.md    ディレクトリごとの CLAUDE.md の雛形（任意）
examples/                  PJ の見本（今は laravel-vue）
```

スキルの中の例（会議室予約の app、`AC-RCR-2` など）は、説明のための架空のもの。
