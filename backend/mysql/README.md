# MySQL 로컬 스키마 보정

이 디렉터리는 Docker Compose로 띄운 로컬 MySQL에 필요한 SQL을 보관합니다.

## `init`와 `post-start` 차이

- `mysql/init`: MySQL 컨테이너가 새 볼륨으로 처음 초기화될 때만 실행됩니다.
  - **`01_schema.sql` — 운영 스키마 정본입니다 (이슈 #58).** 빈 DB 에 이 앱을 올릴 때
    가장 먼저 실행합니다. 예전에는 이 디렉터리가 비어 있어서, **빈 운영 DB 에 앱을
    올릴 방법이 저장소에 없었습니다** — prod 는 `ddl-auto=validate` 라 아무것도 만들지
    않고, 아래 `post-start` 는 전부 `ALTER TABLE` 이라 테이블이 이미 있다고 전제합니다.
  - 이 파일은 **손으로 고치지 않습니다.** JPA 엔티티에서 뽑습니다:
    ```
    cd backend
    ./gradlew test --tests '*SchemaDdlDriftTest*'
    cp build/generated-schema.sql mysql/init/01_schema.sql
    ```
    `SchemaDdlDriftTest` 가 이 파일과 엔티티가 어긋나면 CI 를 빨간불로 만듭니다.
- `mysql/post-start`: 백엔드 앱이 뜬 뒤 수동으로 실행하는 SQL입니다.

이 프로젝트는 `places` 같은 테이블을 Spring/Hibernate가 앱 시작 시점에 생성합니다. 그래서 `places` 테이블을 대상으로 하는 `ALTER TABLE`은 `mysql/init`에 넣으면 새 볼륨에서 실패할 수 있습니다.

## `post-start` 실행 순서

백엔드와 MySQL이 뜬 뒤, 관리자 CMD에서 번호 순으로 실행합니다. 전부 멱등이라 이미 적용된 항목은 아무 변경 없이 메시지만 출력합니다.

```cmd
docker exec -i heattrip-mysql sh -lc "mysql -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE" < mysql\post-start\01_add_places_search_fulltext.sql
docker exec -i heattrip-mysql sh -lc "mysql -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE" < mysql\post-start\02_add_places_emotion_columns.sql
docker exec -i heattrip-mysql sh -lc "mysql -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE" < mysql\post-start\03_add_journey_place_id.sql
docker exec -i heattrip-mysql sh -lc "mysql -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE" < mysql\post-start\04_users_social_account_model.sql
docker exec -i heattrip-mysql sh -lc "mysql -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE" < mysql\post-start\05_refresh_token.sql
docker exec -i heattrip-mysql sh -lc "mysql -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE" < mysql\post-start\06_chat_rooms.sql
docker exec -i heattrip-mysql sh -lc "mysql -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE" < mysql\post-start\07_family_group.sql
docker exec -i heattrip-mysql sh -lc "mysql -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE" < mysql\post-start\08_care_log.sql
docker exec -i heattrip-mysql sh -lc "mysql -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE" < mysql\post-start\09_chat_message.sql
docker exec -i heattrip-mysql sh -lc "mysql -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE" < mysql\post-start\10_place_cache.sql
docker exec -i heattrip-mysql sh -lc "mysql -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE" < mysql\post-start\11_dog.sql
docker exec -i heattrip-mysql sh -lc "mysql -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE" < mysql\post-start\12_walk.sql
docker exec -i heattrip-mysql sh -lc "mysql -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE" < mysql\post-start\13_walk_path_t.sql
docker exec -i heattrip-mysql sh -lc "mysql -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE" < mysql\post-start\14_community.sql
docker exec -i heattrip-mysql sh -lc "mysql -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE" < mysql\post-start\15_report.sql
docker exec -i heattrip-mysql sh -lc "mysql -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE" < mysql\post-start\16_user_block.sql
docker exec -i heattrip-mysql sh -lc "mysql -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE" < mysql\post-start\17_report_target_to_snapshot.sql
```

| 파일 | 무엇을 |
|:---|:---|
| `01_add_places_search_fulltext.sql` | `GET /api/explore/places/search`가 쓰는 `places.search_text` FULLTEXT 인덱스 |
| `02_add_places_emotion_columns.sql` | `places`의 감정 데이터 컬럼(`seed_emotion`·`ugc_emotion`·`ugc_count`) |
| `03_add_journey_place_id.sql` | 다이어리↔장소 연결용 `journey.place_id` |
| `04_users_social_account_model.sql` | 소셜 계정 모델 — `users.provider`·`social_id`·`role` 추가, 레거시 `username` 백필, `UNIQUE(provider, social_id)` (이슈 #7) |
| `05_refresh_token.sql` | refresh 토큰 원장 — `refresh_token` 테이블 생성, `UNIQUE(token_hash)`, `user_id`·`expires_at` 인덱스 (이슈 #9) |
| `06_chat_rooms.sql` | 방·멤버십·초대 — `chat_room`·`chat_room_member`·`chat_room_invite` 생성, `UNIQUE(origin_kind, origin_ref)`·`UNIQUE(room_id, user_id)`·`UNIQUE(code)`, `chat_room` 으로의 FK 둘 (이슈 #74 · [ADR-0011](../../docs/99-decisions/decision-log.md)) |
| `07_family_group.sql` | 가족 케어 그룹 — `family_group(id, name, created_at)` 생성. **초대코드도 멤버십도 여기 없다** (이슈 #75 · [ADR-0011](../../docs/99-decisions/decision-log.md)) |
| `08_care_log.sql` | 오늘의 케어와 산책 주의사항 — `care_log`·`walk_note` 생성, `family_group`·`users`로의 FK 4개, `walk_note`의 `UNIQUE(group_id)`(그룹당 한 장), `care_log.type` CHECK 다섯 값 (이슈 #76) |
| `09_chat_message.sql` | 채팅 메시지 — `chat_message` 생성, `UNIQUE(room_id, room_seq)`(커서가 `id` 가 아닌 근거)·`UNIQUE(room_id, client_msg_id)`(재전송 멱등)·`idx_chat_sender`, `chat_room`으로의 FK 하나. **`06` 이 먼저입니다** (이슈 #78 · [ADR-0011](../../docs/99-decisions/decision-log.md)) |
| `10_place_cache.sql` | 관광공사(KTO) 프록시의 캐시와 호출 예산 — `kto_call_budget`·`place_cell`·`pet_place_detail` 생성. **FK 가 하나도 없습니다.** `kto_call_budget` 의 `PRIMARY KEY (day, pool)` 이 KTO 일 1,000콜 한도를 지키는 유일한 장치이고, 그 판정이 조건부 UPDATE 한 문장입니다 (이슈 #40) |
| `11_dog.sql` | 반려동물 프로필 — `dog` 생성, `users` 로의 FK 하나(`ON DELETE CASCADE`)·`idx_dog_user`·이름 붙은 CHECK 둘(`ck_dog_species`·`ck_dog_size`). **CASCADE 여야 합니다** — `UserService.deleteMe` 가 `users` 행을 물리 삭제하므로 `RESTRICT` 면 반려동물을 등록한 사람이 영구히 탈퇴 불가가 됩니다(MySQL 1451). 사후 검증이 그 모드까지 확인합니다 (이슈 #145) |
| `12_walk.sql` | 산책 기록 — `walk` 생성, `dog` 로의 FK 하나(`ON DELETE CASCADE`)·`uq_walk_client(dog_id, client_walk_id)`(재전송 멱등)·인덱스 둘. **`11` 이 먼저입니다.** `path` 는 `LINESTRING SRID 4326` 이고 **NULL 을 허용합니다** — `SPATIAL INDEX` 를 만들지 않는 이유와 함께 [ADR-0015](../../docs/99-decisions/decision-log.md) 에 있습니다. **SRID 검증은 이 파일의 사후 검증에서만 됩니다** — `information_schema.columns.column_type` 이 `linestring` 뿐이라 `SchemaDdlDriftTest` 는 SRID 가 빠진 스키마를 같다고 봅니다(실측) (이슈 #145) |
| `13_walk_path_t.sql` | 산책 경로의 **점별 시각** — `walk.path_t JSON NULL` 추가. `path` 와 길이가 같아야 하지만 **DB 에 CHECK 를 걸지 않았습니다** — 검사는 `WalkPath.toPathTimes` 가 유일한 방어선이고 그 사실을 이 스크립트 §B-1 이 적어 뒀습니다. **12 가 먼저입니다** (이슈 #155) |
| `14_community.sql` | 커뮤니티 표 셋 — `post`·`comment`·`reaction` 생성. `users` 로의 FK 셋(**CASCADE 아님** — 탈퇴가 남의 글에서 대화를 끊지 않는다)·`post` 로의 FK 둘(CASCADE)·`uq_reaction(post_id, user_id, type)`(**사용자당 글마다 여러 반응** — ADR-0016 결정 2)·인덱스 둘. **04 가 먼저입니다.** `board` 는 ASCII 키이고 장소 참조는 `content_id VARCHAR(64)` 이며 FK 가 없습니다 (장소는 캐시라 행이 없을 수 있습니다) (이슈 #169) |
| `15_report.sql` | 신고 표 둘 — `report`·`report_snapshot` 생성. `users` 로의 **FK 를 안 겁니다** (신고는 값으로만 사람을 가리킵니다 — 탈퇴가 신고 기록을 지우면 안 됩니다) · `target_type`·`reason`·`role` 셋에 CHECK · 인덱스 셋. **UNIQUE 가 없습니다** — 글은 편집되므로 같은 사람이 같은 글을 다시 신고하는 것을 DB 가 막으면 안 됩니다 (이슈 #166 · ADR-0016) |
| `16_user_block.sql` | `chat_block` → `user_block` **이름 변경**(인덱스 `uq_chat_block` → `uq_user_block` 포함). 가리기는 처음부터 사람 단위였고, 채팅 안에 있었던 것은 채팅이 그것을 처음 필요로 했기 때문입니다. 커뮤니티가 같은 가리기를 쓰면서 그 이름이 거짓이 됐습니다. **행이 0일 때만 공짜입니다** — 두 표가 다 있으면 어느 쪽이 정본인지 사람이 정하도록 멈춥니다 (이슈 #166 · ADR-0016) |
| `17_report_target_to_snapshot.sql` | 신고의 좌표를 `report` 부모에서 `report_snapshot` 자식으로 내립니다 — `target_type`·`target_id`·`target_ordinal`·`content_type` 추가, 부모의 `target_*`·인덱스·CHECK 제거, 자식에 CHECK 둘과 인덱스 하나. 채팅 신고가 한 건에 메시지 셋까지라 부모 한 칸으로는 안 담겼습니다. **15 가 먼저입니다.** `chat_report` 에 행이 있으면 멈춥니다 — 신고는 다시 만들 수 없는 기록이라 이관을 사람이 정해야 합니다 (이슈 #254 · ADR-0016) |

### 04는 실패하면 멈춥니다 — 그게 정상입니다

`04`는 `ALTER TABLE`을 쓰기 때문에 트랜잭션으로 감쌀 수 없습니다(MySQL의 DDL은 암묵적 커밋을 일으킵니다). 대신 앞뒤로 관문이 하나씩 있습니다.

- **사전 점검**: 같은 `(provider, social_id)`를 갖게 될 행이 이미 여럿이면, `users`를 한 글자도 바꾸지 않고 중복 목록을 출력한 뒤 `ERROR 1644`로 중단합니다. 목록의 행을 병합·삭제한 뒤 다시 실행하면 됩니다.
- **사후 검증**: 컬럼 3개·`UNIQUE` 제약·백필이 전부 끝났는지 확인하고, 하나라도 빠졌으면 `ERROR 1644`로 실패합니다.

사후 검증이 필요한 이유는 `spring.jpa.hibernate.ddl-auto=validate`가 **UNIQUE 제약을 검사하지 않기 때문**입니다. 제약이 빠진 채 배포해도 앱은 멀쩡히 뜨고, 아무도 모르는 상태로 중복이 쌓입니다.

되돌리는 SQL(DOWN)은 `04_users_social_account_model.sql` 헤더 주석에 있습니다.

### 05는 실패하면 멈춥니다 — 그게 정상입니다

`05`는 새 테이블을 만들 뿐이라 백필이 없지만, 관문은 04와 같이 둡니다.

- **사전 점검**: dev는 `ddl-auto=update`라 **앱이 먼저 뜨면 Hibernate가 `refresh_token`을 이미 만들어 둡니다.** 엔티티 초안이 다른 상태로 만든 테이블(UNIQUE 없음 등)에 중복 `token_hash`가 들어 있으면 UNIQUE를 걸 수 없습니다. 그럴 때는 스키마를 한 글자도 바꾸지 않고 그 해시 목록을 출력한 뒤 `ERROR 1644`로 중단합니다. 해당 행을 지우면 그 사용자는 재로그인만 하면 됩니다.
- **사후 검증**: 컬럼 6개·`UNIQUE(token_hash)`·`user_id` 인덱스·`expires_at` 인덱스가 전부 걸렸는지 확인하고, 하나라도 빠졌으면 `ERROR 1644`로 실패합니다.

사후 검증이 필요한 이유는 04와 같습니다 — `spring.jpa.hibernate.ddl-auto=validate`는 **UNIQUE 제약도 인덱스도 검사하지 않습니다.** `uk_refresh_token_token_hash`가 빠진 채 배포해도 앱은 멀쩡히 뜨고, 재사용 감지의 전제("해시 1개 = 행 1개")가 아무도 모르게 무너집니다.

**실행 순서**: `05`는 앱 배포 **전**에 돌립니다. 테이블이 없으면 로그인이 실패하므로 이 순서는 사실상 강제됩니다. 되돌릴 때는 앱을 먼저 내립니다. 되돌리는 SQL(DOWN)은 `05_refresh_token.sql` 헤더 주석에 있습니다.

만료된 `refresh_token` 행은 이 스크립트가 아니라 애플리케이션의 야간 스케줄 잡이 지웁니다(기본 04:30 Asia/Seoul, `auth.refresh-token.purge-cron`으로 조정).

### 06도 실패하면 멈춥니다 — 관문이 하나 더 있습니다

`06`은 04·05와 같은 사전 점검·사후 검증을 갖고, 여기에 **경계 검증**을 하나 더 답니다.

- **사전 점검**: dev가 `ddl-auto=update`라 앱이 먼저 뜨면 Hibernate가 세 표를 이미 만들어 둡니다. 그 표에 중복 `(origin_kind, origin_ref)`나 중복 초대코드가 들어 있으면 `UNIQUE`를 걸 수 없습니다. 그럴 때는 스키마를 한 글자도 바꾸지 않고 목록을 출력한 뒤 `ERROR 1644`로 중단합니다.
- **사후 검증**: 표 3개·컬럼·`UNIQUE` 3개·`chat_room`으로의 FK 2개가 전부 걸렸는지 확인합니다. `UNIQUE`는 이름이 아니라 **컬럼 수**로 셉니다 — 이름만 보면 "한 컬럼만 걸린 `UNIQUE`"를 통과시키고, 그러면 같은 가족 그룹에 방이 둘 생기는 것을 못 막습니다.
- **경계 검증**: `chat_*` 표에서 `chat_*` 밖으로 나가는 FK가 **0개**인지 봅니다. `users`·`family_group`·`dog`로 FK를 내지 않는 것이 [ADR-0011](../../docs/99-decisions/decision-log.md)의 결정이고, `refresh_token.user_id`(이슈 #9)가 이미 같은 방식입니다. 저장소 쪽은 `ChatBoundaryArchitectureTest`가 같은 것을 잡습니다.

**실행 순서**: `06`은 앱 배포 **전**에 돌립니다. prod는 `ddl-auto=validate`라 표가 없으면 부팅 자체가 실패하므로 이 순서는 사실상 강제됩니다. 빈 DB를 새로 세우는 경우에는 필요 없습니다 — `mysql/init/01_schema.sql`이 세 표를 이미 담고 있습니다. 되돌리는 SQL(DOWN)은 `06_chat_rooms.sql` 헤더 주석에 있습니다.

### 07은 `06` 다음입니다 — FK 때문이 아닙니다

`07_family_group.sql`이 만드는 `family_group`에는 **FK가 하나도 없습니다.** 그런데도 `06` 뒤인 이유는, 그룹을 만드는 코드가 **같은 트랜잭션에서** `chat_room`과 `chat_room_member(OWNER)`를 함께 INSERT하기 때문입니다. 세 표가 없으면 그룹 생성이 통째로 실패합니다.

- **사전 점검**: 같은 이름의 표가 **다른 모양**으로 이미 있으면 멈춥니다. `CREATE TABLE IF NOT EXISTS`는 이미 있는 표를 고치지 않으므로, 이 관문이 없으면 스크립트는 조용히 성공하고 그 차이는 prod 부팅(`ddl-auto=validate`)에서야 드러납니다. 특히 옛 정의의 `invite_code` 컬럼이 남아 있으면 `ERROR 1644`로 중단합니다 — 초대코드는 `chat_room_invite`로 옮겼습니다([ADR-0011](../../docs/99-decisions/decision-log.md)).
- **사후 검증**: 표·컬럼과 함께 **경계를 양방향으로** 봅니다. `family_group`이 내보내는 FK 0개, `chat_*`가 `family_group`으로 거는 FK 0개, 그리고 `group_member` 표가 **없을 것**. 마지막 것이 ADR-0011 결정 1(멤버십 표는 `chat_room_member` 하나)을 실행 가능한 형태로 적은 것입니다.

되돌리는 SQL(DOWN)은 `07_family_group.sql` 헤더 주석에 있습니다. 되돌려도 **방과 대화는 남습니다** — `chat_room`은 이 표로 FK를 걸지 않기 때문입니다.

### 08은 `07` 다음입니다 — 이번에는 **진짜 FK 때문**입니다

`08_care_log.sql`이 만드는 `care_log`·`walk_note`는 `family_group(id)`과 `users(id)`로 **FK를 정상적으로 겁니다.** "chat 밖으로 나가는 FK 0개"는 `chat_*` 세 표에만 걸리는 규칙입니다([ADR-0011](../../docs/99-decisions/decision-log.md) 결정 4). 부모 표가 없으면 `CREATE`가 `errno 150`으로 죽는데 그 메시지는 무엇이 없는지 안 알려주므로, 스크립트가 **먼저 사람 말로 멈춥니다**.

- **사전 점검**: `care_log.dog_id`가 `NOT NULL`이면 중단합니다. `dog` 표가 정본 스키마에 없어서(`docs/03-database/schema.md §3`은 계획입니다) 그 값을 채울 수 없고, 그 모양의 표에는 이 앱이 한 행도 못 넣습니다. `walk_note`에 `created_at`이 있어도 중단합니다 — 그룹당 여러 장이던 옛 모양이고, 지금은 `updated_by`·`updated_at`을 든 **한 장**입니다.
- **사후 검증**: 표 2개·컬럼(8/5)과 함께 **FK 4개**·`walk_note`의 `UNIQUE(group_id)`를 봅니다. `ddl-auto=validate`도 `SchemaDdlDriftTest`도 FK·UNIQUE·CHECK를 보지 않으므로 여기서 안 보면 아무도 안 알려줍니다.
- **경계 검증**: `dog`로 가는 FK 0개(표 자체가 없습니다), 그리고 케어 두 표와 `chat_*` 사이의 FK가 **양방향 모두 0개**인지 봅니다. 케어는 그룹 단위로 공유되고 방에서는 **인가만** 받습니다 — 표끼리 묶으면 방 삭제가 케어 기록 삭제 순서에 묶입니다.

`care_log.dog_id`에 FK가 없는 것을 **#9의 "일부러 FK를 안 걸었다"와 같은 것으로 읽으면 안 됩니다.** #9(`refresh_token.user_id`)는 `users` 표가 있는데도 걸지 않은 판단이고, 여기는 참조할 표가 아직 없는 것입니다. `dog` 표가 생기는 날 여기는 FK를 걸고 #9는 안 겁니다.

되돌리는 SQL(DOWN)은 `08_care_log.sql` 헤더 주석에 있습니다. 되돌려도 **그룹·방·대화는 남습니다** — 화살표가 이쪽에서 저쪽으로만 가기 때문입니다.

### 09는 `06` 다음입니다 — `chat_room`으로 FK를 겁니다

`09_chat_message.sql`이 만드는 `chat_message`는 `chat_room(id)`으로 `ON DELETE CASCADE` FK를 겁니다. **경계 안**이라 정상입니다 — 방이 지워지면 그 방의 대화도 갈 곳이 없습니다. 반대로 `sender_user_id`에는 FK를 걸지 않습니다: `ON DELETE CASCADE`면 **탈퇴 한 번에 그 사람이 방에 쓴 말이 전부 사라지고**, 남는 것은 대답만 있고 질문이 없는 대화입니다([ADR-0011](../../docs/99-decisions/decision-log.md) 결정 4).

- **사전 점검**: `chat_room`이 없으면 "06을 먼저 실행하라"고 말하고 멈춥니다. FK를 빼고 만들어 두는 선택지는 없습니다 — 방이 지워졌는데 메시지가 남으면 아무도 볼 수 없는 행이 영원히 쌓입니다. 그리고 dev는 `ddl-auto=update`라 앱이 먼저 뜨면 Hibernate가 표를 이미 만들어 두는데, 그 표에 중복 `(room_id, room_seq)`나 중복 `(room_id, client_msg_id)`가 있으면 `UNIQUE`를 걸 수 없으므로 목록을 출력한 뒤 중단합니다.
- **사후 검증**: 표·컬럼 10개와 함께 **`UNIQUE` 둘을 컬럼 수로** 봅니다. `uq_chat_room_seq`가 `(room_id)` 한 컬럼에만 걸리면 한 방에 메시지가 한 줄만 들어가고, 그 사실은 스크립트가 성공한 것처럼 끝난 뒤에야 드러납니다.
- **경계 검증**: 06과 같습니다 — `chat_*`에서 `chat_*` 밖으로 나가는 FK가 **0개**인지 봅니다.

**왜 `UNIQUE(room_id, room_seq)`가 이 표의 핵심인가**: 커서가 `id`가 아니라 `room_seq`이기 때문입니다. `id AUTO_INCREMENT`는 INSERT 시점에 배정되고 남에게 보이는 것은 커밋 시점이라, 늦게 커밋된 작은 `id`를 `afterId` 폴링이 **영구히** 건너뜁니다. `ddl-auto=validate`도 `SchemaDdlDriftTest`도 `UNIQUE`를 보지 않으므로, 이 제약이 빠진 채 배포해도 앱은 멀쩡히 뜨고 발급이 틀린 날 조용히 메시지 하나가 사라집니다.

되돌리는 SQL(DOWN)은 `09_chat_message.sql` 헤더 주석에 있습니다. **되돌리면 모든 대화 내용이 사라집니다** — 방·멤버십은 남지만 그 방의 말은 복구할 수 없습니다.
