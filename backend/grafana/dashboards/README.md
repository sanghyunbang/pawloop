# Grafana 대시보드

이 폴더는 Grafana가 자동으로 읽는 dashboard JSON을 보관한다.

## 현재 dashboard

| 파일 | 설명 |
| --- | --- |
| `heat-trip-backend-overview.json` | Spring Boot API 부하 테스트 관측용 dashboard |

## 수정 방법

1. Grafana UI에서 dashboard를 수정한다.
2. JSON model을 export한다.
3. 이 폴더의 JSON 파일을 교체한다.
4. public repo에 들어가도 되는지 확인한다.

dashboard JSON에는 보통 secret이 들어가지 않지만, datasource URL이나 annotation에 내부 주소가 들어갈 수 있으므로 커밋 전 확인한다.

## 패널 추가 기준

부하 테스트 관점에서 의미 있는 패널만 추가한다.

- HTTP endpoint별 latency
- HTTP status별 error ratio
- Hikari connection pool
- JVM memory/GC
- process CPU
- 필요 시 MySQL exporter 지표

현재는 MySQL exporter를 붙이지 않았기 때문에 MySQL 내부 지표는 dashboard에 없다. DDL 테스트에서는 MySQL 세션에서 `SHOW FULL PROCESSLIST`, `performance_schema.metadata_locks`를 별도로 확인한다.
