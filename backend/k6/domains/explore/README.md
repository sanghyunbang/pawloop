# Explore Load Tests

## 목적

장소 조회 API의 기본 읽기 성능을 본다. 로그인, 외부 API, LLM 호출이 없어서 Backend EC2와 MySQL의 read path baseline으로 쓰기 좋다.

## 대상 API

| API | 이유 |
| --- | --- |
| `GET /api/explore/places?page=&size=` | 일반 목록 조회. pagination + count 비용 확인 |
| `GET /api/explore/places/scroll?size=&cursor=` | 무한 스크롤 조회. cursor path 확인 |
| `GET /api/explore/places/search?q=&page=&size=` | 검색 조건 path 확인 |
| `GET /api/explore/places/{id}` | 상세 조회 latency 확인 |

## 실행

```bash
BASE_URL="http://<BACKEND_EC2_PRIVATE_IP>:8080" \
VUS=30 \
DURATION=10m \
k6 run k6/domains/explore/explore-read-baseline.js
```

## 해석

먼저 이 테스트로 read baseline을 잡고, 이후 Journey CRUD나 DDL 테스트에서 p95/p99가 얼마나 나빠지는지 비교한다.

