package com.heattrip.heat_trip_backend.OAuth.principal;

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
@Documented
@Target(ElementType.PARAMETER)
@Retention(RetentionPolicy.RUNTIME)
public @interface CurrentUser {
}
