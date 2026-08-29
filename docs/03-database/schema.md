# 테이블 스키마 (MySQL DDL)

> Pawloop(포루프) MySQL 공간형 스키마의 테이블별 상세 정의(DDL). 각 테이블의 컬럼·타입·제약·인덱스(특히 `SPATIAL INDEX`)·FK를 명세한다. GPS 산책 경로는 `walk.path`(`LINESTRING`), 장소 좌표는 `place.geom`(`POINT`)에 공간 컬럼으로 저장하고 `SPATIAL INDEX` + `ST_Distance_Sphere`/`MBRContains`로 주변 검색을 수행한다. **가족 케어 공유** 기능으로 `family_group`·`group_member`·`chat_message`·`walk_note` 테이블이 추가되고, `care_log`는 `group_id`/`done_by`를 더해 가족 공유 케어 기록으로 확장된다. 전체 관계는 [ERD](./erd.md) 참조.

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

---

## 1. `app_user` — 사용자 계정

소셜 로그인 기반 계정(로그인 자체는 post-MVP). `provider + social_id` 조합이 유니크.

```sql
CREATE TABLE app_user (
  id         BIGINT       NOT NULL AUTO_INCREMENT,
  provider   VARCHAR(20)  NOT NULL COMMENT 'kakao|naver|google (post-MVP)',
  social_id  VARCHAR(191) NOT NULL COMMENT '소셜 제공자 고유 ID',
  nickname   VARCHAR(50)  NOT NULL,
  created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_user_social (provider, social_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK, AUTO_INCREMENT | |
| `provider` | `VARCHAR(20)` | NOT NULL | `kakao`/`naver`/`google` (post-MVP) |
| `social_id` | `VARCHAR(191)` | NOT NULL, UNIQUE(provider,social_id) | 소셜 고유 ID |
| `nickname` | `VARCHAR(50)` | NOT NULL | 표시 닉네임 |
| `created_at` | `DATETIME` | NOT NULL, 기본 now | 가입 시각 |

---

## 2. `dog` — 반려견 프로필

사용자의 강아지 프로필. `app_user` 1:N `dog`. 앱 도메인(`DogProfile`)의 `size`(small/medium/large)·`neutered`·`avatar`와 매핑. 나이는 앱에서 개월 수로 표시하나 DB는 `birth`(생일)로 저장하는 것이 정규.

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
    REFERENCES app_user (id) ON DELETE CASCADE,
  CONSTRAINT ck_dog_size CHECK (size IN ('small','medium','large'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | |
| `user_id` | `BIGINT` | FK→`app_user.id`, NOT NULL, INDEX | 소유 사용자 |
| `name` | `VARCHAR(50)` | NOT NULL | 이름 |
| `breed` | `VARCHAR(50)` | NULL | 견종 |
| `size` | `VARCHAR(10)` | NOT NULL, CHECK | 소/중/대형견 |
| `birth` | `DATE` | NULL | 생일(나이 산출) |
| `neutered` | `BOOLEAN` | NOT NULL 기본 FALSE | 중성화 여부 |
| `avatar` | `VARCHAR(255)` | NULL | 아바타 경로 |

---

## 3. `walk` — 산책 기록 (GPS 경로)

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

## 4. `place` — 장소 POI 캐시 (좌표 POINT)

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

## 5. `trail` — 산책로 코스 (경로 LINESTRING)

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

## 6. `post` — 커뮤니티 게시글

커뮤니티 글. 게시판(`board`)으로 분류하고 장소(`place`) 선택 태그 가능(`place_id` nullable). `app_user` 1:N `post`.

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
    REFERENCES app_user (id) ON DELETE CASCADE,
  CONSTRAINT fk_post_place FOREIGN KEY (place_id)
    REFERENCES place (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | |
| `user_id` | `BIGINT` | FK→`app_user.id`, NOT NULL, INDEX | 작성자 |
| `board` | `VARCHAR(20)` | NOT NULL, INDEX(board,created_at) | 게시판 |
| `place_id` | `BIGINT` | FK→`place.id` nullable, ON DELETE SET NULL | 태그 장소 |
| `title` | `VARCHAR(150)` | NOT NULL | 제목 |
| `body` | `TEXT` | NOT NULL | 본문 |

---

## 7. `comment` — 댓글

게시글 댓글. `post` 1:N, `app_user` 1:N.

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
    REFERENCES app_user (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | |
| `post_id` | `BIGINT` | FK→`post.id`, NOT NULL, INDEX | 대상 글 |
| `user_id` | `BIGINT` | FK→`app_user.id`, NOT NULL | 작성자 |
| `body` | `TEXT` | NOT NULL | 내용 |

---

## 8. `reaction` — 반응

게시글 반응(도움돼요/귀여워요/공감). 사용자당 글별 반응 유형 유니크. `post` 1:N, `app_user` 1:N.

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
    REFERENCES app_user (id) ON DELETE CASCADE,
  CONSTRAINT ck_reaction_type CHECK (type IN ('help','cute','empathy'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | |
| `post_id` | `BIGINT` | FK→`post.id`, NOT NULL, UNIQUE(post,user,type) | 대상 글 |
| `user_id` | `BIGINT` | FK→`app_user.id`, NOT NULL | 남긴 사람 |
| `type` | `VARCHAR(10)` | NOT NULL, CHECK | `help`(도움돼요)/`cute`(귀여워요)/`empathy`(공감) |

---

## 9. `bookmark` — 장소 저장

사용자가 저장한 장소. `app_user`·`place` 각각 1:N, 사용자-장소 조합 유니크.

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
    REFERENCES app_user (id) ON DELETE CASCADE,
  CONSTRAINT fk_bookmark_place FOREIGN KEY (place_id)
    REFERENCES place (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | |
| `user_id` | `BIGINT` | FK→`app_user.id`, NOT NULL, UNIQUE(user,place) | 저장한 사람 |
| `place_id` | `BIGINT` | FK→`place.id`, NOT NULL, INDEX | 저장 대상 |

---

## 10. `family_group` — 가족 케어 그룹

가족이 함께 반려를 돌보는 그룹. 초대코드(`invite_code`)로 멤버가 참여하며, 케어 공유·산책 주의사항·그룹 채팅의 단위가 된다.

```sql
CREATE TABLE family_group (
  id          BIGINT      NOT NULL AUTO_INCREMENT,
  name        VARCHAR(50) NOT NULL,
  invite_code VARCHAR(12) NOT NULL COMMENT '가족 초대코드',
  created_at  DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_group_invite (invite_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | |
| `name` | `VARCHAR(50)` | NOT NULL | 그룹 이름 |
| `invite_code` | `VARCHAR(12)` | NOT NULL, UNIQUE | 초대코드(`POST /api/groups/join`) |
| `created_at` | `DATETIME` | NOT NULL, 기본 now | 생성 시각 |

---

## 11. `group_member` — 그룹 구성원

`family_group`↔`app_user` 연결(N:M 해소). 그룹 생성자는 `owner`, 초대코드로 참여한 멤버는 `member`. 그룹-사용자 조합 유니크.

```sql
CREATE TABLE group_member (
  id        BIGINT      NOT NULL AUTO_INCREMENT,
  group_id  BIGINT      NOT NULL,
  user_id   BIGINT      NOT NULL,
  role      VARCHAR(10) NOT NULL DEFAULT 'member' COMMENT 'owner|member',
  joined_at DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_member (group_id, user_id),
  KEY idx_member_user (user_id),
  CONSTRAINT fk_member_group FOREIGN KEY (group_id)
    REFERENCES family_group (id) ON DELETE CASCADE,
  CONSTRAINT fk_member_user FOREIGN KEY (user_id)
    REFERENCES app_user (id) ON DELETE CASCADE,
  CONSTRAINT ck_member_role CHECK (role IN ('owner','member'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | |
| `group_id` | `BIGINT` | FK→`family_group.id`, NOT NULL, UNIQUE(group,user) | 소속 그룹 |
| `user_id` | `BIGINT` | FK→`app_user.id`, NOT NULL, INDEX | 구성원 |
| `role` | `VARCHAR(10)` | NOT NULL 기본 member, CHECK | `owner`/`member` |
| `joined_at` | `DATETIME` | NOT NULL, 기본 now | 참여 시각 |

---

## 12. `chat_message` — 가족 그룹 채팅

그룹 채팅 메시지. 커서 페이지네이션(`id` 커서)으로 조회하며, MVP는 폴링·실시간(WebSocket/STOMP)은 post-MVP. `family_group` 1:N, `app_user` 1:N.

```sql
CREATE TABLE chat_message (
  id         BIGINT   NOT NULL AUTO_INCREMENT,
  group_id   BIGINT   NOT NULL,
  user_id    BIGINT   NOT NULL,
  body       TEXT     NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_chat_group (group_id, id),
  KEY idx_chat_user (user_id),
  CONSTRAINT fk_chat_group FOREIGN KEY (group_id)
    REFERENCES family_group (id) ON DELETE CASCADE,
  CONSTRAINT fk_chat_user FOREIGN KEY (user_id)
    REFERENCES app_user (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | 커서 페이지네이션 기준 |
| `group_id` | `BIGINT` | FK→`family_group.id`, NOT NULL, INDEX(group_id,id) | 대상 그룹 |
| `user_id` | `BIGINT` | FK→`app_user.id`, NOT NULL | 작성자 |
| `body` | `TEXT` | NOT NULL | 메시지 본문 |
| `created_at` | `DATETIME` | NOT NULL, 기본 now | 전송 시각 |

---

## 13. `walk_note` — 산책 주의사항 (가족 공유 메모)

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

## 14. `care_log` — 케어 로그 (가족 케어 공유)

당초 post-MVP 확장으로 계획했던 테이블을 **가족 케어 공유**에 맞춰 확장한 정의. 물/밥/산책/투약/병원 로그를 하나의 유연 스키마로 저장하고, 누가(`done_by`)·언제 했는지를 가족 그룹(`group_id`, nullable)에 공유해 이중 급여·산책 누락을 방지한다. FK 관계상 `family_group`(10) 생성 후 적용한다.

```sql
CREATE TABLE care_log (
  id          BIGINT      NOT NULL AUTO_INCREMENT,
  dog_id      BIGINT      NOT NULL,
  group_id    BIGINT      NULL COMMENT '가족 그룹 공유(nullable — 미소속 시 개인 기록)',
  type        VARCHAR(10) NOT NULL COMMENT 'water|meal|walk|med|vet',
  done_by     BIGINT      NOT NULL COMMENT '수행자(app_user.id) — 누가 했는지',
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
    REFERENCES app_user (id) ON DELETE CASCADE,
  CONSTRAINT ck_carelog_type CHECK (type IN ('water','meal','walk','med','vet'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

| 컬럼 | 타입 | 제약 | 설명 |
| --- | --- | --- | --- |
| `id` | `BIGINT` | PK | |
| `dog_id` | `BIGINT` | FK→`dog.id`, NOT NULL, INDEX(dog,occurred_at) | 대상 강아지 |
| `group_id` | `BIGINT` | FK→`family_group.id` nullable, ON DELETE SET NULL, INDEX(group,occurred_at) | 공유 대상 가족 그룹 |
| `type` | `VARCHAR(10)` | NOT NULL, CHECK | `water`(물)/`meal`(밥)/`walk`(산책)/`med`(투약)/`vet`(병원) |
| `done_by` | `BIGINT` | FK→`app_user.id`, NOT NULL, INDEX | 수행자(누가 했는지) |
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
| `app_user` | `uq_user_social(provider, social_id)` | UNIQUE | 소셜 계정 중복 방지 |
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
| `family_group` | `uq_group_invite(invite_code)` | UNIQUE | 초대코드 중복 방지 |
| `group_member` | `uq_member(group_id, user_id)` | UNIQUE | 그룹 중복 참여 방지 |
| `chat_message` | `idx_chat_group(group_id, id)` | 보조 | 그룹별 채팅 커서 페이지네이션 |
| `walk_note` | `idx_walknote_group(group_id, created_at)` | 보조 | 그룹별 산책 주의사항 조회 |
| `care_log` | `idx_carelog_dog(dog_id, occurred_at)` | 보조 | 강아지별 케어 이력 |
| `care_log` | `idx_carelog_group(group_id, occurred_at)` | 보조 | 그룹별 "오늘의 케어" 조회 |

> 공간 컬럼(`walk.path`, `place.geom`, `trail.path`)은 모두 `SRID 4326` + `NOT NULL` + `SPATIAL INDEX`. 초기에는 MySQL 공간형 단일 저장소로 운영하고, 대량 GPS 시계열·장소검색(ES/Redis)은 규모 확장 시 옵션이다. 관계 개요는 [ERD](./erd.md) 참조.
