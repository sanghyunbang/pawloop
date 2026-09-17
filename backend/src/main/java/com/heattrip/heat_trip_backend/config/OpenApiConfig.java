package com.heattrip.heat_trip_backend.config;

import io.swagger.v3.oas.annotations.OpenAPIDefinition;
import io.swagger.v3.oas.annotations.info.Info;
import io.swagger.v3.oas.annotations.servers.Server;
import io.swagger.v3.oas.annotations.security.SecurityScheme;
import io.swagger.v3.oas.annotations.enums.SecuritySchemeType;
import org.springframework.context.annotation.Configuration;

/**
 * Swagger UI 가 광고하는 것 — 제목과 <b>서버 주소</b>.
 *
 * <p>여기 적힌 주소는 주석이 아니다. 문서를 연 사람이 "Try it out" 을 누르면 <b>이 주소로</b>
 * 요청이 나간다. 2026-09-18 에 {@code api.heattrip.link} → {@code api.pawloop.app} 으로 옮겼다 —
 * 옛 호스트는 Cloudflare 530 을 주므로, 눌러 본 사람은 서버가 죽은 줄 안다(#682).
 *
 * <p><b>도메인의 정본은 terraform 이다</b> —
 * {@code backend/infra/terraform/envs/prod/backend/terraform.tfvars} 의 {@code domain_name}.
 * 여기는 그것을 따라 적는 자리이므로, 도메인을 옮기면 이 줄도 같이 옮겨야 한다.
 *
 * <p>제목은 계약({@code docs/04-api/openapi.yaml} 의 {@code info.title})과 같아야 한다.
 * 그 파일이 API 계약의 단일 출처이고, 여기가 다르면 같은 API 가 두 이름으로 보인다.
 */
@OpenAPIDefinition(
    info = @Info(title = "Pawloop API", version = "v1",
        description = "포루프(Pawloop) — 반려동물 산책·동반장소·커뮤니티 앱의 REST API. "
            + "계약의 단일 출처는 저장소의 docs/04-api/openapi.yaml 이다."),
    servers = {
        @Server(url = "http://localhost:8080", description = "Local Dev"),
        @Server(url = "https://api.pawloop.app", description = "Production")
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
