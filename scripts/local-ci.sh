#!/usr/bin/env bash
# CI 와 같은 검사를 로컬에서 한 번에 돌린다.
#
# ## 왜 있나
#
# 이 저장소는 private 이라 깃헙 액션이 계정의 Actions 분(minutes)을 쓴다. 분이 떨어지면
# 잡이 **시작조차 못 하고** 1~2초 만에 죽는다(단계 0개·로그 없음). 그때도 머지는 해야
# 하므로, 같은 명령을 여기서 돌려 근거를 남긴다.
#
# ## 이 스크립트가 지켜야 하는 것 — "안 돈 것" 과 "통과한 것" 을 구분한다 (#643)
#
# 근거를 만드는 것이 유일한 존재 이유다. 그러니 **초록이라고 말하기 전에 무엇을 몇 개
# 확인했는지 댈 수 있어야 한다.** 숫자를 못 대면 빨간불이다.
#
# 2026-09-17 에 그러지 못했다. 결과 디렉터리를 지우고 돌렸는데도 이렇게 나왔다.
#
#     초록 (ok)
#     전부 초록
#
# 로그를 열어 보니 `> Task :test FROM-CACHE` · `BUILD SUCCESSFUL in 1s` 였다. 1,874개가
# 1초에 돌 리 없다 — gradle 이 결과 XML 을 캐시에서 풀어 놓았을 뿐이고, 테스트는 한 개도
# 안 돌았다. 그런데 출력은 진짜로 다 통과한 실행과 **글자 하나까지 같았다.** (#640 근거를
# 모으다 걸렸다.)
#
# 그래서 지금은 세 가지를 한다.
#
#   1. 백엔드 테스트를 **매번 새로 돌린다** — cleanTest + --no-build-cache
#   2. gradle 태스크 줄을 읽어 `:test` 가 **진짜 실행됐는지** 확인한다
#   3. 결과 XML 을 **파서로** 읽어 실제 개수를 찍는다. 0개면 빨간불이다
#
# ## 무엇을 도나 — .github/workflows/ci.yml 과 같은 명령
#
#   backend  ./gradlew test jacocoTestReport jacocoTestCoverageVerification
#   app      flutter analyze --no-fatal-warnings --no-fatal-infos · flutter test
#   docs     bash .github/scripts/check-docs-drift.sh
#
# CI 와 일부러 다르게 하는 것 둘:
#
#   - 앱 테스트에 `--coverage` 를 안 붙인다. CI 는 리포트를 아티팩트로 올리려고 켜지만
#     로컬에서는 결과만 보면 되고, 켜면 눈에 띄게 느려진다.
#   - 백엔드에 `cleanTest` 와 `--no-build-cache` 를 붙인다. CI 는 매번 빈 체크아웃에서
#     시작해서 캐시도 이전 결과도 없다 — 거기서는 "새로 돈다" 가 공짜다. 로컬은 아니다.
#     `backend/gradle.properties` 가 `org.gradle.caching=true` 라, 안 붙이면 위의 그
#     FROM-CACHE 가 그대로 돌아온다. **cleanTest 만으로는 안 된다** — 캐시가 지운 결과를
#     다시 풀어 놓는다(`backend/build.gradle` 주석이 같은 말을 적어 뒀고, 2026-09-17 에
#     다시 재현했다). 둘을 같이 붙여야 실행된다.
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

# ── 이번 실행이 진짜 근거인지 재는 도구들 ────────────────────────────
#
# gradle 은 `--console=plain` 에서 태스크마다 한 줄을 찍는다. 접미사가 결과다.
#
#   "> Task :test"             진짜로 돌았다          → EXECUTED
#   "> Task :test FROM-CACHE"  캐시에서 풀어 놓았다   → 근거가 아니다
#   "> Task :test UP-TO-DATE"  건너뛰었다             → 근거가 아니다
#   줄이 아예 없다             태스크가 안 걸렸다     → MISSING
#
# UP-TO-DATE 를 근거로 안 치는 것이 과하게 보일 수 있다. 입력이 같으면 옛 결과가 맞긴
# 하다. 그런데 **이 저장소는 gradle 의 입력 판정에 두 번 당했다** — build.gradle 의
# inputs.files(...) 선언 더미가 #46 에서 생긴 이유이고, 아래 vfs.watch=false 가 #419 에서
# "옛 결과가 다시 나왔다" 를 겪은 결과다. 그 전력이 있는 판정을 근거로 삼지 않는다.
task_outcome() {
  awk -v task="$2" '
    $1 == ">" && $2 == "Task" && $3 == task { outcome = (NF >= 4) ? $4 : "EXECUTED" }
    END { print (outcome == "") ? "MISSING" : outcome }
  ' "$1"
}

# 테스트 결과 XML 을 **파서로** 읽는다. 정규식으로 읽지 않는 이유: 통과한 테스트는
# self-closing(`<testcase .../>`) 이라 줄 단위로 훑으면 그 경계를 넘어가 실패를 엉뚱한
# 테스트 이름에 붙인다. 개수만 세더라도 같은 도구를 쓴다.
#
# "OK <클래스> <테스트> <실패> <에러> <건너뜀>" 또는 "ERR <이유>" 를 찍는다.
backend_test_totals() {
  python3 - "$1" <<'PY'
import glob
import sys
import xml.etree.ElementTree as ET

directory = sys.argv[1]
paths = sorted(glob.glob(directory + "/TEST-*.xml"))
if not paths:
    print("ERR 결과 XML 이 한 개도 없다: " + directory)
    raise SystemExit(0)

classes = tests = failures = errors = skipped = 0
for path in paths:
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as exc:
        print("ERR 결과 XML 을 읽지 못했다 (%s): %s" % (path, exc))
        raise SystemExit(0)
    classes += 1
    tests += int(root.get("tests", 0))
    failures += int(root.get("failures", 0))
    errors += int(root.get("errors", 0))
    skipped += int(root.get("skipped", 0))

if tests == 0:
    print("ERR 결과 XML 은 있는데 테스트가 0개다 (클래스 %d개)" % classes)
    raise SystemExit(0)

print("OK %d %d %d %d %d" % (classes, tests, failures, errors, skipped))
PY
}

