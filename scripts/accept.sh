#!/usr/bin/env bash
# scripts/accept.sh — 受け入れテスト（docs/accept/<タスク名>/）を、採点のときだけ app にコピーして回す
#
# 使い方:
#   scripts/accept.sh <タスク名>          docs/accept/<タスク名>/ のテストをコピー先にコピーして回し、終わったら消す
#   scripts/accept.sh <タスク名> --keep   回したあともコピーを残す（調べるとき用。コピー先は .gitignore に入れておく）
#
# ハーネス（harness_cc）が持つファイル。PJ ごとのことはこのファイルに書かず、.claude/harness.env に書く。
#   必須: accept_run <コピーしたディレクトリ>   … そのディレクトリのテストだけを回す関数。終了コードをそのまま返す
#   任意: harness_env                           … 環境変数だけを決める軽い関数（DB の向き先など）。check.sh と共通
#   任意: harness_prepare                       … DB が起きているか、ビルドなど、テストの前の準備。失敗したら 0 以外を返す
#   任意: ACCEPT_DEST_ROOT（既定 tests/Acceptance）、ACCEPT_GLOB（既定 *）、ACCEPT_DIR_NAME（as-is / studly / snake。既定 as-is）
#
# 回すのは accept-test（書いたとき）と ac-review（採点）。build は回さない（headless-build.json の deny）。
# 普段のテストの対象には入れないので、scripts/check.sh と pre-push には影響しない。
#
# 終了コード: 0 = 全部通った / 1 = 落ちた・準備に失敗した / 2 = 使い方の誤り・設定が無い
set -uo pipefail
cd "$(dirname "$0")/.."

task=""
keep=0
for arg in "$@"; do
  case "$arg" in
    --keep) keep=1 ;;
    -*) echo "accept.sh: 不明なオプション: ${arg}（--keep）" >&2; exit 2 ;;
    *) if [ -z "$task" ]; then task="$arg"; else echo "accept.sh: タスク名は 1 つだけ: ${arg}" >&2; exit 2; fi ;;
  esac
done
if [ -z "$task" ]; then
  echo "使い方: scripts/accept.sh <タスク名> [--keep]" >&2
  exit 2
fi
# タスク名は英小文字・数字・ハイフンだけ（spec の決まり）。コピー先のパスに入れて rm -rf するので、
# ../ や / を含む名前を通すと app の外を消しうる。ここで止める
if ! [[ "$task" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "NG: タスク名は英小文字・数字・ハイフンだけ: ${task}" >&2
  exit 2
fi

# ---- 設定 ----
conf=".claude/harness.env"
if [ ! -f "$conf" ]; then
  echo "NG: ${conf} が無い（harness_cc の templates/harness.env をコピーして埋める）" >&2
  exit 2
fi
# shellcheck source=/dev/null
. "./$conf"
if ! declare -F accept_run >/dev/null; then
  echo "NG: ${conf} に accept_run が無い（コピーしたディレクトリのテストだけを回す関数）" >&2
  exit 2
fi
dest_root="${ACCEPT_DEST_ROOT:-tests/Acceptance}"
glob="${ACCEPT_GLOB:-*}"
dir_style="${ACCEPT_DIR_NAME:-as-is}"
case "$dest_root" in
  ""|/*|*..*) echo "NG: ACCEPT_DEST_ROOT は app の中の相対パスにする: ${dest_root}" >&2; exit 2 ;;
esac

# ---- 受け入れテストを集める ----
src="docs/accept/$task"
if [ ! -d "$src" ]; then
  echo "NG: ${src} が無い（受け入れテストは docs リポジトリの docs/accept/<タスク名>/ に置く）" >&2
  exit 2
fi
shopt -s nullglob
files=("$src"/$glob)
shopt -u nullglob
tests=()
for f in ${files[@]+"${files[@]}"}; do
  [ -f "$f" ] && [ "$(basename "$f")" != "accept.md" ] && tests+=("$f")
done
if [ "${#tests[@]}" -eq 0 ]; then
  echo "NG: ${src} に ${glob} のテストが無い" >&2
  exit 2
fi

# ---- コピー先のディレクトリ名 ----
case "$dir_style" in
  as-is)  name="$task" ;;
  studly) name="$(printf '%s' "$task" | awk -F'-' '{for (i = 1; i <= NF; i++) printf "%s%s", toupper(substr($i, 1, 1)), substr($i, 2)}')" ;;
  snake)  name="${task//-/_}" ;;
  *) echo "NG: ACCEPT_DIR_NAME は as-is / studly / snake のどれか: ${dir_style}" >&2; exit 2 ;;
esac
dst="$dest_root/$name"

# ---- 準備（DB など。PJ の harness.env）----
if declare -F harness_env >/dev/null; then
  harness_env
fi
if declare -F harness_prepare >/dev/null; then
  if ! harness_prepare; then
    echo "NG: 準備（harness_prepare）に失敗した" >&2
    exit 1
  fi
fi

# ---- コピーして回す。落ちても、止められても、コピーは消す ----
cleanup() { [ "$keep" = 1 ] || rm -rf "$dst"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
rm -rf "$dst"
mkdir -p "$dst"
cp "${tests[@]}" "$dst/"

echo "==> 受け入れテスト: ${task}（${#tests[@]} ファイル → ${dst}）"
accept_run "$dst"
status=$?
if [ "$status" -eq 0 ]; then
  echo "================ ACCEPT GREEN: ${task} ================"
else
  echo "================ ACCEPT FAILED: ${task} ================"
fi
[ "$keep" = 1 ] && echo "（--keep: ${dst} を残した。調べ終わったら消す）"
exit "$status"
