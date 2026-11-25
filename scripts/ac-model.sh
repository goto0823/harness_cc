#!/usr/bin/env bash
# scripts/ac-model.sh — 状態のモデル（docs/spec/<タスク名>-model.qnt と -model.md）の枠を作り、Quint で回して確かめる
#
# 使い方:
#   scripts/ac-model.sh new <タスク名>     枠を作る（あれば作り直す）
#   scripts/ac-model.sh check <タスク名>   型を確かめ、quint run で「起きてはいけないこと」「たどり着けること」「行き止まり」を見る
#   （AC の節は scripts/ac-matrix.sh ac <タスク名> で出す。モデルを書く係が読むのはそれだけ）
#
# モデルを書くのは /ac-model（spec を書いた会話とは別の会話）。spec の会話はこの 2 つのファイルを書き換えない。
# quint run はランダムに試すだけで、全部の状態は調べない。だから結果は「起きない」ではなく「<回数> 回 × <歩数> 歩 試して見つからなかった」と書く。
#
# 見るもの:
#   - 型（quint typecheck）
#   - 起きてはいけないこと: 1 つずつ --invariant で回し、破れる道すじが見つからないか
#   - たどり着けること: 1 つずつ --observation で回し、たどり着けるか（たどり着けない = モデルが空回りしているか、AC の抜け）
#   - 行き止まり: --no-invariant で回し、どの道すじも最後の歩まで進めるか（途中で進めなくなる状態 = AC の抜け）
#   - 形: 表の名前が .qnt の val にある、出典の AC が実在する、finished と idle がある、未決が空、表の後に AC が変わっていない
#
# 設定（環境変数。.claude/harness.env に書いてもよい）:
#   QUINT_CMD          quint の呼び方（既定: PATH の quint。無ければ npx --no-install quint）
#   QUINT_BACKEND      rust（既定。初回に GitHub から評価器を取ってくる）か typescript（取ってこない。遅い）
#   QUINT_MAX_SAMPLES  1 つの性質あたり何回試すか（既定 10000）
#   QUINT_MAX_STEPS    1 回に何歩進むか（既定 30）
#
# 終了コード: 0 = 通った / 1 = 破れた・たどり着けない・行き止まり・未決・形の誤り・古い / 2 = 使い方の誤り・ファイルや道具が無い
set -uo pipefail
cd "$(dirname "$0")/.."

cmd="${1:-}"
task="${2:-}"
if [ -z "$cmd" ] || [ -z "$task" ] || [ "$#" -ne 2 ]; then
  echo "使い方: scripts/ac-model.sh new|check <タスク名>" >&2
  exit 2
fi
case "$cmd" in new|check) ;; *) echo "ac-model.sh: 不明なコマンド: ${cmd}（new / check）" >&2; exit 2 ;; esac
if ! [[ "$task" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "NG: タスク名は英小文字・数字・ハイフンだけ: ${task}" >&2
  exit 2
fi

spec="docs/spec/${task}-spec.md"
md="docs/spec/${task}-model.md"
qnt="docs/spec/${task}-model.qnt"
if [ ! -f "$spec" ]; then echo "NG: ${spec} が無い" >&2; exit 2; fi
if [ ! -x scripts/ac-matrix.sh ]; then echo "NG: scripts/ac-matrix.sh が無い（install.sh で入れる）" >&2; exit 2; fi
if ! ac_text="$(scripts/ac-matrix.sh ac "$task")"; then exit 2; fi
now_sum="$(printf '%s\n' "$ac_text" | cksum | awk '{ print $1 }')"

# Quint のモジュール名は英字で始まり、英数字と _ だけ
module="$(printf '%s' "$task" | awk -F'-' '{ for (i = 1; i <= NF; i++) printf "%s%s", toupper(substr($i, 1, 1)), substr($i, 2) }')"
case "$module" in [A-Za-z]*) ;; *) module="M${module}" ;; esac

if [ "$cmd" = new ]; then
  cat > "$qnt" <<EOF
