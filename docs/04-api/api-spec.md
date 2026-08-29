# Pawloop(포루프) REST API 명세

> [!IMPORTANT]
> **API 계약의 단일 출처(SSOT)는 [`openapi.yaml`](openapi.yaml) 이다.**
> 이 문서는 사람이 읽기 위한 요약이며, 값이 충돌하면 **언제나 `openapi.yaml` 이 우선한다.**
> 계약을 바꿀 때는 `openapi.yaml` 을 먼저 고치고, 이 문서를 뒤따라 맞춘다.

> 산책·동반장소·커뮤니티 앱 **Pawloop(포루프)**의 REST API 명세. 현재 구현된 부분과 **계획(Planned)** 을 함께 정리한다. 지금 앱은 장소 데이터를 관광공사 KTO API로 **직접 호출**하고 있으며, 백엔드는 이 문서의 프록시·저장 API로 점진 이전한다.

관련 문서: [ERD](../03-database/erd.md) · [아키텍처](../02-architecture/)

---

## 0. 개요

| 항목 | 값 |
|---|---|
| 백엔드 | Spring Boot (Java/Kotlin 혼용) + MySQL(공간형 POINT/LINESTRING) |
| Base URL(운영) | `https://api.heattrip.link` (도메인 유지, 서비스명만 Pawloop로 피벗) |
| Base URL(로컬) | `http://10.0.2.2:8080` (안드로이드 에뮬레이터 → 호스트 localhost) |
| 프론트 진입점 | `app/lib/core/config/env.dart` → `Env.apiBase` (`--dart-define=API_BASE` > `.env: API_BASE_URL` > 로컬) |
| 인증 | JWT Bearer 토큰 (`Authorization: Bearer <token>`) |
| Content-Type | `application/json; charset=utf-8` |
| 시간 | ISO-8601 (`2026-06-30T08:12:00+09:00`), 서버는 KST 기준 |
| 좌표 | WGS84 위도(`lat`)/경도(`lng`). KTO 응답의 `mapx`=경도, `mapy`=위도 |

### 구현 상태 범례

| 표기 | 의미 |
|---|---|
| ✅ 구현 | 레거시 백엔드에 유사 엔드포인트 존재(감정앱). Pawloop 맥락으로 재사용/개편 |
| 🟡 계획 | Pawloop MVP 대상. 아직 미구현(설계 확정) |
| 🔵 프록시 계획 | 현재 앱이 외부 API 직접 호출. 백엔드 프록시+캐싱으로 이전 예정 |
| ⚪ post-MVP | 확장 범위. 스텁만 |

> 레거시 백엔드(`backend/`)에는 감정앱 시절의 `/auth`(signup/login/me), `/api/social`(cards/comments/reactions), tour import 컨트롤러가 있다. 아래 명세는 이 구조와 JWT 규약을 **그대로 계승**하되, 리소스명을 반려(강아지) 도메인으로 바꾼 것이다.

---

## 1. 공통 규약

### 1.1 인증 헤더

