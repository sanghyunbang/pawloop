# App Store 심사 답변 문안 (Guideline 2.1 — Information Needed)

2026-09-18 반려에 대한 답변입니다. **두 군데에 같은 내용을 넣습니다.**

1. **심사 메시지 답장** — App Store Connect → 앱 → `메시지` (Resolution Center)
2. **`앱 심사 정보` → `메모`** — 버전 페이지. 다음 제출부터 계속 남습니다

아래 `─── 여기부터 붙여넣기 ───` 부터 끝까지 그대로 복사하면 됩니다. 영어입니다 — 심사자가 읽는 글이라서요.

영상 링크는 이미 채워져 있습니다 — `https://youtu.be/pW9TUA8Wov8`
(일부 공개 · 로그인 안 한 브라우저에서 재생되는 것을 확인했습니다).

---

─── 여기부터 붙여넣기 ───

Thank you for the review. Below are answers to each of the six items, in order.

**1. Screen recording**

https://youtu.be/pW9TUA8Wov8

Recorded on a physical iPhone 17 running iOS 26, from the current build. It starts from launching the app and covers, in order: the first-run introduction, the device-permission notice, Sign in with Apple (this creates the account), the required consent screen, dog registration, choosing a neighborhood, recording a walk with GPS, logging pee/poop/water and taking a photo during the walk, saving the walk record, viewing the saved records, writing a community post with a photo, reporting and blocking another user's post, and finally deleting the account.

Two notes on what you will see:

- **The walk in the recording was made indoors over about 20 seconds, so almost no GPS distance accumulated (0.0 km).** Walk tracking requires actual outdoor movement. The timer, the live map, the activity logging, the in-walk photo and saving the record are all shown working.
- **After blocking, the blocked user's post appears in the community list as a collapsed row** reading "가린 사람의 글입니다 · 눌러서 보기" (This post is from someone you hid · tap to view). Neither its photo, title nor body is shown. A normal post is visible directly above it for comparison.

**2. Purpose and target audience**

Pawloop is a dog-walking companion app for dog owners in South Korea.

The problem it solves: a daily walk leaves no trace. Owners cannot tell how far their dog actually walked this week, where nearby dog-friendly places and animal hospitals are, or whether today's weather and air quality are safe for a walk. When several family members share one dog, nobody knows who already walked or fed the dog today.

What Pawloop provides: it records each walk by GPS (distance, time, route, and one-tap logging of pee, poop and water), keeps the records as weekly statistics, shows nearby dog-friendly places, animal hospitals and walking trails drawn from Korean government open data, shows a walk-safety index from the national weather and air-quality feeds, lets family members share one dog's care log, and provides a neighborhood community feed and group chat.

Target audience: dog owners in South Korea. Rated 13+ because of the user-generated community.

**3. Setting up and accessing the main features**

*Login credentials — please read this first.*

The app has no email/password sign-up, so we cannot create a demo account for you. Authentication is social login only: Sign in with Apple, Google, and Kakao.

**Please use "Apple로 계속하기" (Continue with Apple) with your own Apple ID.** Sign in with Apple is fully implemented and works from any region. A first sign-in creates the account; there is no separate registration step.

You may also tap "그냥 둘러보기" (Just browse) on the login screen to enter the app without an account, but walk recording, posting, reporting and chat all require login.

*The app's interface is Korean only.* Here is what to tap:

1. Launch the app. Three introduction slides — tap "다음" (Next), then "시작하기" (Start). You may tap "건너뛰기" (Skip).
2. A device-permission notice screen — tap "확인했어요" (Got it).
3. Login screen — tap the black button "Apple로 계속하기" (Continue with Apple).
4. **Consent screen (required, cannot be skipped).** Tap "전체 동의 (선택 항목 포함)" (Agree to all, including optional) at the top, then the button at the bottom "동의하고 시작하기" (Agree and start). The four required items are: age 14 or over, Terms of Service, Privacy Policy, and Location-Based Services Terms. Marketing is optional and can be left unchecked.
5. Onboarding — tap "우리 아이 등록하기" (Register my dog), enter any name, or tap "나중에 할래요" (Later) to skip.
6. When iOS asks for location, please tap Allow. Walk recording needs it.

