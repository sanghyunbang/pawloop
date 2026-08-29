#!/usr/bin/env bash
#
# 문서가 코드와 어긋난 채 남아 있는지 검사한다 — 이슈 #59.
#
# 왜 필요한가
#   #29 가 flutter_dotenv 를 걷어내고 --dart-define 으로 옮긴 뒤, "`.env` 에서
#   환경값을 읽는다" 는 서술이 문서 곳곳에 남았다. #41 과 #54 가 두 번에 걸쳐
#   14줄을 고쳤는데, 그건 사람이 눈으로 찾아서 고친 것이다. 다음에 같은 일이
#   생기면 또 누군가 기억해야 한다.
#
#   이 스크립트는 그 기억을 CI 로 옮긴다.
#
# 무엇을 잡는가
#   앱 문서에서 `.env` 나 flutter_dotenv 를 **현재형으로** 언급하는 줄.
#   "예전에는 이랬다" 는 이력 서술은 통과시킨다 — 그건 지워야 할 거짓이 아니라
#   남겨야 할 맥락이다.
#
# 무엇을 잡지 않는가
#   - 백엔드의 `backend/.env` — 실재한다. application-dev.properties 가
#     spring.config.import 로 읽는다
#   - APK 안에 .env 가 없는지 확인하는 검증 커맨드 (setup.md)
#   - 이력 서술 (아래 ALLOW 패턴)
#
# 새 드리프트 규칙을 더할 때는 RULES 에 한 줄 추가한다.

set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

FAILED=0

# 이력·정상 언급으로 인정하는 표현. 한 줄에 이 중 하나라도 있으면 통과.
#
# backend 계열을 통과시키는 이유: `backend/.env` 는 실재한다.
# application-dev.properties 가 spring.config.import 로 읽는다. 앱의 .env 와 다른 물건이다.
ALLOW='예전|걷어냈|걷어내|제거했|버렸|이력|더 이상|이제는|dart-define|\.env\.example|없어도|없이|남아 있지 않은지|flutter_assets/\.env|backend/\.env|application-dev|application-prod|spring\.config\.import'

# ── 아직 못 고친 줄 (소유 이슈가 있는 것만) ────────────────────────────────
#
# 여기 적힌 줄은 게이트를 통과한다. **소유 이슈 번호가 없으면 적지 말 것** —
# 소유자 없는 예외는 영원히 남는다.
#
# 고쳐지면 이 목록에서 지운다. 지우지 않으면 게이트가 그 줄을 계속 눈감아 준다.
KNOWN_STALE=(
  "docs/04-api/api-spec.md:.*serviceKey.*YOUR_DECODING_SERVICE_KEY"   # 소유 #10 (계약 정합)
  "docs/99-decisions/decision-log.md:.*serviceKey 취급 주의"           # 소유 #15 (ADR·문서 정합)
)

is_known_stale() {
  local line="$1"
  for pattern in "${KNOWN_STALE[@]}"; do
    if printf '%s' "$line" | grep -qE "$pattern"; then
      return 0
    fi
  done
  return 1
}

echo "── 문서 드리프트 검사 ──"

scan() {
  local label="$1" root="$2" pattern="$3"
  local raw hits=""
  raw=$(grep -rnE "$pattern" "$root" --include='*.md' 2>/dev/null \
        | grep -vE "$ALLOW" || true)

  # 소유 이슈가 붙은 알려진 항목은 통과시킨다.
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    if is_known_stale "$line"; then
      echo "  (알려진 미해결, 소유 이슈 있음) ${line%%:*}"
      continue
    fi
    hits="${hits}${line}"$'\n'
  done <<< "$raw"

  hits="${hits%$'\n'}"

  if [ -n "$hits" ]; then
    echo
    echo "::error::낡은 서술: $label"
    echo "$hits" | sed 's/^/    /'
    echo
    echo "    #29 이후 앱 환경값은 --dart-define 으로 들어온다. 문서를 고치거나,"
    echo "    이력 서술이라면 '예전에는' 같은 표현을 넣어 의도를 분명히 하라."
    FAILED=1
  else
    echo "  OK  $label"
  fi
}

scan "앱 문서가 .env 를 현재형으로 말한다" "docs" '`\.env`|flutter_dotenv'

# 코드에도 남아 있으면 안 된다 — #29 가 의존성을 지웠으므로 import 는 컴파일도 안 되지만,
# 주석·문자열로 남아 사용자에게 보이는 안내가 되는 경우가 있었다(emotion_map_screen.dart).
scan "앱 코드가 사용자에게 .env 를 안내한다" "app/lib" 'flutter_dotenv|\.env 확인|\.env를 확인|\.env 를 확인'

echo
if [ "$FAILED" -ne 0 ]; then
  echo "실패 — 위 줄들을 고치거나 이력 서술로 명시할 것."
  exit 1
fi
echo "통과 — 낡은 .env 서술 없음."
