# Prometheus 설정

이 폴더는 Backend EC2에서 Spring Boot Actuator 지표를 수집하기 위한 Prometheus 설정을 보관한다.

## 파일 구성

```text
prometheus/
  prometheus.yml
```

| 파일 | 역할 |
| --- | --- |
| `prometheus.yml` | Prometheus scrape 대상과 scrape interval 정의 |

## 수집 대상

현재 Prometheus는 두 대상을 수집한다.

| job | target | 설명 |
| --- | --- | --- |
| `heattrip-backend` | `app:8080/actuator/prometheus` | Spring Boot API metrics |
| `prometheus` | `prometheus:9090` | Prometheus 자기 자신 |

`app:8080`은 Docker Compose 내부 서비스명이다. 외부 public IP가 아니라 Compose network 안에서 접근한다.

## Spring Boot 쪽 전제

Prometheus가 Spring Boot 지표를 읽으려면 다음이 필요하다.

```gradle
implementation 'io.micrometer:micrometer-registry-prometheus'
```

그리고 `application.properties`에 다음 노출 설정이 있다.

```properties
management.endpoints.web.exposure.include=health,info,prometheus,metrics
management.endpoint.prometheus.enabled=true
management.prometheus.metrics.export.enabled=true
```

## 실행

Backend EC2에서 다음 명령으로 앱과 observability stack을 함께 실행한다.

```bash
docker compose \
  -f docker-compose.yml \
  -f docker-compose.observability.yml \
  up -d --build
```

## 보안 기준

Prometheus UI는 기본적으로 `127.0.0.1:9090`에만 열린다.

```yaml
ports:
  - "127.0.0.1:${PROMETHEUS_PORT:-9090}:9090"
```

EC2 public internet에 `9090`을 직접 열지 않는다. 필요하면 SSH tunnel을 사용한다.

```bash
ssh -L 9090:127.0.0.1:9090 ec2-user@<backend-ec2-public-ip>
```

## 부하 테스트에서 확인할 PromQL 예시

HTTP 요청량:

```promql
sum(rate(http_server_requests_seconds_count{application="heat-trip-backend"}[5m]))
```

HTTP p95 latency:

```promql
histogram_quantile(
  0.95,
  sum(rate(http_server_requests_seconds_bucket{application="heat-trip-backend"}[5m])) by (le)
)
```

HTTP 5xx 비율:

```promql
sum(rate(http_server_requests_seconds_count{application="heat-trip-backend",status=~"5.."}[5m]))
/
clamp_min(sum(rate(http_server_requests_seconds_count{application="heat-trip-backend"}[5m])), 0.001)
```

Hikari pending connection:

```promql
hikaricp_connections_pending{application="heat-trip-backend"}
```

