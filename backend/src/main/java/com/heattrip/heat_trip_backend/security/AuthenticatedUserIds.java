package com.heattrip.heat_trip_backend.security;

/**
 * 지금 요청의 인증 주체 id 를 주는 자리 — 이슈 #660.
 *
 * <h2>왜 인터페이스인가</h2>
 *
 * <p>principal 타입({@code OAuth.principal.AuthenticatedUser})을 여기서 직접 부르면
 * <b>{@code security -> OAuth} 간선</b>이 새로 생긴다. 그건 #106 이 일부러 끊은 방향이고,
 * {@code ChatRateLimitFilter} 도 같은 이유로 그 타입을 안 부른다.
 *
 * <p>그래서 방향을 뒤집는다 — 필요한 쪽이 선언하고 {@code OAuth} 가 구현한다. {@code ViewerId}(#223)
 * 가 내린 결론과 같다: <b>열어야 하는 것은 타입이 아니라 "보는 사람의 id 를 주는 자리"</b> 다.
 * {@code @ViewerId} 는 컨트롤러 파라미터용이라 필터에서는 쓸 수 없어서, 필터 쪽 짝으로 이것을 둔다.
 *
 * <p>{@code Authentication#getName()} 으로 때우지 않는 이유: 그 문자열은 principal 의
 * {@code toString()} 이라 {@code AuthenticatedUser[id=7, role=ROLE_USER]} 같은 모양이다.
 * 레이트리밋처럼 "같으면 같다" 만 필요한 자리에는 충분하지만, <b>동의를 조회하려면 진짜 id</b> 가
 * 있어야 한다. 그 문자열을 파싱하는 것은 모양이 바뀌는 날 조용히 틀린다.
 */
public interface AuthenticatedUserIds {

    /**
     * 지금 요청의 {@code users.id}. 토큰이 없거나 인증되지 않았으면 {@code null}.
     *
     * <p>{@code null} 을 예외로 바꾸지 않는다 — 인증이 <b>선택</b>인 경로가 실제로 있고
     * ({@code PublicPaths}), 그 요청도 이 자리를 지난다.
     */
    Long ofCurrentRequest();
}
