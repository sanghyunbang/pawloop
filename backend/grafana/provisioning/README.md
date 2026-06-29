# Grafana 프로비저닝

이 폴더는 Grafana가 시작될 때 datasource와 dashboard를 자동으로 등록하기 위한 설정이다.

## 구조

```text
grafana/provisioning/
  datasources/
    prometheus.yml
  dashboards/
    dashboards.yml
```

## Datasource

`datasources/prometheus.yml`은 Grafana가 Prometheus에 연결할 수 있게 한다.

```text
http://prometheus:9090
```

이 주소는 Docker Compose 내부 서비스명이다. EC2 public IP가 아니다.

## Dashboard Provider

`dashboards/dashboards.yml`은 `/var/lib/grafana/dashboards` 경로의 JSON dashboard를 Grafana에 등록한다.

Compose에서는 다음처럼 mount한다.

```yaml
volumes:
  - ./grafana/dashboards:/var/lib/grafana/dashboards:ro
```

## 주의

- provisioning 파일에는 실제 비밀번호를 넣지 않는다.
- Grafana admin password는 `.env` 또는 SSM Parameter Store로 주입한다.
- datasource URL은 Docker 내부 주소만 사용한다.
