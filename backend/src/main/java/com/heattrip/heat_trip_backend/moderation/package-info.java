/**
 * 신고 — 이슈 #166.
 *
 * <h2>왜 별도 모듈인가</h2>
 * <p>신고 대상이 될 UGC 가 커뮤니티 하나가 아니다. {@code emotion_card}·{@code card_comment}
 * 가 정본에 살아 있고 {@code /api/social/cards} 로 서빙되며, 채팅에는 이미 자기 신고 표가
 * 있다. 신고를 커뮤니티 안에 두면 그 축들을 담을 자리가 없다 — ADR-0016 이 표 이름을
 * {@code community_report} 가 아니라 <b>{@code report}</b> 로 정한 이유가 그것이다.
 *
 * <h2>나가는 참조가 0이다</h2>
 * <p>이 모듈은 어떤 도메인도 부르지 않는다. 스냅샷에 담을 본문·작성자·시각은 <b>부르는
 * 쪽이 만들어서 넘긴다</b> — {@link com.heattrip.heat_trip_backend.moderation.ReportSnapshotInput}.
 * 사용자 id 도 값으로만 들고 {@code users} 로 FK 를 걸지 않는다(15_report.sql 결정 2).
 *
 * <p>그래서 {@code allowedDependencies = {}} 를 붙인다. {@code chat} 이 같은 상황에서 같은
 * 이유로 붙였고, 그쪽 javadoc 이 적어 둔 대로 <b>새 제약이 아니라 이미 지켜지고 있는 것을
 * 애노테이션으로 옮겨 적은 것</b>이다. 다음 사람이 {@code moderation → community} 를 한 줄
 * 넣으면 순환이 생기는데, 그때 잡히는 것이 설계 문장이 아니라 이 검사여야 한다.
 *
 * <h2>거르기도 여기 있다 — 이슈 #681</h2>
 * <p>애플 App Review Guideline <b>1.2 (User-Generated Content)</b> 는 넷을 한 묶음으로
 * 요구한다 — <b>거르기</b> · 신고 · 차단 · 연락처. 셋은 이 모듈과 앱이 이미 들고 있었고
 * 넷째가 없었다. {@link com.heattrip.heat_trip_backend.moderation.ContentFilter} 가 그 하나다.
 *
 * <p>커뮤니티 글·댓글과 채팅 말풍선이 같은 판정을 쓴다. 판정을 각 도메인에 복사하면
 * 한쪽만 낡고, 그때 어느 쪽이 정본인지 아무도 모른다. 이 모듈에 두어도 나가는 참조는
 * 여전히 0이다 — 검사하는 것은 <b>문자열</b>뿐이고, 그것이 글의 제목인지 말풍선인지는
 * 부르는 쪽만 안다.
 *
 * <h2>공개 표면은 이 패키지 <b>바로 아래</b> 타입뿐이다</h2>
 * <p>{@link com.heattrip.heat_trip_backend.moderation.Reports} 가 주고받는 것은
 * {@code ReportSnapshotInput}·{@code ReportReceipt}·{@code ReportReason}·{@code ReportTarget}
 * 이고, {@code entity.*}·{@code repository.*} 는 시그니처에 나오지 않는다. 하위 패키지를
 * 부르면 그것 자체가 모듈 위반이라 기준선이 움직인다(📌 #95 §4).
 *
 * <h2>HTTP 표면은 여기 없다</h2>
 * <p>커뮤니티 신고의 컨트롤러는 {@code community} 에 있다 — 경로가
 * {@code /api/community/posts/{postId}/reports} 이고, 대상이 실재하는지·누가 썼는지를
 * 아는 것이 그쪽이기 때문이다. 이 모듈은 그 사실들을 받아 적기만 한다.
 */
@ApplicationModule(displayName = "Moderation", allowedDependencies = {})
package com.heattrip.heat_trip_backend.moderation;

import org.springframework.modulith.ApplicationModule;
