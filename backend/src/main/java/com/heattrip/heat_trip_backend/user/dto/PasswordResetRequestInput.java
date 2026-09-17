package com.heattrip.heat_trip_backend.user.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;

import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * {@code POST /auth/password/reset-request} 의 본문 — 이슈 #635 조각 ③.
 *
 * <p>주소 하나뿐이다. <b>응답에는 본문이 없다</b> — 그 주소로 계정이 있는지를 말하지 않는
 * 것이 이 경로의 요점이라, 돌려줄 것이 하나도 없어야 한다.
 */
@Getter
@Setter
@NoArgsConstructor
public class PasswordResetRequestInput {

    @NotBlank
    @Email
    private String email;
}
