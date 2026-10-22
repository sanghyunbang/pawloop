#!/usr/bin/env bash
#
# prod 서버에서 SSM 의 .env 를 다시 받아 앱을 재시작한다 — 이슈 #609 · #615.
#
# ## 왜 이 스크립트가 필요한가
#
# 부팅 스크립트(user_data_backend.sh.tftpl)는 SSM 에서 받은 .env 에 **세 줄을 덧붙인다.**
#
#     APP_PUBLISHED_HOST=127.0.0.1     앱 포트를 루프백에만 (#613)
#     PAWLOOP_DOMAIN=…                 Caddyfile 이 {$PAWLOOP_DOMAIN} 로 읽는다
#     PAWLOOP_SITE_DOMAIN=…            소개·약관 페이지의 이름 (#611)
#     ACME_EMAIL=…                     Caddyfile 이 {$ACME_EMAIL} 로 읽는다
#
# **SSM 에는 이 셋이 없다.** 그래서 손으로
#
#     aws ssm get-parameter … > .env && docker compose up -d
#
# 를 하면 저 셋이 사라지고 Caddy 가 도메인을 못 읽어 컨테이너가 죽는다. 80·443 이
# 조용해지고, 그 실패는 컨테이너 로그에만 남는다 — 2026-09-17 에 문법 오류로 똑같이
# 죽어 본 자리다(#616).
#
# 도메인과 이메일은 **지금 .env 에서 읽어 온다.** 여기 적어 두면 terraform 의
# 값과 갈라지고, 갈라진 쪽이 인증서를 못 받는다.
#
# ## 쓰는 법 (서버에서)
#
#     sudo bash /opt/pawloop-backend/repo/backend/scripts/refresh-prod-env.sh
#
# SSM 에서 키를 **일부러 지운** 날은 몇 개여야 하는지를 말해 준다. 안 그러면 "줄었다" 며 선다.
#
#     sudo EXPECT_KEYS=54 bash /opt/pawloop-backend/repo/backend/scripts/refresh-prod-env.sh
#
# 비밀값은 화면에 찍지 않는다. 키 개수와 바뀐 줄 수만 말한다.
set -euo pipefail

PARAM="${PARAM:-/pawloop/prod/backend/env}"
REGION="${REGION:-ap-northeast-2}"
DIR="${DIR:-/opt/pawloop-backend/repo/backend}"

cd "$DIR"

if [ ! -f .env ]; then
  echo "지금 .env 가 없다: $DIR/.env" >&2
  echo "이 스크립트는 **이미 떠 있는 서버**의 설정을 바꾸는 것이라, 기존 .env 에서" >&2
  echo "도메인과 이메일을 읽어 온다. 처음 만드는 것이면 terraform apply 를 쓴다." >&2
  exit 1
fi

# 부팅 스크립트가 덧붙였던 값들. 지금 .env 가 정본이다.
keep_value() {
  grep -m1 "^$1=" .env | cut -d= -f2- || true
}

DOMAIN="$(keep_value PAWLOOP_DOMAIN)"
SITE="$(keep_value PAWLOOP_SITE_DOMAIN)"
EMAIL="$(keep_value ACME_EMAIL)"

if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
  echo "지금 .env 에 PAWLOOP_DOMAIN 이나 ACME_EMAIL 이 없다." >&2
  echo "그대로 진행하면 Caddy 가 도메인을 못 읽고 죽는다. 여기서 선다." >&2
  exit 1
fi

BEFORE_KEYS=$(grep -cE '^[A-Z_]+=' .env || true)

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
chmod 600 "$TMP"

aws ssm get-parameter \
  --name "$PARAM" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text \
  --region "$REGION" > "$TMP"

# 마지막 줄에 줄바꿈이 없으면 덧붙인 줄이 그 값에 달라붙는다 (#600).
if [ -n "$(tail -c1 "$TMP")" ]; then
  echo >> "$TMP"
fi

# 있으면 고치고 없으면 더한다. 두 줄이 생기면 어느 쪽이 이기는지가 compose 구현에
# 달리게 되므로 그 상태를 아예 만들지 않는다.
set_env_value() {
  if grep -q "^$1=" "$TMP"; then
    sed -i "s|^$1=.*|$1=$2|" "$TMP"
  else
    printf '%s=%s\n' "$1" "$2" >> "$TMP"
  fi
}

