# 화면 명세 (Screen Spec)

> Pawloop(포루프) 앱의 화면별 상세 명세 — 목적 · 구성요소 · 상호작용 · 데이터. 실제 `app/lib/v2/screens/` 구현 기준으로 작성.

산책을 wedge로 시작하는 반려(강아지) 산책·동반장소·커뮤니티 앱의 현재 구현(감정 도메인 제거 완료)을 화면 단위로 정리한다. 관련 문서: [ERD](../03-database/erd.md), [공개데이터](../02-architecture/external-data.md).

---

## 0. 공통 요소 (전 화면 공통)

| 항목 | 내용 |
| --- | --- |
| 배경 | `AuroraBackground` — 파스텔 오라 그라데이션(라일락 베이스 `#F3E8F9`→`#E4D6F0` + peach/lilac/mint 블롭) |
| 카드 | `GlassCard` — 반투명 흰색 + `BackdropFilter` blur, radius 22(`T.radius`) |
| 시그니처 그라데이션 | 따뜻한 계열 `#FFA96B → #FF7E8A`(warm), 프로필 계열 `#FF9E7D → #D89BFF`(sig) |
| 아이콘 | Fluent Emoji 3D PNG(강아지 아바타 등) + Material `Icons.*` |
| 폰트 | Pretendard |
| 디자인 토큰 | `T`(app_tokens.dart) — textPrimary `#2C2740` / textSecondary `#574F6E` / textMuted `#9B93B3`, lilacTop, radius, cardShadow |
| 상태관리 | `ValueNotifier` + `ValueListenableBuilder`(경량). 전역: `kMyDog`(반려견), `RootTab.index`(탭) |

### 네비게이션 셸 (`main_shell.dart` · `MainShell`)
- **떠 있는 글래스 알약 바텀네비**(하단 오버레이, 배경 위에 항상 표시) + **가운데 솟은 기록(+) 버튼**.
- 탭 5개: **홈(0) · 지도(1) · [산책 FAB] · 커뮤니티(2) · 통계(3)**.
  - 탭 상태: `RootTab.index`(ValueNotifier<int>). 지도 서브뷰: `RootTab.exploreView`('list'|'map').
  - 활성 탭 강조색 accent `#8E7BFF`(굵게 + 색).
- 가운데 FAB(58px, warm→lilac 그라데이션, edit 아이콘): 탭하면 `WalkTrackingScreen`(산책 트래킹)을 push.
- `RootTab.go(context, i)` — 푸시된 라우트를 모두 닫고 지정 탭으로 이동.

> 참고: 프로필/글상세/기록작성/편집/내기록 화면은 탭이 아니라 push 라우트로 열린다(바텀네비 위에 전체화면).

---

## 1. 홈 (`today_screen.dart` · `TodayScreen`)

### 목적
"오늘 우리 아이랑 산책 갈까요?" — 반려견 히어로 + 오늘 산책 요약 + 산책/코스 진입점. 앱 첫 화면.

### 구성요소 (위→아래)
1. **헤더**: 날짜 라벨(`YYYY. MM. DD 요일`, `DateTime.now()` 파생) + `"{강아지 이름}랑\n산책 갈까요?"` 대형 타이틀 + 우측 상단 `ProfileAvatar`.
2. **반려견 히어로**(가운데): 원형 그라데이션(peach) 배경 + 강아지 아바타(`dog.avatarAsset`, 96px) → 이름(23pt) → `{견종} · {나이} · {크기}` 서브텍스트.
3. **오늘 산책 요약 카드**(GlassCard): 3분할 셀 — `{count}회 오늘 산책` / `{km}km 거리` / `{minutes}분 시간`. **현재 0부터 시작**(`WalkToday()` 기본값, 실제 기록 미연동).
4. **CTA 2버튼**: `산책 시작`(flex 3, warm 채움) / `코스 찾기`(flex 2, 흰색 아웃라인).
5. **날씨 카드**(GlassCard): 해 아이콘 + `산책하기 좋은 날씨예요` / `맑음 · 24°C · 미세먼지 보통`. **하드코딩 더미**.

