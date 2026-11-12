#!/usr/bin/env bash
#
# 신고를 보고 처리한다 — 이슈 #718.
#
# ## 어디서 돌리나
#
# **서버에서.** 운영자 경로(`/internal/**`)는 앱 컨테이너 안의 루프백 커넥터로만 열려 있다
# (`config/OperatorChannel`). 인터넷에서도, 서버의 다른 포트에서도 못 부른다. 이 스크립트가 지금
# 떠 있는 앱 컨테이너(`heattrip-app-blue` 또는 `heattrip-app-green`) 안으로 들어가 그 커넥터를 부른다.
#
#   sudo bash /opt/pawloop-backend/repo/backend/scripts/moderate.sh show 12
#
# 신고 알림(슬랙)에 찍힌 "신고 #12" 의 숫자가 그대로 인자다.
#
# ## 지금 되는 것
#
#   show <신고번호>   신고 한 건과 그 사본(신고 시점의 글·작성자·앞뒤 맥락)을 본다
#
# 삭제(resolve) · 정지(suspend) · 해제(lift) 는 다음 조각에서 더한다.
set -euo pipefail
umask 077

APPS=(heattrip-app-blue heattrip-app-green)

usage() {
  echo "쓰는 법: $0 show <신고번호>" >&2
  exit 2
}

# 지금 떠 있는 앱 컨테이너 하나. healthy 인 것을 먼저 고르고, 없으면 떠 있는 것.
# 배포 중이라 둘 다 떠 있으면 어느 쪽이든 된다 — 둘이 같은 DB 를 본다.
live_app() {
  local name fallback=""
  for name in "${APPS[@]}"; do
    case "$(docker inspect --format '{{.State.Running}}/{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$name" 2>/dev/null || true)" in
      true/healthy) echo "$name"; return 0 ;;
      true/*) fallback="${fallback:-$name}" ;;
    esac
  done
  if [ -n "$fallback" ]; then
    echo "$fallback"
    return 0
  fi
  echo "떠 있는 앱 컨테이너가 없습니다 (${APPS[*]})" >&2
  return 1
}

# call <메서드> <경로> [curl 인자…] — 컨테이너 안의 운영자 커넥터를 부른다.
# 포트는 컨테이너의 설정에서 읽는다(없으면 운영 기본값 9091).
call() {
  local method="$1" path="$2" app port
  shift 2
  app="$(live_app)"
  port="$(docker exec "$app" printenv APP_OPERATOR_PORT 2>/dev/null || true)"
  docker exec -i "$app" curl -sS --fail-with-body -X "$method" "$@" "http://127.0.0.1:${port:-9091}${path}"
}

pretty() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -m json.tool --no-ensure-ascii
  else
    cat
  fi
}

case "${1:-}" in
  show)
    [ -n "${2:-}" ] || usage
    [[ "$2" =~ ^[0-9]+$ ]] || { echo "신고 번호는 숫자입니다: $2" >&2; exit 2; }
    call GET "/internal/moderation/reports/$2" | pretty
    ;;
  resolve|suspend|lift)
    echo "'$1' 은 다음 조각에서 더합니다(#718)." >&2
    exit 2
    ;;
  *)
    usage
    ;;
esac
