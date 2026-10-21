#!/usr/bin/env bash
#
# 끊지 않고 배포한다 — 이슈 #787.
#
# ## 왜 이 스크립트가 필요한가
#
# `docker compose up -d` 한 줄로 배포하면 **36초가 끊긴다**(2026-10-21 실측). 옛 컨테이너를
# 내리고 새것을 올리는 사이가 통째로 비기 때문이고, 그 36초의 거의 전부가 "포트는 열렸는데
# 스프링이 아직 부팅 중" 이다. 끄는 쪽을 아무리 빨리 해도 안 줄어든다.
#
# 앱을 두 벌(`app-blue` · `app-green`) 두고 **새 쪽이 다 뜬 것을 확인한 뒤에** 옛 쪽을
# 내리면, 부팅 시간이 사용자 뒤로 숨는다. 그 순서를 이 스크립트가 쥔다.
#
#     쉬는 쪽을 새 이미지로 띄운다
#         ↓  healthy 가 될 때까지 기다린다  ← 여기를 건너뛰면 끊김이 그대로다
#     Caddy 가 둘 다 건강하다고 본다 (lb_policy first 라 아직 옛 쪽으로 간다)
#         ↓
#     옛 쪽을 내린다 → Caddy 가 새 쪽으로 넘긴다
#
# ## ⚠️ 겹치는 동안 로그인 일부가 실패한다
#
# `AuthCodeStore` 가 로그인 코드를 인메모리로 들고 있어서, 발급한 쪽과 교환받는 쪽이 다르면
# 401 이다. 겹치는 40~60초 동안 **그때 로그인 중이던 사람만** 해당한다 — 지금은 36초 동안
# 전부 끊기므로 그래도 낫다. 고치는 길은 이슈 #792 다.
#
# ## 메모리
#
# t3.medium 은 4GB 고 앱 한 벌이 660MB 를 쓴다. 겹치는 동안이 가장 빠듯하므로 **그 순간의
# `free` 와 `docker stats` 를 찍어 둔다.** 모자라면 OOM 킬러가 아무나 죽이는데, 하필 MySQL 이
# 죽으면 제일 나쁘다. 숫자를 보고 판단하라고 남긴다.
#
# ## 쓰는 법
#
#     # 운영
#     sudo bash scripts/deploy-bluegreen.sh --dir /opt/pawloop-backend/repo/backend --prod
#
#     # 스테이징
#     sudo bash scripts/deploy-bluegreen.sh --dir /opt/heattrip-backend/repo/backend
#
#     # 무엇을 할지만 보고 멈춘다
#     sudo bash scripts/deploy-bluegreen.sh --dry-run
#
# 끊김을 재려면 다른 창에서 `measure-restart-downtime.sh --watch-only` 를 먼저 켜 둔다.
set -u

DIR="."
PROD=0
NO_BUILD=0
DRY_RUN=0
WAIT_SECONDS=240

usage() {
  cat >&2 <<'USAGE'
쓰는 법: bash deploy-bluegreen.sh [옵션]

  --dir PATH    compose 파일이 있는 폴더 (기본: 지금 폴더)
  --prod        docker-compose.prod.yml 을 함께 쓴다 (운영에서는 필수)
  --no-build    이미지를 다시 만들지 않는다 (이미 빌드해 둔 경우)
  --dry-run     무엇을 할지만 보여 주고 멈춘다
  --wait N      새 쪽이 healthy 가 되기를 기다리는 최대 초 (기본: 240)
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dir)      [ $# -ge 2 ] || { usage; exit 2; }; DIR="$2"; shift 2 ;;
    --wait)     [ $# -ge 2 ] || { usage; exit 2; }; WAIT_SECONDS="$2"; shift 2 ;;
    --prod)     PROD=1; shift ;;
    --no-build) NO_BUILD=1; shift ;;
    --dry-run)  DRY_RUN=1; shift ;;
    -h|--help)  usage; exit 0 ;;
    *)          echo "모르는 옵션: $1" >&2; usage; exit 2 ;;
  esac
done

cd "$DIR" 2>/dev/null || { echo "폴더가 없다: $DIR" >&2; exit 1; }

COMPOSE=(docker compose -f docker-compose.yml)
if [ "$PROD" -eq 1 ]; then
  [ -f docker-compose.prod.yml ] || { echo "--prod 인데 docker-compose.prod.yml 이 없다." >&2; exit 1; }
  COMPOSE+=(-f docker-compose.prod.yml)
fi

health_of() {  # 컨테이너 이름 → starting | healthy | unhealthy | none
  docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$1" 2>/dev/null || echo none
}

running() {    # 서비스가 돌고 있나
  [ -n "$("${COMPOSE[@]}" ps --status running --services 2>/dev/null | grep -Fx "$1" || true)" ]
}

# ── 누가 살아 있나 ────────────────────────────────────────────
BLUE_UP=0; GREEN_UP=0
running app-blue  && BLUE_UP=1
running app-green && GREEN_UP=1

if [ "$BLUE_UP" -eq 1 ] && [ "$GREEN_UP" -eq 1 ]; then
  echo "둘 다 돌고 있다. 평소에는 한 벌만 도는 것이 맞다 — 메모리가 660MB 더 나간다." >&2
  echo "어느 쪽을 남길지 정하고 다른 쪽을 내린 뒤에 다시 돌려라:" >&2
  echo "  ${COMPOSE[*]} stop app-green" >&2
  exit 1
