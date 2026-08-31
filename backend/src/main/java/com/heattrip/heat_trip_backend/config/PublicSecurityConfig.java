package com.heattrip.heat_trip_backend.config;

import com.heattrip.heat_trip_backend.OAuth.OAuthSecurityProperties;
import com.heattrip.heat_trip_backend.security.RateLimitProperties;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Configuration;

@Configuration
@EnableConfigurationProperties({
        PublicSecurityProperties.class,
        OAuthSecurityProperties.class,
        RateLimitProperties.class})
public class PublicSecurityConfig {
}
