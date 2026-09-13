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
