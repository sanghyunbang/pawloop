package com.heattrip.heat_trip_backend.OAuth.principal;

import com.heattrip.heat_trip_backend.user.ViewerId;

import org.springframework.core.MethodParameter;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.support.WebDataBinderFactory;
import org.springframework.web.context.request.NativeWebRequest;
import org.springframework.web.method.support.HandlerMethodArgumentResolver;
import org.springframework.web.method.support.ModelAndViewContainer;

/**
 * {@code @ViewerId Long} 을 채운다 — 이슈 #223 · ADR-0021.
 *
 * <p>{@link CurrentUserArgumentResolver} 와 같은 자리에서 같은 것을 읽지만 <b>실패가 {@code null}
 * 이다.</b> 인증 없음 · 익명 토큰 · principal 타입이 다른 경우 셋 다 게스트다. 여기가
 * {@link AuthenticatedUser} 를 읽는 유일한 밖의 자리였던 {@code CommunityController.viewerId()}
 * 를 대신한다 — 그래서 그 타입은 다른 모듈에 열리지 않는다.
 *
 * <p>DB 를 읽지 않는다. 필요한 것이 id 뿐이다 — {@code AuthenticatedUser} javadoc 이 같은 이유로
 * 그 타입을 DB 와 떼어 놨다. 탈퇴한 계정의 살아 있는 토큰이면 있지도 않은 id 가 나가는데, 커뮤니티
 * 읽기는 그 id 로 {@code mine} 을 찾을 뿐이라 빈 값이 된다 — 401 을 낼 자리가 아니다.
 */
public class ViewerIdArgumentResolver implements HandlerMethodArgumentResolver {

    @Override
    public boolean supportsParameter(MethodParameter parameter) {
        return parameter.hasParameterAnnotation(ViewerId.class)
                && Long.class.equals(parameter.getParameterType());
    }

    @Override
    public Long resolveArgument(MethodParameter parameter,
                                ModelAndViewContainer mavContainer,
                                NativeWebRequest webRequest,
                                WebDataBinderFactory binderFactory) {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null
                || !(authentication.getPrincipal() instanceof AuthenticatedUser principal)) {
            return null;
        }
        return principal.id();
    }
}
