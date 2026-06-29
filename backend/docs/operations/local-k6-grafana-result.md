# 로컬 k6 결과를 Grafana에서 보는 방법

이 문서는 같은 PC에서 Docker Compose로 백엔드, MySQL, Prometheus, Grafana, k6를 같이 띄워 smoke test 결과를 화면으로 확인하는 절차입니다.

## 1. Prometheus remote write 켜기

k6 자체 지표를 Prometheus에 저장하려면 Prometheus가 remote write를 받을 수 있어야 합니다.

```cmd
docker compose --env-file .env -f docker-compose.yml -f docker-compose.observability.yml up -d prometheus grafana
```

`docker-compose.observability.yml`에는 다음 옵션이 들어 있습니다.

```yaml
--web.enable-remote-write-receiver
```

이 옵션이 있어야 k6의 `experimental-prometheus-rw` output이 Prometheus로 지표를 보낼 수 있습니다.

## 2. k6를 Prometheus 출력으로 실행

Compose one-off service로 실행합니다.

```cmd
docker compose --env-file .env -f docker-compose.yml -f docker-compose.observability.yml -f docker-compose.k6.yml run --rm k6-explore-smoke
```

테스트 ID를 바꾸고 싶으면 다음처럼 실행합니다.

```cmd
set K6_TEST_ID=local-explore-smoke-001
set K6_DURATION=1m
set K6_VUS=3
docker compose --env-file .env -f docker-compose.yml -f docker-compose.observability.yml -f docker-compose.k6.yml run --rm k6-explore-smoke
```

## 3. Grafana에서 보기

브라우저에서 접속합니다.

```text
http://127.0.0.1:3000
```

로그인 정보는 `.env` 또는 `.env.example`의 값을 따릅니다.

```text
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=change-me-grafana-password
```

접속 후 다음 대시보드를 엽니다.

```text
Dashboards -> Heat Trip -> Heat Trip k6 Load Test
```

여기서 보는 항목:

- k6 요청 처리량
- k6 실패율
- k6 응답시간 p95/p99
- 백엔드 응답시간 p95/p99
- k6 VU
- k6 check 통과량

기존 백엔드 대시보드는 다음입니다.

```text
Dashboards -> Heat Trip -> Heat Trip Backend Overview
```

## 4. Prometheus에서 직접 확인

브라우저에서 접속합니다.

```text
http://127.0.0.1:9090
```

대표 쿼리:

```promql
sum(rate(k6_http_reqs_total[1m])) by (scenario)
```

```promql
avg(k6_http_req_failed_rate) by (scenario)
```

```promql
sum(rate(http_server_requests_seconds_count{application="heat-trip-backend"}[1m])) by (uri,status)
```

```promql
histogram_quantile(0.95, sum(rate(http_server_requests_seconds_bucket{application="heat-trip-backend"}[1m])) by (le,uri))
```

## 5. 주의할 점

k6를 그냥 `k6 run script.js`로 실행하면 결과는 터미널에만 출력됩니다.

Grafana에서 k6 자체 결과를 보려면 반드시 다음 output을 사용해야 합니다.

```text
-o experimental-prometheus-rw
```

백엔드가 받은 요청 결과만 보면 Prometheus scrape만으로 충분하지만, k6의 VU, check, failed rate, k6 기준 latency를 보려면 remote write가 필요합니다.