set_env_value APP_PUBLISHED_HOST 127.0.0.1
set_env_value PAWLOOP_DOMAIN "$DOMAIN"
# 비어 있어도 그대로 쓴다 — Caddy 가 빈 이름이면 그 사이트를 안 세운다(#611).
set_env_value PAWLOOP_SITE_DOMAIN "$SITE"
set_env_value ACME_EMAIL "$EMAIL"

AFTER_KEYS=$(grep -cE '^[A-Z_]+=' "$TMP" || true)
CHANGED=$(diff <(sort .env) <(sort "$TMP") | grep -c '^[<>]' || true)

# 일부러 키를 지운 날은 EXPECT_KEYS 로 "몇 개여야 하는지" 를 말한다. 그러면 줄어든 것이
# 의도인지 사고인지 이 스크립트가 구별할 수 있다 — #747 에서 중복 키 하나와 쓸모없는 줄
# 하나를 지웠다. 안 주면 예전처럼 "줄면 선다".
if [ -n "${EXPECT_KEYS:-}" ]; then
  if [ "$AFTER_KEYS" -ne "$EXPECT_KEYS" ]; then
    echo "새 .env 의 키가 $AFTER_KEYS 개인데 EXPECT_KEYS=$EXPECT_KEYS 라고 했다." >&2
    echo "SSM 이 생각과 다르다. 여기서 선다 — .env 는 안 바꿨다." >&2
    exit 1
  fi
elif [ "$AFTER_KEYS" -lt "$BEFORE_KEYS" ]; then
  echo "새 .env 의 키가 줄었다: $BEFORE_KEYS → $AFTER_KEYS" >&2
  echo "값이 빠진 채로 재시작하면 앱이 안 뜬다. 여기서 선다 — .env 는 안 바꿨다." >&2
  echo "일부러 지운 것이면 EXPECT_KEYS=$AFTER_KEYS 를 앞에 붙여 다시 돌려라." >&2
  exit 1
fi

cp .env ".env.bak-$(date +%Y%m%d-%H%M%S)"
install -m 600 "$TMP" .env

echo "키 $BEFORE_KEYS → $AFTER_KEYS · 바뀐 줄 $CHANGED"
echo "도메인 $DOMAIN 유지"

# ── 어느 한 벌만 띄운다 (이슈 #787 뒤) ────────────────────────────────
#
# 앱이 `app-blue` · `app-green` 두 벌이 됐다. **서비스 이름 없이 `up -d` 를 하면 둘 다
# 뜬다.** t3.medium 은 4GB 이고 앱 한 벌이 660MB 라, 평소에 두 벌을 띄워 둘 이유가 없다.
#
# `--remove-orphans` 는 **compose 가 더 이상 모르는 컨테이너를 치운다.** 블루/그린
# 이전에는 서비스 이름이 `app` 이어서 컨테이너가 `heattrip-backend` 였고, 그것이 남아
# 있으면 **호스트 8080 을 쥐고 있어 Caddy 가 포트를 못 잡는다** — 스테이징에서 실제로
# 겪었다. Caddy 가 못 뜨면 api·site 가 둘 다 죽는다.
COMPOSE=(docker compose -f docker-compose.yml -f docker-compose.prod.yml)

# `|| true` 가 꼭 있어야 한다. 이 스크립트는 `set -euo pipefail` 이고, 둘 다 안 돌고
# 있으면 `grep` 이 1 로 끝나면서 **여기서 스크립트가 죽는다** — `.env` 는 이미 새것으로
# 갈아 끼운 뒤라, 코드는 옛것인데 설정만 새것인 상태로 남는다.
# 블루/그린으로 넘어가는 **첫 배포가 정확히 그 경우**다(아직 `app` 뿐이다).
LIVE=$("${COMPOSE[@]}" ps --status running --services 2>/dev/null \
         | grep -E '^app-(blue|green)$' | head -1 || true)
: "${LIVE:=app-blue}"
echo "앱은 $LIVE 한 벌만 띄운다"

"${COMPOSE[@]}" up -d --remove-orphans mysql caddy "$LIVE"

echo
echo "확인:"
echo "  curl -s -o /dev/null -w '%{http_code}\\n' https://$DOMAIN/actuator/health   # 200"
