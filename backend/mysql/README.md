# MySQL 로컬 스키마 보정

이 디렉터리는 Docker Compose로 띄운 로컬 MySQL에 필요한 SQL을 보관합니다.

## `init`와 `post-start` 차이

- `mysql/init`: MySQL 컨테이너가 새 볼륨으로 처음 초기화될 때만 실행됩니다.
- `mysql/post-start`: 백엔드 앱이 뜬 뒤 수동으로 실행하는 SQL입니다.

이 프로젝트는 `places` 같은 테이블을 Spring/Hibernate가 앱 시작 시점에 생성합니다. 그래서 `places` 테이블을 대상으로 하는 `ALTER TABLE`은 `mysql/init`에 넣으면 새 볼륨에서 실패할 수 있습니다.

## 로컬 검색 API용 FULLTEXT 인덱스

`GET /api/explore/places/search`는 `places.search_text`에 FULLTEXT 인덱스가 있어야 정상 동작합니다.

관리자 CMD에서 백엔드와 MySQL이 뜬 뒤 실행합니다.

```cmd
docker exec -i heattrip-mysql sh -lc "mysql -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE" < mysql\post-start\01_add_places_search_fulltext.sql
```

이미 인덱스가 있으면 아무 변경 없이 메시지만 출력합니다.
