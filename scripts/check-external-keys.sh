#!/usr/bin/env bash
# 외부 API 키가 지금도 살아 있는지 한 번에 물어본다.
#
# ## 왜 있나
#
# 공공데이터포털은 계정 하나에 인증키 하나지만 **API 마다 활용신청이 따로**다. 그래서
# "키는 있는데 이 API 만 안 된다" 가 정상적으로 일어나고, 그 실패는 서버 로그 안쪽에서
# `SERVICE_KEY_IS_NOT_REGISTERED_ERROR` 로만 보인다 — 화면에서는 카드 하나가 안 뜰 뿐이다.
# 키를 새로 신청한 날, 키를 갈아 끼운 날, 배포 전날에 여기서 한 번 물어본다.
#
# ## 무엇을 도나
#
#   1. 공공데이터포털 API 일곱을 실제로 부른다 — 승인됐는지, 응답이 오는지.
#   2. `.env` 와 `dart-define.json` 에 어떤 이름이 있고 무엇이 비었는지 센다.
#
# ## 키를 찍지 않는다
#
# 응답 본문에 키가 섞여 와도 «KEY» 로 가리고, `.env` 는 **이름과 채움 여부**만 읽는다.
# 이 스크립트의 출력을 그대로 이슈에 붙여도 되게 만들어 뒀다.
#
# ## 쓰는 법
#
#   bash scripts/check-external-keys.sh            # 전부
#   bash scripts/check-external-keys.sh public     # 공공데이터포털만
#   bash scripts/check-external-keys.sh env        # .env 이름 점검만
#
# 나가는 값: 지금 앱이 기대는 API 중 하나라도 죽어 있으면 1. 에어코리아처럼 **아직 신청을
# 안 한 것**은 실패로 세지 않는다 — 기다리는 중인 것과 깨진 것은 다르다.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WHAT="${1:-all}"
BASE="https://apis.data.go.kr"
BROKEN=0

# ── 키 읽기 ──────────────────────────────────────────────────────────
# application.properties 와 같은 순서다: PUBLIC_DATA_SERVICE_KEY → TOUR_API_SECRET.
read_env() {
  local file="$1" name="$2"
  [ -f "$file" ] || return 0
  grep -m1 "^${name}=" "$file" | cut -d= -f2- | tr -d ' \r'
}

# 환경변수가 먼저다 — 서버도 그 순서로 읽고(application.properties), 새로 받은 키를
# `.env` 에 넣기 전에 먼저 물어볼 수 있다:
#   PUBLIC_DATA_SERVICE_KEY=… bash scripts/check-external-keys.sh public
KEY="${PUBLIC_DATA_SERVICE_KEY:-${TOUR_API_SECRET:-}}"
[ -z "$KEY" ] && KEY="$(read_env "$ROOT/backend/.env" PUBLIC_DATA_SERVICE_KEY)"
[ -z "$KEY" ] && KEY="$(read_env "$ROOT/backend/.env" TOUR_API_SECRET)"

mask() { [ -n "$KEY" ] && printf '%s' "${1//$KEY/«KEY»}" || printf '%s' "$1"; }

# 한글은 터미널에서 두 칸을 먹는다. printf 의 %-32s 는 그것을 모르고 한 칸으로 세서
# 표가 어긋난다 — 폭을 직접 재서 채운다.
pad() {
  # LC_ALL 을 안 주면 awk 가 바이트를 센다 — 한글 한 글자가 3 으로 잡혀 폭이 두 배가 된다.
  LC_ALL=C.UTF-8 awk -v s="$1" -v want="$2" 'BEGIN {
    n = 0
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      n += (c ~ /^[\x20-\x7e]$/) ? 1 : 2
    }
    printf "%s", s
    for (i = n; i < want; i++) printf " "
  }'
}

