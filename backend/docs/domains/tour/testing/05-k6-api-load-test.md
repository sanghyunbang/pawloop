# 5. k6 기반 실제 API 부하 테스트

JUnit 동시성 테스트는 DB와 service 레벨의 문제를 보기 좋다. 하지만 실제 사용자는 HTTP API를 호출한다.

k6 테스트는 애플리케이션을 실제로 띄운 뒤 `/api/explore/places` 같은 API를 부하 상황에서 호출해 사용자가 체감하는 응답 시간을 측정하는 테스트다.

## 언제 k6가 필요한가

다음 질문에 답하고 싶을 때 k6가 유용하다.

- 실제 HTTP endpoint 기준 p95/p99 latency는 얼마인가?
- Spring MVC, Security, JSON serialization까지 포함하면 얼마나 느려지는가?
- import 중 API 응답 시간이 얼마나 증가하는가?
- 동시 사용자 수가 늘면 어느 지점에서 timeout이 발생하는가?
- connection pool, DB, 애플리케이션 중 어디가 병목인가?

## JUnit 테스트와 k6 테스트의 차이

| 구분 | JUnit 동시성 테스트 | k6 부하 테스트 |
|---|---|---|
| 호출 대상 | service/repository | 실제 HTTP API |
| 속도 | 빠름 | 상대적으로 느림 |
| 원인 분석 | 쉬움 | 여러 계층이 섞임 |
| 사용자 체감 | 간접적 | 직접적 |
| CI 적용 | 가능 | 별도 환경 권장 |

추천 순서는 JUnit으로 병목 후보를 좁힌 뒤 k6로 실제 API 기준 수치를 확인하는 것이다.

## 준비

로컬에서 애플리케이션을 실행한다.

```bash
./gradlew bootRun
```

Windows PowerShell:

```powershell
.\gradlew.bat bootRun
```

테스트 DB에는 충분한 `places` 데이터가 있어야 한다. 최소 1만 건 이상을 추천한다.

## Baseline API 부하 테스트

파일 예시: `k6/explore-places-baseline.js`

```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 10 },
    { duration: '1m', target: 10 },
    { duration: '30s', target: 0 },
  ],
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<500', 'p(99)<1500'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

export default function () {
  const page = Math.floor(Math.random() * 20);
  const res = http.get(`${BASE_URL}/api/explore/places?page=${page}&size=20`);

  check(res, {
    'status is 200': (r) => r.status === 200,
    'body is not empty': (r) => r.body && r.body.length > 0,
  });

  sleep(0.2);
}
```

실행:

```bash
k6 run k6/explore-places-baseline.js
```

PowerShell:

```powershell
$env:BASE_URL="http://localhost:8080"
k6 run k6/explore-places-baseline.js
```

## Cursor API 부하 테스트

파일 예시: `k6/explore-places-scroll.js`

```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 20,
  duration: '2m',
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<700', 'p(99)<2000'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

export default function () {
  let cursor = '';

  for (let i = 0; i < 5; i++) {
    const url = cursor
      ? `${BASE_URL}/api/explore/places/scroll?size=20&cursor=${encodeURIComponent(cursor)}`
      : `${BASE_URL}/api/explore/places/scroll?size=20`;

    const res = http.get(url);

    check(res, {
      'status is 200': (r) => r.status === 200,
    });

    if (res.status !== 200) {
      break;
    }

    const body = JSON.parse(res.body);
    cursor = body.nextCursor;

    if (!cursor) {
      break;
    }

    sleep(0.1);
  }
}
```

## Import 중 API 부하 테스트

이 시나리오는 두 프로세스를 동시에 실행한다.

1. k6가 read API를 계속 호출한다.
2. 별도 터미널에서 import job을 실행한다.

현재 프로젝트에서는 Tour import scheduler/controller가 비활성화되어 있다. 따라서 이 테스트를 실제로 하려면 먼저 import를 실행할 수 있는 방법이 필요하다.

