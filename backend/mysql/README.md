# MySQL 로컬 스키마 보정

이 디렉터리는 Docker Compose로 띄운 로컬 MySQL에 필요한 SQL을 보관합니다.

## `init`와 `post-start` 차이

- `mysql/init`: MySQL 컨테이너가 새 볼륨으로 처음 초기화될 때만 실행됩니다.
- `mysql/post-start`: 백엔드 앱이 뜬 뒤 수동으로 실행하는 SQL입니다.

이 프로젝트는 `places` 같은 테이블을 Spring/Hibernate가 앱 시작 시점에 생성합니다. 그래서 `places` 테이블을 대상으로 하는 `ALTER TABLE`은 `mysql/init`에 넣으면 새 볼륨에서 실패할 수 있습니다.

## `post-start` 실행 순서

백엔드와 MySQL이 뜬 뒤, 관리자 CMD에서 번호 순으로 실행합니다. 전부 멱등이라 이미 적용된 항목은 아무 변경 없이 메시지만 출력합니다.

```cmd
docker exec -i heattrip-mysql sh -lc "mysql -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE" < mysql\post-start\01_add_places_search_fulltext.sql
docker exec -i heattrip-mysql sh -lc "mysql -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE" < mysql\post-start\02_add_places_emotion_columns.sql
docker exec -i heattrip-mysql sh -lc "mysql -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE" < mysql\post-start\03_add_journey_place_id.sql
docker exec -i heattrip-mysql sh -lc "mysql -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE" < mysql\post-start\04_users_social_account_model.sql
```

| 파일 | 무엇을 |
|:---|:---|
| `01_add_places_search_fulltext.sql` | `GET /api/explore/places/search`가 쓰는 `places.search_text` FULLTEXT 인덱스 |
| `02_add_places_emotion_columns.sql` | `places`의 감정 데이터 컬럼(`seed_emotion`·`ugc_emotion`·`ugc_count`) |
| `03_add_journey_place_id.sql` | 다이어리↔장소 연결용 `journey.place_id` |
| `04_users_social_account_model.sql` | 소셜 계정 모델 — `users.provider`·`social_id`·`role` 추가, 레거시 `username` 백필, `UNIQUE(provider, social_id)` (이슈 #7) |

### 04는 실패하면 멈춥니다 — 그게 정상입니다

`04`는 `ALTER TABLE`을 쓰기 때문에 트랜잭션으로 감쌀 수 없습니다(MySQL의 DDL은 암묵적 커밋을 일으킵니다). 대신 앞뒤로 관문이 하나씩 있습니다.

- **사전 점검**: 같은 `(provider, social_id)`를 갖게 될 행이 이미 여럿이면, `users`를 한 글자도 바꾸지 않고 중복 목록을 출력한 뒤 `ERROR 1644`로 중단합니다. 목록의 행을 병합·삭제한 뒤 다시 실행하면 됩니다.
- **사후 검증**: 컬럼 3개·`UNIQUE` 제약·백필이 전부 끝났는지 확인하고, 하나라도 빠졌으면 `ERROR 1644`로 실패합니다.

사후 검증이 필요한 이유는 `spring.jpa.hibernate.ddl-auto=validate`가 **UNIQUE 제약을 검사하지 않기 때문**입니다. 제약이 빠진 채 배포해도 앱은 멀쩡히 뜨고, 아무도 모르는 상태로 중복이 쌓입니다.

되돌리는 SQL(DOWN)은 `04_users_social_account_model.sql` 헤더 주석에 있습니다.
