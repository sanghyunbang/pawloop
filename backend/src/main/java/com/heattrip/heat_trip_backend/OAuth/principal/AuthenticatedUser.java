package com.heattrip.heat_trip_backend.OAuth.principal;

/**
 * 요청 하나의 인증 주체. {@code JWTAuthenticationFilter} 가 {@code SecurityContext} 의
 * principal 로 넣는 값이다. (이슈 #5)
 *
 * <p><b>DB 를 모른다.</b> 토큰에서 읽을 수 있는 것만 담는다 — 필터는 12개 permitAll 경로에도
 * 전부 걸리므로, 여기서 사용자 행을 로드하면 토큰이 붙어 있는 모든 공개 요청에서 쿼리가 낭비된다.
 * 사용자 엔티티가 필요한 핸들러는 {@link CurrentUser} 를 선언하고, 그때 요청당 한 번만 조회한다.
 *
 * <p><b>{@code id} 가 {@code Long} 인 것이 이 이슈의 재발 방지선이다.</b> principal 을 문자열로
 * 두면 {@code userService.findByEmail(principal)} 이 영원히 컴파일된다 — 그 한 줄이 이 이슈의
 * 버그였다.
 *
 * @param id users 테이블 PK. 토큰의 {@code sub}
 * @param role 토큰의 {@code role} 클레임 (예: {@code ROLE_USER})
 */
public record AuthenticatedUser(Long id, String role) {
}
