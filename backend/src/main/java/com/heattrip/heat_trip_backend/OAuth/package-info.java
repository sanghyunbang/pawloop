/**
 * 인증 — OAuth2 로그인, JWT 발급·검증, 현재 사용자 해석.
 *
 * <h2>읽을 때 주의 — {@code OAuth.user} 는 {@code user} 모듈이 아니다</h2>
 * <p>이 패키지 안에 {@code OAuth/user/} 라는 하위 패키지가 있다. 구조 검사 리포트에
 * {@code OAuth.user.…} 와 {@code user.…} 가 나란히 찍히면 <b>사람이 헷갈린다.</b>
 * 도구는 정확히 구분한다 — 모듈은 최상위 패키지 단위이므로 {@code OAuth.user} 는
 * {@code OAuth} 모듈의 내부이고 {@code user} 모듈과 아무 관계가 없다.
 * 헷갈리는 것은 이름뿐이라 지금 바꾸지 않는다(#95 §10).
 *
 * <h2>공개 표면</h2>
 * <p>이 모듈의 공개 표면은 <b>{@code principal} 하나뿐</b>이고, 그것도 패키지째가 아니라
 * 타입 하나다 — {@code CurrentUser} 에 {@code @NamedInterface("principal")} 이 붙어 있다.
 *
 * <p>{@code UnauthenticatedException} 은 <b>여기 없다.</b> #107 에서 {@code user} 로 옮겼다 —
 * {@code user} 의 서비스 둘이 그것을 던지느라 {@code user -> OAuth} 순환을 만들고 있었다.
 *
 * <p>패키지째 열지 않은 이유: {@code OAuth.principal} 에는 파일이 다섯인데 밖에서 쓰는 것은
 * 둘뿐이었다. 나머지 셋({@code AuthenticatedUser} · {@code CurrentUserArgumentResolver} ·
 * {@code CurrentUserWebMvcConfig})은 이 모듈 안의 배선이라 열 이유가 없었다.
 *
 * <p><b>그 중 {@code AuthenticatedUser} 는 이제 밖에서 부른다.</b> (#170) 커뮤니티 읽기
 * 셋이 <b>인증이 선택</b>이라 {@code CurrentUser} 로는 못 받고 principal 을 직접 읽는다 —
 * {@code community.controller.CommunityController.viewerId()} 한 자리, 참조 2건이다.
 * 열지 않았으므로 <b>그 둘은 위반으로 남아 있고</b> 기준선이 232 에서 234 로 올라갔다.
 * 덮지 않고 남겨 두는 것이 #104 의 방식이다. 열지 말지는 #223 에서 정한다.
 *
 * <p>{@code jwt} · {@code handler} · {@code code} · {@code state} · {@code service} 는
 * <b>열지 않는다.</b> 지금 그것들을 부르는 곳이 있고 그건 위반으로 남아 있다 — 덮지 않고
 * 남겨 두는 것이 #104 의 결정이다. {@code config} 와 얽힌 순환은 #106, {@code user} 와의
 * 순환은 #107 이 다룬다.
 */
package com.heattrip.heat_trip_backend.OAuth;
