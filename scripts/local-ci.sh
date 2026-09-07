#!/usr/bin/env bash
# CI 와 같은 검사를 로컬에서 한 번에 돌린다.
#
# ## 왜 있나
#
# 이 저장소는 private 이라 깃헙 액션이 계정의 Actions 분(minutes)을 쓴다. 분이 떨어지면
# 잡이 **시작조차 못 하고** 1~2초 만에 죽는다(단계 0개·로그 없음). 그때도 머지는 해야
# 하므로, 같은 명령을 여기서 돌려 근거를 남긴다.
#
# ## 무엇을 도나 — .github/workflows/ci.yml 과 같은 명령
#
#   backend  ./gradlew test jacocoTestReport jacocoTestCoverageVerification
#   app      flutter analyze --no-fatal-warnings --no-fatal-infos · flutter test
#   docs     bash .github/scripts/check-docs-drift.sh
#
# 다른 것 하나: 앱 테스트에 `--coverage` 를 안 붙인다. CI 는 리포트를 아티팩트로 올리려고
# 켜지만 로컬에서는 결과만 보면 되고, 켜면 눈에 띄게 느려진다.
#
# ## 쓰는 법
#
#   bash scripts/local-ci.sh            # 셋 다
#   bash scripts/local-ci.sh backend    # 하나만 (backend | app | docs)
#
# 로그는 build/local-ci/ 에 남는다. 실패하면 그 경로를 찍고 멈춘다.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/local-ci"
mkdir -p "$OUT"

WHAT="${1:-all}"
FAILED=()

run_backend() {
  echo "── backend — test + jacoco 게이트 ──────────────────────────"
  (cd "$ROOT/backend" && ./gradlew test jacocoTestReport jacocoTestCoverageVerification --console=plain) \
    > "$OUT/backend.log" 2>&1
  local code=$?
  if [ $code -ne 0 ]; then
    echo "  실패 — $OUT/backend.log"
    grep -E "FAILED|violated" "$OUT/backend.log" | head -10
    FAILED+=("backend")
  else
    echo "  초록 ($(grep -c 'tests completed' "$OUT/backend.log" >/dev/null 2>&1; echo ok))"
  fi
}

run_app() {
  echo "── app — analyze + test ───────────────────────────────────"
  (cd "$ROOT/app" && flutter analyze --no-fatal-warnings --no-fatal-infos) > "$OUT/app-analyze.log" 2>&1
  local analyze=$?
  tail -1 "$OUT/app-analyze.log"
  (cd "$ROOT/app" && flutter test) > "$OUT/app-test.log" 2>&1
  local test=$?
  tail -1 "$OUT/app-test.log"
  if [ $analyze -ne 0 ] || [ $test -ne 0 ]; then
    echo "  실패 — $OUT/app-analyze.log · $OUT/app-test.log"
    FAILED+=("app")
  fi
}

run_docs() {
  echo "── docs — 낡은 서술 검사 ──────────────────────────────────"
  (cd "$ROOT" && bash .github/scripts/check-docs-drift.sh) > "$OUT/docs.log" 2>&1
  if [ $? -ne 0 ]; then
    echo "  실패 — $OUT/docs.log"
    tail -10 "$OUT/docs.log"
    FAILED+=("docs")
  else
    echo "  초록"
  fi
}

case "$WHAT" in
  backend) run_backend ;;
  app) run_app ;;
  docs) run_docs ;;
  all) run_docs; run_backend; run_app ;;
  *) echo "쓰는 법: bash scripts/local-ci.sh [all|backend|app|docs]"; exit 2 ;;
esac

echo
if [ ${#FAILED[@]} -eq 0 ]; then
  echo "전부 초록 — 로그: $OUT"
  exit 0
fi
echo "빨간불: ${FAILED[*]} — 로그: $OUT"
exit 1
