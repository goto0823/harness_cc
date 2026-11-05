#!/usr/bin/env bash
# scripts/check.sh の見本（Laravel + Inertia + Vue。PHPUnit / phpstan / pint、vue-tsc / oxlint / vitest）
#
# 実際の PJ で使っていたものから、PJ だけの事情を抜いた形。そのまま使わず、自分の PJ に合わせて直す。
#
# 使い方:
#   scripts/check.sh                      全部（DB 必要）。PR を出す前に回す
#   scripts/check.sh --quick              DB 不要の速い検査だけ（生成 / vue-tsc / oxlint / vitest / pint / phpstan）
#   scripts/check.sh --changed [<base>]   変更分だけ（pre-push の既定に向く）。基準は省略時 CHECK_BASE との merge-base
#   scripts/check.sh --changed --dry-run  何を回すかの計画だけ出す
#
# 順序は FE → BE（速いものから落とす）。CI のランナーが無いリポジトリなら、pre-push からこれを呼ぶ。
set -uo pipefail
cd "$(dirname "$0")/.."
. scripts/lib/check-lib.sh "$@"

# vitest のワーカー数（vitest.config.ts が VITEST_MAX_WORKERS を読む想定）。表示用に同じ規則で解く
if [[ "${VITEST_MAX_WORKERS:-}" =~ ^[1-9][0-9]*$ ]]; then VITEST_WORKERS="$VITEST_MAX_WORKERS"; else VITEST_WORKERS=4; fi
PHPUNIT_PROCESSES="${PHPUNIT_PROCESSES:-4}"

GATES=("frontend:generate" "vue-tsc" "oxlint" "vitest" "vitest unit" "composer dump-autoload" "pint --test" "phpstan" "phpunit Unit" "phpunit Integration" "phpunit Feature" "phpunit 指定ファイル" "phpunit FE 参照")
VITEST_CMD=(npm run --silent test:run)
PINT_ARGS=(--test)
FE_READING_TESTS=()   # resources/js を読む Integration / Feature のテスト（--changed で FE だけが変わったとき回す）
TEST_FILES=()         # 変更された Integration / Feature のテスト（--changed で app が変わっていないとき、これだけ回す）

