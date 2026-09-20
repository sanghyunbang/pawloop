#!/usr/bin/env bash
#
# 코드가 읽는 설정 키 · `.env.example` · 운영 SSM — 셋이 서로 맞는지 이름으로 대조한다. 이슈 #747.
#
# ## 왜 있나
#
# 환경마다 `.env` 가 따로다 — 맥, 윈도우, 운영(SSM). **값은 달라야 정상**이지만(로컬은
# 로컬 DB, 운영은 운영 DB) **키 이름의 목록은 맞아야 한다.** 그런데 그것을 재는 자리가
# 없었다. 2026-09-20 에 실제로 겪은 것 셋:
#
#   - 운영 SSM 에 같은 키가 두 줄이라 뒤엣것(false)이 이겨 레이트리밋이 꺼진 채 돌았다
#   - `SLACK_REPORT_WEBHOOK_URL` 을 코드(#715)는 읽는데 운영에는 없어 알림이 조용히 안 갔다
#   - 윈도우에서 외부 API 키(ORS)를 받아 로컬 `.env` 에만 넣고 있었다 — 그 코드가 올라오면
#     `.env.example` 과 운영에 그 이름이 있어야 하는데, 그걸 알려 줄 것이 없었다
#
# 이 스크립트는 그 셋을 이름으로 찍는다. **값은 한 글자도 안 찍는다** — 출력을 그대로
# 이슈에 붙여도 된다.
#
# ## 무엇을 재나
#
#   A  기본값 없이 요구하는데 `.env.example` 에 없는 키  → 실패. 새 필수 키를 문서에 안 적은 것
#   A2 기본값이 있어 안 적어도 뜨지만 `.env.example` 에 없는 키 → 참고. 조정값이 대부분
#   B  기본값 없이 요구하는데 운영 SSM 에 없거나 빈 키    → 실패. 재기동하면 서버가 안 뜬다
#   C  운영 SSM 에 같은 키가 두 줄                       → 실패. 뒤엣것이 이긴다
#   D  코드는 읽는데 운영에 없는 키 (기본값으로 도는 것)   → 참고. 켜야 할 기능이면 여기 있다
#   E  운영에 있는데 코드·compose·Caddy 아무도 안 읽는 키  → 참고. 죽은 줄
#   F  `.env.example` 에 있는데 아무도 안 읽는 키          → 참고
#
# "코드가 읽는 키" 는 `application.properties` + `application-prod.properties` 의 `${KEY…}` 다
# — 운영이 그 둘로 뜬다. compose(`${KEY…}`)와 Caddyfile(`{$KEY}`)이 읽는 것도 "읽는 쪽" 으로 친다.
#
# ## 쓰는 법
#
#   bash backend/scripts/check-prod-env.sh          # 전부. AWS CLI 와 SSM 읽기 권한이 있어야 한다
#   bash backend/scripts/check-prod-env.sh local    # A·F 만. AWS 없이 — 윈도우에서도, PR 올리기 전에
#
# 나가는 값: A·B·C 중 하나라도 있으면 1.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WHAT="${1:-all}"
PARAM="${PARAM:-/pawloop/prod/backend/env}"
REGION="${REGION:-ap-northeast-2}"
RES="$ROOT/backend/src/main/resources"
B="$ROOT/backend"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
chmod 700 "$T"

KEY='[A-Z_][A-Z0-9_]*'

# 코드가 읽는 키 — 스프링 properties 의 ${KEY} / ${KEY:default}
# 주석 줄은 뺀다 — 주석에 적힌 ${LOG_LEVEL_...} 같은 예시가 키로 잡힌다
grep -hvE '^[[:space:]]*#' "$RES/application.properties" "$RES/application-prod.properties" > "$T/props"
grep -oE "\\\$\\{${KEY}" "$T/props" | sed 's/^\${//' | sort -u > "$T/code"
# 그중 기본값이 없는 것 — ${KEY} 꼴 그대로
grep -oE "\\\$\\{${KEY}\\}" "$T/props" | sed 's/^\${//; s/}$//' | sort -u > "$T/required"
# compose 와 Caddy 가 읽는 키
{ grep -ohE "\\\$\\{${KEY}" "$B"/docker-compose*.yml 2>/dev/null | sed 's/^\${//'
  grep -ohE "\\{\\\$${KEY}\\}" "$B/Caddyfile" 2>/dev/null | sed 's/^{\$//; s/}$//'
} | sort -u > "$T/infra"
sort -u "$T/code" "$T/infra" > "$T/readers"
# .env.example — 주석으로 막아 둔 줄(# KEY=)도 "적혀 있다" 로 친다
grep -oE "^#? *${KEY}=" "$B/.env.example" | sed 's/^#* *//; s/=$//' | sort -u > "$T/example"

FAIL=0
say_list() {  # 제목, 파일. 비면 아무것도 안 찍는다
  [ -s "$2" ] || return 0
  echo "$1"
  sed 's/^/     /' "$2"
  echo
}

