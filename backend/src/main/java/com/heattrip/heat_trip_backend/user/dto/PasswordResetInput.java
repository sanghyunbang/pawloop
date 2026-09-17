package com.heattrip.heat_trip_backend.user.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/** {@code POST /auth/password/reset} 의 본문 — 이슈 #635 조각 ③. */
@Getter
@Setter
@NoArgsConstructor
public class PasswordResetInput {

    @NotBlank
    @Email
    private String email;

    /**
     * 메일로 받은 여섯 자리.
     *
     * <p>모양을 여기서 막는 것은 <b>편의가 아니라 보호</b>다. 형식이 틀린 값까지 서비스로
     * 들여보내면 시도 횟수가 오타로 소모되고, 진짜 코드를 넣기 전에 재설정이 죽는다.
     */
    @NotBlank
    @Pattern(regexp = "^[0-9]{6}$", message = "여섯 자리 숫자입니다.")
    private String code;

    /**
     * 새 비밀번호.
     *
     * <p><b>가입보다 더 조이지 않는다.</b> 가입에는 길이 규칙이 없어서, 여기에만 하한을 두면
     * 그 규칙이 없던 시절에 가입한 사람이 <b>자기 계정을 되찾지 못한다</b> — 재설정은 이미
     * 곤란한 사람이 오는 자리다. 규칙을 조인다면 가입과 함께 조인다.
     *
     * <p>상한 72바이트는 취향이 아니라 bcrypt 의 한계다. 그보다 긴 부분은 <b>조용히
     * 무시되므로</b>, 막지 않으면 "100자를 넣었는데 72자만 맞으면 통과한다" 가 된다.
     */
    @NotBlank
    @Size(max = 72, message = "비밀번호는 72자를 넘을 수 없습니다.")
    private String newPassword;
}
