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
#   ① 앱 문서에서 `.env` 나 flutter_dotenv 를 **현재형으로** 언급하는 줄.
#   ② 죽은 운영 주소 `api.heattrip.link` (#682) — 2026-09-17 에 `api.pawloop.app`
#      으로 옮겼고 옛 주소는 Cloudflare 530 이다.
#   ③ 옛 딥링크 스킴 `heattrip://` (#649) — 지금은 `pawloop://` 다.
#
#   ②·③ 이 ① 과 같은 자리에 있는 이유는 고장 나는 방식이 같아서다. 문서를 그대로
#   따라 하면 결과물이 조용히 안 붙는다 — 옛 주소로 빌드한 APK 는 "연결이 불안정해요"
#   만 띄우고, 옛 스킴을 등록한 앱은 로그인 뒤 브라우저에 멈춘다. 둘 다 원인이
#   문서의 낱말 하나라는 것이 화면에서는 안 보인다.
#
#   "예전에는 이랬다" 는 이력 서술은 통과시킨다 — 그건 지워야 할 거짓이 아니라
#   남겨야 할 맥락이다. 다만 ①과 ②·③ 은 그것을 가리는 방법이 다르다. ① 은 낱말로
#   보고, ②·③ 은 **새 값이 같은 줄에 있는지**로 본다 — 왜 그런지는 아래 주석에.
#
# 무엇을 잡지 않는가
#   - 백엔드의 `backend/.env` — 실재한다. application-dev.properties 가
#     spring.config.import 로 읽는다
#   - APK 안에 .env 가 없는지 확인하는 검증 커맨드 (setup.md)
#   - 이력 서술 (아래 ALLOW · DEAD_HOST_ALLOW · OLD_SCHEME_ALLOW)
#   - `docs/04-api/audit-2026-08/` 과 `docs/99-decisions/` — 그때의 파일을 줄번호까지
#     인용한 기록이다. 고치면 기록이 거짓이 된다
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

# ── 죽은 주소를 통과시키는 조건 (#682) ─────────────────────────────────────
#
# 아래 규칙들(죽은 API 주소·옛 딥링크 스킴)은 `.env` 규칙과 통과 조건이 다르다.
# `dart-define` 이 한 줄에 있다고 죽은 주소가 살아나지는 않기 때문이다 — 실제로
# setup.md 의 릴리스 빌드 명령이 `--dart-define=API_BASE_URL=https://api.heattrip.link`
# 한 줄이었고, 위 ALLOW 로는 그 줄이 그냥 통과한다. 그래서 따로 둔다.
#
# **낱말로 통과시키지 않는다.** 처음에는 "예전|이력|옮겼|였다" 같은 이력 표현으로
# 통과시켰는데, 그것이 거짓 초록을 냈다. 옛 스킴을 도로 집어넣고 돌려 봤더니
# 게이트가 초록이었다 — 그 줄에 마침 "(#14 이전에는 `?token=` 이었다)" 가 붙어 있어서
# `이전에는` 에 걸린 것이다. 그 낱말은 스킴과 아무 상관이 없었다. README 도
# 같은 식으로 `옮겼` 에 걸려 통과했다. 이력 표현은 **줄 어디에나** 있을 수 있어서
# "이 줄이 이력인가" 의 근거가 못 된다.
#
# 그래서 조건을 기계적인 것으로 바꿨다 — **옛 값을 적으려면 새 값을 같은 줄에
# 적어야 한다.** 이력 서술은 자연히 그렇게 쓰이고("`heattrip://` 였고 지금은
# `pawloop://` 다"), 사람을 잘못 이끄는 줄은 자연히 안 그렇다(빌드 명령 한 줄,
# `servers:` 의 url 한 줄, 등록표의 칸 하나). 읽는 사람에게도 이편이 낫다 —
# 옛 주소만 덩그러니 적힌 줄은 언제나 "그래서 지금은 뭐냐" 를 남긴다.
#
# grep -rn 의 출력은 `경로:줄번호:내용` 이라 경로도 이 패턴에 걸린다. 그래서
# 기록 디렉터리 둘은 이름만으로 통과한다 — 그때의 파일을 줄번호까지 인용한
# 기록이고, 고치면 기록이 거짓이 된다.
RECORD_DIRS='audit-2026-08|99-decisions'
DEAD_HOST_ALLOW="$RECORD_DIRS"'|api\.pawloop\.app'
OLD_SCHEME_ALLOW="$RECORD_DIRS"'|pawloop://'

DEFAULT_HINT="#29 이후 앱 환경값은 --dart-define 으로 들어온다. 문서를 고치거나,
이력 서술이라면 '예전에는' 같은 표현을 넣어 의도를 분명히 하라."

