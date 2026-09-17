package com.heattrip.heat_trip_backend.user.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;

import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/** {@code POST /auth/signup/resend} 의 본문 — 이슈 #635. */
@Getter
@Setter
@NoArgsConstructor
public class ResendSignupCodeRequest {

    @NotBlank
    @Email
    private String email;
}