```http
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

- JWT 의 `sub` 는 서버가 발급한 **불투명 사용자 키**다. 이메일이라고 가정하거나 파싱하지 말 것 — 소셜 로그인 경로에서는 이메일이 아니다. 사용자 정보가 필요하면 `GET /auth/me` 로 조회한다.
- 현재 발급되는 클레임은 `sub`·`role`·`iat`·`exp` 뿐이다. `jti` 가 없어 로그아웃해도 액세스 토큰은 만료까지 유효하다. #9 는 `jti` 를 도입하지 않기로 했다 — 블록리스트 저장소라는 소비자가 있어야 의미가 있고, 그건 M2 이후 별도 Epic 이다. 로그아웃은 대신 **서버측 refresh 토큰을 전부 폐기**한다(#9).
- 소셜 로그인 계정과 이메일 가입 계정은 **같은 경로로 동작한다.** 어느 쪽 토큰으로든 `GET /auth/me`·`PUT /auth/me`·`DELETE /auth/me`·`POST /auth/logout` 이 200/204 다. (2026-08 이전에는 소셜 계정에서 400 이었다. #5 에서 해소되었다.)
- 토큰 없음/만료/무효 → `401 Unauthorized`. **본문이 없다** — 상태 코드만 돌아오고 `Content-Type` 도 없다.
  토큰 없음·서명 위조·만료·옛 형식 subject·탈퇴 계정의 살아 있는 토큰이 전부 같은 모양이다(실패 원인을 알려 주지 않는 것이 의도다 — #6).
  클라이언트는 `error.code` 를 읽어 분기하지 말고 상태 코드 401 만 보고 재로그인으로 보낸다. (#5)
- MVP 단계에서는 로그인 없이도 홈/지도/산책이 동작하도록 **비인증 읽기**를 일부 허용(장소 조회 등). 쓰기(산책 저장·글 작성)는 인증 필요.

### 1.2 페이지네이션

목록 API는 커서 기반을 기본으로 한다.

| 파라미터 | 타입 | 기본 | 설명 |
|---|---|---|---|
| `limit` | int | 20 | 페이지 크기(최대 100) |
| `cursor` | string | - | 이전 응답의 `nextCursor` |

```json
{
  "items": [ /* ... */ ],
  "nextCursor": "eyJpZCI6MTIzfQ==",
  "hasMore": true
}
```

### 1.3 에러 포맷

레거시 컨트롤러의 `{"error": "..."}` 패턴을 확장한 공통 envelope.

```json
{
  "error": {
    "code": "PLACE_NOT_FOUND",
    "message": "해당 장소를 찾을 수 없습니다.",
    "traceId": "b3f1..."
  }
}
```

| HTTP | code 예시 | 상황 |
|---|---|---|
| 400 | `VALIDATION_ERROR` | 요청 바디/쿼리 검증 실패 |
| 401 | (본문 없음) | 토큰 없음/무효 — 이 표에서 유일하게 **본문을 주지 않는** 상태다(위 1.1 참조) |
| 403 | `FORBIDDEN` | 타인 리소스 수정 시도 |
| 404 | `NOT_FOUND` | 리소스 없음 |
| 409 | `CONFLICT` | 중복(예: 이미 누른 반응) |
| 429 | `RATE_LIMITED` | 외부 데이터(예: KTO 1000콜/일) 한도 |
| 500 | `INTERNAL_ERROR` | 서버 오류 |

---

## 2. 인증 (Auth)

카카오·구글 OAuth 중심(레거시 `kakao/`, `OAuth/` 패키지 계승). 네이버는 코드·설정이 남아 있으나 제품 결정상 **보류**다(#15). 프론트는 `flutter_web_auth_2`로 소셜 로그인 콜백을 받는다.

> JWT 의 `sub` 는 서버가 발급한 **불투명 사용자 키**다. 이메일이라고 가정하거나 파싱하지 말 것. 사용자 정보는 `GET /auth/me` 로 조회한다.

**인가 경계** — 비인증 허용은 `/auth/signup`, `/auth/login`, `/auth/oauth/**`, `/auth/token/refresh`, `/oauth2/**`, `/login/oauth2/**` 뿐이다. `/auth/me`(GET·PUT·DELETE)와 `/auth/logout` 은 반드시 토큰 검증을 거친다.

### 2.1 소셜 로그인 시작 — ✅ 구현

`GET /oauth2/authorization/{provider}` — `provider ∈ {kakao, google}` (naver 보류)

앱(`flutter_web_auth_2`)이 실제로 여는 URL. 소셜 인증 화면으로 302 리다이렉트되고, 성공 시 백엔드가 앱 딥링크 `heattrip://login-callback?token=<JWT>&refresh=<refreshToken>` 로 되돌린다(#9).

> ⚠️ `token` 은 더 이상 URL 의 꼬리가 아니다. `'token='` 뒤를 전부 잘라 쓰면 `&refresh=...` 까지 삼켜 손상된 액세스 토큰을 저장하게 된다. `Uri.parse(url).queryParameters['token']` 로 읽어야 한다.
> 딥링크에 자격증명 두 개가 실리는 위험(302 Location 헤더·브라우저 히스토리)과 그 대체(1회용 코드 교환)는 `openapi.yaml` 의 같은 경로 설명과 #14 를 보라.

> 계약에 있는 `GET /auth/oauth/{provider}` 는 **미구현**이다. 실제 진입점은 위 경로다.
> 딥링크 스킴은 `heattrip://` 다 — 코드(`social_login_service.dart`, `OAuth2SuccessHandler.java`)가 그렇게 동작한다. 이 문서가 예전에 예시로 들던 `pawloop` 스킴은 오기였고, 그대로 구현하면 콜백을 받지 못한다.

### 2.2 소셜 로그인 콜백 → 토큰 교환 — 🟡 계획(미구현)

`POST /auth/oauth/{provider}/callback`

```json
// Request
{ "code": "authorization_code_from_provider", "redirectUri": "heattrip://login-callback" }
```

```json
// 200 OK
{
  "accessToken": "eyJhbGci...",
  "expiresIn": 3600,
  "isNew": false,
  "user": {
    "id": 42,
    "email": "bori@example.com",
    "nickname": "보리아빠"
  }
}
```

- `isNew` 는 **로그인 응답의 1회성 이벤트 속성**이라 `user` 블록 밖(`AuthTokens` 최상위)에 있다. `true` 면 프론트는 온보딩(강아지 프로필 등록)으로 유도.
- `refreshToken` 은 이 경로(미구현)에는 없다. 소셜 로그인은 딥링크의 `refresh` 파라미터로, 갱신은 `POST /auth/token/refresh` 응답으로 전달된다(#9).

### 2.3 토큰 갱신 — ✅ 구현(#9)

`POST /auth/token/refresh` — 인증 불필요. 주체는 본문의 refresh 토큰 자체가 증명한다.

```json
// Request
{ "refreshToken": "9qQ1t...(패딩 없는 Base64URL 43자, JWT 아님)" }
// 200 OK — 회전된다. 새 refreshToken 으로 반드시 교체 저장할 것
{ "accessToken": "eyJhbGci...", "refreshToken": "새 값", "expiresIn": 3600 }
```

- **회전**: 성공하면 옛 refresh 토큰은 그 자리에서 폐기된다. 다시 쓰면 401 이다.
- **재사용 감지**: 이미 폐기된 refresh 토큰이 다시 오면 유출로 간주해 **그 사용자의 모든 세션**을 폐기하고 401 이다. 즉 옛 토큰으로 한 번 재시도하면 방금 받았던 새 토큰도 함께 죽는다.
- 만료·미존재는 그냥 401 이며 다른 세션을 끊지 않는다. 실패는 전부 **본문 없는 401** 이다.
- ⚠️ 클라이언트는 갱신 요청을 **직렬화(single-flight)** 해야 한다. 같은 값으로 동시에 두 번 보내면 한쪽이 재사용으로 처리되어 전 기기가 끊긴다. 서버는 유예 창을 두지 않는다.
- 수명 14일(`jwt.refresh-expiration`). 서버에는 SHA-256 해시만 저장된다.

### 2.4 내 정보 조회 — ✅ 구현(재사용)

`GET /auth/me` — 헤더 `Authorization: Bearer <token>` 필요.

```json
// 200 OK
{
  "id": 42,
  "email": "bori@example.com",
  "name": "방상현",
  "nickname": "보리아빠",
  "gender": "MALE",
  "age": 32,
  "travelType": "healing",
  "imageUrl": "https://.../me.png",
  "createdAt": "2026-05-01T10:00:00+09:00",
  "updatedAt": "2026-08-01T10:00:00+09:00"
}
```

> `provider` 는 `users` 테이블에 컬럼이 없어 아직 내려오지 않는다(#10·#5). 필드명은 `profileImage` 가 아니라 **`imageUrl`** 이다.

### 2.5 이메일 회원가입 — ✅ 구현 (계약은 목표 형태)

`POST /auth/signup` — 비인증. 목표 계약은 `201 Created` + `User` JSON.

> 현행 구현은 `200 OK` + 본문 `"회원가입 성공"`(평문)이다. 구현을 계약에 맞추는 것은 #10.

### 2.6 이메일 로그인 — ✅ 구현 (계약은 목표 형태)

`POST /auth/login` — 비인증. 목표 계약은 `200 OK` + `AuthTokens` JSON.

> 현행 구현은 JSON 이 아니라 **JWT 원문 문자열**을 본문에 담아 반환한다. 구현을 계약에 맞추는 것은 #10.

### 2.7 내 정보 수정 — ✅ 구현

`PUT /auth/me` — 부분 수정(보낸 필드만 반영). `200 OK` + `User`.

> 시맨틱이 부분 수정이므로 장기적으로는 `PATCH` 가 옳다. 전환은 별도 정리 이슈.

### 2.8 로그아웃 — ✅ 구현(#9)

`POST /auth/logout` — 인증된 주체를 받아 `204 No Content`(멱등) / `401`. 어느 쪽 토큰(소셜·이메일 가입)으로 불러도 204 다.

> **전 기기 로그아웃이다.** 그 사용자의 서버측 refresh 토큰을 전부 폐기한다. 요청 본문은 없다 — 기기 하나만 끊는 경로는 정의하지 않는다.
> **다만 이미 발급된 액세스 토큰은 만료(≤1시간)까지 유효하다.** `jti` 블록리스트가 없기 때문이고, 그건 M2 이후 별도 Epic 이다. 따라서 클라이언트가 저장한 토큰을 반드시 스스로 지워야 한다.

### 2.9 회원 탈퇴 — ✅ 구현(재사용)

`DELETE /auth/me` — `204 No Content` / `401`. (레거시 `AuthController.deleteMe()` 계승)

---

## 3. 강아지 프로필 (Dogs)

프론트 도메인: `app/lib/v2/domain/pet.dart` → `DogProfile { name, breed, size(소형/중형/대형), ageMonths, neutered, avatarAsset }`.
현재 앱은 전역 `ValueNotifier<DogProfile> kMyDog`로 로컬 보관(백엔드 미연동).

### 3.1 내 강아지 목록 — 🟡 계획

`GET /api/dogs` — 인증 필요. 한 사용자가 다견 가정 가능.

```json
// 200 OK
[
  {
    "id": 7,
    "name": "보리",
    "breed": "믹스견",
    "size": "small",          // small | medium | large
    "birth": "2024-01-15",
    "ageMonths": 30,
    "neutered": true,
    "avatarUrl": "https://.../dogs/7.png"
  }
]
```

> `size` enum은 프론트 `DogSize{small,medium,large}`와 1:1. `ageMonths`는 `birth` 기준 서버 계산값(응답 편의 필드).

### 3.2 강아지 등록 — 🟡 계획

`POST /api/dogs`

```json
// Request
{
  "name": "보리",
  "breed": "믹스견",
  "size": "small",
  "birth": "2024-01-15",
  "neutered": true
}
// 201 Created → 3.1 항목 1건 반환
```

검증: `name` 1~20자, `size` ∈ enum, `birth` ≤ 오늘.

### 3.3 강아지 상세 — 🟡 계획

`GET /api/dogs/{dogId}` → 3.1 항목 1건.

### 3.4 강아지 수정(부분) — 🟡 계획

`PATCH /api/dogs/{dogId}` — 본인 소유만(아니면 `403`). 변경 필드만 전송.

```json
// Request
{ "name": "보리", "neutered": true, "size": "medium" }
```

### 3.5 강아지 삭제 — 🟡 계획

`DELETE /api/dogs/{dogId}` — `204 No Content`.

### 3.6 아바타 업로드 — ⚪ post-MVP

`POST /api/dogs/{dogId}/avatar` (multipart/form-data, `file`) — 레거시 `S3/MediaController` 재사용 예정.

---

## 4. 장소 (Places)

**현재 상태:** 앱이 관광공사 KTO(`KorPetTourService2`)를 **직접 호출**한다.
구현 위치: `app/lib/v2/data/pet_places_repository.dart` → `PetPlacesRepository.fetchNearby()`.

### 4.1 (현행) KTO 직접 호출 — 🔵 프록시 계획

```http
GET https://apis.data.go.kr/B551011/KorPetTourService2/locationBasedList2
  ?serviceKey={ENCODED_KEY}
  &MobileOS=ETC&MobileApp=heattrip&_type=json
  &numOfRows=80&pageNo=1
  &mapX={lng}&mapY={lat}&radius=8000&arrange=E
  &contentTypeId={optional}
```

- `serviceKey`: `.env`의 `YOUR_DECODING_SERVICE_KEY`(명칭과 달리 이미 **인코딩된** 키). 프론트에서 그대로 붙임.
- `arrange=E`: 거리순. `radius` 기본 8000m.
- 응답 파싱(프론트): `response.body.items.item[]` → `contentid, title, contenttypeid, addr1, firstimage, tel, mapx(경도), mapy(위도), dist(m)`.
- `contenttypeid`: `12`관광지 `14`문화 `28`레포츠 `32`숙박 `38`쇼핑 `39`음식점.

**한계:** KTO 1000콜/일 제한, 키 노출, 캐싱 부재 → 아래 백엔드 프록시로 이전.

### 4.2 주변 장소 조회 (백엔드 프록시) — 🔵 프록시 계획

`GET /api/places/nearby`

| 쿼리 | 타입 | 기본 | 설명 |
|---|---|---|---|
| `lat` | double | 필수 | 위도(WGS84) |
| `lng` | double | 필수 | 경도 |
| `radius` | int | 8000 | 반경(m) |
| `category` | string | - | 필터. `12/14/28/32/38/39`(KTO) 또는 `vet/shop/trail`(공공데이터 레이어) |
| `limit` | int | 80 | 최대 100 |

동작: 백엔드가 KTO/LOCALDATA/두루누비를 호출·정규화하고 `place` 테이블에 캐시(공간 인덱스), 이후 `ST_Distance_Sphere`로 거리순 반환.

```json
// 200 OK
{
  "items": [
    {
      "id": "kto:126508",              // source:contentId
      "source": "kto_pet",             // kto_pet | localdata_vet | localdata_shop | durunubi_trail
      "category": "39",                // KTO contenttypeid 또는 vet/shop/trail
      "name": "성수동 반려카페",
      "addr": "서울 성동구 ...",
      "tel": "02-000-0000",
      "image": "http://tong.visitkorea.or.kr/...jpg",
      "lat": 37.5445,
      "lng": 127.0557,
      "distanceM": 320,
      "petAllowed": true
    }
  ],
  "count": 45,
  "cachedAt": "2026-06-30T08:00:00+09:00"
}
```

> 카테고리 SSOT: `app/lib/v2/domain/pet.dart` `kPetCategories`. `vet/shop/trail`은 별도 공공데이터 레이어(현재 앱 더미).

### 4.3 장소 상세 — 🔵 프록시 계획

`GET /api/places/{placeId}` — `placeId` = `source:contentId`(예: `kto:126508`).

```json
// 200 OK
{
  "id": "kto:126508",
  "source": "kto_pet",
  "category": "39",
  "name": "성수동 반려카페",
  "addr": "서울 성동구 성수이로 ...",
  "tel": "02-000-0000",
  "images": ["http://.../1.jpg", "http://.../2.jpg"],
  "lat": 37.5445,
  "lng": 127.0557,
  "petInfo": {                         // KTO detailPetTour2 정규화
    "acmpyTypeCd": "가능",
    "acmpyPsblCpam": "실내 동반 가능, 소형견 위주",
    "petFacility": "물그릇 제공"
  },
  "homepage": "https://...",
  "openHours": "10:00~21:00",
  "updatedAt": "2026-06-30T08:00:00+09:00"
}
```

원본 KTO 오퍼레이션: `detailCommon2` + `detailPetTour2`(반려 동반 상세).

### 4.4 산책로 코스 — ⚪ post-MVP

`GET /api/trails/nearby?lat&lng&radius` → 두루누비(걷기여행길) 코스. `path`는 인코딩 폴리라인/GPX 좌표열. 현재 앱은 더미 폴리라인.

---

## 5. 산책 (Walks)

실시간 GPS 트래킹 결과를 저장/조회. 프론트 도메인: `WalkLog { date, place, km, minutes, memo, pace }`, 통계용 `kWeekKm`.
현재 앱은 시뮬 이동 + 로컬 샘플(`kWalks`). 백엔드 미연동.

경로 저장 규약: GPS 경로는 `walk.path` **한 컬럼**(LINESTRING / 인코딩 폴리라인). 개별 포인트 테이블 없음.

### 5.1 산책 생성 — 🟡 계획

`POST /api/walks` — 인증 필요. 트래킹 종료 시 1회 전송.

```json
// Request
{
  "dogId": 7,
  "startedAt": "2026-06-30T07:10:00+09:00",
  "endedAt":   "2026-06-30T07:48:00+09:00",
  "distanceM": 2400,
  "durationS": 2280,
  "path": "y`psFhguhW...",             // 인코딩 폴리라인(권장) 또는 좌표배열
  "placeId": "kto:126508",             // nullable — 시작 근처 장소
  "placeName": "서울숲",
  "memo": "아침 공기가 좋아 한 바퀴 더.",
  "weather": "맑음"
}
```

```json
// 201 Created
{
  "id": 1012,
  "dogId": 7,
  "startedAt": "2026-06-30T07:10:00+09:00",
  "endedAt": "2026-06-30T07:48:00+09:00",
  "distanceM": 2400,
  "durationS": 2280,
  "paceSecPerKm": 950,                 // 서버 계산 (durationS / km)
  "placeName": "서울숲",
  "memo": "아침 공기가 좋아 한 바퀴 더.",
  "weather": "맑음"
}
```

검증: `endedAt` > `startedAt`, `distanceM ≥ 0`, `dogId`는 본인 소유.

### 5.2 산책 목록 — 🟡 계획

`GET /api/walks?dogId={id}&from=2026-06-01&to=2026-06-30&limit=20&cursor=...`

```json
// 200 OK
{
  "items": [
    {
      "id": 1012,
      "date": "2026-06-30",
      "placeName": "서울숲",
      "distanceM": 2400,
      "durationS": 2280,
      "paceSecPerKm": 950,
      "memo": "아침 공기가 좋아 한 바퀴 더."
    }
  ],
  "nextCursor": null,
  "hasMore": false
}
```

### 5.3 산책 상세 — 🟡 계획

`GET /api/walks/{walkId}` — 5.1 응답 + `path`(경로 폴리라인) 포함. 지도에서 경로 리플레이용.

### 5.4 산책 삭제 — 🟡 계획

`DELETE /api/walks/{walkId}` — 본인 소유만. `204 No Content`.

### 5.5 산책 통계 — 🟡 계획

`GET /api/walks/stats?dogId={id}&period=week` — `period ∈ {week, month}`. 통계 차트(`fl_chart`)용 집계.

```json
// 200 OK
{
  "period": "week",
  "range": { "from": "2026-06-24", "to": "2026-06-30" },
  "daily": [                            // 프론트 kWeekKm / kWeekDayLabels 대응
    { "day": "월", "date": "2026-06-24", "distanceKm": 2.1, "count": 1 },
    { "day": "화", "date": "2026-06-25", "distanceKm": 2.9, "count": 1 },
    { "day": "수", "date": "2026-06-26", "distanceKm": 1.2, "count": 1 },
    { "day": "목", "date": "2026-06-27", "distanceKm": 0.0, "count": 0 },
    { "day": "금", "date": "2026-06-28", "distanceKm": 1.8, "count": 1 },
    { "day": "토", "date": "2026-06-29", "distanceKm": 3.1, "count": 1 },
    { "day": "일", "date": "2026-06-30", "distanceKm": 2.4, "count": 1 }
  ],
  "summary": {
    "totalKm": 13.5,
    "totalWalks": 6,
    "avgPaceSecPerKm": 980,
    "topPlaces": ["서울숲", "남산 둘레길", "한강공원(뚝섬)"]
  }
}
```

---

## 6. 커뮤니티 (Community)

레거시 `/api/social`(cards/comments/reactions) 구조를 반려 게시판으로 개편.
프론트 도메인: `PetPost { nick, board, loc, date, title, body, commentCount, reactions[3] }`.
게시판 `kPetBoards = [전체, 산책로 후기, 동반장소, 건강·병원, 자유, 자랑]`, 반응 `kPetReactions = [도움돼요, 귀여워요, 공감]`.

board 코드 매핑:

| 코드 | 라벨 |
|---|---|
| `walk_review` | 산책로 후기 |
| `pet_place` | 동반장소 |
| `health` | 건강·병원 |
| `free` | 자유 |
| `brag` | 자랑 |

reaction 코드: `help`(도움돼요) · `cute`(귀여워요) · `empathy`(공감). (ERD `reaction.type[help/cute/empathy]`와 동일)

### 6.1 글 목록 — ✅ 구현(개편)

`GET /api/posts?board={code}&placeId={id}&limit=20&cursor=...`

- `board` 미지정 = 전체. `placeId` 지정 시 특정 장소 관련 글만.

```json
// 200 OK
{
  "items": [
    {
      "id": 331,
      "board": "walk_review",
      "author": { "id": 42, "nickname": "보리아빠", "avatarUrl": "https://.../42.png" },
      "placeName": "서울숲",
      "placeId": "kto:126508",
      "title": "서울숲 아침 산책 코스 추천",
      "bodyPreview": "이른 아침엔 사람이 적어서 대형견도 편해요...",
      "commentCount": 4,
      "reactions": { "help": 7, "cute": 3, "empathy": 2 },
      "createdAt": "2026-06-30T09:00:00+09:00"
    }
  ],
  "nextCursor": "eyJpZCI6MzMwfQ==",
  "hasMore": true
}
```

### 6.2 글 상세 — 🟡 계획

`GET /api/posts/{postId}` → 6.1 항목 + `body`(전문) + `myReaction`(내가 누른 반응 코드/null).

### 6.3 글 작성 — ✅ 구현(개편)

`POST /api/posts` — 인증 필요. (레거시 `SocialController.shareCard()` 계승)

```json
// Request
{
  "board": "walk_review",
  "title": "서울숲 아침 산책 코스 추천",
  "body": "이른 아침엔 사람이 적어서 대형견도 편해요. 잔디마당은 목줄 필수!",
  "placeId": "kto:126508",            // nullable
  "placeName": "서울숲"                // nullable
}
// 201 Created → 6.2 상세 반환
```

검증: `title` 1~100자, `body` 1~5000자, `board` ∈ enum.

### 6.4 글 수정 — 🟡 계획

`PATCH /api/posts/{postId}` — 작성자만(아니면 `403`). 변경 필드만.

### 6.5 글 삭제 — 🟡 계획

`DELETE /api/posts/{postId}` — 작성자만. `204 No Content`.

### 6.6 댓글 목록 — ✅ 구현(개편)

`GET /api/posts/{postId}/comments?limit=50&cursor=...` — 오래된 순.

```json
// 200 OK
{
  "items": [
    {
      "id": 900,
      "author": { "id": 51, "nickname": "초코맘", "avatarUrl": "https://.../51.png" },
      "body": "저도 아침에 자주 가요! 배변봉투통 위치 공유 감사합니다.",
      "createdAt": "2026-06-30T09:20:00+09:00"
    }
  ],
  "nextCursor": null,
  "hasMore": false
}
```

### 6.7 댓글 작성 — ✅ 구현(개편)

`POST /api/posts/{postId}/comments` — 인증 필요. (레거시 `addComment()` 계승)

```json
// Request
{ "body": "저도 아침에 자주 가요!" }
// 201 Created → 6.6 항목 1건
```

### 6.8 댓글 삭제 — 🟡 계획

`DELETE /api/comments/{commentId}` — 작성자만. `204 No Content`.

### 6.9 반응 토글 — ✅ 구현(개편)

`POST /api/posts/{postId}/reactions` — 인증 필요. 같은 타입 재요청 시 취소(토글). (레거시 `toggleReaction()` 계승)

```json
// Request
{ "type": "cute" }                     // help | cute | empathy
```

```json
// 200 OK
{
  "postId": 331,
  "myReaction": "cute",                // 취소된 경우 null
  "reactions": { "help": 7, "cute": 4, "empathy": 2 }
}
```

---

## 7. 북마크 (Bookmarks) — ⚪ post-MVP

레거시 `bookmark/` 패키지 재사용. 장소 즐겨찾기.

| 메서드 | 경로 | 설명 |
|---|---|---|
| `GET` | `/api/bookmarks` | 내 북마크 장소 목록 |
| `POST` | `/api/bookmarks` | `{ "placeId": "kto:126508" }` 추가 |
| `DELETE` | `/api/bookmarks/{placeId}` | 해제 |

---

## 8. 가족 케어 + 채팅 (Groups) — 🟡 계획

반려는 혼자가 아니라 **가족이 함께** 돌본다. 가족 그룹으로 오늘의 케어(물/밥/산책)를 공유해 이중 급여(밥 두 번)·산책 누락을 막고, 가족 채팅으로 앱의 일일 사용 이유(retention)를 만든다.

프론트 도메인: `app/lib/v2/domain/pet.dart` → `CareType/CareTask/kCareToday/FamilyMember/kFamilyMembers/kFamilyInviteCode/kWalkNotes/ChatMessage/kChatMessages` (현재 더미).
데이터 모델: `family_group(id,name,invite_code,created_at)` · `group_member(id,group_id,user_id,role[owner|member],joined_at)` · `chat_message(id,group_id,user_id,body,created_at)` · `walk_note(id,group_id,body,created_at)` · `care_log`는 기존 계획 확장 — `group_id`(nullable)·`done_by(user_id)` 추가, `type`은 `water|meal|walk|med|vet`.

| 메서드 | 경로 | 설명 |
|---|---|---|
| `POST` | `/api/groups` | 그룹 생성(생성자 `owner`, 초대코드 발급) |
| `POST` | `/api/groups/join` | `{ "inviteCode": "PAW-2K7Q" }` 초대코드로 참여 |
| `GET` | `/api/groups/me` | 내 그룹 + 멤버 목록(없으면 `404`) |
| `GET` | `/api/groups/{groupId}/care-logs?date&type` | 오늘의 케어 조회 — 누가·언제 물/밥/산책을 했는지 |
| `POST` | `/api/groups/{groupId}/care-logs` | 케어 기록 `{ "dogId": 7, "type": "meal", "memo": "" }` (`done_by`는 토큰 사용자) |
| `GET` | `/api/groups/{groupId}/messages?limit&cursor` | 가족 채팅 목록(커서 페이지네이션, MVP는 폴링) |
| `POST` | `/api/groups/{groupId}/messages` | 메시지 전송 `{ "body": "..." }` |
| `GET` | `/api/groups/{groupId}/walk-notes` | 산책 시 주의사항(가족 공유 메모) |
| `PUT` | `/api/groups/{groupId}/walk-notes` | 주의사항 전체 교체 `{ "notes": ["..."] }` |

- 그룹 멤버가 아닌 사용자의 접근 → `403 FORBIDDEN`. 잘못된 초대코드 → `404`, 이미 참여한 그룹 → `409`.
- **post-MVP:** 친구 추가(가족 외), 케어 알림/리마인더, 케어 히스토리 통계, 실시간 채팅(WebSocket/STOMP) 푸시.

---

## 9. 확장 로그 (Care Logs) — ⚪ post-MVP

건강·식사·병원·접종 기록. ERD `care_log(type[meal/health/vet/med], occurred_at, title, value, memo, photo)`. (8장의 가족 케어 공유가 MVP로 앞당겨지며 `type`·`group_id`·`done_by`가 확장됨 — 8장 참조.)

| 메서드 | 경로 | 설명 |
|---|---|---|
| `GET` | `/api/dogs/{dogId}/care-logs?type=vet&from&to` | 로그 목록 |
| `POST` | `/api/dogs/{dogId}/care-logs` | `{ "type":"vet", "occurredAt":"...", "title":"", "value":"", "memo":"" }` |
| `PATCH` | `/api/care-logs/{id}` | 수정 |
| `DELETE` | `/api/care-logs/{id}` | 삭제 |

---

## 10. 프론트↔API 매핑 요약

| 화면(lib/v2) | 현재 데이터 소스 | 목표 API |
|---|---|---|
| 홈 (강아지 히어로/오늘 산책) | `kMyDog`, `WalkToday` (로컬) | `GET /auth/me`, `GET /api/dogs`, `GET /api/walks/stats` |
| 지도 (KTO 45곳 + 병원/펫샵/산책로 더미) | KTO 직접호출(`PetPlacesRepository`) | `GET /api/places/nearby`, `GET /api/places/{id}` |
| 실시간 산책 (시뮬) | 로컬 | `POST /api/walks` |
| 산책 통계 (fl_chart) | `kWeekKm`(로컬) | `GET /api/walks/stats` |
| 커뮤니티 (더미) | `kPetPosts`(로컬) | `GET/POST /api/posts`, `/comments`, `/reactions` |
| 강아지 프로필/편집 | `kMyDog`(로컬) | `GET/POST/PATCH /api/dogs` |
| 홈 오늘의 케어 카드 · family_screen (멤버·초대코드·케어·주의사항) | `kCareToday`, `kFamilyMembers`, `kWalkNotes`(로컬) | `GET /api/groups/me`, `GET/POST /api/groups/{id}/care-logs`, `GET/PUT /api/groups/{id}/walk-notes` |
| family_chat_screen (가족 채팅) | `kChatMessages`(로컬) | `GET/POST /api/groups/{id}/messages` |

---

## 11. 이관 로드맵 (직접호출 → 백엔드)

1. **Phase 1 — 장소 프록시:** `GET /api/places/nearby|{id}`로 KTO 호출을 백엔드 이전. `place` 캐시 테이블 + 공간 인덱스 + KTO 1000콜/일 완화(캐싱·TTL). 프론트 `Env.apiBase` 스위치만으로 전환.
2. **Phase 2 — 계정·프로필:** 카카오/구글 OAuth + `/auth/me` + `/api/dogs`. 로컬 `kMyDog` → 서버 동기화.
3. **Phase 3 — 산책 저장:** `POST /api/walks` + `stats` 집계. GPS 경로 `walk.path` LINESTRING 저장.
4. **Phase 4 — 커뮤니티 실연동:** `/api/posts` 계열로 `kPetPosts` 대체. 레거시 `/api/social` 로직 재사용.
5. **Phase 5 — 공공데이터 레이어:** LOCALDATA(동물병원 ~9,445건, EPSG:5174→WGS84) · 두루누비 산책로 실데이터. `vet/shop/trail` 레이어 더미 제거.
6. **post-MVP:** 북마크, 케어 로그, 매칭/산책 크루.

---

_본 문서는 SSOT. 엔드포인트 변경 시 [ERD](../03-database/erd.md) 및 프론트 `app/lib/v2/data`·`app/lib/v2/domain`과 동기화할 것._
