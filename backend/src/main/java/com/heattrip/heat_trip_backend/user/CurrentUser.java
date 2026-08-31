package com.heattrip.heat_trip_backend.user;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * 현재 요청의 인증된 사용자를 컨트롤러 파라미터로 주입한다. (이슈 #5)
 *
 * <pre>
 *   &#64;GetMapping("/me")
 *   public ResponseEntity&lt;UserResponse&gt; me(&#64;CurrentUser User me) { ... }
 * </pre>
 *
 * <p>주입에 실패하는 모든 경우(인증 없음 · principal 타입 불일치 · 그 id 의 행 없음)는
 * {@link UnauthenticatedException} 이고 <b>본문 없는 401</b> 로 끝난다.
 * 즉 이 애너테이션이 붙은 핸들러의 본문은 사용자가 있다는 전제로만 쓰면 된다.
 *
 * <p><b>속성을 만들지 않는다.</b> {@code required=false} 같은 것을 두면 "인증이 선택인 엔드포인트"라는
 * 개념이 되살아난다. 그건 인가 경계(#23)가 {@code SecurityConfig.publicMatchers} 에서 결정할 일이고,
 * 컨트롤러 파라미터가 결정할 일이 아니다.
 */
/*
 * 이 애노테이션은 원래 {@code OAuth.principal} 에 있었다. 옮긴 이유는 #107 이다.
 *
 * 이것이 붙은 파라미터의 타입은 {@code user.entity.User} 다 — 즉 이 애노테이션이 뜻하는 것은
 * "지금 로그인한 <b>우리 사용자</b>" 이지 "소셜 로그인" 이 아니다. {@code user} 의 어휘다.
 *
 * 그리고 {@code user.controller.AuthController} 가 이것을 쓰느라 {@code user -> OAuth} 화살표를
 * 만들고 있었다. 애노테이션은 인터페이스로 뒤집을 수 없어서, 옮기는 것 말고 방법이 없었다.
 *
 * 값을 채우는 것은 여전히 {@code OAuth.principal.CurrentUserArgumentResolver} 다. 그쪽이
 * {@code user} 를 부르는 것은 남겨 둔 방향이라 문제가 없다.
 */
@Documented
@Target(ElementType.PARAMETER)
@Retention(RetentionPolicy.RUNTIME)
public @interface CurrentUser {
}
