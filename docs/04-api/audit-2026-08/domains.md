# 2부 · Dogs · Places · Walks · Bookmarks · Community · Groups

[← 인덱스](./README.md) · 관련 이슈 [#24](https://github.com/sanghyunbang/heattrip/issues/24)

---

## Bookmarks — 6건

### `HIGH` 장소 식별자 이름과 모양이 경로마다 다르다. 장소 엔티티의 키는 contentId(문자열)인데 북마크는 placeId 라는 다른 이름을 쓴다. 게다가 Place.source 가 kto/vet/shop/trail 4개 레이어이므로 KTO contentId 단독으로는 레이어 간 고유성이 보장되지 않는데, 북마크 키에는 source 가 없다. 프론트가 무엇을 보내야 하는지(contentId? 레이어 접두사 붙인 합성키?), 백엔드가 무엇을 PK 로 잡을지가 계약에서 결정되지 않는다.

**근거**

832행 "contentId: { type: string, example: \"2733967\" }", 834행 "source: { type: string, enum: [kto, vet, shop, trail], example: kto }" vs 473-475행 "required: [placeId]\nproperties:\n  placeId: { type: string }", 486-489행 "- name: placeId\n  in: path\n  required: true\n  schema: { type: string }"

**수정**

이름을 contentId 로 통일하고(또는 Place 쪽을 placeId 로 리네임), 북마크 키를 {source, contentId} 복합키로 정의한다. POST 바디와 경로 파라미터 모두 source 를 포함하고, PlaceRef 같은 공통 스키마로 뽑는다.

### `MEDIUM` GET /api/bookmarks 가 전역 페이지네이션 표준을 위반한다. info.description 은 목록을 커서 페이지네이션(items/nextCursor/hasMore)으로 선언했고 Walks 목록·커뮤니티 목록·그룹 메시지는 Page 를 allOf 로 쓰는데, 북마크 목록만 벌거벗은 배열이고 cursor/limit 파라미터조차 없다. 사용자가 계속 쌓는 무한 증가 목록이라 나중에 페이지네이션을 넣으면 응답 모양이 배열→객체로 바뀌는 파괴적 변경이 된다.

**근거**

14행 "- 목록은 커서 페이지네이션(`items`/`nextCursor`/`hasMore`)." vs 452-462행 "get: ... responses: '200': ... schema:\n  type: array\n  items: { $ref: '#/components/schemas/Place' }" (parameters 절 자체가 없음). 대조 272-284행(walks) 및 348-360행(posts)의 "allOf: - $ref: '#/components/schemas/Page'"

**수정**

GET /api/bookmarks 에 Cursor/Limit 파라미터를 추가하고 응답을 Page allOf + items: Bookmark 형태로 바꾼다.

### `MEDIUM` 북마크 엔티티 스키마 자체가 없다. 목록이 Place 를 그대로 돌려주므로 '언제 저장했는지'(bookmarkedAt/createdAt) 같은 북마크 고유 속성이 계약 어디에도 존재하지 않는다. 저장순 정렬·최근 저장 표시·중복 판정 시점 같은 기본 동작의 기준 필드가 없어 정렬 순서를 서버가 임의로 정하게 된다.

**근거**

460-462행 "schema:\n  type: array\n  items: { $ref: '#/components/schemas/Place' }" — components.schemas 목록(764-1056행)에 Bookmark 스키마 없음(863 Walk, 828 Place 등만 존재). 828-842행 Place 에도 저장 시각 필드 없음.

**수정**

Bookmark 스키마(예: { place: Place, createdAt: date-time })를 신설해 목록 items 로 쓰고, 정렬 기준(createdAt desc)을 오퍼레이션 description 에 명시한다.

### `MEDIUM` 조회 컨텍스트 속성이 엔티티 스키마에 박혀 있어 북마크 응답으로 새어 나온다. Place.distM 은 '조회 기준점으로부터 거리'로 /api/places/nearby 전용 속성인데 Place 엔티티에 정의돼 있고, GET /api/bookmarks 는 그 Place 를 그대로 반환한다. 기준 좌표가 없는 북마크 응답에서 distM 이 무엇이어야 하는지(null? 0? 생략?) 계약이 정하지 않는다.

**근거**

842행 "distM: { type: number, format: double, description: 조회 기준점으로부터 거리(m), example: 320 }" (Place 스키마 828행 소속) + 462행 "items: { $ref: '#/components/schemas/Place' }" (북마크 목록). nearby 전용 기준 좌표는 205-215행의 lat/lng 쿼리 파라미터에만 존재.

**수정**

distM 을 Place 에서 빼고 nearby 응답 전용 래퍼(PlaceWithDistance = allOf[Place, {distM}])로 분리하거나, 최소한 '기준점 없는 응답에서는 생략된다'를 description 에 명시한다.

### `MEDIUM` 생성 응답 본문 규약이 다른 생성 오퍼레이션과 불일치한다. POST /api/bookmarks 는 201 에 본문도 Location 헤더도 없다. 같은 문서의 다른 모든 201 은 생성된 리소스를 반환한다. 또 요청 검증 실패(400)와 존재하지 않는 placeId(404) 응답이 선언돼 있지 않아, 아무 문자열이나 보내도 되는지가 계약상 불명이다.

**근거**

477행 "'201': { description: 추가됨 }" (content 없음). 대조: 155-159행(dogs), 295-299행(walks), 370-374행(posts), 420-424행(comments), 596-600행(care log)은 모두 "'201': ... schema: { $ref: ... }". 400 선언 사례: 160행, 601행, 650행.

**수정**

201 에 생성된 Bookmark 본문을 넣고 Location 헤더를 선언한다. '400': ValidationError, '404': NotFound(미존재 장소)를 추가한다.

### `MEDIUM` 삭제 규약이 반쪽이다. DELETE /api/bookmarks/{placeId} 에 404 가 없고 멱등성 규약도 없다. POST 는 중복을 409 로 명시했는데(478행) DELETE 는 '없는 북마크 삭제'가 204 인지 404 인지 정하지 않는다. 북마크는 UI 상 토글이라 이 케이스가 실제로 자주 발생하며, 백엔드가 404 를 던지면 프론트 토글이 에러 토스트를 띄우는 식으로 갈린다.

**근거**

490-492행 "responses:\n  '204': { description: 삭제됨 }\n  '401': { $ref: '#/components/responses/Unauthorized' }" vs 478행 "'409': { $ref: '#/components/responses/Conflict' }"

**수정**

'404': NotFound 를 추가하거나, description 에 '멱등 — 없어도 204' 를 명시해 한쪽으로 확정한다. POST 도 409 대신 멱등 200 으로 갈지 함께 결정한다.

---

## Community — 10건

### `HIGH` 공개 조회로 선언된 게시글 목록/상세가 '내가 누른 반응'이라는 사용자별 필드를 반환한다. security: [] 는 인증을 계약에서 제거하므로 서버는 토큰을 읽지 않아야 하고, 그러면 mine 은 영원히 null 이다. 프론트는 토큰을 붙여 보내고 mine 을 기대하는데 백엔드는 스펙대로 비인증 처리 → 반응 하이라이트가 서로 다르게 구현된다. 선택적 인증(security: [{}, {bearerAuth: []}])이어야 할 자리에 '인증 없음'이 박혀 있다.

**근거**

L340 `security: []` (GET /api/community/posts), L381 `security: []` (GET /posts/{postId}), L398 `security: []` (GET /comments) / L953 `reactions: { $ref: '#/components/schemas/ReactionSummary' }` / L936 `mine: { type: [string, "null"], description: "내가 누른 반응(없으면 null)" }`

**수정**

목록/상세/댓글 GET 을 `security: [{}, {bearerAuth: []}]` (optional auth)로 바꾸고, 비인증 시 mine 은 항상 null 임을 description 에 명시한다.

### `HIGH` '작성자(author)' 라는 같은 개념이 경로마다 세 가지 다른 모양으로 정의돼 있다. 특히 Comment.author 에는 사용자 식별자가 아예 없어 '내 댓글인지' 판별·프로필 이동·차단이 계약상 불가능하다. 키 이름도 id vs userId 로 갈린다.

**근거**

L942-946 Post.author `id: { type: integer, format: int64 }` + `nickname` / L970-973 Comment.author `properties:` 아래 `nickname: { type: string }` 뿐 / L1041-1045 ChatMessage.author `userId: { type: integer, format: int64 }` + `nickname` / L1017-1022 CareLog.doneBy 도 `userId`+`nickname`

**수정**

공용 `AuthorRef` 스키마(userId, nickname, avatarUrl?)를 만들어 Post.author / Comment.author / ChatMessage.author / CareLog.doneBy 가 모두 $ref 하도록 통일한다.

### `MEDIUM` 반응 엔드포인트가 '토글' 로만 정의돼 있어 요청이 비멱등이고 결과가 서버의 숨은 상태에 좌우된다. 요청 바디에 on/off(또는 DELETE)가 없어서 '취소' 를 명시할 방법이 없다 — 네트워크 재시도 한 번이면 사용자가 누른 반응이 조용히 취소된다. 오프라인 큐/재전송을 쓰는 모바일 계약으로는 위험하다.

**근거**

L430 `summary: 반응 토글(도움돼요/귀여워요/공감)` / L437-441 `type: object / required: [type] / properties: type: { $ref: '#/components/schemas/ReactionType' }` (on/off 플래그 없음) / L427-448 경로에 DELETE 오퍼레이션 없음

**수정**

PUT /reactions {type, active:boolean} 로 멱등화하거나, POST(추가) + DELETE /reactions/{type}(취소) 로 분리한다.

### `MEDIUM` ReactionSummary.mine 이 ReactionType 이 아니라 자유 문자열로 선언돼 enum 제약이 응답에서 사라진다. 요청은 enum 으로 검증되는데 응답은 아무 문자열이나 통과하므로, 생성 클라이언트는 요청은 enum 타입 / 응답은 String 이 되어 매핑 코드를 손으로 짜야 하고 오타 값이 계약상 유효해진다.

**근거**

L936 `mine: { type: [string, "null"], description: "내가 누른 반응(없으면 null)" }` 대비 L441 요청은 `type: { $ref: '#/components/schemas/ReactionType' }`, L925-927 `ReactionType … enum: [help, cute, empathy]`

**수정**

`mine: { oneOf: [ { $ref: '#/components/schemas/ReactionType' }, { type: "null" } ] }` 로 바꾼다.

### `MEDIUM` Board enum 값이 공백과 가운뎃점(·)을 포함한 한글 표시 문자열인데 이 값이 query 파라미터로 전송된다. 문서 내 다른 모든 enum 은 ASCII 키(help/cute/empathy, water/meal/walk, owner/member, small/medium/large)라 규약이 일관되지 않다. 퍼센트 인코딩·유니코드 정규화(NFC/NFD) 차이로 '건강·병원' 매칭이 클라이언트별로 깨질 수 있고, 게시판 이름을 바꾸면 곧바로 API 파괴적 변경이 되며 다국어도 불가능하다.

**근거**

L921-923 `Board: type: string / enum: ["산책로 후기", "동반장소", "건강·병원", "자유", "자랑"]` 를 L342-345 `- name: board / in: query / schema: { $ref: '#/components/schemas/Board' }` 및 L960 PostInput.board 에서 사용 / 대비 L927 `enum: [help, cute, empathy]`, L1006 `enum: [water, meal, walk, med, vet]`, L979 `enum: [owner, member]`

**수정**

Board 를 ASCII 키(trail_review, pet_friendly, health, free, brag)로 바꾸고, 한글 라벨은 description 이나 별도 라벨 맵으로 옮긴다.

### `MEDIUM` 사용자 생성 콘텐츠인데 수정·삭제·신고·차단 오퍼레이션이 계약에 전혀 없다. /api/community/** 는 GET/POST 만 존재해, 사용자가 자기 글/댓글을 지울 방법이 계약상 없다. 같은 문서의 Dogs 는 PATCH/DELETE 와 403(소유자 검증)을 갖추고 있어 내부 일관성도 깨진다. UGC 앱은 스토어 심사에서 신고/차단/삭제 부재가 반려 사유가 되므로 나중에 반드시 계약을 늘려야 한다.

**근거**

오퍼레이션 목록 기준 /api/community 하위는 L337(get) L361(post) L378(get) L395(get) L407(post) L428(post) 뿐 — delete/patch/put 없음 / 대비 L179 `patch:` L194 `delete:` (/api/dogs/{dogId}) 및 L192·L199 `'403': { $ref: '#/components/responses/Forbidden' }`

**수정**

DELETE/PATCH /api/community/posts/{postId}, DELETE /comments/{commentId} 를 403·404 와 함께 추가하고, POST /posts/{postId}/reports (또는 /reports)와 사용자 차단 계약을 정의한다.

### `LOW` 같은 '연결된 장소' 개념이 한 스키마 안에 두 가지 모양으로 들어가 있다. loc(자유 문자열)과 placeId(장소 참조)가 나란히 있으면서 우선순위·정합성 규칙이 없다 — placeId 가 있을 때 loc 을 무시할지, 서버가 장소 title 로 loc 을 채울지, 둘이 어긋나면 뭘 믿을지 계약이 침묵한다. 화면 표기가 클라이언트마다 갈린다.

**근거**

L948-949 `loc: { type: [string, "null"], example: "서울숲" }` / `placeId: { type: [string, "null"], description: 연결된 장소(선택) }` (PostInput 도 동일: L963-964)

**수정**

placeId 만 입력받고 응답에서는 `place: { contentId, title }` 요약 객체로 내려주도록 통일하거나, placeId 가 있으면 loc 은 서버가 채운다는 규칙을 description 에 명시한다.

### `LOW` POST 오퍼레이션의 400 선언이 들쭉날쭉하다. 필수 필드를 가진 요청 바디를 받으면서도 ValidationError 를 선언하지 않은 POST 가 4개나 있고, 같은 문서의 다른 POST 들은 400 을 선언한다. 검증 실패 응답 형태가 계약에 없으면 프론트가 에러 메시지 노출 분기를 못 만든다.

**근거**

400 없음: L369-375(POST /posts, 요청은 L958 `required: [board, title, body]`), L419-425(POST /comments, `required: [body]`), L442-448(POST /reactions, `required: [type]`), L534-542(POST /groups/join, `required: [inviteCode]`) / 400 있음: L517 `'400': { $ref: '#/components/responses/ValidationError' }` (POST /api/groups), L601(care-logs), L650(messages), L694(walk-notes), L160(dogs)

**수정**

위 4개 오퍼레이션에 `'400': { $ref: '#/components/responses/ValidationError' }` 를 추가한다.

### `LOW` 게시글에 이미지 필드가 전혀 없고 문서 어디에도 업로드(multipart) 계약이 없다. 같은 문서가 Place.image 와 Dog.avatarUrl 은 정의해 두었고 Board enum 에는 사진 중심 게시판('자랑','산책로 후기')을 넣어놓아, 계약이 스스로 전제한 사용 시나리오를 스키마가 지원하지 못한다. 이미지가 추가되는 순간 Post/PostInput 과 업로드 경로를 함께 늘려야 한다.

**근거**

L938-954 Post 와 L956-964 PostInput 에 이미지 관련 필드 없음 / 문서 전체에서 이미지 필드는 L816 `avatarUrl: { type: [string, "null"] }` 와 L841 `image: { type: [string, "null"], format: uri }` 뿐이고 multipart/form-data 는 0건 / L923 Board enum 에 `"자랑"`, `"산책로 후기"` 포함

**수정**

Post/PostInput 에 `images: [uri]`(최대 개수 명시)를 추가하고, POST /api/uploads (multipart/form-data → {url}) 같은 업로드 계약을 정의한다.

### `LOW` 목록 정렬 규약이 기계가 읽을 수 없는 형태이거나 아예 없다. 채팅은 '최신순' 이 설명문에만 있고, 게시글 목록은 정렬 언급도 sort 파라미터도 없다. 커서 페이지네이션은 정렬 기준이 고정돼야 커서가 의미를 갖는데 그 기준이 계약에 없어, 백엔드는 createdAt DESC, 프론트는 인기순 탭을 가정하는 식으로 갈릴 수 있다.

**근거**

L337-360 GET /api/community/posts 에 정렬 관련 파라미터·설명 없음(파라미터는 board/cursor/limit 뿐, L341-347) / 대비 L612 `그룹 채팅 메시지(최신순, 커서 페이지네이션).` — 설명문에만 존재

**수정**

게시글 목록에 기본 정렬(createdAt DESC)을 description 으로 못박고, 필요하면 `sort` enum(latest, popular) 파라미터를 계약에 추가한다.

---

## Community · Groups — 4건

### `HIGH` info.description 이 '목록은 커서 페이지네이션(items/nextCursor/hasMore)' 을 표준으로 선언했는데, 목록 엔드포인트 절반이 규약을 어기고 raw 배열을 반환한다. 댓글은 cursor/limit 파라미터조차 없어 인기글에서 무한정 커지는 배열을 통째로 내려받아야 하고, 페이지를 넘길 계약상 방법이 없다.

**근거**

L14 `- 목록은 커서 페이지네이션(\`items\`/\`nextCursor\`/\`hasMore\`).` 대비 → L404-406 GET /posts/{postId}/comments `schema: type: array / items: { $ref: '#/components/schemas/Comment' }` (L395-399 파라미터 없음) / L581-583 GET care-logs 배열 / L665-667 GET walk-notes 배열

**수정**

댓글은 Page + Cursor/Limit 로 전환한다. care-logs/walk-notes 처럼 본질적으로 유한한 목록은 배열로 두되, info.description 에 '고정 크기 목록은 배열' 이라는 예외 규칙을 명시해 규약을 문서화한다.

### `HIGH` Community/Groups 의 모든 응답 스키마에 required 가 하나도 없다. OpenAPI 에서 required 부재는 '전부 선택' 을 뜻하므로, 생성된 클라이언트는 id·createdAt·body 까지 전부 nullable 이 되고 프론트는 온통 null 체크를, 백엔드는 '당연히 항상 준다' 를 가정한다. Page 조차 nextCursor/hasMore 가 선택이라 서버가 hasMore 를 빼도 계약 위반이 아니다.

**근거**

L938-940 `Post: type: object / properties:` (required 없음), L966-968 Comment, L992-995 Group, L1009-1012 CareLog, L1035-1038 ChatMessage, L1049-1052 WalkNote, L930-932 ReactionSummary, L776-778 `Page: type: object / properties:` — 요청 스키마(L958 PostInput `required: [board, title, body]`, L1028 CareLogInput)에만 required 가 있다

**수정**

각 응답 스키마에 required 를 추가한다(예: Post [id, author, board, title, body, commentCount, reactions, createdAt], Page [items, hasMore], CareLog [id, dogId, type, doneBy, occurredAt]).

### `MEDIUM` 경로 파라미터(postId, groupId)를 받는 오퍼레이션 8개가 404 를 선언하지 않는다. 게시글 상세만 404 를 갖고 있어 같은 postId 를 쓰는 형제 오퍼레이션과 에러 계약이 갈린다. 더 큰 문제는 그룹 하위 리소스: 존재하지 않는 groupId 와 '멤버가 아닌 groupId' 를 각각 404 로 줄지 403 으로 줄지 규정이 없어(403 만 선언됨), 백엔드는 정보 은닉 목적으로 404 를, 프론트는 403 분기만 구현하기 쉽다.

**근거**

L390 GET /posts/{postId} 에만 `'404': { $ref: '#/components/responses/NotFound' }` / 404 없음: L399-406(comments GET), L419-425(comments POST), L442-448(reactions POST), L576-585(care-logs GET), L595-603(care-logs POST), L617-631(messages GET), L644-652(messages POST), L660-669·L686-696(walk-notes GET/PUT) — 모두 `'403'`/`'401'` 만 선언

**수정**

해당 오퍼레이션에 404 를 추가하고, '비멤버의 그룹 하위 리소스 접근은 403' 인지 '존재를 숨기려 404' 인지 Groups tag description 에 한 줄로 못박는다.

### `LOW` 페이지네이션 응답을 `allOf: [Page, {properties: {items: ...}}]` 로 조립했는데, allOf 는 덮어쓰기가 아니라 교집합이라 Page.items(`items: {}`)와 구체 타입이 동시에 적용된다. 스펙상 통과하긴 하지만 대다수 코드 생성기(openapi-generator, swagger-codegen 등)가 이 패턴에서 items 를 List<dynamic>/List<Object> 로 뽑아내 타입 안정성이 사라진다. 목록 화면 두 곳이 모두 이 패턴이다.

**근거**

L353-360 `allOf: - $ref: '#/components/schemas/Page' - type: object / properties: items: type: array / items: { $ref: '#/components/schemas/Post' }` / L622-629 messages 동일 패턴 / L776-781 `Page … items: type: array / items: {}`

**수정**

Page 에서 items 를 빼서 `PageMeta`(nextCursor,hasMore)로 만들고 PostPage/ChatMessagePage 를 명시 스키마로 정의하거나, 아예 allOf 없이 각 응답에 items+nextCursor+hasMore 를 직접 쓴다.

---

## Dogs — 7건

### `HIGH` PATCH /api/dogs/{dogId} 가 "부분 수정"이라고 명시해놓고 생성용 DogInput 을 그대로 재사용한다. DogInput 은 required:[name, size] 라서 계약대로면 부분 수정이 불가능하다(예: {"neutered":true} 만 보내면 400). 게다가 PATCH 의 requestBody 에는 required:true 가 없어 빈 본문도 합법이다(POST 는 150행에 required:true 가 있음). 프론트는 부분 전송, 백엔드는 전체 필수 검증으로 갈라진다.

**근거**

181행 `summary: 반려견 수정(부분)` / 182-185행 `requestBody:` 밑에 `required: true` 없음, `schema: { $ref: '#/components/schemas/DogInput' }` / 820행 `required: [name, size]`

**수정**

DogPatchInput(모든 필드 optional, minProperties:1)을 별도로 정의해 PATCH 에 연결하고, PATCH requestBody 에 `required: true` 를 추가한다.

### `HIGH` Dog/DogInput 에 반려동물 종(species) 축이 없다. 리소스명·스키마·사이즈 enum 이 전부 개 전용이라, 고양이/기타를 등록할 계약 경로가 없다. 이 문서는 스스로 "프론트가 실제로 필요로 하는 데이터를 기준으로" 작성했다고 선언했는데, 프론트 도메인 모델은 이미 dog/cat/other 3종을 가진다(app/lib/v2/domain/pet.dart:51-57 `enum PetSpecies { dog, cat, other }`).

**근거**

806-817행 Dog 속성에 species 없음(`name`/`breed`/`size`/`birth`/`ageMonths`/`neutered`/`avatarUrl`) / 818-826행 DogInput 도 동일 / 801-804행 `DogSize: enum [small, medium, large]` `description: 소형견/중형견/대형견` / 8-9행 `프론트가 실제로 필요로 하는 데이터를 기준으로 이 계약을 정의합니다`

**수정**

PetSpecies enum(dog/cat/other)을 추가해 Dog·DogInput 에 넣고, size 는 species=dog 일 때만 필수가 되도록 조건을 명시한다(또는 종 무관한 체급 값으로 재정의). 리소스명도 /api/pets 로의 리네임을 검토한다.

### `HIGH` Dog 엔티티에 소유/공유 축(ownerId, groupId)이 없어 "누가 이 개를 볼 수 있는가"가 계약상 정의되지 않는다. 가족 그룹 케어 기록은 dogId 를 담아 다른 구성원에게 전달되지만, 수신자가 그 dogId 를 Dog 로 해석할 방법이 계약에 없다(목록은 "내 반려견"만 반환). 더구나 PATCH/DELETE 는 403 을 선언해 소유자 검증이 있음을 암시하는데 GET 상세에는 403 이 없어, 남의 개 조회 허용 여부가 미정이다. 프론트와 백엔드가 서로 다른 가시성 규칙을 구현하게 된다.

**근거**

806-817행 Dog 속성에 ownerId/groupId 없음 / 136행 `summary: 내 반려견 목록` / 1014행 CareLog `dogId: { type: integer, format: int64 }`, 1015행 `groupId: ... 가족 그룹(개인 기록이면 null)` / 192행·199행 `'403': { $ref: '#/components/responses/Forbidden' }` (PATCH·DELETE) 대비 169-178행 GET 에는 403 없음

**수정**

Dog 에 ownerId(및 공유 범위 groupId 또는 sharedGroupIds)를 추가하고, GET /api/dogs 에 `scope=mine|group` 또는 `groupId` 필터를 정의한다. GET 상세에 403 을 추가하고 "같은 그룹 구성원은 조회 가능" 같은 규칙을 description 에 명문화한다.

### `MEDIUM` /api/dogs/{dogId} 세 오퍼레이션의 오류 응답 집합이 서로 다르고 구멍이 있다. 전역 security 로 인증이 강제되는데 GET/PATCH/DELETE 어디에도 401 이 없다(컬렉션 경로에는 있음). PATCH 에는 400 이 없고, DELETE 에는 404 가 없다(없는 개를 지우면 204? 404?). 프론트의 에러 분기와 백엔드 구현이 어긋난다.

**근거**

145행·161행 `'401': { $ref: '#/components/responses/Unauthorized' }` (컬렉션에는 있음) 대비 172-199행 GET/PATCH/DELETE 응답에 401 없음 / 186-193행 PATCH 응답은 `'200'`/`'403'`/`'404'` (400 없음) / 197-199행 DELETE 는 `'204': { description: 삭제됨 }` 과 `'403'` 뿐(404 없음)

**수정**

세 오퍼레이션 모두 401 추가, PATCH 에 400 추가, DELETE 에 404 추가. 항목 경로 수준의 공통 responses 를 정하고 전 오퍼레이션에 동일하게 적용한다.

### `MEDIUM` avatarUrl 은 응답에만 있고 입력 스키마에 대응 필드가 없으며, 이미지 업로드 엔드포인트도 계약에 없다. 프로필 사진을 설정할 계약 경로가 존재하지 않는 읽기 전용 필드다.

**근거**

816행 `avatarUrl: { type: [string, "null"] }` / 818-826행 DogInput 속성은 `name`/`breed`/`size`/`birth`/`neutered` 뿐

**수정**

DogInput 에 avatarUrl(또는 avatarFileId)을 추가하고, 필요하면 multipart 업로드 엔드포인트(POST /api/dogs/{dogId}/avatar)를 계약에 정의한다.

### `MEDIUM` 나이 표현이 읽기/쓰기 비대칭이라 라운드트립이 불가능하다. 쓰기는 birth(생년월일)만 받고 읽기는 ageMonths 를 파생 제공하는데, birth 를 모르고 개월수만 아는 클라이언트는 등록/수정이 불가능하다(프론트 편집 화면은 ageMonths 를 직접 입력받는다 — app/lib/v2/domain/pet.dart 의 DogProfile.ageMonths). 또한 birth 는 nullable 인데 birth 에서 계산되는 ageMonths 는 non-null 정수로 선언돼 있어 스키마 내부가 모순된다(birth=null 이면 ageMonths 는 무엇인가).

**근거**

813-814행 `birth: { type: [string, "null"], format: date, example: "2024-01-15" }` / `ageMonths: { type: integer, description: birth로부터 계산(응답 편의), example: 30 }` / 825행 DogInput 에는 `birth` 만 존재

**수정**

ageMonths 를 `type: [integer, "null"]` 로 바꾸고, DogInput 에 birth 대안으로 ageMonths 를 허용(oneOf)하거나 birth 를 필수로 만들어 한쪽으로 정리한다.

### `LOW` POST /api/dogs 가 201 을 반환하면서 Location 헤더를 선언하지 않는다. 생성된 리소스의 정식 URI 를 계약이 알려주지 않아, 클라이언트는 본문의 id 로 URL 을 직접 조립하는 관례에 의존하게 된다.

**근거**

155-159행 `'201':` `description: 등록됨` 아래 `content:` 만 있고 `headers:` 절 없음

**수정**

201 응답에 `headers: { Location: { schema: { type: string, format: uri-reference }, description: 생성된 반려견 URI } }` 를 추가한다.

---

## Dogs · Places — 2건

### `HIGH` info.description 이 목록 응답 표준을 커서 페이지네이션 봉투(items/nextCursor/hasMore)로 선언했는데, Dogs 목록과 Places 목록은 최상위가 그냥 배열이다. 같은 문서의 /api/walks 는 Page 를 allOf 로 붙여 봉투를 쓴다. 표준이 두 개 존재하므로 프론트 파서(List vs {items:[...]})와 백엔드 응답이 어긋난다.

**근거**

14행 `- 목록은 커서 페이지네이션(\`items\`/\`nextCursor\`/\`hasMore\`).` / 142-144행 `schema:` `type: array` `items: { $ref: '#/components/schemas/Dog' }` / 238-240행 `type: array` `items: { $ref: '#/components/schemas/Place' }` / 대조: 274-284행 `allOf: - $ref: '#/components/schemas/Page'`

**수정**

두 목록도 Page allOf 봉투로 통일하거나, info.description 에 "소량 고정 목록(내 반려견 등)은 배열 반환"이라는 예외를 명문화한다. 지금처럼 암묵적으로 두 방식이 공존해서는 안 된다. (같은 문제가 /api/bookmarks 460-462행, /api/groups/{groupId}/care-logs 581-583행에도 있음)

### `HIGH` 응답 엔티티 스키마에 required 가 하나도 없다. Dog, Place, PlaceDetail 모두 전 필드가 선택이라, 백엔드가 id·lat·lng·title 을 빼고 보내도 계약 위반이 아니다. design-first + Prism 목 + 코드젠 조합에서 이 누락은 치명적이다(목 서버는 필드를 생략할 수 있고, 생성된 Dart 모델은 모든 필드가 nullable 이 된다). 요청 스키마에는 required 가 있어(DogInput 820행) 읽기/쓰기 엄격도가 비대칭이다.

**근거**

806-808행 `Dog:` `type: object` `properties:` — required 절 없음 / 828-831행 `Place:` … required 절 없음 / 849-861행 `PlaceDetail: allOf:` 하위 object 에도 required 없음 / 대조 820행 `required: [name, size]`

**수정**

Dog 에 `required: [id, name, size]`, Place 에 `required: [contentId, title, source, lat, lng]` 를 추가한다. 항상 있는 필드와 없을 수 있는 필드를 구분해 명시한다.

---

## Groups — 9건

### `HIGH` '한 사용자가 그룹을 몇 개 가질 수 있는가' 가 계약 안에서 모순된다. /api/groups/me 는 단일 Group 을 반환하고 '없으면 404' 라고 해 1인 1그룹을 전제하는데, POST /api/groups 는 409 를 선언하지 않아 이미 그룹이 있는 사용자의 재생성이 성공인지 충돌인지 알 수 없다(join 만 409 를 선언). 게다가 GET /api/groups(목록)도 GET /api/groups/{groupId}도 없어, 다중 그룹으로 확장하면 경로 구조 자체가 깨진다.

**근거**

L544-556 `/api/groups/me` … L548 `속한 그룹이 없으면 404.` + L555 `'404': { $ref: '#/components/responses/NotFound' }` / L511-518 POST /api/groups 응답은 `'201'`,`'400'`,`'401'` 뿐(409 없음) / L541 join 에는 `'409': { $ref: '#/components/responses/Conflict' }` 존재

**수정**

1인 1그룹 규칙을 info 또는 Groups tag description 에 명문화하고 POST /api/groups 에 409 를 추가한다. 다중 그룹을 열어둘 거면 /api/groups/me 를 목록 반환으로 바꾸고 GET /api/groups/{groupId} 를 추가한다.

### `MEDIUM` 케어 기록을 남기는 계약만 있고 취소·수정 계약이 없다. 이 기능의 존재 이유가 '이중 급여 방지' 인데, 잘못 눌러 생긴 '밥 줌' 기록을 지울 수 없으면 가족은 오히려 밥을 굶기게 된다. care-logs 는 GET/POST 뿐이고 /api/groups/{groupId}/care-logs/{careLogId} 경로 자체가 없다.

**근거**

L558-603 `/api/groups/{groupId}/care-logs` 는 L561 `get:` 과 L586 `post:` 만 존재 / L499-501 문서가 목적을 명시 `가족 간 케어 공유로 이중 급여(밥 두 번)·산책 누락을 막는 기능의 시작점입니다.`

**수정**

DELETE(204) 와 PATCH(memo/occurredAt 수정) 를 갖는 /api/groups/{groupId}/care-logs/{careLogId} 를 추가하고, 본인 기록만 삭제 가능하면 403 을 함께 선언한다.

### `MEDIUM` group-scoped 경로에서 반환되는 엔티티인데 groupId 가 nullable 로 선언돼 있다. 계약상 GET /api/groups/{groupId}/care-logs 가 groupId: null 인 항목을 돌려줘도 유효하므로, 백엔드는 개인 기록을 섞어 내려주고 프론트는 groupId 로 필터링해 화면에서 사라지는 식으로 갈린다. 경로 스코프와 스키마 제약이 서로 모순된다.

**근거**

L1015 `groupId: { type: [integer, "null"], format: int64, description: 가족 그룹(개인 기록이면 null) }` 이 L558 `/api/groups/{groupId}/care-logs` 응답(L581-583)으로 사용됨 / 대비 L1040 ChatMessage `groupId: { type: integer, format: int64 }`, L1054 WalkNote 도 non-null

**수정**

그룹 경로 응답용으로는 groupId 를 non-null + required 로 고정하고, 개인 기록은 별도 경로(/api/dogs/{dogId}/care-logs)나 별도 스키마로 분리한다.

### `MEDIUM` 주의사항 PUT 의 입력과 출력 모양이 어긋난다. 응답은 id/createdAt 을 가진 WalkNote 객체 배열인데 입력은 평범한 문자열 배열이라, 전체 교체 때마다 모든 노트의 id 와 createdAt 이 소실·재생성된다(그러면 응답에 id 가 있을 이유도 사라진다). 동시성 제어(If-Match/version)도 없어 엄마와 아빠가 같은 화면을 열어두면 나중에 저장한 쪽이 상대 메모를 조용히 지운다. 개별 추가/삭제 경로도 없다.

**근거**

L678-685 요청 `required: [notes] / notes: type: array / items: { type: string }` vs L690-693 응답 `items: { $ref: '#/components/schemas/WalkNote' }` / L1049-1056 WalkNote 는 `id`,`groupId`,`createdAt` 보유 / L673 `그룹의 공유 메모를 통째로 교체합니다(간단한 MVP 규약).`

**수정**

POST/DELETE /api/groups/{groupId}/walk-notes/{noteId} 로 개별 CRUD 를 두거나, PUT 을 유지하려면 입력을 {id?, body} 객체 배열로 바꾸고 If-Match/updatedAt 기반 낙관적 잠금과 409 를 선언한다.

### `MEDIUM` 초대코드 수명주기 계약이 없다. 그룹 탈퇴, 멤버 추방, 그룹 삭제, 초대코드 재발급·만료 오퍼레이션이 전부 없어서 한 번 유출된 초대코드는 영구히 유효하고, 그 코드로 들어온 사람은 가족의 케어 기록·채팅에 무기한 접근한다(회수 수단이 계약에 존재하지 않음). Group 스키마에도 expiresAt 류 필드가 없다.

**근거**

Groups 하위 오퍼레이션은 L496(POST /api/groups), L521(POST /join), L545(GET /me), L561·586, L608·632, L657·670 뿐 — 탈퇴/추방/삭제 없음 / L992-1002 Group 에 `inviteCode: { type: string, example: "PAW-2K7Q" }` 만 있고 만료 필드 없음 / L524 `가족에게 받은 초대코드로 그룹에 \`member\` 역할로 참여합니다.`

**수정**

DELETE /api/groups/{groupId}/members/me(탈퇴), DELETE /members/{memberId}(owner 전용, 403), POST /api/groups/{groupId}/invite-code(재발급) 를 추가하고 Group 에 inviteCodeExpiresAt 을 넣는다.

### `MEDIUM` 케어 기록에 dogId 가 필수인데, 그룹 멤버가 그 dogId 를 알아낼 계약이 없다. Group 스키마에는 members 만 있고 공유 반려견 목록이 없으며, /api/dogs 는 '내 반려견 목록' 이라 초대받아 들어온 가족 구성원(반려견 소유자가 아님)은 빈 배열을 받는다. 핵심 플로우가 계약상 막혀 있다.

**근거**

L1026-1030 `CareLogInput … required: [dogId, type]` / L992-1002 Group 필드 `id,name,inviteCode,members,createdAt` (dogs 없음) / L134-136 `/api/dogs: get: … summary: 내 반려견 목록`

**수정**

Group 에 `dogs: [Dog]`(또는 dogIds)를 추가하거나 GET /api/groups/{groupId}/dogs 를 정의하고, /api/dogs 가 '내가 속한 그룹의 반려견 포함' 인지 여부를 description 에 명시한다.

### `MEDIUM` 시간대 규약이 단 한 엔드포인트의 자연어 설명에만 존재한다. '오늘(KST)' 은 care-logs description 에만 적혀 있고 info.description 에는 좌표·페이지네이션 규약만 있을 뿐 타임존 규약이 없다. 모든 date-time 필드의 오프셋 규칙(UTC Z 인지 +09:00 인지)도 미정이라, 백엔드가 UTC 기준으로 하루를 자르면 KST 00:00~09:00 의 케어 기록이 '어제' 로 밀려 오늘 화면에서 사라진다. 이중 급여 방지 기능에서 치명적인 경계 버그다.

**근거**

L564-566 `그룹의 케어 기록(…)을 조회합니다. 기본은 오늘(KST) —` , L570 `description: 조회 날짜(생략 시 오늘, KST)` / info.description L12-15 에는 인증·페이지네이션·좌표만 있고 타임존 항목 없음 / L1023 `occurredAt: { type: string, format: date-time }` (오프셋 규약 없음)

**수정**

info.description 에 '모든 date-time 은 RFC3339 오프셋 포함, 일자 경계는 Asia/Seoul' 을 표준으로 추가하고, date 파라미터에 예시 오프셋을 명시한다.

### `MEDIUM` 문서가 MVP 갱신 방식으로 폴링을 선언했는데, 그 폴링을 수행할 파라미터가 계약에 없다. 목록은 최신순 + cursor(=이전 응답의 nextCursor, 즉 과거로만 넘김)뿐이라 '마지막으로 본 메시지 이후의 새 메시지' 를 요청할 수단이 없다. 프론트는 1페이지 전체 재조회 후 로컬 diff 로, 백엔드는 since 파라미터를 임의 추가하는 식으로 갈릴 여지가 크다. 읽음 표시/안 읽은 수 계약도 없다.

**근거**

L611-613 `그룹 채팅 메시지(최신순, 커서 페이지네이션). MVP는 폴링으로 새 메시지를 확인하고, 실시간(WebSocket/STOMP)은 post-MVP로 확장합니다.` / L614-616 파라미터는 `Cursor`,`Limit` 뿐 / L714-717 `Cursor … description: 이전 응답의 nextCursor`

**수정**

`afterId`(또는 `since`) 쿼리 파라미터를 추가해 신규 메시지 델타 조회를 명시하고, 폴링 주기 권장값과 읽음 커서(lastReadMessageId)를 계약에 넣는다.

### `MEDIUM` CareType 이 닫힌 enum 이고 other/custom 탈출구가 없다. 배변·미용·이빨 닦기 같은 일상 케어를 표현할 방법이 없고, 값을 추가하는 순간 기존 생성 클라이언트에는 파괴적 변경이 된다(모르는 값 수신 시 파싱 실패). 자유 항목은 memo 로 밀어넣게 되는데 그러면 필터(type 쿼리)와 집계가 무의미해진다.

**근거**

L1004-1007 `CareType: type: string / enum: [water, meal, walk, med, vet] / description: 물 갈아주기/밥/산책/약/병원` / L572-575 이 값을 `type` 쿼리 필터로 사용

**수정**

`other` 값과 `label` 필드를 추가하거나, 미지의 값을 만나면 other 로 폴백하라는 규칙을 description 에 명시한다(확장 가능 enum 규약).

---

## Places — 9건

### `HIGH` 장소 식별자가 경로마다 이름이 다르다. 조회는 contentId, 북마크는 placeId, 게시글 연결도 placeId 다. 같은 값을 가리키는데 이름이 두 개라 프론트/백엔드가 매핑 규칙을 각자 정하게 된다.

**근거**

243행 `/api/places/{contentId}:` · 249행 `- name: contentId` · 832행 `contentId: { type: string, example: "2733967" }` / 473-475행 `required: [placeId]` `placeId: { type: string }` · 481행 `/api/bookmarks/{placeId}:` / 949행 `placeId: { type: [string, "null"], description: 연결된 장소(선택) }` · 964행 `placeId: { type: string }`

**수정**

하나로 통일한다(외부 KTO 의존을 이름에 노출하지 않는 placeId 권장). Place 스키마에도 `placeId` 를 두고 KTO 원본키는 별도 필드(예: ktoContentId)로 분리한다.

### `HIGH` Place.source 는 kto/vet/shop/trail 4종인데 식별자는 contentId(KTO 숫자 문자열) 단일 필드뿐이고, 상세 경로 /api/places/{contentId} 에도 source 를 넘길 방법이 없다. vet/shop/trail 항목의 id 채번 규칙(접두어 여부, LOCALDATA 관리번호 사용 여부)이 계약에 없어 소스 간 id 충돌이 가능하고, 상세 조회 시 백엔드가 어느 소스를 조회할지 결정할 근거가 없다. PlaceDetail 은 KTO detailPetTour2 전용으로 서술돼 있어 vet/shop/trail 상세의 계약이 아예 비어 있다.

**근거**

834행 `source: { type: string, enum: [kto, vet, shop, trail], example: kto }` / 832행 `contentId: { type: string, example: "2733967" }` / 243-252행 경로 파라미터는 `contentId` 하나뿐(`schema: { type: string }`) / 857행 `description: 반려동물 동반 상세(KTO detailPetTour2 — 대부분 자유텍스트)`

**수정**

복합키를 명문화한다. `{source}:{externalId}` 형태의 불투명 id 규칙을 description 에 정의하거나, 상세 경로를 /api/places/{source}/{externalId} 로 바꾼다. 그리고 vet/shop/trail 일 때 PlaceDetail.petInfo 가 null 임을 스키마에 표기한다.

### `HIGH` category 필터가 서로 직교하는 두 축(데이터 소스 vs KTO 콘텐츠타입)을 하나의 단일값 enum 으로 합쳐놨다. 그 결과 (1) '음식점 + 동물병원' 같은 다중 선택이 불가능하고, (2) source 만으로 거르는 것이 불가능하며, (3) 엔티티에는 category 와 contentTypeId 가 중복 존재하는데 source 가 vet/shop/trail 이면 contentTypeId 에 넣을 값이 없음에도 nullable 도 optional 표시도 없다. 백엔드는 빈 문자열/null/생략 중 아무거나 고를 수 있다.

**근거**

224-229행 `- name: category` … `type: string` `enum: ['12', '14', '28', '32', '38', '39', 'vet', 'shop', 'trail']` / 835-836행 `category: { $ref: '#/components/schemas/PlaceCategory' }` `contentTypeId: { type: string, example: "12", description: "KTO 콘텐츠타입(...)" }` / 844-847행 PlaceCategory 가 같은 enum 을 인라인 중복 정의

**수정**

필터를 `source`(배열)와 `contentTypeId`(배열) 두 파라미터로 분리하고 style: form/explode 를 명시한다. 엔티티에서는 category 를 제거하거나 contentTypeId 를 `type: [string, "null"]` 로 바꿔 비KTO 소스에서 null 임을 못박는다. 또한 query enum 은 인라인 중복 대신 `$ref: '#/components/schemas/PlaceCategory'` 로 참조해 드리프트를 막는다.

### `MEDIUM` PlaceDetail 이 상세 화면을 채우기에 턱없이 부족하다. Place 상속분 외에 추가되는 것은 overview 와 petInfo 3개 자유텍스트뿐이다. 이미지 갤러리(Place.image 는 단수 1장), 운영시간/휴무일, 주차, 홈페이지/예약, 편의시설 같은 상세 필드가 계약에 없다. 계약 자신도 "현재 프론트는 KTO 직접호출"이라고 적고 있어, 이 상태로 백엔드가 구현하면 프론트는 계속 KTO 를 직접 부르게 된다(프론트 도메인 엔티티는 images/hours/amenities 를 이미 가짐 — app/lib/features/explore/domain/entity_detail/place_detail.dart).

**근거**

849-861행 `PlaceDetail: allOf: - $ref: '#/components/schemas/Place'` + `overview` + `petInfo{acmpyPsblCpam, acmpyNeedMtr, etcAcmpyInfo}` 가 전부 / 841행 `image: { type: [string, "null"], format: uri }` (단수) / 209행 `(현재 프론트는 KTO 직접호출 + 병원/펫샵/산책로 더미)`

**수정**

PlaceDetail 에 images(array), hours(운영시간/휴무일), homepage, parking, amenities 를 추가한다. 값이 없는 소스에서는 빈 배열/null 임을 명시한다.

### `MEDIUM` 동일한 외부 쿼터(KTO)에 의존하는데 목록에만 429 가 있고 상세에는 없다. RateLimited 응답 설명이 "KTO 1000콜/일"이라 상세 조회도 동일 한도에 걸리는데, 프론트는 상세 화면에서 429 처리 코드를 만들 근거가 없다.

**근거**

241행 `'429': { $ref: '#/components/responses/RateLimited' }` (nearby) / 253-259행 상세 응답은 `'200'` 과 `'404'` 뿐 / 759행 `description: "외부 데이터 한도 초과(예: KTO 1000콜/일)"`

**수정**

/api/places/{contentId} 에 `'429': { $ref: '#/components/responses/RateLimited' }` 를 추가한다.

### `MEDIUM` /api/places/nearby 는 필수 좌표를 받으면서 400(ValidationError) 응답이 없고, 좌표·반경·개수에 범위 제약도 없다. lat 에 999, radius 에 -1 을 보내면 계약상 어떤 응답이 정상인지 정의되지 않아 백엔드마다 다르게 처리한다.

**근거**

212-219행 `- name: lat` `required: true` `schema: { type: number, format: double, example: 37.5665 }` (minimum/maximum 없음), lng 동일 / 223행 `schema: { type: integer, default: 8000, maximum: 20000 }` (minimum 없음) / 232행 `schema: { type: integer, default: 80, maximum: 200 }` (minimum 없음) / 233-241행 응답에 400 없음

**수정**

lat 에 minimum:-90/maximum:90, lng 에 -180/180, radius·limit 에 minimum:1 을 넣고 `'400': { $ref: '#/components/responses/ValidationError' }` 를 추가한다.

### `MEDIUM` nearby 의 limit 이 공통 파라미터 Limit 과 기본값·상한이 다른데 별도 이름 없이 인라인 정의돼 있고, 커서 파라미터가 없어 잘린 결과를 더 가져올 방법이 계약에 없다. 같은 이름의 파라미터가 문서 안에서 두 가지 의미(20/100 vs 80/200)를 가진다.

**근거**

230-232행 `- name: limit` `schema: { type: integer, default: 80, maximum: 200 }` / 716-719행 `Limit:` `name: limit` `schema: { type: integer, default: 20, maximum: 100 }` / 711-715행 `Cursor` 파라미터가 nearby 에는 미사용

**수정**

지도 조회용임을 이름으로 드러내거나(`maxResults`), 공통 Limit 을 $ref 로 쓰고 상한 차이를 description 으로 설명한다. 결과가 상한에서 잘렸는지 알 수 있도록 truncated 플래그나 커서를 도입한다.

### `MEDIUM` Place/PlaceDetail 에 북마크 여부 필드가 없다. 북마크 API 는 별도로 존재하고 목록은 Place 배열을 통째로 반환하므로, 상세 화면의 하트 상태를 알려면 전체 북마크 목록을 받아 클라이언트에서 대조해야 한다. 계약이 이 대조 책임을 어디에 두는지 정의하지 않아 구현이 갈린다.

**근거**

828-842행 Place 속성에 bookmarked/isSaved 없음, 849-861행 PlaceDetail 도 없음 / 451-462행 `/api/bookmarks: get:` 응답이 `type: array` `items: { $ref: '#/components/schemas/Place' }`

**수정**

PlaceDetail(및 인증 시 nearby 항목)에 `bookmarked: boolean` 을 추가하고 비인증 시 false/생략임을 명시한다.

### `LOW` PlaceCategory enum 이 KTO contentTypeId 체계의 일부만 담는다. 계약은 이 값을 "KTO 콘텐츠타입"이라고 서술하면서 6개만 허용하는데, KTO 체계에는 15(축제공연행사)·25(여행코스)도 존재한다. 캐시에 해당 타입이 들어오는 순간 응답이 스키마를 위반하고, 새 레이어(예: 호텔·미용실)를 추가할 때마다 enum 을 고쳐야 하는 구조다.

**근거**

844-847행 `PlaceCategory:` `description: 프론트 카테고리 키(KTO contentTypeId 또는 레이어 키)` `enum: ['12', '14', '28', '32', '38', '39', 'vet', 'shop', 'trail']` / 836행 `description: "KTO 콘텐츠타입(12관광지/14문화/28레포츠/32숙박/38쇼핑/39음식점)"`

**수정**

현재 스코프에서 15·25 를 제외한 이유를 description 에 명시하거나 enum 에 포함시킨다. 확장 가능성을 고려해 응답 필드는 enum 대신 문자열 + 문서화된 값 목록으로 완화하는 것도 방법이다.

---

## Places · Dogs — 1건

### `LOW` 오류 예시가 응답 의미와 모순된다. Error 스키마의 인라인 example 이 NOT_FOUND 로 고정돼 있고, RateLimited/ValidationError/Forbidden/NotFound 응답에는 자체 example 이 없다(Unauthorized 만 예외). 그 결과 Prism 목 서버와 문서 뷰어에서 /api/places/nearby 의 429 가 `{"error":{"code":"NOT_FOUND","message":"해당 장소를 찾을 수 없습니다."}}` 로 렌더링되고, Dogs 의 400/403 도 마찬가지다. 프론트가 잘못된 code 값으로 분기 로직을 짜게 된다.

**근거**

772-773행 `code: { type: string, example: NOT_FOUND }` / `message: { type: string, example: "해당 장소를 찾을 수 없습니다." }` / 737행 Unauthorized 만 `example: { error: { code: UNAUTHORIZED, ... } }` 보유 / 738-762행 Forbidden·NotFound·ValidationError·Conflict·RateLimited 는 example 없음

**수정**

각 공통 응답에 자체 example 을 붙이고(RATE_LIMITED, VALIDATION_FAILED, FORBIDDEN 등), Error.code 를 자유 문자열 대신 enum 으로 열거해 프론트가 안전하게 분기하게 한다.

---

## Walks — 10건

### `HIGH` GET /api/walks/{walkId} 가 소유자 전용 리소스인데 401/403 을 선언하지 않고 404 만 둔다. 전역 security 는 bearerAuth 이고(40-41행) 형제 오퍼레이션은 모두 401 을 선언하는데(285, 300, 333행) 상세만 빠져 있다. 남의 산책 기록을 조회했을 때 403 인지 404 인지 계약이 정하지 않아, 백엔드는 403 을 던지고 프론트는 404 만 처리하는 식으로 갈린다. 같은 파일의 Dogs 는 소유자 검증에 403 을 명시한다(192, 199행).

**근거**

302-317행: "/api/walks/{walkId}:" → "get:" ... "responses:" 아래 "'200': description: 산책" 과 "'404': { $ref: '#/components/responses/NotFound' }" 만 존재. 대조: 285행 "'401': { $ref: '#/components/responses/Unauthorized' }", 192행 "'403': { $ref: '#/components/responses/Forbidden' }"(dogs patch), 40-41행 "security:\n  - bearerAuth: []"

**수정**

GET /api/walks/{walkId} 에 '401': Unauthorized, '403': Forbidden 추가. 그리고 '타인 리소스는 403 vs 404 중 무엇' 인지 전역 규약을 info.description 에 한 줄로 못박는다.

### `HIGH` 요청 스키마 WalkInput.path 에 좌표 순서 설명과 항목 길이 제약이 전혀 없다. 응답 스키마 Walk.path 만 '[경도, 위도]' 순서와 minItems/maxItems=2 를 명시한다. 즉 GPS 경로를 보낼 때 [lat,lng] 인지 [lng,lat] 인지 계약이 말해주지 않는다 — 좌표 뒤집힘은 프론트/백엔드가 서로 다르게 구현하는 대표 사례이고, 저장된 경로가 엉뚱한 곳에 찍혀야 발견된다.

**근거**

893-897행: "path:\n  type: array\n  items:\n    type: array\n    items: { type: number, format: double }" (설명·minItems·maxItems·example 전부 없음). 대조 874-880행: "description: GPS 경로. [경도, 위도] 좌표 배열(GeoJSON LineString의 coordinates)." / "minItems: 2" / "maxItems: 2" / "example: [[127.0374, 37.5445], ...]"

**수정**

WalkInput.path 에 Walk.path 와 동일한 description·minItems/maxItems·example 을 복제하거나, 좌표배열 타입을 공통 스키마(예: components.schemas.LineStringCoords)로 뽑아 요청/응답이 같은 $ref 를 쓰게 한다.

### `MEDIUM` 응답 엔티티 Walk 에 required 가 하나도 없어 id·startedAt·distanceM 까지 전부 선택 필드가 된다. 같은 도메인의 요청 스키마 WalkInput 은 required 를 명시하고 있어 비대칭이다. 코드 생성기(Flutter/OpenAPI generator)는 모든 필드를 nullable 로 뽑고, 프론트는 id 조차 null 체크해야 한다. 공통 Page 스키마도 동일하게 required 가 없어 hasMore/items 를 신뢰할 수 없다.

**근거**

863-865행 "Walk:\n  type: object\n  properties:" — required 절 없음. 대조 886행 "required: [dogId, startedAt, distanceM, durationS]". 776-783행 "Page:\n  type: object\n  properties:\n    items: ... nextCursor: ... hasMore: { type: boolean }" — required 없음.

**수정**

Walk 에 required: [id, dogId, startedAt, distanceM, durationS], Page 에 required: [items, hasMore] 를 추가한다.

### `MEDIUM` 주간 통계의 기간 계약이 비어 있다. /api/walks/stats/weekly 는 dogId 만 받고 주 선택 파라미터가 없어 과거 주 조회가 불가능하며, 응답 WalkStats 에도 대상 기간(weekStart/weekEnd)·주 시작 요일·타임존이 없다. weekKm 이 '월~일 길이 7' 이라는 건 설명 문장에만 있고 minItems/maxItems 제약이 없어, 서버가 일요일 시작 7칸이나 6칸을 줘도 스키마상 유효하다. 프론트 차트 축 라벨이 서버 가정과 어긋나도 검증되지 않는다.

**근거**

319-333행: "/api/walks/stats/weekly:" 의 parameters 는 "- name: dogId" 하나뿐. 901-908행 "WalkStats:\n  type: object\n  properties:\n    weekKm:\n      type: array\n      description: 월~일 요일별 거리(km). 길이 7.\n      items: { type: number, format: double }" — minItems/maxItems 없음, weekStart 류 필드 없음.

**수정**

weekOf(또는 from/to) 쿼리 파라미터를 추가하고, WalkStats 에 weekStart/weekEnd(date)와 required 를 넣는다. weekKm 에 minItems: 7, maxItems: 7 을 건다.

### `MEDIUM` 산책 리소스의 라이프사이클이 미완성이다. /api/walks/{walkId} 에 PATCH/DELETE 가 없다. 그런데 Walk.endedAt 은 nullable(진행 중 산책을 표현)이고 WalkInput 의 required 에도 endedAt 이 없어 '아직 안 끝난 산책'을 POST 할 수 있는데, 그것을 종료·수정할 오퍼레이션이 계약에 없다. memo/weather 같은 사후 편집 성격 필드도 수정 경로가 없다. 같은 문서의 Dogs 는 patch/delete 를 갖추고 있다.

**근거**

302-317행: "/api/walks/{walkId}:" 아래 오퍼레이션은 "get:" 뿐. 869행 "endedAt: { type: [string, \"null\"], format: date-time }", 886행 "required: [dogId, startedAt, distanceM, durationS]"(endedAt 없음), 881행 "memo: { type: [string, \"null\"] }". 대조 179-199행 dogs 의 "patch:" / "delete:".

**수정**

PATCH /api/walks/{walkId}(종료·메모 수정)와 DELETE /api/walks/{walkId}(204)를 추가하거나, 'POST 는 완료된 산책만 저장한다'로 확정하고 WalkInput.required 에 endedAt 을 넣어 진행 중 상태를 계약에서 제거한다.

### `MEDIUM` POST /api/walks 에 400(검증 실패)과 403/404(남의 dogId 로 저장 시도)가 선언돼 있지 않다. 요청 바디에 dogId 를 그대로 받는데 그 개가 호출자 소유가 아닐 때의 응답이 계약에 없어, 백엔드가 403/404/400 중 무엇을 줄지 구현자마다 갈린다. 같은 문서의 다른 쓰기 오퍼레이션들은 400 을 선언한다.

**근거**

294-300행 "responses:\n  '201': ... '401': { $ref: '#/components/responses/Unauthorized' }" — 400/403/404 없음. 888행 "dogId: { type: integer, format: int64 }". 대조 160행(dogs post), 601행(care log post), 650행(messages post)의 "'400': { $ref: '#/components/responses/ValidationError' }".

**수정**

'400': ValidationError, '403': Forbidden, '404': NotFound 를 추가한다.

### `MEDIUM` 같은 '거리' 개념이 이름과 단위 셋으로 갈라져 있다. 산책 엔티티는 미터 정수(distanceM), 통계는 킬로미터 실수(totalKm/avgKm/weekKm), 장소는 또 다른 이름의 미터 실수(distM)다. 프론트가 목록 합계와 통계 값을 비교·검증하려면 매번 환산 로직을 자체 구현해야 하고, 반올림 기준이 계약에 없어 화면마다 값이 미세하게 달라진다.

**근거**

870행 "distanceM: { type: integer, example: 2400 }", 904-911행 "weekKm: ... totalKm: { type: number, format: double, example: 13.5 }" / "avgKm: { type: number, format: double, example: 2.3 }", 842행 "distM: { type: number, format: double, ... }"

**수정**

저장·전송 단위를 미터 정수로 통일(totalDistanceM/avgDistanceM/weekDistanceM)하고 km 환산은 표시 계층에 맡긴다. 유지한다면 info.description 에 '거리는 항상 미터, 통계만 km' 같은 규약과 반올림 규칙을 명시한다.

### `LOW` 통계의 topPlaces 가 장소를 문자열 이름으로만 표현해, 문서 내 다른 곳의 장소 표현(contentId 키를 가진 엔티티)과 모양이 다르다. 통계에서 장소 상세로 이동할 수 없고 동명 장소를 구분할 수 없으며, 백엔드가 어떤 이름(공식 title? 사용자 입력?)을 채울지도 정해지지 않는다.

**근거**

912-919행 "topPlaces:\n  type: array\n  description: 자주 간 곳 상위\n  items:\n    type: object\n    properties:\n      place: { type: string, example: \"서울숲\" }\n      count: { type: integer, example: 3 }" vs 832행 "contentId: { type: string, example: \"2733967\" }" (Place 식별자)

**수정**

topPlaces 항목을 { place: PlaceRef(=source+contentId+title), count } 로 바꾸고, 상위 몇 개까지인지(limit)도 description 에 명시한다.

### `LOW` 커서 페이지네이션 목록인데 정렬 기준이 문서화돼 있지 않다. GET /api/walks 는 cursor/limit 만 받고 정렬(최신순/오래된순)이나 기간 필터가 계약에 없다. 커서 페이지네이션은 안정적 정렬 키가 전제인데 그 키가 명시되지 않아, 프론트가 기대하는 순서와 서버 구현이 어긋나도 계약으로 판정할 수 없다. 같은 문서의 그룹 메시지 목록은 '최신순'을 description 에 적어 두었다.

**근거**

266-271행 "parameters:\n  - name: dogId ...\n  - $ref: '#/components/parameters/Cursor'\n  - $ref: '#/components/parameters/Limit'" 와 263-265행에 description 없음. 대조 612행 "그룹 채팅 메시지(최신순, 커서 페이지네이션)."

**수정**

오퍼레이션 description 에 '정렬: startedAt desc, 커서는 (startedAt,id) 기준' 을 명시하고, 필요하면 from/to 기간 필터를 추가한다.

### `LOW` weather 가 표시 문자열과 데이터를 한 필드에 섞고, 요청/응답 양쪽에 자유 문자열로 열려 있다. 누가 값을 만드는지(클라이언트가 넣는지 서버가 채우는지), 어떤 포맷인지, 온도 단위는 무엇인지가 계약에 없어 데이터로 활용(필터·집계)할 수 없고 형식이 클라이언트마다 갈린다.

**근거**

882행 "weather: { type: [string, \"null\"], example: \"맑음 24°C\" }" (응답) 과 899행 "weather: { type: string }" (요청, 설명·example 없음)

**수정**

weather 를 { condition: enum, tempC: number } 구조로 쪼개거나, 최소한 '클라이언트가 산책 시작 시점 값을 넣는다 / 포맷은 서버가 해석하지 않는 표시용 문자열' 임을 description 에 명시한다.

---

