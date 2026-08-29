package com.heattrip.heat_trip_backend.OAuth.principal;

import java.util.List;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.method.support.HandlerMethodArgumentResolver;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

import com.heattrip.heat_trip_backend.user.repository.UserRepository;

/**
 * {@link CurrentUserArgumentResolver} 를 Spring MVC 에 등록한다. (이슈 #5)
 *
 * <p>리포지토리를 필요로 하는 쪽이 여기인 이유: {@code JWTAuthenticationFilter} 는 계속
 * {@code SecurityConfig} 에서 {@code new} 로 만든다. 저장소 주입 때문에 필터를 빈으로 바꾸면
 * {@code ApiRateLimitFilter} 와 같은 함정에 빠진다 — 그 필터는 {@code @Component} 이면서
 * {@code SecurityConfig} 로도 등록돼 서블릿 체인에 이중 등록돼 있다.
 */
@Configuration
public class CurrentUserWebMvcConfig implements WebMvcConfigurer {

    private final UserRepository userRepository;

    public CurrentUserWebMvcConfig(UserRepository userRepository) {
        this.userRepository = userRepository;
    }

    @Override
    public void addArgumentResolvers(List<HandlerMethodArgumentResolver> resolvers) {
        resolvers.add(new CurrentUserArgumentResolver(userRepository));
    }
}
