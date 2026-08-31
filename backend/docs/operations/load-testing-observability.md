# 부하 테스트 관측 구성

이 문서는 별도 Loader EC2에서 k6 부하 테스트를 실행할 때, Backend EC2에서 Prometheus/Grafana로 무엇을 관찰하는지 정리한다.

## 목표

부하 테스트의 목적은 단순히 "k6 결과가 몇 ms인지"만 보는 것이 아니다. Backend EC2, Spring Boot, MySQL, JVM, DB connection pool 중 어디에서 병목이 생기는지 같이 확인해야 한다.

이 구성에서는 역할을 이렇게 나눈다.

| 역할 | 위치 | 설명 |
| --- | --- | --- |
| Backend | Backend EC2 | Spring Boot API와 MySQL 실행 |
| Prometheus | Backend EC2 | Spring Boot `/actuator/prometheus` 지표 수집 |
| Grafana | Backend EC2 | Prometheus 지표 시각화 |
| k6 Loader | Loader EC2 | Backend API에 HTTP 부하 생성 |

## 실행 방법

Backend EC2에서 앱, MySQL, Prometheus, Grafana를 같이 띄운다.

```bash
docker compose \
  -f docker-compose.yml \
  -f docker-compose.observability.yml \
  up -d --build
```

기본 published port는 public 노출을 피하기 위해 localhost에만 바인딩된다.

| 서비스 | 기본 주소 | 이유 |
| --- | --- | --- |
| Backend | `127.0.0.1:8080` | 로컬/터널 중심 기본값 |
| Prometheus | `127.0.0.1:9090` | 외부 공개 불필요 |
| Grafana | `127.0.0.1:3000` | SSH tunnel 권장 |

Loader EC2에서 Backend EC2로 직접 부하를 주려면 Backend EC2의 `.env`에서 앱 포트만 staging 용도로 연다.

```text
APP_PUBLISHED_HOST=0.0.0.0
APP_PUBLISHED_PORT=8080
```

이때 EC2 보안그룹은 반드시 Loader EC2 또는 VPC private CIDR만 허용해야 한다.

## Grafana 접속

Grafana는 기본적으로 Backend EC2의 localhost에만 열린다. 로컬 PC에서 보려면 SSH tunnel을 사용한다.

```bash
ssh -L 3000:127.0.0.1:3000 ec2-user@<backend-ec2-public-ip>
```

그 다음 브라우저에서 접속한다.

```text
http://127.0.0.1:3000
```

계정 정보는 `.env` 또는 SSM에 저장한 backend `.env`에서 관리한다.

```text
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=<실제 비밀번호>
```

public repo에는 실제 비밀번호를 커밋하지 않는다.

## Prometheus 수집 대상

Prometheus는 Compose 내부 네트워크에서 Spring Boot 앱을 scrape한다.

```text
http://app:8080/actuator/prometheus
```

외부에서 `/actuator/prometheus`를 공개할 필요는 없다.

## 봐야 할 지표

부하 테스트 중에는 최소한 다음 지표를 본다.

| 지표 | 의미 |
| --- | --- |
| HTTP request rate | 초당 요청 수 |
| HTTP 5xx error ratio | 서버 오류 비율 |
| HTTP latency p95/p99 | 대부분의 사용자가 체감하는 지연 |
| Hikari active/idle/pending | DB connection pool 포화 여부 |
| JVM memory used | heap/non-heap 메모리 사용량 |
| process CPU | 앱 프로세스 CPU 사용량 |

### 채팅 커스텀 지표 (이슈 #80)

**이 저장소의 첫 커스텀 메트릭이다.** 이름 규약은 `chat/metrics/ChatMetrics.java` 의 javadoc 에 있고, 다음 도메인이 이 모양을 따라온다 — 도메인 접두 · 점 표기 · 카디널리티 낮은 태그만.

| 지표 (Prometheus 이름) | 의미 |
| --- | --- |
| `chat_message_sent_total{room_kind}` | 저장된 메시지. **없으면 "조용한 것" 과 "고장 난 것" 을 구분하지 못한다** — 둘 다 그래프가 평평하다 |
| `chat_poll_total{result="empty"\|"hit"}` | 폴링 응답. `http_server_requests` 로는 안 나온다 — 빈 응답도 새 메시지도 둘 다 200 이다 |
| `chat_seq_assign_seconds` | 방 단위 `room_seq` 발급. **경합이 보이는 유일한 자리** |

