#!/usr/bin/env bash
#
# 배포할 때 몇 초나 끊기는지 잰다 — 이슈 #787.
#
# ## 왜 이 스크립트가 필요한가
#
# "무중단 배포를 했다" 는 **잰 숫자가 있어야 할 수 있는 말**이다. 고치기 전과 뒤를
# 같은 방법으로 재서 나란히 적지 않으면, 좋아졌는지 나빠졌는지 아무도 모른다.
#
# 재는 방법 자체는 어렵지 않다 — 0.2초마다 헬스를 찌르면서 그동안 배포를 건다.
# 어려운 것은 **두 가지를 동시에** 해야 한다는 점이고, 그래서 창을 둘 띄우다 보면
# 시작 시각이 어긋나 "언제부터 끊겼는지" 를 못 맞춘다. 이 스크립트가 둘을 한 번에 한다.
#
# ## 2026-10-21 에 운영에서 처음 재고 배운 것
#
# 끊김이 **36.6초**였는데, 실패 159건의 속내가 이랬다.
#
#     curl 56 (받기 실패)   154건 ≈ 30.8초   연결은 받아들여지는데 응답을 못 준다
#     curl  7 (연결 거부)     4건 ≈  0.8초   포트에 아무도 없다
#     HTTP 503                1건            스프링은 떴는데 아직 DOWN
#
# **포트가 비어 있던 시간은 0.8초뿐이다.** 도커가 컨테이너를 띄우는 즉시 포트를 묶기
# 때문에, TCP 연결은 성립하는데 뒤의 스프링은 아직 부팅 중이다. 부르는 쪽에는 그것이
# "에러" 가 아니라 **"멈춤"** 으로 보인다.
#
# 그래서 **종류별로 세는 것이 총합보다 중요하다.** 총합만 보면 진입점을 고쳐서 줄어들
# 것 같지만, 종류를 보면 대부분이 스프링 부팅 시간이라 블루/그린 말고는 못 줄인다.
#
# ## 쓰는 법
#
#     # 재기동하면서 잰다 (기본)
#     bash backend/scripts/measure-restart-downtime.sh --dir /opt/pawloop-backend/repo/backend --prod
#
#     # 스테이징 (prod 오버라이드 없음)
#     bash backend/scripts/measure-restart-downtime.sh --dir ~/heattrip/backend --label 전-1회차
#
#     # 내리지 않고 지켜보기만 — 다른 창에서 진짜 배포를 걸 때
#     bash backend/scripts/measure-restart-downtime.sh --watch-only
#
# ## 운영에서 돌릴 때
#
# **`--prod` 를 빼면 안 된다.** compose 가 `docker-compose.prod.yml` 을 못 보고
# MySQL 볼륨을 지울지 묻는다(#615). 그 프롬프트의 답은 언제나 N 이다.
#
# 그리고 `refresh-prod-env.sh` 는 **자기가 재기동까지 한다.** 설정을 바꾸면서 재려면
# 이 스크립트가 아니라 그쪽을 쓰고, 이 스크립트는 `--watch-only` 로 옆에서 지켜본다.
set -u

DIR="."
SERVICE="app"
PORT="8080"
SAMPLES="600"      # 0.2초 × 600 ≈ 2분. 재기동이 그 안에 끝난다
INTERVAL="0.2"
PROD=0
WATCH_ONLY=0
LABEL=""

usage() {
  cat >&2 <<'USAGE'
쓰는 법: bash measure-restart-downtime.sh [옵션]

  --dir PATH       compose 파일이 있는 폴더 (기본: 지금 폴더)
  --service NAME   재기동할 서비스 (기본: app)
  --port N         헬스를 찌를 포트 (기본: 8080)
  --samples N      표본 수 (기본: 600 ≈ 2분)
  --prod           docker-compose.prod.yml 을 함께 쓴다 (운영에서는 필수)
  --watch-only     내리지 않고 지켜보기만 한다
  --label TEXT     결과에 붙일 이름 (예: 전-1회차)
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dir)        [ $# -ge 2 ] || { usage; exit 2; }; DIR="$2"; shift 2 ;;
    --service)    [ $# -ge 2 ] || { usage; exit 2; }; SERVICE="$2"; shift 2 ;;
    --port)       [ $# -ge 2 ] || { usage; exit 2; }; PORT="$2"; shift 2 ;;
    --samples)    [ $# -ge 2 ] || { usage; exit 2; }; SAMPLES="$2"; shift 2 ;;
    --label)      [ $# -ge 2 ] || { usage; exit 2; }; LABEL="$2"; shift 2 ;;
    --prod)       PROD=1; shift ;;
    --watch-only) WATCH_ONLY=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *)            echo "모르는 옵션: $1" >&2; usage; exit 2 ;;
  esac
done

