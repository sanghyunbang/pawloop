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
```

| 파일 | 무엇을 |
|:---|:---|
| `01_add_places_search_fulltext.sql` | `GET /api/explore/places/search`가 쓰는 `places.search_text` FULLTEXT 인덱스 |
| `02_add_places_emotion_columns.sql` | `places`의 감정 데이터 컬럼(`seed_emotion`·`ugc_emotion`·`ugc_count`) |
| `03_add_journey_place_id.sql` | 다이어리↔장소 연결용 `journey.place_id` |
| `04_users_social_account_model.sql` | 소셜 계정 모델 — `users.provider`·`social_id`·`role` 추가, 레거시 `username` 백필, `UNIQUE(provider, social_id)` (이슈 #7) |
| `05_refresh_token.sql` | refresh 토큰 원장 — `refresh_token` 테이블 생성, `UNIQUE(token_hash)`, `user_id`·`expires_at` 인덱스 (이슈 #9) |

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
