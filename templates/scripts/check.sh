#!/usr/bin/env bash
# scripts/check.sh — この PJ の検査（ハーネスのスキルが呼ぶ）
#
# 使い方:
#   scripts/check.sh                      全部。PR を出す前に回す
#   scripts/check.sh --quick              速い検査だけ（DB に触らないものなど）。build が 1 ステップごとに回す
#   scripts/check.sh --changed [<base>]   変更分だけ（任意。下の「--changed の判定」を書いたときだけ意味がある）
#   scripts/check.sh --dry-run            何を回すかの計画だけ出して、検査は 1 つも実行しない
#
# 終了コード: 全部通れば 0、1 つでも落ちれば 1（ハーネスはこれだけを見る）。
# 枠組み（オプションの解析・計画・run / skip・集計）は scripts/lib/check-lib.sh。このファイルには PJ のゲートだけを書く。
# 受け入れテストのコピー先（.claude/harness.env の ACCEPT_DEST_ROOT）は、どのゲートの対象にも入れない。
set -uo pipefail
cd "$(dirname "$0")/.."
. scripts/lib/check-lib.sh "$@"

# ---- ゲートの一覧（--dry-run の計画に出す順。run の表示名の、全角の括弧より前と同じ文字列にする）----
GATES=("lint" "型" "unit" "integration")

# ---- --changed の判定（任意）----
# CHANGED_FILES を見て、回さないゲートを plan_skip "<鍵>" "<理由>" で積む。判定できないファイルがあれば
# switch_full "<理由>" で全量に倒す（安全側）。書かなければ、--changed でも全部回る。
if [ "$MODE" = changed ]; then
  for f in "${CHANGED_FILES[@]}"; do
    case "$f" in
      # <ここに: 例 docs だけの変更なら何も回さない、FE だけなら BE のテストを飛ばす、など>
      *) switch_full "判定表に無いファイルの変更: $f"; break ;;
    esac
  done
fi

# ---- --quick で回さないゲート ----
# 計画に積んでおくと、--dry-run の表示と実際の実行が同じ 1 か所から決まる
if [ "$MODE" = quick ]; then
  plan_skip "integration" "--quick（DB を使うテストは回さない）"
fi

[ "$DRY_RUN" = 1 ] && plan_print

# ---- ゲート（速いものから。先に落ちたほうが早く分かる）----
# todo "…" を、そのゲートのコマンドに置き換える（todo のままだと NG になる）。ゲートは足しても減らしてもよい
run "lint（何を見るか）"              todo "lint のコマンド"
run "型（型検査）"                     todo "型検査のコマンド"
run "unit（DB を使わないテスト）"       todo "unit テストのコマンド"

# 計画で回さないなら、run が SKIP と理由を出す。回すなら、先に DB の準備（harness_prepare）を確かめる
if planned_skip "integration" || prepare_or_fail; then
  run "integration（DB を使うテスト）" todo "DB を使うテストのコマンド"
fi

finish
