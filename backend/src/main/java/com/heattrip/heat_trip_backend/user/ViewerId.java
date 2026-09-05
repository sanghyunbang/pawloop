package com.heattrip.heat_trip_backend.user;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * 인증이 <b>선택</b>인 핸들러에서 "보는 사람" 의 {@code users.id} 를 받는다 — 이슈 #223 · ADR-0021.
 *
 * <pre>
 *   &#64;GetMapping("/posts")
 *   public PostPageResponse feed(&#64;ViewerId Long viewerId, ...) { ... }
 * </pre>
 *
 * <p>로그인했으면 그 사람의 id, 아니면 <b>{@code null}</b> 이다. {@link CurrentUser} 와 반대다 —
 * 그쪽은 주입 실패가 전부 401 이고 게스트를 받지 않는다. 그래서 둘을 한 애노테이션의 속성으로
 * 합치지 않았다({@code CurrentUser} javadoc: "{@code required=false} 같은 것을 두면 '인증이
 * 선택인 엔드포인트' 라는 개념이 되살아난다"). 인증이 선택인 엔드포인트는 <b>이 애노테이션이
 * 붙은 자리</b>로만 존재한다 — 어느 핸들러가 게스트를 받는지 grep 한 번으로 셀 수 있다.
 *
 * <p><b>왜 타입이 {@code Long} 인가.</b> 필요한 것은 "누구인가" 뿐이고, 그것도 사용자 행이 아니라
 * id 다. 커뮤니티 읽기 셋은 게스트에게도 같은 목록을 주고 로그인한 사람에게만 {@code mine} 을
 * 채우는데, 그 판정에 사용자 행은 필요 없다 — 행을 올리면 permitAll 경로마다 쿼리가 낭비된다.
 * 그리고 {@code AuthenticatedUser} 타입 자체를 다른 모듈에 열지 않아도 된다 — 열어야 하는 것은
 * 타입이 아니라 <b>"보는 사람의 id 를 주는 자리"</b> 였다(#223 의 결론).
 *
 * <p><b>만료 토큰도 {@code null} 이다.</b> {@code JWTAuthenticationFilter} 는 깨진 토큰을 조용히
 * 무시하므로 401 이 아니라 게스트로 떨어진다. 앱은 401 에서만 토큰을 갱신하니 창은 "앱을 켠 뒤
 * 읽기만 만지는 한 세션" 이고, 다시 켜면 {@code GET /auth/me} 가 401 을 준다(ADR-0016 결정 3).
 *
 * <p>값을 채우는 것은 {@code OAuth.principal.ViewerIdArgumentResolver} 다. 이 애노테이션이
 * {@code CurrentUser} 와 같은 패키지에 있는 이유도 같다(#107) — 애노테이션은 인터페이스로 뒤집을
 * 수 없어서 부르는 쪽의 모듈에 둔다.
 *
 * <p>springdoc 은 이 애노테이션을 무시하도록 등록돼 있다({@code CurrentUserWebMvcConfig}).
 * 안 그러면 생성 계약에 {@code viewerId} 가 query 파라미터로 새어 나온다 —
 * {@code GeneratedOpenApiSpecTest} 가 그것을 잠근다.
 */
@Documented
@Target(ElementType.PARAMETER)
@Retention(RetentionPolicy.RUNTIME)
public @interface ViewerId {
}
