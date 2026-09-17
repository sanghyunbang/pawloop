package com.heattrip.heat_trip_backend.OAuth.principal;

import com.heattrip.heat_trip_backend.security.AuthenticatedUserIds;

import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;

/**
 * {@link AuthenticatedUserIds} 의 구현 — {@code SecurityContext} 의 principal 에서 id 를 꺼낸다.
 * 이슈 #660.
 *
 * <p>{@code CurrentUserArgumentResolver}·{@code ViewerIdArgumentResolver} 와 같은 방식이다 —
 * principal 이 {@link AuthenticatedUser} 인지 보고 거기서 {@code id} 를 읽는다. 이름(문자열)으로
 * 사용자를 다시 찾지 않는다. 그 한 줄이 #5 의 버그였다.
 *
 * <p><b>이 클래스가 {@code OAuth} 쪽에 있는 것이 요점이다.</b> principal 타입을 아는 것은 그것을
 * 만든 모듈이어야 하고, 부르는 쪽({@code security})은 인터페이스만 안다.
 */
@Component
public class SecurityContextUserIds implements AuthenticatedUserIds {

    @Override
    public Long ofCurrentRequest() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || !authentication.isAuthenticated()) {
            return null;
        }
        return authentication.getPrincipal() instanceof AuthenticatedUser user ? user.id() : null;
    }
}
