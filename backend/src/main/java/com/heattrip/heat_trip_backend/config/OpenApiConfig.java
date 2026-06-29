package com.heattrip.heat_trip_backend.config;

import io.swagger.v3.oas.annotations.OpenAPIDefinition;
import io.swagger.v3.oas.annotations.info.Info;
import io.swagger.v3.oas.annotations.servers.Server;
import io.swagger.v3.oas.annotations.security.SecurityScheme;
import io.swagger.v3.oas.annotations.enums.SecuritySchemeType;
import org.springframework.context.annotation.Configuration;

@OpenAPIDefinition(
    info = @Info(title = "HeatTrip API", version = "v1",
        description = "Media upload/read/replace/delete and related endpoints"),
    servers = {
        @Server(url = "http://localhost:8080", description = "Local Dev"),
        @Server(url = "https://api.heattrip.link", description = "Production")
    }
)
@SecurityScheme(
    name = "bearerAuth",
    type = SecuritySchemeType.HTTP,
    scheme = "bearer",
    bearerFormat = "JWT"
)
@Configuration
public class OpenApiConfig { }