*Main features and where to find them:*

- **Record a walk** — Home tab, the large orange button "산책 시작" (Start walk). Walk for a moment, then "종료" (Finish) and "기록 저장하기" (Save record).
- **See your walks and statistics** — on the Home screen, at the bottom of the first card: "내 산책 기록" (My walk records) and "산책 통계" (Walk statistics).
- **Map of dog-friendly places** — the "지도" (Map) tab, second in the bottom bar. Toggle list/map at the top right. Filter chips: 산책로 (trails), 동물병원 (animal hospitals), 카페·식당 (cafes/restaurants).
- **Community (user-generated content)** — the "커뮤니티" tab, fourth in the bottom bar. "글쓰기" (Write) opens the composer; "사진 추가" (Add photo) attaches an image.
- **Reporting and blocking** — open any post written by another user, tap "신고" (Report) at the top right, choose a reason, and tick "이 사람의 메시지를 가리기" (Hide this person) to block them. In chat, long-press another person's message for the same options. Prohibited content is also rejected by a server-side word filter before it is posted, and the Terms of Service (Article 6) list prohibited conduct. Our contact address for reports is shown in Settings under "문의 · 신고" (Contact / Report), and we act on reports within 24 hours.
- **Account deletion** — tap the round profile avatar at the **top right of the Home screen** → "설정" (Settings) → "회원 탈퇴" (Delete account) → "정말로 탈퇴하기" (Delete my account) → confirm in the dialog.

*Two behaviours worth stating explicitly, because they are deliberate:*

- **Blocking hides the blocked user's content from the blocker only.** It does not remove the content for everyone. Removing content globally is handled through the report flow and operator review, not by blocking.
- **Deleting an account permanently removes the user record, their dogs, all walk records, bookmarks and all sign-in tokens.** Community posts and comments the user wrote remain, with the author anonymized to "알 수 없음" (Unknown). We keep them because deleting them would also destroy other users' comments on those threads and any evidence attached to reports filed about them. The deletion screen states this to the user before they confirm.

**4. External services used**

Authentication
- Sign in with Apple
- Google OAuth 2.0
- Kakao Login (a Korean identity provider)

Maps
- NAVER Maps SDK (NAVER Corp., Korea)

Data providers — all from the Korean government open-data portal (data.go.kr), called from our own server, never from the app:
- Korea Tourism Organization — pet-friendly travel information
- Korea Tourism Organization — national tourism information
- Korea Tourism Organization — Durunubi walking-trail information
- Ministry of the Interior and Safety — registered animal hospitals
- Ministry of the Interior and Safety — registered animal-sales businesses
- Korea Meteorological Administration — ultra-short-term weather observations
- AirKorea (Korea Environment Corporation) — air-quality monitoring stations
- AirKorea (Korea Environment Corporation) — air-pollution measurements

Infrastructure
- Amazon Web Services — EC2, S3 and CloudFront (photo and video storage and delivery)
- Cloudflare (DNS and proxy for our API domain)
- Google Fonts (fonts.gstatic.com) — the app downloads one Korean webfont at runtime

Not used, explicitly:
- **No payment processor, no in-app purchase, no external purchase. The app is free and has no paid content or features.**
- No advertising SDK, no analytics SDK, no attribution SDK.
- No AI or machine-learning service. Our server contains disabled code for an optional text summary; it is switched off in production and no AI provider is called by this build.

**5. Regional differences**

Yes — the app's content is region-specific, and we want to be explicit about it rather than claim it works the same everywhere.

Pawloop is built for South Korea. Every place-based feature draws on Korean government open data: walking trails, dog-friendly venues, animal hospitals, weather observations and air-quality readings all exist only for Korean coordinates. The administrative-district list used for "my neighborhood" contains Korean districts only. The interface is Korean; there is no other localization.

Outside Korea, the core GPS walk recording (distance, time, route, statistics) works normally, because it depends only on the device's own GPS. The place-based features have no data to show, and the app says so on screen rather than showing a broken list. Without an account, the map deliberately does not use your location at all and states that it is showing the Seoul City Hall area.

There is no code that enables or disables features by country — the difference is in the data, not in the build.