// 状態のモデル: ${task}
// 書くのは /ac-model（spec を書いた会話とは別の会話）。読んでよいのは scripts/ac-matrix.sh ac ${task} が出す AC の節だけ。
// AC に書いていない振る舞いは決めつけず、「どちらもありうる」（any や nondet）にする。
module ${module} {
  // ---- 状態（AC に出てくるもの）----
  // var status: str

  // ---- 最初の状態 ----
  action init = all {
    // status' = "予約済み",
  }

  // ---- 操作（AC の When を 1 つずつ）----
  // action cancel = all { status == "予約済み", status' = "キャンセル済み" }

  // ---- 終わり: これ以上なにも起きない状態。idle はここでだけ足踏みする ----
  val finished = true // ← AC から書き直す
  action idle = all { finished, /* 全部の var' = var */ }

  action step = any {
    // cancel,
    idle,
  }

  // ---- 起きてはいけないこと（model.md の表と同じ名前）----
  // val neverTwice = ...

  // ---- たどり着けること（model.md の表と同じ名前。finished も含む）----
  // val refundError = status == "返金エラー"
}
EOF
  cat > "$md" <<EOF
---
spec: ${spec}
model: ${qnt}
ac_sum: ${now_sum}
created: $(date +%Y-%m-%d)
---
# 状態のモデル: ${task}

