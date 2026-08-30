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

> **어디까지가 실재인가.** `§1 users` 와 `§2 refresh_token` 만 **지금 DB 에 있다** — 정본은 `backend/mysql/init/01_schema.sql` 이고 JPA 엔티티가 그 스키마를 만든다. `§3 dog` 이하는 아직 **계획**이며, 마일스톤이 오면 여기 적힌 모양대로 만든다. 둘을 섞어 읽으면 "있는 줄 알았는데 없는" 테이블에 쿼리를 짜게 된다.

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

  -- 약관 동의
  agree_tos           BIT(1)       NULL,
  agree_privacy       BIT(1)       NULL,
  agree_marketing     BIT(1)       NULL,
  tos_version         VARCHAR(255) NULL,
  privacy_version     VARCHAR(255) NULL,
  marketing_version   VARCHAR(255) NULL,
  tos_agreed_at       DATETIME(6)  NULL,
  privacy_agreed_at   DATETIME(6)  NULL,
  marketing_agreed_at DATETIME(6)  NULL,

  created_at          DATETIME(6)  NULL,
  updated_at          DATETIME(6)  NULL,

  PRIMARY KEY (id),
  UNIQUE KEY uk_users_provider_social_id (provider, social_id),
  UNIQUE KEY uk_users_email (email)
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

## 3. `dog` — 반려견 프로필

사용자의 강아지 프로필. `users` 1:N `dog`. 앱 도메인(`DogProfile`)의 `size`(small/medium/large)·`neutered`·`avatar`와 매핑. 나이는 앱에서 개월 수로 표시하나 DB는 `birth`(생일)로 저장하는 것이 정규.

