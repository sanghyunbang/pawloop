# 테이블 스키마 (MySQL DDL)

> Pawloop(포루프) MySQL 공간형 스키마의 테이블별 상세 정의(DDL). 각 테이블의 컬럼·타입·제약·인덱스(특히 `SPATIAL INDEX`)·FK를 명세한다. GPS 산책 경로는 `walk.path`(`LINESTRING`), 장소 좌표는 `place.geom`(`POINT`)에 공간 컬럼으로 저장하고 `SPATIAL INDEX` + `ST_Distance_Sphere`/`MBRContains`로 주변 검색을 수행한다. **가족 케어 공유**와 **채팅** 기능으로 `family_group`·`chat_room`·`chat_room_member`·`chat_room_invite`·`chat_message`·`walk_note` 테이블이 추가되고, `care_log`는 `group_id`/`done_by`를 더해 가족 공유 케어 기록으로 확장된다. 방·멤버십·초대는 가족 그룹에 종속되지 않는 범용 3테이블이고, `family_group` 은 `origin_kind`/`origin_ref` 쌍으로 방에 **불투명하게** 닿는다([ADR-0011](../99-decisions/decision-log.md#adr-0011--채팅은-가족-그룹-종속이-아니라-범용-다중-방이다)). 전체 관계는 [ERD](./erd.md) 참조.

## 공통 규약

| 항목 | 규칙 |
| --- | --- |
| 스토리지 엔진 | `InnoDB` (FK·트랜잭션). 단, 공간 컬럼에 `SPATIAL INDEX`를 걸려면 해당 컬럼은 `NOT NULL` + `SRID 4326` 지정. |
| 문자셋 | `utf8mb4` / `utf8mb4_unicode_ci` (이모지·다국어). |
| PK | `BIGINT AUTO_INCREMENT`. |
| 좌표계(SRID) | WGS84 = **4326**. 공간 컬럼은 `SRID 4326` 고정, `ST_Distance_Sphere`로 미터 거리 산출. |
| 시각 | `DATETIME`(앱 로컬 시각 저장) 또는 `TIMESTAMP`(생성/수정 자동). 기본 `created_at`/`updated_at` 부여. |
| 좌표 순서 | MySQL `POINT(x, y)` = `POINT(경도 lng, 위도 lat)`. KTO `mapx=경도`, `mapy=위도`와 매핑. |

> 공간 컬럼은 MySQL 8.0 기준 `SRID 4326`을 명시해야 `SPATIAL INDEX`와 `ST_Distance_Sphere`가 올바르게 동작한다. 좌표 삽입 시 `ST_GeomFromText('POINT(127.0 37.5)', 4326)` 형태를 사용한다.

> **어디까지가 실재인가.** 정본은 `backend/mysql/init/01_schema.sql` 이고 JPA 엔티티가 그 스키마를 만든다 — 거기에 표가 **48개** 있다(전체 목록은 [부록 A](#부록-a-정본의-표-48개--어디에-적혀-있나)). 이 문서에 절이 있는 실재 표는 `§1 users` · `§2 refresh_token` · `§3 dog` · `§4 walk` · `§6 trail_route` · `§7 post` · `§8 comment` · `§9 reaction` · `§11 family_group` · `§12 chat_room` · `§13 chat_room_member` · `§14 chat_room_invite` · `§15 chat_message` · `§16 walk_note` · `§17 care_log` · `§18 emotion_card` · `§19 card_comment` · `§20 card_reaction` · `§21 kto_call_budget` · `§22 place_cell` · `§23 pet_place_detail` · `§24 place_catalog` · `§25 report` · `§26 report_snapshot` · `§27 user_block` · `§28 user_consent` · `§31 course` · `§32 walk_dog` 스물여덟이다. 나머지 절(`§5 place` · `§10 bookmark`)은 아직 **계획**이며, 마일스톤이 오면 여기 적힌 모양대로 만든다. 절이 없는 21개는 감정 여행·관광 수집 시절의 표라 부록 A 에만 적었다 — 지우지 않고 격리한다(#174). 둘을 섞어 읽으면 "있는 줄 알았는데 없는" 테이블에 쿼리를 짜게 된다. `DocDriftTest` 가 정본·절 제목·부록·ERD 넷을 대조한다(#176).
>
> 절마다 제목에 **실재**를 달아 두었으니 목록을 세지 말고 제목을 보면 된다.

---

## 1. `users` — 사용자 계정 (**실재**)

앱이 실제로 쓰는 사용자 테이블이다. 이름이 `users` 인 것은 감정여행(heattrip) 시절부터 있던 테이블을 그대로 이어받았기 때문이고(ADR-0001), JPA 엔티티가 `@Table(name = "users")` 로 그 이름을 고정한다(`backend/.../user/entity/User.java`).

> **각주 — `app_user` 는 어디로 갔나.** 피벗 당시 이 문서와 [ERD](./erd.md)는 새 사용자 테이블을 `app_user` 라는 이름으로 계획했다. 실제로는 새로 만들지 않고 기존 `users` 를 확장하는 쪽으로 갔다(마이그레이션 비용 회피 — ADR-0002 가 `applicationId` 를 그대로 둔 것과 같은 이유). 그래서 이 문서의 `app_user` 는 **한 번도 존재한 적 없는 이름**이었다. 지금은 `users` 로 통일한다.
>
> **정본은 이 문서가 아니다.** 운영 스키마의 정본은 `backend/mysql/init/01_schema.sql` 이고, 그 파일은 JPA 엔티티에서 뽑은 것이다. `SchemaDdlDriftTest` 가 엔티티와 정본이 어긋나면 빨간불을 낸다(#58). 아래 DDL 은 **읽기용 요약**이며, 값이 다르면 정본을 따른다.

소셜 계정의 식별 키는 `(provider, social_id)` 쌍이다 — **이메일이 아니다**(#7). 카카오의 `account_email` 은 선택 동의라서 사용자가 거부하면 이메일이 오지 않고, 시간에 따라 나타났다 사라지는 값은 식별 키가 될 수 없다. 공급자 집합(`kakao`·`google`)은 [ADR-0010](../99-decisions/decision-log.md#adr-0010--소셜-로그인-공급자와-앱-세션-토큰-전략) 이 정한다.

```sql
CREATE TABLE users (
  id                  BIGINT       NOT NULL AUTO_INCREMENT,

  -- 계정 출처 / 식별
  provider            VARCHAR(20)  NULL COMMENT 'local|kakao|google — naver 는 ADR-0010 에서 보류',
  social_id           VARCHAR(191) NULL COMMENT '소셜 공급자가 발급한 고유 ID. 이메일 가입자는 NULL',
  username            VARCHAR(255) NULL COMMENT '레거시 소셜 식별자(예: google_123456). 백필용으로만 남아 있다',
  role                VARCHAR(20)  NOT NULL COMMENT '기본 ROLE_USER. 토큰 발급이 이 값을 쓴다',

  -- 로그인
  email               VARCHAR(255) NULL COMMENT '로그인 ID. 카카오가 이메일을 주지 않으면 NULL 이다',
  password            VARCHAR(255) NULL COMMENT 'BCrypt 해시. 응답에 절대 싣지 않는다(@JsonIgnore)',

  -- 프로필
  name                VARCHAR(255) NULL,
  nickname            VARCHAR(255) NULL COMMENT '소셜 가입 경로에서는 설정되지 않아 NULL 일 수 있다',
  gender              ENUM('MALE','FEMALE','OTHER') NULL,
  age                 INT          NULL,
  age_group           ENUM('OVER14','UNDER14') NULL,
  image_url           VARCHAR(255) NULL,
  travel_type         VARCHAR(255) NULL COMMENT '감정여행(heattrip) 시절 잔재 — ADR-0001',

  -- 동네 (#342). 사용자가 스스로 고른 행정동 코드다 — 단말이 잰 좌표가 아니라 위치정보가 아니고,
  -- 그래서 신고 전(A안 #235)에도 서버가 든다. 좌표 컬럼을 나란히 두지 않는 것이 그 선이다.
  neighborhood_code   VARCHAR(10)  NULL COMMENT '통계청 행정동 코드 10자리. 앞 5자리가 시군구',

  -- 약관 동의 컬럼은 없다. `user_consent` 표(19_user_consent.sql, #190)가 문서별·버전별 이력으로 든다.
  -- 옛 아홉 컬럼(agree_* / *_version / *_agreed_at)은 21 번 스크립트가 값을 옮긴 뒤 지웠다.

  created_at          DATETIME(6)  NULL,
  updated_at          DATETIME(6)  NULL,

  PRIMARY KEY (id),
  UNIQUE KEY uk_users_provider_social_id (provider, social_id),
  UNIQUE KEY uk_users_email (email),
  KEY idx_users_neighborhood (neighborhood_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK, AUTO_INCREMENT | **JWT 의 `sub` 가 이 값이다**(ADR-0010) |
| `provider` | `VARCHAR(20)` | NULL, UNIQUE(provider, social_id) | `local`/`kakao`/`google`. 백필 전 옛 행은 NULL |
| `social_id` | `VARCHAR(191)` | NULL, UNIQUE(provider, social_id) | 191자 = utf8mb4 기준 InnoDB 단일 컬럼 인덱스 상한(767바이트) 관례값 |
| `username` | `VARCHAR(255)` | NULL | 레거시 식별자. 백필 SQL(`mysql/post-start/04_...`)이 이 값을 분해해 위 두 컬럼을 채운다 |
| `role` | `VARCHAR(20)` | **NOT NULL** | `ROLE_USER` 기본. 엔티티의 `@Builder.Default` + `@PrePersist` 가 보장 |
| `email` | `VARCHAR(255)` | **NULL**, UNIQUE | 카카오 미동의 시 NULL. UNIQUE 인덱스는 NULL 을 서로 다른 값으로 보므로 여럿이어도 충돌하지 않는다 |
| `password` | `VARCHAR(255)` | NULL | 소셜 가입자는 NULL. 직렬화 금지 |
| `gender` / `age` / `age_group` / `image_url` | | NULL | 프로필 |
| `travel_type` | `VARCHAR(255)` | NULL | 감정여행 잔재. 정리 대상 |
| `agree_*` / `*_version` / `*_agreed_at` | | NULL | 약관 동의 플래그·버전·시각 |
| `created_at` / `updated_at` | `DATETIME(6)` | NULL | `@PrePersist`/`@PreUpdate` 가 채운다 |

---

## 2. `refresh_token` — refresh 토큰 원장 (**실재**)

앱 세션의 refresh 토큰을 담는 원장이다(#9). RT 는 JWT 가 아니라 **불투명 랜덤 문자열**이고(`SecureRandom` 32바이트 → 패딩 없는 Base64URL 43자), 서버는 원문이 아니라 **SHA-256 해시**를 저장한다. 왜 JWT 가 아닌지는 [ADR-0010](../99-decisions/decision-log.md#adr-0010--소셜-로그인-공급자와-앱-세션-토큰-전략) 의 대안 4 에 있다.

한 행 = 토큰 1개다. 여러 기기로 로그인하면 행이 여럿 생긴다.

```sql
CREATE TABLE refresh_token (
  id         BIGINT      NOT NULL AUTO_INCREMENT,
  user_id    BIGINT      NOT NULL COMMENT 'users.id. FK 제약은 걸려 있지 않다(정본 DDL 기준)',
  token_hash VARCHAR(64) NOT NULL COMMENT 'RT 원문의 SHA-256. 원문은 어디에도 저장하지 않는다',
  expires_at DATETIME(6) NOT NULL COMMENT '발급 + 14일(jwt.refresh-expiration)',
  revoked_at DATETIME(6) NULL     COMMENT '폐기 시각',
  created_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_refresh_token_token_hash (token_hash),
  KEY idx_refresh_token_user_id (user_id),
  KEY idx_refresh_token_expires_at (expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
```

> ⚠️ **폐기는 삭제가 아니다.** 로그아웃·회전·재사용 감지는 행을 남긴 채 `revoked_at` 을 찍는다. 지우면 폐기된 RT 가 다시 왔을 때 "없는 토큰" 과 구별되지 않아 **재사용 감지가 통째로 무력해진다.** 행을 실제로 지우는 것은 탈퇴 정리와 만료 정리(`RefreshTokenPurgeScheduler`) 둘뿐이다.

---

## 3. `dog` — 반려동물 프로필 (**실재**)

사용자의 반려동물 프로필. `users` 1:N `dog`. 앱 도메인(`DogProfile`)의 `size`(small/medium/large)·`neutered`·`avatar`와 매핑. 나이는 앱에서 개월 수로 표시하나 DB는 `birth`(생일)로 저장하는 것이 정규.

> **표 이름이 `dog` 인데 고양이도 들어온다.** `species` 열이 종을 구분한다(#24 · #145). 표와 경로 이름을 `pet` 으로 옮기지 않은 이유는 `walk.dog_id`·`care_log.dog_id`·`/api/dogs`·`WalkInput.dogId` 가 이미 여러 곳에 박혀 있어서, 이름을 바꾸면 그 전부를 같은 변경에서 함께 옮겨야 하기 때문이다.

```sql
CREATE TABLE dog (
  id       BIGINT      NOT NULL AUTO_INCREMENT,
  user_id  BIGINT      NOT NULL,
  name     VARCHAR(50) NOT NULL,
  species  VARCHAR(10) NOT NULL DEFAULT 'dog' COMMENT 'dog|cat|other',
  breed    VARCHAR(50) NULL COMMENT '품종 (예: 믹스견)',
  size     VARCHAR(10) NOT NULL DEFAULT 'small' COMMENT 'small|medium|large',
  birth    DATE        NULL,
  neutered BOOLEAN     NOT NULL DEFAULT FALSE,
  avatar   VARCHAR(255) NULL COMMENT '아바타 에셋/이미지 경로',
  created_at DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at DATETIME(6) NULL COMMENT '소프트 삭제 시각(UTC). NULL 이면 살아 있다 — #156',
  PRIMARY KEY (id),
  KEY idx_dog_user (user_id),
  CONSTRAINT fk_dog_user FOREIGN KEY (user_id)
    REFERENCES users (id) ON DELETE CASCADE,
  CONSTRAINT ck_dog_size CHECK (size IN ('small','medium','large')),
  CONSTRAINT ck_dog_species CHECK (species IN ('dog','cat','other'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | |
| `user_id` | `BIGINT` | FK→`users.id`, NOT NULL, INDEX | 소유 사용자 |
| `name` | `VARCHAR(50)` | NOT NULL | 이름 |
| `species` | `VARCHAR(10)` | NOT NULL 기본 `'dog'`, CHECK | 종. 없으면 고양이를 등록할 경로가 없다 |
| `breed` | `VARCHAR(50)` | NULL | 품종 |
| `size` | `VARCHAR(10)` | NOT NULL, CHECK | 소/중/대형견 |
| `birth` | `DATE` | NULL | 생일(나이 산출) |
| `neutered` | `BOOLEAN` | NOT NULL 기본 FALSE | 중성화 여부 |
| `avatar` | `VARCHAR(255)` | NULL | 아바타 경로 |
| `deleted_at` | `DATETIME(6)` | NULL | **소프트 삭제**(#156). `DELETE /api/dogs/{dogId}` 가 찍고 행은 남긴다. 모든 조회가 `deleted_at IS NULL` 을 건다 |

> **`created_at`·`deleted_at` 은 UTC 다 (#306).** `Dog` 의 `@PrePersist` 가 `LocalDateTime.now()`(JVM 존)를 찍고 있었다 — 개발 기계(KST)와 배포 컨테이너(UTC)가 같은 표에 두 존을 섞는다. `DogTime.nowUtc()` 로 맞췄고, `StoredTimestampsAreUtcTest` 가 이제 모든 엔티티 패키지를 훑는다(그 검사가 `chat`·`group`·`user` 만 보고 있어서 못 잡았다). 응답에 안 나가는 값이라 이미 들어간 KST 행은 그대로 둔다.
>
> **삭제는 소프트 삭제다 (#156).** `walk.fk_walk_dog` 가 `CASCADE` 라 행을 지우면 그 아이의 산책 이력 전부가 조용히 함께 사라진다. FK 를 `RESTRICT` 로 바꾸면 탈퇴(`users` 하드 삭제)가 막힌다. 그래서 안전은 FK 가 아니라 `deleted_at` 으로 산다 — `DogRepository` 의 세 쿼리 전부가 `deleted_at IS NULL` 을 걸고, 산책 목록·통계는 이 컬럼을 보지 않는다("계속 센다"). 지운 아이는 상한(20마리)에 세지 않는다. 이미 있는 DB 는 `23_dog_deleted_at.sql`.

---

## 4. `walk` — 산책 기록 (GPS 경로) (**실재**)

산책 1건. GPS 경로를 `LINESTRING`으로 저장하고 거리(`distance_m`)·시간(`duration_s`)·메모·날씨를 함께 보관. 페이스는 `distance_m`/`duration_s`로 파생(비저장).

> **함께 나간 아이들은 `walk_dog`(§32)가 든다 (#343).** `dog_id` 는 남지만 이제 **대표 아이**(앱이 고른 목록의 첫 마리)라는 뜻이다 — 두 마리를 함께 데리고 나간 산책은 `walk_dog` 에 두 줄이 된다. **아이별 통계·목록은 `dog_id` 가 아니라 `walk_dog` 를 본다.** `dog_id` 로 좁히면 둘째 아이의 산책이 통째로 사라지고, 오류가 안 나므로 아무도 모른다.

> **[ADR-0015](../99-decisions/decision-log.md#adr-0015--산책-경로는-linestring-으로-저장하되-spatial-index-는-만들지-않는다) 로 두 줄이 바뀌었다.** 원래 이 절은 `path` 를 `NOT NULL` 로 두고 `SPATIAL INDEX spx_walk_path` 를 걸었다. 인덱스를 뺀 이유는 저장소에 **`walk` 를 공간으로 묻는 질의가 하나도 없어서**이고, `NOT NULL` 을 푼 이유는 MySQL 이 `SPATIAL INDEX` 에 `NOT NULL` 을 요구하는데 **경로 없는 산책이 실제로 있기 때문**이다 — 손으로 입력한 기록과 위치 권한을 거부한 기록이 그렇다. 없는 경로를 만들어 넣으면 화면이 거짓말을 한다.

```sql
CREATE TABLE walk (
  id          BIGINT     NOT NULL AUTO_INCREMENT,
  dog_id      BIGINT     NOT NULL,
  started_at  DATETIME(6) NOT NULL COMMENT 'UTC. 앱이 보낸 값 — 커서로 쓰지 않는다',
  ended_at    DATETIME(6) NULL COMMENT 'UTC',
  distance_m  INT        NOT NULL DEFAULT 0 COMMENT '총 거리(m)',
  duration_s  INT        NOT NULL DEFAULT 0 COMMENT '총 소요(초)',
  path        LINESTRING SRID 4326 NULL COMMENT 'GPS 경로(폴리라인). 손입력·권한거부 기록은 NULL',
  memo        VARCHAR(500) NULL,
  weather     VARCHAR(30)  NULL,
  client_walk_id VARCHAR(64) NOT NULL COMMENT '앱이 만드는 멱등키(UUID v4)',
  place_source     VARCHAR(16)  NULL COMMENT '카탈로그 출처 kto|vet|shop|trail (#338). FK 없음 — 스냅숏',
  place_content_id VARCHAR(64)  NULL COMMENT '카탈로그 contentId. place_source 와 짝',
  place_name       VARCHAR(120) NULL COMMENT '화면에 나갈 이름. 손으로 적으면 이것만 채워진다',
  created_at  DATETIME(6) NOT NULL COMMENT 'UTC, 서버 시각 — 목록 커서의 기준',
  PRIMARY KEY (id),
  KEY idx_walk_dog (dog_id, started_at),
  KEY idx_walk_dog_created (dog_id, created_at, id) COMMENT '목록 커서. started_at 이 아닌 이유는 아래 참조',
  KEY idx_walk_place (place_source, place_content_id) COMMENT '"자주 가는 곳" 을 묶어 세는 순서 (#338)',
  UNIQUE KEY uq_walk_client (dog_id, client_walk_id),
  CONSTRAINT fk_walk_dog FOREIGN KEY (dog_id)
    REFERENCES dog (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | |
| `dog_id` | `BIGINT` | FK→`dog.id`, NOT NULL, INDEX(dog_id,started_at) | **대표 아이** (#343). 함께 나간 아이 전부는 `walk_dog`(§32)에 있고, 이 아이도 거기 한 줄 들어간다. 지우지 않는 이유 셋: 멱등키 `uq_walk_client` 의 앞자리, 소유권이 이 연관을 타고 `dog.user_id` 로 감, 이미 쌓인 기록이 전부 이 컬럼으로 이어져 있음 |
| `started_at` | `DATETIME` | NOT NULL | 시작 시각 |
| `ended_at` | `DATETIME` | NULL | 종료 시각(진행 중이면 NULL) |
| `distance_m` | `INT` | NOT NULL 기본 0 | 거리(m) |
| `duration_s` | `INT` | NOT NULL 기본 0 | 소요(초) |
| `path` | `LINESTRING` | **SRID 4326**, NULL | GPS 경로 폴리라인. 경로 없는 산책이 있다 |
| `memo` | `VARCHAR(500)` | NULL | 메모 |
| `weather` | `VARCHAR(30)` | NULL | 날씨 |
| `client_walk_id` | `VARCHAR(64)` | NOT NULL, UNIQUE(dog_id, ·) | 멱등키. 재전송이 두 줄이 되지 않게 한다 |
| `place_source` | `VARCHAR(16)` | NULL, INDEX(place_source, place_content_id) | 카탈로그 출처 `kto`·`vet`·`shop`·`trail` (#338). **FK 없음** — `place_catalog` 는 월 1회 통째로 갈아 끼우므로 FK 를 걸면 적재가 막히거나 참조가 깨진다. 값을 베껴 두는 스냅숏이다 |
| `place_content_id` | `VARCHAR(64)` | NULL | 카탈로그 `contentId`. `place_source` 와 **짝** — 하나만 오면 400 |
| `place_name` | `VARCHAR(120)` | NULL | 화면에 나갈 이름. 카탈로그에 없는 곳은 이것만 채워지고, 그때는 "자주 가는 곳" 에 안 들어간다 |

> **시각은 전부 UTC 로 저장한다.** 애플리케이션이 `Instant` 를 UTC 벽시계로 눕혀 넣는다 — `LocalDateTime` 은 드라이버가 시간대 변환을 하지 않는 유일한 타입이라, JDBC URL 의 `serverTimezone` 이나 컨테이너 시계가 무엇이든 넣은 값이 그대로 나온다. **이 저장소의 JDBC URL 은 `Asia/Seoul` 인데 컨테이너 시계는 UTC 다**(실측). 주 경계 계산도 Java 가 한다 — `WEEKDAY()`·`CURDATE()` 는 세션 시간대를 읽고, #40 에서 그 함정이 00:00–09:00 KST 에만 터졌다.
>
> **`client_walk_id` 가 없으면 전송이 타임아웃 났을 때 앱이 두 경우를 구분할 수 없다** — 서버에 안 닿은 것인지, 저장은 됐는데 응답만 못 받은 것인지. 다시 보내면 두 줄이 되고 안 보내면 사라진다. `chat_message.client_msg_id` + `uq_chat_msg_client`(§15)와 같은 장치다.
>
> **목록 커서는 `created_at` 기준이다(`started_at` 이 아니다).** `started_at` 은 앱이 보낸 값이라, 오프라인에 쌓아 둔 산책이 며칠 뒤 과거 시각으로 들어온다. 그걸 커서로 쓰면 **이미 발급된 커서보다 아래 날짜의 행이 영원히 건너뛰어진다.** `idx_walk_dog(dog_id, started_at)` 은 주간 통계 집계가 쓴다.
>
> **`SRID` 는 `SchemaDdlDriftTest` 가 못 잡는다.** `information_schema.columns.column_type` 이 `linestring` 뿐이라 SRID 가 들어 있지 않다(ADR-0015 실측). 마이그레이션 사후검증에서 `st_geometry_columns.srs_id` 로 따로 본다.

---

---

## 5. `place` — 장소 POI 캐시 (좌표 POINT)

동반장소(KTO)·동물병원·펫샵(LOCALDATA) POI 캐시. 좌표를 `POINT`로 저장하고 `SPATIAL INDEX`로 주변 검색. 공공데이터 원본은 `raw_json`에 보관. `source + external_id`로 중복 방지.

```sql
CREATE TABLE place (
  id          BIGINT      NOT NULL AUTO_INCREMENT,
  source      VARCHAR(30) NOT NULL COMMENT 'kto_pet|localdata_vet|localdata_shop',
  external_id VARCHAR(64) NULL COMMENT '원본 고유 ID(KTO contentid 등)',
  category    VARCHAR(30) NULL COMMENT 'contenttypeid 또는 vet/shop/trail',
  name        VARCHAR(150) NOT NULL,
  geom        POINT       SRID 4326 NOT NULL COMMENT '좌표 POINT(lng, lat)',
  addr        VARCHAR(255) NULL,
  tel         VARCHAR(40)  NULL,
  raw_json    JSON         NULL COMMENT '공공데이터 원본',
  updated_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
                           ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_place_src (source, external_id),
  KEY idx_place_category (category),
  SPATIAL INDEX spx_place_geom (geom)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | |
| `source` | `VARCHAR(30)` | NOT NULL | `kto_pet`/`localdata_vet`/`localdata_shop` |
| `external_id` | `VARCHAR(64)` | UNIQUE(source,external_id) | 원본 ID(KTO `contentid` 등) |
| `category` | `VARCHAR(30)` | INDEX | KTO `contenttypeid`(12/14/28/32/38/39) 또는 `vet`/`shop`/`trail` |
| `name` | `VARCHAR(150)` | NOT NULL | 장소명 |
| `geom` | `POINT` | **SRID 4326, NOT NULL, SPATIAL INDEX** | `POINT(경도, 위도)` |
| `addr` | `VARCHAR(255)` | NULL | 주소(KTO `addr1`) |
| `tel` | `VARCHAR(40)` | NULL | 전화 |
| `raw_json` | `JSON` | NULL | 원본 응답 |
| `updated_at` | `DATETIME` | 갱신 자동 | 캐시 갱신 시각 |

> KTO 좌표는 `mapx`(경도)→`POINT` X, `mapy`(위도)→ Y. LOCALDATA 동물병원 좌표는 `EPSG:5174→WGS84(4326)` 변환 후 삽입. 삽입 예: `ST_GeomFromText('POINT(127.0 37.5)', 4326)`.

**주변 검색 예:**
```sql
SELECT id, name, ST_Distance_Sphere(geom, ST_GeomFromText('POINT(127.0 37.5)',4326)) AS dist_m
FROM place
WHERE category = '39'
  AND MBRContains(
        ST_MakeEnvelope(
          ST_GeomFromText('POINT(126.93 37.43)',4326),
          ST_GeomFromText('POINT(127.07 37.57)',4326)),
        geom)
ORDER BY dist_m ASC
LIMIT 80;
```

---

## 6. `trail_route` — 산책로 코스의 선 (**실재**)

두루누비(걷기여행길) 코스 하나의 경로 — [`24_place_catalog_layers.sql`](../../backend/mysql/post-start/24_place_catalog_layers.sql) · #291. 원본 GPX 를 Douglas–Peucker 로 **300점 이하**로 줄여 `payload` 에 `[[경도, 위도], …]` JSON 으로 둔다 — 응답(`GET /api/places/trails/{courseId}/route`)의 `points` 그대로라 꺼내서 객체로 만들지 않는다(§24 와 같은 원칙). 카탈로그(§24 `durunubi` 행)에는 코스의 **시작점**(`start_lat`/`start_lng`)만 실리고 선은 사용자가 그 산책로를 눌렀을 때 따로 나간다 — 2,000 코스의 선을 한 벌에 실으면 16MB 다. `length_m` 은 줄이기 전 원본의 길이다. FK 는 없다 — `course_id` 는 두루누비의 `crsIdx` 다. `fetched_at` 은 §24 와 같은 **서비스 존 벽시계**로, "다시 받을 때가 됐는가" 에만 쓴다.

> 2026-09-06 이전 이 절은 `LINESTRING` + `SPATIAL INDEX` 의 `trail` 표를 **계획**으로 적고 있었다. 만들지 않았다 — 근접 조회는 카탈로그의 시작점으로 하고 선은 키로 한 건씩 꺼내므로 공간 인덱스가 할 일이 없다(ADR-0013 의 `walk` 판단과 같다).

```sql
CREATE TABLE `trail_route` (
  `length_m` int NOT NULL,
  `point_count` int NOT NULL,
  `start_lat` double NOT NULL,
  `start_lng` double NOT NULL,
  `fetched_at` datetime(6) NOT NULL,
  `course_id` varchar(32) NOT NULL,
  `name` varchar(150) NOT NULL,
  `payload` longtext NOT NULL,
  PRIMARY KEY (`course_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `course_id` | `VARCHAR(32)` | PK | 두루누비 `crsIdx`. 카탈로그 항목의 `contentId` 는 `trail:` + 이 값 |
| `name` | `VARCHAR(150)` | NOT NULL | 코스명 |
| `point_count` | `INT` | NOT NULL | 줄인 뒤 남은 점 수(≤ 300) |
| `length_m` | `INT` | NOT NULL | 원본 선의 길이(m) |
| `start_lat` / `start_lng` | `DOUBLE` | NOT NULL | 선의 첫 점 — 카탈로그의 `Place.lat/lng` |
| `payload` | `LONGTEXT` | NOT NULL | `[[경도, 위도], …]` JSON |
| `fetched_at` | `DATETIME(6)` | NOT NULL | 받은 시각(서비스 존 벽시계) |

---

## 7. `post` — 커뮤니티 게시글 (**실재**)

커뮤니티 글. 게시판(`board`)으로 분류하고 장소를 선택 태그할 수 있다(`content_id` nullable). `users` 1:N `post`.

```sql
CREATE TABLE post (
  id          BIGINT       NOT NULL AUTO_INCREMENT,
  user_id     BIGINT       NULL COMMENT '작성자. 탈퇴하면 NULL 이 된다',
  board       VARCHAR(20)  NOT NULL COMMENT 'walk_review|pet_place|health|free|brag',
  title       VARCHAR(200) NOT NULL,
  body        TEXT         NOT NULL,
  content_id  VARCHAR(64)  NULL COMMENT '연결 장소. Place.contentId 와 같은 키. FK 없음',
  course_id   BIGINT       NULL COMMENT '붙은 코스(#339). FK → course.id ON DELETE SET NULL',
  dog_id      BIGINT       NULL COMMENT '찍힌 아이(#451 5번). FK → dog.id ON DELETE SET NULL',
  loc         VARCHAR(100) NULL COMMENT '표시용 장소 이름',
  handle      VARCHAR(50)  NULL COMMENT '작성 시점 닉네임 스냅샷. 응답에는 안 싣는다',
  created_at  DATETIME(6)  NOT NULL,
  PRIMARY KEY (id),
  KEY idx_post_board_created (board, created_at, id),
  KEY idx_post_user (user_id),
  KEY idx_post_dog (dog_id, created_at, id),
  CONSTRAINT fk_post_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE SET NULL,
  CONSTRAINT fk_post_dog FOREIGN KEY (dog_id) REFERENCES dog (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | |
| `user_id` | `BIGINT` | FK→`users.id` **SET NULL**, nullable | 작성자. 탈퇴하면 `NULL` — 아래 각주 |
| `board` | `VARCHAR(20)` | NOT NULL, INDEX(board, created_at, id) | 게시판. **ASCII 키다** — 아래 각주 |
| `title` | `VARCHAR(200)` | NOT NULL | 제목 |
| `body` | `TEXT` | NOT NULL | 본문 |
| `content_id` | `VARCHAR(64)` | nullable, **FK 없음** | 연결 장소. `Place.contentId` 와 같은 키 |
| `course_id` | `BIGINT` | nullable, FK→`course.id` **SET NULL** | 붙은 코스(#339). 코스를 지워도 글은 남고 연결만 빈다. 붙일 수 있는 것은 내 것이면서 공개된 코스뿐이고, 그 판정은 서버가 한다 |
| `dog_id` | `BIGINT` | nullable, FK→`dog.id` **SET NULL**, INDEX(dog_id, created_at, id) | 찍힌 아이(#451 5번, `41_post_dog.sql`). 글 하나에 아이 하나. 내 아이만 붙고 그 판정은 서버가 한다. 아이 사진첩이 `?dogId=` 로 이 인덱스를 탄다 |
| `loc` | `VARCHAR(100)` | nullable | 표시용 장소 이름. `content_id` 와 별개다 |
| `handle` | `VARCHAR(50)` | nullable | 작성 시점 닉네임 스냅샷 |

> **각주 — `board` 는 왜 ASCII 인가.** 2026-09 이전 계약은 값 자체가 한글 표시 문자열이었다
> (`"산책로 후기"` 등). 그 값이 **query 파라미터로 나가고 이 컬럼에 들어간다.** 표시 문구를
> 저장하면 게시판 이름을 다듬는 날 **쌓인 행을 전부 고쳐야 한다.** `CareType` 이 이미 같은
> 모양이다 — 값은 `water|meal|walk|med|vet|poop|pee` 이고 "물/밥/산책/투약/병원/배변/마킹" 은 앱이 붙인다.
>
> `CHECK` 는 걸지 않는다. 게시판은 **제품이 늘리는 목록**이라 값이 늘 때마다 마이그레이션이
> 따라오면 그 자체가 비용이다. 케어 종류는 다섯으로 굳었고 늘리는 날이 M4 로 못 박혀 있다.

> **각주 — 장소 참조에 FK 가 없는 이유.** 반려 앱의 장소는 KTO 프록시 **캐시**
> (`pet_place_detail`, PK `content_id varchar(64)`)에서 온다. 사용자가 고른 장소의 캐시 행이
> 아직 없거나 지워질 수 있고, FK 를 걸면 **그때 글 작성이 실패한다** — 장소는 글의 부속물이지
> 전제가 아니다. 레거시 `places` 표(`contentid bigint`)에는 걸지 않는다. 다른 키 공간이다.

> **각주 — `users` FK 가 `SET NULL` 인 이유. 양쪽으로 틀릴 수 있는 자리다.**
>
> | | 무슨 일이 나는가 |
> |---|---|
> | `CASCADE` | 탈퇴 한 번에 그 사람의 글이 사라지고 **거기 달린 남의 댓글도 함께** 사라진다 |
> | 아무것도 안 적음(= `RESTRICT`) | **글을 한 번 쓴 사람이 영원히 탈퇴하지 못한다** |
>
> 후자가 처음 낸 모양이었고 실측으로 확인했다 — `UserService.deleteMe` 가 `users` 행을
> **물리 삭제**하므로 `DELETE FROM users` 가 `ERROR 1451` 로 죽는다. `11_dog.sql` 이 `dog` 에
> 대해 적어 둔 것과 같은 실패인데, `dog` 은 `CASCADE` 로 풀고 여기는 `SET NULL` 로 푼다 —
> 반려동물은 그 사람의 것이지만 **글에는 남의 댓글이 매달려 있다.**
>
> `care_log.done_by` 가 이미 이 모양이다. `user_id` 가 `NULL` 인 행은 "탈퇴한 사람이 쓴 것"
> 이고, 응답의 `author` 는 `userId=0`·"알 수 없음" 이다(ADR-0017 규약 5).
> `handle`(작성 시점 스냅샷)이 여기서 값을 한다 — `users` 행이 사라진 뒤 **그 글을 누가
> 썼는지 아는 유일한 기록**이다. 다만 응답에는 여전히 안 싣는다.

---

## 8. `comment` — 댓글 (**실재**)

게시글 댓글. `post` 1:N, `users` 1:N.

```sql
CREATE TABLE comment (
  id          BIGINT      NOT NULL AUTO_INCREMENT,
  post_id     BIGINT      NOT NULL,
  user_id     BIGINT      NULL COMMENT '작성자. 탈퇴하면 NULL',
  body        TEXT        NOT NULL,
  handle      VARCHAR(50) NULL COMMENT 'post.handle 과 같은 이유',
  created_at  DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  KEY idx_comment_post_created (post_id, created_at, id),
  KEY idx_comment_user (user_id),
  CONSTRAINT fk_comment_post FOREIGN KEY (post_id)
    REFERENCES post (id) ON DELETE CASCADE,
  CONSTRAINT fk_comment_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | |
| `post_id` | `BIGINT` | FK→`post.id` **CASCADE**, NOT NULL | 대상 글 |
| `user_id` | `BIGINT` | FK→`users.id` **SET NULL**, nullable | 작성자. 탈퇴하면 `NULL` |
| `body` | `TEXT` | NOT NULL | 내용 |
| `handle` | `VARCHAR(50)` | nullable | 작성 시점 닉네임 스냅샷 |

> **각주 — `post` 쪽만 CASCADE 인 이유.** 글이 사라지면 그 댓글은 **부모 없는 행**으로 남아
> 어느 목록에도 안 뜨면서 자리만 차지한다. 나중에 세면 댓글 수가 맞지 않고 왜 안 맞는지
> 아무도 모른다. 사용자 쪽은 `SET NULL` 이다 — 탈퇴해도 댓글이 남아야 **남의 글에서 대화가
> 안 끊긴다.** §7 의 각주와 같은 판단이다.

> **각주 — 수정·삭제 컬럼이 없다.** `updated_at`·`deleted_at` 을 넣지 않았다. 계약에 그
> 오퍼레이션이 없고(#211 `Community-medium-4`), **넣는 날은 컬럼 추가가 아니라 삭제 정책
> 결정**이다 — 지운 댓글 자리를 목록에서 어떻게 다룰지가 먼저다.

---

## 9. `reaction` — 반응 (**실재**)

게시글 반응(도움돼요/귀여워요/공감). **사용자당 글마다 여러 종류**를 누를 수 있다. `post` 1:N, `users` 1:N.

```sql
CREATE TABLE reaction (
  id          BIGINT      NOT NULL AUTO_INCREMENT,
  post_id     BIGINT      NOT NULL,
  user_id     BIGINT      NULL COMMENT '누른 사람. 탈퇴하면 NULL',
  type        VARCHAR(20) NOT NULL COMMENT 'help|cute|empathy',
  created_at  DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_reaction (post_id, user_id, type),
  KEY idx_reaction_user (user_id),
  CONSTRAINT fk_reaction_post FOREIGN KEY (post_id)
    REFERENCES post (id) ON DELETE CASCADE,
  CONSTRAINT fk_reaction_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | |
| `post_id` | `BIGINT` | FK→`post.id` **CASCADE**, UNIQUE(post, user, type) | 대상 글 |
| `user_id` | `BIGINT` | FK→`users.id` **SET NULL**, nullable | 누른 사람. 탈퇴하면 `NULL` |
| `type` | `VARCHAR(20)` | NOT NULL | `help`(도움돼요)/`cute`(귀여워요)/`empathy`(공감) |

> **각주 — UNIQUE 가 세 컬럼인 이유([ADR-0016](../99-decisions/decision-log.md#adr-0016--커뮤니티-착수-전-결정-셋--신고는-미루고-반응은-복수로-열고-게스트-읽기는-메서드-축으로-연다) 결정 2).**
> 도움돼요·귀여워요·공감은 **서로 배타적인 개념이 아니다** — 한 글이 도움도 되고 귀엽기도 하다.
>
> `(post_id, user_id)` 로 좁히면 라디오가 되고, 나중에 넓히려면 계약의 파괴적 변경이다.
> 반대로 넓게 두었다가 좁히려면 **행을 지우는 마이그레이션**이라 어느 반응을 남길지 제품이
> 다시 답해야 한다. **넓은 쪽이 되돌리기 싸다.**

> **각주 — 이 UNIQUE 가 멱등을 딛는다.** 계약의 쓰기는 토글이 아니라
> `POST`/`DELETE .../reactions/{type}` 둘이고 **둘 다 멱등**이다. 동시성으로 이 제약이 깨지면
> 그것은 "이미 눌렀다" 와 같은 뜻이므로 삼키고 최신 집계를 돌려준다.
>
> 2026-09 이전에는 `POST .../reactions` 하나가 토글이었다. 요청에 의도가 없어서 **네트워크
> 재시도 한 번이 사용자의 반응을 조용히 되돌렸다.**

> **각주 — 카운트는 "몇 번" 이지 "몇 명" 이 아니다.** 한 사람이 셋을 다 누를 수 있다.
> 화면이 "7명이 공감했어요" 로 읽히게 쓰면 거짓말이 된다.

> **각주 — `CHECK` 를 걸지 않는다.** `care_log.type` 은 걸었는데 여기는 안 건다. 반응 종류는
> **제품이 늘릴 수 있는 목록**이고 계약의 `ReactionType` 이 단일 출처다. 값이 늘 때마다
> 마이그레이션이 따라오면 그 자체가 비용이다.

---

## 10. `bookmark` — 장소 저장

사용자가 저장한 장소. `users`·`place` 각각 1:N, 사용자-장소 조합 유니크.

```sql
CREATE TABLE bookmark (
  id         BIGINT   NOT NULL AUTO_INCREMENT,
  user_id    BIGINT   NOT NULL,
  place_id   BIGINT   NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_bookmark (user_id, place_id),
  KEY idx_bookmark_place (place_id),
  CONSTRAINT fk_bookmark_user FOREIGN KEY (user_id)
    REFERENCES users (id) ON DELETE CASCADE,
  CONSTRAINT fk_bookmark_place FOREIGN KEY (place_id)
    REFERENCES place (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | |
| `user_id` | `BIGINT` | FK→`users.id`, NOT NULL, UNIQUE(user,place) | 저장한 사람 |
| `place_id` | `BIGINT` | FK→`place.id`, NOT NULL, INDEX | 저장 대상 |

---

## 11. `family_group` — 가족 케어 그룹 (**실재**)

가족이 함께 반려를 돌보는 그룹. **이름과 생성 시각만 든다** — 초대코드도 멤버십도 여기 없다. 초대는 `chat_room_invite`(§14), 멤버십은 `chat_room_member`(§13)가 가지고, 이 그룹의 방은 `chat_room`(§12)이 `origin_kind='FAMILY'` / `origin_ref=family_group.id` 로 **불투명하게** 가리킨다. `chat_room` → `family_group` 방향 FK 는 없고, `chat_room` 의 `UNIQUE(origin_kind, origin_ref)` 가 같은 그룹에 방이 둘 생기는 것을 DB 수준에서 막는다([ADR-0011](../99-decisions/decision-log.md#adr-0011--채팅은-가족-그룹-종속이-아니라-범용-다중-방이다)).

> **예전 정의에는 `invite_code VARCHAR(12)` + `UNIQUE KEY uq_group_invite` 가 있었다.** 그건 그룹당 코드 하나가 영구히 사는 모양이라 만료·사용횟수·폐기를 걸 자리가 없고, 코드를 바꾸려면 그룹 행을 UPDATE 해야 해서 누가 언제 발급했는지가 남지 않는다. 초대코드는 §14 로 나갔다. `post-start/07_family_group.sql` 의 사전 점검이 이 컬럼을 발견하면 마이그레이션을 중단한다.

> **이 표에 행을 넣는 곳은 하나다.** `FamilyGroupService.create` 이고, 그 메서드가 **같은 트랜잭션에서** `chat_room`(§12)과 `chat_room_member(role='OWNER')`(§13)을 함께 INSERT 한다(이슈 #75). 문을 하나로 둔 이유는 "방 없는 그룹" 을 만들 방법 자체를 없애기 위해서다 — 방이 없으면 초대코드를 발급할 사람이 없어 아무도 못 들어온다. 방향은 **group → chat** 한쪽이고, 그 반대(chat 이 이 표를 아는 것)는 `ChatBoundaryArchitectureTest` 가 막는다.

```sql
CREATE TABLE family_group (
  id          BIGINT      NOT NULL AUTO_INCREMENT,
  name        VARCHAR(50) NOT NULL,
  created_at  DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | `chat_room.origin_ref` 가 이 값을 문자열로 든다 |
| `name` | `VARCHAR(50)` | NOT NULL | 그룹 이름 |
| `created_at` | `DATETIME` | NOT NULL, 기본 now | 생성 시각 |

---

## 12. `chat_room` — 채팅방 (범용) (**실재**)

방은 가족 그룹에 종속되지 않는다. `origin_kind`(방을 만든 도메인)와 `origin_ref`(그 도메인의 id 를 문자열로) 한 쌍으로 출처를 들고, 산책 크루 방처럼 가족이 아닌 방도 같은 표에 산다. **`last_seq` 는 `chat_message.room_seq` 의 발급 카운터이자 미읽음 뺄셈의 좌변이다** — 두 값이 다른 문장에서 움직여 어긋날 여지를 없애려고 한 컬럼으로 둔다.

```sql
CREATE TABLE chat_room (
  id          BIGINT      NOT NULL AUTO_INCREMENT,
  origin_kind VARCHAR(20) NOT NULL COMMENT '방을 만든 도메인 — FAMILY 등',
  origin_ref  VARCHAR(64) NOT NULL COMMENT '그 도메인의 id 를 문자열로 — FK 아님',
  name        VARCHAR(50) NOT NULL COMMENT '방 이름',
  tag         VARCHAR(20) NOT NULL COMMENT '화면이 방 종류를 가르는 꼬리표 — 가족·산책 크루',
  last_seq    BIGINT      NOT NULL DEFAULT 0 COMMENT 'room_seq 발급 카운터 = 미읽음 뺄셈의 좌변',
  created_at  DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_chat_room_origin (origin_kind, origin_ref)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | |
| `origin_kind` | `VARCHAR(20)` | NOT NULL, UNIQUE(kind,ref) | 출처 도메인 이름 |
| `origin_ref` | `VARCHAR(64)` | NOT NULL, UNIQUE(kind,ref) | 출처의 id. **FK 를 걸지 않는다** |
| `name` | `VARCHAR(50)` | NOT NULL | 방 이름 |
| `tag` | `VARCHAR(20)` | NOT NULL | 화면이 방 종류를 가르는 꼬리표 |
| `last_seq` | `BIGINT` | NOT NULL, 기본 0 | 발급기. `UPDATE ... SET last_seq = LAST_INSERT_ID(last_seq + 1)` 로 올린다 |
| `created_at` | `DATETIME` | NOT NULL, 기본 now | 생성 시각 |

> **각주 — 왜 `title` 이 아니라 `name` 이고, 왜 `tag` 가 붙었나.** 이 절의 예전 초안은 이름 컬럼을 `title` 로 적고 `tag` 를 빼먹었다. 이미 커밋돼 있는 당시 앱에 있던 `ChatRoom`(`pet.dart` — **#81 에서 제거됐다**)이 `name:` 과 `tag:` 를 요구하고, `chat_list_screen.dart` 는 두 방을 같은 화면으로 넘기면서 **종류를 `tag` 로만 가른다.** [ADR-0011](../99-decisions/decision-log.md#adr-0011--채팅은-가족-그룹-종속이-아니라-범용-다중-방이다)의 출발점이 "화면이 먼저 커밋돼 있고 그 화면이 데이터 모양을 정해 놨다" 인 이상, 이름이 갈리면 API 계층이 매번 두 이름을 옮겨 적어야 한다. 그래서 화면 쪽으로 맞췄다.

> 발급과 메시지 INSERT 는 **하나의 트랜잭션**이다. 발급만 별도 트랜잭션으로 떼면 `id` 커서와 똑같은 구멍(§15 참조)이 생긴다. 락 순서는 **`chat_room` → `chat_room_invite` → `chat_room_member` → `chat_message`** 하나이고, 이 넷 중 둘 이상을 잡는 경로는 전부 이 순서를 따른다 — 전송은 첫째와 넷째, 참여는 앞의 셋을 잡으므로 둘 다 같은 방향의 부분열이라 순환이 없다(`ChatRoomRepository#lockForMemberChange` javadoc 이 정본이다). **락을 쥔 트랜잭션 안에서 외부 호출(푸시·S3)을 하지 않는다** — `innodb_lock_wait_timeout` 이 기본 50초라 느린 호출 하나가 그 방의 전송을 전부 막는다.

---

## 13. `chat_room_member` — 방 멤버십 (**실재**)

멤버십 표는 이것 하나다. **`group_member` 를 따로 만들지 않는다** — 둘을 두면 "가족인데 방에 없는 사람" 같은 상태가 생기고 그걸 막는 코드를 영원히 쓴다. 강퇴·재입장 금지가 전부 여기 붙는다. **행을 지우지 않는다**: 미읽음이 `last_read_seq` 뺄셈이라 지우면 되돌릴 수 없다.

```sql
CREATE TABLE chat_room_member (
  id             BIGINT      NOT NULL AUTO_INCREMENT,
  room_id        BIGINT      NOT NULL,
  user_id        BIGINT      NOT NULL COMMENT 'users.id — FK 없음(경계)',
  role           VARCHAR(10) NOT NULL DEFAULT 'MEMBER' COMMENT 'OWNER|MEMBER',
  joined_at      DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_read_seq  BIGINT      NOT NULL DEFAULT 0 COMMENT '미읽음 = room.last_seq − 이 값',
  removed_at     DATETIME    NULL COMMENT '강퇴 시각 — 행은 남긴다',
  removed_by     BIGINT      NULL COMMENT '강퇴한 방장(users.id) — FK 없음',
  rejoin_blocked BIT(1)      NOT NULL DEFAULT b'0' COMMENT '강퇴 = 재입장 금지',
  muted_at       DATETIME(6) NULL COMMENT '방별 음소거 시각 — NULL 이면 알림이 간다 (#83)',
  PRIMARY KEY (id),
  UNIQUE KEY uq_chat_member (room_id, user_id),
  KEY idx_chat_member_user (user_id),
  CONSTRAINT fk_chat_member_room FOREIGN KEY (room_id)
    REFERENCES chat_room (id) ON DELETE CASCADE,
  CHECK (role IN ('OWNER','MEMBER'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

> **각주 — 왜 `BOOLEAN` 이 아니라 `BIT(1)` 인가.** Hibernate 는 `boolean` 필드를 `bit(1)` 로 만든다 — 정본(`backend/mysql/init/01_schema.sql`)도 `post-start/06_chat_rooms.sql` 도 그 타입으로 적혀 있다. MySQL 에서 `BOOLEAN` 은 `TINYINT(1)` 의 별칭이라, 이 절을 그대로 손으로 실행한 DB 는 정본과 **다른 타입**을 갖게 되고 prod 는 `ddl-auto=validate` 라 그 차이가 부팅에서 드러난다. 문서가 정본을 따라가는 자리다.

> **각주 — CHECK 에 이름을 붙이지 않는다.** Hibernate 가 `@Enumerated(STRING)` 매핑에서 이 CHECK 를 스스로 만드는데 무명이라, MySQL 이 `chat_room_member_chk_1` 로 붙인다. 여기서만 `ck_chat_member_role` 이라고 이름을 주면 같은 내용의 제약이 두 개 생기거나(엔티티에 `@Check` 를 함께 달았을 때 — 실측), `mysql/init` 으로 세운 DB 와 `mysql/post-start` 로 세운 DB 의 제약 이름이 갈린다.

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | |
| `room_id` | `BIGINT` | FK→`chat_room.id`, NOT NULL, UNIQUE(room,user) | 소속 방 |
| `user_id` | `BIGINT` | NOT NULL, INDEX, **FK 없음** | 멤버(`users.id` 값만) |
| `role` | `VARCHAR(10)` | NOT NULL 기본 MEMBER, CHECK | `OWNER` 만 강퇴·초대 회수를 한다 |
| `joined_at` | `DATETIME` | NOT NULL, 기본 now | 참여 시각 |
| `last_read_seq` | `BIGINT` | NOT NULL, 기본 0 | `GREATEST`·`LEAST` 로만 갱신 — 뒤로 못 가고 `room.last_seq` 를 넘지 못한다. 읽음 보고뿐 아니라 **메시지 전송**도 발신자의 값을 그 메시지까지 올린다(#330) |
| `removed_at` | `DATETIME` | NULL | 강퇴 시각 |
| `removed_by` | `BIGINT` | NULL, **FK 없음** | 강퇴한 방장 |
| `rejoin_blocked` | `BIT(1)` | NOT NULL, 기본 `b'0'` | 유효한 초대코드로도 다시 못 들어온다 |
| `muted_at` | `DATETIME(6)` | NULL | 방별 음소거 시각 — 이 방의 알림이 안 간다(#83). `PUT /api/chat/rooms/{roomId}/mute`. 멤버십의 속성이라 여기 있다 |

---

## 14. `chat_room_invite` — 초대코드 (**실재**)

초대코드를 그룹 행의 컬럼 하나로 두지 않고 별도 표에 둔다. 유효기간·사용횟수·회수를 처음부터 갖추고, **누가 언제 발급했는지가 남는다.** 기본값은 **7일 · 사용 횟수 무제한**이다. 방장이 `DELETE /api/chat/rooms/{roomId}/invites/{code}` 로 **회수**하면 그 코드에 즉시 `revoked_at` 이 찍히고 **기존 멤버는 그대로 남는다** — 코드가 유출됐을 때의 대응 수단이다. 폐기한 `code` 는 UNIQUE 라 재사용하지 않는다.

> **재발급은 이전 코드를 죽이지 않는다.** 2026-08 이전에는 이 문단이 발급을 다시 하면 옛 코드에 `revoked_at` 이 찍힌다고 적었는데, 구현은 한 번도 그렇게 하지 않았다(`ChatRoomService.issueInvite` 는 새 행을 저장할 뿐이다). 발급을 두 번 하면 코드 둘이 각각 TTL 동안 독립된 열쇠로 산다. 유출 대응은 **유출된 그 코드를 지목해 `DELETE` 하는 것뿐**이고, 코드 문자열을 잃어버렸을 때의 목록 조회·일괄 회수는 M2.6 이다. 이 문장은 `DocDriftTest` 가 지킨다.

```sql
CREATE TABLE chat_room_invite (
  id         BIGINT      NOT NULL AUTO_INCREMENT,
  room_id    BIGINT      NOT NULL,
  code       VARCHAR(32) NOT NULL COMMENT '초대코드',
  created_by BIGINT      NOT NULL COMMENT 'users.id — FK 없음(경계)',
  expires_at DATETIME    NULL COMMENT 'NULL = 무기한. 기본은 발급 + 7일',
  max_uses   INT         NULL COMMENT 'NULL = 무제한(기본)',
  used_count INT         NOT NULL DEFAULT 0,
  revoked_at DATETIME    NULL COMMENT '회수 시각. 재발급은 이전 코드를 건드리지 않는다',
  created_at DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_chat_invite_code (code),
  KEY idx_chat_invite_room (room_id, created_at),
  CONSTRAINT fk_chat_invite_room FOREIGN KEY (room_id)
    REFERENCES chat_room (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | |
| `room_id` | `BIGINT` | FK→`chat_room.id`, NOT NULL, INDEX(room,created_at) | 대상 방 |
| `code` | `VARCHAR(32)` | NOT NULL, UNIQUE | `POST /api/chat/invites/{code}/join` 이 쓰는 값 |
| `created_by` | `BIGINT` | NOT NULL, **FK 없음** | 발급한 방장 |
| `expires_at` | `DATETIME` | NULL | 만료 — `INVITE_EXPIRED`(410) |
| `max_uses` | `INT` | NULL | 사용 상한 — 넘으면 `INVITE_USES_EXHAUSTED`(409) |
| `used_count` | `INT` | NOT NULL, 기본 0 | 사용 횟수 |
| `revoked_at` | `DATETIME` | NULL | 회수 — `INVITE_REVOKED`(410) |
| `created_at` | `DATETIME` | NOT NULL, 기본 now | 발급 시각 |

---

## 15. `chat_message` — 채팅 메시지 (**실재**)

방 안의 메시지. 조회는 `afterSeq`(델타·오름차순) 또는 `beforeSeq`(과거·내림차순)이고 MVP 는 폴링이다. 소켓은 실측 트리거가 걸릴 때만 연다(M2.9).

**`id` 를 커서로 쓰지 않는다.** `AUTO_INCREMENT` 는 **배정 시점**에 정해지고 커밋 순서와 다르다. 늦게 커밋된 작은 `id` 가 뒤늦게 보이면 `afterId` 폴링은 그 메시지를 **영구히** 건너뛴다. `room_seq` 는 방 단위로 빈틈 없이 발급하므로 델타·순서·미읽음이 전부 이 하나로 풀린다.

**`sender_user_id` 에 FK 를 걸지 않는다.** chat 경계 밖으로 FK 를 내지 않는 것이 이 도메인의 규칙이고, `refresh_token`(#9)이 이미 같은 방식이다. 탈퇴한 사용자의 메시지가 남아야 대화가 읽히므로 `ON DELETE CASCADE` 는 특히 안 된다 — 예전 정의의 `fk_chat_user ... ON DELETE CASCADE` 는 탈퇴 한 번에 남의 대화 흐름을 지운다.

**`sender_name` 은 스냅샷이고, 응답의 `senderName` 은 그 값이 아니다.** 폭은 `users.nickname varchar(255)` 와 같다. 응답의 이름은 `users` 에 있으면 **현재 닉네임**(닉네임을 바꾸면 과거 메시지도 따라 바뀐다 — 카카오·라인이 그렇다), 없으면(탈퇴) **"알 수 없음"** 이다.

> **각주 — 그러면 스냅샷은 무엇을 하나 (이슈 [#78](https://github.com/sanghyunbang/heattrip/issues/78)).** 이 절의 예전 초안은 "닉네임이 바뀌어도 과거 대화의 화자는 바뀌지 않는다" 와 "응답은 현재 닉네임" 을 나란히 적었는데, 그 둘은 같은 값을 두고 반대말을 한다. 응답의 이름은 **현재 닉네임**이고, 그 해석은 chat 밖에서 한다(`chatweb.ChatSenderNames`, 조립은 `chatweb.ChatMessages`) — chat 은 `users` 를 이름으로 부를 수도 조인할 수도 없기 때문이다(결정 4, `ChatBoundaryArchitectureTest`). **즉 응답 경로는 `sender_name` 을 읽지 않는다.** 그런데도 컬럼을 두는 이유는 그 값이 답하는 질문이 따로 있어서다: **"그때 방 안의 사람들이 무슨 이름으로 그 말을 봤는가."** 닉네임은 언제든 바뀌므로, 신고를 받아 `idx_chat_sender` 로 발신자의 메시지를 훑는 시점에는 그 이름이 이미 사라져 있다. `emotion_card.handle`·`card_comment.handle` 이 같은 자리다.

**컬럼 폭은 `ChatRoomService#postMessage` 가 먼저 본다 — 컬럼은 마지막 방어선이다.** `sender_name`(255) 만 검사가 있던 판을 실제로 돌려 보니, 클라이언트가 실제로 보내는 셋(`body`·`content_type`·`client_msg_id`)은 전부 INSERT 까지 내려가 `Data too long for column …` → **500** 이 났다. `GlobalExceptionHandler` 에 `DataIntegrityViolationException` 핸들러가 없어 캐치올이 잡기 때문이고, `openapi.yaml` 의 전송 오퍼레이션은 500 을 선언하지 않는다. 지금은 넷 다 400 이다. **`body` 는 문자가 아니라 바이트로 센다** — `TEXT` 가 65,535바이트라 UTF-8 3바이트인 한글은 22,000자면 이미 넘는다. `varchar(n)` 셋은 코드포인트로 센다 — 자바 `length()` 로 세면 이모지 닉네임(보조평면 문자)이 컬럼에 들어가는데도 400 으로 거절당한다.

**`client_msg_id` 에 `UNIQUE (room_id, sender_user_id, client_msg_id)` 를 건다.** 재전송 멱등의 근거다 — 없으면 지하철에서 타임아웃된 전송을 앱이 재시도할 때 같은 말이 두 줄 남고, 그 둘은 서로 다른 `room_seq` 를 가져 어느 쪽도 지울 근거가 없다. MySQL 의 UNIQUE 인덱스는 `NULL` 을 여러 번 허용하므로 멱등키 없는 전송은 막지 않는다.

**범위에 `sender_user_id` 가 들어 있는 것이 요점이다(#79).** #78 은 `(room_id, client_msg_id)` 로 세웠는데, 그 범위에서는 같은 방의 멤버 A·B 가 같은 키를 쓰면 B 의 요청이 **200 과 함께 A 의 메시지**를 받고 B 가 하려던 말은 어디에도 남지 않는다(실측). B 의 앱은 200 을 성공으로 읽으므로 재시도조차 하지 않는다. 멱등키가 막아야 하는 것은 "같은 사람의 같은 요청이 두 번 도착하는 것" 이고, 재시도는 언제나 보낸 사람 자신이 한다. 좁히는 방향이라 이미 쌓인 데이터가 새 제약을 어길 수 없다.

```sql
CREATE TABLE chat_message (
  id             BIGINT       NOT NULL AUTO_INCREMENT,
  room_id        BIGINT       NOT NULL,
  room_seq       BIGINT       NOT NULL COMMENT '방 안에서 빈틈 없이 1씩 증가',
  sender_user_id BIGINT       NOT NULL COMMENT 'users.id — FK 없음(경계)',
  sender_name    VARCHAR(255) NOT NULL COMMENT '발신 시점 표시 이름 스냅샷 — 응답의 이름은 아니다',
  content_type   VARCHAR(16)  NOT NULL DEFAULT 'text',
  body           TEXT         NOT NULL,
  client_msg_id  VARCHAR(64)  NULL COMMENT '재전송 멱등키. NULL 은 여러 번 허용된다',
  created_at     DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  deleted_at     DATETIME(6)  NULL COMMENT '삭제는 소프트 — 뺀 자리가 seq 빈틈이 되면 안 된다',
  PRIMARY KEY (id),
  UNIQUE KEY uq_chat_room_seq (room_id, room_seq),
  UNIQUE KEY uq_chat_msg_client (room_id, sender_user_id, client_msg_id),
  KEY idx_chat_sender (sender_user_id),
  CONSTRAINT fk_chat_room FOREIGN KEY (room_id)
    REFERENCES chat_room (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | **커서로 쓰지 않는다** |
| `room_id` | `BIGINT` | FK→`chat_room.id`, NOT NULL, UNIQUE(room,seq) | 소속 방 |
| `room_seq` | `BIGINT` | NOT NULL, UNIQUE(room,seq) | 방별 순서. 델타·미읽음의 유일한 근거 |
| `sender_user_id` | `BIGINT` | NOT NULL, INDEX, **FK 없음** | 발신자(`users.id` 값만) |
| `sender_name` | `VARCHAR(255)` | NOT NULL | 발신 시점 표시 이름 스냅샷 — 위 각주 |
| `content_type` | `VARCHAR(16)` | NOT NULL, 기본 `text` | 본문 종류 |
| `body` | `TEXT` | NOT NULL | 메시지 본문. `LONGTEXT` 가 아니다 |
| `client_msg_id` | `VARCHAR(64)` | NULL, UNIQUE(room,sender,client) | 재전송 멱등키 |
| `created_at` | `DATETIME(6)` | NOT NULL, 기본 now | 전송 시각 |
| `deleted_at` | `DATETIME(6)` | NULL | 소프트 삭제 |

**`room_seq` 발급은 한 문장이다.** `UPDATE chat_room SET last_seq = LAST_INSERT_ID(last_seq + 1) WHERE id = ?` 로 올리고 같은 트랜잭션에서 `SELECT LAST_INSERT_ID()` 로 내 번호를 읽는다. 방을 읽어 `+1` 해서 쓰는 판은 두 트랜잭션이 같은 값을 읽어 같은 번호를 쓴다 — 스레드 20개로 재현했고 `Duplicate entry '1-1' for key 'uq_chat_room_seq'` 가 났다(#78). **발급과 INSERT 가 한 트랜잭션이라 롤백이 번호를 되돌린다** — `AUTO_INCREMENT` 와 달리 실패한 요청이 번호를 태우지 않는 이유가 그것이다.

**`deleted_at` 은 톰스톤이다 — 조회에서 거르지 않는다.** 빼면 그 `room_seq` 가 클라이언트에 도달하지 않는다. 미읽음이 `room.last_seq − member.last_read_seq` 뺄셈이라 읽음 커서가 그 번호를 넘지 못하고 **뱃지가 영원히 안 지워진다**. 본문을 가리는 것은 응답을 만드는 쪽의 일이지 조회에서 빼는 것이 아니다.

---

## 16. `walk_note` — 산책 주의사항 (가족 공유 메모) (**실재**)

산책 시 주의사항을 가족이 공유하는 메모. **그룹당 한 장**이다 (`GET|PUT /api/groups/{groupId}/walk-notes`). 이슈 [#76](https://github.com/sanghyunbang/heattrip/issues/76).

> **2026-08 에 모양이 바뀌었다 — 이 절은 그 전까지 1:N 목록이었다.** 행마다 `created_at` 을 두고 PUT 은 `{notes:[...]}` 로 전량 교체하는 모양이었는데, 그러면 PUT 때마다 행을 지우고 다시 넣게 되어 행마다 붙는 `updated_by`·`id` 가 매번 갈린다 — "누가 고쳤는지" 가 사실은 아무것도 가리키지 않는다. 이슈 #76 이 정한 `walk_note(id, group_id, body, updated_by, updated_at)` 한 장으로 맞췄고 `openapi.yaml`·`api-spec.md` 도 함께 고쳤다. **앱이 줄 단위 목록으로 그리는 것은 화면의 표현이다** — 서버가 아는 것은 메모 한 장과 그것을 마지막으로 고친 사람뿐이다.

```sql
CREATE TABLE walk_note (
  id         BIGINT       NOT NULL AUTO_INCREMENT,
  group_id   BIGINT       NOT NULL,
  body       VARCHAR(500) NOT NULL COMMENT '산책 시 주의사항 — 그룹당 한 장',
  updated_by BIGINT       NULL COMMENT '마지막으로 고친 사람(users.id). 탈퇴하면 NULL 이다',
  updated_at DATETIME(6)  NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_walknote_group (group_id),
  KEY fk_walknote_updatedby (updated_by),
  CONSTRAINT fk_walknote_group FOREIGN KEY (group_id)
    REFERENCES family_group (id) ON DELETE CASCADE,
  CONSTRAINT fk_walknote_updatedby FOREIGN KEY (updated_by)
    REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | |
| `group_id` | `BIGINT` | FK→`family_group.id`, NOT NULL, **UNIQUE** | 소속 그룹. UNIQUE 가 "그룹당 한 장" 을 지킨다 |
| `body` | `VARCHAR(500)` | NOT NULL | 메모 전문. 빈 문자열은 "다 지웠다" 는 정상 상태다 |
| `updated_by` | `BIGINT` | FK→`users.id` nullable, **ON DELETE SET NULL** | 마지막으로 고친 사람. 그 사람이 탈퇴하면 `NULL` — 아래 경고 참조 |
| `updated_at` | `DATETIME(6)` | NOT NULL | 마지막으로 고친 시각 |

> `UNIQUE (group_id)` 가 없으면 애플리케이션의 "있으면 고치고 없으면 만든다"(확인-후-쓰기)를 동시에 통과한 두 요청이 메모를 둘 만들고, 조회는 그중 하나만 보여 준다. 마지막 방어선은 DB 다(📌 [#86](https://github.com/sanghyunbang/heattrip/issues/86) 원칙 5).

> ### ⚠️ `updated_by` 는 `ON DELETE SET NULL` 이다 — CASCADE 였다가 고쳤다
>
> 2026-08 까지 이 FK 는 `ON DELETE CASCADE` 였다. 그 상태에서 엄마가 메모를 쓰고 `DELETE /auth/me` 로 탈퇴하면(`UserService.deleteMe` 는 `users` 행을 실제로 지운다) **그룹의 메모 행이 통째로 사라졌다.** 남은 가족의 화면은 "아직 주의사항이 없어요" 를 그리므로 **지워진 것과 한 번도 안 쓴 것을 구별할 수 없다** — 사라졌다는 신호가 아무 데도 없다. 지워지는 내용이 "계단 피하기"·"대형견 만나면 리드줄 짧게" 같은 안전 메모라 실사용 피해가 크다.
>
> 판단의 요점은 **이 컬럼이 문서의 소유자가 아니라 메타데이터**라는 것이다. 메모의 주인은 `group_id` 이고 그 그룹은 살아 있다. `care_log.group_id` 가 이미 같은 질문에 `SET NULL` 로 답했다(가족을 해산했다는 이유로 개인의 케어 이력이 증발하면 안 된다). **사람이 사라지면 이름만 잃는다** — 응답의 표시 이름은 `User.UNKNOWN_DISPLAY_NAME`(`알 수 없음`)으로 떨어지고, `GroupMemberResponse.nickname` 이 같은 상황에서 이미 그 문구를 쓴다.
>
> FK 만 고치는 것으로는 부족했다. `WalkNoteRepository.findByGroupId` 의 fetch join 이 **inner** 인 동안은 행이 DB 에 남아도 쿼리가 못 찾아 서비스가 빈 본문을 답했다 — 화면에서는 CASCADE 로 지우던 것과 글자 하나 다르지 않다. 지금은 `left join fetch` 다. `CareSharingIntegrationTest.whenOneMemberWithdraws_theFamilysNotesAndLogsSurvive` 가 둘을 함께 잠근다.

---

## 17. `care_log` — 케어 로그 (가족 케어 공유) (**실재**)

물/밥/산책/투약/병원 다섯 종류의 케어를 누가(`done_by`)·언제(`occurred_at`) 했는지 기록해 가족 그룹(`group_id`)에 공유한다. **이중 급여와 산책 누락을 막는 것**이 이 표의 목적이다. 이슈 [#76](https://github.com/sanghyunbang/heattrip/issues/76).

**같은 종류를 하루에 두 번 찍어도 두 행이 남는다.** 두 번째가 실수인지 사실인지 서버는 모르고(아침·저녁 두 번 주는 집에서 두 번째 밥은 정상이다), 막으면 실제로 한 일이 기록에서 사라진다. 확인 문구는 앱이 조회 결과를 보고 만든다.

**`done_by` 도 `ON DELETE SET NULL` 이다** — 여기도 2026-08 까지 CASCADE 였다. 그러면 엄마가 탈퇴하는 순간 "오늘 엄마가 산책을 다녀왔다" 가 **아빠 화면에서도** 사라지고, 이 표가 막으려는 사고(산책 누락)가 바로 그 자리에서 생긴다. 기록은 엄마의 소유물이 아니라 **가족이 함께 보는 사건**이다. 판단의 근거는 [§16 의 경고](#16-walk_note--산책-주의사항-가족-공유-메모)와 같고, `CareLogRepository.findDayOfGroup` 의 fetch join 이 **left** 여야 하는 이유도 같다 — inner 면 `done_by` 가 `NULL` 인 행이 조회에서 조용히 빠져 CASCADE 와 구별되지 않는다.

```sql
CREATE TABLE care_log (
  id          BIGINT       NOT NULL AUTO_INCREMENT,
  dog_id      BIGINT       NULL COMMENT '대상 반려동물(dog.id). FK 는 #154 에서 걸었다 — 값은 아직 항상 NULL 이다(쓰기 경로가 dogId 를 안 받는다, #209 Dogs-high-3)',
  group_id    BIGINT       NULL COMMENT '가족 그룹 공유(nullable — 미소속 시 개인 기록)',
  type        VARCHAR(10)  NOT NULL COMMENT 'water|meal|walk|med|vet|poop|pee',
  done_by     BIGINT       NULL COMMENT '수행자(users.id) — 토큰의 사용자다. 탈퇴하면 NULL 이다',
  occurred_at DATETIME(6)  NOT NULL,
  memo        VARCHAR(500) NULL,
  created_at  DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  PRIMARY KEY (id),
  KEY idx_carelog_group (group_id, occurred_at),
  KEY idx_carelog_doneby (done_by),
  KEY idx_carelog_dog (dog_id, occurred_at),
  CONSTRAINT fk_carelog_group FOREIGN KEY (group_id)
    REFERENCES family_group (id) ON DELETE SET NULL,
  CONSTRAINT fk_carelog_doneby FOREIGN KEY (done_by)
    REFERENCES users (id) ON DELETE SET NULL,
  CONSTRAINT fk_carelog_dog FOREIGN KEY (dog_id)
    REFERENCES dog (id) ON DELETE SET NULL,
  CONSTRAINT ck_carelog_type CHECK (type IN ('water','meal','walk','med','vet','poop','pee'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | |
| `dog_id` | `BIGINT` | FK→`dog.id` nullable, **ON DELETE SET NULL**, INDEX(dog,occurred_at) | 대상 반려동물. FK 는 #154 에서 걸었다(`22_care_log_dog_fk.sql`). 값은 아직 항상 `NULL` — 아래 참조 |
| `group_id` | `BIGINT` | FK→`family_group.id` nullable, ON DELETE SET NULL, INDEX(group,occurred_at) | 공유 대상 가족 그룹 |
| `type` | `VARCHAR(10)` | NOT NULL, CHECK | `water`(물)/`meal`(밥)/`walk`(산책)/`med`(투약)/`vet`(병원)/`poop`(배변)/`pee`(마킹). **소문자다**. 뒤의 둘은 #340 이 더했고 `29_care_type_poop.sql` 이 CHECK 를 넓힌다. **어디서 눴는지는 이 표에 없다** — 위치는 기기에만 남는다(A안 #235) |
| `done_by` | `BIGINT` | FK→`users.id` nullable, **ON DELETE SET NULL**, INDEX | 수행자. 토큰의 사용자이지 요청 본문의 값이 아니다. 그 사람이 탈퇴하면 `NULL` — §16 의 경고와 같은 판단이다 |
| `occurred_at` | `DATETIME(6)` | NOT NULL | 발생 시각. 서버 시계다 |
| `memo` | `VARCHAR(500)` | NULL | 메모 |
| `created_at` | `DATETIME(6)` | NOT NULL, 기본 now | 행 생성 시각 |

> ### `dog_id` 의 FK 는 #154 에서 걸었다 — `ON DELETE SET NULL`, 값은 아직 항상 `NULL`
>
> 2026-09-05 까지 이 절은 "FK 가 없는 이유" 였다. #145 가 `dog` 표를 만든 뒤에도 못 건 이유는 `CareLog` 가 `dog_id` 를 스칼라 `Long` 으로 들고 있어서 **Hibernate 가 FK 를 만들지 않았기** 때문이다 — `01_schema.sql` 은 엔티티로 만든 DB 에서 뽑은 파일이라, 마이그레이션에서 `ALTER` 로 더하면 운영 DB 에는 있고 커밋된 스키마에는 없는 제약이 되어 다음 재생성 때 조용히 사라졌다.
>
> #154 가 매핑을 `@ManyToOne Dog` 로 바꿨다. FK 가 엔티티에서 나오므로 재생성에 살아남고, 이미 있는 DB 에는 `22_care_log_dog_fk.sql` 이 같은 모양(`fk_carelog_dog` · `idx_carelog_dog(dog_id, occurred_at)`)으로 건다. 모듈 경계는 `Dog` 의 `@NamedInterface("entity")` 가 열고 `walk` 가 같은 길로 참조한다 — `ModularityBaselineTest` 는 232 그대로다.
>
> **`SET NULL` 인 이유.** 케어는 "누가 언제 무엇을 했는가" 의 기록이라 반려동물이 지워져도 그 사실은 남아야 한다 — `group_id`(가족 해산)·`done_by`(탈퇴)가 같은 질문에 같은 답을 했다. `walk.dog_id` 가 `CASCADE` 인 것과 다른 이유는 산책은 그 개의 기록이고 케어는 가족의 기록이기 때문이다. 사용자 탈퇴(`users` 하드 삭제)는 `fk_dog_user` 로 `dog` 을 `CASCADE` 로 지우고, 그 삭제가 여기를 `SET NULL` 로 훑는다 — `idx_carelog_dog` 가 그 자리다. `RESTRICT` 면 케어 기록이 있는 사람은 탈퇴를 못 한다.
>
> **값이 아직 `NULL` 인 이유.** `POST /api/groups/{groupId}/care-logs` 가 `dogId` 를 받지 않는다. 받으려면 "가족 구성원이 남의 반려동물 id 를 알 수 있는가" 가 먼저 정해져야 하고, 그것은 #209 의 `Dogs-high-3`(가족 공유 가시성)이 소유한다. 그때까지 FK 는 "잘못된 id 는 못 들어간다" 만 지킨다.
>
> **#9(`refresh_token.user_id`)와 같은 것으로 읽으면 안 된다.** #9 는 탈퇴 경로가 DB 삭제 순서에 묶이는 것을 피한 **판단**이고 지금도 안 건다. 여기는 매핑의 결과였고, 매핑을 바꾼 날 걸었다.

> **`group_id` 가 `NULL` 인 행은 지금 0건이다.** 이 이슈가 여는 경로는 `/api/groups/{groupId}/care-logs` 뿐이라 여기서 만들어지는 행은 전부 그룹을 든다. 개인 기록을 만드는 경로(`POST /api/dogs/{dogId}/care-logs`, M4)는 아직 없고, 조회 필터가 `group_id = :groupId` 라서 만약 `NULL` 행이 생겨도 **어떤 조회에도 나오지 않는다** — 의도다. 컬럼을 nullable 로 두는 것은 그 경로가 생길 자리를 비워 두는 것이고, 그때 개인 기록 조회도 함께 온다.

> `ON DELETE SET NULL` 이라 그룹을 해산해도 "내가 밥을 줬다" 는 사실은 남는다(그 행은 개인 기록이 된다). CASCADE 로 지우면 가족을 해산했다는 이유로 개인의 케어 이력이 통째로 증발한다.

> "오늘의 케어" 조회(`GET /api/groups/{groupId}/care-logs`)는 `idx_carelog_group(group_id, occurred_at)`으로 그룹·당일 범위를 스캔한다. **인가(403)와 이 `group_id` 필터는 서로 다른 방어다** — 인가만 있으면 두 가족에 속한 사람이 옆집 기록까지 본다.

> 건강·식사·병원 상세(`title`·`value`·`photo`)는 M4 다. 지금 넣지 않는 이유는 쓰지 않는 컬럼이 무슨 뜻인지 아무도 모르는 채로 남기 때문이다. M4 가 그 컬럼과 함께 `CareType` 상수·CHECK 제약·계약의 `enum` 을 같이 넓힌다.

---

## 18. 감정카드 셋 — 코드는 지웠고 표는 운영 DB 에 남아 있다 (#94)

`emotion_card` · `card_comment` · `card_reaction` 은 감정 여행 시절의 표다. 2026-09-03 에는 지우지 않고 격리하기로 했고([#174](https://github.com/sanghyunbang/heattrip/issues/174)), 2026-09-06 에 그 코드(`social` 패키지)를 [#94](https://github.com/sanghyunbang/heattrip/issues/94) 로 지웠다. **표와 데이터는 그대로다** — 다만 정본 `01_schema.sql` 은 엔티티에서 뽑으므로 여기서 빠졌고, 새 DB 에는 만들어지지 않는다. 지우는 SQL 은 만들지 않았다 — 되돌릴 수 없는 일은 따로 정한다. 같은 처지의 표가 부록 A 아래에 20개 더 있다. §19·§20 번호는 비워 둔다 — 뒤 절의 번호를 흔들지 않기 위해서다.

---

## 21. `kto_call_budget` — KTO 일 호출 예산 (**실재**)

관광공사(KTO) 프록시의 호출 예산 — [`10_place_cache.sql`](../../backend/mysql/post-start/10_place_cache.sql)(#40). `PRIMARY KEY (day, pool)` 이 **KTO 일 1,000콜 한도를 지키는 유일한 장치**이고, 그 판정은 조건부 `UPDATE` 한 문장이다. FK 는 없다.

```sql
CREATE TABLE `kto_call_budget` (
  `day` date NOT NULL,
  `used` int NOT NULL,
  `pool` varchar(16) NOT NULL,
  PRIMARY KEY (`day`,`pool`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
```

---

## 22. `place_cell` — 주변 장소 셀 스냅샷 (**실재**)

`GET /api/places/nearby` 가 좌표를 **0.02° 격자로 접은 셀**(`lat_idx`, `lng_idx`) 단위로 KTO 응답을 통째로(`payload`) 보관한다 — 같은 셀의 두 번째 요청부터는 KTO 를 부르지 않는다(#40). `fail_streak`·`failed_at` 이 실패한 셀의 재시도를 늦춘다. FK 는 없다.

```sql
CREATE TABLE `place_cell` (
  `fail_streak` int NOT NULL,
  `item_count` int NOT NULL,
  `lat_idx` int NOT NULL,
  `lng_idx` int NOT NULL,
  `total_count` int NOT NULL,
  `failed_at` datetime(6) DEFAULT NULL,
  `fetched_at` datetime(6) NOT NULL,
  `payload` longtext NOT NULL,
  PRIMARY KEY (`lat_idx`,`lng_idx`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
```

---

## 23. `pet_place_detail` — 반려동반 장소 상세 캐시 (**실재**)

장소 상세(`GET /api/places/{contentId}`)의 KTO 응답 캐시. `content_id` 가 키이고 공통 정보(`common_fetched_at`)와 반려 동반 정보(`pet_fetched_at`)를 따로 받은 시각을 든다. `not_found_at` 은 KTO 가 모른다고 한 id 를 다시 묻지 않게 한다. FK 는 없다.

```sql
CREATE TABLE `pet_place_detail` (
  `lat` double DEFAULT NULL,
  `lng` double DEFAULT NULL,
  `common_fetched_at` datetime(6) DEFAULT NULL,
  `not_found_at` datetime(6) DEFAULT NULL,
  `pet_fetched_at` datetime(6) DEFAULT NULL,
  `content_type_id` varchar(16) DEFAULT NULL,
  `content_id` varchar(64) NOT NULL,
  `tel` varchar(64) DEFAULT NULL,
  `image` varchar(512) DEFAULT NULL,
  `acmpy_need_mtr` text,
  `acmpy_psbl_cpam` text,
  `addr` varchar(255) DEFAULT NULL,
  `etc_acmpy_info` text,
  `title` varchar(255) DEFAULT NULL,
  `overview` longtext,
  PRIMARY KEY (`content_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
```

---

## 24. `place_catalog` — 장소 한 벌, 출처별 한 행 (**실재**)

장소 목록 **한 벌** — [`18_place_catalog.sql`](../../backend/mysql/post-start/18_place_catalog.sql) · [`24_place_catalog_layers.sql`](../../backend/mysql/post-start/24_place_catalog_layers.sql). §22 `place_cell` 이 좌표를 접은 키를 갖는 것과 달리 이 표에는 좌표 키가 없고, 그래서 요청에 좌표도 지역도 실려 오지 않는다. #273 에서는 행이 하나(`CHECK (id = 1)`, KTO 전국)였고, **#291 이 출처별 한 행**으로 넓혔다 — `source` 가 `kto`(id 1, 매일 04:40 예열 #279) · `localdata`(id 2, 행정안전부 인허가 동물병원·동물판매업, 월 1회) · `durunubi`(id 3, 두루누비 걷기여행길, 월 1회)이고 UNIQUE + CHECK 가 그것을 지킨다. 번호는 코드의 `CatalogSource` 가 든다. `GET /api/places/catalog` 은 세 행의 `payload` 를 **문자열로 이어 붙여** 하나의 배열로 내보내고, `etag` 는 세 해시를 다시 해시한다. `fetched_at` 은 **서비스 존(Asia/Seoul) 벽시계**다 — 다른 표의 UTC 와 다르다. FK 는 없다.

```sql
CREATE TABLE `place_catalog` (
  `fail_streak` int NOT NULL,
  `id` int NOT NULL,
  `item_count` int NOT NULL,
  `total_count` int NOT NULL,
  `failed_at` datetime(6) DEFAULT NULL,
  `fetched_at` datetime(6) NOT NULL,
  `source` varchar(16) NOT NULL,
  `etag` varchar(64) NOT NULL,
  `payload` longtext NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_place_catalog_source` (`source`),
  CONSTRAINT `chk_place_catalog_source` CHECK ((`source` in (_utf8mb4'kto',_utf8mb4'localdata',_utf8mb4'durunubi')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
```

---

## 25. `report` — 신고 (**실재**)

신고 한 건 — [`15_report.sql`](../../backend/mysql/post-start/15_report.sql). **`users` 로의 FK 를 안 건다** — 신고는 값으로만 사람을 가리킨다. 탈퇴가 신고 기록을 지우면 안 되기 때문이다. `reason` 에 CHECK. **UNIQUE 가 없다** — 같은 사람이 같은 글을 두 번 신고할 수 있고, 그것을 세는 것은 운영의 일이다. 신고 대상의 좌표는 §26 `report_snapshot` 이 든다(17).

```sql
CREATE TABLE `report` (
  `created_at` datetime(6) NOT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `reported_user_id` bigint DEFAULT NULL,
  `reporter_user_id` bigint NOT NULL,
  `reason` varchar(16) NOT NULL,
  `memo` varchar(500) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_report_reported` (`reported_user_id`),
  KEY `idx_report_reporter` (`reporter_user_id`),
  CONSTRAINT `chk_report_reason` CHECK ((`reason` in (_utf8mb4'spam',_utf8mb4'abuse',_utf8mb4'sexual',_utf8mb4'fraud',_utf8mb4'other')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
```

---

## 26. `report_snapshot` — 신고 대상 스냅샷 (**실재**)

신고 시점의 대상(글·댓글·메시지·방)을 **본문째 복사**해 둔 것 — 대상이 지워지거나 고쳐져도 신고는 그때 모양을 본다. `role` 이 `target`(신고 대상 그 자체)·`context`(주변 메시지)를 가르고, `target` 행은 `body` 가 비면 안 된다(CHECK). `fk_report_snapshot_report … ON DELETE CASCADE` — 스냅샷은 신고 없이 존재할 이유가 없다. 이 저장소에서 `users` 밖으로 가는 FK 를 가진 채팅 쪽 표는 없고, 여기도 `chat_message` 로 가는 FK 는 없다(ADR-0011 결정 4).

```sql
CREATE TABLE `report_snapshot` (
  `author_user_id` bigint DEFAULT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `occurred_at` datetime(6) NOT NULL,
  `report_id` bigint NOT NULL,
  `role` varchar(8) NOT NULL,
  `target_id` bigint NOT NULL,
  `target_ordinal` bigint DEFAULT NULL,
  `content_type` varchar(16) DEFAULT NULL,
  `target_type` varchar(24) NOT NULL,
  `title` varchar(200) DEFAULT NULL,
  `author_name` varchar(255) DEFAULT NULL,
  `body` text,
  PRIMARY KEY (`id`),
  KEY `idx_report_snapshot_report` (`report_id`),
  KEY `idx_report_snapshot_target` (`target_type`,`target_id`),
  CONSTRAINT `fk_report_snapshot_report` FOREIGN KEY (`report_id`) REFERENCES `report` (`id`) ON DELETE CASCADE,
  CONSTRAINT `chk_report_snapshot_role` CHECK ((`role` in (_utf8mb4'target',_utf8mb4'context'))),
  CONSTRAINT `chk_report_snapshot_target_has_body` CHECK (((`role` <> _utf8mb4'target') or (`body` is not null))),
  CONSTRAINT `chk_report_snapshot_target_type` CHECK ((`target_type` in (_utf8mb4'community_post',_utf8mb4'community_comment',_utf8mb4'chat_message',_utf8mb4'chat_room')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
```

---

## 27. `user_block` — 가리기 (**실재**)

한 사람이 다른 사람을 가린 기록 — `chat_block` 에서 이름을 바꿨다([`16_user_block.sql`](../../backend/mysql/post-start/16_user_block.sql)). 가리기는 처음부터 사람 단위였고 채팅 안에 있었던 것은 채팅이 그것을 처음 필요로 했기 때문이다; 커뮤니티가 같은 가리기를 쓰면서 이름을 옮겼다. `UNIQUE (blocker_user_id, blocked_user_id)`. `users` 로의 FK 는 없다.

```sql
CREATE TABLE `user_block` (
  `blocked_user_id` bigint NOT NULL,
  `blocker_user_id` bigint NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_user_block` (`blocker_user_id`,`blocked_user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
```

---

## 28. `user_consent` — 약관 동의 이력 (**실재**)

약관·개인정보·위치·마케팅 동의의 **이력** — [`19_user_consent.sql`](../../backend/mysql/post-start/19_user_consent.sql)(#190 · ADR-0020). **덧붙이기만 한다** — 동의도 철회도 새 행이고 "지금 상태" 는 계정·문서(`kind`)별 마지막 행이다. `users` 의 옛 `agree_*` 아홉 컬럼은 [`21_users_drop_consent_columns.sql`](../../backend/mysql/post-start/21_users_drop_consent_columns.sql) 이 여기로 옮기고 지웠다. `created_at` 은 UTC 다. `users` 로의 FK 는 없다 — 탈퇴한 사람의 동의 증빙을 남긴다.

```sql
CREATE TABLE `user_consent` (
  `agreed` bit(1) NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `kind` varchar(16) NOT NULL,
  `version` varchar(16) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_user_consent_user` (`user_id`,`id`),
  CONSTRAINT `chk_user_consent_kind` CHECK ((`kind` in (_utf8mb4'TERMS',_utf8mb4'PRIVACY',_utf8mb4'LOCATION',_utf8mb4'MARKETING')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
```

---

## 29. `device_token` — 기기 토큰 원장 (**실재**)

푸시 알림(#83)의 기기 토큰 — [`25_push.sql`](../../backend/mysql/post-start/25_push.sql). 한 행이 "이 기기(토큰)는 지금 이 사용자의 것" 이다. `UNIQUE(token)` 이라 같은 기기에서 다른 계정으로 들어오면 주인이 바뀐다 — 등록(`PUT /api/push/tokens`)이 upsert 인 이유다. `user_id` 는 값만 든다 — `push` 모듈이 `users` 를 모른다. **지우지 않고 `revoked_at` 을 찍는다** — FCM 이 "없는 기기" 라 답하거나 로그아웃하면. 지우면 "없던 토큰" 과 "죽은 토큰" 을 구별할 수 없다(`refresh_token` 과 같은 이유). 탈퇴만 행을 지운다(개인정보). 사용자당 살아 있는 토큰은 10개까지 — 넘치면 `last_seen_at` 이 오래된 것부터 폐기한다.

```sql
CREATE TABLE `device_token` (
  `created_at` datetime(6) NOT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `last_seen_at` datetime(6) NOT NULL,
  `platform` varchar(8) NOT NULL,
  `revoked_at` datetime(6) DEFAULT NULL,
  `user_id` bigint NOT NULL,
  `token` varchar(512) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_device_token_token` (`token`),
  KEY `idx_device_token_user` (`user_id`,`revoked_at`),
  CONSTRAINT `chk_device_token_platform` CHECK ((`platform` in (_utf8mb4'android',_utf8mb4'ios')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
```

---

## 30. `push_preference` — 알림 전체 끄기 (**실재**)

사용자별 "전체 끄기" 하나(#83). **행이 없으면 켜진 것**이라 가입 때 만들지 않고 처음 끄는 순간 생긴다. 방별 음소거는 여기 없다 — 멤버십의 속성이라 §13 `chat_room_member.muted_at` 이다. 탈퇴 때 행을 지운다.

```sql
CREATE TABLE `push_preference` (
  `enabled` bit(1) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `user_id` bigint NOT NULL,
  PRIMARY KEY (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
```

---

## 31. `course` — 내가 남긴 코스 (**실재**)

산책 기록 중에 "여기 좋다" 고 남긴 것(#339). **산책과 다른 것이다** — 산책은 "그날 내가 걸었다" 이고 코스는 "여기를 이렇게 걸으면 좋다" 다. 그래서 (1) `walk.path` 에서 **양 끝 100m 를 잘라 낸 선**이 들어가고(집 앞이 남으면 공개할 수 없다), (2) 산책을 지워도 코스는 남는다(`fk_course_walk ... ON DELETE SET NULL`).

`SPATIAL INDEX` 는 없다 — `walk` 와 같은 이유다([ADR-0015](../99-decisions/decision-log.md#adr-0015--산책-경로는-linestring-으로-저장하되-spatial-index-는-만들지-않는다)). 지도의 "이웃 코스" 는 공개 목록을 받아 **기기에서** 거리를 잰다(A안 #235).

```sql
CREATE TABLE `course` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `walk_id` bigint DEFAULT NULL,
  `name` varchar(60) NOT NULL,
  `note` varchar(200) DEFAULT NULL,
  `tags` varchar(60) DEFAULT NULL,
  `path` linestring /*!80003 SRID 4326 */ NOT NULL,
  `distance_m` int NOT NULL,
  `duration_s` int NOT NULL,
  `visibility` varchar(10) NOT NULL DEFAULT 'private',
  `created_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_course_user` (`user_id`,`created_at`),
  KEY `idx_course_public` (`visibility`,`created_at`),
  KEY `fk_course_walk` (`walk_id`),
  CONSTRAINT `fk_course_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_course_walk` FOREIGN KEY (`walk_id`) REFERENCES `walk` (`id`) ON DELETE SET NULL,
  CONSTRAINT `ck_course_visibility` CHECK (`visibility` in ('private','public'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | |
| `user_id` | `BIGINT` | FK→`users.id`, **CASCADE** | 주인. 탈퇴하면 함께 사라진다 — 그 사람의 글이다 |
| `walk_id` | `BIGINT` | FK→`walk.id`, **SET NULL** | 어느 산책에서 왔나. 산책을 지워도 코스는 남는다 |
| `name` | `VARCHAR(60)` | NOT NULL | 코스 이름 |
| `note` | `VARCHAR(200)` | NULL | 한 줄 소개 |
| `tags` | `VARCHAR(60)` | NULL | `leash`·`poopbag`·`shade` 를 콤마로. 값이 셋으로 닫혀 있어 표를 나누지 않았다 |
| `path` | `LINESTRING` | **SRID 4326**, NOT NULL | 양 끝 100m 를 자른 선. 선이 곧 코스다 |
| `distance_m` | `INT` | NOT NULL | **자른 뒤**의 길이. 원래 산책의 거리가 아니다 |
| `duration_s` | `INT` | NOT NULL | 원래 산책의 소요. 자른 만큼을 뺄 수 없다 |
| `visibility` | `VARCHAR(10)` | NOT NULL 기본 `private`, CHECK | `private`\|`public`. 공개는 사용자가 명시적으로 하는 일이다 |
| `created_at` | `DATETIME(6)` | NOT NULL | UTC |

---

## 32. `walk_dog` — 한 번의 산책에 여러 마리 (**실재**)



`walk` 는 아이 **하나**에 묶여 있었다. 두 마리를 함께 데리고 나가면 한 마리 것으로 저장되거나 같은 산책을 두 번 적어야 했다 — 프로필은 "우리 아이들" 을 여러 마리 받는데 산책만 한 마리였다.



```sql

CREATE TABLE walk_dog (

  dog_id  BIGINT NOT NULL,

  walk_id BIGINT NOT NULL,

  PRIMARY KEY (dog_id, walk_id),

  KEY fk_walkdog_walk (walk_id),

  CONSTRAINT fk_walkdog_dog  FOREIGN KEY (dog_id)  REFERENCES dog (id)  ON DELETE CASCADE,

  CONSTRAINT fk_walkdog_walk FOREIGN KEY (walk_id) REFERENCES walk (id) ON DELETE CASCADE

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

```



| 컬럼 | 타입 | 제약 | 설명 |

| --- | --- | --- | --- |

| `dog_id` | `BIGINT` | PK(1/2), FK→`dog.id` CASCADE | 함께 나간 아이 |

| `walk_id` | `BIGINT` | PK(2/2), FK→`walk.id` CASCADE | 그 산책 |



> **PK 가 `(dog_id, walk_id)` 순서인 것은 Hibernate 가 정하는 순서이고**(`mysql/init/01_schema.sql` 이 엔티티에서 재생성된다), 마침 바라던 순서다 — 이 표에 가장 자주 오는 질문이 "이 아이의 산책" 이라 `dog_id` 가 앞이어야 인덱스를 탄다. 반대 방향은 MySQL 이 `fk_walkdog_walk` 에 자동으로 만드는 인덱스가 받는다.

>

> **양쪽 FK 가 모두 `CASCADE` 다.** 이 표에는 사실이 없다 — "이 산책에 이 아이가 있었다" 라는 이음매뿐이라, 산책이나 아이가 사라지면 남을 이유가 없다. `care_log` 가 `SET NULL` 인 것과 다른 이유가 여기 있다: 거기는 "누가 밥을 줬다" 라는 **사실**이라 사람이 사라져도 남아야 한다.

>

> **대표 아이도 여기 한 줄 들어간다.** 안 넣으면 "아이별 통계" 가 `walk.dog_id` 와 이 표를 합쳐 봐야 하고, 그 합치기를 잊는 질의가 언젠가 하나 생긴다. `33_walk_dog.sql` 이 이미 쌓인 산책까지 채운다 — 안 채우면 아이별 통계가 과거를 전부 0 으로 말한다.

>

> **`@ManyToMany` 가 아니라 엔티티다.** 이 저장소에 `@ManyToMany` 는 하나도 없고, `@JoinTable` 에 Hibernate 의 `@OnDelete` 를 붙이면 **소유자 쪽 한 짝에만** 붙어 새 DB 와 마이그레이션한 DB 의 규칙이 달라진다.



## 33. `schedule` — 앞으로 할 일 (**실재**)

지금까지 앱은 **지나간 일만** 알았다. `care_log` 는 "누가 언제 했다" 이고(`occurred_at` 이 서버 시계라 미래를 못 넣는다), `walk` 은 끝난 산책이다. 앞으로 할 일을 적을 자리가 한 곳도 없어서, 가족은 병원 일정을 **채팅으로** 조율하고 그 결정은 스크롤 위로 사라졌다(`docs/00-product/feature-family-care.md` S3 가 그 장면을 적고 있고, 같은 문서가 문제로 꼽은 것이 "전달 누락·중복 질문" 이다).

```sql
CREATE TABLE schedule (
  id         BIGINT       NOT NULL AUTO_INCREMENT,
  owner_kind VARCHAR(10)  NOT NULL,
  owner_ref  BIGINT       NOT NULL,
  dog_id     BIGINT       NULL,
  kind       VARCHAR(10)  NOT NULL,
  title      VARCHAR(100) NOT NULL,
  memo       VARCHAR(500) NULL,
  on_date    DATE         NOT NULL,
  at_time    TIME(6)      NULL,
  assignee   BIGINT       NULL,
  status     VARCHAR(10)  NOT NULL,
  done_at    DATETIME(6)  NULL,
  care_log_id BIGINT      NULL,
  repeat_kind VARCHAR(10) NOT NULL,
  repeat_until DATE       NULL,
  origin_id  BIGINT       NULL,
  version    INT          NOT NULL,
  created_by BIGINT       NOT NULL,
  updated_by BIGINT       NULL,
  created_at DATETIME(6)  NOT NULL,
  updated_at DATETIME(6)  NULL,
  PRIMARY KEY (id),
  KEY idx_schedule_owner_date (owner_kind, owner_ref, on_date),
  KEY idx_schedule_dog_date   (dog_id, on_date),
  CONSTRAINT fk_schedule_dog        FOREIGN KEY (dog_id)     REFERENCES dog (id)   ON DELETE SET NULL,
  CONSTRAINT fk_schedule_assignee   FOREIGN KEY (assignee)   REFERENCES users (id) ON DELETE SET NULL,
  CONSTRAINT fk_schedule_created_by FOREIGN KEY (created_by) REFERENCES users (id) ON DELETE CASCADE,
  CONSTRAINT fk_schedule_updated_by FOREIGN KEY (updated_by) REFERENCES users (id) ON DELETE SET NULL,
  CONSTRAINT ck_schedule_owner_kind CHECK (owner_kind IN ('dog','group','room')),
  CONSTRAINT ck_schedule_kind       CHECK (kind IN ('walk','vet','med','groom','bath','food','etc')),
  CONSTRAINT fk_schedule_origin     FOREIGN KEY (origin_id)  REFERENCES schedule (id) ON DELETE CASCADE,
  CONSTRAINT ck_schedule_status     CHECK (status IN ('planned','done','skipped')),
  CONSTRAINT ck_schedule_repeat     CHECK (repeat_kind IN ('none','daily','weekly','monthly'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK, AI | |
| `owner_kind` | `VARCHAR(10)` | NOT NULL, CHECK | 일정의 주인이 어느 도메인인가 — `dog` · `group` · `room` |
| `owner_ref` | `BIGINT` | NOT NULL, **FK 아님** | 그 도메인의 id. 소유권은 서버가 확인한다 |
| `dog_id` | `BIGINT` | NULL, FK→`dog.id` **SET NULL** | 어느 아이 것인가. `owner_ref` 와 **별개다** |
| `kind` | `VARCHAR(10)` | NOT NULL, CHECK | `walk`·`vet`·`med`·`groom`·`bath`·`food`·`etc` |
| `title` | `VARCHAR(100)` | NOT NULL | |
| `memo` | `VARCHAR(500)` | NULL | |
| `on_date` | `DATE` | NOT NULL | **사용자의 날짜**(KST). 시각과 달리 시간대 변환을 하지 않는다 |
| `at_time` | `TIME(6)` | NULL | `NULL` 이면 **"하루 종일"** 이다 |
| `assignee` | `BIGINT` | NULL, FK→`users.id` **SET NULL** | 맡기로 한 사람 |
| `status` | `VARCHAR(10)` | NOT NULL, CHECK | `planned`·`done`·`skipped` |
| `done_at` | `DATETIME(6)` | NULL | 완료·건너뜀으로 바꾼 시각. `planned` 로 되돌리면 다시 `NULL` |
| `care_log_id` | `BIGINT` | NULL, **FK 아님** | 완료로 바꾸면서 남긴 케어 기록의 id(#420). 되돌릴 때 그 줄을 거두는 열쇠다 |
| `repeat_kind` | `VARCHAR(10)` | NOT NULL, CHECK | `none`·`daily`·`weekly`·`monthly`(#421). 요일·날짜는 `on_date` 에서 나온다 |
| `repeat_until` | `DATE` | NULL | 되풀이가 끝나는 날. `NULL` 이면 끝이 없다 |
| `origin_id` | `BIGINT` | NULL, FK→`schedule.id` **CASCADE** | 이 행이 어느 규칙의 하루를 대신하는가(#421) |
| `version` | `INT` | NOT NULL | 낙관적 잠금(`@Version`) |
| `created_by` | `BIGINT` | NOT NULL, FK→`users.id` **CASCADE** | 적은 사람 |
| `updated_by` | `BIGINT` | NULL, FK→`users.id` **SET NULL** | 마지막으로 고친 사람 |
| `created_at` / `updated_at` | `DATETIME(6)` | | |

> **`owner_kind` + `owner_ref` 는 `chat_room` 과 같은 방식이다.** 일정의 주인이 셋이다 — **아이**("보리 심장사상충 약") · **가족 그룹**("토요일 병원, 아빠 담당") · **크루**("토요일 합동 산책", #417). 셋을 표 셋으로 나누면 "합쳐 보기" 가 매번 `UNION` 이 되고, 화면 하나가 그중 하나를 빠뜨리는 날이 온다. `chat_room` 이 이미 이 문제를 `origin_kind`/`origin_ref` 로 풀었다([ADR-0011](../99-decisions/decision-log.md)) — 같은 방식을 쓴다.
>
> **그래서 이 두 컬럼에는 FK 가 없다.** 세 도메인을 가리키는 컬럼 하나에 FK 를 걸 수 없다. `chat_room` 이 같은 이유로 안 걸고, 그 대신 서비스가 소유권을 확인한다. `room` 은 값만 미리 열어 두었고 **서버가 아직 400 으로 거절한다** — 확인할 멤버십이 없는 채로 통과시키면 아무나 남의 크루 일정을 만들 수 있다.
>
> **`dog_id` 는 `owner_ref` 와 별개다.** "가족 소유인데 보리 것" 이 흔하다. `owner` 로만 두면 어느 아이 것인지 적을 자리가 없고, `dog_id` 로만 두면 "사료 주문" 처럼 아이 하나에 안 묶이는 일을 못 적는다. 그래서 조회가 둘을 **겹쳐 쓸 수 있다** — "우리 가족 일정 중 보리 것".
>
> **지우기 규칙이 넷 다 다르다.** `dog` 와 `assignee` 는 `SET NULL` — 아이를 보내도 그날 병원에 갔다는 계획은 남고, 담당자가 탈퇴해도 그 일이 남아 있다는 사실은 남아야 한다(`care_log.dog_id` 가 #154 에서 고른 것과 같은 답이다). `created_by` 만 `CASCADE` 다 — 그 사람의 계획이다.
>
> **`at_time` 이 `NULL` 일 수 있다.** 시각 없는 일정이 많다 — "이번 주말 목욕". 0시로 채워 넣으면 화면이 **"00:00 목욕"** 이라고 적게 되고, 그건 사용자가 안 정한 것을 정한 것처럼 보이게 한다.
>
> **`version` — 낙관적 잠금.** 가족 여럿이 같은 일정을 고친다. 실시간 공동 편집은 안 한다(소켓 #84 가 아직 없고, 일정은 초당 여러 번 고치는 것이 아니다). 대신 뒤에 온 쪽이 **409** 를 받고 최신 값을 본다 — 조용히 덮어쓰면 아빠가 옮긴 병원 시각이 엄마의 옛 화면으로 되돌아간다.
>
> **`care_log_id` 에 FK 를 안 건다** (#420). 걸려면 `Schedule` 엔티티가 `care.entity.CareLog` 를 들어야 하고 그건 모듈 경계를 넘는다 — `owner_ref` 가 같은 이유로 FK 가 아니다. `01_schema.sql` 은 엔티티에서 재생성되므로 마이그레이션에만 FK 를 적어 두면 **다음 재생성에서 조용히 사라진다.** 대신 사람이 케어 칸에서 그 줄을 먼저 지웠을 수 있다는 전제로 다룬다 — 거두기는 없는 id 를 조용히 지나간다.
>
> **인덱스도 안 만든다.** 이 컬럼으로 찾지 않는다 — 늘 `schedule` 한 줄을 이미 들고 있고 거기서 id 를 꺼내 쓸 뿐이라, 인덱스는 쓰이지 않으면서 쓰기만 느리게 한다.
>
> **일정을 지워도 그 케어 기록은 남는다.** 되돌리기(`planned` 로)와 다른 답인 것이 의도다 — 되돌리기는 "그 일이 일어나지 않았다" 는 말이지만, 지우기는 "이 계획을 더 안 본다" 는 말이다. 이미 다녀온 병원의 기록까지 사라지면 계획을 정리하다 사실을 잃는다.
>
> **반복은 규칙 한 줄이다** (#421). 1년치 심장사상충 약을 365행으로 만들어 두면, 규칙을 고칠 때 그 전부를 손봐야 하고 한 번 빠뜨리면 옛 값이 남은 행이 조용히 생긴다. 조회할 때 **서버가** 펼친다 — 앱이 펼치면 해석이 두 벌이 되고 그중 하나가 언젠가 다르게 센다(윤년·말일이 그 자리다).
>
> **요일·날짜 컬럼이 없다.** `weekly` 는 `on_date` 의 요일이고 `monthly` 는 그 날짜다. 따로 두면 "매주 화요일인데 시작일은 수요일" 같은 모순을 저장할 수 있게 되고, 그 행을 무엇으로 읽을지 아무도 못 정한다. 31일 규칙은 30일까지인 달을 **건너뛴다** — 말일로 당기면 사용자가 안 정한 날에 알림이 온다.
>
> **좌표 컬럼이 없다.** A안(#235)에서 좌표는 기기를 안 떠나고, 일정은 그것이 필요한 기능이 아니다. 장소가 필요해지는 날에는 `walk` 처럼 카탈로그 참조(출처 + contentId)를 쓴다.
>
> **인덱스 둘.** `idx_schedule_owner_date (owner_kind, owner_ref, on_date)` 가 달력이 묻는 유일한 질문("이 주인의 이 기간")이고, `idx_schedule_dog_date (dog_id, on_date)` 가 "보리 것만" 필터다 — `dog_id` 로 시작하지 않으면 앞 인덱스를 못 쓴다.

## 34. `schedule_exception` — 반복의 하루짜리 예외 (**실재**)

이 표가 없으면 반복을 쓸 수 없다. "이번 주 목욕만 하루 미루기" 가 불가능해지고, 사용자는 반복을 지우고 다시 만든다 — 그러면 지난 기록도 함께 사라진다.

```sql
CREATE TABLE schedule_exception (
  on_date     DATE        NOT NULL,
  schedule_id BIGINT      NOT NULL,
  kind        VARCHAR(10) NOT NULL,
  PRIMARY KEY (on_date, schedule_id),
  KEY fk_schedexc_schedule (schedule_id),
  CONSTRAINT fk_schedexc_schedule FOREIGN KEY (schedule_id) REFERENCES schedule (id) ON DELETE CASCADE,
  CONSTRAINT ck_schedule_exception_kind CHECK (kind IN ('skip','override'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `on_date` | `DATE` | PK(1/2) | 어느 날인가. **사용자의 날짜**다(KST) |
| `schedule_id` | `BIGINT` | PK(2/2), FK→`schedule.id` CASCADE | 어느 규칙의 예외인가 |
| `kind` | `VARCHAR(10)` | NOT NULL, CHECK | `skip`(그날 안 함) 또는 `override`(그날짜용 행이 대신함) |

> **`skip` 과 `override` 는 펼치기에서 같다** — 둘 다 그날은 규칙에서 빠진다. 다른 것은 `override` 면 그날짜용 행이 따로 하나 생긴다는 것뿐이고, 그 행은 자기 `on_date` 로 평범하게 조회되며 `schedule.origin_id` 로 규칙에 이어져 있다. 구분을 남기는 것은 **사람이 DB 를 들여다볼 때**를 위해서다 — 옮긴 행이 지워진 뒤 그 자리가 왜 비어 있는지 알 수 있어야 한다.
>
> **PK 컬럼 순서가 `(on_date, schedule_id)` 인 것은 Hibernate 가 정한 것**이다(`mysql/init/01_schema.sql` 이 엔티티에서 재생성된다). 바라던 순서는 아니지만 — 이 표에 오는 질문은 "이 규칙의 예외" 라 `schedule_id` 가 앞이면 좋다 — **정본을 따른다.** 반대로 적으면 새로 세운 DB 와 마이그레이션한 DB 의 인덱스가 갈리고 오류는 안 난다. 그 방향은 `fk_schedexc_schedule` 에 딸린 인덱스가 받는다(`walk_dog` 이 #343 에서 같은 자리였다).
>
> **한 규칙의 한 날짜에 예외는 하나뿐이다.** 대리 키를 두면 같은 날짜에 두 줄이 생길 수 있고, 그러면 펼치기가 그중 무엇을 볼지 정해야 한다.
>
> **규칙을 지우면 함께 사라진다.** 규칙이 없는 예외는 아무 일도 안 한다.

> **같은 이름의 옛 표가 운영 DB 에 있었다.** 감정 여행 시절의 `schedule`(여행 일정 — `schedule_id, user_id, title, content, date_from, date_to`)이 코드 없이 표만 남아 있다(#94). `34_schedule.sql` 이 그것을 **지우지 않고** `schedule_legacy_journey` 로 옮긴다 — 사람이 적어 둔 행이고, 지우는 것은 마이그레이션이 결정할 일이 아니다. `journey.schedule_id` 의 FK 도 `RENAME TABLE` 이 함께 옮긴다.

## 인덱스 · 공간 인덱스 요약
## 36. `crew_favor` — 품앗이 (**실재**)

"12/24 오후, 보리 두 시간만 봐 주실 분"(#417). **금액도 평점도 후기도 없다** — 이슈가 그은 선이다: 돈이 오가면 우리가 중개자가 되고 사고 시 배상·신고 의무가 따라온다.

```sql
CREATE TABLE crew_favor (
  id          BIGINT       NOT NULL AUTO_INCREMENT,
  crew_id     BIGINT       NOT NULL,
  asked_by    BIGINT       NULL,
  taken_by    BIGINT       NULL,
  dog_id      BIGINT       NULL,
  on_date     DATE         NOT NULL,
  slot        VARCHAR(10)  NOT NULL,
  note        VARCHAR(200) NULL,
  status      VARCHAR(10)  NOT NULL,
  schedule_id BIGINT       NULL,
  created_at  DATETIME(6)  NOT NULL,
  updated_at  DATETIME(6)  NULL,
  PRIMARY KEY (id),
  KEY idx_crew_favor_crew (crew_id, on_date),
  CONSTRAINT fk_crew_favor_crew  FOREIGN KEY (crew_id)  REFERENCES crew (id)  ON DELETE CASCADE,
  CONSTRAINT fk_crew_favor_asker FOREIGN KEY (asked_by) REFERENCES users (id) ON DELETE SET NULL,
  CONSTRAINT fk_crew_favor_taker FOREIGN KEY (taken_by) REFERENCES users (id) ON DELETE SET NULL,
  CONSTRAINT fk_crew_favor_dog   FOREIGN KEY (dog_id)   REFERENCES dog (id)   ON DELETE SET NULL,
  CONSTRAINT ck_crew_favor_slot   CHECK (slot IN ('morning','afternoon','evening')),
  CONSTRAINT ck_crew_favor_status CHECK (status IN ('open','taken'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `crew_id` | `BIGINT` | FK→`crew.id` CASCADE | 크루가 사라지면 부탁도 사라진다 |
| `asked_by` / `taken_by` | `BIGINT` | FK→`users.id` SET NULL | **탈퇴해도 약속은 남는다** |
| `dog_id` | `BIGINT` | FK→`dog.id` SET NULL | **부탁한 사람**의 아이. 없어도 된다 |
| `on_date` | `DATE` | NOT NULL | 사람이 고른 날짜(KST) — UTC 로 안 눕힌다 |
| `slot` | `VARCHAR(10)` | NOT NULL, CHECK | `morning`·`afternoon`·`evening`. **시각이 아니다** |
| `note` | `VARCHAR(200)` | NULL | "두 시간만 부탁드려요" |
| `status` | `VARCHAR(10)` | NOT NULL, CHECK | `open`·`taken` **둘뿐이다** |
| `schedule_id` | `BIGINT` | NULL, **FK 없음** | 맡으면 생기는 크루 일정 |

> **끝났는지는 이 표가 모른다.** 맡으면 크루 소유 일정 한 줄이 생기고(`owner_kind='room'`, `owner_ref=crew.id`), **그 줄의 완료 표시가 "했다" 를 말한다.** 여기에 상태를 하나 더 두면 같은 사실이 두 곳에 살고 한쪽만 고쳐진다. "취소됨" 도 없다 — 거둬들이면 행이 사라진다.
>
> **`schedule_id` 에 FK 가 없다.** 걸려면 엔티티가 `schedule.entity.Schedule` 을 들어야 하고 그건 모듈 경계를 넘는다. SQL 에만 적으면 `01_schema.sql` 재생성에서 조용히 사라진다(`schedule.care_log_id` 가 #420 에서 같은 자리였다). 크루를 지울 때 그 줄까지 거두는 것은 **서비스**가 한다.
>
> **FK 넷의 삭제 규칙이 서로 다르다.** `crew_id` 만 CASCADE 다 — 사람·아이가 CASCADE 로 잘못 서면 **한 사람이 탈퇴할 때 남의 약속이 함께 사라진다.** 오류도 안 나고, 사라진 뒤에는 무엇이 있었는지 아무도 모른다. `38_crew_favor.sql` 의 사후 검증과 `CrewFavorMigrationExecutionTest` 가 그것을 잰다.
>
> **시간대가 시각이 아닌 이유.** 부탁은 "오후" 이지 "14시 00분" 이 아니다. 시각을 받으면 부탁하는 사람이 없는 정밀도를 지어내고 맡는 사람은 그 시각에 묶인다. 그래서 크루 일정에도 `at_time` 을 안 채우고 시간대는 메모로 간다 — 0시로 채우면 달력이 "새벽 12시" 로 그린다.

## 35. `crew` — 동네 반려인 모임 (**실재**)

동네 모임 하나. **표는 이것 하나뿐이다** — 멤버십도 초대코드도 방(`chat_room`)의 것이다.

```sql
CREATE TABLE crew (
  capacity          INT          NOT NULL,
  created_at        DATETIME(6)  NOT NULL,
  id                BIGINT       NOT NULL AUTO_INCREMENT,
  updated_at        DATETIME(6)  NULL,
  neighborhood_code VARCHAR(10)  NULL,
  visibility        VARCHAR(10)  NOT NULL,
  name              VARCHAR(30)  NOT NULL,
  intro             VARCHAR(200) NULL,
  PRIMARY KEY (id),
  KEY idx_crew_public (visibility, neighborhood_code),
  CONSTRAINT ck_crew_capacity   CHECK (capacity BETWEEN 2 AND 100),
  CONSTRAINT ck_crew_visibility CHECK (visibility IN ('invite','public'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK, AUTO_INCREMENT | `chat_room.origin_ref` 가 이 값을 문자열로 든다 |
| `name` | `VARCHAR(30)` | NOT NULL | 모임 이름. **방 이름도 이 값**이다 — 고치면 함께 바뀐다 |
| `intro` | `VARCHAR(200)` | NULL | 한 줄 소개. 없어도 된다 |
| `neighborhood_code` | `VARCHAR(10)` | NULL | 행정동 코드(#342). **좌표가 아니다** |
| `visibility` | `VARCHAR(10)` | NOT NULL, CHECK | `invite`(기본) · `public` |
| `capacity` | `INT` | NOT NULL, CHECK 2..100 | **방장이 정한 정원**. 방의 정원과 다른 숫자다 |
| `created_at` / `updated_at` | `DATETIME(6)` | — | 서버가 찍는 UTC |

> **`crew_member` 표를 안 만든다.** 크루의 멤버는 **그 크루 방의 멤버**이고 그것은 `chat_room_member` 다 — [ADR-0011](https://github.com/sanghyunbang/heattrip/issues/72) 이 채팅을 범용 다중 방으로 정하면서 `chat_room.origin_kind`/`origin_ref` 를 열어 뒀고, 그 컬럼 주석이 이미 "가족방도 산책 크루 방도 같은 표에 산다" 고 적고 있었다. 표를 따로 만들면 멤버십이 **두 곳**에 생기고, 언젠가 "크루는 나갔는데 방에는 남아 있는" 계정이 만들어진다. `family_group` 이 같은 이유로 사용자 컬럼을 안 갖는다.
>
> **방장 컬럼도 없다.** 방장은 그 방의 `OWNER` 멤버(`chat_room_member.role`)다. 컬럼을 따로 두면 둘이 갈리는 날 "크루 화면에서는 방장인데 대화방에서는 못 내보내는" 사람이 생긴다.
>
> **`chat_room` 으로 나가는 FK 가 없다.** 방 쪽이 이미 `(origin_kind='CREW', origin_ref=crew.id)` 로 들고 있어 같은 사실이 두 곳에 살게 된다. 그리고 그 FK 를 엔티티가 들려면 `crew` 가 `chat.entity.ChatRoom` 을 import 해야 하는데 그건 모듈 경계를 넘는다(`ChatBoundaryArchitectureTest`) — SQL 에만 적으면 `01_schema.sql` 재생성에서 조용히 사라진다(`schedule.care_log_id` 가 같은 자리다).
>
> **`idx_crew_public (visibility, neighborhood_code)`** 가 "우리 동네 공개 크루" 를 받는다. 찾기는 시군구 **앞 다섯 자리** `LIKE` 라 이 인덱스를 그대로 탄다 — 열 자리를 맞추면 같은 구의 옆 동네 모임이 안 보인다.
>
> **정원 CHECK 는 Hibernate 의 `update` 도 prod 의 `validate` 도 안 본다.** 그래서 `37_crew.sql` 의 사후 검증과 `CrewMigrationExecutionTest` 가 그것을 잰다 — 없으면 아무 데서도 안 잡힌다.


| 테이블 | 인덱스 | 종류 | 목적 |
| --- | --- | --- | --- |
| `users` | `uk_users_provider_social_id(provider, social_id)` | UNIQUE | 소셜 계정 중복 방지 |
| `users` | `uk_users_email(email)` | UNIQUE | 이메일 중복 방지 (NULL 은 서로 다른 값) |
| `refresh_token` | `uk_refresh_token_token_hash(token_hash)` | UNIQUE | 같은 RT 가 두 행이 되지 않게 |
| `refresh_token` | `idx_refresh_token_user_id(user_id)` | 보조 | 전 기기 로그아웃(사용자별 폐기) |
| `refresh_token` | `idx_refresh_token_expires_at(expires_at)` | 보조 | 만료 RT 정리 배치 |
| `dog` | `idx_dog_user(user_id)` | 보조 | 사용자별 강아지 조회 |
| `walk` | `idx_walk_dog(dog_id, started_at)` | 보조 | 강아지별 산책 이력 |
| `course` | `idx_course_user(user_id, created_at)` | 보조 | 내 코스 최근 순 |
| `course` | `idx_course_public(visibility, created_at)` | 보조 | 공개 코스 한 벌(지도의 "이웃 코스") |
| `walk` | `spx_walk_path(path)` | **SPATIAL** | GPS 경로 공간 연산 |
| `walk_dog` | `PRIMARY(dog_id, walk_id)` | PK | "이 아이의 산책" — 아이별 통계·목록이 앞자리를 탄다(#343) |
| `walk_dog` | `fk_walkdog_walk(walk_id)` | 보조(FK 자동) | "이 산책의 아이들" |
| `place` | `uq_place_src(source, external_id)` | UNIQUE | POI 중복 방지 |
| `place` | `idx_place_category(category)` | 보조 | 카테고리 필터 |
| `place` | `spx_place_geom(geom)` | **SPATIAL** | 주변 장소 검색 |
| `place_catalog` | `uk_place_catalog_source(source)` | UNIQUE | 출처(kto·localdata·durunubi)당 한 벌 — #291 |
| `post` | `idx_post_board(board, created_at)` | 보조 | 게시판별 최신순 |
| `comment` | `idx_comment_post(post_id, created_at)` | 보조 | 글별 댓글 |
| `reaction` | `uq_reaction(post_id, user_id, type)` | UNIQUE | 중복 반응 방지 |
| `bookmark` | `uq_bookmark(user_id, place_id)` | UNIQUE | 중복 저장 방지 |
| `chat_room` | `uq_chat_room_origin(origin_kind, origin_ref)` | UNIQUE | 같은 출처에 방이 둘 생기는 것을 막는다 |
| `chat_room_member` | `uq_chat_member(room_id, user_id)` | UNIQUE | 방 중복 참여 방지 |
| `chat_room_member` | `idx_chat_member_user(user_id)` | 보조 | 내 방 목록 조회 |
| `chat_room_invite` | `uq_chat_invite_code(code)` | UNIQUE | 초대코드 중복 방지. 폐기한 코드는 재사용하지 않는다 |
| `chat_room_invite` | `idx_chat_invite_room(room_id, created_at)` | 보조 | 방별 초대코드 이력 |
| `chat_message` | `uq_chat_room_seq(room_id, room_seq)` | UNIQUE | 방별 순서·델타·미읽음의 유일한 근거. `afterSeq` 범위 스캔도 이 인덱스다 |
| `chat_message` | `uq_chat_msg_client(room_id, sender_user_id, client_msg_id)` | UNIQUE | 재전송 멱등. `NULL` 은 여러 번 허용된다. **범위에 보낸 사람이 들어 있다** — 방 전체로 두면 같은 방의 다른 멤버가 같은 키를 썼을 때 그 사람의 메시지가 사라진다(#79) |
| `chat_message` | `idx_chat_sender(sender_user_id)` | 보조 | 발신자별 조회(신고 처리) |
| `walk_note` | `uq_walknote_group(group_id)` | UNIQUE | 그룹당 주의사항 한 장 |
| `care_log` | `idx_carelog_group(group_id, occurred_at)` | 보조 | 그룹별 "오늘의 케어" 조회 |
| `care_log` | `idx_carelog_doneby(done_by)` | 보조 | 사용자 삭제 시 `SET NULL` 이 훑는 자리 |
| `care_log` | `idx_carelog_dog(dog_id, occurred_at)` | 보조 | `dog` 삭제 시 `SET NULL` 이 훑는 자리 · 반려동물별 케어 기록(#154) |
| `device_token` | `uk_device_token_token(token)` | UNIQUE | 같은 기기(토큰)는 한 행 — 등록이 upsert 인 이유(#83) |
| `device_token` | `idx_device_token_user(user_id, revoked_at)` | 보조 | 사용자의 살아 있는 토큰 조회 · 전 기기 폐기(#83) |
| `schedule` | `idx_schedule_owner_date(owner_kind, owner_ref, on_date)` | 보조 | 달력이 묻는 유일한 질문 — "이 주인의 이 기간"(#418) |
| `schedule` | `idx_schedule_dog_date(dog_id, on_date)` | 보조 | "보리 것만" 필터. `dog_id` 로 시작하지 않으면 위 인덱스를 못 쓴다(#418) |

> 공간 컬럼(`walk.path`, `place.geom`)은 모두 `SRID 4326` + `NOT NULL` + `SPATIAL INDEX`. 초기에는 MySQL 공간형 단일 저장소로 운영하고, 대량 GPS 시계열·장소검색(ES/Redis)은 규모 확장 시 옵션이다. 관계 개요는 [ERD](./erd.md) 참조.

---

## 37. `media_objects` — 업로드 객체 원장 (**실재**)

S3 에 올린 파일 하나에 행 하나. 감정 여행 시절(여정·리뷰·프로필 사진)부터 있던 표이고, #429 가 커뮤니티 글의 사진·영상을 여기에 얹었다 — **표를 새로 안 만들었다.** `ref_type`·`ref_id` 가 "어느 도메인의 무엇에 붙었나" 를 불투명한 쌍으로 들게 처음부터 만들어져 있었고, 업로드·삭제·URL 조립이 다 있었다. 같은 원장을 둘로 나누면 삭제와 청소가 두 벌이 된다.

```sql
CREATE TABLE media_objects (
  id            BIGINT        NOT NULL AUTO_INCREMENT,
  category      ENUM('JOURNEY_IMAGE','POST_IMAGE','POST_VIDEO','PROFILE_IMAGE','REVIEW_IMAGE') NOT NULL,
  owner_id      VARCHAR(255)  NOT NULL COMMENT 'users.id 를 문자열로 — 아래 각주',
  ref_type      VARCHAR(255)  NULL COMMENT '어디에 붙었나. POST 면 커뮤니티 글. NULL 이면 아직 안 붙었다',
  ref_id        VARCHAR(255)  NULL COMMENT '무엇에 붙었나. ref_type=POST 면 post.id. FK 는 없다 — 아래 각주',
  media_key     VARCHAR(512)  NOT NULL COMMENT 'S3 object key. URL 은 런타임에 CloudFront 도메인과 조립한다',
  original_name VARCHAR(255)  NULL,
  content_type  VARCHAR(255)  NULL,
  size          BIGINT        NOT NULL,
  status        VARCHAR(10)   NOT NULL COMMENT 'pending|ready — 영상은 앱이 S3 에 직접 올려서 중간 상태가 있다',
  poster_key    VARCHAR(512)  NULL COMMENT '영상 썸네일의 S3 키. 사진은 NULL',
  width         INT           NULL COMMENT '앱이 준 픽셀 폭. 서버는 이미지를 안 연다',
  height        INT           NULL,
  duration_ms   INT           NULL COMMENT '영상 길이. 사진은 NULL',
  created_at    DATETIME(6)   NOT NULL,
  updated_at    DATETIME(6)   NULL,
  deleted_at    DATETIME(6)   NULL COMMENT '감정 여행 시절의 소프트 삭제 자리. 지금 코드는 안 쓴다 — 지울 때 행을 지운다',
  PRIMARY KEY (id),
  UNIQUE KEY UK3pkjswl54cvrded30nci3u45t (media_key),
  KEY idx_media_owner (owner_id),
  KEY idx_media_ref (ref_type, ref_id),
  KEY idx_media_orphan (ref_type, created_at),
  CONSTRAINT ck_media_status CHECK (status IN ('pending','ready'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | |
| `category` | `ENUM` | NOT NULL | `JOURNEY_IMAGE`·`PROFILE_IMAGE`·`REVIEW_IMAGE` 는 감정 여행 시절 값이다. 운영 DB 에 그 값의 행이 남아 있어 못 뺀다. **순서는 알파벳순이다** — 아래 각주 |
| `owner_id` | `VARCHAR(255)` | NOT NULL, INDEX | 올린 사람. `users.id` 를 문자열로 적는다 |
| `ref_type` · `ref_id` | `VARCHAR(255)` | nullable, INDEX(ref_type, ref_id) | 어디의 무엇에 붙었나. 글이면 `('POST', post.id)`. **둘 다 `NULL` 이면 아직 안 붙은 것**이고 하루 뒤 청소 대상이다 |
| `media_key` | `VARCHAR(512)` | NOT NULL, **UNIQUE** | S3 키. 같은 키를 두 번 올리는 경합은 이 제약이 오류 하나로 끝낸다(📌 #86 원칙 5) |
| `status` | `VARCHAR(10)` | NOT NULL, **CHECK** `pending|ready` | 파일이 S3 에 있는가. `pending` 은 글에 안 붙는다 |
| `poster_key` | `VARCHAR(512)` | nullable | 영상 썸네일. 앱이 만들어 따로 올린다 |
| `width` · `height` · `duration_ms` | `INT` | nullable | 앱이 준 값. 피드가 자리를 미리 잡는다 — 없으면 정사각형 |

> **각주 — `post` 로 나가는 FK 가 없는 이유.** `ref_type`·`ref_id` 는 `chat_room.origin_kind`·`origin_ref` 와 같은 **불투명한 쌍**이다(ADR-0011 의 방식). FK 를 걸려면 `S3` 의 엔티티가 `community.entity.Post` 를 들어야 하고 그건 모듈 경계를 넘는다 — 화살표는 `community → S3` 한 방향이어야 한다(`S3/MediaAttachment`). 글을 지울 때 사진을 함께 지우는 것은 **서비스**가 한다(`CommunityService.deletePost` → `MediaAttachment.detachAll`). DB 의 CASCADE 로는 어차피 안 된다 — 버킷의 파일은 DB 가 모른다.
>
> **각주 — `status` 가 왜 있나.** 사진은 서버가 받아 S3 에 놓지만 영상은 **앱이 S3 에 직접** 올린다. `api.heattrip.link` 앞의 Cloudflare 무료 요금제가 요청 본문을 100MB 까지만 받기 때문이다. 그러면 "자리는 잡았는데 아직 안 올라온" 상태가 생기고 그것이 `pending` 이다. "붙었다" 는 상태가 아니다 — `ref_type` 이 말한다. 여기에 또 두면 같은 사실이 두 곳에 산다(`crew_favor.status` 와 같은 판단).
>
> **각주 — 붙지 않은 것은 하루 뒤 거둔다.** 업로드가 글보다 먼저라, 글을 안 쓰고 나간 사람의 파일이 `ref_type IS NULL` 로 남는다. `MediaOrphanSweeper` 가 새벽 4:10 에 `ref_type IS NULL AND created_at < 어제` 를 묻고 행과 S3 객체를 지운다 — `idx_media_orphan` 이 그 질문의 인덱스다. **`POST_*` 카테고리만** 본다. 벌크 삭제라 두 인스턴스가 동시에 돌아도 같다(📌 #86 원칙 2).
>
> **각주 — `owner_id` 가 문자열인 이유.** 감정 여행 시절의 흔적이다. 이슈 #5 이전에는 JWT subject(이메일 또는 `kakao_1234567890`)가 들어갔고 지금은 `users.id` 다. 소유권 검사는 `String.equals` 라 옛 행은 진짜 주인에게도 안 맞는다 — 보안 구멍은 아니다(옛 값은 숫자와 겹칠 수 없다). 백필 여부는 [migration.md](./migration.md) §3-1.
>
> **각주 — enum 의 순서.** Hibernate 가 `@Enumerated(STRING)` 을 MySQL `enum(...)` 으로 뽑는데, 상수를 **알파벳순으로 정렬해** 뽑는다 — 선언 순서가 아니다(2026-09-13 실측. 옛 셋이 우연히 알파벳순이라 몰랐다). 값을 더하려면 컬럼 타입을 다시 쓰는데(`39_post_media.sql` 의 `MODIFY`), 그 순서도 알파벳순이어야 정본 재생성과 갈리지 않는다. `SchemaDdlDriftTest` 가 `column_type` 문자열을 그대로 비교한다. 순서가 바뀌어도 MySQL 은 있는 행의 값을 **이름으로** 옮긴다 — `PROFILE_IMAGE` 는 그대로 `PROFILE_IMAGE` 다.

---

## 38. `post_bookmark` — 글 저장 (**실재**)

"내 사진첩" 에 넣어 둔 글(#451 4번). `post` 1:N, `users` 1:N, 사용자-글 조합 유니크. **§10 `bookmark`(장소 저장, 계획)와 다른 표다** — 대상이 글이다.

```sql
CREATE TABLE post_bookmark (
  id          BIGINT      NOT NULL AUTO_INCREMENT,
  post_id     BIGINT      NOT NULL,
  user_id     BIGINT      NOT NULL COMMENT '저장한 사람. 탈퇴하면 행도 사라진다',
  created_at  DATETIME(6) NOT NULL COMMENT '저장한 순간 - 목록의 정렬 축',
  PRIMARY KEY (id),
  UNIQUE KEY uq_post_bookmark (post_id, user_id),
  KEY idx_post_bookmark_user (user_id, created_at, id),
  CONSTRAINT fk_post_bookmark_post FOREIGN KEY (post_id) REFERENCES post (id) ON DELETE CASCADE,
  CONSTRAINT fk_post_bookmark_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | |
| `post_id` | `BIGINT` | FK→`post.id` **CASCADE**, UNIQUE(post, user) | 저장한 글 |
| `user_id` | `BIGINT` | FK→`users.id` **CASCADE**, NOT NULL | 저장한 사람 |
| `created_at` | `DATETIME(6)` | NOT NULL | 저장한 순간 — 목록의 정렬 축 |

> **각주 — `reaction` 과 닮았지만 다른 점 둘.** 탈퇴하면 **행이 사라진다**(`user_id` CASCADE) —
> 반응은 집계가 남아야 해서 SET NULL 이지만 저장은 그 사람만 보는 목록이라 사람이 없으면 목록도
> 없다. 그리고 **정렬 축이 이 표의 시각**이다 — 저장한 글 목록은 "언제 저장했나" 순이지 글이 쓰인
> 순이 아니다(Instagram 의 저장됨). `idx_post_bookmark_user (user_id, created_at, id)` 가 커서의
> 두 축을 그대로 든다.

> **각주 — 세지 않는다.** "몇 명이 저장했나" 는 화면에 없다. 있으면 글쓴이에게 남의 사진첩을
> 들여다보는 숫자가 된다. 그래서 집계 쿼리도 그것을 위한 인덱스도 없다.

> **각주 — 이 UNIQUE 가 멱등을 딛는다.** 계약의 쓰기는 `POST`/`DELETE .../bookmark` 둘이고 둘 다
> 멱등이다(반응과 같은 모양, `40_post_bookmark.sql`).

---

## 부록 A. 정본의 표 27개 — 어디에 적혀 있나

`01_schema.sql` 의 `CREATE TABLE` 전부다. **상태**는 전부 `실재 §N` 이고 그 절이 정의다. 감정 여행·관광 수집 시절의 표 23개는 2026-09-06 에 #94 로 코드를 지우면서 정본에서 빠졌다 — 운영 DB 에는 남아 있다(§18, 아래 목록). `DocDriftTest` 가 이 표의 이름 집합이 정본의 `CREATE TABLE` 집합과 **정확히 같은지** 재고, `실재 §N` 이 실제 절 번호·제목의 **실재** 표시와 맞는지 잰다(#176) — 정본에서 표 하나가 생기거나 사라지면 여기가 빨간불이다.

| 표 | 상태 | 모듈 | 한 줄 |
| --- | --- | --- | --- |
| `course` | 실재 §31 | `walk` | 내가 걸은 길 중에 남긴 코스 — 양 끝 100m 를 자른 선(#339) |
| `walk_dog` | 실재 §32 | `walk`·`dog` | 한 번의 산책에 함께 나간 아이들(#343). 아이별 통계·목록이 이 표를 본다 |
| `care_log` | 실재 §17 | `care` | 케어 로그 |
| `chat_message` | 실재 §15 | `chat` | 채팅 메시지 |
| `chat_room` | 실재 §12 | `chat` | 채팅방(범용) |
| `chat_room_invite` | 실재 §14 | `chat` | 초대코드 |
| `chat_room_member` | 실재 §13 | `chat` | 방 멤버십 |
| `comment` | 실재 §8 | `community` | 게시글 댓글 |
| `device_token` | 실재 §29 | `push` | 기기 토큰 원장 — 푸시(#83) |
| `crew_favor` | 실재 §36 | `crew` | **품앗이**(#417). 맡으면 크루 소유 일정 한 줄이 생기고 `schedule_id` 가 그것을 든다. 금액도 평점도 없다 |
| `crew` | 실재 §35 | `crew` | 동네 반려인 모임(#417). 멤버십은 `chat_room_member` 가 든다 — `crew_member` 를 안 만든다 |
| `dog` | 실재 §3 | `dog` | 반려동물 프로필(소프트 삭제 `deleted_at`) |
| `family_group` | 실재 §11 | `group` | 가족 케어 그룹 |
| `kto_call_budget` | 실재 §21 | `place` | KTO 일 호출 예산 |
| `media_objects` | 실재 §37 | `S3` · `community` | 업로드 객체 원장(S3 key). #429 가 커뮤니티 글의 사진·영상을 여기에 얹었다 — `ref_type=POST`. 안 붙은 것은 하루 뒤 거둔다 |
| `pet_place_detail` | 실재 §23 | `place` | 장소 상세 캐시 |
| `place_catalog` | 실재 §24 | `place` | 장소 한 벌 — 출처별 한 행(kto·localdata·durunubi, #291) |
| `place_cell` | 실재 §22 | `place` | 주변 장소 셀 스냅샷 |
| `post` | 실재 §7 | `community` | 커뮤니티 게시글 |
| `post_bookmark` | 실재 §38 | `community` | 글 저장(#451 4번) — "내 사진첩". 저장한 순이 정렬 축, 탈퇴하면 행이 사라진다. §10 `bookmark`(장소, 계획)와 다른 표 |
| `push_preference` | 실재 §30 | `push` | 알림 전체 끄기 — 행이 없으면 켜짐(#83) |
| `reaction` | 실재 §9 | `community` | 게시글 반응 |
| `refresh_token` | 실재 §2 | `user` | refresh 토큰 원장 |
| `report` | 실재 §25 | `moderation` | 신고 |
| `report_snapshot` | 실재 §26 | `moderation` | 신고 대상 스냅샷 |
| `schedule` | 실재 §33 | `schedule` | 앞으로 할 일(#418). 주인이 셋이라 `owner_kind`+`owner_ref` 를 불투명하게 든다 |
| `schedule_exception` | 실재 §34 | `schedule` | 반복의 하루짜리 예외(#421). 건너뛴 날과 옮긴 날 |
| `trail_route` | 실재 §6 | `place` | 산책로 코스의 선 — 두루누비 GPX 를 300점 이하로 줄인 `[[경도, 위도]]` JSON(#291) |
| `user_block` | 실재 §27 | `moderation` | 가리기 |
| `user_consent` | 실재 §28 | `consent` | 약관 동의 이력 |
| `users` | 실재 §1 | `user` | 앱 사용자 계정 |

정본에서 빠졌지만 운영 DB 에 남아 있는 표(#94, 2026-09-06): `bookmarks` · `card_comment` · `card_reaction` · `cat3_category_mapping` · `collection_items` · `collections` · `emotion_card` · `emotion_categories` · `emotion_feedbacks` · `emotion_reviews` · `feedback` · `journey` · `journey_photos` · `place_descriptions` · `place_features` · `place_hashtags` · `place_kakao_links` · `place_simple_tags` · `place_star_ratings` · `place_trait_snapshots` · `place_traits` · `places` · `schedule_legacy_journey`. 코드가 없으니 새 행은 생기지 않는다.

> `schedule` 이 이 목록에서 빠지고 `schedule_legacy_journey` 가 들어온 것은 #418 이 그 이름을 다시 쓰기 때문이다. **지운 것이 아니라 옮겼다** — `34_schedule.sql` 이 `RENAME TABLE` 로 옆에 세워 두고, 그 표를 가리키던 `journey.schedule_id` 의 FK 도 MySQL 이 함께 옮긴다(마이그레이션 실행 테스트가 그것을 잰다). 되돌리기는 이름을 되돌리는 것이고 값은 한 줄도 안 잃는다.
| `walk` | 실재 §4 | `walk` | 산책 기록(GPS 경로) |
| `walk_note` | 실재 §16 | `care` | 산책 주의사항(그룹당 한 장) |
