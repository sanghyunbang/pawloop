#!/usr/bin/env bash
#
# 운영 설정(SSM 파라미터)의 키를 고친다 — 이슈 #747.
#
# ## 왜 이 스크립트가 필요한가
#
# **운영의 `.env` 정본은 SSM 파라미터 하나다**(`/pawloop/prod/backend/env`). 맥이나
# 윈도우의 `backend/.env` 는 로컬 개발용이고 운영과 아무 관계가 없다 — 그걸 고치고
# 운영이 바뀐 줄 알기 쉬운 구조라, 2026-09-20 에 실제로 그 혼란을 겪었다.
#
# 그러면 SSM 을 고쳐야 하는데, 손으로 하면 두 가지로 넘어진다.
#
#   aws ssm put-parameter --value "$(...)"     ← 셸이 값 안의 특수문자를 먹는다
#   콘솔의 텍스트 상자에서 직접 편집          ← 비밀이 잔뜩 든 2.5KB 에서 두 줄 찾기
#
# 어느 쪽이든 **다른 줄을 조용히 날려도 아무도 모른다.** 키가 하나 빠진 채 재시작하면
# `prod` 프로필은 기본값이 없어서 서버가 아예 안 뜬다. 그래서 고치는 길을 하나로 두고,
# 넘어지는 자리마다 멈추게 한다.
#
# 같은 키가 두 줄이면 **뒤엣것이 이긴다.** 앞줄만 보고 켜져 있다고 믿게 되는 자리다 —
# 2026-09-20 에 `APP_SECURITY_RATE_LIMIT_ENABLED` 가 `true`(30줄)·`false`(49줄)로 있었고
# 운영은 `false` 로, 즉 레이트리밋이 꺼진 채 돌고 있었다(#747). 그래서 이 스크립트는
# 중복을 먼저 말하고, 그 키를 이번에 건드리면 한 줄로 합치고, 안 건드리면 선다.
#
# ## 쓰는 법 (맥에서. 서버에 들어갈 필요 없다)
#
#     # 먼저 --dry-run 으로 무엇이 바뀌는지 본다. 아무것도 저장하지 않는다.
#     bash backend/scripts/set-prod-env.sh --dry-run SPRING_PROFILES_ACTIVE=prod
#
#     # 확인했으면 그대로 다시. 여러 개를 한 번에 줄 수 있다.
#     bash backend/scripts/set-prod-env.sh \
#       SPRING_PROFILES_ACTIVE=prod \
#       SPRING_JPA_HIBERNATE_DDL_AUTO=validate
#
# 없는 키를 주면 **더한다.** 있는 키를 주면 **값을 바꾼다.** 같은 키가 이미 두 줄이면 한 줄로
# 합친다. 줄을 아예 없애려면 `--remove KEY` 다.
#
#     bash backend/scripts/set-prod-env.sh --remove SPRING_DATASOURCE_URL
#
# ## 이걸 돌려도 운영은 아직 안 바뀐다
#
# SSM 은 **다음 재기동 때** 서버로 내려간다. 바로 먹이려면 서버에서:
#
#     ssh -i ~/.ssh/pawloop-staging.pem ec2-user@<운영 IP>
#     sudo bash /opt/pawloop-backend/repo/backend/scripts/refresh-prod-env.sh
#
# `refresh-prod-env.sh` 를 쓰는 이유는 그 파일 머리말에 있다 — 손으로 `.env` 를 덮으면
# Caddy 가 도메인을 못 읽고 죽고, 그러면 API 도 같이 죽는다. 키를 지웠으면 그쪽에
# `EXPECT_KEYS=<개수>` 를 붙인다 — 안 그러면 "키가 줄었다" 며 선다.
#
# ## 되돌리기
#
# SSM 은 버전이 남는다. 이 스크립트가 끝나면서 이전 버전 번호를 알려 준다.
#
#     aws ssm get-parameter --name /pawloop/prod/backend/env:<이전버전> \
#       --with-decryption --query Parameter.Value --output text --region ap-northeast-2
#
# 비밀값은 화면에 찍지 않는다. 키 이름과 개수만 말한다.
#
# 맥의 기본 bash 는 3.2 라 빈 배열을 `"${arr[@]}"` 로 펼치면 `set -u` 에 걸린다. 그래서
# 배열은 전부 `${arr[@]+"${arr[@]}"}` 로 펼친다.
set -euo pipefail
umask 077

