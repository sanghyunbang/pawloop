#!/usr/bin/env bash
# 이 DB 에 마이그레이션이 어디까지 들어갔는지 묻는다.
#
# ## 왜 있나
#
# **저장소에 스크립트가 있는 것과 DB 에 들어간 것은 다른 사실인데, 그 차이를 알 방법이
# 없었다.** 2026-09-08 에 로컬 dev DB 에서 둘이 조용히 빠져 있는 것을 우연히 찾았다 —
#
#   24_place_catalog_layers.sql  옛 CHECK 가 안 지워져, 부팅마다 인허가 8,110행을 받아 놓고
#                                저장에서 통째로 버렸다(Check constraint violated).
#   29_care_type_poop.sql        ck_carelog_type 이 다섯 값 그대로라 배변·마킹 기록이 실패했다.
#
# ## 왜 어느 쪽에서도 안 걸렸나
#
# dev 는 `ddl-auto=update` 라 **Hibernate 가 표와 컬럼을 만들어 준다.** 그래서 새 표도 새
# 컬럼도 저절로 생겨 "다 들어간 것처럼" 보인다. 그런데 **Hibernate 는 CHECK 제약을 절대 안
# 건드리고**, prod 의 `validate` 도 CHECK 와 PK 는 안 본다. CHECK 만 고치는 마이그레이션은
# 그래서 **양쪽 어디서도 안 잡힌다.** 여기가 그 자리다.
#
# ## 무엇을 재나
#
# 마이그레이션마다 **"들어갔으면 반드시 참인 사실" 한 줄**을 DB 에 묻는다. 각 스크립트의
# `[D] 사후 검증` 절이 이미 그 조건을 적어 뒀고, 여기 표는 그중 하나씩을 가져온 것이다.
# `MigrationChecksAreCompleteTest` 가 "빠뜨린 파일이 없다" 를 잠근다.
#
# ## 값을 찍지 않는다
#
# 접속 정보는 이름만 읽고 비밀번호는 `MYSQL_PWD` 로 넘긴다 — 명령줄에 안 남는다.
# 출력을 그대로 이슈에 붙여도 된다.
#
# ## 쓰는 법
#
#   bash scripts/check-migrations.sh                     # backend/.env 의 dev DB
#   DB_HOST=… DB_PORT=… DB_NAME=… DB_USER=… DB_PASS=… \
#     bash scripts/check-migrations.sh                   # 운영 DB 등 다른 곳
#
# 나가는 값: 빠진 것이 하나라도 있으면 1 이고, 돌려야 할 파일 이름을 찍는다.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/backend/.env"

read_env() {
  [ -f "$ENV_FILE" ] || return 0
  grep -m1 "^$1=" "$ENV_FILE" | cut -d= -f2- | tr -d ' \r'
}

# `jdbc:mysql://호스트:포트/이름?…` 에서 조각을 꺼낸다.
JDBC="$(read_env SPRING_DATASOURCE_URL)"
JDBC_HOSTPORT="$(printf '%s' "$JDBC" | sed -n 's#^jdbc:mysql://\([^/?]*\).*#\1#p')"
JDBC_DB="$(printf '%s' "$JDBC" | sed -n 's#^jdbc:mysql://[^/]*/\([^?]*\).*#\1#p')"

DB_HOST="${DB_HOST:-${JDBC_HOSTPORT%%:*}}"
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-}"
if [ -z "$DB_PORT" ]; then
  case "$JDBC_HOSTPORT" in
    *:*) DB_PORT="${JDBC_HOSTPORT##*:}" ;;
    *) DB_PORT=3306 ;;
  esac
fi
DB_NAME="${DB_NAME:-${JDBC_DB:-heat_trip_db}}"
DB_USER="${DB_USER:-$(read_env SPRING_DATASOURCE_USERNAME)}"
DB_PASS="${DB_PASS:-$(read_env SPRING_DATASOURCE_PASSWORD)}"

# `mysql` 이 PATH 에 없는 것이 윈도우에서는 보통이다.
MYSQL="${MYSQL_CLIENT:-}"
if [ -z "$MYSQL" ]; then
  if command -v mysql >/dev/null 2>&1; then
    MYSQL="$(command -v mysql)"
  else
    for guess in "/c/Program Files/MySQL/MySQL Server 8.0/bin/mysql.exe" \
                 "/c/Program Files/MySQL/MySQL Server 8.4/bin/mysql.exe"; do
      [ -x "$guess" ] && MYSQL="$guess" && break
    done
  fi
fi
if [ -z "$MYSQL" ]; then
  echo "mysql 클라이언트를 못 찾았다. MYSQL_CLIENT=/경로/mysql 로 알려 준다."
  exit 2
fi

q() {
  MYSQL_PWD="$DB_PASS" "$MYSQL" -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "$DB_NAME" \
    -N -B --default-character-set=utf8mb4 -e "$1" 2>/dev/null
}

