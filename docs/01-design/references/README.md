# 디자인 레퍼런스 캡처

UI/UX 결정을 할 때 근거로 붙인 그림들입니다. **탭별 UI/UX 이슈**(하단 메뉴바 · 홈 · 지도 · 산책 · 커뮤니티 · 채팅 · 일정 · 색 체계)가
이 폴더의 파일을 링크합니다. 2026-09-13 에 "레퍼런스를 찾아 캡처하고 이슈에 탭별로 하나씩 달아
UI/UX 고민이 누적되게 한다" 고 정하고 쌓기 시작했습니다.

- 외부 캡처는 **디자인 연구를 위한 인용**입니다. 저해상도이고, 출처는 아래 표에 전부 적혀 있으며,
  **제품 자산으로는 한 장도 쓰지 않습니다** — 앱 화면에도 스토어 이미지에도 들어가지 않습니다.
  (2026-10-22 에 저장소를 공개로 돌리면서 이 문장을 고쳤습니다. 전에는 "배포물에 넣지 않는다" 고
  적혀 있었는데, 저장소 자체가 공개된 지금은 그 말이 사실과 어긋납니다.)
- 앱스토어 공식 스크린샷은 각 앱의 스토어 페이지에 공개된 마케팅 이미지를 600px 로 받은 것입니다.
- 우리 앱 캡처(`ours-*`)는 에뮬레이터(1080×2400, Medium Phone API 36)에서 찍어 540px 로 줄인 것입니다.