書くのは /ac-model（spec を書いた会話とは別の会話）。spec の会話はこのファイルと .qnt を書き換えない。AC を直したら、作り直す。
読んでよいのは \`scripts/ac-matrix.sh ac ${task}\` が出す AC の節と、この枠だけ。

## 起きてはいけないこと
AC の Then や「変えないこと」から、どの状態でも成り立つべきこと。名前は .qnt の \`val\` と同じにする。出典に AC の番号を書く。

| 名前 | 中身 | 出典 |
|---|---|---|

## たどり着けること
AC の Then に出てくる状態に、本当にたどり着けるか。たどり着けなければ、モデルが空回りしているか AC の抜け。
\`finished\`（これ以上なにも起きない状態）はいつも入れる。出典に AC の番号を書く（finished だけは「いつも」でよい）。

| 名前 | 中身 | 出典 |
|---|---|---|
| finished | これ以上なにも起きない状態 | いつも |

## どちらもありうるにしたこと
AC に書いていないので、決めつけずに「どちらもありうる」にした振る舞い（同時に来る・順番が入れ替わる・失敗する、など）。

| 何を | どう書いたか | 出典 |
|---|---|---|

## 未決
モデルに書けなかったこと（AC から読み取れない状態や操作）。1 行ずつ「- 」で書く。無ければ「なし」と 1 行書く。
EOF
  echo "作った: ${qnt}、${md}（モジュール ${module}）"
  exit 0
fi

# ---- check ----
for f in "$md" "$qnt"; do
  if [ ! -f "$f" ]; then echo "NG: ${f} が無い（/ac-model ${task} で作る）" >&2; exit 2; fi
done
if [ -f .claude/harness.env ]; then
  # shellcheck source=/dev/null
  . ./.claude/harness.env
fi
backend="${QUINT_BACKEND:-rust}"
samples="${QUINT_MAX_SAMPLES:-10000}"
steps="${QUINT_MAX_STEPS:-30}"
if [ -n "${QUINT_CMD:-}" ]; then
  read -r -a quint <<< "$QUINT_CMD"
elif command -v quint >/dev/null 2>&1; then
  quint=(quint)
else
  quint=(npx --no-install quint)
fi
if ! "${quint[@]}" --version >/dev/null 2>&1; then
  echo "NG: quint が無い（npm install -g @informalsystems/quint か、app の devDependencies に入れる。呼び方は QUINT_CMD）" >&2
  exit 2
fi
case "$samples$steps" in *[!0-9]*) echo "NG: QUINT_MAX_SAMPLES と QUINT_MAX_STEPS は数" >&2; exit 2 ;; esac

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
grep -oE '^### AC-[A-Za-z0-9]+-[0-9]+' "$spec" | sed 's/^### //' > "$tmp/ids"

# model.md を読む: 種類<TAB>名前<TAB>中身<TAB>出典 を出し、形の誤りは「ERR<TAB>…」で出す
awk -v ids_file="$tmp/ids" '
  function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  function cites(s,   n, t, id) {
    n = 0; t = s
    while (match(t, /AC-[A-Za-z0-9]+-[0-9]+/)) {
      id = substr(t, RSTART, RLENGTH); n++
      if (!(id in ids)) print "ERR\t出典の " id " は spec に無い AC"
      t = substr(t, RSTART + RLENGTH)
    }
    return n
  }
  BEGIN { while ((getline l < ids_file) > 0) ids[l] = 1 }
  FNR == 1 && /^---[ \t]*$/ { fm = 1; next }
  fm && /^---[ \t]*$/ { fm = 0; next }
  fm { if ($0 ~ /^ac_sum:/) { s = $0; sub(/^ac_sum:[ \t]*/, "", s); print "SUM\t" trim(s) } next }
  /^## / { sec = trim(substr($0, 4)); hdr = 0; next }
  sec == "未決" {
    if ($0 ~ /^[ \t]*-[ \t]+/) { s = $0; sub(/^[ \t]*-[ \t]+/, "", s); print "Q\t" trim(s) }
    else if (trim($0) == "なし") print "NOQ"
    next
  }
  /^[ \t]*\|/ {
    if (sec != "起きてはいけないこと" && sec != "たどり着けること" && sec != "どちらもありうるにしたこと") next
    if ($0 ~ /^[ \t]*\|[ \t:|-]+$/) next
    if (!hdr) { hdr = 1; next }
    s = $0; sub(/^[ \t]*\|/, "", s); sub(/\|[ \t]*$/, "", s)
    n = split(s, c, "|"); for (i = 1; i <= n; i++) c[i] = trim(c[i])
    if (c[1] == "") next
    if (sec == "どちらもありうるにしたこと") { if (cites(c[3]) == 0) print "ERR\t「どちらもありうる」の「" c[1] "」の出典に AC の番号が無い"; print "OPEN\t" c[1] "\t" c[2] "\t" c[3]; next }
    if (c[1] !~ /^[A-Za-z_][A-Za-z0-9_]*$/) { print "ERR\t名前「" c[1] "」は Quint の名前にできない（英字で始まり、英数字と _ だけ）"; next }
    if (seen[c[1]]++) { print "ERR\t名前「" c[1] "」が 2 回ある"; next }
    kind = (sec == "起きてはいけないこと") ? "INV" : "OBS"
    if (!(kind == "OBS" && c[1] == "finished") && cites(c[3]) == 0) print "ERR\t「" c[1] "」の出典に AC の番号が無い"
    print kind "\t" c[1] "\t" c[2] "\t" c[3]
  }
' "$md" > "$tmp/md"

errs=()
while IFS="$(printf '\t')" read -r k a _; do
  [ "$k" = ERR ] && errs+=("$a")
done < "$tmp/md"
file_sum="$(awk -F'\t' '$1 == "SUM" { print $2 }' "$tmp/md")"
stale=0
if [ -z "$file_sum" ]; then errs+=("frontmatter に ac_sum が無い（scripts/ac-model.sh new ${task} で作り直す）")
elif [ "$file_sum" != "$now_sum" ]; then stale=1; fi
awk -F'\t' '$1 == "INV"' "$tmp/md" > "$tmp/inv"
awk -F'\t' '$1 == "OBS"' "$tmp/md" > "$tmp/obs"
awk -F'\t' '$1 == "Q" { print $2 }' "$tmp/md" > "$tmp/q"
[ -s "$tmp/inv" ] || errs+=("「起きてはいけないこと」が 1 つも無い")
grep -q "^OBS	finished	" "$tmp/md" || errs+=("「たどり着けること」に finished が無い")
if [ ! -s "$tmp/q" ] && ! grep -q '^NOQ' "$tmp/md"; then errs+=("「未決」が空（無ければ「なし」と書く）"); fi
if [ -s "$tmp/q" ] && grep -q '^NOQ' "$tmp/md"; then errs+=("「未決」に項目があるのに「なし」も書いてある"); fi
grep -qE '^[[:space:]]*action[[:space:]]+idle[[:space:]]*=' "$qnt" || errs+=(".qnt に action idle が無い")
while IFS="$(printf '\t')" read -r _ name _; do
  grep -qE "^[[:space:]]*(pure[[:space:]]+)?val[[:space:]]+${name}([[:space:]]|:|=)" "$qnt" || errs+=("「${name}」が .qnt の val に無い")
done < <(cat "$tmp/inv" "$tmp/obs")

seed="0x$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
run() { # $@ = quint run に足す引数。出力は $tmp/out、終了コードを返す
  "${quint[@]}" run "$qnt" --backend="$backend" --max-samples="$samples" --max-steps="$steps" --seed="$seed" "$@" > "$tmp/out" 2>&1
}

echo "==> 状態のモデル: ${task}（quint run: ${samples} 回 × ${steps} 歩、seed=${seed}、backend=${backend}）"
tc_ok=1
if ! "${quint[@]}" typecheck "$qnt" > "$tmp/tc" 2>&1; then
  tc_ok=0
  echo "[型] NG"
  sed 's/^/    /' "$tmp/tc"
  errs+=("型の誤り（quint typecheck）")
else
  echo "[型] OK"
fi

bad=0
if [ "$tc_ok" = 1 ]; then
  echo "[起きてはいけないこと]"
  while IFS="$(printf '\t')" read -r _ name what src; do
    if run --invariant="$name"; then
      echo "  ${name}: 見つからなかった（${what}。${src}）"
    elif grep -q 'Invariant violated' "$tmp/out"; then
      bad=1
      echo "  ${name}: 破れた（${what}。${src}）。道すじ:"
      awk '/^\[State [0-9]+\]/ { p = 1 } p && /^\[violation\]/ { exit } p && NF { print "      " $0 }' "$tmp/out"
    else
      bad=1; echo "  ${name}: 回せなかった"; sed 's/^/      /' "$tmp/out" | tail -8
    fi
  done < "$tmp/inv"
  echo "[たどり着けること]"
  while IFS="$(printf '\t')" read -r _ name what src; do
    if run --no-invariant --observation="$name"; then
      echo "  ${name}: たどり着いた（${what}。${src}）"
    elif grep -q 'Observation not reached' "$tmp/out"; then
      bad=1; echo "  ${name}: たどり着かなかった（${what}。${src}）"
    else
      bad=1; echo "  ${name}: 回せなかった"; sed 's/^/      /' "$tmp/out" | tail -8
    fi
  done < "$tmp/obs"
  echo "[行き止まり]"
  if run --no-invariant; then
    min="$(sed -n 's/.*Trace length statistics: .*min=\([0-9]*\).*/\1/p' "$tmp/out" | head -1)"
    if [ -z "$min" ]; then
      bad=1; echo "  道すじの長さが読めなかった"; sed 's/^/      /' "$tmp/out" | tail -5
    elif [ "$min" -le "$steps" ]; then
      bad=1; echo "  ある: 途中で進めなくなる道すじがある（いちばん短い道すじが ${min} 状態。最後まで進めば $((steps + 1)) 状態）。finished でないのに、どの操作もできない状態がある"
    else
      echo "  見つからなかった（どの道すじも ${steps} 歩 進めた）"
    fi
  else
    bad=1; echo "  回せなかった"; sed 's/^/      /' "$tmp/out" | tail -8
  fi
fi

if [ -s "$tmp/q" ]; then
  echo "==> 人に聞くこと（モデルに書けなかったこと。AC に書き足す）"
  sed 's/^/- /' "$tmp/q"
fi
if [ -s "$tmp/md" ] && grep -q '^OPEN' "$tmp/md"; then
  echo "==> どちらもありうるにしたこと（AC に書いていない）"
  awk -F'\t' '$1 == "OPEN" { print "- " $2 "（" $3 "。" $4 "）" }' "$tmp/md"
fi
if [ "${#errs[@]}" -gt 0 ]; then
  echo "==> 形の誤り（/ac-model で直す）"
  printf -- '- %s\n' "${errs[@]}"
fi
[ "$stale" = 1 ] && echo "==> 古い: モデルを作った後に spec の AC が変わった（/ac-model で作り直す）"
if [ "$bad" = 0 ] && [ ! -s "$tmp/q" ] && [ "${#errs[@]}" -eq 0 ] && [ "$stale" = 0 ]; then
  echo "================ MODEL OK: ${task}（ランダムに試して見つからなかった。全部は調べていない） ================"
  exit 0
fi
echo "================ MODEL NG: ${task} ================"
exit 1
