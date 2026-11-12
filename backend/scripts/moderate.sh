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
#   show    <신고번호>                                   신고 한 건과 그 사본(신고 시점의 글·작성자·앞뒤 맥락)
#   resolve <신고번호> remove  --reason "<사유>" [--yes]   신고된 글·댓글을 지운다
#   resolve <신고번호> dismiss --reason "<사유>" [--yes]   살펴봤고 지울 것 없음으로 닫는다
#
# resolve 는 먼저 show 와 같은 화면을 띄우고 확인을 받는다(--yes 면 묻지 않는다). **지운 글은 되살릴 수
# 없다** — 작성자가 지울 때와 같은 길로 댓글·반응·저장·사진까지 함께 사라지고, 지우기 직전의 사본만
# 조치 기록(moderation_action)에 남는다. 누가 했는지는 서버에 들어간 계정 이름(sudo 앞의 사용자)으로
# 적힌다. 한 신고에 판단은 한 번이라, 이미 처리한 신고를 다시 처리하면 409 와 함께 먼저 내린 판단을 보여 준다.
#
# 채팅 메시지 신고는 아직 remove 로 처리할 수 없다(409) — 보낸 사람을 정지로 막는다(다음 조각).
# 정지(suspend) · 해제(lift) 는 다음 조각에서 더한다.
set -euo pipefail
umask 077

APPS=(heattrip-app-blue heattrip-app-green)

usage() {
  echo "쓰는 법:" >&2
  echo "  $0 show <신고번호>" >&2
  echo "  $0 resolve <신고번호> remove|dismiss --reason \"<사유>\" [--yes]" >&2
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
# 포트는 컨테이너의 설정에서 읽는다(없으면 운영 기본값 9091). 4xx·5xx 면 실패로 끝나되 서버가 적은
# 이유(본문)는 그대로 내보낸다.
call() {
  local method="$1" path="$2" app port
  shift 2
  app="$(live_app)"
  port="$(docker exec "$app" printenv APP_OPERATOR_PORT 2>/dev/null || true)"
  docker exec -i "$app" curl -sS --fail-with-body -X "$method" "$@" "http://127.0.0.1:${port:-9091}${path}"
}

# JSON 이면 보기 좋게, 아니면 받은 그대로.
pretty() {
  local body
  body="$(cat)"
  if command -v python3 >/dev/null 2>&1 \
      && printf '%s' "$body" | python3 -m json.tool --no-ensure-ascii 2>/dev/null; then
    return 0
  fi
  printf '%s\n' "$body"
}

report_id() {
  [[ "${1:-}" =~ ^[0-9]+$ ]] || { echo "신고 번호는 숫자입니다: ${1:-(없음)}" >&2; exit 2; }
}

resolve() {
  local id="${1:-}" decision="${2:-}" reason="" yes=0
  report_id "$id"
  case "$decision" in
    remove|dismiss) ;;
    *) echo "처리는 remove 또는 dismiss 입니다: ${decision:-(없음)}" >&2; exit 2 ;;
  esac
  shift 2
  while [ $# -gt 0 ]; do
    case "$1" in
      --reason) [ $# -ge 2 ] || usage; reason="$2"; shift 2 ;;
      --yes) yes=1; shift ;;
      *) echo "모르는 인자입니다: $1" >&2; usage ;;
    esac
  done
  [ -n "${reason//[[:space:]]/}" ] || { echo "--reason 으로 사유를 적어 주세요 — 조치 기록에 남습니다." >&2; exit 2; }

  local actor="${SUDO_USER:-${USER:-}}"
  [ -n "$actor" ] || actor="$(id -un)"

  # 무엇을 처리하는지 먼저 본다. 없는 신고면 여기서 404 로 끝난다.
  call GET "/internal/moderation/reports/$id" | pretty
  echo

  if [ "$yes" -ne 1 ]; then
    local what answer=""
    if [ "$decision" = remove ]; then
      what="위 신고 대상(글·댓글)을 지웁니다. 되살릴 수 없습니다"
    else
      what="지울 것 없음으로 닫습니다"
    fi
    printf '신고 #%s — %s.\n사유: %s\n기록될 이름: %s\n계속할까요? [y/N] ' "$id" "$what" "$reason" "$actor" >&2
    # 터미널이 없으면(파이프·cron) 묻지 못하므로 그만둔다 — 기본값이 "아니오" 다.
    read -r answer </dev/tty || true
    case "$answer" in
      y|Y|yes|YES) ;;
      *) echo "그만둡니다 — 아무것도 바뀌지 않았습니다." >&2; exit 1 ;;
    esac
  fi

  local out status=0
  out="$(call POST "/internal/moderation/reports/$id/resolve" \
    --data-urlencode "decision=$decision" \
    --data-urlencode "reason=$reason" \
    --data-urlencode "actor=$actor")" || status=$?
  printf '%s\n' "$out" | pretty
  [ "$status" -eq 0 ] || exit "$status"

  # 대상이 전부 이미 없었으면(다른 신고로 먼저 지웠다) 기록이 안 남아 이 신고는 열려 있다.
  if [ "$decision" = remove ] && printf '%s' "$out" | grep -Eq '"removed"[[:space:]]*:[[:space:]]*\[[[:space:]]*\]'; then
    echo "지울 것이 이미 없었습니다 — 이 신고는 아직 열려 있습니다. 닫으려면:" >&2
    echo "  $0 resolve $id dismiss --reason \"이미 지워진 글\"" >&2
  fi
}

case "${1:-}" in
  show)
    report_id "${2:-}"
    call GET "/internal/moderation/reports/$2" | pretty
    ;;
  resolve)
    shift
    [ $# -ge 2 ] || usage
    resolve "$@"
    ;;
  suspend|lift)
    echo "'$1' 은 다음 조각에서 더합니다(#718)." >&2
    exit 2
    ;;
  *)
    usage
    ;;
esac
