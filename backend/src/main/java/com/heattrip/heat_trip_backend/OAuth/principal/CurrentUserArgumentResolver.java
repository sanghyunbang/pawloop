package com.heattrip.heat_trip_backend.OAuth.principal;

import org.springframework.core.MethodParameter;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.support.WebDataBinderFactory;
import org.springframework.web.context.request.NativeWebRequest;
import org.springframework.web.method.support.HandlerMethodArgumentResolver;
import org.springframework.web.method.support.ModelAndViewContainer;

import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

/**
 * {@link CurrentUser} 가 붙은 {@link User} 파라미터를 채운다 — 인증 주체 해석의 <b>유일한</b> 지점이다. (이슈 #5)
 *
 * <p>예전에는 컨트롤러 8곳이 각자 Authorization 헤더를 다시 읽고 토큰을 파싱하고
 * {@code findByEmail} 을 했다. 규약이 바뀌면 8곳을 모두 고쳐야 했고, 실제로 #7 이 저장 구조를
 * 바꿨을 때 아무도 고치지 않아 모든 소셜 계정에서 프로필 조회가 400 이었다.
 *
 * <p>DB 조회는 여기서만, 요청당 최대 1회다. 필터가 아니라 여기인 이유는 필터가 12개 permitAll
 * 경로에도 전부 걸리기 때문이다. 순비용은 0 이다 — 예전에도 소비처 전부가 요청당
 * {@code findByEmail} 을 한 번씩 했다. 캐시는 두지 않는다(탈퇴·role 변경이 즉시 반영돼야 한다).
 */
public class CurrentUserArgumentResolver implements HandlerMethodArgumentResolver {

    private final UserRepository userRepository;

    public CurrentUserArgumentResolver(UserRepository userRepository) {
        this.userRepository = userRepository;
    }

    @Override
    public boolean supportsParameter(MethodParameter parameter) {
        return parameter.hasParameterAnnotation(CurrentUser.class)
                && User.class.isAssignableFrom(parameter.getParameterType());
    }

    @Override
    public User resolveArgument(MethodParameter parameter,
                                ModelAndViewContainer mavContainer,
                                NativeWebRequest webRequest,
                                WebDataBinderFactory binderFactory) {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();

        // principal 이 AuthenticatedUser 가 아닌 경우: 인증 없음, 익명 토큰, 그리고 누군가
        // 필터의 principal 타입을 되돌린 경우. 셋 다 401 이다.
        if (authentication == null || !(authentication.getPrincipal() instanceof AuthenticatedUser principal)) {
            throw new UnauthenticatedException();
        }

        // 서명도 형식도 멀쩡한데 그 id 의 행이 없다 = 탈퇴한 계정의 아직 살아 있는 토큰.
        // null 을 돌려주면 컨트롤러에서 NPE → 500 이 된다. 반드시 던진다.
        return userRepository.findById(principal.id())
                .orElseThrow(UnauthenticatedException::new);
    }
}
