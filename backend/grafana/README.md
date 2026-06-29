# Grafana 설정

이 폴더는 Prometheus 지표를 시각화하기 위한 Grafana provisioning 파일과 dashboard JSON을 보관한다.

## 파일 구성

```text
grafana/
  dashboards/
    heat-trip-backend-overview.json
  provisioning/
    dashboards/
      dashboards.yml
    datasources/
      prometheus.yml
```

| 경로 | 역할 |
| --- | --- |
| `dashboards/` | Grafana dashboard JSON |
| `provisioning/datasources/` | Prometheus datasource 자동 등록 |
| `provisioning/dashboards/` | dashboard 파일 자동 로드 설정 |

## 실행 방식

Grafana는 `docker-compose.observability.yml`에서 실행된다.

```bash
docker compose \
  -f docker-compose.yml \
  -f docker-compose.observability.yml \
  up -d grafana
```

기본 포트는 public 노출 방지를 위해 localhost에만 바인딩한다.

```yaml
ports:
  - "127.0.0.1:${GRAFANA_PORT:-3000}:3000"
```

## 접속

Backend EC2에서 직접 볼 수 있다면:

```text
http://127.0.0.1:3000
```

로컬 PC에서 EC2의 Grafana를 보려면 SSH tunnel을 사용한다.

```bash
ssh -L 3000:127.0.0.1:3000 ec2-user@<backend-ec2-public-ip>
```

## 계정 정보

Grafana admin 계정은 `.env` 또는 SSM에 저장한 backend `.env`에서 주입한다.

```text
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=<실제 비밀번호>
```

public repo에는 실제 비밀번호를 커밋하지 않는다. `.env.example`에는 placeholder만 둔다.

## 기본 dashboard

현재 dashboard는 `Heat Trip Backend Overview` 하나다.

주요 패널:

- HTTP Request Rate
- HTTP 5xx Error Ratio
- HTTP Latency p95/p99
- Hikari Connections
- JVM Memory Used
- Process CPU

## 부하 테스트에서 보는 순서

1. k6 실행 시간대를 확인한다.
2. HTTP latency p95/p99가 튀는지 본다.
3. 같은 시간에 5xx ratio가 증가했는지 본다.
4. Hikari pending이 증가하면 DB connection pool 병목을 의심한다.
5. CPU/memory가 같이 증가하면 JVM 또는 EC2 size 문제를 의심한다.

