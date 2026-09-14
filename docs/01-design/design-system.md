# Pawloop(포루프) 디자인 시스템

> 파스텔 오라 그라데이션 배경 + 반투명 글래스 카드 + 플로팅 산책 FAB를 축으로 한 "따뜻하고 부드러운 반려 산책" UI 시스템. 실제 구현은 `app/lib/v2/theme/`(디자인 토큰·테마)와 `app/lib/v2/widgets/`(공용 위젯)에 있으며, 이 문서는 그 코드를 SSOT로 삼아 정리한다.

관련 문서: [화면/IA](./information-architecture.md) · [ERD](../03-database/erd.md)

---

## 1. 디자인 원칙

| 원칙 | 설명 |
| --- | --- |
| 파스텔 오라 | 진한 UI 대신 은은한 방사형 글로우로 배경을 채워 "따뜻한 산책" 분위기를 만든다. |
| 글래스모피즘 | 콘텐츠는 반투명 흰 카드(`GlassCard`) + `BackdropFilter` 블러로 배경 위에 부드럽게 떠 있게 한다. |
| 경량 상태관리 | `ValueNotifier` + `ValueListenableBuilder`로 테마·탭·프로필을 전역 구독한다(전용 상태관리 라이브러리 미사용). |
| 산책 우선 | 하단 네비 가운데에 솟은 산책 FAB로 핵심 액션(산책 트래킹)을 항상 노출한다. |
| 3D 이모지 | 강아지/발바닥 등 브랜드 아이콘은 Fluent Emoji 3D PNG, 그 외 UI는 Material 아이콘. |

---

## 2. 컬러

색은 `lib/v2/theme/app_tokens.dart`의 `T` 토큰과 `lib/v2/theme/themes.dart`의 배경 테마에서 가져온다. Flutter `Color`의 `0xAARRGGBB`(맨 앞 2자리 = 알파) 표기를 그대로 옮긴다.

### 2.1 텍스트

| 토큰 | 값 | 용도 |
| --- | --- | --- |
| `T.textPrimary` | `#2B2825` | 제목·본문 강조 (웜 차콜) |
| `T.textSecondary` | `#5A544D` | 보조 텍스트·아웃라인 버튼 라벨 |
| `T.textMuted` | `#9A938A` | 비활성 탭·캡션 |
| `T.textFaint` | `#C2BBB1` | 최약 텍스트/플레이스홀더 |

