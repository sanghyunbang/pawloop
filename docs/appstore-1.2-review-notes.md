# App Store 심사 답변 — Guideline 1.2 (초안)

> 초안입니다. 운영자 도구(#718)와 채팅 차단 처리 결정이 끝나면 5번과 4번의 채팅 문장을 확정합니다.
> 붙여넣을 곳 두 군데: 심사 메시지 답장 · `앱 심사 정보` → `메모`(메모 칸은 4,000자 제한 — 아래 영어 본문은 약 3,000자).

─── 여기부터 붙여넣기 ───

Thank you for the review. Build 2.0.0 (4) addresses each point of Guideline 1.2.

**1. Terms (EULA) agreed before sign-in**
The login screen now has a required checkbox, "이용약관과 개인정보처리방침에 동의합니다" (I agree to the Terms of Service and the Privacy Policy), above the Kakao, Google and Apple buttons. Until it is checked, tapping a sign-in button does not start sign-in; it only says what is missing. Both document names open the full text. Article 6 of the Terms states that we have no tolerance for objectionable content or abusive users: obscene, violent, hateful or discriminatory content, harassment and spam are prohibited, every report is reviewed within 24 hours, violating content is deleted and its author is suspended or terminated. The same zero-tolerance line is printed under the checkbox.

**2. Filtering objectionable content**
Posts, comments and chat messages pass a server-side filter before they are stored. Text containing listed objectionable words is rejected and never shown to anyone.

**3. Flagging**
Every post and comment written by another user has "신고" (Report). In chat, long-press another user's message. The user picks a reason; we store the report with a snapshot of the content.

**4. Blocking**
Every post and comment written by another user now has a separate "차단" (Block) button next to "신고". After one confirmation, everything that user wrote disappears at once from the community feed, place pages, saved posts and photo albums. It is removed, not collapsed, and our server stops returning that user's posts and comments to the blocker. Every block also notifies us immediately (see 5).
[CHAT — 결정 후 확정]

**5. Acting on reports within 24 hours**
Each report and each block sends an alert to our moderation channel at the moment it is filed. We review every report within 24 hours. When content violates the Terms, we delete it for everyone and suspend the author's account. [#718 확정 후 — suspended 계정이 무엇을 못 하는지 한 줄]

**6. Contact**
Settings → "문의 · 신고" (Contact / Report) shows our support email.

**Screen recording** (physical iPhone 17, iOS 26): [VIDEO_LINK]
It shows, in order: launching the app, the login screen with the Terms checkbox (sign-in does not start until it is checked), opening the Terms, signing in, reporting another user's post, blocking that user, and that user's posts disappearing from the feed.

**Correction to our previous note.** We wrote that no AI service is used. Our server now uses OpenAI to write an optional one-paragraph weekly walk summary. It receives only aggregate walk numbers (weekly distance, count and minutes, time-of-day counts) and the dog's size and age range, never a name, email, location, place or note. This is disclosed in our Privacy Policy.

─── 여기까지 ───
