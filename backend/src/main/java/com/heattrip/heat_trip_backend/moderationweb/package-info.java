/**
 * 가리기의 HTTP 표면 — 이슈 #166.
 *
 * <h2>왜 얇은 층이 따로 있나</h2>
 * <p>{@code chatweb} 과 같은 이유다 — <b>인증 주체 해석</b> 때문이다. {@code moderation} 은
 * 나가는 참조가 0이어야 하는데({@code allowedDependencies = {}}) 컨트롤러는
 * {@code @CurrentUser User} 가 필요하다. 그 예외를 {@code moderation} 에 여는 대신 층을
 * 얇게 얹는 쪽을 골랐다.
 *
 * <p>여기 있는 것은 컨트롤러와 요청 record 뿐이다. 판단은 전부
 * {@link com.heattrip.heat_trip_backend.moderation.Blocks} 가 한다.
 *
 * <h2>신고는 왜 여기 없나</h2>
 * <p>신고 경로는 {@code /api/community/posts/{postId}/reports} 라 <b>대상이 실재하는지·누가
 * 썼는지를 아는 쪽</b>이 받아야 한다. 그래서 {@code community} 에 있다. 가리기는 대상이
 * 사람 하나뿐이고 그 실재조차 확인하지 않으므로(컨트롤러 javadoc) 여기서 끝난다.
 */
@ApplicationModule(
        displayName = "Moderation Web Adapter",
        allowedDependencies = { "moderation", "user", "user :: entity" })
package com.heattrip.heat_trip_backend.moderationweb;

import org.springframework.modulith.ApplicationModule;
