# Heat Trip k6 Load Tests

이 디렉터리는 Loader EC2에서 실행할 k6 부하 테스트를 보관한다. 백엔드 리포지토리에 같이 두는 이유는 API 경로, 요청 바디, 인증 방식 변경과 부하 테스트를 같은 버전으로 관리하기 위해서다.

## 디렉터리 규칙

```text
k6/
  lib/                    # 공통 설정, 인증, JSON helper
  domains/
    explore/              # 공개 장소 조회 API
    journey/              # JWT 기반 여행 글 CRUD API
    curation/             # 추천/큐레이션 API. 기본 테스트는 LLM 호출 제외
  operations/
    mysql-ddl/            # 운영성 검증. DDL 잠금/지연 영향 확인용
```

새 테스트는 먼저 도메인 기준으로 `k6/domains/<domain>/` 아래에 둔다. 특정 장애 대응, DB migration, cutover 검증처럼 일회성 운영 목적이 강하면 `k6/operations/<topic>/` 아래에 둔다.

## Loader EC2 사용법

전체 repo를 clone해도 되고, k6만 sparse checkout해도 된다.

```bash
git clone <repo-url> heat_trip_backend
cd heat_trip_backend

export BASE_URL="http://<BACKEND_EC2_PRIVATE_IP>:8080"
k6 run k6/domains/explore/explore-read-baseline.js
```

k6 디렉터리만 받고 싶으면:

```bash
git clone --filter=blob:none --sparse <repo-url> heat_trip_load
cd heat_trip_load
git sparse-checkout set k6

export BASE_URL="http://<BACKEND_EC2_PRIVATE_IP>:8080"
k6 run k6/domains/explore/explore-read-baseline.js
```

## 공통 환경변수

| 변수 | 기본값 | 설명 |
| --- | --- | --- |
| `BASE_URL` | `http://localhost:8080` | Backend EC2 API 주소 |
| `VUS` | 스크립트별 기본값 | 동시 가상 사용자 수 |
| `DURATION` | 스크립트별 기본값 | 테스트 지속 시간 |
| `SLEEP_SECONDS` | 스크립트별 기본값 | 반복 사이 대기 시간 |
| `ACCESS_TOKEN` | 없음 | Journey처럼 JWT가 필요한 API에 사용할 토큰 |
| `TEST_EMAIL` | 자동 생성 | `ACCESS_TOKEN`이 없을 때 signup/login에 쓸 테스트 계정 |
| `TEST_PASSWORD` | `Loadtest1234!` | 테스트 계정 비밀번호 |

## Backend rate limit 주의

이 애플리케이션은 `APP_SECURITY_RATE_LIMIT_ENABLED` 기반 rate limit을 갖고 있다. Backend 자체 처리량을 보고 싶으면 staging에서 일시적으로 rate limit을 끄고 테스트한다.

```bash
APP_SECURITY_RATE_LIMIT_ENABLED=false
```

반대로 public 방어 정책을 검증하는 목적이면 rate limit을 켠 상태에서 별도 시나리오로 분리한다.

Journey 테스트는 가장 안정적으로는 미리 테스트 계정을 만들고 토큰을 넣어서 실행한다.

```bash
export BASE_URL="http://<BACKEND_EC2_PRIVATE_IP>:8080"
export ACCESS_TOKEN="<jwt>"
k6 run k6/domains/journey/journey-crud.js
```

또는 staging에서 `/auth/signup`, `/auth/login`이 열려 있으면:

```bash
export BASE_URL="http://<BACKEND_EC2_PRIVATE_IP>:8080"
export TEST_EMAIL="loadtest@example.com"
export TEST_PASSWORD="Loadtest1234!"
k6 run k6/domains/journey/journey-crud.js
```

## 현재 포함된 테스트

| 파일 | 목적 | 주요 API |
| --- | --- | --- |
| `domains/explore/explore-read-baseline.js` | 공개 장소 조회 baseline | `GET /api/explore/places`, `/scroll`, `/search`, `/{id}` |
| `domains/journey/journey-crud.js` | JWT 기반 여행 글 CRUD | `POST/GET/PUT/DELETE /journeys/v2/entries` |
| `domains/curation/curation-non-llm-baseline.js` | LLM 토큰 소비 없는 추천 경로 | `POST /api/curation/rank`, `/categories`, `/recommend` with `cat3Filter` |
| `operations/mysql-ddl/journey-body-ddl-traffic.js` | Journey body 컬럼 변경 중 읽기/쓰기 영향 확인 | Journey CRUD mixed traffic |

## 의도적으로 제외한 테스트

- 실제 LLM 호출 대량 부하: OpenAI/Python recommender 비용과 rate limit 때문에 기본 세트에서 제외한다.
- S3 이미지 업로드 대량 부하: 저장 비용과 외부 서비스 영향이 있어서 별도 media 전용 테스트로 분리한다.
- 운영 DB 직접 DDL: k6는 트래픽만 만들고 DDL은 staging MySQL 세션에서 사람이 실행한다.

## 기본 실행 예시

Explore 조회:

```bash
BASE_URL="http://<BACKEND_EC2_PRIVATE_IP>:8080" \
VUS=30 \
DURATION=10m \
k6 run k6/domains/explore/explore-read-baseline.js
```

Journey CRUD:

```bash
BASE_URL="http://<BACKEND_EC2_PRIVATE_IP>:8080" \
ACCESS_TOKEN="<jwt>" \
VUS=20 \
DURATION=10m \
k6 run k6/domains/journey/journey-crud.js
```

LLM 호출 없는 curation:

```bash
BASE_URL="http://<BACKEND_EC2_PRIVATE_IP>:8080" \
VUS=10 \
DURATION=5m \
k6 run k6/domains/curation/curation-non-llm-baseline.js
```

MySQL DDL 영향 테스트는 반드시 staging에서만 실행한다.

```bash
BASE_URL="http://<BACKEND_EC2_PRIVATE_IP>:8080" \
ACCESS_TOKEN="<jwt>" \
VUS=20 \
DURATION=15m \
BODY_CHARS=180 \
k6 run k6/operations/mysql-ddl/journey-body-ddl-traffic.js
```
