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
#   show    <신고번호>                                     신고 한 건과 그 사본(신고 시점의 글·작성자·앞뒤 맥락)
#   resolve <신고번호> remove  --reason "<사유>" [--yes]     신고된 글·댓글을 지운다
#   resolve <신고번호> dismiss --reason "<사유>" [--yes]     살펴봤고 지울 것 없음으로 닫는다
#   user    <사용자번호>                                    한 사람의 지금 상태(정지 중인가)와 받은 조치
#   suspend <신고번호> [--days N] --reason "<사유>" [--yes]  그 신고의 대상을 정지한다(기간을 비우면 무기한)
#   suspend --user <사용자번호> [--days N] --reason "<사유>" [--yes]
#                                                          신고 없이 정지한다
#   lift    <사용자번호> --reason "<사유>" [--yes]           정지를 푼다
#
# 바꾸는 명령(resolve·suspend·lift)은 무엇을 바꾸는지 먼저 보여 주고 확인을 받는다(--yes 면 묻지 않는다).
# 터미널이 없고 --yes 도 없으면 아무것도 보내지 않는다. 누가 했는지는 서버에 들어간 계정 이름(sudo 앞의
# 사용자)으로 적힌다.
#
# - **지운 글은 되살릴 수 없다** — 작성자가 지울 때와 같은 길로 댓글·반응·저장·사진까지 함께 사라지고,
#   지우기 직전의 사본만 조치 기록(moderation_action)에 남는다. 한 신고에 판단은 한 번이다(다시 하면 409).
# - **정지된 사람은 계정 삭제와 로그아웃만 할 수 있다.** 정지하는 순간 그 사람의 로그인 연장(refresh
#   토큰)이 전부 끊기고 푸시도 멈춘다. 신고 번호로 정지하면 그 신고의 대상이 정지된다. 기간을 바꾸려면
#   lift 한 뒤 다시 suspend 한다(정지 중에 다시 정지하면 409).
# - 채팅 메시지 신고는 아직 remove 로 처리할 수 없다(409) — 보낸 사람을 정지로 막는다.
set -euo pipefail
umask 077

APPS=(heattrip-app-blue heattrip-app-green)

# 옵션 — parse_options 가 채운다.
REASON="" DAYS="" USER_ID="" YES=0

usage() {
  echo "쓰는 법:" >&2
  echo "  $0 show <신고번호>" >&2
  echo "  $0 resolve <신고번호> remove|dismiss --reason \"<사유>\" [--yes]" >&2
  echo "  $0 user <사용자번호>" >&2
  echo "  $0 suspend <신고번호> [--days N] --reason \"<사유>\" [--yes]" >&2
  echo "  $0 suspend --user <사용자번호> [--days N] --reason \"<사유>\" [--yes]" >&2
  echo "  $0 lift <사용자번호> --reason \"<사유>\" [--yes]" >&2
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

# number <값> <이름> — 양의 정수가 아니면 끝낸다.
number() {
  [[ "${1:-}" =~ ^[0-9]+$ ]] || { echo "$2 — 숫자여야 합니다: ${1:-(없음)}" >&2; exit 2; }
}

# 위치 인자 뒤의 옵션을 읽는다. 그 명령에 없는 옵션은 각 명령이 거절한다.
parse_options() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --reason) [ $# -ge 2 ] || usage; REASON="$2"; shift 2 ;;
      --days) [ $# -ge 2 ] || usage; DAYS="$2"; shift 2 ;;
      --user) [ $# -ge 2 ] || usage; USER_ID="$2"; shift 2 ;;
      --yes) YES=1; shift ;;
      *) echo "모르는 인자입니다: $1" >&2; usage ;;
    esac
  done
}

require_reason() {
  [ -n "${REASON//[[:space:]]/}" ] || { echo "--reason 으로 사유를 적어 주세요 — 조치 기록에 남습니다." >&2; exit 2; }
}

actor() {
  local who="${SUDO_USER:-${USER:-}}"
  [ -n "$who" ] || who="$(id -un)"
  echo "$who"
}

# confirm <줄…> — 무엇을 하는지 보여 주고 y 를 받아야 지나간다. --yes 면 묻지 않는다.
# 터미널이 없으면(파이프·cron) 묻지 못하므로 그만둔다 — 기본값이 "아니오" 다.
confirm() {
  local line answer=""
  [ "$YES" -eq 1 ] && return 0
  for line in "$@"; do
    printf '%s\n' "$line" >&2
  done
  printf '계속할까요? [y/N] ' >&2
  read -r answer </dev/tty || true
  case "$answer" in
    y|Y|yes|YES) ;;
    *) echo "그만둡니다 — 아무것도 바뀌지 않았습니다." >&2; exit 1 ;;
  esac
}

# post_form <경로> [이름=값…] — 폼으로 보내고 결과를 보여 준다. 실패면 서버가 적은 이유를 보여 주고 그 코드로
# 끝난다. 받은 본문은 LAST_OUT 에 남긴다.
LAST_OUT=""
post_form() {
  local path="$1" out status=0 pair
  local args=()
  shift
  for pair in "$@"; do
    args+=(--data-urlencode "$pair")
  done
  out="$(call POST "$path" "${args[@]}")" || status=$?
  printf '%s\n' "$out" | pretty
  [ "$status" -eq 0 ] || exit "$status"
  LAST_OUT="$out"
}