| 파일 | 무엇 | 출처 |
|:---|:---|:---|
| `web-hig-tab-bars.jpg` | Apple HIG — 탭 바. "탭 바는 이동용이지 동작용이 아니다" · 탭 수는 적을수록 · iOS 26 에서 콘텐츠 위에 떠 있는 Liquid Glass | https://developer.apple.com/design/human-interface-guidelines/tab-bars |
| `web-hig-materials.jpg` | Apple HIG — 재질(Liquid Glass). 유리는 **이동 층**(탭 바·툴바)에만, 콘텐츠 층에는 안 쓴다 | https://developer.apple.com/design/human-interface-guidelines/materials |
| `web-hig-color.jpg` | Apple HIG — 색. 강조색은 하나, 콘텐츠가 화려하면 크롬은 단색 | https://developer.apple.com/design/human-interface-guidelines/color |
| `web-m3-navigation-bar.jpg` | Material 3 — 내비게이션 바. 목적지 3~5개 · **같은 폭** · 활성 표시 알약 | https://m3.material.io/components/navigation-bar/guidelines |
| `web-pinterest-ideas-bottom-nav.jpg` | Pinterest 아이디어 "Bottom navigation bar design" 모음 — 가운데 버튼을 둘 때도 좌우 2+2 가 대부분 | https://www.pinterest.com/ideas/bottom-navigation-bar-design/894978120704/ |
| `web-pinterest-ideas-pet-app.jpg` | Pinterest 아이디어 "Pet app UI design" 모음 | https://www.pinterest.com/ideas/pet-app-ui-design/936748503392/ |
| `web-buffer-image-sizes.jpg` | Buffer — 2026 소셜 이미지 크기 가이드. 피드 세로 사진은 **4:5 까지** | https://buffer.com/resources/social-media-image-sizes/ |
| `web-envato-color-2026.jpg` | Envato — 2026 모바일 앱 색 경향. 세이지·샌드·테라코타 같은 중립 자연색 | https://elements.envato.com/learn/color-scheme-trends-in-mobile-app-design |
| `palette-options.png` | 우리 팔레트 후보 셋(A 스톤·세이지 / B 슬레이트·스카이 / C 웜 샌드·테라코타)을 같은 화면으로 그린 것 | 직접 만듦 (`scratchpad/palette_preview.html`) |
| `app-dogpan-1..4.jpg` | 반려견 판 — 사진이 주인공인 피드 · 목록/격자 전환 · 좋아요/댓글/저장/공유 한 줄 · 구독 · 인기 글 | https://apps.apple.com/kr/app/id1299646688 |
| `app-karrot-2..4.jpg` | 당근 — 같은 폭 탭 다섯이 든 떠 있는 유리 바 · 흰 바탕에 강조색 하나(주황) · 검은 "전체" 칩 · 오른쪽 아래 "+ 글쓰기" | https://apps.apple.com/kr/app/id1018769995 |
| `app-instagram-3.jpg` | Instagram — 홈 피드. 같은 폭 다섯 칸, 가운데 + 는 튀어나오지 않는다 | https://apps.apple.com/kr/app/id389801252 |
| `app-pinterest-4.jpg` | Pinterest — 두 열 벽돌(masonry) 격자. 사진이 많이 보이는 화면의 기준 | https://apps.apple.com/kr/app/id429047995 |
| `ours-before-home.jpg` | 우리 앱 홈 — 2026-09-13 상태. 왼쪽 셋 · 오른쪽 둘 · 가운데만 솟은 메뉴바 | 에뮬레이터 |
| `ours-before-community.jpg` | 우리 앱 커뮤니티 — 세로 영상 포스터가 화면을 통째로 먹는다(#440 의 4:5 고침이 아직 안 들어간 빌드) | 에뮬레이터 |
| `ours-before-schedule.jpg` | 우리 앱 일정 — 칩이 제목에 붙고, + 가 "일정 적기" 카드에 겹치고, 전부 라일락 | 에뮬레이터 |

## 수상작 — "아무거나 말고 상 받은 것" (2026-09-13)

앱스토어 공식 스크린샷을 iTunes 검색 API 로 받았습니다(`award-*.jpg`). 출처는 각 앱의 스토어 페이지입니다.

| 파일 | 앱 | 상 | 배운 것 |
|:---|:---|:---|:---|
| `award-focus-friend-1..2.jpg` | Focus Friend (Hank Green) | Google Play **올해의 앱 2025** | 크림·살구 바탕에 귀여운 캐릭터 하나. 색은 적고 캐릭터가 주인공 |
| `award-gentler-streak-1..2.jpg` | Gentler Streak | Apple Design Award 2023 | 코랄→주황 그라데이션 히어로 + 흰 카드. **따뜻한데 핑크가 아니다** — 우리 브랜드 톤의 검증된 예 |
| `award-vocabulary-1..2.jpg` | Vocabulary (Monkey Taps) | ADA 2025 Visuals & Graphics 최종 후보 | 테라코타·틸·크림의 절제된 팔레트, 일관된 일러스트. "조용히 다 맞는 앱" |
| `award-capybara-1.jpg` | Capy — AI Meeting Translator | ADA 2025 Innovation 최종 후보 | 크림 바탕 + 귀여운 카피바라. 복잡한 일을 단순하고 사랑스럽게 |
| `award-crouton-1.jpg` | Crouton | ADA 2024 Interaction 수상 | 화면마다 선명한 단색 바탕(파랑·초록·빨강) — 대담한 색 쓰기 |
| `award-mela-1.jpg` | Mela | ADA 2025 Interaction 최종 후보 | 코랄 바탕에 흰 카드, 사진이 주인공 |
| `award-lumy-2.jpg` | Lumy | ADA 2025 Delight & Fun 최종 후보 | "carefully curated color palette" — 어두운 바탕에 금색 한 점 |
| `award-rooms-2.jpg` | Rooms | ADA 2024 Delight & Fun 수상 | 보라·파랑 위의 복셀 방. 색이 많아도 한 세계로 읽힌다 |
| `award-capwords-1.jpg` | CapWords | ADA 2025 Delight & Fun 수상 | 노랑 한 색 + 스티커. 명랑함은 색의 개수가 아니라 확신에서 온다 |
| `award-denim-1.jpg` | Denim | ADA 2025 Delight & Fun 최종 후보 | 메시 그라데이션 — 우리 오라 배경의 먼 친척 |
| `web-ada-2025.jpg` · `web-ada-2024.jpg` | Apple Design Awards 수상·후보 목록 | — | https://developer.apple.com/design/awards/2025/ · /2024/ |
| `web-play-best-2025.jpg` · `web-play-best-2025-kr.jpg` | Google Play Best of 2025 (세계 · 아시아) | — | https://blog.google/products/google-play/best-apps-games-2025/ |

## 다른 참고 사이트 (2026-09-13: "핀터레스트 외에 UI/UX 참고 사이트를 검색해서 들어가 봐")

검색해서 나온 곳: Mobbin · Refero · Screenlane · Dribbble · Behance · Muzli · UX Archive · Pttrns · Page Flows.
들어가 본 결과 — **Mobbin · Refero · Behance 는 로그인 없이는 거의 안 보입니다**(캡처가 빈 화면). 로그인 없이 볼 수 있는 셋을 캡처했습니다.

| 파일 | 어디 | 쓸모 |
|:---|:---|:---|
| `web-dribbble-pet-app.jpg` | Dribbble "pet app" 검색 | 시각 방향(색·일러스트). 실제 앱이 아니라 콘셉트가 많다 |
| `web-muzli-mobile.jpg` | Muzli 모바일 앱 영감 60+ | 실제 앱 중심의 큐레이션 |
| `web-refero.jpg` | Refero 첫 화면 | 실제 앱 화면·흐름. 로그인하면 검색 가능 — 계정을 만들면 볼 만합니다 |

## 우리 앱 — 메뉴바 고친 뒤 (#446, 2026-09-13)

| 파일 | 무엇 |
|:---|:---|
| `ours-after-home.jpg` | 홈 — 다섯 칸 같은 폭, 산책은 바 안의 둥근 버튼. 날짜 줄에 달력 아이콘(일정 문) |
| `ours-after-community.jpg` | 커뮤니티 — 유리 바 너머로 영상이 비친다(채도 보정). 사진 크기는 #441 이 합쳐져야 4:5 가 된다 |
| `ours-after-schedule.jpg` | 일정 — 홈에서 밀려 들어와 뒤로 가기가 붙었다. 색·간격·+ 는 #453 PR 에서 |

## 우리 앱 — 일정 화면·시트를 폼 부품으로 (#453 · #445, 2026-09-13)

| 파일 | 무엇 |
|:---|:---|
| `ours-after-schedule-2.jpg` | 일정 — 오라 배경 + 반투명 카드, 머리말 오른쪽의 둥근 +, 칩 여백, 칸 비율 1.0, 선택은 강조색 |
| `ours-after-schedule-sheet.jpg` | 일정 적기 시트 — 흰 입력칸 · 날짜/시각 고르기 상자 · 알약 칩 · 그라데이션 저장 |
| `ours-after-crew-sheet.jpg` | 크루 만들기 시트 — 같은 부품. 이름이 비어 있어 만들기가 회색 |

## 팔레트 후보 — 실제 앱 화면 (#447, 2026-09-13)

단색 후보 A·B·C(HTML 그림)는 기각했습니다. 이번엔 토큰 값만 바꿔 **실제로 빌드**해 찍었습니다(`scratchpad/palette_apply.py coral|sky`).

| 파일 | 무엇 |
|:---|:---|
| `palette-candidates-on-device.jpg` | 한 장에 나란히 — 열: 지금(라일락) · 후보 1 크림+코랄 · 후보 2 크림+하늘, 행: 홈 · 일정 · 일정 적기 시트 · 커뮤니티 |
| `palette-now-*.jpg` | 지금 |
| `palette-coral-*.jpg` | 후보 1 — 크림 바탕 · 피치/하늘/민트 오라 · 강조색 코랄 `#F0603F` · CTA 살구→코랄 |
| `palette-sky-*.jpg` | 후보 2 — 같은 바탕 · 강조색 하늘 `#3D8BFD` · CTA 살구→코랄 |

## 결정 — 흰 바탕, 색은 버튼·외곽선에 (#447 · #446, 2026-09-14)

"일정 탭은 필수 — 차라리 걷기를 홈에" · "배경은 시각적 부담 없는 흰색으로 하고, 버튼이든 외곽선에 색을 주는 걸로."

| 파일 | 무엇 |
|:---|:---|
| `ours-white-all.jpg` | 한 장에 — 홈 · 지도 · 일정 · 일정 적기 시트 · 커뮤니티 · 크루 · 채팅 |
| `ours-white-*.jpg` | 각 화면. 흰 바탕 · 외곽선 카드 · 회색 칩 · 강조색 코랄레드 `#E04A2B` 하나 · 채움 버튼 주황→코랄레드. 탭 다섯(홈·지도·일정·커뮤니티·채팅) 같은 폭, 산책은 홈의 "산책 시작" |
| `ours-white-crew-home.jpg` · `ours-white-favor-sheet.jpg` | 크루 홈(품앗이 카드 설명 한 줄) · 부탁 올리기 시트(폼 부품, #445 마지막 조각) | 에뮬레이터 |
| `ours-white-photo-wall.jpg` | 커뮤니티 **사진 벽**(#451 1번) — 격자 보기. 사진·영상 있는 글만 두 열 벽돌, 세로 4:5 는 왼쪽에 하나, 가로 둘은 오른쪽에 | 에뮬레이터 |
| `ours-white-feed-photo-first.jpg` | 커뮤니티 카드 — 사진·영상이 있으면 **사진이 먼저**(#451 2번). 작성자·제목·본문은 그 아래 | 에뮬레이터 |
| `ours-white-compose-photo-first.jpg` | 글쓰기 — 첫 칸이 **사진 · 영상**(#451 3번), 게시판·제목·본문은 그 아래 | 에뮬레이터 |
| `ours-white-home-photo-strip.jpg` · `ours-white-home-strip-more.jpg` | 홈의 **이웃의 사진** 한 줄(#451 6번)과 "더 보기" 로 열린 커뮤니티 사진 벽 | 에뮬레이터 |

## 피드 밀도 · 여러 장 (#451 → 밀도 이슈, 2026-09-14)

"피드도 레딧 같은 거 참고하면 좋을 듯 — 한 화면에 글 하나만 꽉 차는 게 말이 안 된다. 사진 여러 장이나 영상 여러 개면 어떻게 할지 인스타 등 참고해서."

| 파일 | 어디 | 배운 것 |
|:---|:---|:---|
| `app-reddit-3..6.jpg` | Reddit (공식 스크린샷) | 카드 = 제목 → 그림(정사각 근처로 자름) → **한 줄 액션 바**(추천 수 · 댓글 수 · 공유). 여백이 작고 글 사이 구분선. 한 화면에 두세 글 |
| `app-instagram-3.jpg` | Instagram (공식 스크린샷) | 사진 한 장이 한 화면 — 사진이 주인공인 앱의 카드. 여러 장은 옆으로 넘기는 캐러셀, 오른쪽 위 "1/N" 과 아래 점 |
| `app-threads-1.jpg` | Threads (공식 스크린샷) | 글 중심의 촘촘한 피드 — 아바타 작게, 액션은 아이콘 한 줄 |
| `web-m3-carousel.jpg` | Material 3 — 캐러셀 | 여러 장은 가로로 넘기고, 위치는 점·숫자로. 자동 넘김은 안 한다 | 
| `web-hig-image-views.jpg` | Apple HIG — 이미지 뷰 | 그림은 자르지 말고 비율을 지키되, 목록에서는 정해진 틀에 맞춘다 |
| `ours-465-feed-before-after.jpg` | 우리 앱 (#465 뒤) | 예전(카드 약 750dp, 한 화면에 글 하나) → 지금(사진 1:1 · 아바타 28 · 본문 2줄 · 액션 한 줄, 약 530dp). 글만 있는 글은 한 화면에 두세 장 |
| `ours-465-carousel-list-detail.jpg` | 우리 앱 (#465 뒤) | 여러 장은 캐러셀("2/3" 과 점) → 누르면 전체 보기 그 자리 · 목록 보기의 오른쪽 섬네일 · 상세는 4:5 그대로 |
| `ours-451-like.jpg` | 우리 앱 (#451 4번 뒤) | 카드 사진 **두 번 탭 = 귀여워요** — 하트가 사진 위에서 튀고(응답을 안 기다림), 응답이 오면 액션 줄의 하트가 채워진다. 사진 벽 타일은 왼쪽 아래 하트 알약(두 번 탭 없음) |
| `ours-451-bookmark.jpg` | 우리 앱 (#451 4번 뒤) | 카드 액션 줄의 **책갈피**(누르면 저장, "저장했어요 — 내 정보 > 저장한 글") · 상세는 반응 줄 끝의 네모 · 내 정보 메뉴의 "저장한 글" · 저장한 글 화면(저장한 순, 사진 벽) |
| `ours-448-dog-photo.jpg` · `ours-448-dog-photo-edit.jpg` | 우리 앱 (#448 뒤) | 아이 사진 — 홈 히어로가 이모지에서 **사진**으로, 내 정보 머리·아이 줄도 같은 사진, 등록 시트 맨 위 사진 칸. 편집 화면: 아바타(카메라 배지) → 시스템 사진 고르기 → 올린 뒤 "사진 지우기" |
| `ours-451-dog-gallery.jpg` | 우리 앱 (#451 5번 뒤) | 아이 사진첩 — 글쓰기의 **"어떤 아이?"** 칩(사진+이름, 홈에서 고른 아이가 기본, 다시 누르면 뺌) · 카드의 게시판 칩 옆 아이 꼬리표 · 내 프로필 머리 아래 "○○의 사진첩" · 사진첩 화면(그 아이가 찍힌 글이 사진 벽으로, 글만 있는 글은 한 줄, 비어 있으면 "아직 ○○ 사진이 없어요") |
| `ours-449-place-photo.jpg` | 우리 앱 (#449 뒤) | 지도 장소 카드 — 관광공사 사진이 있는 곳은 **사진이 먼저, 카드 폭 16:9**(AllTrails 코스 카드 순서), 사진 없는 공공데이터 층은 한 줄 카드 그대로. 장소 시트는 맨 위에 사진(Apple 지도), 내용은 스크롤 |
| `ours-449-chip-order.jpg` | 우리 앱 (#449 뒤) | 지도 칩 줄 — 전: 열 개가 순서 없이 한 줄(여행지 · 카페 · 레포츠 · 숙박 · 쇼핑…). 후: 자주 쓰는 다섯(산책로 · 동물병원 · 카페·식당 · 여행지 · 놀이터) + "더보기", 펼치면 나머지 + "접기" (Google 지도의 More 칩) |
| `ours-452-unread-dot.jpg` | 우리 앱 (#452 뒤) | 채팅 탭의 **안 읽음 점** — 안 읽은 방이 있으면 탭 아이콘 오른쪽 위에 점 하나(개수 아님, HIG). 방 목록의 개수 뱃지는 그대로. 방을 보고 나오면 꺼진다 |
| `ours-450-walk-photos.jpg` | 우리 앱 (#450 뒤) | 산책 사진 — 산책 중 한 손 기록 줄의 넷째 칸 **사진**(찍은 장수 배지) · 끝내기 시트의 사진 띠 · 저장 화면의 사진 카드 · 기록 상세의 사진 띠. 공유 카드는 첫 장이 배경(위아래 스크림 + 흰 글자) |
| `ours-452-chat-photo.jpg` | 우리 앱 (#452 뒤) | 채팅 말풍선 사진 — 글자 칸 왼쪽 사진 버튼 · 보내는 중(흐린 사진) · 내 사진 말풍선(4:5) · 상대의 사진 말풍선(아바타 · 이름 · 사진) · 방 목록의 "사진" |
| `app-alltrails-1.jpg` | AllTrails(Apple 2023 iPhone App of the Year) 스토어 페이지 — 근처 탐색 목록: 이름 · 거리 · 길이 · 난이도 · 평점 한 줄, 고르는 기준이 칩. 코스 추천 카드의 기준 | https://apps.apple.com/kr/app/id405075943 |
| `app-komoot-1.jpg` | Komoot 스토어 페이지 — 추천 투어 카드에 "왜 이 코스인지" 한 줄과 지도 미리보기 | https://apps.apple.com/kr/app/id447374873 |
| `app-mungkok-1.jpg` | 멍콕(국내 반려 앱) 스토어 페이지 — "추천 코스 따라가기" 는 정적 목록. 우리는 오늘 · 우리 아이 기준이라는 것이 차이 | https://apps.apple.com/kr/app/id6753100529 |
| `strava-routes.jpg` | Strava Stories — Find New Routes Near You: 거리 칩으로 길이를 먼저 정하고 인기(히트맵) 순으로 추천, 이유가 데이터 | https://stories.strava.com/articles/find-new-routes-near-you |
| `strava-athlete-intelligence.jpg` | Strava Stories — Athlete Intelligence(2024-10 공개 베타): 활동 아래 짧은 AI 카드 두세 문장, 베타 라벨, 👍/👎 | https://stories.strava.com/articles/meet-athlete-intelligence-personalized-ai-insights-that-help-you-reach-your |
| `strava-athlete-intelligence-help.jpg` | Strava 도움말 — Athlete Intelligence 가 무엇을 읽고 무엇을 쓰는지(입력은 활동 데이터, 출력은 요약과 제안) | https://support.strava.com/hc/en-us/articles/26786795557005-Athlete-Intelligence-on-Strava |
| `oura-advisor.jpg` | Oura Advisor — 주간 흐름을 대화체로 풀어 주는 AI. 우리는 대화까지 안 가고 두 문장 + 제안 한 줄 | https://ouraring.com/blog/oura-advisor |
| `ours-486-ai-summary.jpg` | 우리 앱 (#486 뒤) | 통계 화면 — 규칙 문장 카드 아래 "AI 요약 · 베타" 카드(두 문장 + 제안), 진짜 모델(gpt-5.6-luna)의 문장 | 에뮬레이터 |
| `ours-452-chat-list-time.jpg` | 우리 앱 (#452 목록 시각 뒤) | 채팅 방 목록 — 제목 줄 오른쪽에 마지막 말의 시각(오늘 HH:mm · 어제 · 9월 12일) | 에뮬레이터 |
| `ours-452-chat-reply.jpg` | 우리 앱 (#452 답장 뒤) | 채팅방 답장 — 길게 눌러 메뉴 첫 줄 "답장" · 입력창 위 인용 띠("OO에게 답장" · 첫 줄 · 닫기) · 보낸 말풍선 안 인용 블록 | 에뮬레이터 |
| `ours-452-quote-jump.jpg` | 우리 앱 (#452 인용 → 원문 뒤) | 채팅 답장의 인용을 누르면 원문까지 올라가 그 줄이 잠깐 코랄로 물들고, 1.4초 뒤 사라진다 | 에뮬레이터 |
| `ours-500-change-feed.jpg` | 우리 앱 (변경 피드 뒤) | 남이 지운 말이 폴링에 따라와 **같은 자리**가 "삭제된 메시지예요" 로 바뀐다 — 방을 다시 열지 않았고 대화 맨 아래로 올라오지도 않는다 | 에뮬레이터 |
| `ours-452-chat-reaction.jpg` | 우리 앱 (반응) | 길게 눌러 고른 다섯 · 말풍선 아래 칩(내가 누른 것은 코랄 테두리) · 남이 누른 반응이 변경 피드로 따라온다 | 에뮬레이터 |
| `ours-486-insight-feedback.jpg` | 우리 앱 (#486 👍/👎 뒤) | 통계 화면 AI 요약 카드 — 꼬리 위 "도움이 됐나요?" 와 엄지 둘, 누르면 코랄 채움 | 에뮬레이터 |
| `ours-341-weekly-reminder.jpg` | 우리 앱 (일요일 저녁 알림 뒤) | 설정 "알림" 절의 주간 정리 카드(끄고 켠 모습)와 실제로 도착한 알림 — 문구에 숫자 · 이름 없음 | 에뮬레이터 |
| `ours-486-insight-async.jpg` | 우리 앱 (모델 호출 비동기화 뒤) | 통계 화면 — 서버가 요약을 만드는 동안의 한 줄 카드 "AI 요약을 만들고 있어요", 4초 뒤 한 번 더 읽어 새 문장으로 | 에뮬레이터 |
| `ours-486-notification-deeplink.jpg` | 우리 앱 (알림 딥링크 뒤) | 도착한 저녁 산책 알림과, 눌렀을 때 쌓인 화면을 닫고 홈으로 가는 모습 | 에뮬레이터 |
| `ours-452-chat-thread.jpg` | 우리 앱 (#452 읽기 흐름 뒤) | 채팅방 — 같은 분의 말은 한 묶음(이름 한 번 · 시각은 마지막) · 날짜 구분선 · 위에서 읽는 중 "새 메시지 N개" 알약 | 에뮬레이터 |
| `ours-483-map-ground.jpg` | 우리 앱 (#483 뒤) | 끝내기 시트 미리보기 · 경로 사진 · 공유 카드의 바닥이 끝내기 순간의 지도 — 선 · 시작/끝 · 순간 표식은 그림 파일이 그린다 | 에뮬레이터 |
| `ours-485-today-course.jpg` | 우리 앱 (#485 뒤) | 홈의 오늘의 코스 카드 — 규칙으로 고른 하나 · 이유 한 줄 · 다른 코스 · 여기서 산책 시작 → 트래킹 → 기록 저장하기의 장소 칸에 코스 이름 | 에뮬레이터 |
| `ours-585-home-before.jpg` | 우리 앱 (#585 전) | 홈 — 아이 둘이 **같은 얼굴 둘**로 선다. 사진을 안 올린 집은 이름을 읽기 전에는 못 가른다 | 에뮬레이터 |
| `ours-585-picker.jpg` | 우리 앱 (#585 뒤) | 편집 화면의 "사진이 없을 때의 얼굴" — 맨 앞 `기본`(종류 그림) + 얼굴 열셋, 고른 칸은 코랄 테두리 | 에뮬레이터 |
| `ours-585-preview.jpg` | 우리 앱 (#585 뒤) | 얼굴을 고르면 **저장 전에** 위의 큰 아바타가 그 자리에서 바뀐다 | 에뮬레이터 |
| `ours-585-home-after.jpg` | 우리 앱 (#585 뒤) | 홈 — 보리(푸들) · 뭉치(기본)로 갈린다. 사진 없이 이름을 안 읽고도 가려진다 | 에뮬레이터 |
| `ours-585-two-faces.jpg` | 우리 앱 (#585 뒤) | 사진 없는 아이 둘이 **서로 다른 얼굴**로 — 보리(푸들) · 뭉치(누렁이). 고른 얼굴은 집 것이라 다른 식구 화면에도 그대로다 | 에뮬레이터 |
| `ours-585-photo-cleared.jpg` | 우리 앱 (#585 뒤) | 사진을 지우면 **"고르기 전" 이 아니라 고른 얼굴**로 돌아간다 — 그래서 두 값이 한 칸을 안 나눠 쓴다 | 에뮬레이터 |
| `hig-charts.jpg` | Apple HIG — Charts: 숫자 카드(막대 · 목표 대비)가 근거이고 글은 그 아래의 해석 | https://developer.apple.com/design/human-interface-guidelines/charts |
