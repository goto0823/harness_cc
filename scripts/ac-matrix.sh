#!/usr/bin/env bash
# scripts/ac-matrix.sh — 認可の表（docs/spec/<タスク名>-authz.md）の枠を作り、埋めたものを確かめる
#
# 使い方:
#   scripts/ac-matrix.sh ac <タスク名>      spec の「## 受け入れ条件」の節だけを出す（表を埋める係が読むのはこれだけ）
#   scripts/ac-matrix.sh new <タスク名>     表の枠を作る（あれば作り直す）。行は .claude/project.md の「### 認可の表の行」から
#   scripts/ac-matrix.sh check <タスク名>   埋めた表を確かめ、操作ごとに並べて出す
#
# 表を埋めるのは /ac-matrix（spec を書いた会話とは別の会話）。spec の会話は表を書き換えない。
# このスクリプトは表の中身の正しさ（AC の読み方）は見ない。見るのは形だけ:
#   - project.md の行が 1 つも欠けていない（「よそ」を消して埋まったように見せられない）
#   - 操作 × 行 のすべての組み合わせに答えが 1 つずつある（抜け・重複が無い）
#   - 答えが できる／できない／未決／矛盾 のどれかで、できる・できないには実在する AC の番号がある
#   - 表を作った後に spec の AC が変わっていない（ac_sum）
#
# 終了コード: 0 = 通った / 1 = 未決・矛盾・抜け・形の誤り・古い / 2 = 使い方の誤り・設定やファイルが無い
set -uo pipefail
cd "$(dirname "$0")/.."

cmd="${1:-}"
task="${2:-}"
if [ -z "$cmd" ] || [ -z "$task" ] || [ "$#" -ne 2 ]; then
  echo "使い方: scripts/ac-matrix.sh ac|new|check <タスク名>" >&2
  exit 2