# flutter 의 마지막 요약 줄은 "00:05 +123: All tests passed!" 꼴이다. +N 이 통과 개수다.
# 로그 전체에서 마지막 +N 을 집는다.
flutter_test_count() {
  tr '\r' '\n' < "$1" | grep -oE '\+[0-9]+' | tail -1 | tr -d '+'
}

run_backend() {
  echo "── backend — test + jacoco 게이트 ──────────────────────────"

  if ! command -v python3 >/dev/null 2>&1; then
    echo "  근거 없음 — python3 가 없어 테스트 개수를 셀 수 없다."
    echo "  개수를 못 대면 초록이라고 말하지 않는다 (#643)."
    FAILED+=("backend")
    return
  fi

  # -Dorg.gradle.vfs.watch=false 를 붙이는 이유 — #419 실측.
  #
  # 문서를 gradle 밖의 도구로 고친 뒤 이 검사를 돌렸더니 **옛 결과가 다시 나왔다**. 같은
  # 트리에서 데몬만 새로 띄우니 초록이었다(문서 검사 2 실패 → 0). 파일 감시가 외부
  # 프로세스의 쓰기를 놓치면 test 태스크가 UP-TO-DATE 로 보이고, 그러면 출력이 캐시에서
  # 복원된다 — build.gradle 의 입력 선언 주석이 같은 함정을 적어 뒀다("cleanTest 도 안
  # 통했다(캐시에서 복원)").
  #
  # 감시를 끄면 매번 파일을 다시 훑는다. 조금 느려지는 대신 이 스크립트가 **지금 트리**를
  # 재는 것이 보장된다. 초록도 빨강도 믿을 수 없으면 그건 검사가 아니다.
  #
  # cleanTest 와 --no-build-cache 는 그 다음 층이다. 헤더의 "CI 와 일부러 다르게" 참조.
  (cd "$ROOT/backend" \
    && ./gradlew cleanTest test jacocoTestReport jacocoTestCoverageVerification \
         -Dorg.gradle.vfs.watch=false --no-build-cache --console=plain) \
    > "$OUT/backend.log" 2>&1
  local code=$?

  if [ $code -ne 0 ]; then
    echo "  실패 — $OUT/backend.log"
    grep -E "FAILED|violated" "$OUT/backend.log" | head -10
    FAILED+=("backend")
    return
  fi

  # 초록이라고 말하기 전에 두 가지를 본다. 종료 코드 0 은 "테스트가 통과했다" 가 아니라
  # "gradle 이 화내지 않았다" 까지만 말한다.
  local outcome
  outcome=$(task_outcome "$OUT/backend.log" ':test')
  if [ "$outcome" != "EXECUTED" ]; then
    echo "  근거 없음 — :test 가 $outcome 이다. 이번 실행은 테스트를 안 돌렸다."
    echo "  옛 결과나 캐시로 초록을 만들지 않는다 (#643). — $OUT/backend.log"
    FAILED+=("backend")
    return
  fi

  local summary
  summary=$(backend_test_totals "$ROOT/backend/build/test-results/test")
  case "$summary" in
    "ERR "*)
      echo "  근거 없음 — ${summary#ERR }"
      FAILED+=("backend")
      return
      ;;
  esac

  local classes tests failures errors skipped
  read -r _ classes tests failures errors skipped <<< "$summary"
  echo "  초록 — 클래스 ${classes}개 · 테스트 ${tests}개 (실패 ${failures} · 에러 ${errors} · 건너뜀 ${skipped}) · jacoco 게이트 통과"
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
    return
  fi

  # 이 레인에는 백엔드 같은 구멍이 없다 — 실측으로 확인했다(#643). flutter test 는 빌드
  # 캐시가 없고, 돌 것이 없으면 스스로 죽는다: `test/` 에 `_test.dart` 가 없으면 1,
  # 파일은 있는데 테스트가 0개면 79 로 끝난다. 그래서 위의 종료 코드 검사가 이미 막는다.
  #
  # 그래도 개수는 찍는다. "무엇을 몇 개 확인했는지 댈 수 있어야 한다" 는 같은 규칙이다.
  local count
  count=$(flutter_test_count "$OUT/app-test.log")
  if [ -z "$count" ]; then
    echo "  근거 없음 — flutter 가 0 으로 끝났는데 요약 줄에서 개수를 못 찾았다."
    echo "  출력 형식이 바뀌었을 수 있다. 눈으로 볼 것 — $OUT/app-test.log"
    FAILED+=("app")
    return
  fi
  echo "  초록 — 테스트 ${count}개 통과"
}

run_docs() {
  echo "── docs — 낡은 서술 검사 ──────────────────────────────────"
  (cd "$ROOT" && bash .github/scripts/check-docs-drift.sh) > "$OUT/docs.log" 2>&1
  if [ $? -ne 0 ]; then
    echo "  실패 — $OUT/docs.log"
    tail -10 "$OUT/docs.log"
    FAILED+=("docs")
    return
  fi
  # 그 게이트도 이제 검사마다 몇 개를 봤는지 찍는다. 그대로 보여 준다 — "OK" 세 줄과
  # "0개를 보고 OK" 를 사람이 구분할 수 있어야 한다 (#643).
  grep '^  OK' "$OUT/docs.log" | sed 's/^  /  /'
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