if [ "$(q 'SELECT 1;')" != "1" ]; then
  echo "DB 에 못 붙었다 — $DB_HOST:$DB_PORT/$DB_NAME (사용자 이름은 backend/.env 에서 읽는다)"
  echo "  backend/.env 의 SPRING_DATASOURCE_* 를 보거나 DB_HOST/DB_PORT/DB_NAME/DB_USER/DB_PASS 로 덮는다."
  exit 2
fi

# ── 한 줄짜리 질문들 ──────────────────────────────────────────────────
has_table()  { q "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name='$1';"; }
has_column() { q "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='$1' AND column_name='$2';"; }
has_cons()   { q "SELECT COUNT(*) FROM information_schema.table_constraints WHERE constraint_schema=DATABASE() AND table_name='$1' AND constraint_name='$2';"; }
has_index()  { q "SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema=DATABASE() AND table_name='$1' AND index_name='$2';"; }
check_has()  { q "SELECT COUNT(*) FROM information_schema.check_constraints WHERE constraint_schema=DATABASE() AND constraint_name='$1' AND check_clause LIKE '%$2%';"; }

MISSING=()
CURRENT_FILE=""

# 이 마이그레이션에 대한 판정. $1 기대(1/0) · $2 실제 · $3 무엇을 봤나
want() {
  local expect="$1" got="$2" what="$3"
  if [ "${got:-x}" = "$expect" ]; then
    printf '  ✓ %s\n' "$what"
  else
    printf '  ✗ %s  (기대 %s · 실제 %s)\n' "$what" "$expect" "${got:-읽기 실패}"
    MISSING+=("$CURRENT_FILE")
  fi
}

step() {
  CURRENT_FILE="$1"
  printf '\n%s\n' "$1"
}

echo "── $DB_HOST:$DB_PORT/$DB_NAME 에 마이그레이션이 들어갔나 ──"

step "01_add_places_search_fulltext.sql"
want 1 "$(has_index places ft_places_search_text)" "places 의 FULLTEXT 인덱스 ft_places_search_text"

step "02_add_places_emotion_columns.sql"
want 1 "$(has_column places seed_emotion)" "places.seed_emotion"

step "03_add_journey_place_id.sql"
want 1 "$(has_column journey place_id)" "journey.place_id"

step "04_users_social_account_model.sql"
want 1 "$(has_column users provider)" "users.provider"
want 1 "$(has_cons users uk_users_provider_social_id)" "uk_users_provider_social_id"

step "05_refresh_token.sql"
want 1 "$(has_table refresh_token)" "refresh_token 표"
want 1 "$(has_cons refresh_token uk_refresh_token_token_hash)" "uk_refresh_token_token_hash"

step "06_chat_rooms.sql"
want 1 "$(has_table chat_room)" "chat_room 표"
want 1 "$(has_cons chat_room_member uq_chat_member)" "uq_chat_member"

step "07_family_group.sql"
want 1 "$(has_table family_group)" "family_group 표"

step "08_care_log.sql"
want 1 "$(has_table care_log)" "care_log 표"
want 1 "$(has_table walk_note)" "walk_note 표"

step "09_chat_message.sql"
want 1 "$(has_table chat_message)" "chat_message 표"
want 1 "$(has_cons chat_message uq_chat_room_seq)" "uq_chat_room_seq"

step "10_place_cache.sql"
want 1 "$(has_table place_cell)" "place_cell 표"
want 1 "$(has_table kto_call_budget)" "kto_call_budget 표"

step "11_dog.sql"
want 1 "$(has_table dog)" "dog 표"
want 1 "$(has_column dog species)" "dog.species"

step "12_walk.sql"
want 1 "$(has_table walk)" "walk 표"

step "13_walk_path_t.sql"
want 1 "$(has_column walk path_t)" "walk.path_t"

step "14_community.sql"
want 1 "$(has_table post)" "post 표"
want 1 "$(has_cons post chk_post_board)" "chk_post_board"

step "15_report.sql"
want 1 "$(has_table report)" "report 표"
want 1 "$(has_table report_snapshot)" "report_snapshot 표"

step "16_user_block.sql"
want 1 "$(has_table user_block)" "user_block 표"
want 0 "$(has_table chat_block)" "chat_block 은 없어야 한다 (RENAME 이 안 돌면 둘 다 남는다)"

step "17_report_target_to_snapshot.sql"
want 1 "$(has_column report_snapshot target_type)" "report_snapshot.target_type"
want 1 "$(has_cons report_snapshot chk_report_snapshot_target_type)" "chk_report_snapshot_target_type"

step "18_place_catalog.sql"
want 1 "$(has_table place_catalog)" "place_catalog 표"

step "19_user_consent.sql"
want 1 "$(has_table user_consent)" "user_consent 표"
want 1 "$(has_cons user_consent chk_user_consent_kind)" "chk_user_consent_kind"

step "20_drop_chat_report.sql"
want 0 "$(has_table chat_report)" "chat_report 는 없어야 한다"
want 0 "$(has_table chat_reported_message)" "chat_reported_message 는 없어야 한다"