elif [ "$BLUE_UP" -eq 1 ]; then
  LIVE=app-blue;  NEXT=app-green
elif [ "$GREEN_UP" -eq 1 ]; then
  LIVE=app-green; NEXT=app-blue
else
  echo "둘 다 안 돌고 있다. 첫 기동이면 이 스크립트가 아니라 평소 방법으로 띄워라:" >&2
  echo "  ${COMPOSE[*]} up -d app-blue" >&2
  exit 1
fi

CONTAINER_NEXT="heattrip-$NEXT"
CONTAINER_LIVE="heattrip-$LIVE"

echo "호스트    $(hostname)"
echo "폴더      $(pwd)"
echo "지금      $LIVE$([ "$PROD" -eq 1 ] && echo '  (prod 오버라이드 켜짐)')"
echo "다음      $NEXT"
echo

if [ "$DRY_RUN" -eq 1 ]; then
  echo "--dry-run 이라 여기서 멈춘다. 할 일은 이것이다:"
  [ "$NO_BUILD" -eq 0 ] && echo "  1) ${COMPOSE[*]} build $NEXT"
  echo "  2) ${COMPOSE[*]} up -d --force-recreate --no-deps $NEXT"
  echo "  3) $CONTAINER_NEXT 가 healthy 가 될 때까지 기다린다 (최대 ${WAIT_SECONDS}초)"
  echo "  4) ${COMPOSE[*]} stop $LIVE"
  exit 0
fi

# ── 1) 새 이미지 ──────────────────────────────────────────────
if [ "$NO_BUILD" -eq 0 ]; then
  echo ">> 1/4  이미지를 만든다"
  "${COMPOSE[@]}" build "$NEXT" 2>&1 | tail -3 | sed 's/^/   /'
  BUILD_RC=${PIPESTATUS[0]}
  if [ "$BUILD_RC" -ne 0 ]; then
    echo "빌드가 실패했다($BUILD_RC). $LIVE 는 그대로 돌고 있다 — 서비스에 영향 없다." >&2
    exit 1
  fi
else
  echo ">> 1/4  --no-build 라 건너뛴다"
fi

# ── 2) 쉬는 쪽을 띄운다 ───────────────────────────────────────
echo ">> 2/4  $NEXT 를 띄운다"
"${COMPOSE[@]}" up -d --force-recreate --no-deps "$NEXT" 2>&1 | sed 's/^/   /'

# ── 3) healthy 가 될 때까지 ───────────────────────────────────
echo ">> 3/4  $NEXT 가 준비될 때까지 기다린다 (최대 ${WAIT_SECONDS}초)"
START=$(date +%s)
while :; do
  ST=$(health_of "$CONTAINER_NEXT")
  ELAPSED=$(( $(date +%s) - START ))
  if [ "$ST" = "healthy" ]; then
    echo "   ${ELAPSED}초 만에 healthy"
    break
  fi
  if [ "$ELAPSED" -ge "$WAIT_SECONDS" ]; then
    echo >&2
    echo "${WAIT_SECONDS}초 안에 healthy 가 안 됐다 (지금 상태: $ST)." >&2
    echo "**$LIVE 는 그대로 돌고 있다 — 서비스는 안 끊겼다.**" >&2
    echo "새 쪽 로그를 보고 원인을 찾은 뒤 다시 돌려라:" >&2
    echo "  ${COMPOSE[*]} logs $NEXT --tail 50" >&2
    echo "되돌리려면 새 쪽만 내린다:" >&2
    echo "  ${COMPOSE[*]} stop $NEXT" >&2
    exit 1
  fi
  printf '\r   %3d초  %s ' "$ELAPSED" "$ST"
  sleep 2
done

# ── 겹치는 순간의 메모리 ──────────────────────────────────────
echo
echo "-- 둘이 겹친 지금의 메모리 (여기가 가장 빠듯하다) --"
free -m | sed 's/^/   /'
docker stats --no-stream --format '   {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}' 2>/dev/null

# ── 4) 옛 쪽을 내린다 ────────────────────────────────────────
echo
echo ">> 4/4  $LIVE 를 내린다 — 여기서 앞단이 넘어간다"
"${COMPOSE[@]}" stop "$LIVE" 2>&1 | sed 's/^/   /'

# ── 확인 ─────────────────────────────────────────────────────
echo
echo "-- 앞단을 지나 들어가 본다 --"
for i in 1 2 3 4 5; do
  CODE=$(curl -s -o /dev/null -m 5 -w '%{http_code}' http://127.0.0.1:8080/actuator/health)
  echo "   $i회  HTTP $CODE"
  [ "$CODE" = "200" ] || sleep 2
done

echo
echo "-- 지금 컨테이너 --"
"${COMPOSE[@]}" ps --format '   {{.Service}}\t{{.Status}}'

echo
echo "되돌리려면 옛 쪽을 다시 띄우고 새 쪽을 내린다:"
echo "  ${COMPOSE[*]} up -d --no-deps $LIVE   # 옛 이미지가 그대로 남아 있다"
echo "  ${COMPOSE[*]} stop $NEXT"