# "코드가 읽는 키" 는 **이 작업 트리의** properties 다. 로컬이 origin/main 보다 뒤면 최근 PR 이
# 더한 키가 여기 없어서 E("죽은 줄")에 잘못 잡힌다 — 2026-09-20 에 #715 의
# SLACK_REPORT_WEBHOOK_URL 이 그랬다. 그래서 어느 커밋을 읽는지, 뒤처졌는지 먼저 말한다.
HEAD_SHORT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo '?')"
BEHIND="$(git -C "$ROOT" rev-list --count HEAD..origin/main 2>/dev/null || echo '?')"
echo "기준 커밋 $HEAD_SHORT (origin/main 보다 ${BEHIND}커밋 뒤 — 0 이 아니면 git pull 뒤 다시 재라)"
echo "코드가 읽는 키 $(wc -l < "$T/code" | tr -d ' ')개 · 그중 기본값 없는 것 $(wc -l < "$T/required" | tr -d ' ')개 · .env.example $(wc -l < "$T/example" | tr -d ' ')개"
echo

# A 는 기본값 없이 요구하는 키만 실패로 센다. 기본값이 있는 조정값(타임아웃·한도·크론)은
# .env.example 에 없어도 서버가 뜨므로 A2 로 참고만 한다 — 처음 판은 47개를 다 실패로 세서
# 진짜 빠진 것이 묻혔다. 실패하는 검사는 며칠 안에 무시당한다.
comm -23 "$T/required" "$T/example" > "$T/A"
if [ -s "$T/A" ]; then FAIL=1; fi
say_list "A  기본값 없이 요구하는데 .env.example 에 없다 — 새 필수 키를 문서에 안 적었다:" "$T/A"
comm -23 "$T/code" "$T/example" | comm -23 - "$T/A" > "$T/A2"
say_list "A2 (참고) 기본값이 있어 안 적어도 뜨지만 .env.example 에 없다 ($(wc -l < "$T/A2" | tr -d ' ')개):" "$T/A2"

comm -23 "$T/example" "$T/readers" > "$T/F"
say_list "F  (참고) .env.example 에 있는데 아무도 안 읽는다:" "$T/F"

if [ "$WHAT" = "local" ]; then
  [ "$FAIL" -eq 0 ] && echo "local: A 없음" || echo "local: 실패"
  exit "$FAIL"
fi

# ── 운영 SSM ──────────────────────────────────────────────────────────
if ! aws ssm get-parameter --name "$PARAM" --with-decryption \
     --query "Parameter.Value" --output text --region "$REGION" > "$T/ssm" 2>"$T/ssm.err"; then
  echo "운영 SSM 을 못 읽었다 ($PARAM):" >&2
  sed 's/^/     /' "$T/ssm.err" >&2
  echo "AWS 자격이 없으면 'local' 인자로 A·F 만 재라." >&2
  exit 2
fi
chmod 600 "$T/ssm"

grep -oE "^${KEY}=" "$T/ssm" | sed 's/=$//' | sort > "$T/ssm.all"
sort -u "$T/ssm.all" > "$T/ssm.keys"
uniq -d "$T/ssm.all" > "$T/C"
# 있지만 값이 빈 키
grep -E "^${KEY}=[[:space:]]*$" "$T/ssm" | sed 's/=.*//' | sort -u > "$T/ssm.empty"
comm -23 "$T/ssm.keys" "$T/ssm.empty" > "$T/ssm.filled"

VERSION="$(aws ssm get-parameter --name "$PARAM" --query "Parameter.Version" --output text --region "$REGION" 2>/dev/null || echo '?')"
echo "운영 SSM 버전 $VERSION · 키 $(wc -l < "$T/ssm.all" | tr -d ' ')줄 (고유 $(wc -l < "$T/ssm.keys" | tr -d ' ')개 · 빈 값 $(wc -l < "$T/ssm.empty" | tr -d ' ')개)"
echo

comm -23 "$T/required" "$T/ssm.filled" > "$T/B"
if [ -s "$T/B" ]; then FAIL=1; fi
say_list "B  기본값 없이 요구하는데 운영에 없거나 비어 있다 — 재기동하면 서버가 안 뜬다:" "$T/B"

if [ -s "$T/C" ]; then FAIL=1; fi
say_list "C  운영에 같은 키가 두 줄 — 뒤엣것이 이긴다:" "$T/C"

comm -23 "$T/code" "$T/ssm.filled" | comm -23 - "$T/B" > "$T/D"
say_list "D  (참고) 코드는 읽는데 운영에 없거나 비어 기본값으로 돈다:" "$T/D"

comm -23 "$T/ssm.keys" "$T/readers" > "$T/E"
say_list "E  (참고) 운영에 있는데 코드·compose·Caddy 아무도 안 읽는다 — 죽은 줄:" "$T/E"

if [ "$FAIL" -eq 0 ]; then
  echo "A·B·C 없음 — 키 목록이 맞는다."
else
  echo "실패 — 위의 A·B·C 를 고쳐라. 운영 값은 backend/scripts/set-prod-env.sh 로 넣는다."
fi
exit "$FAIL"
