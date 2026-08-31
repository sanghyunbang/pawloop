# 백엔드 구현 가이드 (프론트 계약 → Spring 구조)

> "백엔드를 이제 직접 구현하려는데 **뭘 보고 뭘 만들어야 하지?**"
> 프론트(Flutter)가 먼저 완성됐고, 그 요구가 [`openapi.yaml`](../04-api/openapi.yaml) 계약에 다 담겨 있습니다.
> 이 문서는 그 계약을 **Spring Boot 레이어(Controller / Service / DTO / Entity)** 로 옮길 때의 청사진입니다.
> ⚠️ 구현 코드(로직)는 담지 않습니다 — 만들 **대상과 시그니처**만. 로직은 직접 구현하세요.

---

## 0. 시작할 때 뭘 보나 (2가지 길)

### 길 A — 계약에서 "구현할 껍데기"를 자동 생성해서 그 위에 채우기 (Swagger식)
`openapi.yaml`에서 **Spring 서버 스텁**(컨트롤러 인터페이스 + DTO 클래스)을 생성하면, "구현해야 할 목록"이 코드로 나옵니다. 그걸 `implements` 해서 **서비스 로직만** 채우면 됩니다.
```bash
npx @openapitools/openapi-generator-cli generate -i docs/04-api/openapi.yaml -g spring -o build/gen/spring --additional-properties=interfaceOnly=true,useSpringBoot3=true
```
→ 생성된 `*Api.java`(컨트롤러 인터페이스)와 DTO를 참고/차용하되, 이 프로젝트 컨벤션(아래)에 맞게 손으로 옮겨 구현하는 걸 권장(생성물 그대로 커밋 X).

