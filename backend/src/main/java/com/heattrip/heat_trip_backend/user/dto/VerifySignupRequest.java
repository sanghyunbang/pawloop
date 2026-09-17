package com.heattrip.heat_trip_backend.user.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/** {@code POST /auth/signup/verify} 의 본문 — 이슈 #635. */
@Getter
@Setter
@NoArgsConstructor
public class VerifySignupRequest {

    @NotBlank
    @Email
    private String email;

    /**
     * 메일로 받은 여섯 자리.
     *
     * <p>모양을 여기서 막는 것은 <b>편의가 아니라 보호</b>다. 형식이 틀린 값까지 서비스로
     * 들여보내면 시도 횟수가 오타로 소모되고, 진짜 코드를 넣기 전에 대기 행이 죽는다.
     */
    @NotBlank
    @Pattern(regexp = "^[0-9]{6}$", message = "여섯 자리 숫자입니다.")
    private String code;
}
