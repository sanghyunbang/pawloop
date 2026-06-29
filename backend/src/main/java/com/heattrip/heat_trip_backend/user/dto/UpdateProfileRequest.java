package com.heattrip.heat_trip_backend.user.dto;

import lombok.*;

import java.util.List;

@Getter @Setter
@NoArgsConstructor @AllArgsConstructor
public class UpdateProfileRequest {
    private String name;        // null 이면 미수정
    private String nickname;    // null 이면 미수정
    private String gender;      // FEMALE/MALE/OTHER (null/이상값이면 미수정 or OTHER로)
    private Integer age;        // null 이면 미수정
    private String travelType;  // null 이면 미수정
    private String imageUrl;    // null 이면 미수정 (S3 URL)

    // ✅ 선택: 마케팅 동의 변경
    private Boolean agreeMarketing;
}