### 상호작용
| 요소 | 동작 |
| --- | --- |
| 산책 시작 | `WalkTrackingScreen` push |
| 코스 찾기 | `RootTab.index.value = 1`(지도 탭 전환) |
| ProfileAvatar | (공통 아바타 위젯) 프로필 진입 |

### 데이터
- `kMyDog`(ValueNotifier<DogProfile>) → 이름·견종·나이·크기·아바타. 편집 화면과 실시간 연동.
- `WalkToday`(count/km/minutes) — 현재 상수 0. 날씨는 하드코딩.

---

## 2. 지도 — 리스트/지도 (`explore_screen.dart` · `ExploreScreen`)

### 목적
"우리 아이랑 갈 수 있는 곳" — 관광공사 반려동물 동반여행(KTO) 장소 + 병원/펫샵/산책로 레이어를 **리스트/지도 토글**과 **카테고리 필터**로 탐색.

### 공통 컨트롤
- **뷰 토글**(`_viewToggle`): `list`(view_agenda) / `map`(map). 활성 시 warm 그라데이션. `initialView`로 진입 뷰 지정(셸의 `RootTab.exploreView`).
- **카테고리 필터 칩**(`_catChips`, 가로 스크롤): `전체` + `kPetCategories` 9종. 활성 칩은 카테고리 색으로 채움.
  - 카테고리: 여행지(12)/카페·식당(39)/레포츠(28)/숙박(32)/쇼핑(38)/문화(14) = KTO contenttypeid, + 병원(vet)/펫샵(shop)/산책로(trail) = 별도 레이어.
- **검색바**: 플레이스홀더만(`카페, 공원, 산책로...`) — **미구현(비활성 표시용)**.

### 리스트 뷰 (`_listView`)
- 타이틀 `지도` + 서브 `우리 아이랑 갈 수 있는 곳` + `ProfileAvatar`.
- 상태별 분기:
  - 로딩 → `CircularProgressIndicator`.
  - `trail` 필터 → **산책로 카드 2개**(더미: 서울숲 강변 2.6km / 중랑천 4.1km, 탭 시 지도 뷰로 전환).
  - 결과 없음 → `_emptyBox`(paw 이미지 + "이 지역엔 등록된 곳이 없어요").
  - 결과 있음 → 헤더(`반려동반 가능 · N곳` 또는 레이어명, 출처 `관광공사`/`공공데이터 (더미)`) + `_placeCard` 목록.
- **장소 카드**(`_placeCard`): 썸네일(firstimage 또는 카테고리색 폴백) + 이름 + 카테고리 태그 + 거리(`near_me`) + 주소. 탭 시 바텀시트.

### 지도 뷰 (`_mapView`)
- **NaverMap**(`flutter_naver_map`): 초기 중심 서울시청(37.5665, 126.9816), zoom 12(min 9 / max 18), 위치버튼 on, ko 로케일.
- 상단 오버레이: 검색바(`이 지역에서 찾기...`, 더미) + 뷰 토글 + ProfileAvatar + 카테고리 칩.
- **마커**(`_refreshMarkers`): 필터된 장소마다 카테고리색 원형 핀(`NOverlayImage.fromWidget`), 탭 시 바텀시트.
  - `trail` 선택 시 → 폴리라인(`_trailCoords`, `#2FB89B`) + 시작 마커 + 카메라 이동.
  - vet/shop 레이어 선택 시 → 더미 데이터 위치로 카메라 이동.
- 좌하단 **범례**(`_legend`): 카테고리 9종 색 도트 목록.
- 로딩 시 상단 "주변 장소 불러오는 중..." 카드.

### 장소 상세 바텀시트 (`_showPlaceSheet`)
- 카테고리색 아이콘 박스 + 이름 + 카테고리 태그 + 거리 + 닫기(X).
- 주소(`place_outlined`) / 전화(`call_outlined`, 있을 때) + `반려동물 동반 가능 (관광공사)` 배지.