`room_kind` 는 방 종류다(`family` · `walk_crew`, ADR-0011). 태그가 없으면 "산책 크루 채팅이 죽었는데 가족 채팅은 멀쩡한 상태" 를 구분할 수 없다.

### 임계와 그때 할 행동

**경보가 아니라 사람이 보는 기준이다.** Prometheus 알림 규칙과 alertmanager 는 만들지 않았다 — 그건 M5 의 일이고, 여기서 같이 하면 채팅 변경이 운영 인프라 변경을 겸하게 되어 어느 쪽도 제대로 리뷰되지 않는다.

| 무엇 | 기준 | 그때 할 것 |
| --- | --- | --- |
| HTTP p95 | > 500ms 가 5분 지속 | `chat_seq_assign_seconds` 부터 본다. 거기가 벌어져 있으면 방 경합이다 |
| `hikaricp_connections_pending` | **> 0 이 1분 지속** | **롤백 조건이다. 채팅 배포를 되돌린다.** 커넥션을 기다리는 요청이 있다는 것은 풀이 이미 포화됐다는 뜻이고, 그 상태는 스스로 회복되지 않는다 |
| `chat_poll_total{result="empty"}` 비율 | > 0.95 | 한도를 낮추는 것이 아니라 **폴링 간격을 늘린다.** 비용은 DB 를 읽는 것이 아니라 아무것도 없는데 왕복하는 것이고, 간격은 클라이언트가 정한다 (#81) |

**롤백 조건을 문장으로 적으면 이렇다.** `hikaricp_connections_pending` 이 0보다 큰 상태로 1분을 넘기면 채팅 배포를 되돌린다. 지표를 더 보거나 원인을 찾은 뒤에 되돌리는 것이 아니라, 그 조건 하나로 되돌린다 — 커넥션 풀이 마르면 채팅과 무관한 경로까지 함께 죽기 때문이다.

## k6 결과와 같이 보는 방법

k6 결과에서 `http_req_duration p(95)`, `p(99)`, `http_req_failed`가 나빠졌다면 Grafana에서 같은 시간대를 본다.

판단 예시는 다음과 같다.

| 현상 | Grafana에서 같이 볼 것 | 의심 지점 |
| --- | --- | --- |
| p95/p99만 증가 | Hikari pending 증가 여부 | DB connection pool 부족 |
| 5xx 증가 | JVM memory, CPU, HTTP status | 앱 exception 또는 resource 부족 |
| Journey CRUD만 느림 | Hikari active/pending, MySQL 상태 | 쓰기 경합 또는 DDL lock |
| Explore search만 느림 | HTTP latency, DB pool | 검색 쿼리/인덱스 문제 |

## Rate Limit 주의

이 앱에는 애플리케이션 rate limit이 있다. Backend 자체 처리량을 보고 싶은 테스트에서는 staging에서 일시적으로 꺼야 한다.

```text
APP_SECURITY_RATE_LIMIT_ENABLED=false
```

반대로 public abuse defense를 검증하려는 테스트라면 rate limit을 켠 상태로 별도 시나리오를 만든다. 두 목적을 섞으면 성능 병목과 방어 정책을 구분하기 어렵다.

## 운영 DB DDL 테스트와의 관계

`k6/operations/mysql-ddl` 테스트는 k6가 DDL을 실행하는 구조가 아니다. k6는 Journey API read/write 트래픽만 만들고, 사람 또는 DBA가 staging MySQL 세션에서 `ALTER TABLE`을 실행한다.

이때 Grafana에서는 특히 다음을 본다.

- HTTP latency p95/p99 급증 여부
- HTTP 5xx 증가 여부
- Hikari pending 증가 여부
- JVM CPU/memory 급등 여부

DB 쪽에서는 별도로 `SHOW FULL PROCESSLIST`, `performance_schema.metadata_locks`를 확인한다.