The app is distributed in South Korea.

**6. Regulated industry and third-party material**

Pawloop does not operate in a regulated industry. It is not a medical, health, financial, gambling or dating app. It records walks and shows public place information; it makes no medical or veterinary claims and provides no diagnosis, treatment or medication guidance. The "animal hospital" feature is a directory of publicly registered businesses, not a medical service.

Third-party material used, and our authorization for it:

- **Korean government open data.** All eight datasets listed in item 4 are obtained through the Korean government's public data portal (data.go.kr) under approved API usage applications held by the developer, and are published under Korea Open Government License (KOGL) terms that permit commercial use with attribution. Attribution is shown in the app on the relevant screens.
- **Administrative district boundaries** from Statistics Korea's SGIS, published under KOGL Type 1, redistributed under CC BY 4.0. Attribution is shown on the neighborhood-selection screen.
- **NAVER Maps SDK**, used under NAVER Cloud Platform's developer terms with a registered application for this app's bundle identifier.
- **User-generated content** is owned by the users who post it; our Terms of Service grant us only the licence needed to display it in the service.

The app contains no third-party copyrighted media, no licensed characters, no music and no third-party trademarks.

One clarification about location data, since it affects the privacy label: **the app never transmits GPS coordinates to our servers.** Walk routes are computed and kept on the device. The only location-derived values that leave the device are the administrative district code the user picks for "my neighborhood" (stored on the account), and a 5 km weather grid number sent without authentication and cached by grid only. This is why our App Privacy declaration lists Coarse Location rather than Precise Location.

─── 여기까지 ───

---

## 한국어 요지 (붙여넣지 마세요 — 보내기 전 확인용)

| 질문 | 답의 핵심 |
|---|---|
| 1 영상 | 실기기 녹화 + **실내 촬영이라 거리가 0인 이유**와 **차단된 글이 접혀 보이는 것**을 미리 설명 |
| 2 목적 | 한국 반려인용 산책 기록 앱 |
| 3 접근법 | **데모 계정 없음.** 심사자 본인 Apple ID 로. 한국어 전용이라 버튼 이름을 다 적음 + **차단은 본인만 · 탈퇴해도 글은 남는 이유** |
| 4 외부 서비스 | 인증 셋 · 네이버 지도 · 공공데이터 여덟 · AWS/Cloudflare/구글폰트. **결제·광고·분석·AI 전부 없음** |
| 5 지역차 | **있다고 솔직히.** 한국 데이터 전용, 한국어 전용. 밖에서도 GPS 산책 기록은 됨 |
| 6 규제·저작권 | 규제 산업 아님 + **좌표를 서버로 안 보낸다**는 설명(개인정보 라벨과 앞뒤 맞춤) |

### 사실 근거 (전부 확인함)

- AI 안 적음 — 운영 컨테이너 `OPENAI_API_KEY` 길이 0, `SPRING_AI_MODEL_CHAT` 비어 있음
- 푸시 안 적음 — 서버에만 있고 앱 `pubspec.yaml` 에 firebase 0건
- 결제 없음 — 앱에 `in_app_purchase`·StoreKit 0, 서버에 PG 참조 0
- 좌표 미전송 — `LocationUploadPolicy` 가 관문이고 테스트가 지킴. 날씨는 5km 격자만, 인증 없이, 격자 번호로만 캐시
- 탈퇴 동작 — `users` 행 삭제(hard), `dog`·`walk` CASCADE, `post`·`comment`·`reaction` SET NULL
- 차단 한 방향 — `BlockRepository.findBlockedIdsOf(blockerUserId)`
- 원스토어에도 같은 사실로 신고: `위치 정보 예 · 서버 미전송`

### 아직 남은 것

- **[#707](https://github.com/sanghyunbang/pawloop/issues/707) — 신고를 운영자가 보는 수단이 없습니다.** 위 3번에 "24시간 안에 처리한다" 고 적었으니, 최소한 신고가 들어오면 알림이 오게 붙여야 합니다. 안 그러면 적어 놓고 못 지킵니다
- 밖에서 2분 걷는 짧은 클립을 따로 찍어 링크를 하나 더 주면 1번이 더 단단해집니다 (선택)
