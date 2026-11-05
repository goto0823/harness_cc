#!/usr/bin/env bash
# install.sh — ハーネスを app に入れる・更新する
#
# 使い方（harness_cc のルートで）:
#   ./install.sh <app のルート>             入れる・更新する
#   ./install.sh <app のルート> --dry-run   何をするかだけ出す
#
# ファイルは 2 種類に分けて扱う:
#   上流が持つもの（ハーネスの更新で変わる。app では書き換えない）… いつも上書きする
#     .claude/skills/<スキル>/ の中身すべて、scripts/accept.sh、scripts/lib/check-lib.sh
#   PJ が持つもの（最初に 1 回作ったら、あとは PJ が書き換える）… 無いときだけ作る。あれば触らない
#     .claude/project.md、.claude/harness.env、.claude/headless-build.json、scripts/check.sh
#   app にもう設定があるもの … 触らず、手で足すものを出す
#     .claude/settings.json の permissions.deny、CLAUDE.md の 2 節、.gitignore
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
app=""
dry=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry=1 ;;
    -*) echo "install.sh: 不明なオプション: ${arg}（--dry-run）" >&2; exit 2 ;;
    *) app="$arg" ;;
  esac
done
if [ -z "$app" ]; then
  echo "使い方: ./install.sh <app のルート> [--dry-run]" >&2
  exit 2
fi
if [ ! -d "$app" ]; then
  echo "NG: ${app} が無い" >&2
  exit 2
fi
app="$(cd "$app" && pwd)"
if [ "$app" = "$here" ]; then
  echo "NG: harness_cc 自身には入れない。app のルートを渡す" >&2
  exit 2
fi
if ! git -C "$app" rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "NG: ${app} は git のリポジトリではない（app のルートを渡す）" >&2
  exit 2
fi

notes=()
do_copy() { # $1=元（here からの相対） $2=先（app からの相対） $3=mode（overwrite | create）
  local src="$here/$1" dst="$app/$2" mode="$3"
  if [ -e "$dst" ] && [ "$mode" = create ]; then
    echo "  そのまま:   $2（PJ のもの。あるので触らない）"
    return 0
  fi
  if [ -e "$dst" ] && cmp -s "$src" "$dst"; then
    echo "  同じ:       $2"
    return 0
  fi
  local verb="作る"; [ -e "$dst" ] && verb="上書き"
  echo "  ${verb}:     $2"
  [ "$dry" = 1 ] && return 0
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  case "$dst" in *.sh) chmod +x "$dst" ;; esac
}

echo "==> 上流が持つもの（いつも上書き）"
# スキルのフォルダの中身（SKILL.md とテンプレートなど）をすべて
while IFS= read -r f; do
  rel="${f#"$here"/}"
  do_copy "$rel" ".claude/$rel" overwrite
done < <(find "$here/skills" -type f | sort)
do_copy "scripts/accept.sh" "scripts/accept.sh" overwrite
do_copy "scripts/lib/check-lib.sh" "scripts/lib/check-lib.sh" overwrite

echo "==> PJ が持つもの（無いときだけ作る）"
do_copy "templates/project.md" ".claude/project.md" create
do_copy "templates/harness.env" ".claude/harness.env" create
do_copy "headless-build.json" ".claude/headless-build.json" create
do_copy "templates/scripts/check.sh" "scripts/check.sh" create

echo "==> app にもう設定があるもの（手で足す）"
if [ -e "$app/.claude/settings.json" ]; then
  # harness の deny の 1 行ずつ（"Bash(...)"）が、app の settings.json にあるかを文字列で見る
  missing=()
  while IFS= read -r rule; do
    grep -qF "$rule" "$app/.claude/settings.json" || missing+=("$rule")
  done < <(grep -oE '"(Bash|Read|Edit)\([^"]*\)"' "$here/settings.json")
  if [ "${#missing[@]}" -eq 0 ]; then
    echo "  そのまま:   .claude/settings.json（deny はそろっている）"
  else
    echo "  手で足す:   .claude/settings.json の permissions.deny に ${#missing[@]} 行"
    printf '                %s\n' "${missing[@]}"
    notes+=(".claude/settings.json の permissions.deny に、上の ${#missing[@]} 行を足す（既にある設定は消さない）")
  fi
else
  do_copy "settings.json" ".claude/settings.json" create
fi
if [ -e "$app/CLAUDE.md" ] && grep -q '^## 規模と進め方' "$app/CLAUDE.md"; then
  echo "  そのまま:   CLAUDE.md（「規模と進め方」がある）"
else
  echo "  手で足す:   CLAUDE.md に harness_cc/templates/CLAUDE.md の 2 節"
  notes+=("CLAUDE.md に「規模と進め方」と「3 段階」を足す")
fi
for pat in "/docs/" "/tests/Acceptance/" ".playwright-mcp/"; do
  if [ -e "$app/.gitignore" ] && grep -qxF "$pat" "$app/.gitignore"; then
    echo "  そのまま:   .gitignore に $pat"
  else
    echo "  手で足す:   .gitignore に $pat"
    case "$pat" in
      /tests/Acceptance/) notes+=(".gitignore に $pat を足す（受け入れテストのコピー先を変えたなら、そのパス）") ;;
      *) notes+=(".gitignore に $pat を足す") ;;
    esac
  fi
done

echo
if [ "$dry" = 1 ]; then echo "（--dry-run。何も書いていない）"; fi
echo "次にやること:"
echo "  - .claude/project.md と .claude/harness.env の <ここに: …> を埋める"
echo "  - scripts/check.sh の todo を、この PJ のコマンドにする（見本: harness_cc/examples/）"
echo "  - .claude/headless-build.json に、受け入れテストを直接回すコマンドの deny を足す（README §3）"
for n in ${notes[@]+"${notes[@]}"}; do echo "  - $n"; done
echo "  - docs のリポジトリを docs/ に clone する（README §5）"
