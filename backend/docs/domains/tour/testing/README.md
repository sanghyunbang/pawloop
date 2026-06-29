# Tour 데이터 파이프라인 테스트 구조

이 문서는 Tour API 기반 데이터 파이프라인을 어떤 관점으로 테스트할지 정리한다.

목표는 단순히 "테스트가 통과한다"가 아니라, 다음 질문에 수치로 답하는 것이다.

- 외부 API 응답을 내부 모델로 안전하게 변환하는가?
- 대량 저장 중 기존 조회 API가 실패하지 않는가?
- import 중 조회 지연 시간이 얼마나 증가하는가?
- snapshot/search_text 전체 update가 읽기 API에 어느 정도 영향을 주는가?
- 실제 HTTP 트래픽을 받는 상황에서도 병목이 어디서 발생하는가?

## 테스트 계층

Tour 관련 테스트는 한 종류로 끝내기 어렵다. 검증하려는 문제가 서로 다르기 때문이다.

| 단계 | 문서 | 목적 |
|---|---|---|
| 1 | `01-tour-unit-tests.md` | DTO 매핑, 정제, 파싱 같은 순수 로직 검증 |
| 2 | `02-mysql-concurrency-integration-test.md` | MySQL/InnoDB 기준 read/write 동시성 검증 |
| 3 | `03-import-read-latency-test.md` | import 중 read latency 변화를 수치화 |
| 4 | `04-snapshot-search-text-update-test.md` | snapshot/search_text 전체 update 영향 측정 |
| 5 | `05-k6-api-load-test.md` | 실제 HTTP API 부하 테스트 |

## 왜 단위 테스트만으로 부족한가

단위 테스트는 빠르고 안정적이지만 DB lock, transaction isolation, MVCC, 커넥션 풀 고갈 같은 문제를 보여주지 못한다.

예를 들어 `PlaceMapper.toEntity()`가 올바르게 매핑되는지는 단위 테스트로 충분하다. 하지만 `PlaceService.saveInBatches()`가 실행되는 동안 `/api/explore/places` 조회가 느려지는지, 실패하는지, 부분 갱신 상태가 노출되는지는 실제 DB 기반 테스트가 필요하다.

## 왜 H2보다 MySQL이 필요한가

동시성 테스트는 실제 운영 DB와 같은 종류의 DB에서 보는 것이 중요하다.

현재 프로젝트는 MySQL/InnoDB 사용을 전제로 한다. InnoDB는 MVCC, row lock, transaction isolation, gap lock 등 MySQL 고유의 동작이 있다. H2는 빠른 테스트에는 좋지만, MySQL의 lock 동작과 완전히 같지 않다.

따라서 동시성이나 latency 수치를 보여주려면 다음 중 하나를 추천한다.

- 로컬 Docker MySQL
- Testcontainers MySQL

학습과 재현성을 생각하면 Testcontainers MySQL이 가장 좋다.

## 권장 테스트 순서

1. 단위 테스트로 정제/매핑 안정성 확인
2. MySQL 통합 테스트 환경 구성
3. 작은 데이터셋으로 동시성 테스트 구조 확인
4. 데이터 크기를 늘려 import 중 read latency 측정
5. snapshot/search_text 전체 update 영향 측정
6. 필요한 경우 k6로 실제 HTTP 부하 테스트 수행

## 측정 지표

수치로 보여줄 때는 최소한 아래 지표를 기록한다.

| 지표 | 의미 |
|---|---|
| read success count | 조회 성공 수 |
| read failure count | 조회 실패 수 |
| avg latency | 평균 응답 시간 |
| p95 latency | 느린 상위 5% 요청의 경계 |
| p99 latency | 느린 상위 1% 요청의 경계 |
| max latency | 최악 응답 시간 |
| import duration | import 전체 소요 시간 |
| timeout count | timeout 발생 수 |
| row count before/after | 데이터 수 변화 |

평균만 보면 위험하다. 대부분의 요청은 빠르지만 일부 요청이 매우 느린 경우 평균은 문제를 숨길 수 있다. 그래서 p95/p99를 같이 봐야 한다.

## 테스트할 때 주의할 점

- 외부 Tour API를 실제로 호출하지 말고 테스트용 `Place` 데이터를 직접 생성한다.
- 외부 API는 네트워크, quota, 응답 속도 변수가 있어서 동시성 원인 분석을 흐린다.
- latency 테스트는 같은 머신에서 여러 번 반복하고 평균적인 경향을 본다.
- 테스트 데이터 수는 처음에는 1천 건, 이후 1만 건, 5만 건처럼 늘린다.
- 결과는 "문제 있음/없음"보다 "어떤 상황에서 얼마나 느려지는가"로 정리한다.

## 결과 표 예시

| 시나리오 | read 요청 | 실패 | avg | p95 | p99 | max | import time |
|---|---:|---:|---:|---:|---:|---:|---:|
| read only | 10,000 | 0 | 35ms | 80ms | 140ms | 300ms | - |
| read + import | 10,000 | 0 | 60ms | 220ms | 900ms | 2.4s | 48s |
| read + snapshot rebuild | 10,000 | 3 | 180ms | 1.8s | 5.2s | timeout | 2m 10s |

이런 표가 있으면 "현재 구조가 운영에서 충분한가"를 감이 아니라 데이터로 이야기할 수 있다.
