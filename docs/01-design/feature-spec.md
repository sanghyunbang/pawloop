# 기능 명세 (Feature Spec)

> Pawloop(포루프)의 MVP 4대 기능(산책·지도·커뮤니티·프로필)과 신규 MVP 기능(가족 케어 & 채팅), 확장 기능의 목적·동작·데이터·상태를 정리한다. 실제 코드(`app/lib/v2`)를 기준으로 작성했으며, 더미/미연동 부분은 그대로 표기한다.

관련 문서: [ERD](../03-database/erd.md) · [화면 흐름](./user-flows.md) · [정보 구조(IA)](./information-architecture.md)

---

## 0. 요약

Pawloop은 "반려동물과 함께 걷고, 동네 반려인들과 연결되는 공간"을 지향한다. **산책을 wedge로** 좁게 시작해 지도(동반장소)·커뮤니티·프로필로 확장한다. 감정 여행(heattrip) 앱에서 피벗하며 감정 요소는 전부 제거됐다.

- 진입: `main.dart` → `MainShell`(`lib/v2/screens/main_shell.dart`)
- 네비 5탭 구성: **홈 · 지도 · [산책 기록 FAB] · 커뮤니티 · 채팅** (가운데 솟은 원형 FAB → 실시간 산책 트래킹). 통계는 탭이 아니라 `me_screen`·`today_screen` 둘에서 push 한다
- 상태관리: `ValueNotifier` + `ValueListenableBuilder` (경량). 탭 인덱스/지도뷰는 `RootTab`(전역 `ValueNotifier`)로 보관.
- 도메인 SSOT: `lib/v2/domain/pet.dart` (`DogProfile`, `PetCategory`, `PetPost` 등). 산책은 `lib/v2/data/walk_*.dart` 다(#145).

### 기능 우선순위 (한눈에)

| 우선순위 | 기능 | 상태 | 데이터 소스 | 비고 |
|---|---|---|---|---|
| P0 | 실시간 산책 트래킹 | **완료(#145·#160)** | `geolocator` 위치 스트림 → `walk.path(LINESTRING)` | 실 GPS — 위치를 못 쓰면 이유별 안내 화면 + 직접 입력 |
| P0 | 산책 기록 작성/조회 | **완료(#145)** | `GET/POST /api/walks` | 트래킹 초안 → 저장. 못 보내면 초안 큐에 남는다 |
| P0 | 지도 · 동반장소 | **실연동(#40 · #273 · #291)** | 관광공사 KorPetTourService2 · 행정안전부 인허가 · 두루누비 | 병원/펫샵/산책로도 실데이터. 산책로는 시트를 열면 선을 그린다 |
| P0 | 강아지 프로필 | 세션 내 편집 반영 | 전역 `kMyDog` | 앱 재시작 시 초기화(미영속) |
| P1 | 커뮤니티(피드/상세/댓글/반응) | 더미 | 로컬 상수(`kPetPosts`) | 백엔드 social API 미연동 |
| P1 | 산책 통계 | **완료(#145)** | `GET /api/walks/stats/weekly` | fl_chart 주간 막대. 이번 주 + 전체 기간이 한 응답 |
| P1 | 가족 케어 & 채팅(그룹·오늘의 케어·주의사항·채팅) | **완료(M2.5·M2.6)** | `family_repository.dart` · `chat_repository.dart` (서버) | §6 |
| P2 | 로그인 | **완료(#12)** | `GET /auth/me` · 소셜 로그인(카카오·구글) | 1회용 코드 교환 · 토큰 보관 · 401 자동 갱신 · 서버 로그아웃 |
| P2 | 실위치(geolocator) | 미도입 | 서울 시청 고정 | `_center` 하드코딩 |
| P3 | 건강/식사/병원/동네 로그 | 미구현 | — | post-MVP 확장 |
| P3 | 반려인 매칭/산책 크루 | 미구현 | — | post-MVP 확장 |

> 상태 표기: **더미** = UI만·데이터 하드코딩, **미영속** = 세션 내 동작하나 저장 안 됨, **실연동** = 외부 API 실제 호출.

---

## 1. 산책 (Walk)

가장 핵심적인 wedge. "실시간 트래킹"과 "수기 기록", 두 경로로 산책을 남긴다.

### 1.1 실시간 산책 트래킹 — `walk_tracking_screen.dart`

| 항목 | 내용 |
|---|---|
| 목적 | 산책 중 경로·거리·시간·페이스를 실시간으로 보여주고, 종료 시 기록으로 저장 유도 |
| 진입 | 홈 "산책 시작" CTA / 바텀네비 가운데 FAB |
| 동작 | 네이버 지도 위 라이브 스탯 패널(km·시간·페이스), 경로 폴리라인 + 헤드 마커, 카메라 추적. 일시정지/재개, 종료 |
| 종료 흐름 | 바텀시트(`WalkFinishSheet` — 시간·거리·페이스 요약 + **경로 미리보기**) → "기록 저장하기"(→ `CreateScreen(prefillPlace:'오늘 산책')`) / "저장 안 함" / **"경로 사진 저장"**(#310): 타일 없이 로컬 캔버스에 그린 PNG 를 기기 갤러리 앨범 Pawloop 에만 넣는다 — 네트워크 0, 업로드 경로 없음. A안 빌드(지도 키 없음)에서도 "내가 걸은 길" 이 보이는 자리다 |
| 데이터 | **실 GPS**: `LocationService.locate()` 로 첫 점을 잡고 `Geolocator.getPositionStream`(5m)을 구독. Haversine `_dist()`로 누적 거리. 위치를 못 쓰면 `WalkLocationDeniedScreen` 이 이유를 말하고 직접 입력으로 보낸다 — 가짜 경로를 그리지 않는다(#160) |
| 상태 | `_seconds`, `_km`, `_paused`, `_path`(진행 경로), `_pathT`(점별 델타 초, `_path` 와 길이 동일), `_denial`(위치 판정 — `null` 이면 판정 전이라 지도를 만들지 않는다). `NaverMapController _ctrl` |
| 남은 것 | 백그라운드 트래킹(화면을 끄면 스트림이 끊긴다). 경로 자체는 `POST /api/walks` 로 `walk.path`(LINESTRING SRID 4326)에 저장된다 |

### 1.2 산책 기록 작성 — `create_screen.dart`

| 항목 | 내용 |
|---|---|
| 목적 | 산책 장소·날짜·거리·시간·사진·메모를 수기로 남긴다 |
| 진입 | 트래킹 종료 후 저장 / `MyRecordsScreen` "산책 기록하기" |
| 동작 | 장소(TextField, `prefillPlace` 프리필) · 날짜(오늘 표시, 선택 UI 미구현) · 거리/시간 스텝퍼(±0.1km / ±5분) · 사진(플레이스홀더, "곧 지원") · 메모(4줄) |
| 저장 | `_save()` → `maybePop()` + "산책 기록이 저장됐어요 🐾" 스낵바. **DB 저장 없음(미영속)** |
| 상태 | `km`(기본 2.0), `minutes`(기본 30), `_place`/`_memo` TextEditingController |
| 데이터 모델 | `ServerWalk{id, dogId, clientWalkId, startedAt, endedAt, distanceM, durationS, path, memo, weather}` — 계약의 `Walk` 그대로. 아직 못 보낸 것은 `WalkDraft` |

### 1.3 내 산책 기록 조회 — `myrecords_screen.dart`

| 항목 | 내용 |
|---|---|
| 목적 | 이번 달 요약 + 전체 산책 리스트 열람 |
| 동작 | 요약 카드(전체 기간 거리·횟수·시간) + 산책 카드 리스트(시각대·날짜·km·분·페이스·메모). 전송 대기 중인 것은 위에 놓이고 뱃지가 붙는다 |
| 데이터 | `GET /api/walks`(커서, 경로 미포함) + 전송 대기 초안. `kWalks` 는 지웠다(#145) |

---

## 2. 지도 (Explore / Map)

"우리 아이랑 갈 수 있는 곳"을 리스트/지도로 탐색. 유일하게 **외부 API 실연동**된 기능.

| 항목 | 내용 | 화면 |
|---|---|---|
| 목적 | 반려동반 가능 장소 + 병원/펫샵/산책로를 카테고리별로 탐색 | `explore_screen.dart` |
| 뷰 | 리스트 ↔ 지도 토글(`view = 'list'|'map'`). 카메라·마커는 `NaverMap` | |
| 필터 | 카테고리 칩 가로 스크롤(전체 + `kPetCategories` 9종). 선택 시 `_catFilter` = contenttypeid 또는 레이어 key — 항목은 `PetPlace.categoryKey`(`contentTypeId` 가 있으면 그것, 없으면 `category`)로 견준다 | |
| 장소 상세 | 마커/카드 탭 → 바텀시트(이름·카테고리·거리·요약·주소·전화·출처 배지). 산책로면 지도 뷰에서 선(`GET /api/places/trails/{courseId}/route`)을 받아 폴리라인으로 그리고 카메라를 맞춘다(#291) | |

### 2.1 데이터 소스

| 레이어 | key | 소스 | 상태 |
|---|---|---|---|
| 여행지/카페·식당/레포츠/숙박/쇼핑/문화 | `12/39/28/32/38/14` | 관광공사 **KorPetTourService2** `locationBasedList2` | **실연동** |
| 병원 | `vet` | 행정안전부 인허가 동물병원(전국) — 서버가 월 1회 받아 카탈로그에 이어 붙인다 | **실연동**(#291) |
| 펫샵 | `shop` | 행정안전부 인허가 동물판매업(전국) | **실연동**(#291) |
| 산책로 | `trail` | 두루누비 걷기여행길 — 시작점은 카탈로그, 선은 `trail_route` | **실연동**(#291) — 카드의 `summary`("2.6km · 약 40분 · 쉬움") + 지도 폴리라인 |

- 호출: `PetPlacesRepository.fetchNearby(lat, lng, radius=8000, numOfRows=80)` → **우리 백엔드**의 `GET /api/places/nearby`. 앱에 관광공사 서비스키가 없다 — 서버가 대신 부르고 셀 단위로 캐시한다(#40). `radius` 의 상한은 계약이 18,000m 로 정한다(서버가 셀 중심에서 20km 를 받아 두고 셀 반지름 약 1.4km 를 뺀 값).
- 응답 파싱: `PetPlace.fromJson` — `mapx`(경도)/`mapy`(위도)/`contenttypeid`/`addr1`/`tel`/`firstimage`/`dist`. 좌표 0인 항목은 제외.
- 카테고리 매핑: `petCatByType(contentTypeId)` (SSOT `kPetCategories`, `pet.dart`).

### 2.2 상태 / 동작 세부

| 상태 | 의미 |
|---|---|
| `_center` | 지도 중심(**서울 시청 37.5665,126.9816 고정** — 실위치 미도입) |
| `_places` | KTO에서 받은 `PetPlace` 목록 |
| `_loading` | 로딩 인디케이터/스낵바 표시 |
| `_catFilter` | null=전체 / contenttypeid / 레이어 key |
| `_mapCtrl` | `NaverMapController` |

- `_filtered` 게터: `trail`이면 빈 리스트(선으로 표시), `vet/shop`이면 더미 레이어, null이면 전체, 그 외 contenttypeid 필터.
- 마커: `NOverlayImage.fromWidget`으로 카테고리색 원형 핀 렌더(플랫폼 통일). `trail`은 `NPolylineOverlay` + 시작 마커.
- 미연동: 검색바(플레이스홀더, 입력 불가), "이 지역에서 찾기"(지도 이동 시 재조회 미구현), 실위치.

---

## 3. 커뮤니티 (Community / Feed)

반려인들의 산책·동반장소·건강 이야기. **전부 더미**(백엔드 social API 미연동).

### 3.1 피드 — `feed_screen.dart`

| 항목 | 내용 |
|---|---|
| 목적 | 게시판별 글 목록을 카드/리스트로 열람 |
| 게시판 | `kPetBoards` = 전체·산책로 후기·동반장소·건강·병원·자유·자랑. 필터 버튼 → 바텀시트 선택 |
| 뷰 토글 | 카드(`_card`) ↔ 리스트(`_row`) |
| 카드 구성 | 닉네임 아바타(첫 글자) · 게시판칩(색상) · 위치 · 제목 · 본문(3줄) · 반응칩 3종 · 댓글수 |
| 상태 | `feedBoard`('전체'), `view`('card') |
| 데이터 | **더미** `kPetPosts`(4건). `PetPost{nick, board, loc, date, title, body, commentCount, reactions[3]}` |

### 3.2 글 상세 — `post_detail_screen.dart`

| 항목 | 내용 |
|---|---|
| 목적 | 글 본문 + 반응 + 댓글 스레드 |
| 반응 | `kPetReactions` = 도움돼요·귀여워요·공감. 버튼 탭 시 **로컬 토글**(카운트 ±1, `_picked` Set) |
| 댓글 | 하단 입력바에서 전송 → 로컬 리스트에 '나' 댓글 추가(**세션 한정, 미영속**). 시드 3건 |
| 상태 | `_reactions`(글 반응 복사본), `_picked`(선택 반응), `_cmts`(댓글 리스트) |
| 미연동 | 글 작성 진입점 없음(피드에 새 글 버튼 미구현), 좋아요/댓글 서버 저장 없음 |

> 백엔드에는 커뮤니티용 엔티티가 아직 반려 맥락으로 재정의되지 않음(레거시 `explore/emotion` 계열 존재). ERD의 `post/comment/reaction`은 목표 스키마.

---

## 4. 프로필 (Profile / Me)

우리 아이(강아지) 프로필 + 산책 활동 요약 + 메뉴.

### 4.1 프로필 조회 — `me_screen.dart`

| 항목 | 내용 |
|---|---|
| 목적 | 강아지 프로필 카드 + 산책 활동 요약 + 메뉴 |
| 프로필 | 아바타 · 이름 · "견종 · 나이 · 크기" · 중성화 배지 |
| 요약 | 총 산책 횟수·총 거리·이번주(`WalkStats` 의 `allTime*` + `week*`, **한 번의 호출**) → 탭 시 `MyRecordsScreen` |
| 메뉴 | 프로필 편집 · 내 산책 기록 · 북마크(스낵바만) · 로그아웃(스낵바만) |
| 데이터 | 전역 `kMyDog`(`ValueNotifier<DogProfile>`) |

### 4.2 프로필 편집 — `edit_screen.dart`

| 항목 | 내용 |
|---|---|
| 목적 | 강아지 정보 수정 |
| 필드 | 이름 · 견종 · 크기(`DogSize` 세그먼트: 소형/중형/대형) · 나이(개월, 숫자) · 중성화 토글 · 프로필 테두리 색(`kAvatarBorders`) |
| 저장 | `_save()` → `kMyDog.value = copyWith(...)`. **세션 내 즉시 반영**(홈/프로필 갱신). 앱 재시작 시 초기값 복귀(미영속) |
| 삭제 | 화면 아래 "프로필 지우기" → 확인("산책 기록은 그대로 남고 통계에도 계속 세요. 프로필은 되돌릴 수 없어요") → `DELETE /api/dogs/{dogId}`(소프트 삭제, #156) → 목록에서 빠지고 남은 아이가 선택된다 |
| 데이터 모델 | `DogProfile{name, breed, size, ageMonths, neutered, avatarAsset}` + 파생 `ageLabel` |

> 목표: `dog` 테이블(user_id FK) 연동. 현재는 로그인/유저 개념 없이 단일 반려견 전역 상태.

---

## 5. 홈 · 통계 (보조 화면)

### 5.1 홈 — `today_screen.dart`

| 항목 | 내용 |
|---|---|
| 목적 | 우리 아이 히어로 + 오늘 산책 요약 + 진입 CTA |
| 구성 | 날짜/인사("{이름}랑 산책 갈까요?") · 강아지 히어로 · 오늘 산책 요약(**서버 + 전송 대기**) · CTA(산책 시작/코스 찾기) · 날씨 카드(하드코딩) |
| 상태 | `kMyDog` 구독. 요약은 항상 0(실기록 연동 전) |

### 5.2 산책 통계 — `insight_screen.dart`

| 항목 | 내용 |
|---|---|
| 목적 | 이번 주 요약 + 주간 거리 막대그래프 + 자주 가는 곳 |
| 요약 | 총 거리·횟수·평균(`WalkStats` 의 이번 주 값) |
| 차트 | `fl_chart` `BarChart` 주간(월~일) 막대. 오늘(**실제 요일**) 강조 그라데이션, 툴팁 |
| 자주 가는 곳 | **항상 빈 상태** — `Walk` 에 장소 축이 없다(#145) |
| 데이터 | `GET /api/walks/stats/weekly` + 전송 대기 초안. 주 경계는 **KST** 이고 서버가 자른다 |

---

## 6. 가족 케어 & 채팅 (Family Care & Chat)

반려는 혼자가 아니라 **가족이 함께** 돌본다. 가족 간 케어 공유로 이중 급여(밥 두 번)·산책 누락을 막고, 앱의 일일 사용 이유(리텐션)를 만든다.

**아래 §6.1~6.4 는 전부 서버 연동이 끝났다**(M2.5·M2.6 — #75·#76·#78~#81). 데이터는 `lib/v2/domain/pet.dart` 의 로컬 상수가 아니라 `lib/v2/data/family_repository.dart`·`chat_repository.dart` 가 든다. 아래 표의 "더미" 표기는 그때의 계획이었고, 각 절의 **상태** 행이 지금을 말한다.

### 6.1 가족 그룹 — `family_screen.dart` (MVP)

| 항목 | 내용 |
|---|---|
| 목적 | 케어를 함께 나눌 가족 단위를 만든다(그룹 생성·초대코드로 참여·멤버 목록) |
| 진입 | 홈 "오늘의 케어" 카드 / 프로필 메뉴 "우리 가족" |
| 동작 | 그룹 생성, 초대코드 공유/입력으로 참여, 멤버 목록(역할 owner/member) 표시. 가족 화면에서 케어 현황·주의사항·채팅으로 진입 |
| 데이터 | `family_group(id, name, created_at)` — **초대코드도 멤버 표도 여기 없다.** ADR-0011(#72)이 초대코드를 방으로 옮겼고 멤버십은 `chat_room_member` 다 |
| API | `POST /api/groups`(생성 — 같은 트랜잭션에서 방과 방장 멤버십이 함께 생긴다) · `POST /api/chat/rooms/{roomId}/invites`(초대코드 발급) · `POST /api/chat/invites/{code}/join`(참여) · `GET /api/groups/me`(내 그룹) |
| 상태 | ✅ 서버 연동됨. 2026-08 이전에는 이 칸이 `POST /api/groups/join` 을 적었는데, ADR-0014(#152)가 지운 경로가 여기서 되살아나 있던 것이다(#201) |

### 6.2 오늘의 케어 공유 (MVP)

| 항목 | 내용 |
|---|---|
| 목적 | 물 갈아주기/밥/산책을 **누가·언제** 했는지 가족이 공유 — 이중 급여·산책 누락 방지 |
| 진입 | 홈 "오늘의 케어" 카드 / 가족 화면 케어 현황 |
| 동작 | 오늘의 케어 항목(물/밥/산책) 체크 + 수행자·시각 표시. 기록 시 그룹에 공유. 잘못 찍은 **내** 기록은 칸을 길게 눌러 지운다 — 남의 기록은 못 지운다(#209) |
| 데이터 | 기존 care_log 계획 확장: `care_log(id, dog_id FK, group_id FK nullable, type[water/meal/walk/med/vet], done_by(user_id), occurred_at, memo)`. 더미: `CareType`/`CareTask`/`kCareToday` |
| API | `GET/POST /api/groups/{groupId}/care-logs`(오늘 케어 조회/기록) · `DELETE …/care-logs/{careLogId}`(본인 기록 삭제, #209) |
| 상태 | ✅ **서버 연동됨** (M2.5·M2.6) |

### 6.3 산책 시 주의사항 (MVP)

| 항목 | 내용 |
|---|---|
| 목적 | 산책할 때 알아야 할 것을 가족 공유 메모로 남긴다 |
| 진입 | 가족 화면 |
| 동작 | 공유 메모 열람/수정 |
| 데이터 | `walk_note(id, group_id FK, body, created_at)` 또는 그룹의 공유 메모. 더미: `kWalkNotes` |
| API | `GET/PUT /api/groups/{groupId}/walk-notes` |
| 상태 | ✅ **서버 연동됨** (M2.5·M2.6) |

### 6.4 가족 채팅 — `family_chat_screen.dart` (MVP)

| 항목 | 내용 |
|---|---|
| 목적 | 가족 그룹 채팅 — 케어를 둘러싼 일상 대화로 일일 사용 이유를 만든다 |
| 진입 | 가족 화면 → 채팅 |
| 동작 | 메시지 목록(커서 페이지네이션) + 입력바 전송. **MVP는 폴링**, 실시간(WebSocket/STOMP)은 post-MVP |
| 데이터 | `chat_message(id, room_id FK, room_seq, sender_user_id, sender_name, content_type, body, client_msg_id, created_at, deleted_at)`. **`group_id`·`user_id` FK 는 없다** — 방은 가족 그룹에 종속되지 않고([ADR-0011](../99-decisions/decision-log.md)), `users` 로 FK 를 내면 탈퇴 한 번에 그 사람이 쓴 말이 전부 사라진다. 더미: `ChatMessage`/`kChatMessages` |
| API | `GET/POST /api/chat/rooms/{roomId}/messages` |
| 상태 | ✅ **서버 연동됨** (M2.5·M2.6) |

### 6.5 post-MVP

친구 추가(가족 외) · 케어 알림/리마인더 · 케어 히스토리 통계 · 실시간 푸시.

> UI/UX는 기존 바이브 유지 — AuroraBackground + GlassCard, 따뜻한 그라데이션(#FFA96B→#FF7E8A), Pretendard, Fluent Emoji 톤.

---

## 7. 확장 기능 (post-MVP)

MVP 범위 밖. 개요만 정의하며 현재 미구현.

| 우선순위 | 기능 | 개요 | 필요 선행 |
|---|---|---|---|
| P2 | **로그인** | 소셜 로그인(카카오·구글 — 네이버는 ADR-0010 에서 보류). 백엔드 OAuth/JWT 는 #7·#9·#14 에서 실렸다. 유저별 반려견·기록·글 귀속 | `users` 연동, 앱 토큰 저장 |
| P2 | **실위치** | `geolocator` 도입 → 지도 `_center`·트래킹 GPS 실제화. 권한 처리 | 위치 권한 UX |
| P3 | **건강 로그** | 체중·컨디션 등 기록 | `care_log(type=health)` |
| P3 | **식사 로그** | 사료·간식·급여량 | `care_log(type=meal)` |
| P3 | **병원/접종 기록** | 방문·접종·투약 이력 | `care_log(type=vet/med)` |
| P3 | **동네 로그** | 동네 단위 활동/장소 로그 | 지역 스키마 |
| P3 | **반려인 매칭 / 산책 크루** | 근처 반려인 매칭·동반 산책 모집 | 유저·위치·매칭 |
| P2 | **백엔드 반려 API** | 산책/장소/커뮤니티 실연동. KTO는 향후 백엔드 프록시+캐싱(1000콜/일 제한 대응) | Spring `tour/social` 재정의 |

### 확장 시 데이터 모델(요약)

- `walk(dog_id, started_at, ended_at, distance_m, duration_s, path LINESTRING, memo, weather)` — GPS 경로는 한 컬럼
- `care_log(dog_id, type[meal/health/vet/med], occurred_at, title, value, memo, photo)`
- `place_catalog(source, payload)` — 출처별 장소 한 벌(KTO/인허가/두루누비, #291) · `trail_route(course_id, payload)` — 산책로의 선
- 공간쿼리: `ST_Distance_Sphere`/`MBRContains` + SPATIAL INDEX. 상세는 [ERD](../03-database/erd.md) 참조.

---

## 8. 공통 사항

| 항목 | 내용 |
|---|---|
| 상태관리 | `ValueNotifier` + `ValueListenableBuilder`. 전역: `RootTab.index/exploreView`, `kMyDog`, `AppThemeCtl.avatarBorder` |
| 영속성 | **현재 없음** — 대부분 로컬 상수/세션 상태. 저장 액션은 스낵바 피드백만 |
| 외부 연동 | 관광공사 KorPetTourService2 · 행정안전부 인허가 · 두루누비(전부 서버 경유, 실연동) · 네이버 지도 SDK(Client ID) |
| 미구현 진입점 | 커뮤니티 글쓰기, 지도 검색, 날짜 선택, 사진 첨부, 북마크 저장, 로그인 |
