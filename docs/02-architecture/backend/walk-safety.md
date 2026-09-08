# WalkSafety (산책 안전 지수 재료) — 백엔드 구현 메모

> 대상: `com.heattrip.heat_trip_backend.walksafety` 패키지. openapi `/api/walk-safety/now`. 이슈 #336.
> 참조 계약: [openapi.yaml](../../04-api/openapi.yaml) `paths./api/walk-safety/now`, `schemas.WalkSafetyNow`
> 외부 데이터: [external-data.md §7](../external-data.md)
> 테이블 없음 — 저장하는 것이 없다.

## 1. 개요

| 항목 | 내용 |
| --- | --- |
| 리소스 책임 | 기상청 초단기실황 + 에어코리아 미세먼지를 **서버가** 불러 격자 하나의 관측값 한 묶음으로 준다. 판정은 앱이 한다 |
| 왜 서버인가 | 공공데이터포털 키를 앱에 두지 않는다(#40). 대신 앱은 5km 격자 번호만 보내고 요청에 인증이 없다 — 서버는 누구의 격자인지 모른다(A안 #235 과의 절충) |
| 저장 | 없음. 격자별 응답 10분 메모리 캐시 · 측정소 목록 24시간 메모리 캐시뿐 |
| 인가 | `SecurityConfig.PUBLIC_MATCHERS` 의 `/api/walk-safety/now`. rate limit `walk-safety` 버킷(IP 분당 30) |
| 키 | `app.public-data.service-key` ← `PUBLIC_DATA_SERVICE_KEY`(없으면 `TOUR_API_SECRET`). 비어 있으면 503 |

## 2. 패키지

```
walksafety/
  package-info.java                    @ApplicationModule(allowedDependencies = {})
  controller/WalkSafetyController      GET /api/walk-safety/now?nx=&ny= → 200 · 400 · 503
  service/WalkSafetyService            격자 캐시 · 기준 시각(kmaBase, 매시 40분) · 가장 가까운 측정소
  service/KmaNowcastClient             getUltraSrtNcst — WebClient "kmaWebClient"
  service/AirKoreaClient               getMsrstnList · getMsrstnAcctoRltmMesureDnsty — "airKoreaWebClient"
  service/PublicDataJson               봉투 읽기(게이트웨이 오류·서비스 오류·XML 은 "없음")
  service/KmaGrid                      격자 역변환(칸 중심) · 하버사인 · 범위 검사
  dto/WalkSafetyNowResponse
```

`config` 모듈의 `KtoWebClientConfig` 가 두 WebClient 빈을 만든다(타임아웃 네 겹). 이 모듈은 그 클래스를 **타입으로 부르지 않고** 문자열 이름으로 주입받는다 — 모듈 경계 위반 0.

## 3. 실패의 모양

| 상황 | 응답 |
| --- | --- |
| 격자 범위 밖 | 400 — 기상청을 부르지 않는다 |
| 기상청 실황 없음(키 없음·게이트웨이 오류·기온 항목 없음·타임아웃) | 503 — 반쪽 값을 주지 않는다. 앱은 카드를 안 그린다 |
| 에어코리아 실패 | 200 인데 `pm10`·`pm25`·`station` 이 null — 앱은 "미세먼지 정보 없음". 측정소 목록을 못 받은 경우는 **5분만** 그 상태를 기억한다(`EMPTY_STATIONS_TTL`) |

> 두 API 는 2026-09-08 에 활용신청이 승인됐다. 그런데도 PM 이 안 붙으면 **승인이 아니라 주소를 의심한다** — 오퍼레이션 이름이 틀리면 게이트웨이가 `NO_OPENAPI_SERVICE_ERROR` 를 주고, 그 응답은 승인 대기와 화면에서 구별되지 않는다. `AirKoreaClientTest` 가 나가는 URI 를 재고, `scripts/check-external-keys.sh` 가 실제로 불러 본다.

## 4. 테스트

- `WalkSafetyParserTest` — 실제 응답 모양(2026-09-07 서울)·게이트웨이 오류·XML·측정소·실시간.
- `WalkSafetyServiceTest` — 기준 시각(40분 전 시 단위 내림, 자정 경계).
- `WalkSafetyEndpointIntegrationTest` — 인증 없이 200 · 계약 키 집합 · 격자 캐시 · 에어코리아 없음 · 503 · 400.
- `ApiRateLimitFilterTest.walkSafety_hasItsOwnBucket` — permitAll 경로가 한도 표에 있다.
