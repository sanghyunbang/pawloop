# MySQL DDL Impact Tests

## 목적

운영과 비슷한 읽기/쓰기 트래픽이 있는 상태에서 `Journey.body` 같은 컬럼 변경이 API 지연, 실패, metadata lock 대기를 만드는지 staging에서 확인한다.

이 테스트는 k6가 DDL을 실행하는 테스트가 아니다. k6는 트래픽만 만들고, DBA/개발자가 별도 MySQL 세션에서 ALTER를 실행하며 영향을 관찰한다.

## 절대 원칙

- 운영 DB에서 바로 실행하지 않는다.
- 운영과 같은 MySQL major version, schema, index, 데이터량에 가까운 staging에서 먼저 실행한다.
- `VARCHAR(255) -> TEXT` 같은 타입 변경은 직접 운영 ALTER 전에 온라인 가능 여부를 먼저 확인한다.
- k6 결과만 보지 말고 MySQL processlist, metadata lock, slow query, DB CPU/IO를 같이 본다.

## 사전 확인

테이블/컬럼 이름은 실제 DB에서 먼저 확인한다.

```sql
SHOW CREATE TABLE journey;
SHOW FULL COLUMNS FROM journey LIKE 'body';
SHOW INDEX FROM journey;
```

현재 entity는 `Journey.body`에 별도 TEXT 정의가 없으므로, DB가 자동 생성된 환경에서는 `VARCHAR(255)`일 수 있다.

## 1. 기준 부하 실행

DDL 전 정상 부하 기준을 잡는다.

```bash
BASE_URL="http://<BACKEND_EC2_PRIVATE_IP>:8080" \
ACCESS_TOKEN="<jwt>" \
VUS=20 \
DURATION=15m \
BODY_CHARS=180 \
k6 run k6/operations/mysql-ddl/journey-body-ddl-traffic.js
```

## 2. 온라인 변경 가능성 probe

k6가 도는 중 MySQL에서 먼저 실패를 기대하고 온라인 변경 가능성을 확인한다.

```sql
SET SESSION lock_wait_timeout = 5;

ALTER TABLE journey
  MODIFY COLUMN body TEXT,
  ALGORITHM=INPLACE,
  LOCK=NONE;
```

이 SQL이 실패하면 "운영 중 무중단 직접 MODIFY는 어렵다"는 신호로 본다. 그 상태에서 운영에 직접 `ALTER TABLE ... MODIFY COLUMN body TEXT`를 치면 쓰기 대기와 API timeout 위험이 있다.

## 3. staging에서만 직접 ALTER 영향 확인

위 probe가 실패했을 때 장애 양상을 알고 싶다면 staging에서만 COPY 방식 변경을 실험한다.

```sql
SET SESSION lock_wait_timeout = 5;

ALTER TABLE journey
  MODIFY COLUMN body TEXT,
  ALGORITHM=COPY;
```

이때 k6에서 볼 것:

- `http_req_failed` 증가
- `journey_create`, `journey_update`, `journey_list` p95/p99 급증
- timeout 또는 5xx 증가

MySQL에서 같이 볼 것:

```sql
SHOW FULL PROCESSLIST;
```

```sql
SELECT
  OBJECT_TYPE,
  OBJECT_SCHEMA,
  OBJECT_NAME,
  LOCK_TYPE,
  LOCK_STATUS,
  OWNER_THREAD_ID
FROM performance_schema.metadata_locks
WHERE OBJECT_NAME = 'journey';
```

`Waiting for table metadata lock` 또는 `LOCK_STATUS = 'PENDING'`이 쌓이면 운영 직접 ALTER는 위험하다.

## 4. safer migration 비교 테스트

직접 MODIFY 대신 새 컬럼을 추가하는 방식도 staging에서 비교한다.

```sql
ALTER TABLE journey
  ADD COLUMN body_text TEXT NULL,
  ALGORITHM=INSTANT;
```

그 다음 애플리케이션을 dual-write로 바꾸는 것이 안전한 운영 전환 방식이다.

- 새 글 저장: `body`, `body_text` 둘 다 저장
- 조회: `COALESCE(body_text, body)`
- 기존 데이터: id range 기준 chunk backfill
- 최종 점검 시간: 컬럼명 rename/drop 정리

## 5. TEXT 변경 후 긴 본문 저장 검증

DDL이 끝난 뒤 긴 본문 저장이 실제로 되는지 확인한다.

```bash
BASE_URL="http://<BACKEND_EC2_PRIVATE_IP>:8080" \
ACCESS_TOKEN="<jwt>" \
VUS=5 \
DURATION=2m \
BODY_CHARS=2000 \
k6 run k6/operations/mysql-ddl/journey-body-ddl-traffic.js
```

이 단계에서 실패하면 DB 컬럼 변경, JPA schema, request validation, MySQL row size/charset 쪽을 다시 확인한다.

