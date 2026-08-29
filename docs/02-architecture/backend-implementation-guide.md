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
├── user            # Auth (기존 AuthController) + app_user
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

---

## 3. 공통 building blocks (리소스마다 반복되는 것)

### 3.1 인증 — 이미 있는 것 재사용
- OAuth2 로그인 + JWT 발급/검증은 **`OAuth/` 패키지에 이미 구현**돼 있습니다(카카오/네이버/구글, `JWTProvider`, `JWTAuthenticationFilter`, 성공 시 `heattrip://login-callback?token=`).
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