선택지:

- 임시 admin controller 추가
- local profile에서만 동작하는 runner 추가
- 테스트용 command endpoint 추가
- JUnit에서 import를 실행하고 k6는 HTTP read만 수행

운영 코드에 바로 admin endpoint를 열기보다는, local/test profile 전용으로 제한하는 것이 좋다.

## import 중 k6 실행 절차 예시

터미널 1:

```bash
./gradlew bootRun
```

터미널 2:

```bash
k6 run k6/explore-places-baseline.js
```

터미널 3:

```bash
# 예: local/test 전용 import endpoint가 있다고 가정
curl -X POST http://localhost:8080/internal/test/tour/import
```

그 다음 k6 결과에서 import 시작 전후의 p95/p99 변화를 본다.

## k6 결과에서 볼 값

k6는 실행 후 이런 지표를 보여준다.

```text
http_req_duration..............: avg=45ms min=5ms med=20ms max=1.8s p(90)=80ms p(95)=220ms
http_req_failed................: 0.00%
http_reqs......................: 12000
iterations.....................: 12000
```

중요한 값:

- `http_req_duration avg`
- `http_req_duration p(95)`
- `http_req_duration p(99)` 또는 threshold
- `http_req_failed`
- `http_reqs`

## 결과 표 예시

| 시나리오 | VUs | duration | 요청 수 | 실패율 | avg | p95 | p99 | max |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| read only | 20 | 2m | 12,000 | 0% | 45ms | 180ms | 500ms | 1.2s |
| read + import | 20 | 2m | 11,500 | 0.2% | 120ms | 900ms | 2.8s | 6.0s |
| read + snapshot rebuild | 20 | 2m | 9,800 | 1.5% | 350ms | 2.5s | 8.0s | timeout |

## threshold 설정 방법

threshold는 "이 정도는 넘어가면 실패로 보겠다"는 기준이다.

예시:

```javascript
thresholds: {
  http_req_failed: ['rate<0.01'],
  http_req_duration: ['p(95)<500', 'p(99)<1500'],
}
```

의미:

- 실패율은 1% 미만이어야 한다.
- p95는 500ms 미만이어야 한다.
- p99는 1500ms 미만이어야 한다.

초기에는 너무 엄격하게 잡지 말고 현재 상태를 측정한 뒤 목표치를 정한다.

## 병목 해석

### k6 p95/p99가 높고 JUnit repository 테스트도 높다

DB write/read 동시성 또는 쿼리 성능 문제가 유력하다.

### JUnit repository 테스트는 괜찮은데 k6만 느리다

Controller, Security, JSON serialization, 네트워크, thread pool, connection pool 문제를 본다.

### 실패율이 증가한다

다음을 확인한다.

- DB connection pool 고갈
- lock wait timeout
- HTTP server thread 고갈
- security filter 비용
- query timeout
- JVM GC

## 운영에 가까운 테스트를 위한 추가 관찰

가능하면 부하 테스트 중 아래도 같이 본다.

- Spring Actuator metrics
- Hikari connection pool active/idle/pending
- MySQL processlist
- MySQL slow query log
- CPU 사용률
- memory/GC

예시로 MySQL에서 확인할 수 있는 것:

```sql
SHOW FULL PROCESSLIST;
SHOW ENGINE INNODB STATUS;
```

단, 이 SQL은 실행 시점의 상태만 보여주므로 반복 측정이 필요하다.

## 결론

k6는 마지막 단계의 테스트다. 처음부터 k6로만 보면 병목 원인을 찾기 어렵다.

권장 흐름:

1. JUnit 단위 테스트로 매핑/정제 검증
2. JUnit MySQL 통합 테스트로 DB 동시성 검증
3. import/snapshot 중 read latency 측정
4. k6로 실제 HTTP API 기준 사용자 체감 latency 확인