# ── 하나 물어보기 ────────────────────────────────────────────────────
# $1 이름 · $2 URL · $3 기대(required|pending) · $4 성공을 알아보는 문자열
ask() {
  local name="$1" url="$2" expect="$3" ok_mark="$4" body verdict note
  body="$(curl -s --max-time 25 "$url" 2>/dev/null)"
  body="$(mask "$body")"

  if [ -z "$body" ]; then
    verdict="✗ 응답 없음"; note="(타임아웃이거나 네트워크)"
  elif printf '%s' "$body" | grep -q "$ok_mark"; then
    verdict="✓ 승인"; note="응답 정상"
  elif printf '%s' "$body" | grep -q "SERVICE_KEY_IS_NOT_REGISTERED_ERROR"; then
    verdict="… 활용신청 대기"; note="SERVICE_KEY_IS_NOT_REGISTERED_ERROR"
  elif printf '%s' "$body" | grep -q "NO_OPENAPI_SERVICE_ERROR"; then
    # 승인 대기가 **아니다.** 게이트웨이가 "그런 오퍼레이션이 없다" 고 말하는 것이라
    # 대개 우리 쪽 경로가 틀렸다. 2026-09-08 에 실제로 그랬다 — 에어코리아 실시간 측정의
    # 이름이 getMsrstnAcct(nt)RltmMesureDnsty 였고, 승인이 난 뒤에도 계속 이 오류였다.
    verdict="✗ 주소가 틀렸다"; note="NO_OPENAPI_SERVICE_ERROR — 승인 문제가 아니라 오퍼레이션 이름/경로를 본다"
  elif printf '%s' "$body" | grep -q "LIMITED_NUMBER_OF_SERVICE_REQUESTS"; then
    verdict="⚠ 한도 초과"; note="오늘 호출 한도를 다 썼다 — 승인 자체는 살아 있다"
  else
    verdict="✗ 알 수 없음"; note="$(printf '%s' "$body" | tr -d '\n' | tr -s ' ' | head -c 90)"
  fi

  printf '  %s %s %s\n' "$(pad "$name" 34)" "$(pad "$verdict" 16)" "$note"
  case "$verdict" in
    "✓ 승인"|"⚠ 한도 초과") return 0 ;;
    "… 활용신청 대기") [ "$expect" = "required" ] && BROKEN=$((BROKEN + 1)); return 0 ;;
    *) [ "$expect" = "required" ] && BROKEN=$((BROKEN + 1)); return 0 ;;
  esac
}

check_public_data() {
  echo "── 공공데이터포털 — API 마다 활용신청이 따로다 ───────────────"
  if [ -z "$KEY" ]; then
    echo "  backend/.env 에서 키를 못 읽었다 (PUBLIC_DATA_SERVICE_KEY · TOUR_API_SECRET)"
    BROKEN=$((BROKEN + 1))
    return
  fi

  local common="MobileOS=ETC&MobileApp=heattrip&_type=json&numOfRows=1&pageNo=1"
  local seoul="mapX=127.0396&mapY=37.5443&radius=2000&arrange=E"

  ask "KTO 반려동물 동반여행" \
    "$BASE/B551011/KorPetTourService2/locationBasedList2?serviceKey=$KEY&$common&$seoul" \
    required '"resultCode":"0000"'

  ask "KTO 국문 관광정보(장소 개요)" \
    "$BASE/B551011/KorService2/locationBasedList2?serviceKey=$KEY&$common&$seoul" \
    required '"resultCode":"0000"'

  ask "KTO 두루누비(걷기여행길)" \
    "$BASE/B551011/Durunubi/courseList?serviceKey=$KEY&$common&brdDiv=DNWW" \
    required '"resultCode":"0000"'

  local localdata="pageNo=1&numOfRows=1&returnType=json&cond%5BSALS_STTS_CD%3A%3AEQ%5D=01"
  ask "행안부 인허가 — 동물병원" \
    "$BASE/1741000/animal_hospitals/info?serviceKey=$KEY&$localdata" \
    required '"BPLC_NM"'

  ask "행안부 인허가 — 동물판매업" \
    "$BASE/1741000/animal_sales/info?serviceKey=$KEY&$localdata" \
    required '"BPLC_NM"'

  # 초단기실황은 매시 40분에 그 시각 것이 나온다 — 한 시간 전을 시 단위로 부른다(KST).
  local bd bt
  bd="$(TZ=Asia/Seoul date -d '-1 hour' +%Y%m%d)"
  bt="$(TZ=Asia/Seoul date -d '-1 hour' +%H00)"
  ask "기상청 초단기실황 ($bd $bt)" \
    "$BASE/1360000/VilageFcstInfoService_2.0/getUltraSrtNcst?serviceKey=$KEY&dataType=JSON&numOfRows=10&pageNo=1&base_date=$bd&base_time=$bt&nx=61&ny=126" \
    required '"resultCode":"00"'

  # 아래 둘은 아직 신청 전이다 — 승인되면 산책 안전 지수에 미세먼지가 붙는다(#336).
  ask "에어코리아 측정소정보" \
    "$BASE/B552584/MsrstnInfoInqireSvc/getMsrstnList?serviceKey=$KEY&returnType=json&numOfRows=1&pageNo=1" \
    pending '"stationName"'

  ask "에어코리아 대기오염정보" \
    "$BASE/B552584/ArpltnInforInqireSvc/getMsrstnAcctoRltmMesureDnsty?serviceKey=$KEY&returnType=json&numOfRows=1&pageNo=1&stationName=%EC%A4%91%EA%B5%AC&dataTerm=DAILY&ver=1.3" \
    pending '"pm10Value"'
}