DEAD_HOST_HINT="운영 API 주소는 https://api.pawloop.app 이다. 옛 api.heattrip.link 는
Cloudflare 530 이라 그 주소로 만든 빌드는 서버에 못 붙는다 (#682).
이력으로 남길 줄이면 새 주소 api.pawloop.app 을 **같은 줄에** 함께 적어라."

OLD_SCHEME_HINT="로그인 콜백 스킴은 pawloop://login-callback 이다. 옛 heattrip:// 는
같은 이름표를 단 예전 앱이 가로채서 2026-09 에 옮겼다 (#649).
서버가 허용하는 값은 app.security.oauth.redirect-allowlist 가 정한다.
이력으로 남길 줄이면 새 스킴 pawloop:// 를 **같은 줄에** 함께 적어라."

# ── 아직 못 고친 줄 (소유 이슈가 있는 것만) ────────────────────────────────
#
# 여기 적힌 줄은 게이트를 통과한다. **소유 이슈 번호가 없으면 적지 말 것** —
# 소유자 없는 예외는 영원히 남는다.
#
# 고쳐지면 이 목록에서 지운다. 지우지 않으면 게이트가 그 줄을 계속 눈감아 준다.
KNOWN_STALE=(
  # 지금은 비어 있다.
  #
  # 마지막 항목이었던 decision-log.md 의 "serviceKey 취급 주의" 는 #15 에서 고쳤다 —
  # ADR-0004 의 그 줄이 이제 `--dart-define=YOUR_DECODING_SERVICE_KEY` 를 말하고
  # `.env` 는 "예전에는 … #29 가 옮겼다" 는 이력 서술로만 남아 ALLOW 를 탄다.
  # 예외를 지우지 않으면 게이트가 그 줄을 영원히 눈감아 준다.
  #
  # 새로 추가할 때는 **소유 이슈 번호를 반드시 적을 것.**
)

is_known_stale() {
  local line="$1"
  # 목록이 비면 `"${arr[@]}"` 가 오래된 bash(<4.4) + `set -u` 에서 unbound 로 죽는다.
  # 지금은 비어 있는 것이 정상 상태이므로 먼저 막는다.
  [ "${#KNOWN_STALE[@]}" -eq 0 ] && return 1
  for pattern in "${KNOWN_STALE[@]}"; do
    if printf '%s' "$line" | grep -qE "$pattern"; then
      return 0
    fi
  done
  return 1
}

echo "── 문서 드리프트 검사 ──"

scan() {
  # 다섯 번째 인자는 **이 규칙만의 통과 표현**이다. 안 주면 `.env` 규칙의 ALLOW 를 쓴다.
  # 규칙마다 "이건 이력이라 괜찮다" 의 뜻이 다르기 때문에 인자로 뺐다 (#682).
  local label="$1" root="$2" pattern="$3" include="${4:-*.md}" allow="${5:-$ALLOW}"
  # 여섯 번째는 빨간불일 때 찍을 안내문이다. 규칙이 셋에서 다섯으로 늘면서 ".env 는
  # --dart-define 으로 옮겼다" 하나로는 안 맞게 됐다 — 죽은 주소를 고치러 온 사람에게
  # 그 문장은 아무 말도 아니다 (#682).
  local hint="${6:-$DEFAULT_HINT}"
  local raw hits="" scanned

  # **몇 개를 봤는지 먼저 센다** — 0개면 빨간불이다 (#643).
  #
  # 아래 grep 은 대상이 없어도 조용하다: `2>/dev/null` 이 "그런 파일이 없다" 를 삼키고
  # `|| true` 가 종료 코드를 지운다. 그러면 빈 결과가 나오고 이 함수는 `OK` 를 찍는다 —
  # **"아무것도 안 봤다" 가 "깨끗하다" 로 둔갑한다.**
  #
  # 이게 이론이 아니라, 아래 세 번째 호출이 실제로 그 상태였다. 라벨은 "앱 코드" 인데
  # include 가 `*.md` 로 박혀 있어서 `app/lib` 의 dart 185개 대신 md 1개를 보고 있었다.
  # 그래서 include 를 인자로 받고, 본 개수를 세고, 0개면 죽는다. 다음에 경로를 옮기거나
  # 이름을 바꾸는 사람은 조용한 초록 대신 빨간불을 본다.
  scanned=$(find "$root" -type f -name "$include" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$scanned" -eq 0 ]; then
    echo
    echo "::error::검사 대상이 0개다: $label"
    echo "    root=$root  include=$include"
    echo
    echo "    경로를 옮겼거나 이름을 바꿨으면 이 스크립트의 scan 호출도 같이 고쳐라."
    echo "    0개를 보고 통과시키면 이 게이트는 있으나 마나다."
    FAILED=1
    return
  fi

  raw=$(grep -rnE "$pattern" "$root" --include="$include" 2>/dev/null \
        | grep -vE "$allow" || true)

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
    echo "$hint" | sed 's/^/    /'
    FAILED=1
  else
    echo "  OK  $label (${scanned}개 훑음)"
  fi
}

scan "앱 문서가 .env 를 현재형으로 말한다" "docs" '`\.env`|flutter_dotenv'

# 루트 README 도 본다. 저장소의 첫인상 문서인데 검사 밖에 있었고, 그 사이
# 넉 달 전을 말하는 서술이 15곳까지 쌓였다(2026-09-02). grep -r 은 파일 하나에도
# 그대로 동작한다.
scan "README 가 .env 를 현재형으로 말한다" "README.md" '`\.env`|flutter_dotenv'

# 코드에도 남아 있으면 안 된다 — #29 가 의존성을 지웠으므로 import 는 컴파일도 안 되지만,
# 주석·문자열로 남아 사용자에게 보이는 안내가 되는 경우가 있었다(emotion_map_screen.dart).
scan "앱 코드가 사용자에게 .env 를 안내한다" "app/lib" 'flutter_dotenv|\.env 확인|\.env를 확인|\.env 를 확인' '*.dart'

# ── 죽은 운영 주소 (#682) ──────────────────────────────────────────────────
#
# 2026-09-17 에 운영 주소가 api.heattrip.link → api.pawloop.app 으로 바뀌었다.
# 옛 주소는 Cloudflare 530 을 준다 — 살아 있지 않다.
#
# 이것이 왜 게이트가 되어야 하는가: setup.md 의 릴리스 빌드 명령이 옛 주소를 그대로
# 들고 있었다. 그 문서대로 만든 APK 는 서버에 못 붙고, 화면에는 "연결이 불안정해요"
# 로만 보인다 — 빌드 명령의 한 낱말이 원인이라는 것이 거기서는 안 보인다.
#
# 계약 파일도 본다. openapi.yaml 의 `servers:` 가 옛 주소였고, 그 계약으로 클라이언트를
# 만드는 사람은 문서를 읽지도 않고 죽은 주소를 받는다. `*.md` 만 보면 그것을 놓친다.
scan "문서가 죽은 운영 주소를 말한다"        "docs"      'heattrip\.link' '*.md'   "$DEAD_HOST_ALLOW" "$DEAD_HOST_HINT"
scan "계약(yaml)이 죽은 운영 주소를 말한다"  "docs"      'heattrip\.link' '*.yaml' "$DEAD_HOST_ALLOW" "$DEAD_HOST_HINT"
scan "README 가 죽은 운영 주소를 말한다"     "README.md" 'heattrip\.link' '*.md'   "$DEAD_HOST_ALLOW" "$DEAD_HOST_HINT"

# ── 옛 딥링크 스킴 (#649) ──────────────────────────────────────────────────
#
# 같은 종류의 고장이다. 문서가 시키는 대로 `heattrip` 스킴을 OS 에 등록하면 로그인이
# 브라우저에서 끝나고 앱으로 안 돌아온다. setup.md 의 iOS·안드로이드 등록표가 실제로
# 그 값이었다 — `app/test/platform_config_test.dart` 는 이미 `pawloop` 을 잠그고 있었는데
# 문서만 옛 값이었다.
#
# `heattrip://` 만 찾으면 그 등록표를 못 잡는다. 표에는 스킴이 URL 꼴로 안 적히고
# `CFBundleURLSchemes=[heattrip]` · `scheme=heattrip` 처럼 **설정값 꼴**로 적히기
# 때문이다. 정작 사람이 그대로 베끼는 것은 이 꼴이다.
OLD_SCHEME='heattrip://|CFBundleURLSchemes=\[heattrip\]|scheme=heattrip|scheme="heattrip"'
scan "문서가 옛 딥링크 스킴을 말한다"        "docs"      "$OLD_SCHEME"    '*.md'   "$OLD_SCHEME_ALLOW" "$OLD_SCHEME_HINT"
scan "README 가 옛 딥링크 스킴을 말한다"     "README.md" "$OLD_SCHEME"    '*.md'   "$OLD_SCHEME_ALLOW" "$OLD_SCHEME_HINT"

# ── README 의 그림이 생성기와 어긋났나 ────────────────────────────────────
#
# 같은 종류의 고장이다. `docs/diagrams/*.svg` 는 **밝은 판과 어두운 판 두 벌**이고,
# `scripts/build_diagrams.py` 가 한 소스에서 둘을 뽑는다. 손으로 고치면 **한쪽만 고친
# 채로 넘어간다** — 깃헙 라이트에서는 맞는데 다크에서는 옛 그림이 뜨는 식이고, 고친
# 사람은 자기 테마만 보므로 모른다.
#
# 그래서 커밋된 `.svg` 가 생성기의 지금 출력과 같은지 본다. 다르면 다시 뽑아 커밋해야
# 한다.
if command -v python3 >/dev/null 2>&1; then
  if DIAG_OUT=$(python3 scripts/build_diagrams.py --check 2>&1); then
    echo "  OK  $DIAG_OUT"
  else
    echo "  실패  README 그림이 생성기와 어긋난다"
    echo "$DIAG_OUT" | sed 's/^/        /'
    FAILED=1
  fi
else
  echo "  건너뜀  python3 가 없어 README 그림을 대조하지 못했다"
fi

echo
if [ "$FAILED" -ne 0 ]; then
  echo "실패 — 위 줄들을 고치거나 이력 서술로 명시할 것."
  exit 1
fi
echo "통과 — 낡은 .env 서술·죽은 주소·옛 딥링크 스킴 없고, README 그림도 생성기와 같다."
