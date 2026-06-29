# Journey Load Tests

## 목적

`/journeys/v2`의 여행 글 CRUD를 실제 JWT 인증 상태에서 검증한다. 사용자가 요청한 "글 CRUD" 부하 테스트의 기본 시나리오다.

## 대상 API

| API | 행위 |
| --- | --- |
| `POST /journeys/v2/entries` | 글 생성 |
| `GET /journeys/v2/entries` | 내 글 목록 조회 |
| `GET /journeys/v2/entries/{id}` | 글 상세 조회 |
| `PUT /journeys/v2/entries/{id}` | 글 수정 |
| `GET /journeys/v2/stats` | 통계 조회 |
| `DELETE /journeys/v2/entries/{id}` | 글 삭제 |

## 실행

```bash
BASE_URL="http://<BACKEND_EC2_PRIVATE_IP>:8080" \
ACCESS_TOKEN="<jwt>" \
VUS=20 \
DURATION=10m \
k6 run k6/domains/journey/journey-crud.js
```

`ACCESS_TOKEN`이 없으면 스크립트는 `TEST_EMAIL`, `TEST_PASSWORD`로 signup/login을 시도한다. staging에서 auth endpoint 접근이 막혀 있으면 미리 토큰을 발급해서 `ACCESS_TOKEN`을 넣는다.

## body 길이

`Journey.body`는 현재 JPA entity에서 `String body`이고 별도 `@Column(columnDefinition = "TEXT")`가 없다. DB가 Hibernate 기본값으로 만들어졌다면 `VARCHAR(255)`일 수 있으므로, migration 전에는 `BODY_CHARS`를 255 이하로 둔다.

```bash
BODY_CHARS=180 k6 run k6/domains/journey/journey-crud.js
```

TEXT migration 이후에는 긴 본문 저장 검증용으로 값을 늘릴 수 있다.

```bash
BODY_CHARS=2000 k6 run k6/domains/journey/journey-crud.js
```

