/**
 * 사용자 — 계정 · 세션 토큰 원장 · 프로필.
 *
 * <h2>이 모듈은 아무도 부르지 않는다</h2>
 * <p>{@code allowedDependencies = {}} 는 <b>빈 배열</b>이고 속성을 안 쓴 것과 다르다.
 * 안 쓰면 "제한 없음", 빈 배열은 "다른 모듈을 하나도 못 부른다" 이다. 여기는 후자다.
 *
 * <p>#107 이전에는 {@code OAuth} 를 일곱 번 불렀고, {@code OAuth} 는 이 모듈을 열 번 불렀다.
 * 저장소에 마지막으로 남아 있던 순환이 그것이다. 셋으로 끊었다.
 * <ul>
 *   <li>{@code service.AccessTokenIssuer} — 토큰 발급을 <b>포트로 뒤집었다.</b>
 *       {@code OAuth.jwt.JWTProvider} 가 그것을 구현한다.</li>
 *   <li>{@code UnauthenticatedException} · {@code CurrentUser} — <b>이 모듈로 옮겼다.</b>
 *       둘 다 "우리 사용자" 의 어휘이지 "소셜 로그인" 의 어휘가 아니다.</li>
 *   <li>{@code /auth/oauth/*} 두 경로 — {@code OAuth.controller.OAuthLoginController} 로
 *       <b>분리했다.</b> {@code /auth/signup} · {@code /auth/login} 은 여기 그대로 있다.</li>
 * </ul>
 *
 * <h2>방향을 이쪽으로 정한 이유</h2>
 * <p>{@code OAuth} 는 외부 신원을 우리 사용자로 바꾸는 <b>번역 층</b>이라 {@code user} 를 아는
 * 것이 자연스럽다. 반대로 {@code user} 가 토큰을 어떻게 만드는지 아는 것은 우연한 결합이다.
 * 그리고 {@code user.entity.User} 는 밖의 파일 34개가 부르는 공용 어휘다 — 모두가 부르는
 * 타입을 가진 모듈이 남을 부르지 않는 쪽이 옳다.
 *
 * <h2>공개 표면</h2>
 * <p>패키지 <b>루트</b>에 {@code CurrentUser} 와 {@code UnauthenticatedException} 이 있다 —
 * 루트는 그 자체로 공개 표면이라 별도 선언이 필요 없다. 그와 별개로
 * {@code entity.User} 에 {@code @NamedInterface("entity")} 가 붙어 있다(#105).
 * <b>둘은 따로 열어야 한다</b> — 부르는 쪽이 {@code "user"} 만 적으면 {@code User} 를 못 부른다.
 *
 * <p>{@code repository} · {@code dto} · {@code service} 는 열지 않았다. 밖에서 그것들을 부르는
 * 곳이 아직 있고, 그건 위반으로 남아 있다 — 덮지 않는 것이 #105 의 결정이다.
 */
@ApplicationModule(displayName = "User", allowedDependencies = {})
package com.heattrip.heat_trip_backend.user;

import org.springframework.modulith.ApplicationModule;