### 길 B — 이 가이드의 리소스별 청사진을 보고 레이어별로 직접 만들기
아래 [리소스별 청사진](#4-리소스별-청사진)에 각 리소스의 Controller/Service/DTO/Entity 시그니처가 정리돼 있습니다.

> 두 길을 같이 쓰면 좋습니다: 스텁으로 "빠진 것 없나" 대조하고, 청사진으로 각 레이어 책임을 이해.
> 백엔드엔 이미 `springdoc`이 있어, 구현 후 `/swagger-ui.html`이 자동 생성되니 계약과 실제가 맞는지 최종 대조까지 됩니다.

---

## 1. 레이어드 구조 (요청이 흐르는 길)

```
HTTP 요청
  │
  ▼
Controller   @RestController  — 입력 검증, DTO 변환, 인증(userId 추출), ResponseEntity 반환
  │  (Request DTO)
  ▼
Service      @Service         — 비즈니스 로직, 트랜잭션, 외부 API 호출 조율
  │  (Entity)
  ▼
Repository   JpaRepository    — DB 접근, 공간쿼리(native @Query)
  │
  ▼
Entity/DB    @Entity → MySQL (공간형 POINT/LINESTRING + SPATIAL INDEX)
```
- **DTO는 경계(Controller)에서만** 쓰고, 내부는 Entity로. (Entity를 그대로 응답에 노출하지 말 것)
- 응답 DTO는 Service 또는 Mapper에서 Entity → DTO 변환.

---

## 2. 패키지 구조 (기존 컨벤션 그대로)

```
com.heattrip.heat_trip_backend
├── user            # Auth (기존 AuthController) + users
├── OAuth           # JWT Provider/Filter, OAuth2 SuccessHandler (재사용)
├── dog             # ← 신규: 반려견 프로필
├── place           # ← 신규: 장소(KTO/병원/펫샵/산책로) 프록시+캐시
├── walk            # ← 신규: 산책 기록/통계
├── community       # ← 신규(기존 social 패턴 차용): 게시판/댓글/반응
├── bookmark        # ← 신규
├── tour            # 기존 TourApiClient(KorService2) — Place 프록시 패턴 참고
├── S3              # MediaController — 아바타/사진 업로드 재사용
└── config          # WebClientConfig(외부 API), Security 등
```
각 리소스 패키지 하위: `controller/ · service/ · repository/ · entity/ · dto/` (social 패키지가 표준 예시).

### 2.1 도메인 성숙도로 두 단 (2026-08-31, 이슈 #95)

5종을 편집증적으로 전부에 강제하지 않는다. **도메인 성숙도로 두 단을 둔다.** 다만 한 폴더에 다 넣는 것은 어느 단에서도 안 된다.

| 단 | 대상 | 하위 구조 |
|:---|:---|:---|
| **1단 — 단순 CRUD** | `bookmark` · `feedback` · `social` · `user` · `group` | `controller/ service/ repository/ entity/ dto/` |
| **2단 — 핵심 도메인** | `chat` · `care` · `curation` · `explore` | `api/ application/ domain/ infrastructure/` |

단을 올릴 때는 **이슈를 하나 파고 근거를 적는다.** 조용히 올리지 않는다.

### 2.2 `api` 하위 패키지에는 이름을 붙인다 (이슈 #108 · ADR-0012)

**2단 구조를 쓰는 순간 구조 검사와 정면으로 부딪힌다.** Spring Modulith 의 기본 규칙은 "모듈 패키지 **바로 아래** 타입만 공개, 하위 패키지는 전부 내부" 다. 그러니 `care/api/CareController` 를 밖에서 부르면 그대로 위반이다.

**규칙: 2단 도메인의 `api` 하위 패키지에는 `@NamedInterface("api")` 를 붙인다. 그것이 그 도메인의 공개 표면이다.**

```java
// care/api/package-info.java
@org.springframework.modulith.NamedInterface("api")
package com.heattrip.heat_trip_backend.care.api;
```

부르는 쪽은 더블 콜론으로 그 표면만 집는다.

```java
@ApplicationModule(allowedDependencies = { "care :: api" })
```

**동작하는 예가 저장소 안에 있다** — [`chatweb/package-info.java`](../../backend/src/main/java/com/heattrip/heat_trip_backend/chatweb/package-info.java). `@ApplicationModule` 로 허용 목록을 선언하고 `"user :: entity"` 로 이름 붙은 표면을 집는다.

**`::` 로 표면을 지정하면 나머지는 닫힌다.** 그리고 **루트와 이름 붙은 표면은 따로 열어야 한다** — `"user"` 만 적으면 `user.entity.User` 를 못 부른다. 없는 표면 이름을 적으면 검사가 통과하는 게 아니라 `IllegalArgumentException` 으로 **던진다**.

### 2.3 1단(단순 CRUD)에서는 무엇을 여는가

**결론: 아무것도 안 연다. 그것이 기본값이다.**

- `controller/` — HTTP 진입점이다. 다른 모듈이 부를 일이 없다. 열지 않는다.
- `repository/` — 남이 직접 부르는 것은 공용 어휘가 아니라 **그냥 새는 것**이다. 열지 않는다.
- `service/` · `dto/` — 남이 부르고 있다면 **그게 정상인지부터 묻는다.** 대개는 경계가 잘못 그어진 신호다.
- `entity/` — 여기만 예외가 생길 수 있다. 실제로 `user.entity.User` 는 밖의 파일 34개가 부르는 공용 어휘라 `@NamedInterface("entity")` 를 붙였다(이슈 #105). **다만 그건 빚을 합법으로 만든 것이지 옳다고 정한 것이 아니다** — 경계를 넘는 JPA 연관을 걷어내는 작업이 이슈 #120~#123 으로 따로 잡혀 있다.

밖에서 부를 것이 생기면 **루트로 올린다.** 패키지 루트는 그 자체로 공개 표면이라 별도 선언이 필요 없다.

### 2.4 `chat` 에 2단을 적용할 때의 조건

`chat` 은 지금 2단 구조가 **아니다** — 루트에 20개 + `entity/` + `repository/` + `metrics/` 다. 그런데 **그 모양이 구조 검사의 기본형과 정확히 일치해서** 켜자마자 위반 0건이다.

2단으로 옮기면 그 0건이 깨질 수 있다. 옮길 때 `api` 에 이름을 붙여야 하고, **무엇을 `api` 에 넣을지는 이미 정해져 있다.** 2026-08-31 실측으로 루트 20개가 이렇게 갈린다.

| 밖에서 실제로 부름 → `api/` 로 (14) | 밖에서 이름이 안 보임 (6) |
|:---|:---|
| `ChatRoomService` · `ChatRoomView` · `ChatMessageView` · `ChatRoomSummaryView` · `ChatMessagePageView` · `ChatMemberView` · `ChatLimitViolationException` · `ChatReadView` · `ChatMessageSender` · `ChatMessageSendResult` · `ChatJoinResult` · `ChatInviteView` · `ChatReportService` · `ChatReportView` | `ChatErrorCode` · `ChatLimits` · `FixedChatLimits` · `InviteCodeGenerator` · `ChatReportedMessageView` · `ChatReportReason` |

**오른쪽 칸의 이름이 "내부로 옮겨도 된다" 는 뜻은 아니다.** 세는 방식이 **밖의 소스에 그 이름이 적혀 있는가** 라서 맹점이 하나 있다 — `ChatReportedMessageView` 는 밖 어디에도 안 적혀 있지만 `ChatReportView` 가 들고 있는 리스트의 원소 타입이라, 내부로 내리면 **공개 record 의 시그니처가 깨진다**(#82).

`ChatReportReason` 은 사정이 다르다 — 밖으로 나가는 것은 그 enum 이 아니라 `wireValue()` 문자열이라 **진짜로 내부다.** 같은 칸에 있어도 이유가 다르다.

즉 오른쪽 칸은 "옮길 것" 목록이 아니라 **"옮기기 전에 한 번 더 볼 것" 목록**이다.

### 2.5 이 검사가 잡아 주지 않는 것

**"공개인데 아무도 안 쓰는 표면" 은 `verify()` 가 안 잡는다.** 위 표의 오른쪽 넷이 그것이다 — 루트에 있어서 공개인데 밖에서 부르는 곳이 0건이다. 구조 검사는 "밖에서 내부를 불렀는가" 만 본다.

그걸 잡는 것은 [`ChatBoundaryArchitectureTest`](../../backend/src/test/java/com/heattrip/heat_trip_backend/chat/ChatBoundaryArchitectureTest.java) 다. 그 테스트는 쿼리 문자열과 정본 SQL 도 본다 — **바이트코드에 안 남는 것들이라 구조 검사로는 절대 못 잡는다.**

**도구를 넣었다고 그 테스트를 지우면 안 되는 이유가 이것이다.** 둘은 겹치지 않는다.

---

## 3. 공통 building blocks (리소스마다 반복되는 것)

### 3.1 인증 — 이미 있는 것 재사용
- OAuth2 로그인 + JWT 발급/검증은 **`OAuth/` 패키지에 이미 구현**돼 있습니다(카카오/네이버/구글, `JWTProvider`, `JWTAuthenticationFilter`, 성공 시 `heattrip://login-callback?code=&state=` — #14 이전에는 `?token=` 이었다).
- 컨트롤러에서 현재 사용자: `HttpServletRequest`에서 필터가 넣어준 인증 정보로 userId(=email subject) 추출. (기존 `SocialController`가 이 방식)
- 인증 필요 엔드포인트: 쓰기(산책 저장, 글 작성, 북마크, 강아지 CRUD). 읽기(장소/글 목록)는 비인증 허용.

### 3.2 에러 포맷
기존 `{"error": {...}}` envelope 유지. 권장: `@RestControllerAdvice`로 공통 예외 → `ErrorResponse` record.
```
{ "error": { "code": "NOT_FOUND", "message": "...", "traceId": "..." } }
```

### 3.3 커서 페이지네이션
목록 응답 공통 형태:
```
{ "items": [...], "nextCursor": "base64", "hasMore": true }
```
`limit`(기본 20, 최대 100) + `cursor`(이전 nextCursor). 커서는 보통 `id` 또는 `(정렬키,id)`를 base64로.

### 3.4 외부 공공데이터 프록시 + 캐시
- 패턴: `config/WebClientConfig`의 WebClient + `tour/TourApiClient`(KorService2 호출)를 참고해 **`KorPetTourService2` 클라이언트**를 추가.
- KTO는 1,000콜/일 제한 → **`place` 테이블에 주기 동기화(캐시)** 후 DB에서 서빙 권장. (스케줄러: 기존 `tour/schedules/TourFetchScheduler` 패턴)
- serviceKey는 이미 인코딩된 값 → 쿼리에 그대로(재인코딩 금지).

### 3.5 공간(Spatial) 처리 (MySQL)
- 좌표: `place.geom POINT`, 경로: `walk.path`/`trail.path LINESTRING`. `SPATIAL INDEX` 필수.
- 주변 조회: `ST_Distance_Sphere(geom, POINT(:lng,:lat)) <= :radius` (native @Query). 위경도 순서 주의(POINT는 경도,위도).
- LOCALDATA 병원/펫샵 좌표는 **EPSG:5174(중부원점 TM) → WGS84 변환** 후 저장.
- 저장 시 프론트가 보내는 `path`(좌표 배열, [경도,위도]) → `ST_GeomFromText('LINESTRING(...)')`.

---

## 4. 리소스별 청사진

각 문서에 Controller/Service/DTO/Entity 시그니처가 정리돼 있습니다(구현 바디 없음).

| 리소스 | 문서 | 핵심 |
|---|---|---|
| Auth | [backend/auth.md](backend/auth.md) | 기존 OAuth/JWT 재사용 + `/auth/me` 등 |
| Dogs | [backend/dogs.md](backend/dogs.md) | 반려견 CRUD + 아바타 |
| Places | [backend/places.md](backend/places.md) | KTO 프록시+캐시, 공간 주변조회, 레이어 |
| Walks | [backend/walks.md](backend/walks.md) | 산책 저장(LINESTRING)·주간 통계 |
| Community | [backend/community.md](backend/community.md) | 게시판/댓글/반응(social 패턴) |
| Bookmarks | [backend/bookmarks.md](backend/bookmarks.md) | 저장 장소 |

### 권장 구현 순서
1. **Auth**(이미 대부분 있음 — `/auth/me` 정비부터) → 2. **Dogs**(가장 단순한 CRUD로 레이어 감 잡기) → 3. **Places**(외부 API+공간, 앱 핵심) → 4. **Walks**(공간+통계) → 5. **Community**(social 차용) → 6. **Bookmarks**.

---

## 5. 참고
- 계약(SSOT): [`../04-api/openapi.yaml`](../04-api/openapi.yaml) · 사용법: [`../04-api/README.md`](../04-api/README.md)
- 데이터 모델: [`../03-database/erd.md`](../03-database/erd.md) · [`../03-database/schema.md`](../03-database/schema.md)
- 기존 구조: [`backend-structure.md`](backend-structure.md)