### 데이터
- `PetPlacesRepository.fetchNearby(lat, lng, radius:8000, numOfRows:80)` → KTO `locationBasedList2` **직접 호출**(향후 백엔드 프록시 권장). `Env.tourServiceKey` 사용, 응답 `mapx/mapy/contenttypeid/addr1/firstimage/tel/dist`.
- `_dummyVet`(3건) / `_dummyShop`(2건) / `_trailCoords` — **더미 레이어**(실제론 LOCALDATA 인허가 · 두루누비 걷기여행길).
- 필터 로직: `_filtered`(trail→빈배열+폴리라인, vet/shop→더미, null→전체, 그 외→contentTypeId 일치).

---

## 3. 산책 트래킹 (`walk_tracking_screen.dart` · `WalkTrackingScreen`)

### 목적
실시간 GPS 산책 트래킹 화면 — 지도 위 경로 폴리라인 + 라이브 스탯(거리/시간/페이스). **현재 시뮬레이션 더미**(실제 배포 시 geolocator 스트림 → `walk.path` LINESTRING 저장).

### 구성요소
1. **풀스크린 NaverMap**: 초기 중심 더미 루트 시작점(37.5445, 127.0374), zoom 16.
2. **상단 뒤로가기 버튼**(원형, 좌상단): 타이머 취소 후 pop.
3. **하단 라이브 패널**(흰색 라운드 카드):
   - 상태 표시: `산책 기록 중`(핑크 점) / `일시정지됨`(회색) + `실시간 GPS`.
   - **3-스탯**(대형 26pt): `{km}`(km) / `{mm:ss}`(시간) / `{페이스}`(분'초"/km).
   - 컨트롤 2버튼: `일시정지/재개`(토글) / `종료`(warm 그라데이션).

### 상호작용 · 동작 로직
| 요소 | 동작 |
| --- | --- |
| onMapReady | `_start()` — 1초 Timer로 더미 루트(`_makeRoute`, 40점 로브형 루프)를 한 점씩 진행 |
| 매 tick | `_seconds++`, `_km += Haversine 거리`, 경로에 점 추가 → `_drawPath`(폴리라인 `#FF7E8A` + head 마커), 카메라 헤드 추적 |
| 일시정지/재개 | `_paused` 토글(타이머는 유지, tick만 스킵) |
| 종료 | `_finish()` — 타이머 취소 + **완료 바텀시트** |
| 뒤로가기 | 타이머 취소 후 pop |

### 완료 바텀시트 (`_finish`)
- `산책 완료! 🐾` + 3-스탯(시간/거리/페이스).
- `기록 저장하기`(warm) → `CreateScreen(prefillPlace: '오늘 산책')`로 `pushReplacement`.
- `저장 안 함` → 시트 + 화면 pop.

### 데이터
- 로컬 상태만: `_route`(더미 40점), `_path`, `_seconds`, `_km`, `_idx`, `_paused`. 백엔드/영속화 미연동.
- 거리 계산: Haversine(`_dist`), 페이스 = `_seconds / _km` 파생.

---

## 4. 산책 통계 (`insight_screen.dart` · `InsightScreen`)

### 목적
이번 주 산책 활동 요약 + 주간 거리 차트 + 자주 가는 곳. (통계 탭)

### 구성요소
1. **헤더**: `산책 통계` + `우리 아이 활동 기록` + `ProfileAvatar`.
2. **이번 주 요약 카드**(GlassCard): 3분할 — `{총거리}km 총 거리` / `{횟수}회 산책 횟수` / `{평균}km 평균 거리`. 숫자는 warm 그라데이션 텍스트(`ShaderMask`).
3. **주간 거리 막대그래프 카드**(`fl_chart` BarChart):
   - 범례: `오늘`(핑크 점) / `평일`(연보라 사각).
   - 월~일 7개 막대. 오늘(`kWalkTodayIdx=6`, 일)은 warm 그라데이션 + 라벨 강조, 나머지는 연보라(`#8C9E8FE8`).
   - 터치 툴팁: `{요일}요일\n{값} km`. Y축 눈금 4분할, 배경 rod 표시.
4. **자주 가는 곳 카드**(`_topPlacesCard`): `kWalks`의 장소 빈도 상위 3. 순위 뱃지(warm) + 장소명 + `{count}회` 뱃지.

### 상호작용
- 막대 터치 → 툴팁 표시(요일·거리). 그 외 정적 리스트.

### 데이터 (모두 파생/상수)
- `kWeekKm = [2.1, 2.9, 1.2, 0, 1.8, 3.1, 2.4]`(월~일), `kWeekDayLabels`.
- 파생: `_totalKm`(합), `_walkCount`(>0 개수), `_avgKm`, `_maxKm`(축 스케일).
- `_topPlaces` — `kWalks` place 빈도 집계 상위 3.

---

## 5. 커뮤니티 (`feed_screen.dart` · `FeedScreen`)

### 목적
반려인들의 산책·동반장소·건강 이야기 피드. 게시판 필터 + 카드/리스트 토글. (커뮤니티 탭)

### 구성요소
1. **헤더**: `커뮤니티` + 뷰 토글(card/list) + `ProfileAvatar` + 서브 `우리 아이들 이야기`.
2. **게시판 필터 바**(`_boardFilter`): `전체 ▾` 버튼(탭 시 바텀시트) + 우측 `{N}개의 글` 카운트.
   - 바텀시트(`_openBoardSheet`): `kPetBoards` 6종(전체/산책로 후기/동반장소/건강·병원/자유/자랑) Wrap 칩. 선택 시 warm 강조.
3. **피드 리스트**(뷰별 분기):
   - **카드 뷰**(`_card`): 닉 아바타(닉 첫 글자, warm) + 닉 + 날짜 + 보드 칩(보드별 색) + 위치 → 제목 → 본문 3줄 → **반응 칩 3종**(도움돼요/귀여워요/공감 + 카운트) → 구분선 → `댓글 N개 · 자세히 보기`.
   - **리스트 뷰**(`_row`): 아바타 + 제목 1줄 + 보드 칩 + 위치 + 댓글 수(압축).

### 상호작용
| 요소 | 동작 |
| --- | --- |
| 뷰 토글 | `view` card/list 전환 |
| `전체 ▾` | 게시판 선택 바텀시트 |
| 게시판 칩 | `feedBoard` 설정 → 필터링 |
| 카드/행 탭 | `PostDetailScreen(post)` push |

### 데이터
- `kPetPosts`(더미 4건). `PetPost`: nick/board/loc/date/title/body/commentCount/reactions[3].
- 필터: `feedBoard == '전체'` 이거나 `p.board == feedBoard`.
- **더미** — 백엔드 커뮤니티 API 미연동, 작성 기능 없음(피드에 새 글 추가 불가).

---

## 6. 글 상세 (`post_detail_screen.dart` · `PostDetailScreen`)

### 목적
커뮤니티 글 1건 상세 + 반응 토글 + 댓글 스레드/입력.

### 구성요소
1. **헤더**: 뒤로가기 + `산책 이야기`.
2. **글 카드**(`_postCard`): 작성자 아바타(닉 해시 색) + 닉 + 보드 칩 + 위치 + 날짜 → 제목(18pt) → 본문 전문.
3. **반응 버튼 줄**(`_reactionRow`): 3버튼(도움돼요/귀여워요/공감 + 아이콘 + 카운트). 선택 시 warm 채움 + 카운트 ±1.
4. **댓글 섹션**: `댓글 {N}` 헤더 + 댓글 카드 목록(아바타 + 닉 + 본문). 비면 "첫 댓글을 남겨보세요."
5. **하단 입력 바**(`_inputBar`): 텍스트필드(`우리 아이 이야기를 나눠보세요`) + 전송 버튼(원형, warm).

### 상호작용
| 요소 | 동작 |
| --- | --- |
| 반응 버튼 | `_toggleReaction(i)` — 로컬 토글(`_picked`), 카운트 ±1 |
| 댓글 전송 | `_send()` — 빈 값 아니면 `_cmts`에 `('나', 입력)` 추가, 입력 클리어, 키보드 내림 |
| 뒤로가기 | pop |

### 데이터
- `widget.post`(전달받은 `PetPost`).
- 로컬 상태: `_reactions`(초기 post.reactions 복제), `_picked`(선택 집합), `_cmts`(더미 3건 시드 + 사용자 추가).
- **로컬 전용** — 반응/댓글 모두 화면 메모리에만 존재(백엔드 미연동, 새로고침 시 초기화).

---

## 7. 강아지 프로필 (`me_screen.dart` · `MeScreen`)

### 목적
우리 아이(반려견) 프로필 + 산책 활동 요약 + 설정 메뉴. (push 라우트, `내 프로필`)

### 구성요소
1. **헤더**: 뒤로가기 + `내 프로필`.
2. **프로필 헤더**(`_dogHeader`): 원형 peach 그라데이션 + 강아지 아바타(62px) → 이름(21pt) → `{견종} · {나이} · {크기}` → 중성화 시 `중성화 완료` 배지(초록).
3. **산책 활동 요약 카드**(`_statsCard`, 탭 가능): 3분할 — `{kWalks.length}회 총 산책` / `{총거리}km 총 거리` / `{이번주}km 이번주` + 하단 `산책 기록 보기 ›`.
4. **메뉴 카드**(`_menuCard`):
   - 상단 **배너**(`우리 아이 정보 관리` / `견종·나이·크기 수정`, warm) → 편집.
   - 행: `프로필 편집` / `내 산책 기록` / `북마크`(스낵바) / `로그아웃`(빨강, 스낵바).

### 상호작용
| 요소 | 동작 |
| --- | --- |
| 활동 요약 카드 / 내 산책 기록 | `MyRecordsScreen` push |
| 배너 / 프로필 편집 | `EditScreen` push |
| 북마크 | 스낵바 "저장한 장소가 아직 없어요..."(미구현) |
| 로그아웃 | 스낵바 "로그아웃되었습니다"(더미, 실제 인증 없음) |

### 데이터
- `kMyDog`(ValueListenableBuilder) → 프로필 전 항목.
- 파생 집계: `kWalks` 총 거리/횟수, `kWeekKm` 이번주 합.

> 관련 화면 **내 산책 기록**(`myrecords_screen.dart` · `MyRecordsScreen`): 이번 달 요약(총거리/횟수/총시간) + `산책 기록하기` 버튼(→ CreateScreen) + `kWalks` 전체 산책 카드 목록(장소/날짜/거리·시간·페이스/메모).

---

## 8. 프로필 편집 (`edit_screen.dart` · `EditScreen`)

### 목적
반려견 프로필 항목 편집 후 전역 `kMyDog` 갱신.

### 구성요소 (위→아래)
1. **헤더**: 뒤로가기 + `프로필 편집` + 우측 `저장` 버튼(sig 그라데이션).
2. **아바타**(`_avatar`): 원형 peach + 강아지 이미지 + 우하단 pets 배지. 테두리색은 `AppThemeCtl.avatarBorder` 반영.
3. **프로필 테두리 색 피커**(`_borderPicker`): `kAvatarBorders` 색상 원형 스와치, 선택 시 진한 테두리.
4. **입력 필드**: `이름`(텍스트) / `견종`(텍스트, 힌트 "예: 믹스견, 포메라니안").
5. **크기 세그먼트**(`_sizeSegment`): 소형견/중형견/대형견 3분할, 선택 시 sig 채움.
6. **나이 필드**(`_ageField`): 숫자 입력(digitsOnly) + `개월` 접미.
7. **중성화 토글**(`_neuterToggle`): 커스텀 스위치.
8. **저장하기 버튼**(하단, sig).

### 상호작용
| 요소 | 동작 |
| --- | --- |
| 테두리 색 스와치 | `AppThemeCtl.avatarBorder.value` 갱신(전역 아바타 테두리) |
| 크기 세그먼트 | `_size` 선택 |
| 중성화 토글 | `_neutered` 토글 |
| 저장 / 저장하기 | `_save()` |

### 저장 로직 (`_save`)
- 이름/견종은 공백이면 기존값 유지, 나이는 파싱 실패/음수면 기존값 유지.
- `kMyDog.value = copyWith(...)` → 홈/프로필 즉시 반영. 스낵바 "우리 아이 프로필이 저장됐어요" + pop.

### 데이터
- 초기값: `kMyDog.value`(이름/견종/나이(개월)/크기/중성화).
- 컨트롤러: `_name`, `_breed`, `_age`. `DogSize` enum, `bool _neutered`.

---

## 9. 산책 기록 작성 (`create_screen.dart` · `CreateScreen`)

### 목적
산책 1건 기록 작성 — 장소·날짜·거리·시간·사진·메모. 트래킹 완료 / 내 기록 화면에서 진입.

### 구성요소
1. **헤더**: 뒤로가기 + `산책 기록` + 우측 `저장`.
2. **장소·날짜 카드**(`_placeCard`): `어디를 걸었나요?` 장소 입력(place 아이콘, 힌트 "예: 서울숲, 한강공원, 동네 한 바퀴") + `날짜`(오늘 날짜 표시, 선택 UI는 아이콘만 — **미구현**).
3. **거리·시간 스텝퍼 카드**(`_metricsCard`): `얼마나 걸었나요?` — 거리(±0.1km, 0~99) / 시간(±5분, 0~600) `−  값  +`.
4. **사진 카드**(`_photoCard`): `추가` 버튼(스낵바 "사진 첨부는 곧 지원돼요") + 더미 썸네일 2개. **미구현(플레이스홀더)**.
5. **메모 카드**(`_memoCard`): `오늘의 산책` 멀티라인 입력(4줄).
6. **저장하기 버튼**(하단, warm, pets 아이콘).

### 상호작용
| 요소 | 동작 |
| --- | --- |
| 스텝퍼 ± | `km` / `minutes` 증감(clamp) |
| 사진 추가 | 스낵바(미지원 안내) |
| 저장 / 저장하기 | `_save()` — pop + 스낵바 "산책 기록이 저장됐어요 🐾" |

### 데이터
- 로컬 상태: `_place`(prefill 가능, `prefillPlace`), `_memo`, `km`(기본 2.0), `minutes`(기본 30), 날짜 = `DateTime.now()` 파생.
- **영속화 없음** — `_save()`는 스낵바만 표시(백엔드/로컬 저장 미연동). `kWalks`에 추가되지 않음.

---

## 부록 — 화면 · 파일 · 진입 경로 매핑

| 화면 | 파일 | 진입 경로 | 데이터 소스 |
| --- | --- | --- | --- |
| 홈 | `today_screen.dart` | 탭 0 | `kMyDog`, `WalkToday`(0/더미) |
| 지도(리스트·지도) | `explore_screen.dart` | 탭 1 | KTO API(실연동) + vet/shop/trail 더미 |
| 산책 트래킹 | `walk_tracking_screen.dart` | 홈 CTA / 중앙 FAB | 시뮬 더미 경로 |
| 산책 통계 | `insight_screen.dart` | 탭 3 | `kWeekKm`, `kWalks`(상수) |
| 커뮤니티 | `feed_screen.dart` | 탭 2 | `kPetPosts`(더미) |
| 글 상세 | `post_detail_screen.dart` | 커뮤니티 카드 탭 | `PetPost` + 로컬 댓글/반응 |
| 강아지 프로필 | `me_screen.dart` | (push, 프로필 진입) | `kMyDog`, `kWalks` |
| 프로필 편집 | `edit_screen.dart` | 프로필 → 편집 | `kMyDog`(갱신) |
| 산책 기록 작성 | `create_screen.dart` | 트래킹 완료 / 내 기록 | 로컬 상태(미영속) |
| (내 산책 기록) | `myrecords_screen.dart` | 프로필 → 내 산책 기록 | `kWalks`(상수) |

> **미연동/더미 요약**: 로그인·실제 위치(서울 고정)·병원/펫샵/산책로 실데이터·날씨·산책 기록 영속화·커뮤니티 백엔드는 모두 더미 또는 미구현. KTO 반려동반 장소만 실연동.