PARAM="${PARAM:-/pawloop/prod/backend/env}"
REGION="${REGION:-ap-northeast-2}"
MAX_BYTES="${MAX_BYTES:-4096}"   # SSM Standard 파라미터의 한도

usage() { echo "쓰는 법: bash $0 [--dry-run] [--remove KEY] KEY=VALUE [KEY=VALUE ...]" >&2; }

DRY_RUN=0
PAIRS=()
REMOVES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --remove)
      [ $# -ge 2 ] || { echo "--remove 뒤에 키 이름이 없다." >&2; usage; exit 2; }
      REMOVES+=("$2"); shift 2 ;;
    *=*)       PAIRS+=("$1"); shift ;;
    *)         echo "모르는 인자: $1" >&2; usage; exit 2 ;;
  esac
done

if [ "${#PAIRS[@]}" -eq 0 ] && [ "${#REMOVES[@]}" -eq 0 ]; then
  echo "고칠 키를 하나도 안 줬다." >&2; usage; exit 2
fi

valid_key() { printf '%s' "$1" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$'; }
for k in ${REMOVES[@]+"${REMOVES[@]}"}; do
  valid_key "$k" || { echo "키 이름이 이상하다: $k" >&2; exit 2; }
done
for p in ${PAIRS[@]+"${PAIRS[@]}"}; do
  valid_key "${p%%=*}" || { echo "키 이름이 이상하다: ${p%%=*}" >&2; exit 2; }
  # sed 구분자로 | 를 쓴다. 값에 | 가 있으면 다른 글자로 바꿔야 하므로 여기서 막는다.
  if printf '%s' "${p#*=}" | grep -q '|'; then
    echo "값에 | 가 들어 있다 (${p%%=*}). 이 스크립트가 못 다룬다 — 콘솔에서 고쳐라." >&2; exit 1
  fi
done

BEFORE="$(mktemp)"; AFTER="$(mktemp)"
trap 'rm -f "$BEFORE" "$AFTER" "$AFTER.tmp" "$AFTER.bak"' EXIT
chmod 600 "$BEFORE" "$AFTER"

OLD_VERSION="$(aws ssm get-parameter --name "$PARAM" --with-decryption \
  --query "Parameter.Version" --output text --region "$REGION")"
aws ssm get-parameter --name "$PARAM" --with-decryption \
  --query "Parameter.Value" --output text --region "$REGION" > "$BEFORE"

# 마지막 줄에 줄바꿈이 없으면 덧붙인 줄이 그 값에 달라붙는다 (#600 과 같은 자리).
if [ -n "$(tail -c1 "$BEFORE")" ]; then echo >> "$BEFORE"; fi

cp "$BEFORE" "$AFTER"

BEFORE_KEYS=$(grep -cE '^[A-Za-z_][A-Za-z0-9_]*=' "$BEFORE" || true)
echo "파라미터: $PARAM (버전 $OLD_VERSION · 키 ${BEFORE_KEYS}줄)"

# ── 중복 키 ────────────────────────────────────────────────────────────
touched() {  # 이번 호출에서 지우거나 세팅하는 키인가
  local k="$1" x
  for x in ${REMOVES[@]+"${REMOVES[@]}"}; do [ "$x" = "$k" ] && return 0; done
  for x in ${PAIRS[@]+"${PAIRS[@]}"}; do [ "${x%%=*}" = "$k" ] && return 0; done
  return 1
}
DUPES="$(grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' "$BEFORE" | tr -d '=' | sort | uniq -d || true)"
UNTOUCHED_DUPES=""
for d in $DUPES; do
  echo
  echo "  같은 키가 두 번 이상 있다 — 뒤엣것이 이긴다: $d"
  grep -nE "^$d=" "$BEFORE" | sed 's/^/     /'
  if touched "$d"; then
    echo "     → 이번에 이 키를 건드리니 한 줄로 합친다"
  else
    UNTOUCHED_DUPES="$UNTOUCHED_DUPES $d"
  fi
done
if [ -n "$UNTOUCHED_DUPES" ]; then
  echo
  echo "** 건드리지 않는 키에 중복이 있다:$UNTOUCHED_DUPES **" >&2
  echo "   어느 값이 맞는지 정한 뒤 KEY=VALUE 로 함께 주면 한 줄로 합쳐진다. 저장하지 않았다." >&2
  exit 1
fi
echo

# ── 고치기 ────────────────────────────────────────────────────────────
count_lines() { grep -cE "^$1=" "$AFTER" || true; }
# 그 키의 줄을 전부 지운다. grep -v 는 남는 줄이 없으면 1 을 돌려주므로 || true.
drop_key() { grep -vE "^$1=" "$AFTER" > "$AFTER.tmp" || true; mv "$AFTER.tmp" "$AFTER"; }

TOUCHED=()

for key in ${REMOVES[@]+"${REMOVES[@]}"}; do
  n=$(count_lines "$key")
  if [ "$n" -eq 0 ]; then
    echo "  $key — 없다. 지울 것이 없다"
    continue
  fi
  drop_key "$key"
  echo "  $key — ${n}줄 지운다"
  TOUCHED+=("$key")
done

for pair in ${PAIRS[@]+"${PAIRS[@]}"}; do
  key="${pair%%=*}"
  val="${pair#*=}"
  n=$(count_lines "$key")
  if [ "$n" -eq 1 ]; then
    old="$(grep -m1 "^$key=" "$AFTER" | cut -d= -f2-)"
    if [ "$old" = "$val" ]; then
      echo "  $key — 이미 그 값이다. 건너뛴다"
      continue
    fi
    sed -i.bak "s|^$key=.*|$key=$val|" "$AFTER" && rm -f "$AFTER.bak"
    echo "  $key — 값을 바꾼다 (이전 값은 안 찍는다)"
  elif [ "$n" -gt 1 ]; then
    drop_key "$key"
    printf '%s=%s\n' "$key" "$val" >> "$AFTER"
    echo "  $key — ${n}줄을 지우고 한 줄로 다시 쓴다"
  else
    printf '%s=%s\n' "$key" "$val" >> "$AFTER"
    echo "  $key — 새로 더한다"
  fi
  TOUCHED+=("$key")
done

AFTER_KEYS=$(grep -cE '^[A-Za-z_][A-Za-z0-9_]*=' "$AFTER" || true)
CHANGED=$(diff <(sort "$BEFORE") <(sort "$AFTER") | grep -cE '^[<>]' || true)
BYTES_AFTER=$(wc -c < "$AFTER" | tr -d ' ')

echo
echo "키 $BEFORE_KEYS → ${AFTER_KEYS}줄 · 바뀐 줄 $CHANGED · $BYTES_AFTER 바이트"

# ── 안전장치 ───────────────────────────────────────────────────────────
# 하나라도 걸리면 저장하지 않는다. 운영 설정은 되돌리기가 재기동이라 비싸다.

# 실제로 달라진 키의 집합이 내가 건드린 키의 집합과 정확히 같아야 한다. 값 안의 개행이나
# 특수문자가 다른 줄을 먹으면 여기서 드러난다. 줄 수를 세는 것보다 이게 정확하다 —
# 중복을 합칠 때는 새 값이 옛 값 중 하나와 같은지에 따라 줄 수가 달라진다.
CHANGED_KEYS="$(diff <(sort "$BEFORE") <(sort "$AFTER") | grep -E '^[<>] ' | sed -E 's/^[<>] //' \
  | grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' | tr -d '=' | sort -u || true)"
TOUCHED_KEYS="$(printf '%s\n' ${TOUCHED[@]+"${TOUCHED[@]}"} | sed '/^$/d' | sort -u)"
if [ "$CHANGED_KEYS" != "$TOUCHED_KEYS" ]; then
  echo "내가 건드린 키 말고 다른 키가 바뀌었다." >&2
  echo "  건드린 키: $(printf '%s' "$TOUCHED_KEYS" | tr '\n' ' ')" >&2
  echo "  바뀐 키:   $(printf '%s' "$CHANGED_KEYS" | tr '\n' ' ')" >&2
  echo "값 안에 개행이나 특수문자가 있을 수 있다. 저장하지 않았다." >&2
  exit 1
fi

if [ "$BYTES_AFTER" -ge "$MAX_BYTES" ]; then
  echo "$BYTES_AFTER 바이트다. SSM Standard 한도($MAX_BYTES)를 넘어 저장이 거부된다." >&2
  echo "저장하지 않았다. Advanced 계층으로 올리거나 값을 줄여라." >&2
  exit 1
fi

if [ "$CHANGED" -eq 0 ]; then
  echo "바뀐 것이 없다. 저장하지 않는다."
  exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo
  echo "--dry-run 이라 여기서 멈춘다. 아무것도 저장하지 않았다."
  echo "이 그대로 저장하려면 --dry-run 만 빼고 다시 돌려라."
  exit 0
fi

# ── 저장 ──────────────────────────────────────────────────────────────
NEW_VERSION="$(aws ssm put-parameter --name "$PARAM" --type SecureString \
  --value "file://$AFTER" --region "$REGION" --overwrite \
  --query Version --output text)"

