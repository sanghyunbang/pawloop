package com.heattrip.heat_trip_backend.user.dto;

import lombok.Getter;
import lombok.Setter;

@Getter
@Setter
public class SignupRequest {
    private String email;
    private String password;
    private String nickname;
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