# ── 이름과 채움 여부만 ───────────────────────────────────────────────
check_env_names() {
  echo
  echo "── 자리는 있는가 — 이름과 채움 여부만 본다 ────────────────────"
  local file="$ROOT/backend/.env"
  if [ ! -f "$file" ]; then
    echo "  backend/.env 가 없다 — backend/.env.example 을 복사한다"
  else
    for name in TOUR_API_SECRET PUBLIC_DATA_SERVICE_KEY \
                KAKAO_CLIENT_ID KAKAO_CLIENT_SECRET \
                GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET \
                APPLE_CLIENT_ID APPLE_TEAM_ID APPLE_KEY_ID APPLE_PRIVATE_KEY \
                AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_S3_BUCKET \
                JWT_SECRET; do
      local value
      value="$(read_env "$file" "$name")"
      case "$value" in
        "") printf '  %s %s\n' "$(pad "$name" 24)" "— 비어 있음" ;;
        change-me*|dev-*) printf '  %s %s\n' "$(pad "$name" 24)" "— 자리표시 그대로" ;;
        *) printf '  %s %s\n' "$(pad "$name" 24)" "채워짐 (${#value}자)" ;;
      esac
    done
  fi

  echo
  local defines="$ROOT/app/dart-define.json"
  if [ -f "$defines" ]; then
    for name in NAVER_MAP_CLIENT_ID API_BASE_URL UPLOAD_LOCATION; do
      local value
      value="$(grep -oE "\"$name\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$defines" | head -1 | sed 's/.*: *"//;s/"$//')"
      case "$value" in
        "") printf '  %s %s\n' "$(pad "$name" 24)" "— 비어 있음 (app/dart-define.json)" ;;
        *) printf '  %s %s\n' "$(pad "$name" 24)" "채워짐 (${#value}자) (app/dart-define.json)" ;;
      esac
    done
  else
    echo "  app/dart-define.json 이 없다 — dart-define.example.json 을 복사한다"
    echo "  (없이 빌드하면 지도 자리에 안내 카드가 뜬다 — 이슈 #182)"
  fi
}

case "$WHAT" in
  public) check_public_data ;;
  env) check_env_names ;;
  all) check_public_data; check_env_names ;;
  *) echo "쓰는 법: bash scripts/check-external-keys.sh [all|public|env]"; exit 2 ;;
esac

echo
if [ "$BROKEN" -gt 0 ]; then
  echo "지금 기대고 있는 API 중 $BROKEN 개가 응답하지 않는다."
  exit 1
fi
echo "지금 기대고 있는 API 는 전부 살아 있다. '활용신청 대기' 는 아직 신청 안 한 것이다."