resolve() {
  local id="${1:-}" decision="${2:-}"
  number "$id" "신고 번호"
  case "$decision" in
    remove|dismiss) ;;
    *) echo "처리는 remove 또는 dismiss 입니다: ${decision:-(없음)}" >&2; exit 2 ;;
  esac
  shift 2
  parse_options "$@"
  [ -z "$DAYS$USER_ID" ] || { echo "resolve 에는 --days·--user 가 없습니다." >&2; exit 2; }
  require_reason

  # 무엇을 처리하는지 먼저 본다. 없는 신고면 여기서 404 로 끝난다.
  call GET "/internal/moderation/reports/$id" | pretty
  echo
  if [ "$decision" = remove ]; then
    confirm "신고 #$id — 위 신고 대상(글·댓글)을 지웁니다. 되살릴 수 없습니다." "사유: $REASON" "기록될 이름: $(actor)"
  else
    confirm "신고 #$id — 지울 것 없음으로 닫습니다." "사유: $REASON" "기록될 이름: $(actor)"
  fi

  post_form "/internal/moderation/reports/$id/resolve" "decision=$decision" "reason=$REASON" "actor=$(actor)"

  # 대상이 전부 이미 없었으면(다른 신고로 먼저 지웠다) 기록이 안 남아 이 신고는 열려 있다.
  if [ "$decision" = remove ] && printf '%s' "$LAST_OUT" | grep -Eq '"removed"[[:space:]]*:[[:space:]]*\[[[:space:]]*\]'; then
    echo "지울 것이 이미 없었습니다 — 이 신고는 아직 열려 있습니다. 닫으려면:" >&2
    echo "  $0 resolve $id dismiss --reason \"이미 지워진 글\"" >&2
  fi
}

suspend_user() {
  local report="" case_json length
  if [ $# -gt 0 ] && [[ "$1" != --* ]]; then
    report="$1"
    shift
  fi
  parse_options "$@"
  require_reason
  if [ -n "$report" ]; then
    number "$report" "신고 번호"
    [ -z "$USER_ID" ] || { echo "신고 번호와 --user 는 함께 쓰지 않습니다 — 신고 번호를 주면 그 신고의 대상을 정지합니다." >&2; exit 2; }
    case_json="$(call GET "/internal/moderation/reports/$report")" || { printf '%s\n' "$case_json" | pretty; exit 1; }
    printf '%s\n' "$case_json" | pretty
    USER_ID="$(printf '%s' "$case_json" | sed -n 's/.*"reportedUserId"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p')"
    [ -n "$USER_ID" ] || { echo "신고 #$report 에는 대상 사용자가 없습니다(비어 있거나 탈퇴했습니다)." >&2; exit 1; }
  fi
  [ -n "$USER_ID" ] || usage
  number "$USER_ID" "사용자 번호"
  if [ -n "$DAYS" ]; then
    number "$DAYS" "기간(일)"
    length="${DAYS}일"
  else
    length="무기한"
  fi

  echo
  echo "사용자 #$USER_ID 의 지금 상태:"
  call GET "/internal/moderation/users/$USER_ID" | pretty
  echo
  confirm "사용자 #$USER_ID 를 $length 정지합니다. 로그인 연장이 전부 끊기고, 계정 삭제·로그아웃만 할 수 있게 됩니다." \
    "사유: $REASON" "기록될 이름: $(actor)"

  local fields=("reason=$REASON" "actor=$(actor)")
  [ -z "$report" ] || fields+=("reportId=$report")
  [ -z "$DAYS" ] || fields+=("days=$DAYS")
  post_form "/internal/moderation/users/$USER_ID/suspend" "${fields[@]}"
}

lift_user() {
  local id="${1:-}"
  number "$id" "사용자 번호"
  shift
  parse_options "$@"
  [ -z "$DAYS$USER_ID" ] || { echo "lift 에는 --days·--user 가 없습니다." >&2; exit 2; }
  require_reason

  echo "사용자 #$id 의 지금 상태:"
  call GET "/internal/moderation/users/$id" | pretty
  echo
  confirm "사용자 #$id 의 정지를 풉니다." "사유: $REASON" "기록될 이름: $(actor)"
  post_form "/internal/moderation/users/$id/lift" "reason=$REASON" "actor=$(actor)"
}

case "${1:-}" in
  show)
    number "${2:-}" "신고 번호"
    call GET "/internal/moderation/reports/$2" | pretty
    ;;
  resolve)
    shift
    [ $# -ge 2 ] || usage
    resolve "$@"
    ;;
  user)
    number "${2:-}" "사용자 번호"
    call GET "/internal/moderation/users/$2" | pretty
    ;;
  suspend)
    shift
    [ $# -ge 1 ] || usage
    suspend_user "$@"
    ;;
  lift)
    shift
    [ $# -ge 1 ] || usage
    lift_user "$@"
    ;;
  *)
    usage
    ;;
esac
