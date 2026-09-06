# 구현 현황 (Implementation Status)

> Pawloop(포루프) Flutter 앱의 화면·기능별 실제 구현 상태. 감정 여행(heattrip) → 반려(강아지 산책) 피벗 완료 기준. **소스 오브 트루스는 `app/lib/v2/`** 이며, 이 문서는 그 코드를 직접 읽고 정리한 것이다.

- **기준 커밋/시점**: `app/lib/v2/` 현재 상태
- **엔트리**: `app/lib/main.dart` → go_router(`app/lib/app/app_router.dart`) → `/home` = `v2/screens/main_shell.dart`(`MainShell`)
- **네비**: 플로팅 글래스 알약 5탭 — 홈 / 지도 / **[산책 기록 FAB]** / 커뮤니티 / **채팅** (`main_shell.dart:108-111`). 통계(`insight_screen`)는 탭이 아니라 `me_screen`·`today_screen` **둘**에서 진입한다
- **상태 표기**: `구현완료`(UI+동작) · `실연동`(외부 데이터 연동됨) · `더미`(하드코딩·시뮬) · `미구현`

---

## 1. 요약

| 영역 | 상태 | 한 줄 |
| --- | --- | --- |
| 감정 → 반려 피벗 | ✅ 완료 | 도메인 `v2/domain/pet.dart`(강아지/산책/장소/커뮤니티)로 전면 교체. 감정 요소 없음 |
| 홈(오늘) | ✅ 구현완료 (더미 데이터) | 강아지 히어로 + 오늘 산책 요약 + CTA + 날씨 |
| 지도(탐색) | ✅ **실연동** | 관광공사 반려동반(전국 한 벌) + 병원/펫샵(행정안전부 인허가, 전국) + 산책로(두루누비, 시트에서 선) — #291 |
| 산책 트래킹 | ✅ 실 GPS · 서버 저장 | 실 위치 스트림(5m)으로 폴리라인·거리·페이스. 끝내면 `POST /api/walks` 로 남는다(#145). 위치 판정 전에는 시뮬 경로를 그리지 않는다 |
| 산책 통계 | ✅ 구현완료 (더미 데이터) | fl_chart 주간 막대 + 요약 + 자주 가는 곳 |
| 커뮤니티 | ✅ **읽기·쓰기·수정·삭제가 서버** | 백엔드 `/api/community` 열 경로(#170·#211) — 읽기 셋은 **인증 선택**(게스트가 읽는다), 반응은 멱등 둘, 수정 하나, 삭제 둘. 앱은 `community_repository.dart` 로 붙었고 편집 화면만 아직 없다(#171·#172·#211). 남은 것은 관리(#166) |
| 강아지 프로필 | ✅ 구현완료 (로컬 상태) | 프로필/편집. `ValueNotifier`로 전역 반영, 영속화 없음 |
| 로그인 | ✅ 구현완료 (카카오·구글) | 소셜 로그인 화면 · 1회용 코드 교환 · 토큰 보관 · 401 자동 갱신 · 서버 로그아웃 |
| 실위치 | ✅ 구현완료 | `location_service.dart` — 단발 조회 + 5m distanceFilter 스트림. 실패했을 때만 서울시청으로 떨어진다 |
| 백엔드 반려 API | ✅ 대부분 | 인증·프로필·가족·케어·주의사항·채팅·장소 프록시·반려동물·산책·**커뮤니티**가 서버에 있고 앱이 전부 붙었다. 병원/펫샵/산책로 실데이터도 #291 에서 서버로 갔다 |
| 채팅 | ✅ 서버 연동 | 방 목록·방 안·가족 화면 셋 다 서버에서 받는다. 적응형 폴링 · 낙관적 전송 · 멱등 재전송 · 미읽음 뱃지(#81) |
| 채팅 서버 | ✅ 엔드포인트 + 운영 API | 표 넷(#74·#78) 위에 조회·전송·읽음·방목록 4종(#79), 초대·강퇴·차단·신고(#75·#82). **메시지 삭제만 아직 없다** (ADR-0011 · #72) |

---

## 2. 화면별 상태 (`app/lib/v2/screens/`)

| 화면 | 파일 | 상태 | 구현된 것 | 더미 / 미구현 |
| --- | --- | --- | --- | --- |
| **홈 (오늘)** | `today_screen.dart` `TodayScreen` | ✅ 구현완료 | 날짜 헤더, 강아지 히어로, 오늘 산책 요약(회/km/분 — **서버 + 전송 대기**), CTA, 날씨 카드 | 날씨 카드 하드코딩(맑음·24°C). 서버를 못 부르면 0 대신 "기록을 불러오지 못했어요" 를 말한다 |
| **지도 (탐색)** | `explore_screen.dart` `ExploreScreen` | ✅ 실연동 | 리스트/지도 토글, 카테고리 필터 칩 아홉, 네이버맵 마커·바텀시트, 카테고리 색핀, 범례, 산책로 선(#291) | 검색창 비동작(플레이스홀더). 산책로 선은 지도 키 있는 빌드에서만 그린다 |
| **산책 트래킹** | `walk_tracking_screen.dart` `WalkTrackingScreen` | ✅ 구현완료 | 실 위치 스트림으로 경로 폴리라인, 라이브 스탯, 일시정지/재개/종료 → 저장 화면으로 **초안 전달** | 위치를 못 쓰면 이유를 말하는 화면을 띄우고 직접 입력으로 넘긴다 — 가짜 경로를 그리지 않는다(#160) |
| **산책 통계** | `insight_screen.dart` `InsightScreen` | ✅ 구현완료 | fl_chart 주간 거리 막대(**실제 오늘** 강조), 요약(총거리·횟수·평균), 주간 문구 | 자주 가는 곳은 **항상 빈 상태** — `Walk` 에 장소 축이 없다(계약의 `topPlaces` 도 같다) |
| **커뮤니티 (피드)** | `feed_screen.dart` `FeedScreen` | ✅ 서버 연동 | 카드/리스트 토글, 게시판 필터 시트, 반응 칩, 글 카드/행, 커서 더 보기, 당겨서 새로고침 | `GET /api/community/posts`(#171). 게시판은 `CommunityBoard` enum 이 ASCII 키(`walk_review`)와 한글 라벨을 함께 든다. 못 부르면 빈 목록이 아니라 "불러오지 못했어요" + 다시 시도. 글쓰기 진입은 `writePost()` 하나를 지난다(#172). 상세에서 내 글을 지우면 `true` 를 들고 나와 목록이 새로고침한다(#211) |
| **글 상세** | `post_detail_screen.dart` `PostDetailScreen` | ✅ 서버 연동 | 본문, 반응 셋(동시 선택), 댓글 스레드, 댓글 입력 | 반응은 멱등 `POST`/`DELETE .../reactions/{type}` 이고 **응답의 집계를 그대로 그린다**(로컬에서 안 센다). 게스트는 `reactions.mine == null` 로 판별하고 입력칸 대신 안내를 그린다 — 쓰고 나서 401 을 내면 쓴 글자를 잃는다 |
| **강아지 프로필** | `me_screen.dart` `MeScreen` | ✅ 구현완료 | 프로필 헤더, 산책 활동 요약(→기록), 메뉴(편집/기록/북마크/로그아웃) | 북마크는 스낵바만(미구현). 로그아웃은 `POST /auth/logout`(전 기기 폐기) 후 로그인 화면으로 — #12 |
| **프로필 편집** | `edit_screen.dart` `EditScreen` | ✅ 구현완료 | 이름·견종·크기·나이(개월)·중성화 편집, 아바타 테두리색, 저장 시 `kMyDog` 갱신 | 앱 재시작 시 초기화(영속 저장 없음), 아바타 이미지 자체는 고정 |
| **산책 기록 작성** | `create_screen.dart` `CreateScreen` | ✅ 구현완료 | 트래킹 초안(거리·시간·경로)을 받아 저장, 초안 없으면 손입력 | 사진 첨부 "곧 지원", 날짜 선택 비동작. 스텝퍼를 **만졌을 때만** 실측값을 덮는다(1분 미만이 사라지지 않게) |
| **내 산책 기록** | `myrecords_screen.dart` `MyRecordsScreen` | ✅ 구현완료 | **전체 기간** 요약, 기록하기 버튼, 산책 카드 리스트(서버 + 전송 대기 뱃지) | 장소 축이 없어 카드 제목은 시작 시각대(새벽/아침/오후/저녁) |
| **위치 찍기** | `pin_picker_screen.dart` `PinPickerScreen` | 🟡 더미 | 스타일라이즈드 지도 탭 → 좌표 기록, pop 반환 | 실지도 아님(장식용 배경). 현재 플로우에서 호출부 없음 |
| **채팅 (방 목록)** | `chat_list_screen.dart` `ChatListScreen` | ✅ 서버 연동 | 방 카드 리스트(이름·태그·마지막 메시지·미읽음 뱃지·멤버 수) — `GET /api/chat/rooms` | 방은 가족 그룹을 만들 때 함께 생긴다(#196). 방만 따로 만드는 경로는 없다 — ADR-0011 이 방을 `origin_kind`/`origin_ref` 로 그룹에 매달았다 |
| **채팅 (방 안)** | `family_chat_screen.dart` `FamilyChatScreen` | ✅ 서버 연동 | 적응형 폴링(`afterSeq` 델타·ETag), 낙관적 전송 + 같은 멱등키 재전송, 읽음 보고, 신고·가리기·강퇴, 첫 진입 약관 동의 | 메시지 삭제 UI 없음(서버 API 도 없다) |
| **가족** | `family_screen.dart` `FamilyScreen` | ✅ 서버 연동 | 멤버 목록, 초대코드, 오늘의 케어 현황, 산책 주의사항, 채팅 진입 — `FamilyRepository`(#76). **그룹 만들기·초대 코드로 참여**(#196) | 그룹이 없으면 만들기·참여 둘 다 보이고, 만들면 초대 코드가 바로 뜬다 |

---

## 3. 기능/도메인 상태

### 3.1 산책
| 기능 | 상태 | 비고 |
| --- | --- | --- |
| 실시간 GPS 트래킹 | ✅ | geolocator 스트림 + `walk.path` LINESTRING 저장(#145). 위치 판정 전에는 아무것도 그리지 않는다 |
| 산책 기록(수동 작성) | ✅ | `create_screen` 이 `POST /api/walks` 로 보낸다. 못 보내면 초안 큐에 남는다 |
| 산책 통계/차트 | ✅ | fl_chart. 소스는 `GET /api/walks/stats/weekly`(이번 주 + 전체 기간) |
| 자주 가는 곳 | ❌ 빈 상태 | `Walk` 에 장소 축이 없다. 계약의 `topPlaces` 도 항상 빈 배열이다 — 그럴듯한 값을 만들지 않는다 |

### 3.2 지도/장소
| 레이어 | 상태 | 데이터 소스 |
| --- | --- | --- |
| 반려동반 장소(여행지/카페·식당/레포츠/숙박/쇼핑/문화) | ✅ **실연동** | 관광공사 KorPetTourService2 `locationBasedList2` — `pet_places_repository.dart` |
| 동물병원 | ✅ **실연동**(#291) | 행정안전부 인허가 동물병원 — 전국, 영업 중만, EPSG:5174→WGS84 는 서버가. 카탈로그에 `source=vet` 으로 이어 붙는다 |
| 펫샵 | ✅ **실연동**(#291) | 행정안전부 인허가 동물판매업 — `source=shop`, `summary` 에 상세 업무 구분 |
| 산책로 | ✅ **실연동**(#291) | 두루누비 걷기여행길 — 시작점은 카탈로그(`source=trail`), 선은 `GET /api/places/trails/{courseId}/route`. 공공데이터포털 활용신청 뒤 첫 적재 |
| 지도 SDK | ✅ | `flutter_naver_map`. Client ID(`--dart-define=NAVER_MAP_CLIENT_ID`) 없으면 지도 비활성 |
| 장소 검색 | ❌ 미구현 | 검색창은 플레이스홀더(비동작) |
| 현재 위치 기반 | ✅ 구현완료 | 현위치로 카메라·검색 중심을 잡고, 실패했을 때만 서울시청(37.5665, 126.9816)으로 떨어진다 |

> KTO 서비스키는 **서버 환경변수** `TOUR_API_SECRET` 으로만 존재한다([#40](https://github.com/sanghyunbang/heattrip/issues/40)). 앱은 `GET /api/places/nearby` 만 부르고, 서버가 좌표를 0.02° 격자로 접어 캐시하며 일 1,000콜 한도를 `kto_call_budget` 표가 게이트로 지킨다.
>
> ⚠️ 앱에 남은 유일한 과금성 자격증명이다. `--dart-define` 은 `.env` 에셋 번들링(#29 이전)보다 낫지만 완화일 뿐 — 문자열은 여전히 바이너리 안에 있다. **[#40](https://github.com/sanghyunbang/heattrip/issues/40) 에서 호출을 백엔드 프록시로 옮기면 이 키는 앱에서 완전히 사라진다**(그때 기존 키는 폐기·재발급).

### 3.3 커뮤니티
| 기능 | 상태 | 비고 |
| --- | --- | --- |
| 게시판(전체/산책로후기/동반장소/건강·병원/자유/자랑) | ✅ | `CommunityBoard` enum 이 ASCII 키(`walk_review`)와 한글 라벨을 함께 든다. 목록의 '전체' 는 필터이지 게시판이 아니라 글쓰기 선택지에는 없다 |
| 목록(카드/리스트) | ✅ 서버 | `GET /api/community/posts` 커서 페이지. 빈 게시판이면 어느 게시판이 비었는지 말한다(#173) |
| 반응(도움돼요/귀여워요/공감) | ✅ 서버 | 멱등 `POST`/`DELETE .../reactions/{type}`. **셋을 동시에 누를 수 있다**(ADR-0016). 응답의 집계를 그대로 그린다 |
| 댓글 | ✅ 서버 | 오래된 것부터. 게스트에게는 입력칸 대신 안내 |
| 글쓰기 | ✅ | `post_write_screen.dart`(#172). 진입점 셋이 `writePost()` 하나를 지나고 거기서 미로그인을 안내한다. 지도 장소 시트에서 오면 `loc`·`contentId` 를 물고 온다 |
| 삭제(글·댓글) | ✅ 서버 | `DELETE .../posts/{id}` · `.../posts/{id}/comments/{id}`(#211). **내가 쓴 것만** — `PostDetailScreen._isMine` 이 `PersonRef.userId` 와 내 id 를 견줘 버튼을 그리고, 진짜 판정은 서버가 한다. 글 삭제만 한 번 묻는다(남의 댓글까지 사라진다). 탈퇴한 사람의 글은 아무도 못 지운다 — 그건 관리이고 [#166](https://github.com/sanghyunbang/heattrip/issues/166) 의 결정이다 |
| 글 수정 | ✅ | `PATCH .../posts/{id}`(#211) + 앱 편집 화면(#243). **글쓰기 화면을 편집 모드로 재사용**한다 — 두 벌이면 상한도 문구도 갈린다. **안 바뀐 키는 안 보낸다**(`PostPatch`, `minProperties: 1`) — 다 실으면 그 사이 다른 기기에서 고친 값을 조용히 되돌린다. 하나도 안 고쳤으면 요청을 안 보낸다. `loc`·`contentId` 는 못 바꾼다(계약이 뺐다) — 화면이 읽기 전용으로 보여만 준다 |
| '수정됨' 표시 | ✅ | `Post.updatedAt` 이 `null` 이면 한 번도 안 고친 글이다. **값이 실제로 달라진 경우에만** 서버가 찍는다 — 같은 값을 다시 보내는 것은 수정이 아니다. 댓글에는 없다(수정 경로가 계약에 없다) |

### 3.4 프로필/계정
| 기능 | 상태 | 비고 |
| --- | --- | --- |
| 강아지 프로필(견종/크기/나이/중성화) | ✅ | `DogProfile`, 전역 `kMyDog`(`ValueNotifier`) |
| 프로필 편집 | ✅ | 저장 시 즉시 전역 반영. **영속화 없음** |
| 아바타 테두리색 | ✅ | `AppThemeCtl.avatarBorder` |
| 로그인/소셜 | ✅ 구현완료 | `v2/screens/login_screen.dart`(카카오·구글). `flutter_web_auth_2` 로 `/oauth2/authorization/{provider}?state=` 를 열고, 딥링크의 1회용 `code` 를 `POST /auth/oauth/{provider}/callback` 으로 교환한다(#14). 공급자 집합은 [ADR-0010](../99-decisions/decision-log.md#adr-0010--소셜-로그인-공급자와-앱-세션-토큰-전략) |
| 북마크 | ❌ 미구현 | 스낵바만 |

### 3.5 채팅

**서버 설계의 입력이 되는 것은 아래 표입니다.** 도메인 SSOT 는 `app/lib/v2/domain/pet.dart` 이고, 화면이 이미 요구하는 필드가 곧 계약입니다. 자세한 근거는 [ADR-0011](https://github.com/sanghyunbang/heattrip/issues/72).

| 클라 모델 | 필드(실측) | 서버에서 무엇이 되는가 |
| --- | --- | --- |
| `ChatRoom`(`pet.dart:413`) | `name` · `tag`('가족'/'산책 크루') · `color` · `icon` · `messages` · `unread` · `memberCount` · `isDefault` | `tag` → `chat_room.origin_kind`. `unread` → `room.last_seq − member.last_read_seq` **뺄셈**(캐시 아님). `memberCount` → 방 목록 쿼리의 집계. `color`·`icon` 은 클라 표현이라 서버로 가지 않는다 |
| `ChatMessage`(`pet.dart:381`) | `sender`(String) · `text` · `time`(**표시 문자열** `'08:11'`) · `mine`(bool) | `sender` → `sender_name` 스냅샷. `mine` 은 서버가 주지 않고 `senderUserId == 내 id` 로 클라가 계산한다. ⚠️ **`time` 이 표시 문자열이라 `afterSeq` 커서를 붙이려면 클라 모델부터 바뀐다** — `roomSeq`(int)와 `createdAt`(DateTime) 두 필드가 새로 필요하다 |

| 기능 | 상태 | 비고 |
| --- | --- | --- |
| 방 목록·미읽음 뱃지 | 🟡 더미 | `unread` 가 상수. 서버에서는 뺄셈 |
| 메시지 송수신 | 🟡 로컬 | 폴링·재시도·멱등키(`clientMsgId`) 전부 없음 |
| 읽음 처리 | ❌ 미구현 | `lastReadSeq` 개념 자체가 클라에 없음 |
| 신고·차단·강퇴 | ❌ 미구현 | 스토어 UGC 심사 요건(Apple 1.2 · Google Play UGC). M2.7 |
| 푸시 알림 | ❌ 미구현 | 저장소 전체에 푸시 자산 0. M2.8 |

---

## 4. 아키텍처/기술 스택 실측

| 항목 | 실제 |
| --- | --- |
| 구조 | `main.dart`(진입) → go_router `/home` → `MainShell`. 화면 `v2/screens/`, 도메인 `v2/domain/pet.dart`, 데이터 `v2/data/pet_places_repository.dart`, 위젯 `v2/widgets/`(aurora=`AuroraBackground`+`GlassCard`, `profile_avatar`), 테마 `v2/theme/`(`app_tokens`=T, `themes`) |
| 상태관리 | `ValueNotifier` + `ValueListenableBuilder`(경량). 화면 내 `setState` |
| 라우팅 | 탭 전환은 `RootTab.index`(전역 `ValueNotifier`), 상세는 `Navigator.push`(MaterialPageRoute) |
| 지도 | `flutter_naver_map`(pubspec `^1.3.1`) |
| 차트 | `fl_chart ^1.2.0` |
| 네트워크 | `http` + `AuthedClient`(401 자동 갱신·단일 비행). 외부 직접 호출 **0종** — 관광공사는 백엔드 프록시 경유(#40) |
| 설정 | 컴파일 타임 `--dart-define` 단독(`flutter_dotenv`·`.env` 는 #29 에서 제거). 단일 진입점 `core/config/env.dart` 의 `Env`. 키: `API_BASE`(override) · `API_BASE_URL` · `NAVER_MAP_CLIENT_ID`. **관광공사 키는 #40 에서 제거됐다.** 값 묶음 템플릿은 `app/dart-define.example.json` |
| 디자인 | 파스텔 오라 그라데이션 배경, 글래스 카드(BackdropFilter blur), 따뜻한 그라데이션(#FFA96B→#FF7E8A), 플로팅 글래스 알약 네비 + 가운데 솟은 산책 FAB |

---

## 5. 미구현/우선순위 갭 (Next)

1. **실위치·GPS**: `geolocator` 도입 → 지도 중심/주변 검색을 현재 위치로, 산책 트래킹을 실제 위치 스트림으로.
2. **산책 기록 영속화**: `create_screen`·트래킹 종료 → 로컬 저장(DB/`shared_preferences`) 또는 백엔드 `walk` 저장.
3. ~~**공공데이터 실연동**: 병원/펫샵(LOCALDATA, EPSG:5174→WGS84 변환), 산책로(두루누비 GPX) → 더미 레이어 교체.~~ → **완료**(#291).
4. **백엔드 반려 API + KTO 프록시/캐싱**: 직접 호출 → Spring Boot 프록시(1000콜/일 회피·캐시), 커뮤니티/프로필 CRUD.
5. ~~**로그인**~~: 카카오·구글 소셜 로그인과 `users` 연결은 #11·#12·#14 에서 실었다. 남은 것은 **로그인 사용자에 귀속되는 데이터**(강아지 프로필·산책 기록·커뮤니티 글)의 서버화다.
6. ~~**커뮤니티 글쓰기**~~: 작성 화면(#172)·삭제·수정(#211)까지 실었다. 서버에 없는 것은 관리(#166)뿐이고, 앱에 없는 것은 편집 화면이다.
7. **채팅 서버화**: 화면 셋(`chat_list_screen`·`family_chat_screen`·`family_screen`)이 이미 있고 탭 3번을 차지하는데 서버가 없다. 방·멤버십·메시지 3테이블 + 폴링 API(M2.5~M2.6). **여기서 `id` 커서를 쓰면 안 된다** — 이유는 [ADR-0011](https://github.com/sanghyunbang/heattrip/issues/72).

> 참조: [ERD](../03-database/erd.md), [외부 데이터 연동](../02-architecture/external-data.md) (경로는 문서 세트 기준, 없으면 생성 예정)
