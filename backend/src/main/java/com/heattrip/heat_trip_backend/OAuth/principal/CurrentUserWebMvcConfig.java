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

    static {
        // springdoc 은 커스텀 리졸버를 모른다. 알려 주지 않으면 @CurrentUser User me 를
        // @ModelAttribute 처럼 보고 **required=true 인 query 파라미터** `me`(스키마는 User 전체)로
        // 문서화한다 — 실측으로 /v3/api-docs 의 오퍼레이션 33개가 그렇게 오염됐다.
        // 런타임은 멀쩡하지만(리졸버가 먼저 잡는다) 깨지는 건 계약이다: Swagger UI 의 Try it out 이
        // 없는 파라미터를 요구하고, openapi-generator 로 뽑은 클라이언트는 33개 시그니처가 틀린다.
        // 손으로 쓴 정본(docs/04-api/openapi.yaml)에는 그 파라미터가 없으므로 정본과 생성본이 갈린다.
        //
        // 여기 한 곳에서 끈다. 대안은 컨트롤러 33곳에 @Parameter(hidden = true) 를 붙이는 것이고,
        // 그건 아홉 번째 컨트롤러에서 다시 빠진다.
        // 정적 초기화인 이유: @Bean 메서드로 두면 springdoc 이 스캔을 시작한 뒤에 실행될 수 있다.
        // 잠그는 테스트: GeneratedOpenApiSpecTest.
        org.springdoc.core.utils.SpringDocUtils.getConfig().addAnnotationsToIgnore(CurrentUser.class);
    }

    private final UserRepository userRepository;

    public CurrentUserWebMvcConfig(UserRepository userRepository) {
        this.userRepository = userRepository;
    }

    @Override
    public void addArgumentResolvers(List<HandlerMethodArgumentResolver> resolvers) {
        resolvers.add(new CurrentUserArgumentResolver(userRepository));
    }
}
