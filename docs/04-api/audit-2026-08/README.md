# API 계약 감사 — 2026-08

> 대상: [`openapi.yaml`](../openapi.yaml) · 함께 본 문서: [`api-spec.md`](../api-spec.md)

**계약 문서 자체의 설계 품질**을 감사한 기록이다. "코드가 계약을 지키는가"가 아니라 **"계약이 제대로 만들어졌는가"** 를 본다.

`/auth`는 제기된 주장 8건을 각각 **적대적으로 검증**했다 — 반증을 먼저 시도하고, 조금이라도 부정확하면 `PARTIAL`/`REFUTED`로 판정한 뒤 정확한 사실을 기록했다. 나머지 도메인은 설계 결함 스캔이다.

## 결과

| 범위 | 결과 | 문서 |
|:---|:---|:---|
| `/auth` | CONFIRMED **18** · PARTIAL **5** · REFUTED **0** (총 23건) | [1부 — auth.md](./auth.md) |
| Dogs · Places · Walks · Bookmarks · Community · Groups | high **16** · medium **31** · low **11** (총 58건) | [2부 — domains.md](./domains.md) |

관련 이슈: [#23](https://github.com/sanghyunbang/pawloop/issues/23) (`/auth`) · [#24](https://github.com/sanghyunbang/pawloop/issues/24) (나머지 도메인)

## 반복해서 나온 뿌리 원인

도메인을 가리지 않고 같은 결함이 반복된다. 개별 항목을 고치기 전에 이 다섯 가지를 정하는 편이 낫다.

| 뿌리 원인 | 무슨 일이 벌어지나 | 어디서 |
|:---|:---|:---|
| **응답 스키마에 `required`가 없다** | `{}` 빈 객체가 유효한 응답이 된다. 코드 생성기가 전 필드를 nullable로 만들고, Prism 목 기반 계약 테스트가 아무것도 못 잡는다 | Auth · Dogs · Places · Community · Groups |
| **커서 페이지네이션을 표준으로 선언해놓고 raw 배열을 반환** | `info.description`이 `items`/`nextCursor`/`hasMore`를 표준이라 하는데 목록 절반이 그냥 배열이다. 댓글은 `cursor`/`limit` 파라미터조차 없다 | Dogs · Places · Community · Groups |
| **401·403 응답 누락** | 인증을 요구하거나 소유자 검증이 필요한 오퍼레이션에 응답 선언이 없다. 형제 오퍼레이션은 선언하는데 일부만 빠져 있어 누락으로 보인다 | Auth · Walks · Dogs |
| **부분 수정에 생성용 스키마를 재사용** | `PATCH`인데 `required`가 걸린 생성 스키마를 쓴다. 계약대로면 부분 수정이 불가능하다 | Dogs |
| **같은 개념을 경로마다 다른 이름으로** | 장소 키가 `contentId`와 `placeId`로 갈리고, 작성자(author)가 세 가지 모양이다 | Places · Bookmarks · Community |

## 감사 방법

에이전트 10대를 병렬로 돌렸다. 3대는 `/auth` 주장을 적대적 검증, 3대는 나머지 도메인 스캔, 4대는 별건(이슈별 테스트 항목 초안). 모든 주장에 `openapi.yaml` 줄번호와 인용을 붙이도록 강제했고, 근거 없는 추측은 금지했다.
