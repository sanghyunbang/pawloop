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
            summary = "로그아웃",
            description = "클라이언트가 저장한 토큰을 지우게 하는 신호입니다. "
                    + "**서버측에는 아직 폐기할 상태가 없습니다** — refresh 토큰도, 액세스 토큰 "
                    + "블록리스트(`jti`)도 구현돼 있지 않아 발급된 accessToken 은 만료까지 유효합니다. "
                    + "실제 폐기는 이슈 #9 범위입니다."
    )
    @ApiResponse(responseCode = "204", description = "로그아웃 성공(본문 없음)")
    @ApiResponse(responseCode = "401", description = "토큰 없음/무효")
    @SecurityRequirement(name = "bearerAuth")   // 자물쇠 표시(인증 필요)
    // 시그니처만. @PostMapping 과 @CurrentUser 는 구현(AuthController) 쪽에 있다 —
    // 인자 해석은 구현 메서드의 파라미터 애너테이션으로 결정된다.
    ResponseEntity<Void> logout(User me);
}
