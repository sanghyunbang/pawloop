# Curation Load Tests

## 목적

추천 API 중 LLM 토큰을 소비하지 않는 경로를 먼저 검증한다.

`/api/curation/recommend`는 `cat3Filter`가 비어 있으면 Python recommender/LLM 경로를 탄다. 반대로 `cat3Filter`가 있으면 현재 서비스 코드에서 LLM을 건너뛰고 내부 scoring만 수행한다. 그래서 기본 부하 테스트는 `cat3Filter`를 넣는다.

## 대상 API

| API | LLM 호출 여부 | 비고 |
| --- | --- | --- |
| `POST /api/curation/rank` | 없음 | 내부 scoring |
| `POST /api/curation/categories` | 없음 | category aggregation |
| `POST /api/curation/recommend` with `cat3Filter` | 없음 | orchestration + scoring, LLM skip |

## 실행

```bash
BASE_URL="http://<BACKEND_EC2_PRIVATE_IP>:8080" \
VUS=10 \
DURATION=5m \
CAT3_FILTER="A02010100,A02020700" \
k6 run k6/domains/curation/curation-non-llm-baseline.js
```

## 실제 LLM 연동 테스트 방향

실제 LLM을 대량으로 때리는 부하 테스트는 비용과 rate limit 때문에 기본 k6에 넣지 않는다. 필요하면 다음 중 하나로 분리한다.

1. Python recommender를 stub 서버로 바꾸고 `/recommend` 응답을 고정한다.
2. 실제 Python 서버는 쓰되 OpenAI 호출을 mock/fake provider로 치환한다.
3. 운영 전 smoke test만 낮은 VU와 짧은 duration으로 수행한다.

실제 LLM 호출을 포함하는 테스트를 추가할 때는 `curation-llm-smoke.js`처럼 이름에 `llm`과 `smoke`를 명시하고, 기본 README 실행 예시에는 넣지 않는다.

