# scripts/lib/check-lib.sh — scripts/check.sh の枠組み（オプションの解析・回す／回さないの計画・実行・集計）
#
# ハーネス（harness_cc）が持つファイル。PJ のゲート（何を回すか）は scripts/check.sh に書き、このファイルは書き換えない。
# scripts/check.sh の先頭で、app のルートに cd してから読み込む:
#
#   set -uo pipefail
#   cd "$(dirname "$0")/.."
#   . scripts/lib/check-lib.sh "$@"
#
# 読み込むと次が決まる:
#   MODE      full（既定）| quick（--quick）| changed（--changed [<base>]）
#   DRY_RUN   1 なら計画だけ出して実行しない（--dry-run）。check.sh は plan_print を呼んで終える
#   --changed のとき: CHANGED_FILES（基準から作業ツリーまでの変更ファイル。未コミット・未追跡を含む）と BASE_SHA
#
# .claude/harness.env があれば読み込み、harness_env があれば呼ぶ（環境変数だけを決める軽い関数）。
# harness_prepare（DB が起きているか、ビルドなど）は、DB を使うゲートの前で check.sh が prepare_or_fail で呼ぶ。
#
# bash 3.2（macOS の既定）でも動くように書く: 連想配列を使わない。空の配列は ${a[@]+"${a[@]}"} で展開する。
# set -e は使わない。1 つのゲートが落ちても残りを回し、最後に finish がまとめて終了コードを返すため。

MODE=full
DRY_RUN=0
BASE_ARG=""
for __arg in "$@"; do
  case "$__arg" in
    --quick)   MODE=quick ;;
    --changed) MODE=changed ;;
    --dry-run) DRY_RUN=1 ;;
    -*) echo "check.sh: 不明なオプション: ${__arg}（--quick / --changed [<base>] / --dry-run）" >&2; exit 2 ;;
    *)  BASE_ARG="$__arg" ;;
  esac
done
unset __arg

if [ -f .claude/harness.env ]; then
  # shellcheck source=/dev/null
  . ./.claude/harness.env
fi
if declare -F harness_env >/dev/null; then
  harness_env
fi

# ---- 計画: ゲートごとに「回さない理由」「回す理由」を積む ----
# ゲートは run "<鍵>（<説明>）" <コマンド> で呼ぶ。鍵（全角の括弧より前）が計画の単位。
# 既定（全量 / --quick）はすべて回す。--changed では check.sh が CHANGED_FILES を見て plan_skip を積む。
PLAN_SKIPS=""   # "<鍵>\t<理由>" を改行区切り
PLAN_RUNS=""
FULL_REASON=""  # switch_full の理由。空でなければ全量に倒れている
plan_skip() { PLAN_SKIPS+="$1"$'\t'"$2"$'\n'; }
plan_run()  { PLAN_RUNS+="$1"$'\t'"$2"$'\n'; }
__plan_lookup() { printf '%s' "$2" | awk -F'\t' -v k="$1" '$1==k{print $2; exit}'; }
plan_skip_reason() { __plan_lookup "$1" "$PLAN_SKIPS"; }
# 計画で回さないことになっているか（DB の準備を飛ばすかどうかの判定などに使う）
planned_skip() { [ -n "$(plan_skip_reason "$1")" ]; }
plan_run_reason() {
  local r; r=$(__plan_lookup "$1" "$PLAN_RUNS")
  if [ -n "$r" ]; then echo "$r"
  elif [ "$MODE" = quick ]; then echo "--quick"
  elif [ "$MODE" = changed ]; then echo "変更分（回さない理由が無い）"
  else echo "全量（既定ですべて回す）"; fi
}

