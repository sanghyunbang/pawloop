# Dogs (반려견 프로필) — 백엔드 구현 청사진

> 대상: `com.heattrip.heat_trip_backend.dog` 패키지. openapi `/api/dogs`, `/api/dogs/{dogId}` CRUD + 아바타 업로드.
> ⚠️ 이 문서는 **청사진(무엇을 만들지)** 만 제공한다. 메서드 바디는 개발자가 직접 구현한다. 여기 코드는 시그니처/필드/쿼리 개요뿐이다.
>
> 참조 계약: [openapi.yaml](../../04-api/openapi.yaml) `paths./api/dogs*`, `schemas.Dog / DogInput / DogSize`
> 데이터 모델: [schema.md §2 `dog`](../../03-database/schema.md), [erd.md `dog`](../../03-database/erd.md)
> 컨벤션 출처: `social/{controller,service,repository,entity,dto}`, `user/controller/AuthController`, `S3/media/*`

---

## 1. 개요

| 항목 | 내용 |
| --- | --- |
| 리소스 책임 | 로그인 사용자의 반려견 프로필 CRUD. 목록/상세/등록/부분수정/삭제 + 아바타 이미지 업로드. |
| 소유권 규칙 | 모든 쓰기(등록 제외)·상세는 `dog.user_id == 현재 userId` 여야 한다. 타인 dog 수정/삭제 시 **403 Forbidden**. |
| 관련 테이블 | `dog`(주), `app_user`(FK 소유자). 삭제 시 `walk`가 `dog` FK를 `ON DELETE CASCADE` 하므로 산책 기록도 함께 삭제됨(구현 노트 참고). |
| 재사용 가능한 기존 자산 | ① JWT→User 추출: `@CurrentUser User me` 파라미터 하나로 받는다(#5). 인증 주체 해석은 `CurrentUserArgumentResolver` 한 곳뿐이고, 실패는 전부 **본문 없는 401** 이다 — 컨트롤러가 `Authorization` 헤더를 다시 읽거나 `findByEmail` 로 주체를 찾는 것은 금지이며 `AuthSubjectContractSpecTest` 가 소스 스캔으로 막는다. (#5 이전 서술이던 `requireUser(HttpServletRequest)` 패턴은 삭제됐다.) ② 아바타 업로드: `S3/media/MediaController`(`POST /media`, `multipart`, `UploadCategory`) + `MediaService.uploadMany/publicUrl`. ③ 에러 응답: social의 `Map.of("error", msg)` + `ResponseStatusException` 패턴. ④ 엔티티/DTO/레포 스타일: `social` 패키지(Lombok `@Getter/@Builder`, record DTO, Spring Data). |
| SSOT 주의 | `size` enum은 `small/medium/large` 3종(openapi `DogSize` = schema `ck_dog_size` CHECK 와 일치). 임의 값 금지. |

---

## 2. Controller — `DogController`

`@RestController @RequestMapping("/api/dogs")`. 메서드는 모두 `ResponseEntity<?>` 반환. 인증 사용자는 `requireUser(HttpServletRequest)`(social 패턴)로 추출. openapi paths와 1:1.

| HTTP · 경로 | 메서드 시그니처 | 반환 DTO | 인증 | openapi |
| --- | --- | --- | --- | --- |
| `GET /api/dogs` | `list(HttpServletRequest request)` | `List<DogDto>` (200) | 필요 | `/api/dogs` get |
| `POST /api/dogs` | `create(@RequestBody DogInputRequest req, HttpServletRequest request)` | `DogDto` (201) | 필요 | `/api/dogs` post |
| `GET /api/dogs/{dogId}` | `detail(@PathVariable("dogId") Long dogId, HttpServletRequest request)` | `DogDto` (200 / 404) | 필요\* | `/api/dogs/{dogId}` get |
| `PATCH /api/dogs/{dogId}` | `update(@PathVariable("dogId") Long dogId, @RequestBody DogInputRequest req, HttpServletRequest request)` | `DogDto` (200 / 403 / 404) | 필요 | `/api/dogs/{dogId}` patch |
| `DELETE /api/dogs/{dogId}` | `delete(@PathVariable("dogId") Long dogId, HttpServletRequest request)` | `Void` (204 / 403) | 필요 | `/api/dogs/{dogId}` delete |
| `POST /api/dogs/{dogId}/avatar` | `uploadAvatar(@PathVariable("dogId") Long dogId, @RequestPart("file") MultipartFile file, HttpServletRequest request)` | `DogDto` (200 / 403 / 404) | 필요 | (openapi 미기재 — 아바타 업로드 확장. `consumes=multipart/form-data`) |

- openapi `Dog` 스펙상 CRUD 응답은 순수 `Dog` 객체(커서 페이지네이션 대상 아님 — 목록은 배열 그대로). 따라서 `Page`/`nextCursor` 미적용.
- `\*` 상세(get)는 openapi에 `security` 표기가 없으나, 소유권 검증이 필요하므로 인증 유지 권장(타인 dog 열람 차단). 정책 확정 필요 시 노트 참고.
- 등록 성공은 **201 Created**(social의 `ResponseEntity.ok` 와 달리 여기선 `status(HttpStatus.CREATED)` 사용 — openapi가 201 명시).
- 아바타 업로드 엔드포인트는 `MediaController`의 multipart 규약(`@RequestPart("file") MultipartFile`)을 그대로 따른다.

---

## 3. DTO (record) — `dog/dto/`

Java `record`. 요청 `XxxRequest`, 응답 `XxxDto`. openapi schema와 매핑.

### 3.1 `DogDto` (응답) ↔ openapi `Dog`

| 필드 | 타입 | openapi `Dog` | 비고 |
| --- | --- | --- | --- |
| `id` | `Long` | `id` | |
| `name` | `String` | `name` | |
| `breed` | `String` | `breed` | nullable |
| `size` | `String` | `size` (`DogSize`) | `small/medium/large` 문자열 |
| `birth` | `String` | `birth` | `LocalDate`→ISO date 문자열(`yyyy-MM-dd`), nullable |
| `ageMonths` | `Integer` | `ageMonths` | **파생 필드** — `birth`로부터 계산(비저장). birth==null이면 null/0 정책 결정 |
| `neutered` | `boolean` | `neutered` | |
| `avatarUrl` | `String` | `avatarUrl` | nullable. 저장은 objectKey, 응답은 `MediaService.publicUrl(...)` 조립 값 |

### 3.2 `DogInputRequest` (요청) ↔ openapi `DogInput`

| 필드 | 타입 | 필수 | openapi `DogInput` | 비고 |
| --- | --- | --- | --- | --- |
| `name` | `String` | 필수 | `name` | |
| `breed` | `String` | 선택 | `breed` | |
| `size` | `String` | 필수 | `size` (`DogSize`) | 서비스에서 `small/medium/large` 검증 |
| `birth` | `String` | 선택 | `birth` | ISO date 문자열; 서비스에서 `LocalDate.parse` |
| `neutered` | `Boolean` | 선택 | `neutered` | 기본 `false`(래퍼 타입으로 두어 PATCH 부분수정 구분) |

- PATCH(부분 수정)는 `DogInputRequest` 재사용. **null=미변경** 규약(social의 `handle` null 처리 스타일). `size`는 값이 오면 검증, `name`은 create시 필수·patch시 선택으로 서비스에서 분기.
- `ageMonths`는 요청에 없고 응답 전용 파생값(`birth` → 현재일 기준 개월). 정규 저장값은 `birth`(schema.md §2 주석: "나이는 앱에서 개월 수로 표시하나 DB는 birth로 저장").
- 아바타 업로드 요청 바디는 별도 DTO 없음 — multipart `file` 파트만(MediaController와 동일).
- 공통 DTO: 에러는 별도 record 없이 social 관례대로 `Map.of("error", ...)` 사용(참조만). openapi `Error`/`Page` 스키마는 이 리소스 응답에 직접 등장하지 않음.

---

## 4. Service — `DogService` (`@Service`, `@Transactional(readOnly = true)`, 쓰기 메서드에 `@Transactional`)

메서드 시그니처 + 한 줄 책임(무엇을만; 어떻게는 개발자 구현).

| 시그니처 | 책임(한 줄) |
| --- | --- |
| `List<DogDto> listByUser(Long userId)` | 해당 사용자의 dog 전체를 등록순/이름순으로 조회해 DTO 목록 반환. |
| `DogDto create(Long userId, DogInputRequest req)` | size/name 검증 후 `Dog` 신규 저장(소유자=userId), 저장 결과를 DTO로. |
| `DogDto get(Long userId, Long dogId)` | dogId 조회 → 없으면 NOT_FOUND, 소유자 아니면 FORBIDDEN, DTO 반환. |
| `DogDto update(Long userId, Long dogId, DogInputRequest req)` | 소유권 검증 후 전달된 non-null 필드만 부분 갱신, DTO 반환. |
| `void delete(Long userId, Long dogId)` | 소유권 검증 후 삭제(연쇄 삭제 영향은 노트 참고). |
| `DogDto updateAvatar(Long userId, Long dogId, MultipartFile file)` | 소유권 검증 → `MediaService`로 업로드(카테고리 `PROFILE_IMAGE`) → `dog.avatar`에 objectKey 저장 → 응답 DTO의 `avatarUrl`은 `publicUrl`로 조립. |
| `DogDto toDto(Dog dog)` (private/헬퍼) | 엔티티→DTO 매핑(`ageMonths` 파생, `avatar`→`avatarUrl` publicUrl 변환). |
| `void requireOwner(Dog dog, Long userId)` (private 헬퍼) | `dog.userId != userId` 이면 403(`ResponseStatusException` 또는 도메인 예외). |

- 소유권 실패는 **403**, 리소스 없음은 **404** 로 구분(social은 400/500만 쓰지만, openapi Dogs는 403/404 명시하므로 `ResponseStatusException(HttpStatus.FORBIDDEN/NOT_FOUND)` 사용).
- 검증 실패(잘못된 size, name 누락)는 **400**(`IllegalArgumentException` → 컨트롤러에서 `badRequest`, social 패턴).
- `MediaService` 주입해 아바타 업로드 위임(직접 S3 접근 금지). `UploadCategory.PROFILE_IMAGE`(prefix `profiles`, image/jpeg·png·webp, 5MB) 재사용.

---

## 5. Entity & Repository

### 5.1 Entity — `dog/entity/Dog` (`@Entity @Table(name="dog")`, Lombok `@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder`)

schema.md §2 `dog` 테이블 기준. 엔티티 필드 ↔ 컬럼:

| 엔티티 필드 : 타입 | 컬럼 | 제약 | 비고 |
| --- | --- | --- | --- |
| `id : Long` | `id` | PK, `@GeneratedValue(IDENTITY)` | |
| `userId : Long` | `user_id` | FK→`app_user.id`, NOT NULL | 소유자. 인덱스 `idx_dog_user(user_id)` |
| `name : String` | `name` | `VARCHAR(50)` NOT NULL | |
| `breed : String` | `breed` | `VARCHAR(50)` NULL | |
| `size : String` | `size` | `VARCHAR(10)` NOT NULL DEFAULT `'small'`, CHECK(small/medium/large) | 문자열 저장(enum 매핑 대신 String + 서비스 검증 권장, social 스타일) |
| `birth : LocalDate` | `birth` | `DATE` NULL | |
| `neutered : boolean` | `neutered` | `BOOLEAN` NOT NULL DEFAULT FALSE | |
| `avatar : String` | `avatar` | `VARCHAR(255)` NULL | **S3 objectKey 저장**(원본 URL 아님). 응답 시 publicUrl로 변환 |
| `createdAt : LocalDateTime` | `created_at` | NOT NULL DEFAULT now, `updatable=false`, `@PrePersist` | social `EmotionCard` 패턴 |

- FK: `@ManyToOne` 매핑 대신 `userId : Long` 스칼라로 두는 것이 social(`EmotionCard.userId`) 컨벤션과 일치(연관 객체 로딩 불필요). DDL의 `fk_dog_user`는 스키마에서 이미 보장.
- 공간 컬럼 없음(POINT/LINESTRING 미해당) — SPATIAL INDEX 불필요.

### 5.2 Repository — `dog/repository/DogRepository extends JpaRepository<Dog, Long>`

| 메서드 시그니처 | 용도 |
| --- | --- |
| `List<Dog> findByUserIdOrderByIdAsc(Long userId)` | 사용자별 dog 목록(파생 쿼리, social `findAllByOrderByIdDesc` 스타일). |
| `Optional<Dog> findByIdAndUserId(Long id, Long userId)` | 상세/수정/삭제 시 조회+소유권 동시 필터(선택). 소유권을 서비스에서 명시적으로 403 구분하려면 `findById` 후 비교 방식도 가능. |

- native/공간 `@Query` **불필요**(공간 컬럼 없음). 전부 Spring Data 파생 쿼리로 충분.
- 삭제는 `deleteById` 또는 `delete(entity)` 사용(연쇄 삭제는 DB FK가 처리).

---

## 6. 구현 노트 (함정 위주)

1. **JWT 추출 규약(재사용)**: `@CurrentUser User me` 파라미터 하나로 받는다(#5). 인증 주체 해석은 `CurrentUserArgumentResolver` 한 곳뿐이고, 실패는 전부 **본문 없는 401** 이다 — 컨트롤러가 `Authorization` 헤더를 다시 읽거나 `findByEmail` 로 주체를 찾는 것은 금지이며 `AuthSubjectContractSpecTest` 가 소스 스캔으로 막는다. subject 는 `users.id` 이고 `me.getId()` 를 그대로 `dog.user_id` 에 쓴다.
2. **소유자 검증(403 핵심)**: 상세/수정/삭제/아바타 모두 조회한 `dog.userId`와 현재 `userId` 비교 필수. 불일치 시 **404가 아니라 403**(openapi가 403 Forbidden 명시). 단, "리소스 존재 은닉" 보안 정책을 택하면 타인 dog를 404로 숨기는 변형도 가능 — 팀 정책 확정 후 통일.
3. **`ageMonths` 파생**: 저장 금지, 응답 시 `birth`↔현재일로 계산(`Period.between(birth, LocalDate.now()).toTotalMonths()`). `birth==null`이면 null 반환할지 0으로 둘지 openapi에 미정의 → 프론트와 합의(권장: null).
4. **`birth` 직렬화**: 요청/응답 모두 ISO `yyyy-MM-dd` 문자열. 엔티티는 `LocalDate`. 파싱 실패는 400으로.
5. **아바타 업로드 프록시(직접 S3 금지)**: `MediaService`에 위임. `UploadCategory.PROFILE_IMAGE`(prefix `profiles`, 허용 image/jpeg·png·webp, 최대 5MB) 사용. 검증(타입/크기)은 `S3/ImageValidator`·`UploadValidator`가 담당하므로 중복 검증 불필요. `dog.avatar`에는 **objectKey**를 저장하고, DTO의 `avatarUrl`은 `mediaService.publicUrl(objectKey)`로 조립(원본 URL을 DB에 박지 말 것 — CDN/버킷 변경 대응).
6. **PATCH 부분수정 null 규약**: `DogInputRequest`의 래퍼 타입(`Boolean neutered` 등)으로 "미전송(null)=미변경" vs "false로 변경"을 구분. primitive로 두면 이 구분이 불가능하니 주의.
7. **좌표/공간 없음**: Dogs는 EPSG:5174→WGS84, `ST_Distance_Sphere`, SPATIAL INDEX 모두 **해당 없음**(그건 `place`/`walk`/`trail` 리소스 사항). 여기선 신경 쓸 필요 없음.
8. **트랜잭션**: `DogService`에 `@Transactional(readOnly=true)` 기본 + 쓰기 메서드(`create/update/delete/updateAvatar`)에 `@Transactional`(social `SocialService` 패턴 동일).
9. **삭제 연쇄 영향**: `walk.fk_walk_dog ON DELETE CASCADE`, (post-MVP `care_log`도 CASCADE). dog 삭제 시 산책 기록이 함께 사라진다 — 하드삭제 정책이 맞는지 확인. 소프트삭제가 필요하면 스키마 변경(현재 스키마엔 `deleted_at` 없음) → MVP는 하드삭제로 진행.
10. **아바타 교체/고아 파일**: 아바타를 새로 올리면 기존 objectKey는 `MediaObject`로 남아 고아가 될 수 있음. `MediaService.replace(mediaId,...)` 또는 업로드 후 구 키 삭제 정책을 선택(교체 API를 쓰려면 media id를 dog가 참조해야 함 — 단순화하려면 dog는 objectKey만 들고, 교체 시 이전 키 삭제는 후속 정리 작업으로 둠).
11. **응답 코드**: 등록 201, 삭제 204, 수정/상세/아바타 200. social이 200 위주였던 것과 달리 openapi Dogs 스펙(201/204)을 우선 준수.
