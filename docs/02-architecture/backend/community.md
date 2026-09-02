# Community (커뮤니티) — 백엔드 구현 청사진

> Pawloop 백엔드(Spring Boot + MySQL 공간형)에서 **커뮤니티(게시판·댓글·반응)** 리소스를 개발자가 직접 구현할 때 읽는 청사진.
> ⚠️ 이 문서는 **구조·시그니처·매핑**만 제공한다. 메서드 바디(구현 코드)는 포함하지 않는다 — 개발자가 직접 작성한다.
>
> 참조 계약: [`openapi.yaml`](../../04-api/openapi.yaml) `/api/community/**` · 데이터 모델: [`erd.md`](../../03-database/erd.md) · [`schema.md`](../../03-database/schema.md) `post`/`comment`/`reaction`
> 컨벤션 출처: `backend/.../social/**` (record DTO, `ResponseEntity<?>`, JWT 추출), `.../user/controller/AuthController.java`, `.../OAuth/jwt/JWTProvider.java`

> [!IMPORTANT]
> **이 청사진은 2026-09-02 에 ADR-0016·ADR-0017 로 맞췄습니다.** 바뀐 것 셋입니다.
>
> | | |
> |---|---|
> | 장소 식별자 | `placeId` → **`contentId`** ([ADR-0017](../../99-decisions/decision-log.md#adr-0017--계약이-지키는-여섯-규약--이름을-손으로-적는-대신-전체를-도는-검사로-잠근다)). `Place.contentId` 와 같은 키입니다 |
> | 반응 | 단수 토글 → **복수 + 멱등 `POST`/`DELETE .../reactions/{type}`** ([ADR-0016](../../99-decisions/decision-log.md#adr-0016--커뮤니티-착수-전-결정-셋--신고는-미루고-반응은-복수로-열고-게스트-읽기는-메서드-축으로-연다) 결정 2) |
> | 게스트 읽기 | `security: []` → **인증 선택**, 서버는 **메서드 축 한 줄** (ADR-0016 결정 3) |
>
> DB 컬럼 이름(`post.place_id`)은 그대로입니다 — 계약의 필드 이름과 컬럼 이름은 다를 수 있습니다.
>
> 작성자 표현도 바뀌었습니다 — `Post.author`·`Comment.author` 는 이제 공통 `PersonRef`
> (`userId`+`nickname`)를 `$ref` 합니다. 특히 `Comment.author` 에는 **식별자가 아예 없었고**,
> 그래서 "내 댓글인가" 판별·차단이 계약상 불가능했습니다(ADR-0017 규약 5).

---

## 1. 개요

| 항목 | 내용 |
| --- | --- |
| 책임 | 커뮤니티 게시글 목록/작성/상세, 댓글 목록/작성, 게시글 반응(help/cute/empathy) 토글. |
| 관련 테이블 | `post`(글), `comment`(댓글), `reaction`(반응). 읽기 조인: `users`(작성자 닉네임), `place`(태그 장소, nullable FK). |
| 재사용 후보 | 기존 `social` 패키지의 `EmotionCard/CardReaction/CardComment` 구조가 거의 동일 → **패턴을 그대로 복제/개편**한다. 특히 (a) 반응 저장/삭제 로직(`SocialService.toggleReaction` — **토글이 아니라 멱등 add/remove 로 나눠 쓴다**, ADR-0016 결정 2), (b) 반응/댓글 수 N+1 방지 배치 집계(`findByCardIdIn`, `countByCardIdInGroupBy`), (c) `ReactionSummary`(reactions map + mine)는 social의 `{reactions, myReactions}` 개편판이다. |
| 기존과 차이 | ① 반응 타입이 `SAME/CHEER/CALM`(social) → `help/cute/empathy`(community). ② `ReactionSummary.mine`은 **배열 또는 `null`** 이다 — 셋을 동시에 누를 수 있다(ADR-0016 결정 2). `null` 은 비인증, `[]` 는 로그인했는데 아무것도 안 누른 것이다. social 의 `myReactions`(리스트)와 **같은 카디널리티**다. ③ 목록이 **커서 페이지네이션**(`items`/`nextCursor`/`hasMore`)이다(social은 limit-only). ④ `board` enum·장소 참조(`contentId`) nullable FK 존재. |
| 인증 정책 | 읽기(GET 목록/상세/댓글목록)는 **인증 선택**(`security: [{}, {bearerAuth: []}]`) — 토큰이 있으면 `reactions.mine` 이 채워진다. 쓰기(글/댓글 작성, 반응)는 **인증 필요**. `SecurityConfig` 에서 **메서드 축 한 줄**로 GET 셋만 열고 와일드카드는 쓰지 않는다(ADR-0016 결정 3). social 은 전부 authenticated 였다 — 주의. |

---

## 2. Controller

**클래스:** `CommunityController` — `@RestController` + `@RequestMapping("/api/community")`
(social `SocialController` 스타일: 생성자 주입 `CommunityService`/`JWTProvider`/`UserService`, `private User requireUser(HttpServletRequest)`로 JWT subject(email)→User 추출. 읽기 엔드포인트는 requireUser 호출 안 함.)

| # | HTTP · 경로 | 메서드 시그니처 (파라미터 타입) | 반환 DTO | 인증 | openapi paths |
| --- | --- | --- | --- | --- | --- |
| 1 | `GET /api/community/posts` | `feed(@RequestParam(required=false) String board, @RequestParam(required=false) String cursor, @RequestParam(defaultValue="20") Integer limit, HttpServletRequest req)` | `PostPageDto` (`Page` + `items: List<PostDto>`) | ✕ | `/api/community/posts` GET |
| 2 | `POST /api/community/posts` | `create(@RequestBody PostRequest body, HttpServletRequest req)` | `PostDto` (201) | ✔ | `/api/community/posts` POST |
| 3 | `GET /api/community/posts/{postId}` | `detail(@PathVariable Long postId, HttpServletRequest req)` | `PostDto` | ✕ | `/api/community/posts/{postId}` GET |
| 4 | `GET /api/community/posts/{postId}/comments` | `comments(@PathVariable Long postId)` | `List<CommentDto>` | ✕ | `.../comments` GET |
| 5 | `POST /api/community/posts/{postId}/comments` | `addComment(@PathVariable Long postId, @RequestBody CommentRequest body, HttpServletRequest req)` | `CommentDto` (201) | ✔ | `.../comments` POST |
| 6 | `POST /api/community/posts/{postId}/reactions/{type}` | `addReaction(@CurrentUser User me, @PathVariable Long postId, @PathVariable String type)` | `ReactionSummary` | ✔ | `.../reactions/{type}` POST |
| 7 | `DELETE /api/community/posts/{postId}/reactions/{type}` | `removeReaction(@CurrentUser User me, @PathVariable Long postId, @PathVariable String type)` | `ReactionSummary` | ✔ | `.../reactions/{type}` DELETE |

> **반환 규약(social 준수):** 메서드는 `ResponseEntity<?>` 반환. 정상은 `ResponseEntity.ok(dto)` / 작성은 `ResponseEntity.status(HttpStatus.CREATED).body(dto)`. 검증 실패는 `IllegalArgumentException` → `ResponseEntity.badRequest().body(Map.of("error", ...))`, not-found는 404 매핑, 그 외는 500. (읽기 시 `mine`은 인증 헤더가 있으면 채우고 없으면 null — requireUser 대신 optional 추출 헬퍼를 두는 것도 가능.)
> **인증 추출:** `@CurrentUser User me` 파라미터 하나로 받는다(#5). 인증 주체 해석은 `CurrentUserArgumentResolver` 한 곳뿐이고, 실패는 전부 **본문 없는 401** 이다 — 컨트롤러가 `Authorization` 헤더를 다시 읽거나 `findByEmail` 로 주체를 찾는 것은 금지이며 `AuthSubjectContractSpecTest` 가 소스 스캔으로 막는다. (#5 이전에는 컨트롤러마다 `requireUser` 헬퍼가 헤더를 다시 읽고 `findByEmail` 을 했다 — 그 헬퍼들은 전부 삭제됐다.)

---

## 3. DTO (record)

공통 `Error`, `Page`는 openapi `components/schemas`의 것을 참조만 한다(별도 정의 X). 요청 DTO는 social 스타일상 record 또는 lombok `@Getter @Setter @NoArgsConstructor` 클래스 중 하나 — social의 `CommentRequest`/`ReactionRequest`는 클래스였으므로 **요청은 클래스, 응답은 record** 로 통일 권장.

### 응답 record

**`PostDto`** ↔ openapi `Post`
| 필드 | 타입 | 비고 |
| --- | --- | --- |
| `id` | `Long` | |
| `author` | `AuthorDto` | 중첩(아래) |
| `board` | `String` | Board enum 문자열 |
| `loc` | `String` | nullable. 표시용 지역명(`place.name` 또는 사용자 입력) |
| `contentId` | `String` | nullable. 연결 장소 식별자. **`Place.contentId` 와 같은 키다**(ADR-0017). 2026-09 이전에는 `placeId` 였다 |
| `title` | `String` | |
| `body` | `String` | |
| `commentCount` | `int` | |
| `reactions` | `ReactionSummary` | 집계 + mine |
| `createdAt` | `String` | ISO-8601 (`DateTimeFormatter.ISO_LOCAL_DATE_TIME`) |

**`AuthorDto`** ↔ openapi `Post.author`
| 필드 | 타입 |
| --- | --- |
| `id` | `Long` |
| `nickname` | `String` |
> (댓글 author는 `nickname`만 필요 → 별도 `CommentAuthorDto` 또는 `AuthorDto` 재사용. openapi `Comment.author`는 nickname 단독.)

**`CommentDto`** ↔ openapi `Comment` (social의 것과 유사하나 author 구조 다름)
| 필드 | 타입 | 비고 |
| --- | --- | --- |
| `id` | `Long` | |
| `author` | `AuthorDto` | nickname만 채워도 무방 |
| `body` | `String` | |
| `createdAt` | `String` | ISO-8601 |

**`ReactionSummary`** ↔ openapi `ReactionSummary`
| 필드 | 타입 | 비고 |
| --- | --- | --- |
| `help` | `int` | 도움돼요 카운트 |
| `cute` | `int` | 귀여워요 카운트 |
| `empathy` | `int` | 공감 카운트 |
| `mine` | `List<String>` | nullable. 내가 누른 반응들. **`null`=비인증 / `[]`=로그인했는데 안 누름** (ADR-0016 결정 2). |

**`PostPageDto`** ↔ openapi `Page` allOf + `items: List<Post>`
| 필드 | 타입 | 비고 |
| --- | --- | --- |
| `items` | `List<PostDto>` | |
| `nextCursor` | `String` | nullable. 다음 페이지 커서(마지막 항목 기준 base64/id 인코딩) |
| `hasMore` | `boolean` | |

### 요청

**`PostRequest`** ↔ openapi `PostInput` (`@Getter @Setter @NoArgsConstructor` 클래스)
| 필드 | 타입 | 필수 | 비고 |
| --- | --- | --- | --- |
| `board` | `String` | ✔ | Board enum 값 검증 |
| `title` | `String` | ✔ | |
| `body` | `String` | ✔ | |
| `loc` | `String` | ✕ | |
| `contentId` | `String` | ✕ | 있으면 `place` 조회/링크 |

**`CommentRequest`** ↔ openapi `.../comments` POST body (social `CommentRequest` 재사용 가능하나 community용은 `body`만)
| 필드 | 타입 | 필수 |
| --- | --- | --- |
| `body` | `String` | ✔ |

**`ReactionRequest`** ↔ openapi `.../reactions` POST body
| 필드 | 타입 | 필수 | 비고 |
| --- | --- | --- | --- |
| `type` | `String` | ✔ | `help`/`cute`/`empathy` 중 하나 |

---

## 4. Service

**클래스:** `CommunityService` — `@Service @Transactional(readOnly = true)` (쓰기 메서드에 `@Transactional`). 생성자 주입: `PostRepository`, `CommentRepository`, `ReactionRepository`, `PlaceRepository`(loc/contentId 해석용), `UserRepository`(작성자 닉네임). social과 동일하게 상수(`VALID_REACTION_TYPES = {help,cute,empathy}`, `VALID_BOARDS`, `MAX_LIMIT`, `DEFAULT_LIMIT`)를 둔다.

| 메서드 시그니처 | 한 줄 책임 (무엇을) |
| --- | --- |
| `PostPageDto feed(String board, String cursor, Integer limit, Long currentUserId)` | board 필터 + 커서 이후 최신순 페이지 조회 → `items/nextCursor/hasMore` 구성. |
| `PostDto create(Long userId, PostRequest req)` | board·title·body 검증, `contentId` 해석, `post` 저장 후 DTO 반환. |
| `PostDto detail(Long postId, Long currentUserId)` | 단건 조회(+작성자·반응·댓글수), 없으면 not-found. |
| `List<CommentDto> comments(Long postId)` | 게시글 존재 검증 후 댓글 오래된 순 목록. |
| `CommentDto addComment(Long postId, Long userId, String body)` | 글 존재·body 검증 후 댓글 저장 → DTO. |
| `ReactionSummary addReaction(Long postId, Long userId, String type)` | type 검증 후 없으면 저장. **멱등** — 이미 있으면 아무것도 안 하고 최신 집계 반환. |
| `ReactionSummary removeReaction(Long postId, Long userId, String type)` | 있으면 삭제. **멱등** — 없어도 최신 집계 반환. |
| `private ReactionSummary summarize(Long postId, Long currentUserId)` (헬퍼) | 단건 글의 help/cute/empathy 카운트 + mine 계산. |
| `private Map<Long,ReactionSummary> summarizeBatch(List<Long> postIds, Long currentUserId)` (헬퍼) | 목록용 반응 배치 집계(N+1 방지). |
| `private Map<Long,Integer> commentCounts(List<Long> postIds)` (헬퍼) | 목록용 댓글 수 배치 집계(N+1 방지). |
| `private PostDto mapPost(Post, AuthorDto, ReactionSummary, int commentCount)` (헬퍼) | 엔티티 → PostDto 변환. |

> **커서 규약:** `cursor`는 이전 응답 `nextCursor`(예: 마지막 post id를 base64 인코딩). 서비스는 커서 디코드 → `id < cursorId` 조건으로 다음 페이지 조회, `limit+1`건 조회해 초과분 존재 여부로 `hasMore` 판단 후 잘라내고 마지막 항목 id로 `nextCursor` 생성. board가 null이면 전체.
> **반응 정책(ADR-0016 결정 2):** 유저당 글마다 **여러 type** 을 동시에 가질 수 있다 — 도움돼요·귀여워요·공감은 서로 배타적인 개념이 아니다. 스키마 유니크 `(post_id, user_id, type)` 이 그대로 불변식이고, **서비스가 따로 단일화하지 않는다.** 켜고 끄는 것은 `POST`/`DELETE .../reactions/{type}` 둘이고 **둘 다 멱등**이다. 2026-09 이전에는 `POST .../reactions` 하나가 토글이었는데, 요청에 의도가 없어 **재시도 한 번이 반응을 되돌렸다.**

---

## 5. Entity & Repository

패키지 `com.heattrip.heat_trip_backend.community.entity` / `.repository`. lombok `@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder`, `@PrePersist`로 `createdAt` 세팅(social 스타일). 테이블 정의는 [`schema.md`](../../03-database/schema.md) §6~8 기준.

### Entity: `Post` (`@Table(name="post")`)
| 엔티티 필드 | 컬럼 | 타입/제약 | 비고 |
| --- | --- | --- | --- |
| `id` | `id` | `Long` PK IDENTITY | |
| `userId` | `user_id` | `Long` NOT NULL | FK→`users.id`. (연관관계 대신 social처럼 id 스칼라 매핑 권장) |
| `board` | `board` | `String` NOT NULL | Board enum 문자열 저장 |
| `placeId` | `place_id` | `Long` NULL | **nullable FK**→`place.id`, ON DELETE SET NULL |
| `title` | `title` | `String` NOT NULL | |
| `body` | `body` | `String`(`TEXT`) NOT NULL | `@Column(columnDefinition="TEXT")` |
| `createdAt` | `created_at` | `LocalDateTime` NOT NULL, updatable=false | `@PrePersist` |

### Entity: `Comment` (`@Table(name="comment")`)
| 필드 | 컬럼 | 타입/제약 |
| --- | --- | --- |
| `id` | `id` | `Long` PK |
| `postId` | `post_id` | `Long` NOT NULL, FK→`post.id` |
| `userId` | `user_id` | `Long` NOT NULL, FK→`users.id` |
| `body` | `body` | `String`(`TEXT`) NOT NULL |
| `createdAt` | `created_at` | `LocalDateTime` NOT NULL, `@PrePersist` |

### Entity: `Reaction` (`@Table(name="reaction", uniqueConstraints=@UniqueConstraint(name="uq_reaction", columnNames={"post_id","user_id","type"}))`)
| 필드 | 컬럼 | 타입/제약 |
| --- | --- | --- |
| `id` | `id` | `Long` PK |
| `postId` | `post_id` | `Long` NOT NULL, FK→`post.id` |
| `userId` | `user_id` | `Long` NOT NULL, FK→`users.id` |
| `type` | `type` | `String(10)` NOT NULL, CHECK in(help,cute,empathy) |
| `createdAt` | `created_at` | `LocalDateTime` NOT NULL, `@PrePersist` |

### 인덱스 (schema.md와 일치, **SPATIAL 없음** — 커뮤니티는 공간 컬럼 미사용)
| 테이블 | 인덱스 | 종류 | 용도 |
| --- | --- | --- | --- |
| `post` | `idx_post_board(board, created_at)` | 보조 | 게시판별 최신순 커서 페이징 |
| `post` | `idx_post_user(user_id)` / `idx_post_place(place_id)` | 보조 | 작성자·장소 조인 |
| `comment` | `idx_comment_post(post_id, created_at)` | 보조 | 글별 댓글 |
| `reaction` | `uq_reaction(post_id, user_id, type)` | UNIQUE | 중복 반응 방지 |

### Repository (Spring Data `JpaRepository`)

**`PostRepository extends JpaRepository<Post, Long>`**
| 메서드 시그니처 | 용도 |
| --- | --- |
| `List<Post> findAllByOrderByIdDesc(Pageable pageable)` | 전체 첫 페이지(커서 없음) |
| `List<Post> findByBoardOrderByIdDesc(String board, Pageable pageable)` | board 필터 첫 페이지 |
| `List<Post> findByIdLessThanOrderByIdDesc(Long cursorId, Pageable pageable)` | 전체 커서 이후 페이지 |
| `List<Post> findByBoardAndIdLessThanOrderByIdDesc(String board, Long cursorId, Pageable pageable)` | board+커서 페이지 |
> (파생 쿼리로 충분 — 공간/네이티브 쿼리 불필요. `limit+1` 조회로 hasMore 판단.)

**`CommentRepository extends JpaRepository<Comment, Long>`**
| 메서드 | 용도 |
| --- | --- |
| `List<Comment> findByPostIdOrderByIdAsc(Long postId)` | 글별 댓글(오래된 순) |
| `long countByPostId(Long postId)` | 단건 댓글 수 |
| `@Query("select c.postId, count(c) from Comment c where c.postId in :ids group by c.postId") List<Object[]> countByPostIdInGroupBy(@Param("ids") List<Long> ids)` | 목록용 배치 집계(N+1 방지) |

**`ReactionRepository extends JpaRepository<Reaction, Long>`**
| 메서드 | 용도 |
| --- | --- |
| `List<Reaction> findByPostId(Long postId)` | 단건 집계/mine |
| `List<Reaction> findByPostIdIn(List<Long> postIds)` | 목록용 배치 집계 |
| `List<Reaction> findByPostIdAndUserId(Long postId, Long userId)` | `mine` 배열을 채운다(복수다 — ADR-0016 결정 2) |
| `Optional<Reaction> findByPostIdAndUserIdAndType(Long postId, Long userId, String type)` | 멱등 판정 — 이미 있는지 본다 |

---

## 6. 구현 노트 (함정 위주)

- **인증 분기(읽기 vs 쓰기) — ADR-0016 결정 3:** GET 셋은 계약이 `security: [{}, {bearerAuth: []}]`(**인증 선택**)이다. `security: []` 가 아니다 — 그것은 인증을 계약에서 **제거**해 `mine` 을 영원히 `null` 로 만든다(ADR-0017 규약 6이 뒤집었다).
  서버는 **같은 체인에 메서드 축 한 줄**로 연다. `.requestMatchers(HttpMethod.GET, "/api/community/posts", "/api/community/posts/*", "/api/community/posts/*/comments").permitAll()` 을 `anyRequest().authenticated()` **앞**에 둔다.
  **와일드카드(`/api/community/**`)는 쓰지 않는다** — 같은 경로의 `POST` 까지 열린다. `/api/explore/**` 가 그 반례다(그 아래 `POST .../feedback` 이 토큰 없이 행을 만든다).
  그리고 **rate limit 규칙을 함께 붙인다** — 표에 없는 경로는 한도가 0 이 아니라 **무한**이고, 지금은 `authenticated` 가 방어선인데 게스트에 열면 그것이 사라진다.
- **JWT 추출:** subject 는 **`users.id`** 다(#5 — 예전 서술의 email 이 아니다). `@CurrentUser User me` 파라미터 하나로 받는다(#5). 인증 주체 해석은 `CurrentUserArgumentResolver` 한 곳뿐이고, 실패는 전부 **본문 없는 401** 이다 — 컨트롤러가 `Authorization` 헤더를 다시 읽거나 `findByEmail` 로 주체를 찾는 것은 금지이며 `AuthSubjectContractSpecTest` 가 소스 스캔으로 막는다. 읽기 엔드포인트의 `mine` 처럼 **인증이 선택인 경로**는 컨트롤러 파라미터로 표현하지 않는다 — 그 결정은 `SecurityConfig` 가 한다(#23). **`@CurrentUser` 는 그대로 둔다**(실패를 전부 401 로 만드는 것이 설계다). 주체는 **컨트롤러 밖**에서 읽는다 — 필터가 넣는 `AuthenticatedUser` principal 이 이미 "없으면 없는 대로" 이고, 토큰이 없으면 `SecurityContext` 가 비어 있을 뿐이다. **새 애노테이션도 새 리졸버도 만들지 않는다**(ADR-0016 결정 3).
- **반응은 복수다(ADR-0016 결정 2):** 스키마 유니크 `(post, user, type)` 이 그대로 불변식이고 **서비스가 단일화하지 않는다.** social 의 `myReactions`(리스트) 로직이 여기서는 **맞는 모양**이다 — 복붙하면 안 되는 것은 반응 타입 이름(`SAME/CHEER/CALM` → `help/cute/empathy`)뿐이다.
- **멱등 트랜잭션:** `addReaction`·`removeReaction` 은 삽입/삭제가 있으므로 `@Transactional`(쓰기). **둘 다 멱등이라 재시도가 안전하다.** 동시성으로 유니크 제약이 깨지면 그것은 "이미 눌렀다" 와 같은 뜻이므로 삼키고 최신 집계를 반환한다.
- **커서 페이지네이션:** `nextCursor`는 마지막 항목 `id`를 base64 등으로 인코딩(openapi 예 `eyJpZCI6MTIzfQ==`). `limit`은 기본 20·최대 100(`components/parameters/Limit`). `limit+1`건 조회 → 초과 시 `hasMore=true`, 초과분 잘라내고 마지막 id로 커서 생성. 커서 디코드 실패는 400.
- **장소 참조는 `contentId` 다(ADR-0017):** openapi `Post.contentId` 는 **string** 이고 `Place.contentId` 와 같은 키다. 2026-09 이전에는 `placeId` 였다. DB `post.place_id` 가 **BIGINT FK** 라면 저장할 때 `place` 조회로 해석해 매핑하고 응답에서 다시 문자열로 돌린다. 존재하지 않는 장소면 링크 없이 저장한다(FK 는 `ON DELETE SET NULL`). `loc` 은 표시용 문자열이다.
- **N+1 방지:** 목록(feed)은 social의 배치 집계 패턴을 그대로 이식 — 페이지 내 postIds로 `findByPostIdIn`(반응)·`countByPostIdInGroupBy`(댓글)·작성자 닉네임 배치 조회 후 메모리에서 조립. 단건 루프 쿼리 금지.
- **board 검증:** Board enum은 한글(`산책로 후기`/`동반장소`/`건강·병원`/`자유`/`자랑`). 공백/중점(·) 포함 문자열이므로 서비스 상수 `Set`으로 정확히 검증(오타 시 400). DB `board VARCHAR(20)` + `utf8mb4`.
- **공간/좌표 무관:** 이 리소스는 `POINT`/`LINESTRING`, `ST_Distance_Sphere`, EPSG:5174→WGS84 변환과 **무관**하다(그건 Places/Walks 담당). 커뮤니티에 공간 쿼리를 넣지 말 것.
- **외부 API 없음:** community는 공공데이터 프록시/캐싱(KTO·LOCALDATA)과 무관 — `TourApiClient`/`WebClientConfig` 패턴 불필요. 순수 RDB CRUD.
- **에러 형식:** 검증 실패는 `IllegalArgumentException`→`Map.of("error", msg)` 400(social 방식) 또는 openapi `Error` 스키마(`{error:{code,message,traceId}}`)에 맞춘 공통 핸들러 사용. 프로젝트에 `observability/error` 글로벌 핸들러가 있으면 그쪽 포맷을 우선.

완료: C:/Users/mm206/git_projects/heattrip/docs/02-architecture/backend/community.md