```sql
CREATE TABLE dog (
  id       BIGINT      NOT NULL AUTO_INCREMENT,
  user_id  BIGINT      NOT NULL,
  name     VARCHAR(50) NOT NULL,
  breed    VARCHAR(50) NULL COMMENT '견종 (예: 믹스견)',
  size     VARCHAR(10) NOT NULL DEFAULT 'small' COMMENT 'small|medium|large',
  birth    DATE        NULL,
  neutered BOOLEAN     NOT NULL DEFAULT FALSE,
  avatar   VARCHAR(255) NULL COMMENT '아바타 에셋/이미지 경로',
  created_at DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_dog_user (user_id),
  CONSTRAINT fk_dog_user FOREIGN KEY (user_id)
    REFERENCES users (id) ON DELETE CASCADE,
  CONSTRAINT ck_dog_size CHECK (size IN ('small','medium','large'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | |
| `user_id` | `BIGINT` | FK→`users.id`, NOT NULL, INDEX | 소유 사용자 |
| `name` | `VARCHAR(50)` | NOT NULL | 이름 |
| `breed` | `VARCHAR(50)` | NULL | 견종 |
| `size` | `VARCHAR(10)` | NOT NULL, CHECK | 소/중/대형견 |
| `birth` | `DATE` | NULL | 생일(나이 산출) |
| `neutered` | `BOOLEAN` | NOT NULL 기본 FALSE | 중성화 여부 |
| `avatar` | `VARCHAR(255)` | NULL | 아바타 경로 |

---

## 4. `walk` — 산책 기록 (GPS 경로)

산책 1건. GPS 경로를 `LINESTRING`으로 저장하고 거리(`distance_m`)·시간(`duration_s`)·메모·날씨를 함께 보관. `dog` 1:N `walk`. 페이스는 `distance_m`/`duration_s`로 파생(비저장).

```sql
CREATE TABLE walk (
  id          BIGINT     NOT NULL AUTO_INCREMENT,
  dog_id      BIGINT     NOT NULL,
  started_at  DATETIME   NOT NULL,
  ended_at    DATETIME   NULL,
  distance_m  INT        NOT NULL DEFAULT 0 COMMENT '총 거리(m)',
  duration_s  INT        NOT NULL DEFAULT 0 COMMENT '총 소요(초)',
  path        LINESTRING SRID 4326 NOT NULL COMMENT 'GPS 경로(폴리라인)',
  memo        VARCHAR(500) NULL,
  weather     VARCHAR(30)  NULL,
  created_at  DATETIME   NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_walk_dog (dog_id, started_at),
  SPATIAL INDEX spx_walk_path (path),
  CONSTRAINT fk_walk_dog FOREIGN KEY (dog_id)
    REFERENCES dog (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | |
| `dog_id` | `BIGINT` | FK→`dog.id`, NOT NULL, INDEX(dog_id,started_at) | 산책한 강아지 |
| `started_at` | `DATETIME` | NOT NULL | 시작 시각 |
| `ended_at` | `DATETIME` | NULL | 종료 시각(진행 중이면 NULL) |
| `distance_m` | `INT` | NOT NULL 기본 0 | 거리(m) |
| `duration_s` | `INT` | NOT NULL 기본 0 | 소요(초) |
| `path` | `LINESTRING` | **SRID 4326, NOT NULL, SPATIAL INDEX** | GPS 경로 폴리라인 |
| `memo` | `VARCHAR(500)` | NULL | 메모 |
| `weather` | `VARCHAR(30)` | NULL | 날씨 |

> `path`는 `SPATIAL INDEX` 요건상 `NOT NULL`. 산책 시작 직후 최소 1점 이상으로 초기화하거나, 종료 시점에 확정 저장하는 정책을 택한다.

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

## 6. `trail` — 산책로 코스 (경로 LINESTRING)

두루누비(걷기여행길) 산책로 코스. 경로를 `LINESTRING`으로 저장. 현재 다른 엔티티와 FK 없이 지도 레이어(`trail` 카테고리)에만 사용(향후 `walk`/`post` 연결 확장 여지).

```sql
CREATE TABLE trail (
  id       BIGINT      NOT NULL AUTO_INCREMENT,
  source   VARCHAR(30) NOT NULL DEFAULT 'durunubi' COMMENT '두루누비(걷기여행길)',
  name     VARCHAR(150) NOT NULL,
  path     LINESTRING  SRID 4326 NOT NULL COMMENT '산책로 경로',
  length_m INT         NULL COMMENT '코스 길이(m)',
  created_at DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  SPATIAL INDEX spx_trail_path (path)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | |
| `source` | `VARCHAR(30)` | NOT NULL 기본 durunubi | 데이터 출처 |
| `name` | `VARCHAR(150)` | NOT NULL | 코스명 |
| `path` | `LINESTRING` | **SRID 4326, NOT NULL, SPATIAL INDEX** | 코스 경로 |
| `length_m` | `INT` | NULL | 코스 길이(m) |

---

## 7. `post` — 커뮤니티 게시글

커뮤니티 글. 게시판(`board`)으로 분류하고 장소(`place`) 선택 태그 가능(`place_id` nullable). `users` 1:N `post`.

```sql
CREATE TABLE post (
  id         BIGINT      NOT NULL AUTO_INCREMENT,
  user_id    BIGINT      NOT NULL,
  board      VARCHAR(20) NOT NULL COMMENT '산책로후기|동반장소|건강·병원|자유|자랑',
  place_id   BIGINT      NULL COMMENT '태그된 장소(nullable)',
  title      VARCHAR(150) NOT NULL,
  body       TEXT        NOT NULL,
  created_at DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_post_board (board, created_at),
  KEY idx_post_user (user_id),
  KEY idx_post_place (place_id),
  CONSTRAINT fk_post_user FOREIGN KEY (user_id)
    REFERENCES users (id) ON DELETE CASCADE,
  CONSTRAINT fk_post_place FOREIGN KEY (place_id)
    REFERENCES place (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | |
| `user_id` | `BIGINT` | FK→`users.id`, NOT NULL, INDEX | 작성자 |
| `board` | `VARCHAR(20)` | NOT NULL, INDEX(board,created_at) | 게시판 |
| `place_id` | `BIGINT` | FK→`place.id` nullable, ON DELETE SET NULL | 태그 장소 |
| `title` | `VARCHAR(150)` | NOT NULL | 제목 |
| `body` | `TEXT` | NOT NULL | 본문 |

---

## 8. `comment` — 댓글

게시글 댓글. `post` 1:N, `users` 1:N.

```sql
CREATE TABLE comment (
  id         BIGINT   NOT NULL AUTO_INCREMENT,
  post_id    BIGINT   NOT NULL,
  user_id    BIGINT   NOT NULL,
  body       TEXT     NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_comment_post (post_id, created_at),
  KEY idx_comment_user (user_id),
  CONSTRAINT fk_comment_post FOREIGN KEY (post_id)
    REFERENCES post (id) ON DELETE CASCADE,
  CONSTRAINT fk_comment_user FOREIGN KEY (user_id)
    REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | |
| `post_id` | `BIGINT` | FK→`post.id`, NOT NULL, INDEX | 대상 글 |
| `user_id` | `BIGINT` | FK→`users.id`, NOT NULL | 작성자 |
| `body` | `TEXT` | NOT NULL | 내용 |

---

## 9. `reaction` — 반응

게시글 반응(도움돼요/귀여워요/공감). 사용자당 글별 반응 유형 유니크. `post` 1:N, `users` 1:N.

```sql
CREATE TABLE reaction (
  id         BIGINT      NOT NULL AUTO_INCREMENT,
  post_id    BIGINT      NOT NULL,
  user_id    BIGINT      NOT NULL,
  type       VARCHAR(10) NOT NULL COMMENT 'help|cute|empathy',
  created_at DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_reaction (post_id, user_id, type),
  KEY idx_reaction_user (user_id),
  CONSTRAINT fk_reaction_post FOREIGN KEY (post_id)
    REFERENCES post (id) ON DELETE CASCADE,
  CONSTRAINT fk_reaction_user FOREIGN KEY (user_id)
    REFERENCES users (id) ON DELETE CASCADE,
  CONSTRAINT ck_reaction_type CHECK (type IN ('help','cute','empathy'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | |
| `post_id` | `BIGINT` | FK→`post.id`, NOT NULL, UNIQUE(post,user,type) | 대상 글 |
| `user_id` | `BIGINT` | FK→`users.id`, NOT NULL | 남긴 사람 |
| `type` | `VARCHAR(10)` | NOT NULL, CHECK | `help`(도움돼요)/`cute`(귀여워요)/`empathy`(공감) |

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

## 11. `family_group` — 가족 케어 그룹

가족이 함께 반려를 돌보는 그룹. **이름과 생성 시각만 든다** — 초대코드도 멤버십도 여기 없다. 초대는 `chat_room_invite`(§14), 멤버십은 `chat_room_member`(§13)가 가지고, 이 그룹의 방은 `chat_room`(§12)이 `origin_kind='FAMILY'` / `origin_ref=family_group.id` 로 **불투명하게** 가리킨다. `chat_room` → `family_group` 방향 FK 는 없고, `chat_room` 의 `UNIQUE(origin_kind, origin_ref)` 가 같은 그룹에 방이 둘 생기는 것을 DB 수준에서 막는다([ADR-0011](../99-decisions/decision-log.md#adr-0011--채팅은-가족-그룹-종속이-아니라-범용-다중-방이다)).

> **예전 정의에는 `invite_code VARCHAR(12)` + `UNIQUE KEY uq_group_invite` 가 있었다.** 그건 그룹당 코드 하나가 영구히 사는 모양이라 만료·사용횟수·폐기를 걸 자리가 없고, 코드를 바꾸려면 그룹 행을 UPDATE 해야 해서 누가 언제 발급했는지가 남지 않는다. 초대코드는 §14 로 나갔다.

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

## 12. `chat_room` — 채팅방 (범용)

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

> **각주 — 왜 `title` 이 아니라 `name` 이고, 왜 `tag` 가 붙었나.** 이 절의 예전 초안은 이름 컬럼을 `title` 로 적고 `tag` 를 빼먹었다. 이미 커밋돼 있는 앱의 `ChatRoom`(`app/lib/v2/domain/pet.dart:437`)이 `name:` 과 `tag:` 를 요구하고, `chat_list_screen.dart` 는 두 방을 같은 화면으로 넘기면서 **종류를 `tag` 로만 가른다.** [ADR-0011](../99-decisions/decision-log.md#adr-0011--채팅은-가족-그룹-종속이-아니라-범용-다중-방이다)의 출발점이 "화면이 먼저 커밋돼 있고 그 화면이 데이터 모양을 정해 놨다" 인 이상, 이름이 갈리면 API 계층이 매번 두 이름을 옮겨 적어야 한다. 그래서 화면 쪽으로 맞췄다.

> 발급과 메시지 INSERT 는 **하나의 트랜잭션**이다. 발급만 별도 트랜잭션으로 떼면 `id` 커서와 똑같은 구멍(§15 참조)이 생긴다. 락 순서는 항상 `chat_room` → `chat_room_member` 이고, **락을 쥔 트랜잭션 안에서 외부 호출(푸시·S3)을 하지 않는다.**

---

## 13. `chat_room_member` — 방 멤버십

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
| `last_read_seq` | `BIGINT` | NOT NULL, 기본 0 | `GREATEST`·`LEAST` 로만 갱신 — 뒤로 못 가고 `room.last_seq` 를 넘지 못한다 |
| `removed_at` | `DATETIME` | NULL | 강퇴 시각 |
| `removed_by` | `BIGINT` | NULL, **FK 없음** | 강퇴한 방장 |
| `rejoin_blocked` | `BIT(1)` | NOT NULL, 기본 `b'0'` | 유효한 초대코드로도 다시 못 들어온다 |

---

## 14. `chat_room_invite` — 초대코드

초대코드를 그룹 행의 컬럼 하나로 두지 않고 별도 표에 둔다. 유효기간·사용횟수·회수를 처음부터 갖추고, **누가 언제 발급했는지가 남는다.** 기본값은 **7일 · 사용 횟수 무제한**이다. 방장이 재발급하면 이전 코드는 즉시 `revoked_at` 이 찍히고 **기존 멤버는 그대로 남는다** — 코드가 유출됐을 때의 유일한 대응 수단이다. 폐기한 `code` 는 UNIQUE 라 재사용하지 않는다.

```sql
CREATE TABLE chat_room_invite (
  id         BIGINT      NOT NULL AUTO_INCREMENT,
  room_id    BIGINT      NOT NULL,
  code       VARCHAR(32) NOT NULL COMMENT '초대코드',
  created_by BIGINT      NOT NULL COMMENT 'users.id — FK 없음(경계)',
  expires_at DATETIME    NULL COMMENT 'NULL = 무기한. 기본은 발급 + 7일',
  max_uses   INT         NULL COMMENT 'NULL = 무제한(기본)',
  used_count INT         NOT NULL DEFAULT 0,
  revoked_at DATETIME    NULL COMMENT '재발급·회수 시각',
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

## 15. `chat_message` — 채팅 메시지

방 안의 메시지. 조회는 `afterSeq`(델타·오름차순) 또는 `beforeSeq`(과거·내림차순)이고 MVP 는 폴링이다. 소켓은 실측 트리거가 걸릴 때만 연다(M2.9).

**`id` 를 커서로 쓰지 않는다.** `AUTO_INCREMENT` 는 **배정 시점**에 정해지고 커밋 순서와 다르다. 늦게 커밋된 작은 `id` 가 뒤늦게 보이면 `afterId` 폴링은 그 메시지를 **영구히** 건너뛴다. `room_seq` 는 방 단위로 빈틈 없이 발급하므로 델타·순서·미읽음이 전부 이 하나로 풀린다.

**`sender_user_id` 에 FK 를 걸지 않는다.** chat 경계 밖으로 FK 를 내지 않는 것이 이 도메인의 규칙이고, `refresh_token`(#9)이 이미 같은 방식이다. 탈퇴한 사용자의 메시지가 남아야 대화가 읽히므로 `ON DELETE CASCADE` 는 특히 안 된다 — 예전 정의의 `fk_chat_user ... ON DELETE CASCADE` 는 탈퇴 한 번에 남의 대화 흐름을 지운다.

**`sender_name` 은 스냅샷이다.** `users.nickname varchar(255)` 와 폭을 맞춘다. 닉네임이 바뀌어도 과거 대화의 화자는 바뀌지 않는다. 응답의 `senderName` 은 `users` 에 있으면 현재 닉네임, 없으면(탈퇴) "알 수 없음" 이다.

```sql
CREATE TABLE chat_message (
  id             BIGINT       NOT NULL AUTO_INCREMENT,
  room_id        BIGINT       NOT NULL,
  room_seq       BIGINT       NOT NULL COMMENT '방 안에서 빈틈 없이 1씩 증가',
  sender_user_id BIGINT       NOT NULL COMMENT 'users.id — FK 없음(경계)',
  sender_name    VARCHAR(255) NOT NULL COMMENT '발신 시점 닉네임 스냅샷',
  content_type   VARCHAR(16)  NOT NULL DEFAULT 'text',
  body           TEXT         NOT NULL,
  created_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at     DATETIME     NULL COMMENT '삭제는 소프트 — 뺀 자리가 seq 빈틈이 되면 안 된다',
  PRIMARY KEY (id),
  UNIQUE KEY uq_chat_room_seq (room_id, room_seq),
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
| `sender_name` | `VARCHAR(255)` | NOT NULL | 발신 시점 닉네임 스냅샷 |
| `content_type` | `VARCHAR(16)` | NOT NULL, 기본 `text` | 본문 종류 |
| `body` | `TEXT` | NOT NULL | 메시지 본문 |
| `created_at` | `DATETIME` | NOT NULL, 기본 now | 전송 시각 |
| `deleted_at` | `DATETIME` | NULL | 소프트 삭제 |

---

## 16. `walk_note` — 산책 주의사항 (가족 공유 메모)

산책 시 주의사항을 가족이 공유하는 메모. `family_group` 1:N (`GET|PUT /api/groups/{groupId}/walk-notes`).

```sql
CREATE TABLE walk_note (
  id         BIGINT       NOT NULL AUTO_INCREMENT,
  group_id   BIGINT       NOT NULL,
  body       VARCHAR(500) NOT NULL COMMENT '산책 시 주의사항',
  created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_walknote_group (group_id, created_at),
  CONSTRAINT fk_walknote_group FOREIGN KEY (group_id)
    REFERENCES family_group (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | |
| `group_id` | `BIGINT` | FK→`family_group.id`, NOT NULL, INDEX(group,created_at) | 소속 그룹 |
| `body` | `VARCHAR(500)` | NOT NULL | 주의사항 내용 |
| `created_at` | `DATETIME` | NOT NULL, 기본 now | 작성 시각 |

---

## 17. `care_log` — 케어 로그 (가족 케어 공유)

당초 post-MVP 확장으로 계획했던 테이블을 **가족 케어 공유**에 맞춰 확장한 정의. 물/밥/산책/투약/병원 로그를 하나의 유연 스키마로 저장하고, 누가(`done_by`)·언제 했는지를 가족 그룹(`group_id`, nullable)에 공유해 이중 급여·산책 누락을 방지한다. FK 관계상 `family_group`(§11) 생성 후 적용한다.

```sql
CREATE TABLE care_log (
  id          BIGINT      NOT NULL AUTO_INCREMENT,
  dog_id      BIGINT      NOT NULL,
  group_id    BIGINT      NULL COMMENT '가족 그룹 공유(nullable — 미소속 시 개인 기록)',
  type        VARCHAR(10) NOT NULL COMMENT 'water|meal|walk|med|vet',
  done_by     BIGINT      NOT NULL COMMENT '수행자(users.id) — 누가 했는지',
  occurred_at DATETIME    NOT NULL,
  title       VARCHAR(100) NULL,
  value       VARCHAR(100) NULL COMMENT '수치/양 등 (예: 몸무게 5.2kg)',
  memo        VARCHAR(500) NULL,
  photo       VARCHAR(255) NULL,
  created_at  DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_carelog_dog (dog_id, occurred_at),
  KEY idx_carelog_group (group_id, occurred_at),
  KEY idx_carelog_doneby (done_by),
  CONSTRAINT fk_carelog_dog FOREIGN KEY (dog_id)
    REFERENCES dog (id) ON DELETE CASCADE,
  CONSTRAINT fk_carelog_group FOREIGN KEY (group_id)
    REFERENCES family_group (id) ON DELETE SET NULL,
  CONSTRAINT fk_carelog_doneby FOREIGN KEY (done_by)
    REFERENCES users (id) ON DELETE CASCADE,
  CONSTRAINT ck_carelog_type CHECK (type IN ('water','meal','walk','med','vet'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | |
| `dog_id` | `BIGINT` | FK→`dog.id`, NOT NULL, INDEX(dog,occurred_at) | 대상 강아지 |
| `group_id` | `BIGINT` | FK→`family_group.id` nullable, ON DELETE SET NULL, INDEX(group,occurred_at) | 공유 대상 가족 그룹 |
| `type` | `VARCHAR(10)` | NOT NULL, CHECK | `water`(물)/`meal`(밥)/`walk`(산책)/`med`(투약)/`vet`(병원) |
| `done_by` | `BIGINT` | FK→`users.id`, NOT NULL, INDEX | 수행자(누가 했는지) |
| `occurred_at` | `DATETIME` | NOT NULL | 발생 시각(언제 했는지) |
| `title` | `VARCHAR(100)` | NULL | 제목 |
| `value` | `VARCHAR(100)` | NULL | 수치/양 |
| `memo` | `VARCHAR(500)` | NULL | 메모 |
| `photo` | `VARCHAR(255)` | NULL | 사진 경로 |

> "오늘의 케어" 조회(`GET /api/groups/{groupId}/care-logs`)는 `idx_carelog_group(group_id, occurred_at)`으로 그룹·당일 범위를 스캔한다.

---

## 인덱스 · 공간 인덱스 요약

| 테이블 | 인덱스 | 종류 | 목적 |
| --- | --- | --- | --- |
| `users` | `uk_users_provider_social_id(provider, social_id)` | UNIQUE | 소셜 계정 중복 방지 |
| `users` | `uk_users_email(email)` | UNIQUE | 이메일 중복 방지 (NULL 은 서로 다른 값) |
| `refresh_token` | `uk_refresh_token_token_hash(token_hash)` | UNIQUE | 같은 RT 가 두 행이 되지 않게 |
| `refresh_token` | `idx_refresh_token_user_id(user_id)` | 보조 | 전 기기 로그아웃(사용자별 폐기) |
| `refresh_token` | `idx_refresh_token_expires_at(expires_at)` | 보조 | 만료 RT 정리 배치 |
| `dog` | `idx_dog_user(user_id)` | 보조 | 사용자별 강아지 조회 |
| `walk` | `idx_walk_dog(dog_id, started_at)` | 보조 | 강아지별 산책 이력 |
| `walk` | `spx_walk_path(path)` | **SPATIAL** | GPS 경로 공간 연산 |
| `place` | `uq_place_src(source, external_id)` | UNIQUE | POI 중복 방지 |
| `place` | `idx_place_category(category)` | 보조 | 카테고리 필터 |
| `place` | `spx_place_geom(geom)` | **SPATIAL** | 주변 장소 검색 |
| `trail` | `spx_trail_path(path)` | **SPATIAL** | 산책로 코스 공간 표시 |
| `post` | `idx_post_board(board, created_at)` | 보조 | 게시판별 최신순 |
| `comment` | `idx_comment_post(post_id, created_at)` | 보조 | 글별 댓글 |
| `reaction` | `uq_reaction(post_id, user_id, type)` | UNIQUE | 중복 반응 방지 |
| `bookmark` | `uq_bookmark(user_id, place_id)` | UNIQUE | 중복 저장 방지 |
| `chat_room` | `uq_chat_room_origin(origin_kind, origin_ref)` | UNIQUE | 같은 출처에 방이 둘 생기는 것을 막는다 |
| `chat_room_member` | `uq_chat_member(room_id, user_id)` | UNIQUE | 방 중복 참여 방지 |
| `chat_room_member` | `idx_chat_member_user(user_id)` | 보조 | 내 방 목록 조회 |
| `chat_room_invite` | `uq_chat_invite_code(code)` | UNIQUE | 초대코드 중복 방지. 폐기한 코드는 재사용하지 않는다 |
| `chat_room_invite` | `idx_chat_invite_room(room_id, created_at)` | 보조 | 방별 초대코드 이력 |
| `chat_message` | `uq_chat_room_seq(room_id, room_seq)` | UNIQUE | 방별 순서·델타·미읽음의 유일한 근거 |
| `chat_message` | `idx_chat_sender(sender_user_id)` | 보조 | 발신자별 조회(신고 처리) |
| `walk_note` | `idx_walknote_group(group_id, created_at)` | 보조 | 그룹별 산책 주의사항 조회 |
| `care_log` | `idx_carelog_dog(dog_id, occurred_at)` | 보조 | 강아지별 케어 이력 |
| `care_log` | `idx_carelog_group(group_id, occurred_at)` | 보조 | 그룹별 "오늘의 케어" 조회 |

> 공간 컬럼(`walk.path`, `place.geom`, `trail.path`)은 모두 `SRID 4326` + `NOT NULL` + `SPATIAL INDEX`. 초기에는 MySQL 공간형 단일 저장소로 운영하고, 대량 GPS 시계열·장소검색(ES/Redis)은 규모 확장 시 옵션이다. 관계 개요는 [ERD](./erd.md) 참조.
