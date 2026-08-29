package com.heattrip.heat_trip_backend.config;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Configuration;

@Configuration
@EnableConfigurationProperties({PublicSecurityProperties.class, OAuthSecurityProperties.class})
public class PublicSecurityConfig {
}