fi
case "$cmd" in ac|new|check) ;; *) echo "ac-matrix.sh: 不明なコマンド: ${cmd}（ac / new / check）" >&2; exit 2 ;; esac
if ! [[ "$task" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "NG: タスク名は英小文字・数字・ハイフンだけ: ${task}" >&2
  exit 2
fi

spec="docs/spec/${task}-spec.md"
authz="docs/spec/${task}-authz.md"
project=".claude/project.md"

if [ ! -f "$spec" ]; then
  echo "NG: ${spec} が無い" >&2
  exit 2
fi

# spec の「## 受け入れ条件」の節（見出しから次の ## の前まで）
ac_section() {
  awk '
    /^## 受け入れ条件[ \t]*$/ { f = 1; print; next }
    f && /^## / { f = 0 }
    f { print }
  ' "$spec"
}
ac_sum() { ac_section | cksum | awk '{ print $1 }'; }

if [ "$cmd" = ac ]; then
  out="$(ac_section)"
  if [ -z "$out" ]; then
    echo "NG: ${spec} に「## 受け入れ条件」の節が無い" >&2
    exit 2
  fi
  printf '%s\n' "$out"
  exit 0
fi

# project.md の「### 認可の表の行」の表の 1 列目（行の名前）と、説明（2 列目が ○ なら「よそ。」を頭に付け、3 列目を続ける）を、タブ区切りで出す
project_rows() {
  awk '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    /^### 認可の表の行[ \t]*$/ { f = 1; next }
    f && /^#/ { f = 0 }
    f && /^[ \t]*\|/ {
      if ($0 ~ /^[ \t]*\|[ \t:|-]+$/) next      # 区切りの行
      if (!hdr) { hdr = 1; next }               # 見出しの行
      s = $0; sub(/^[ \t]*\|/, "", s); sub(/\|[ \t]*$/, "", s)
      n = split(s, c, "|")
      name = trim(c[1]); far = (n >= 2) ? trim(c[2]) : ""; desc = (n >= 3) ? trim(c[3]) : ""
      if (far != "" && far != "○") { print "BAD\t" name; next }
      if (far == "○") desc = (desc == "") ? "よそ" : "よそ。" desc
      if (name != "") print name "\t" desc
    }
  ' "$project"
}

if [ ! -f "$project" ]; then
  echo "NG: ${project} が無い" >&2
  exit 2
fi
rows="$(project_rows)"
if [ -z "$rows" ]; then
  echo "NG: ${project} の「## ロール」に「### 認可の表の行」の表が無い（harness_cc の templates/project.md を見て足す）" >&2
  exit 2
fi
bad="$(printf '%s\n' "$rows" | awk -F'\t' '$1 == "BAD" { print $2 }')"
if [ -n "$bad" ]; then
  echo "NG: ${project} の「### 認可の表の行」の「よそ」の列は ○ か空にする: $(printf '%s' "$bad" | tr '\n' ' ')" >&2
  exit 2
fi
if printf '%s\n' "$rows" | grep -q '<ここに'; then
  echo "NG: ${project} の「### 認可の表の行」が <ここに: …> のまま" >&2
  exit 2
fi

if [ "$cmd" = new ]; then
  if [ -z "$(ac_section)" ]; then
    echo "NG: ${spec} に「## 受け入れ条件」の節が無い" >&2
    exit 2
  fi
  {
    echo "---"
    echo "spec: ${spec}"
    echo "ac_sum: $(ac_sum)"
    echo "created: $(date +%Y-%m-%d)"
    echo "---"
    echo "# 認可の表: ${task}"
    echo
    echo "埋めるのは /ac-matrix（spec を書いた会話とは別の会話）。spec の会話はこのファイルを書き換えない。AC を直したら、作り直す。"
    echo "読んでよいのは \`scripts/ac-matrix.sh ac ${task}\` が出す AC の節と、この枠だけ。"
    echo
    echo "## 行"
    echo "project.md の行は消さない。AC にしか出てこない相手（例: 予約した本人）は足してよい。出典に AC の番号を書く。"
    echo
    echo "| 行 | 説明 | 出典 |"
    echo "|---|---|---|"
    printf '%s\n' "$rows" | while IFS="$(printf '\t')" read -r name desc; do
      echo "| ${name} | ${desc} | project.md |"
    done
    echo
    echo "## 操作"
    echo "AC の When から、人によってできる・できないが分かれうる操作を 1 行ずつ。出典に AC の番号を書く。"
    echo "そういう操作が 1 つも無いなら、表の行を書かずに、表の下に「操作なし: <理由>」と 1 行書く。"
    echo
    echo "| 操作 | 出典 |"
    echo "|---|---|"
    echo
    echo "## 答え"
    echo "操作 × 行 のすべての組み合わせを 1 行ずつ。答えは次の 4 つだけ:"
    echo "- できる／できない: AC にそう書いてある。出典に AC の番号を書く"
    echo "- 未決: AC から読み取れない。推測で埋めない。メモに、AC のどこまでは書いてあって何が無いかを書く"
    echo "- 矛盾: AC どうしで食い違う。出典に食い違う AC を 2 つ以上書き、メモに何が食い違うかを書く"
    echo
    echo "| 操作 | 行 | 答え | 出典 | メモ |"
    echo "|---|---|---|---|---|"
  } > "$authz"
  echo "作った: ${authz}（行 $(printf '%s\n' "$rows" | wc -l | tr -d ' ')）"
  exit 0
fi

# ---- check ----
if [ ! -f "$authz" ]; then
  echo "NG: ${authz} が無い（/ac-matrix ${task} で作る）" >&2
  exit 2
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf '%s\n' "$rows" | cut -f1 > "$tmp/rows"
grep -oE '^### AC-[A-Za-z0-9]+-[0-9]+' "$spec" | sed 's/^### //' > "$tmp/ids"
now_sum="$(ac_sum)"

awk -v now_sum="$now_sum" -v task="$task" '
  function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  function err(m) { errs[++ne] = m }
  # s の中の AC 番号を、ids に無いものも含めて数える。無い番号は err に足す。見つかった数を返す
  function cite(s, where,   n, t, id) {
    n = 0; t = s
    while (match(t, /AC-[A-Za-z0-9]+-[0-9]+/)) {
      id = substr(t, RSTART, RLENGTH); n++
      if (!(id in ids)) err(where ": " id " は spec に無い AC")
      t = substr(t, RSTART + RLENGTH)
    }
    return n
  }
  FILENAME == ARGV[1] { if ($0 != "") { prow[$0] = 1; porder[++np] = $0 } next }
  FILENAME == ARGV[2] { if ($0 != "") ids[$0] = 1; next }
  # ---- authz.md ----
  FNR == 1 && /^---[ \t]*$/ { fm = 1; next }
  fm && /^---[ \t]*$/ { fm = 0; next }
  fm { if ($0 ~ /^ac_sum:/) { s = $0; sub(/^ac_sum:[ \t]*/, "", s); file_sum = trim(s) } next }
  /^## / { sec = trim(substr($0, 4)); hdr = 0; next }
  /^#/ { sec = ""; next }
  sec == "操作" && /^操作なし[:：]/ { noop = 1; next }
  /^[ \t]*\|/ {
    if (sec != "行" && sec != "操作" && sec != "答え") next
    if ($0 ~ /^[ \t]*\|[ \t:|-]+$/) next
    if (!hdr) { hdr = 1; next }
    s = $0; sub(/^[ \t]*\|/, "", s); sub(/\|[ \t]*$/, "", s)
    n = split(s, c, "|")
    for (i = 1; i <= n; i++) c[i] = trim(c[i])
    if (sec == "行") {
      name = c[1]; src = (n >= 3) ? c[3] : ""
      if (name == "") next
      if (name in row) { err("行「" name "」が 2 回ある"); next }
      row[name] = 1; rorder[++nr] = name
      if (src != "project.md") {
        if (name in prow) {} else if (cite(src, "行「" name "」の出典") == 0) err("行「" name "」（project.md に無い行）の出典に AC の番号が無い")
      }
    } else if (sec == "操作") {
      name = c[1]; src = (n >= 2) ? c[2] : ""
      if (name == "") next
      if (name in op) { err("操作「" name "」が 2 回ある"); next }
      op[name] = 1; oorder[++no] = name; osrc[name] = src
      if (cite(src, "操作「" name "」の出典") == 0) err("操作「" name "」の出典に AC の番号が無い")
    } else {
      o = c[1]; r = c[2]; a = (n >= 3) ? c[3] : ""; src = (n >= 4) ? c[4] : ""; memo = (n >= 5) ? c[5] : ""
      if (o == "" && r == "") next
      k = o SUBSEP r
      if (k in ans) { err("答え「" o " × " r "」が 2 回ある"); next }
      ans[k] = a; asrc[k] = src; amemo[k] = memo; aorder[++na] = k
      where = "答え「" o " × " r "」"
      if (a == "できる" || a == "できない") {
        if (cite(src, where "の出典") == 0) err(where "は「" a "」なのに出典に AC の番号が無い")
      } else if (a == "矛盾") {
        if (cite(src, where "の出典") < 2) err(where "は「矛盾」なのに出典の AC が 2 つ未満")
      } else if (a == "未決") {
        cite(src, where "の出典")
      } else {
        err(where "の答え「" a "」は できる／できない／未決／矛盾 のどれでもない")
      }
    }
  }
  END {
    if (file_sum == "") err("frontmatter に ac_sum が無い（scripts/ac-matrix.sh new " task " で作り直す）")
    else if (file_sum != now_sum) stale = 1
    for (i = 1; i <= np; i++) if (!(porder[i] in row)) err("project.md の行「" porder[i] "」が表から消えている")
    if (no == 0 && !noop) err("操作が 1 つも無く、「操作なし: <理由>」も無い")
    if (no > 0 && noop) err("操作があるのに「操作なし」も書いてある")
    for (i = 1; i <= na; i++) {
      split(aorder[i], kk, SUBSEP)
      if (!(kk[1] in op)) err("答え「" kk[1] " × " kk[2] "」の操作が「## 操作」に無い")
      if (!(kk[2] in row)) err("答え「" kk[1] " × " kk[2] "」の行が「## 行」に無い")
    }
    nq = 0
    printf "==> 認可の表: %s（行 %d × 操作 %d）\n", task, nr, no
    if (noop) print "  操作なし"
    for (i = 1; i <= no; i++) {
      o = oorder[i]
      printf "[%s]（%s）\n", o, osrc[o]
      for (j = 1; j <= nr; j++) {
        r = rorder[j]; k = o SUBSEP r
        if (!(k in ans)) { printf "  %-14s %s\n", r, "（抜け）"; err("答え「" o " × " r "」が無い（抜け）"); continue }
        printf "  %-14s %-6s %s\n", r, ans[k], asrc[k]
        if (ans[k] == "未決" || ans[k] == "矛盾") q[++nq] = "- " r " × " o ": " ans[k] (asrc[k] != "" ? "（" asrc[k] "）" : "") (amemo[k] != "" ? " — " amemo[k] : "")
      }
    }
    if (nq > 0) {
      print "==> 人に聞くこと（AC に書き足す）"
      for (i = 1; i <= nq; i++) print q[i]
    }
    if (ne > 0) {
      print "==> 表の形の誤り（/ac-matrix で作り直す）"
      for (i = 1; i <= ne; i++) print "- " errs[i]
    }
    if (stale) print "==> 古い: 表を作った後に spec の AC が変わった（/ac-matrix で作り直す）"
    if (nq == 0 && ne == 0 && !stale) { print "================ AUTHZ OK: " task " ================"; exit 0 }
    print "================ AUTHZ NG: " task " ================"
    exit 1
  }
' "$tmp/rows" "$tmp/ids" "$authz"
