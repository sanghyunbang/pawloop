package com.heattrip.heat_trip_backend.push.dto;

import com.heattrip.heat_trip_backend.push.entity.DeviceToken;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * 계약의 {@code PushTokenInput}. {@code platform} 은 계약의 enum 과 같은 두 값이다 —
 * {@code PushContractSpecTest} 가 이 패턴과 계약의 enum 을 견준다.
 */
public record PushTokenRequest(
        @NotBlank @Size(max = DeviceToken.TOKEN_MAX_LENGTH) String token,
        @NotBlank @Pattern(regexp = PLATFORM_PATTERN) String platform) {

    public static final String PLATFORM_PATTERN = "android|ios";
}