# ---- --changed: 基準からの変更ファイルを集める ----
# 基準は <base>（省略時 CHECK_BASE。harness.env で決める。無ければ origin/main）と HEAD の merge-base。
# 判定できないときは安全側に倒して全量に切り替える（switch_full）。
CHANGED_FILES=()
BASE_SHA=""
# 全量に倒す。それまでに積んだ「回さない」「回す理由」はすべて捨てる（判定の途中で倒れても、それまでの plan_skip が残らないように）。
# 倒したら、変更分の判定のための plan_skip はもう積まない（判定のループは break する）。
# 全量でも回さないもの（全量のテストに含まれるゲートなど）は、倒れたあとに積んでよい
switch_full() {
  [ -n "$FULL_REASON" ] && return 0
  FULL_REASON="$1"; MODE=full; PLAN_SKIPS=""; PLAN_RUNS=""
  echo "全量に切替: $1"
}
if [ "$MODE" = changed ]; then
  __base_ref="${BASE_ARG:-${CHECK_BASE:-origin/main}}"
  if ! git rev-parse --verify -q "$__base_ref" >/dev/null; then
    switch_full "基準 $__base_ref が無い（fetch 前か、ref 名の誤り）"
  elif ! BASE_SHA=$(git merge-base "$__base_ref" HEAD 2>/dev/null); then
    switch_full "基準 $__base_ref と HEAD の merge-base が取れない"
  else
    while IFS= read -r __f; do [ -n "$__f" ] && CHANGED_FILES+=("$__f"); done < <(
      { git diff --name-only "$BASE_SHA"; git ls-files --others --exclude-standard; } | sort -u)
    if [ "${#CHANGED_FILES[@]}" -eq 0 ]; then
      echo "変更なし: 基準 ${BASE_SHA:0:8}（$__base_ref との merge-base）から作業ツリーまで差分が無い。検査は回さない"
      exit 0
    fi
  fi
  unset __f
fi

# ---- 計画を出す（--dry-run）----
# check.sh は GATES に鍵を並べておく。plan_print はそれを順に「回す / 回さない」と理由で出して終える。
GATES=()
plan_print() {
  local g why
  echo "計画（--dry-run。検査は実行しない）"
  echo "  モード: $MODE${BASE_SHA:+。基準 ${BASE_SHA:0:8}、変更 ${#CHANGED_FILES[@]} ファイル}"
  for g in ${GATES[@]+"${GATES[@]}"}; do
    why=$(plan_skip_reason "$g")
    if [ -n "$why" ]; then echo "  回さない: $g — $why"; else echo "  回す:     $g — $(plan_run_reason "$g")"; fi
  done
  exit 0
}

# ---- 実行と集計 ----
failed=()
run() { # $1=表示名（鍵（説明）） 残り=コマンド
  local name="$1"; shift
  local key="${name%%（*}"
  local why; why=$(plan_skip_reason "$key")
  echo; echo "==> $name"
  if [ -n "$why" ]; then echo "SKIP: $why"; return 0; fi
  if "$@"; then echo "OK: $name"; else echo "NG: $name"; failed+=("$name"); fi
}
skip() { echo; echo "==> $1"; echo "SKIP: $2"; }
# 雛形の埋め忘れ。回すと NG になる（埋め忘れたまま ALL GREEN にしないため）
todo() { echo "未設定: $*（scripts/check.sh のこのゲートを埋める）" >&2; return 1; }
fail_gate() { echo; echo "NG: $1"; failed+=("$1"); }

# DB を使うゲートの前に呼ぶ。harness_prepare が無ければ何もしない。失敗したら失敗として積み、1 を返す
prepare_or_fail() {
  if ! declare -F harness_prepare >/dev/null; then return 0; fi
  echo; echo "==> 準備（harness_prepare）"
  if harness_prepare; then return 0; fi
  fail_gate "準備（harness_prepare。DB の起動などを確かめる）"
  return 1
}

# ホストのポートが開いているか（DB が起きているか）。bash の /dev/tcp を使うので、DB のクライアントが無くても確かめられる
port_up() { (exec 3<>"/dev/tcp/$1/$2") 2>/dev/null; }

finish() {
  echo
  if [ "${#failed[@]}" -gt 0 ]; then
    echo "================ FAILED ================"
    printf ' - %s\n' "${failed[@]}"
    exit 1
  fi
  echo "================ ALL GREEN ================"
  exit 0
}
