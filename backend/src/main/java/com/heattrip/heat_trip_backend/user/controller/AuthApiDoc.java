package com.heattrip.heat_trip_backend.user.controller;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.ResponseEntity;

@Tag(name = "Auth", description = "소셜 로그인 · 토큰 · 내 정보")   // 이 그룹 전체 설명
public interface AuthApiDoc {

    @Operation(
            summary = "로그아웃",
            description = "저장된 refreshToken을 폐기해 더 이상 재발급되지 않게 합니다. "
                    + "accessToken은 만료까지 유효하므로 클라이언트도 토큰을 지워야 합니다."
    )
    @ApiResponse(responseCode = "204", description = "로그아웃 성공(본문 없음)")
    @ApiResponse(responseCode = "401", description = "토큰 없음/무효")
    @SecurityRequirement(name = "bearerAuth")   // 자물쇠 표시(인증 필요)
    ResponseEntity<?> logout(HttpServletRequest request);  // ← 시그니처만. @PostMapping은 여기 X
}