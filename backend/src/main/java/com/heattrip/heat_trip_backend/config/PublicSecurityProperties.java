package com.heattrip.heat_trip_backend.config;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * 공개 표면·CORS 설정 — {@code app.security.*}.
 *
 * <p><b>레이트리밋 설정은 여기 없다.</b> {@code security.RateLimitProperties} 로 옮겼다 (#106).
 * 원래 이 클래스의 중첩 클래스였는데, 그러면 {@code security.ApiRateLimitFilter} 가
 * {@code config} 를 알아야 하고 {@code config.SecurityConfig} 는 필터 체인을 조립하려고
 * {@code security} 를 안다 — <b>양쪽이 서로를 아는 순환</b>이었다.
 *
 * <p>방향을 하나로 정했다: <b>조립하는 쪽이 조립되는 쪽을 안다.</b> 설정은 그것을 쓰는 모듈
 * 안에 둔다. 설정 키({@code app.security.rate-limit.*})와 환경변수는 한 글자도 안 바뀌었다.
 */
@Getter
@Setter
@ConfigurationProperties(prefix = "app.security")
public class PublicSecurityProperties {

    private boolean docsPublic = false;
    private String allowedOrigins = "http://localhost:8080,http://10.0.2.2:8080";
}