cd "$DIR" 2>/dev/null || { echo "폴더가 없다: $DIR" >&2; exit 1; }

COMPOSE=(docker compose -f docker-compose.yml)
if [ "$PROD" -eq 1 ]; then
  [ -f docker-compose.prod.yml ] || { echo "--prod 인데 docker-compose.prod.yml 이 없다." >&2; exit 1; }
  COMPOSE+=(-f docker-compose.prod.yml)
fi

HEALTH="http://127.0.0.1:${PORT}/actuator/health"
LOG="/tmp/restart-downtime-$(date +%Y%m%d-%H%M%S).log"

echo "호스트      $(hostname)"
echo "폴더        $(pwd)"
echo "서비스      $SERVICE$([ "$PROD" -eq 1 ] && echo '  (prod 오버라이드 켜짐)')"
echo "헬스        $HEALTH"
echo "표본        ${SAMPLES}개 × ${INTERVAL}초"
echo "로그        $LOG"
[ -n "$LABEL" ] && echo "이름        $LABEL"
echo

# 재기동 전에 지금 살아 있는지부터 본다. 죽어 있는 것을 재면 숫자가 거짓이 된다.
BASE=$(curl -s -o /dev/null -m 2 -w '%{http_code}' "$HEALTH")
if [ "$BASE" != "200" ]; then
  echo "시작 전 헬스가 $BASE 다. 200 이 아니면 재도 뜻이 없다." >&2
  exit 1
fi
echo "시작 전 헬스 200 — 잰다."

if [ "$WATCH_ONLY" -eq 1 ]; then
  echo
  echo ">> 지켜보기만 한다. 다른 창에서 배포를 거세요."
else
  echo
  echo ">> ${SERVICE} 를 내렸다 올린다. 그동안 서비스가 끊긴다."
  for i in 3 2 1; do printf "   %d..." "$i"; sleep 1; done
  echo
fi

# ── 지켜보는 쪽 ────────────────────────────────────────────────
(
  i=0
  while [ "$i" -lt "$SAMPLES" ]; do
    code=$(curl -s -o /dev/null -m 2 -w '%{http_code}' "$HEALTH")
    rc=$?
    echo "$(date +%s.%N) $code $rc"
    sleep "$INTERVAL"
    i=$((i + 1))
  done
) > "$LOG" 2>&1 &
PROBE=$!

sleep 3   # 멀쩡할 때의 기준선을 먼저 찍는다

T_START=$(date +%s.%N)
if [ "$WATCH_ONLY" -eq 0 ]; then
  echo ">> 재기동"
  "${COMPOSE[@]}" up -d --force-recreate --no-deps "$SERVICE" 2>&1 | sed 's/^/   /'
fi
T_END=$(date +%s.%N)

echo ">> 표본이 다 찰 때까지 기다린다"
wait "$PROBE" 2>/dev/null

# ── 결과 ──────────────────────────────────────────────────────
echo
echo "================= 결과${LABEL:+ · $LABEL} ================="
awk -v a="$T_START" -v b="$T_END" -v iv="$INTERVAL" '
  { total++ }
  $2 != 200 { n++; if (!s) s = $1; e = $1 }
  END {
    printf "표본            %d개\n", total;
    printf "명령 걸린 시간  %.1f초\n", b - a;
    if (n == 0) {
      printf "\n끊김 없음 — 200 이 아닌 응답이 0건\n";
    } else {
      printf "\n끊긴 시간       %.1f초\n", e - s + iv;
      printf "실패            %d건\n", n;
      printf "첫 실패         명령 시작 %.1f초 뒤\n", s - a;
    }
  }' "$LOG"

echo
echo "-- 실패 종류별 --"
awk '$2 != 200 { print $2, $3 }' "$LOG" | sort | uniq -c | while read -r cnt http rc; do
  case "$rc" in
    7)  why="연결 거부 — 포트에 아무도 없다" ;;
    28) why="타임아웃 — 받긴 받는데 2초 안에 답이 없다" ;;
    52) why="빈 응답 — 연결은 됐는데 아무것도 안 준다" ;;
    56) why="받기 실패 — 연결은 받아들여지는데 응답을 못 준다" ;;
    0)  why="HTTP 로는 성공했지만 200 이 아니다" ;;
    *)  why="" ;;
  esac
  printf "  %4d건  HTTP %-4s curl %-3s %s\n" "$cnt" "$http" "$rc" "$why"
done
[ "$(awk '$2 != 200' "$LOG" | wc -l)" -eq 0 ] && echo "  (없음)"

echo
echo "-- 지금 컨테이너 --"
"${COMPOSE[@]}" ps --format '{{.Service}}  {{.Status}}' 2>/dev/null

echo
echo "로그를 맥으로 가져가려면:"
echo "  scp -i <키> <사용자>@<서버>:$LOG ."
