package com.heattrip.heat_trip_backend.user.controller;

import com.heattrip.heat_trip_backend.user.entity.User;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.ResponseEntity;

@Tag(name = "Auth", description = "소셜 로그인 · 토큰 · 내 정보")   // 이 그룹 전체 설명
public interface AuthApiDoc {

    @Operation(
            summary = "로그아웃(전 기기)",
            description = "Authorization 헤더의 액세스 토큰으로 주체를 식별해 그 사용자의 "
                    + "**서버측 세션(refresh 토큰)을 전부 폐기합니다**(이슈 #9). "
                    + "특정 기기 하나만 끊는 요청 본문은 정의하지 않습니다. 멱등입니다 — "
                    + "이미 폐기된 상태여도 204 입니다. "
                    + "다만 **이미 발급된 accessToken 은 만료(≤1시간)까지 유효합니다** — "
                    + "토큰 단위 무효화(`jti` 블록리스트)는 이 이슈의 범위가 아닙니다. "
                    + "그러므로 클라이언트는 저장한 토큰을 반드시 스스로 삭제해야 합니다."
    )
    @ApiResponse(responseCode = "204", description = "로그아웃 성공(본문 없음)")
    @ApiResponse(responseCode = "401", description = "토큰 없음/무효")
    @SecurityRequirement(name = "bearerAuth")   // 자물쇠 표시(인증 필요)
    // 시그니처만. @PostMapping 과 @CurrentUser 는 구현(AuthController) 쪽에 있다 —
    // 인자 해석은 구현 메서드의 파라미터 애너테이션으로 결정된다.
    ResponseEntity<Void> logout(User me);
}