echo
echo "저장했다. 버전 $OLD_VERSION → $NEW_VERSION"

# 정말 들어갔는지 다시 읽어 확인한다. 저장 성공 응답만 믿지 않는다.
echo "다시 읽어서 확인:"
VERIFY="$(aws ssm get-parameter --name "$PARAM" --with-decryption \
  --query "Parameter.Value" --output text --region "$REGION")"
fail=0
for pair in ${PAIRS[@]+"${PAIRS[@]}"}; do
  key="${pair%%=*}"
  n=$(printf '%s\n' "$VERIFY" | grep -cE "^$key=" || true)
  if [ "$n" -eq 1 ] && printf '%s\n' "$VERIFY" | grep -q "^$(printf '%s' "$pair" | sed 's/[][\.*^$/]/\\&/g')$"; then
    echo "  $key — 들어갔다 (한 줄)"
  else
    echo "  $key — **안 들어갔거나 ${n}줄이다**" >&2; fail=1
  fi
done
for key in ${REMOVES[@]+"${REMOVES[@]}"}; do
  if printf '%s\n' "$VERIFY" | grep -qE "^$key="; then
    echo "  $key — **아직 있다**" >&2; fail=1
  else
    echo "  $key — 지워졌다"
  fi
done
[ "$fail" -eq 0 ] || exit 1

cat <<MSG

아직 운영에는 안 먹었다. 서버가 새 .env 를 물어야 한다:

  ssh -i ~/.ssh/pawloop-staging.pem ec2-user@\$(aws ec2 describe-instances \\
    --filters 'Name=tag:Name,Values=pawloop-prod-backend' 'Name=instance-state-name,Values=running' \\
    --query 'Reservations[].Instances[].PublicIpAddress' --output text --region $REGION)
  sudo bash /opt/pawloop-backend/repo/backend/scripts/refresh-prod-env.sh
  # 키를 지웠으면 앞에 EXPECT_KEYS=<서버 .env 의 기대 키 수> 를 붙인다

되돌리려면 버전 $OLD_VERSION 을 꺼내 쓴다:

  aws ssm get-parameter --name $PARAM:$OLD_VERSION --with-decryption \\
    --query Parameter.Value --output text --region $REGION
MSG