# 全量に切り替える「共有物・基盤ファイル」。検査の仕組みそのもの・依存・テストの共有物。
# これらが変わると変更分の判定が信用できないので、1 つでも当たれば全量
is_full_trigger() {
  case "$1" in
    scripts/check.sh|scripts/lib/*|.githooks/*|.claude/harness.env|vitest.config.ts|package.json|package-lock.json|composer.json|composer.lock|phpunit.xml|phpstan.neon|pint.json|.oxlintrc.json|tsconfig*.json|tests/TestCase.php|tests/Support/*|tests/Fixtures/*) return 0 ;;
  esac
  return 1
}

# ---- --changed の判定 ----
# 先に「全量に倒すファイル」「判定表に無いファイル」を全部探し、倒れなかったときだけ回さない計画を積む
if [ "$MODE" = changed ]; then
  FE_CHANGED=0; BE_CHANGED=0; TESTS_CHANGED=0
  PHP_FILES=()   # pint に渡す、変更された PHP ファイル（削除されたものは除く）
  for f in "${CHANGED_FILES[@]}"; do
    if is_full_trigger "$f"; then switch_full "共有物・基盤ファイルの変更: $f"; break; fi
    case "$f" in
      resources/js/*) FE_CHANGED=1 ;;
      app/*|database/*|routes/*|config/*)
        BE_CHANGED=1
        if [[ "$f" == *.php && -f "$f" ]]; then PHP_FILES+=("$f"); fi ;;
      tests/Integration/*|tests/Feature/*)
        TESTS_CHANGED=1
        if [[ "$f" == *.php && -f "$f" ]]; then PHP_FILES+=("$f"); TEST_FILES+=("$f"); fi ;;
      tests/Unit/*|tests/Architecture/*)
        TESTS_CHANGED=1   # Unit スイートは PHP が変わればいつも回るので、ファイル指定は要らない
        if [[ "$f" == *.php && -f "$f" ]]; then PHP_FILES+=("$f"); fi ;;
      *) switch_full "判定表に無いファイルの変更: $f"; break ;;   # lang/ views/ bootstrap/ など。安全側で全量
    esac
  done
fi
if [ "$MODE" = changed ]; then
  # ---- FE ----
  if [ "$FE_CHANGED" = 1 ]; then
    VITEST_CMD=(node_modules/.bin/vitest run --changed "$BASE_SHA" --passWithNoTests)
    plan_run "vitest" "FE の変更。--changed ${BASE_SHA:0:8} で、変更ファイルを import するテストだけ"
  else
    if [ "$BE_CHANGED" = 1 ]; then
      plan_run  "frontend:generate" "app の変更（ルートや DTO の変化が生成物に出る）"
      plan_run  "vue-tsc" "app の変更（生成した型の変化を FE の型検査で拾う）"
    else
      plan_skip "frontend:generate" "FE も app も変更なし（テストだけ）"
      plan_skip "vue-tsc" "FE も app も変更なし（テストだけ）"
    fi
    plan_skip "oxlint" "FE の変更なし"
    plan_skip "vitest" "FE の変更なし（app/ を読む FE テストは「vitest unit」で回す）"
  fi
  if [ "$BE_CHANGED" = 1 ]; then
    plan_run  "vitest unit" "app の変更（app/ の PHP を読む FE の unit テストは、import のつながりで追えない）"
  else
    plan_skip "vitest unit" "app の変更なし"
  fi
  # ---- PHP の静的検査 ----
  if [ "$BE_CHANGED" = 1 ] || [ "$TESTS_CHANGED" = 1 ]; then
    if [ "${#PHP_FILES[@]}" -gt 0 ]; then
      PINT_ARGS=(--test "${PHP_FILES[@]}")
      plan_run  "pint --test" "変更した PHP ${#PHP_FILES[@]} ファイルだけ"
    else
      plan_skip "pint --test" "変更した PHP ファイルが無い（削除だけ、または PHP 以外）"
    fi
  else
    plan_skip "composer dump-autoload" "PHP の変更なし"
    plan_skip "pint --test" "PHP の変更なし"
    plan_skip "phpstan" "PHP の変更なし"
  fi
  # ---- PHPUnit ----
  if [ "$BE_CHANGED" = 1 ]; then
    plan_skip "phpunit 指定ファイル" "Integration / Feature の全量に含まれる"
    plan_skip "phpunit FE 参照" "Integration / Feature の全量に含まれる"
  else
    plan_skip "phpunit Integration" "app の変更なし（変更したテストと resources/js を読むテストだけ別に回す）"
    plan_skip "phpunit Feature" "app の変更なし（同上）"
    if [ "${#TEST_FILES[@]}" -eq 0 ]; then
      plan_skip "phpunit 指定ファイル" "変更した Integration / Feature のテストが無い"
    fi
    if [ "$FE_CHANGED" = 1 ]; then
      while IFS= read -r t; do [ -n "$t" ] && FE_READING_TESTS+=("$t"); done < <(
        grep -rl 'resources/js' tests/Integration tests/Feature --include='*Test.php' 2>/dev/null | sort)
      [ "${#FE_READING_TESTS[@]}" -eq 0 ] && plan_skip "phpunit FE 参照" "resources/js を読む Integration / Feature が無い"
    else
      plan_skip "phpunit FE 参照" "FE の変更なし"
    fi
  fi
else
  # 全量 / --quick では「vitest unit」「phpunit 指定ファイル」「phpunit FE 参照」は全量のテストに含まれるので回さない
  plan_skip "vitest unit" "vitest の全量に含まれる"
  plan_skip "phpunit 指定ファイル" "Integration / Feature の全量に含まれる"
  plan_skip "phpunit FE 参照" "Integration / Feature の全量に含まれる"
fi
if [ "$MODE" = quick ]; then
  for g in "phpunit Unit" "phpunit Integration" "phpunit Feature"; do plan_skip "$g" "--quick（DB 不要分だけ）"; done
fi

[ "$DRY_RUN" = 1 ] && plan_print

# ---- Frontend（速い順）----
# 生成物（ルートの関数や TypeScript の型）は gitignore。vue-tsc / oxlint より前に必ず作る。コマンドは PJ のもの
run "frontend:generate（ルートと型の生成）" php artisan frontend:generate
if [ -x node_modules/.bin/vue-tsc ]; then
  run "vue-tsc" node_modules/.bin/vue-tsc --noEmit
else
  skip "vue-tsc" "node_modules/.bin/vue-tsc が無い（npm ci を）"
fi
run "oxlint（lint:ci）" npm run --silent lint:ci
run "vitest（${VITEST_WORKERS} ワーカー）" "${VITEST_CMD[@]}"
run "vitest unit（app/ を読む FE の unit テスト。app が変わったとき）" node_modules/.bin/vitest run --project unit

# ---- Backend ----
# rebase や merge でクラスの削除・移動を取り込むと、最適化した vendor/composer/autoload_classmap.php が古いまま残り、
# 「消したクラスが class_exists() で true」「include の失敗」が起きる。毎回作り直す
run "composer dump-autoload（クラスを動かしたあとの classmap を作り直す）" composer dump-autoload -q
if [ -f pint.json ]; then
  run "pint --test" vendor/bin/pint "${PINT_ARGS[@]}"
else
  skip "pint --test" "pint.json が無い"
fi
run "phpstan" vendor/bin/phpstan analyse --memory-limit=512M --no-progress

if planned_skip "phpunit Unit" || prepare_or_fail; then
  run "phpunit Unit（DB なし。アーキテクチャのテストを含む）" php artisan test --testsuite=Unit --compact
  # Integration / Feature は DB 待ちが大半なので、paratest で並列にする（Unit は数秒なので直列のまま）。
  # --parallel / --processes は --testsuite より前に置く。artisan test は自分の知らないオプション（PHPUnit に素通しする
  # --testsuite= など）に出会うと、そこで自分のオプションの解析を止めるので、後ろに置いた --parallel は PHPUnit に渡って
  # "Unknown option" になる
  run "phpunit Integration（DB あり。${PHPUNIT_PROCESSES} 並列）" php artisan test --parallel --processes="$PHPUNIT_PROCESSES" --compact --testsuite=Integration
  run "phpunit Feature（HTTP。${PHPUNIT_PROCESSES} 並列）" php artisan test --parallel --processes="$PHPUNIT_PROCESSES" --compact --testsuite=Feature
  run "phpunit 指定ファイル（変更したテストだけ。直列）" php artisan test --compact ${TEST_FILES[@]+"${TEST_FILES[@]}"}
  run "phpunit FE 参照（resources/js を読むテスト。FE だけ変わったとき）" php artisan test --compact ${FE_READING_TESTS[@]+"${FE_READING_TESTS[@]}"}
fi

finish