> **2026-09-14 사장님 결정(#447): "배경은 시각적 부담 없는 흰색으로, 색은 버튼이든 외곽선에."** 라일락 바탕·핑크 CTA·보라 회색 글자를 전부 뺐다. 인라인 브랜드 색은 없다 — 전부 `T` 토큰이다.

### 2.2 시그니처 그라데이션 (SIG) · 강조색

브랜드의 "따뜻한 그라데이션". `140deg #FF9E7D → #E04A2B`(피치 → 코랄레드). 핑크·라일락은 없다.

| 토큰 | 값 |
| --- | --- |
| `T.sigStart` | `#FF9E7D` (피치) |
| `T.sigEnd` | `#E04A2B` (코랄레드) |
| `T.sig` | `LinearGradient(begin: (-0.7,-1) → end: (0.7,1))` |
| `T.accent` | `#E04A2B` (코랄레드, 흰 글자 4:1) — 활성 탭 · 선택된 칩 · 선택된 날 · 링크 · 머티리얼 primary. **강조색은 하나** |

아바타 테두리, 머리말의 둥근 버튼(`SigFab`)에 사용. 홈 화면 CTA(`산책 시작`)와 채움 버튼(`PrimaryButton`)은 `T.warm`(`#FF8F4D → #E04A2B`, 주황→코랄레드, 중간색 위 흰 글자 3:1)을 쓴다. 주황 글자·테두리는 `T.warmText`(`#E07A4E`) · `T.warmMid`(`#FF8F63`)다.

### 2.3 글래스 카드 표면

| 토큰 | 값 | 비고 |
| --- | --- | --- |
| `T.cardBg` | `#FFFFFF` | 카드 배경 — 흰 바탕 위라 **외곽선이 카드를 만든다** |
| `T.cardBorder` | `#ECE8E2` | 카드 외곽선 (웜 그레이) |
| `T.line` | `#E4E0DA` | 입력칸 · 구분선 |
| `T.surface` | `#F7F5F2` | 목록 줄 · 칩 바탕 · 비활성 상자 |
| `T.cardShadow` | `#3A342E` α≈0.06, blur 18, y+6 | 아주 옅게 — 선이 만들고 그림자는 거든다 |

`GlassCard` 는 이 토큰을 그대로 쓴다(블러는 남아 있지만 흰 바탕에선 보이지 않는다).

### 2.4 배경 테마 (Aurora)

`kThemes` 6종. 각 테마 = 베이스 상하 그라데이션 2색 + 오라 블롭 3색. **기본 = `화이트`(index 0, 블롭 없음)** — 사장님 결정(#447). 라일락·블루·민트·코랄·모노는 고르기 옵션으로 남는다. 전역 `AppThemeCtl.index`로 전환되어 앱 전체 배경에 반영된다.

| 테마 | baseTop | baseBottom | blob1(좌상) | blob2(우상) | blob3(중하) |
| --- | --- | --- | --- | --- | --- |
| 라일락 | `#F3E8F9` | `#E4D6F0` | `#FFC79E` | `#D4B0FF` | `#9EE2C4` |
| 블루 | `#E8EFFA` | `#DBE3F4` | `#9EC3FF` | `#A8B6FF` | `#9FE0E6` |
| 민트 | `#E6F3EC` | `#D6EAE1` | `#9DE9C9` | `#A8DCF2` | `#DCE9A6` |
| 코랄 | `#FBE9E4` | `#F4DBDD` | `#FFB892` | `#FF9FBE` | `#FFD79A` |
| 모노 | `#EEEFF4` | `#E2E2EC` | `#C7CCDC` | `#D5CBE4` | `#CDE0D9` |

기본 팔레트 토큰: `T.bgTop` / `T.bgBottom` 둘 다 `#FFFFFF`. 오라 블롭 토큰 `T.auroraPeach #FFC79E` / `T.auroraLilac #BFD8F5`(하늘) / `T.auroraMint #9EE2C4` 은 인트로 카드 색조 등에 남아 있다.

### 2.5 프로필 아바타 테두리 (`kAvatarBorders`)

사용자가 고르는 아바타 테두리 색. 전역 `AppThemeCtl.avatarBorder`(기본 라일락 `#8E7BFF`).

| 라일락 | 코랄 | 민트 | 블루 | 핑크 | 옐로 |
| --- | --- | --- | --- | --- | --- |
| `#8E7BFF` | `#FF7A59` | `#33BFA6` | `#5B79F5` | `#FF6B9D` | `#FFC44D` |

### 2.6 카테고리 색 (지도/필터)

`pet.dart`의 `kPetCategories`가 지도·필터·범례가 공유하는 카테고리 색 SSOT. 아홉 색은 서로 RGB 거리 80 이상이고(#328, 테스트가 잠근다) 범례는 색과 아이콘을 함께 그린다.

| 카테고리 | 색 | 카테고리 | 색 |
| --- | --- | --- | --- |
| 여행지 | `#3DBE6C` | 문화 | `#9C6644` |
| 카페·식당 | `#FF6B6B` | 병원 | `#D7263D` |
| 레포츠 | `#F5A623` | 펫샵 | `#D946EF` |
| 숙박 | `#3B82F6` | 산책로 | `#0B7A75` |
| 쇼핑 | `#8B5CF6` | (기타) | `#8E86A8` |

---

## 3. 타이포그래피

- **폰트**: Pretendard (로컬 OTF, `pubspec.yaml`에 5 weight 등록). `google_fonts`는 보조.
- **등록 weight**: Regular 400 / Medium 500 / SemiBold 600 / Bold 700 / ExtraBold 800.
- 제목·수치 강조에는 **w800(ExtraBold)**를 적극 사용하고, 캡션은 w500~w700을 쓴다.

실제 화면(`today_screen.dart`)에서 관찰되는 타입 스케일:

| 역할 | size | weight | 기타 | 예시 |
| --- | --- | --- | --- | --- |
| 히어로 타이틀 | 25 | w800 | height 1.25, letterSpacing -0.5 | "○○랑\n산책 갈까요?" |
| 이름/섹션 헤드 | 23 | w800 | | 강아지 이름 |
| 통계 수치 | 19 | w800 | | "3회 / 1.2km / 25분" |
| 버튼 라벨 | 15 | w700 | | "산책 시작" |
| 카드 타이틀 | 13.5 | w700 | | "산책하기 좋은 날씨예요" |
| 날짜/메타 | 12.5 | w700 | letterSpacing 0.3 | 날짜 라벨 |
| 캡션/서브 | 11.5~13.5 | w500~w600 | 반투명 자주색 | 브리드·요약 라벨 |
| 네비 라벨 | 11 | w500 / w800(활성) | | 홈·지도·커뮤니티·채팅 |

---

## 4. 형태 토큰 (Radius / Elevation / Blur)

| 항목 | 값 | 위치 |
| --- | --- | --- |
| 기본 카드 radius | `T.radius = 22` | `GlassCard` 기본 |
| 폼/입력 카드 radius | 20 | create/edit/me 화면 |
| 버튼 radius | 16 | 홈 CTA |
| 플로팅 네비 알약 radius | 26 | `main_shell` |
| 카드 블러 | `blur(16, 16)` | `GlassCard` `BackdropFilter` |
| 네비 알약 블러 | `blur(22, 22)` | 플로팅 네비 |
| 카드 그림자 | `#5A4682` α0.10, blur 26, y+10 | `T.cardShadow` |
| 네비 알약 그림자 | `#5A4690` α≈0.18, blur 30, y+12 | `main_shell` |
| FAB 그림자 | `#D89BFF` α0.50, blur 22, y+10 | 산책 FAB |

---

## 5. 핵심 컴포넌트

### 5.1 `AuroraBackground` (`widgets/aurora.dart`)

전 화면 공통 배경. 전역 `AppThemeCtl.index`를 `ValueListenableBuilder`로 구독 → 테마 변경 시 앱 전체 배경이 즉시 바뀐다.

- 베이스: `topCenter → bottomCenter` 선형 그라데이션(`baseTop → baseBottom`).
- 오라 블롭 3개: `RadialGradient`로 부드러운 글로우.
  - `(-0.9, -0.95)` r0.95 blob1 α0.50 (좌상)
  - `(1.0, -0.8)` r0.90 blob2 α0.42 (우상)
  - `(0.0, 1.2)` r1.10 blob3 α0.40 (중하)
  - stops `[0.0, 0.78]` → 바깥으로 투명하게 페이드.
- 사용: `AuroraBackground(child: SafeArea(...))` 형태로 `Scaffold.body` 최상단 래핑.

### 5.2 `GlassCard` (`widgets/aurora.dart`)

반투명 흰 글래스 카드. 배경 위 콘텐츠 컨테이너의 기본 단위.

```dart
GlassCard(
  padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 8), // 기본 all(18)
  radius: T.radius, // 기본 22
  child: ...,
)
```

- 구성: `ClipRRect` → `BackdropFilter(blur 16)` → `Container(bg 0xD6FFFFFF, border 0xCCFFFFFF, T.cardShadow)`.
- 파라미터: `child`(필수), `padding`(기본 `all(18)`), `radius`(기본 `T.radius`).

### 5.3 `ProfileAvatar` (`widgets/profile_avatar.dart`)

모든 메인 탭 우상단 공통 프로필 진입 버튼.

- 원형, 그라데이션 `#FFD9C2 → #E9C9FF`(topLeft→bottomRight), 테두리 = 전역 `AppThemeCtl.avatarBorder`.
- 테두리 두께: size≥60 → 3.5, 그 외 2.5. 그림자 = 테두리색 α0.4, blur 12, y+4.
- `size`(기본 38), `tappable`(기본 true → 탭 시 `MeScreen` 푸시).

### 5.4 플로팅 바텀 네비 (`screens/main_shell.dart`) — #446

`MainShell`이 본문 위에 `_ShellNav`를 오버레이(배경 끊김 없이 항상 표시).

- **유리 알약**: `left/right 16`, 최소 높이 66, radius 26. 배경 흰색 88%(`0xE0FFFFFF`) + `T.cardBorder` 외곽선 + 블러 24 + 채도 1.5배(`ColorFilter.matrix`) — 흰 바탕에선 외곽선이 알약을 만들고, 스크롤 밑 콘텐츠가 살짝 비친다. HIG 대로 유리는 이 이동 층에만 쓰고 카드에는 안 쓴다.
- **다섯 칸 전부 같은 폭**(`Expanded`): 홈(`home_rounded`) / 지도(`map_outlined`) / 일정(`event_note_outlined`) / 커뮤니티(`forum_outlined`) / 채팅(`chat_bubble_outline`). 가운데가 일정이라 좌우가 대칭이다.
  - 탭 번호: 홈 0 · 지도 1 · 일정 2 · 커뮤니티 3 · 채팅 4. **산책은 바에 없다** — 사장님 결정(2026-09-14): 일정 탭은 필수이고 가운데 산책까지 두면 여섯이라, 산책은 홈의 "산책 시작" 이 맡는다.
  - 활성 색 `T.accent`, 비활성 `T.textMuted`. 활성 라벨 w800, 비활성 w500. 라벨 배율은 1.3 에서 멈춘다(#396).
  - **채팅 칸의 안 읽음 점**(#452): 안 읽은 방이 하나라도 있으면 아이콘 오른쪽 위에 9dp 점(`T.accent`, 흰 테두리 1.5, `chat-unread-dot`). **개수가 아니라 점** — HIG(탭 바 뱃지는 정말 중요한 것에만). 음소거한 방은 안 센다. `ChatUnread.any` 를 듣고, `ChatUnreadWatcher`(`data/chat_unread.dart`) 가 로그인한 동안 60초마다 · 앱이 앞으로 올 때 `GET /api/chat/rooms` 를 본다. 방 목록 화면도 받을 때마다 같은 답으로 갱신한다.
- 홈 머리말의 날짜 줄과 "오늘 할 일" 줄도 `openSchedule` 로 일정 탭에 간다.
- 탭 상태는 전역 `RootTab.index`(+ `exploreView`)로 관리하며, 푸시된 화면에서도 `RootTab.go(...)`로 탭 전환 가능.

### 5.5 버튼

| 종류 | 형태 |
| --- | --- |
| Primary(채움) | height 54, radius 16, SIG/warm 그라데이션, 흰 텍스트·아이콘, 은은한 그림자 |
| Secondary(아웃라인) | height 54, radius 16, 배경 `0xCCFFFFFF`, 테두리 `0x80FFFFFF`, 라벨 `T.textSecondary` |

아이콘 20px + 8px gap + 라벨(15/w700) 가로 배치.

**코드는 `widgets/form_kit.dart` 다(#445).** `PrimaryButton`(그라데이션 상자 안의 투명한 `FilledButton` — 잉크·포커스·스크린리더가 머티리얼 그대로) · `SecondaryButton`(`OutlinedButton`) · `PickerButton`(날짜·시각처럼 눌러서 고르는 값) · `GlassField`(흰 채움 + `T.line` 테두리, `InputBorder.none`) · `PillChip` · `FormLabel` · `SheetFrame`(바텀시트 틀: 손잡이 · 제목 · 한 줄 설명) · `SigFab`(머리말의 둥근 "새로 적기"). 시트(일정 · 아이 등록 · 크루 만들기·고치기)는 전부 이 부품으로 짠다 — 머티리얼 기본 `OutlineInputBorder` · `OutlinedButton` · 색 없는 `FilledButton` 을 화면에 직접 쓰지 않는다.

### 5.6 칩 / 카테고리 태그

- 지도 필터·범례 칩은 `kPetCategories`의 `(label, color, icon)`을 사용 — 아이콘 + 라벨, 카테고리색을 배경 저채도/테두리·아이콘 강조색으로. 지도 칩 줄의 **순서**는 화면이 정한다(#449): 자주 쓰는 다섯(산책로 · 동물병원 · 카페·식당 · 여행지 · 놀이터)이 먼저, 나머지는 "더보기" 뒤(Google 지도의 More 칩). `kPetCategories` 의 순서는 범례 것이라 건드리지 않는다.
- 알약형(둥근) 형태를 기본으로 하고, 선택 시 해당 카테고리색으로 채운다. 폼 안의 고르기 칩(종류 · 반복 · 아이 · 담당 · 종 · 몸집)은 `form_kit.dart` 의 `PillChip` — 선택되면 `T.accent` 로 채우고 흰 글자다(#445).

### 5.8 커뮤니티 피드 카드 (`screens/feed_screen.dart`) — #451 · #465

한 화면에 글 하나만 꽉 차던 카드(≈750dp)를 Reddit 의 카드 밀도로 줄였다(≈520dp). 규칙:

| 줄 | 규칙 | 근거 |
|:---|:---|:---|
| 사진·영상 | 카드 맨 위, 카드 폭. **세로 사진은 카드에서 1:1 까지**(`PostMediaStrip(minAspect: 1)`), 상세·사진 벽은 4:5 까지. 원본은 전체 보기에서 | Reddit 은 세로 사진도 정사각 근처로 자른다 · HIG 이미지 뷰 |
| 여러 장 | 옆으로 넘기는 **캐러셀** — 첫 장 비율을 전부가 따르고 오른쪽 위 "1/N", 아래 점. 자동 넘김 없음. 영상 장은 포스터 + 재생 표시 | Instagram · Material 3 캐러셀 |
| 작성자 | 아바타 **28** · 닉네임(Flexible) · 동네(1.3배부터 접음) · 날짜(오른쪽 끝). 게시판 칩은 다음 줄에 장소와 함께 — 2.0배·320dp 에서 칩과 날짜가 한 줄에 못 들어간다 | #433 의 접기 규칙 |
| 제목 · 본문 | 제목 2줄, 본문 **2줄** — 나머지는 상세에서 | Reddit · Threads |
| 액션 | **한 줄** — 왼쪽 반응(아이콘 · 이름 · 수, 가로 스크롤, 1.3배부터 이름 접음), 오른쪽 끝 `💬 N ›`. 상자·구분선 없음 | Reddit 액션 바 · #432 넘침 규칙 |
| 여백 | 카드 안 14, 카드 사이 10 | |
| 목록(간단히) 보기 | 오른쪽 56×56 섬네일(첫 장, 영상이면 재생 표시) | Reddit compact |
| 좋아요 | 카드 사진 **두 번 탭 = 귀여워요** — 하트가 사진 위에서 바로 튀고(`LikeBurst`), 집계는 서버 응답으로. 두 번 탭은 켜기만(떼지 않음). 액션 줄의 반응은 누르면 켜고 끔(카드는 안 열림). 벽 타일은 왼쪽 아래 **하트 알약**(두 번 탭 없음 — 열기가 늦어지면 안 된다) | Instagram · #451 4번 |
| 저장 | 액션 줄 오른쪽(댓글 수 앞)의 **책갈피** — 누르면 켜고 끔(멱등 `POST`/`DELETE .../bookmark`, 응답의 상태를 그림). 상세 머리말에도. 모이는 곳은 내 정보 > **저장한 글**(`saved_posts_screen.dart`) — 저장한 순, 사진 글은 벽·글만 있는 글은 한 줄. 세지 않는다 | 반려견 판 "내 사진첩" · Instagram 저장됨 · #451 4번 |
| 아이 사진 | 등록 시트 맨 위의 원형 사진 칸(카메라 배지) · 편집 화면의 아바타를 누르면 바꾸기, 아래 "사진 지우기". 올리기는 글 사진과 같은 두 단계(`POST /media` PROFILE_IMAGE → `PUT /api/dogs/{id}/avatar`). 홈 히어로·내 정보·아이 고르기는 `DogAvatar` — 사진이 있으면 사진, 없으면 종 이모지 | #448 "아이 사진을 히어로로" |
| 아이 사진첩 | 글쓰기의 **"어떤 아이?"** 칩(사진+이름, 새 글은 지금 고른 아이가 기본, 다시 누르면 뺌) → 카드의 게시판 칩 옆 **아이 꼬리표** → 내 정보의 아이 머리 아래 "○○의 사진첩"(사진 벽 + 한 줄, `?dogId=`) | #451 5번 "아이 프로필에 그 아이가 찍힌 사진 격자" |

### 5.9 지도 장소 카드 (`screens/explore_screen.dart`) — #449

지도 탭도 사진 앱이다. 관광공사 사진이 있는 곳은 **사진이 먼저, 카드 폭**:

| 경우 | 카드 | 근거 |
|:---|:---|:---|
| 사진 있음(관광공사 `image`) | **사진 카드** — 맨 위 카드 폭 **16:9**(`AspectRatio`, 못 받으면 같은 자리에 카테고리색 바탕 + 아이콘 — 목록이 흔들리지 않게), 아래 이름 · 카테고리 태그 · 거리 · 요약 · 주소 | AllTrails 코스 카드(사진 → 이름 → 거리) · 16:9 라 한 화면에 두어 곳이 보인다(#465 의 밀도) |
| 사진 없음(병원 · 펫샵 · 산책로 · 놀이터) | 한 줄 카드 — 카테고리 아이콘 64 + 같은 글 묶음 | 사진 없이 카드만 키우면 밀도만 잃는다 |
| 장소 시트 | 사진이 있으면 맨 위 시트 폭 16:9, 내용은 스크롤(작은 화면 · 큰 글자에서 넘치지 않게) | Apple 지도 장소 시트 — 사진이 맨 위 |

### 5.7 통계 차트

- `fl_chart ^1.2` 기반. 통계 화면(`me_screen` 에서 push)에서 주간 산책 막대차트 + 요약.
- 차트 색은 SIG/카테고리 팔레트와 맞춰 글래스 카드 안에 배치.

---

## 6. 아이콘

| 계열 | 용도 | 예 |
| --- | --- | --- |
| Fluent Emoji 3D PNG | 브랜드/캐릭터 강조 | `assets/emoji/dog.png`(강아지 히어로·아바타), `assets/emoji/paw.png`(발바닥) |
| Material Icons (rounded 우선) | UI/네비/카테고리 | `home_rounded`, `map_outlined`, `pets`, `park_rounded`, `route_rounded` 등 |

- 3D 이모지는 `Image.asset(..., gaplessPlayback: true)`로 로드하며 radial 그라데이션 원형 배지 위에 얹는다(홈 히어로 150×150 원 안 96×96 이모지).
- 카테고리 아이콘은 `PetCategory.icon`(Material)으로 지도·필터가 공유한다.
- 보조 아이콘 패키지 `iconsax`도 pubspec에 포함(일부 화면).

---

## 7. 디자인 토큰 요약 (`T`)

`app_tokens.dart`의 `T` 클래스(정적 상수). 신규 UI는 하드코딩 대신 이 토큰을 우선 참조한다.

```dart
// 텍스트
T.textPrimary   // #2B2825
T.textSecondary // #5A544D
T.textMuted     // #9A938A
T.textFaint     // #C2BBB1

// 글래스 카드 · 면 · 선
T.cardBg        // #FFFFFF — 외곽선이 카드를 만든다
T.cardBorder    // #ECE8E2
T.radius        // 22
T.surface       // #F7F5F2 — 목록 줄 · 칩 바탕
T.surfaceBright // #FFFFFF
T.line          // #E4E0DA — 입력칸 · 구분선

// 바탕 (기본 테마 kThemes[0] '화이트' 와 같은 값)
T.bgTop    // #FFFFFF
T.bgBottom // #FFFFFF

// 오라 블롭 · 히어로 글로우
T.auroraPeach // #FFC79E
T.auroraLilac // #BFD8F5 (하늘)
T.auroraMint  // #9EE2C4
T.glowStart   // #FFE7D2 — 아이 히어로 · 로고 뒤 둥근 빛
T.glowEnd     // #FFD0C0

// 강조색 하나 — 활성 탭 · 선택 · 링크 · 머티리얼 primary
T.accent     // #E04A2B (코랄레드)
T.accentSoft // 0x14E04A2B
T.accentLine // 0x33E04A2B

// 시그니처 그라데이션 — 아바타 테두리 · 머리말 둥근 버튼
T.sigStart // #FF9E7D
T.sigEnd   // #E04A2B
T.sig      // LinearGradient (-0.7,-1) → (0.7,1)
T.sigGlow  // 0x40E04A2B

// 따뜻한 그라데이션 — 홈 CTA · 채움 버튼
T.warmStart // #FF8F4D
T.warmEnd   // #E04A2B
T.warm      // LinearGradient (-0.8,-1) → (0.8,1)
T.warmGlow  // 0x40E04A2B
T.warmText  // #E07A4E — "더보기" · 링크 · 선택된 칩 글자
T.warmMid   // #FF8F63 — 선택된 칩 테두리 · 케어 색
T.warmSoft  // 0x1AE04A2B — 따뜻한 칩 바탕

// 그림자 — 흰 바탕이라 아주 옅게
T.cardShadow // #3A342E α0.06, blur 18, y+6
T.barShadow  // 0x1F3A342E — 탭 바
```

**인라인 색은 없다(#447).** 2026-09-13 까지 위 색이 화면마다 `Color(0x…)` 로 166곳 적혀 있었다(주황 글자만 75곳). 지금은 전부 토큰이고, 팔레트를 바꾸는 날은 `app_tokens.dart` 의 값만 바꾼다. 카테고리색·상태색(빨강 오류 · 초록 성공 · 앰버 주의)은 토큰이 아니라 그대로다.

배경 테마(`AppThemeDef` / `kThemes`)·아바타 테두리(`kAvatarBorders`)·카테고리 색(`kPetCategories`)은 각각 `themes.dart` / `pet.dart`에 있으며, `T`와 함께 앱 전체 시각 SSOT를 이룬다.

---

## 8. 사용 가이드 (요약)

1. 화면 `Scaffold.body` 최상단은 항상 `AuroraBackground`로 감싼다.
2. 콘텐츠 블록은 `GlassCard`로, radius/blur/shadow를 재발명하지 않는다.
3. 색·radius·그림자는 `T` 토큰 → `kThemes`/`kPetCategories` 순으로 참조하고, 인라인 하드코딩은 최소화한다.
4. 강조 액션은 SIG 그라데이션(또는 warm 변형), 상태 텍스트는 `T.text*` 위계를 지킨다.
5. 브랜드 아이콘은 Fluent Emoji 3D, 기능 아이콘은 Material(rounded)로 통일한다.
6. 시트·폼은 `widgets/form_kit.dart` 의 부품으로 짠다(#445). 새 시트에 머티리얼 기본 입력칸·버튼을 직접 쓰지 않는다.
7. 유리(`BackdropFilter`)는 이동 층(탭 바)에만, 콘텐츠는 `GlassCard`(약한 블러)로 — HIG "재질"(#446).
8. 목록의 사진은 틀에 맞춘다 — 카드는 1:1, 벽·상세는 4:5 까지. 원본 비율은 전체 보기에서만(#465).

> 미구현/정리 대상: 다크 모드(현재 라이트 파스텔 전용), 접근성 대비(반투명 텍스트 대비 검증), 팔레트 다시 고르기(#447).
