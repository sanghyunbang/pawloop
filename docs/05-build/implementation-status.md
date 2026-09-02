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
| 지도(탐색) | 🟡 **KTO 실연동** + 더미 레이어 | 관광공사 반려동반 실데이터(서울) + 병원/펫샵/산책로 더미 |
| 산책 트래킹 | ✅ 실 GPS · 서버 저장 | 실 위치 스트림(5m)으로 폴리라인·거리·페이스. 끝내면 `POST /api/walks` 로 남는다(#145). 위치 판정 전에는 시뮬 경로를 그리지 않는다 |
| 산책 통계 | ✅ 구현완료 (더미 데이터) | fl_chart 주간 막대 + 요약 + 자주 가는 곳 |
| 커뮤니티 | 🟡 더미 | 목록/상세/댓글/반응 UI 동작. 백엔드 미연동 |
| 강아지 프로필 | ✅ 구현완료 (로컬 상태) | 프로필/편집. `ValueNotifier`로 전역 반영, 영속화 없음 |
| 로그인 | ✅ 구현완료 (카카오·구글) | 소셜 로그인 화면 · 1회용 코드 교환 · 토큰 보관 · 401 자동 갱신 · 서버 로그아웃 |
| 실위치 | ✅ 구현완료 | `location_service.dart` — 단발 조회 + 5m distanceFilter 스트림. 실패했을 때만 서울시청으로 떨어진다 |
| 백엔드 반려 API | ✅ 상당 부분 | 인증·프로필·가족·케어·주의사항·채팅·장소 프록시·**반려동물·산책**이 서버 연동. 남은 더미는 커뮤니티다 |
| 채팅 | ✅ 서버 연동 | 방 목록·방 안·가족 화면 셋 다 서버에서 받는다. 적응형 폴링 · 낙관적 전송 · 멱등 재전송 · 미읽음 뱃지(#81) |
| 채팅 서버 | ✅ 엔드포인트 + 운영 API | 표 넷(#74·#78) 위에 조회·전송·읽음·방목록 4종(#79), 초대·강퇴·차단·신고(#75·#82). **메시지 삭제만 아직 없다** (ADR-0011 · #72) |

---

## 2. 화면별 상태 (`app/lib/v2/screens/`)

| 화면 | 파일 | 상태 | 구현된 것 | 더미 / 미구현 |
| --- | --- | --- | --- | --- |
| **홈 (오늘)** | `today_screen.dart` `TodayScreen` | ✅ 구현완료 | 날짜 헤더, 강아지 히어로, 오늘 산책 요약(회/km/분 — **서버 + 전송 대기**), CTA, 날씨 카드 | 날씨 카드 하드코딩(맑음·24°C). 서버를 못 부르면 0 대신 "기록을 불러오지 못했어요" 를 말한다 |
| **지도 (탐색)** | `explore_screen.dart` `ExploreScreen` | 🟡 KTO 실연동 + 더미 | 리스트/지도 토글, 카테고리 필터 칩, 네이버맵 마커·바텀시트, 카테고리 색핀, 범례 | 병원·펫샵 `_dummyVet`/`_dummyShop` 하드코딩, 산책로 폴리라인 `_trailCoords` 더미, 검색창 비동작(플레이스홀더), 중심 좌표 서울 고정 |
| **산책 트래킹** | `walk_tracking_screen.dart` `WalkTrackingScreen` | ✅ 구현완료 | 실 위치 스트림으로 경로 폴리라인, 라이브 스탯, 일시정지/재개/종료 → 저장 화면으로 **초안 전달** | 위치를 못 쓰면 이유를 말하는 화면을 띄우고 직접 입력으로 넘긴다 — 가짜 경로를 그리지 않는다(#160) |
| **산책 통계** | `insight_screen.dart` `InsightScreen` | ✅ 구현완료 | fl_chart 주간 거리 막대(**실제 오늘** 강조), 요약(총거리·횟수·평균), 주간 문구 | 자주 가는 곳은 **항상 빈 상태** — `Walk` 에 장소 축이 없다(계약의 `topPlaces` 도 같다) |
| **커뮤니티 (피드)** | `feed_screen.dart` `FeedScreen` | 🟡 더미 | 카드/리스트 토글, 게시판 필터 시트, 반응 칩, 글 카드/행 | `kPetPosts` 하드코딩. 글쓰기 진입 없음(작성 버튼 미연결) |
| **글 상세** | `post_detail_screen.dart` `PostDetailScreen` | 🟡 더미(로컬 동작) | 본문, 반응 토글(+1/-1), 댓글 스레드, 댓글 입력·추가 | 로컬 state에만 반영(새로고침 시 초기화). 백엔드 미연동 |
| **강아지 프로필** | `me_screen.dart` `MeScreen` | ✅ 구현완료 | 프로필 헤더, 산책 활동 요약(→기록), 메뉴(편집/기록/북마크/로그아웃) | 북마크는 스낵바만(미구현). 로그아웃은 `POST /auth/logout`(전 기기 폐기) 후 로그인 화면으로 — #12 |
| **프로필 편집** | `edit_screen.dart` `EditScreen` | ✅ 구현완료 | 이름·견종·크기·나이(개월)·중성화 편집, 아바타 테두리색, 저장 시 `kMyDog` 갱신 | 앱 재시작 시 초기화(영속 저장 없음), 아바타 이미지 자체는 고정 |
| **산책 기록 작성** | `create_screen.dart` `CreateScreen` | ✅ 구현완료 | 트래킹 초안(거리·시간·경로)을 받아 저장, 초안 없으면 손입력 | 사진 첨부 "곧 지원", 날짜 선택 비동작. 스텝퍼를 **만졌을 때만** 실측값을 덮는다(1분 미만이 사라지지 않게) |
| **내 산책 기록** | `myrecords_screen.dart` `MyRecordsScreen` | ✅ 구현완료 | **전체 기간** 요약, 기록하기 버튼, 산책 카드 리스트(서버 + 전송 대기 뱃지) | 장소 축이 없어 카드 제목은 시작 시각대(새벽/아침/오후/저녁) |
| **위치 찍기** | `pin_picker_screen.dart` `PinPickerScreen` | 🟡 더미 | 스타일라이즈드 지도 탭 → 좌표 기록, pop 반환 | 실지도 아님(장식용 배경). 현재 플로우에서 호출부 없음 |
| **채팅 (방 목록)** | `chat_list_screen.dart` `ChatListScreen` | ✅ 서버 연동 | 방 카드 리스트(이름·태그·마지막 메시지·미읽음 뱃지·멤버 수) — `GET /api/chat/rooms` | 방 만들기는 가족 그룹 생성 경로에 묶여 있고, 그 경로가 앱에 아직 없다 |
| **채팅 (방 안)** | `family_chat_screen.dart` `FamilyChatScreen` | ✅ 서버 연동 | 적응형 폴링(`afterSeq` 델타·ETag), 낙관적 전송 + 같은 멱등키 재전송, 읽음 보고, 신고·가리기·강퇴, 첫 진입 약관 동의 | 메시지 삭제 UI 없음(서버 API 도 없다) |
| **가족** | `family_screen.dart` `FamilyScreen` | ✅ 서버 연동 | 멤버 목록, 초대코드, 오늘의 케어 현황, 산책 주의사항, 채팅 진입 — `FamilyRepository`(#76) | 그룹이 없을 때 **만드는 버튼이 없다**(`POST /api/groups` 호출처 0곳) |

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
| 동물병원 | 🟡 더미 | LOCALDATA(인허가) 연동 예정. 현재 `_dummyVet` 3건 |
| 펫샵 | 🟡 더미 | LOCALDATA 예정. 현재 `_dummyShop` 2건 |
| 산책로 | 🟡 더미 | 두루누비(걷기여행길) 예정. 현재 폴리라인/카드 하드코딩 |
| 지도 SDK | ✅ | `flutter_naver_map`. Client ID(`--dart-define=NAVER_MAP_CLIENT_ID`) 없으면 지도 비활성 |
| 장소 검색 | ❌ 미구현 | 검색창은 플레이스홀더(비동작) |
| 현재 위치 기반 | ✅ 구현완료 | 현위치로 카메라·검색 중심을 잡고, 실패했을 때만 서울시청(37.5665, 126.9816)으로 떨어진다 |

> KTO 서비스키는 **서버 환경변수** `TOUR_API_SECRET` 으로만 존재한다([#40](https://github.com/sanghyunbang/heattrip/issues/40)). 앱은 `GET /api/places/nearby` 만 부르고, 서버가 좌표를 0.02° 격자로 접어 캐시하며 일 1,000콜 한도를 `kto_call_budget` 표가 게이트로 지킨다.
>
> ⚠️ 앱에 남은 유일한 과금성 자격증명이다. `--dart-define` 은 `.env` 에셋 번들링(#29 이전)보다 낫지만 완화일 뿐 — 문자열은 여전히 바이너리 안에 있다. **[#40](https://github.com/sanghyunbang/heattrip/issues/40) 에서 호출을 백엔드 프록시로 옮기면 이 키는 앱에서 완전히 사라진다**(그때 기존 키는 폐기·재발급).

### 3.3 커뮤니티
| 기능 | 상태 | 비고 |
| --- | --- | --- |
| 게시판(전체/산책로후기/동반장소/건강·병원/자유/자랑) | ✅ (더미) | `kPetBoards` 필터 |
| 목록(카드/리스트) | ✅ (더미) | `kPetPosts` |
| 반응(도움돼요/귀여워요/공감) | 🟡 로컬 토글 | 상세에서 +1/-1, 서버 미반영 |
| 댓글 | 🟡 로컬 | 입력·추가되나 화면 벗어나면 초기화 |
| 글쓰기 | ❌ 미구현 | 작성 진입점 없음 |

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
3. **공공데이터 실연동**: 병원/펫샵(LOCALDATA, EPSG:5174→WGS84 변환), 산책로(두루누비 GPX) → 더미 레이어 교체.
4. **백엔드 반려 API + KTO 프록시/캐싱**: 직접 호출 → Spring Boot 프록시(1000콜/일 회피·캐시), 커뮤니티/프로필 CRUD.
5. ~~**로그인**~~: 카카오·구글 소셜 로그인과 `users` 연결은 #11·#12·#14 에서 실었다. 남은 것은 **로그인 사용자에 귀속되는 데이터**(강아지 프로필·산책 기록·커뮤니티 글)의 서버화다.
6. **커뮤니티 글쓰기**: 작성 화면·서버 반영.
7. **채팅 서버화**: 화면 셋(`chat_list_screen`·`family_chat_screen`·`family_screen`)이 이미 있고 탭 3번을 차지하는데 서버가 없다. 방·멤버십·메시지 3테이블 + 폴링 API(M2.5~M2.6). **여기서 `id` 커서를 쓰면 안 된다** — 이유는 [ADR-0011](https://github.com/sanghyunbang/heattrip/issues/72).

> 참조: [ERD](../03-database/erd.md), [외부 데이터 연동](../02-architecture/external-data.md) (경로는 문서 세트 기준, 없으면 생성 예정)

완료: C:/Users/mm206/git_projects/heattrip/docs/05-build/implementation-status.md
