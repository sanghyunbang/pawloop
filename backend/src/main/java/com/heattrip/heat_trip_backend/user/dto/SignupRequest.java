package com.heattrip.heat_trip_backend.user.dto;

import com.heattrip.heat_trip_backend.user.entity.User;

import jakarta.validation.constraints.Size;

import lombok.Getter;
import lombok.Setter;

@Getter
@Setter
public class SignupRequest {
    private String email;
    private String password;
    /** 상한은 {@link User#MAX_NICKNAME_LENGTH} — 이슈 #229. 가입도 무방비였다. */
    @Size(max = User.MAX_NICKNAME_LENGTH,
            message = "닉네임은 " + User.MAX_NICKNAME_LENGTH + "자를 넘을 수 없습니다.")
    private String nickname;

    @Size(max = User.MAX_NAME_LENGTH, message = "이름은 " + User.MAX_NAME_LENGTH + "자를 넘을 수 없습니다.")
    private String name;
    private String gender;

    // ✅ 추가
    private String ageGroup;       // "over14" | "under14"
    private Boolean agreeTos;      // 필수
    private Boolean agreePrivacy;  // 필수
    private Boolean agreeMarketing;// 선택

    // ✅ 문서 버전 (프런트에서 보내거나, 서버 기본값 적용)
    private String tosVersion;        // 예: "v1.0"
    private String privacyVersion;    // 예: "v1.0"
    private String marketingVersion;  // 예: "v1.0"
}
