# 디자인 레퍼런스 캡처 (내부 참고용)

UI/UX 이슈에 붙이는 그림들입니다. **탭별 UI/UX 이슈**(하단 메뉴바 · 홈 · 지도 · 산책 · 커뮤니티 · 채팅 · 일정 · 색 체계)가
이 폴더의 파일을 링크합니다. 사장님이 2026-09-13 에 "핀터레스트 등 UI 사이트에서 레퍼런스를 찾아 캡처하고,
이슈에 탭별로 하나씩 달아 UI/UX 고민이 누적되게 하라" 고 하셔서 만들었습니다.

- 외부 캡처는 **참고용**이고 배포물에 넣지 않습니다. 출처는 아래 표에 있습니다.
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

## 수상작 — "아무거나 말고 상 받은 것" (사장님 2026-09-13)

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

## 다른 참고 사이트 (사장님 2026-09-13: "핀터레스트 외에 UI/UX 참고 사이트를 검색해서 들어가 봐")

검색해서 나온 곳: Mobbin · Refero · Screenlane · Dribbble · Behance · Muzli · UX Archive · Pttrns · Page Flows.
들어가 본 결과 — **Mobbin · Refero · Behance 는 로그인 없이는 거의 안 보입니다**(캡처가 빈 화면). 로그인 없이 볼 수 있는 셋을 캡처했습니다.

| 파일 | 어디 | 쓸모 |
|:---|:---|:---|
| `web-dribbble-pet-app.jpg` | Dribbble "pet app" 검색 | 시각 방향(색·일러스트). 실제 앱이 아니라 콘셉트가 많다 |
| `web-muzli-mobile.jpg` | Muzli 모바일 앱 영감 60+ | 실제 앱 중심의 큐레이션 |
| `web-refero.jpg` | Refero 첫 화면 | 실제 앱 화면·흐름. 로그인하면 검색 가능 — 사장님 계정으로 볼 만합니다 |

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

단색 후보 A·B·C(HTML 그림)는 사장님이 기각하셨습니다. 이번엔 토큰 값만 바꿔 **실제로 빌드**해 찍었습니다(`scratchpad/palette_apply.py coral|sky`).

| 파일 | 무엇 |
|:---|:---|
| `palette-candidates-on-device.jpg` | 한 장에 나란히 — 열: 지금(라일락) · 후보 1 크림+코랄 · 후보 2 크림+하늘, 행: 홈 · 일정 · 일정 적기 시트 · 커뮤니티 |
| `palette-now-*.jpg` | 지금 |
| `palette-coral-*.jpg` | 후보 1 — 크림 바탕 · 피치/하늘/민트 오라 · 강조색 코랄 `#F0603F` · CTA 살구→코랄 |
| `palette-sky-*.jpg` | 후보 2 — 같은 바탕 · 강조색 하늘 `#3D8BFD` · CTA 살구→코랄 |

## 결정 — 흰 바탕, 색은 버튼·외곽선에 (#447 · #446, 2026-09-14)

사장님: "일정 탭은 필수 — 차라리 걷기를 홈에" · "배경은 시각적 부담 없는 흰색으로 하고, 버튼이든 외곽선에 색을 주는 걸로."

| 파일 | 무엇 |
|:---|:---|
| `ours-white-all.jpg` | 한 장에 — 홈 · 지도 · 일정 · 일정 적기 시트 · 커뮤니티 · 크루 · 채팅 |
| `ours-white-*.jpg` | 각 화면. 흰 바탕 · 외곽선 카드 · 회색 칩 · 강조색 코랄레드 `#E04A2B` 하나 · 채움 버튼 주황→코랄레드. 탭 다섯(홈·지도·일정·커뮤니티·채팅) 같은 폭, 산책은 홈의 "산책 시작" |
| `ours-white-crew-home.jpg` · `ours-white-favor-sheet.jpg` | 크루 홈(품앗이 카드 설명 한 줄) · 부탁 올리기 시트(폼 부품, #445 마지막 조각) | 에뮬레이터 |
| `ours-white-photo-wall.jpg` | 커뮤니티 **사진 벽**(#451 1번) — 격자 보기. 사진·영상 있는 글만 두 열 벽돌, 세로 4:5 는 왼쪽에 하나, 가로 둘은 오른쪽에 | 에뮬레이터 |
| `ours-white-feed-photo-first.jpg` | 커뮤니티 카드 — 사진·영상이 있으면 **사진이 먼저**(#451 2번). 작성자·제목·본문은 그 아래 | 에뮬레이터 |
| `ours-white-compose-photo-first.jpg` | 글쓰기 — 첫 칸이 **사진 · 영상**(#451 3번), 게시판·제목·본문은 그 아래 | 에뮬레이터 |
| `ours-white-home-photo-strip.jpg` · `ours-white-home-strip-more.jpg` | 홈의 **이웃의 사진** 한 줄(#451 6번)과 "더 보기" 로 열린 커뮤니티 사진 벽 | 에뮬레이터 |