step "21_users_drop_consent_columns.sql"
want 0 "$(has_column users agree_tos)" "users.agree_tos 는 없어야 한다 (동의는 user_consent 로 옮겼다)"

step "22_care_log_dog_fk.sql"
want 1 "$(has_column care_log dog_id)" "care_log.dog_id"
want 1 "$(has_cons care_log fk_carelog_dog)" "fk_carelog_dog"

step "23_dog_deleted_at.sql"
want 1 "$(has_column dog deleted_at)" "dog.deleted_at"

step "24_place_catalog_layers.sql"
want 1 "$(has_column place_catalog source)" "place_catalog.source"
want 1 "$(has_table trail_route)" "trail_route 표"
want 1 "$(has_cons place_catalog chk_place_catalog_source)" "chk_place_catalog_source"
want 0 "$(has_cons place_catalog chk_place_catalog_singleton)" "chk_place_catalog_singleton 은 없어야 한다 (남으면 병원·펫샵을 못 담는다)"

step "25_push.sql"
want 1 "$(has_table device_token)" "device_token 표"
want 1 "$(has_table push_preference)" "push_preference 표"

step "26_walk_place.sql"
want 1 "$(has_column walk place_source)" "walk.place_source"
want 1 "$(has_column walk place_content_id)" "walk.place_content_id"

step "27_course.sql"
want 1 "$(has_table course)" "course 표"

step "28_post_course.sql"
want 1 "$(has_column post course_id)" "post.course_id"

step "29_care_type_poop.sql"
want 1 "$(check_has ck_carelog_type poop)" "ck_carelog_type 이 poop 을 받는다"
want 1 "$(check_has ck_carelog_type pee)" "ck_carelog_type 이 pee 를 받는다"

step "30_users_neighborhood.sql"
want 1 "$(has_column users neighborhood_code)" "users.neighborhood_code"

step "31_place_catalog_localtrail.sql"
want 1 "$(check_has chk_place_catalog_source localtrail)" "chk_place_catalog_source 가 localtrail 을 받는다 (안 받으면 동네 길이 조용히 안 담긴다)"

step "32_place_catalog_playground.sql"
want 1 "$(check_has chk_place_catalog_source playground)" "chk_place_catalog_source 가 playground 를 받는다 (안 받으면 놀이터가 조용히 안 담긴다)"

step "33_walk_dog.sql"
want 1 "$(has_table walk_dog)" "walk_dog 표 (없으면 부팅이 validate 에서 죽는다)"

step "34_schedule.sql"
want 1 "$(has_table schedule)" "schedule 표 (없으면 부팅이 validate 에서 죽는다)"

step "35_schedule_care_log.sql"
want 1 "$(has_column schedule care_log_id)" "schedule.care_log_id (없으면 부팅이 validate 에서 죽는다)"

step "36_schedule_repeat.sql"
want 1 "$(has_column schedule repeat_kind)" "schedule.repeat_kind (없으면 부팅이 validate 에서 죽는다)"
want 1 "$(has_table schedule_exception)" "schedule_exception 표 (없으면 하루만 건너뛰기가 안 된다)"

step "37_crew.sql"
want 1 "$(has_table crew)" "crew 표 (없으면 부팅이 validate 에서 죽는다)"
want 1 "$(check_has ck_crew_visibility invite)" "ck_crew_visibility 가 invite 를 받는다 (없으면 아무 문자열이나 공개 범위가 된다)"

step "38_crew_favor.sql"
want 1 "$(has_table crew_favor)" "crew_favor 표 (없으면 부팅이 validate 에서 죽는다)"
want 1 "$(check_has ck_crew_favor_slot afternoon)" "ck_crew_favor_slot 이 afternoon 을 받는다 (없으면 아무 문자열이나 시간대가 된다)"

step "39_post_media.sql"
want 1 "$(has_column media_objects status)" "media_objects.status 컬럼 (없으면 부팅이 validate 에서 죽는다)"
want 1 "$(check_has ck_media_status pending)" "ck_media_status 가 pending 을 받는다 (없으면 아무 문자열이나 상태가 된다)"
want 1 "$(has_index media_objects idx_media_orphan)" "idx_media_orphan (없으면 고아 청소가 표 전체를 훑는다)"

# ── 마무리 ───────────────────────────────────────────────────────────
echo
if [ "${#MISSING[@]}" -eq 0 ]; then
  echo "전부 들어가 있다."
  exit 0
fi

echo "덜 들어간 것이 있다 — 아래를 순서대로 돌린다:"
printf '%s\n' "${MISSING[@]}" | sort -u | while read -r f; do
  echo "  mysql -h $DB_HOST -P $DB_PORT -u $DB_USER $DB_NAME < backend/mysql/post-start/$f"
done
echo
echo "각 스크립트는 멱등이다 — 이미 들어간 부분은 '이미 있음' 을 찍고 지나간다."
exit 1
