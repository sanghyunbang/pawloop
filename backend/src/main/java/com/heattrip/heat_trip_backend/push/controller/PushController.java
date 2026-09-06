package com.heattrip.heat_trip_backend.push.controller;

import com.heattrip.heat_trip_backend.user.CurrentUser;
import com.heattrip.heat_trip_backend.push.dto.PushSettingsRequest;
import com.heattrip.heat_trip_backend.push.dto.PushSettingsResponse;
import com.heattrip.heat_trip_backend.push.dto.PushTokenRequest;
import com.heattrip.heat_trip_backend.push.service.DeviceTokenService;
import com.heattrip.heat_trip_backend.push.service.PushPreferenceService;
import com.heattrip.heat_trip_backend.user.entity.User;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 푸시 — 기기 토큰 등록과 전체 끄기 (이슈 #83). 계약은 {@code docs/04-api/openapi.yaml} 의 {@code Push} 태그다.
 *
 * <ul>
 *   <li><b>인증</b> — {@code SecurityConfig} 의 {@code anyRequest().authenticated()} 가 받는다.
 *       {@code publicMatchers} 에 줄을 더하지 않는다({@code ConsentController} 와 같다).
 *       주체는 언제나 토큰의 주인이다 — 경로에 사용자 id 가 없다.</li>
 *   <li><b>rate limit</b> — {@code PUT} 둘은 {@code group-write} 버킷이다({@code ApiRateLimitFilter.resolveRule}).
 *       요청 한 건이 행을 만들거나 바꾸기 때문이고, {@code PUT /api/consents} 와 같은 판단이다.
 *       {@code GET} 은 설정 화면이 들어올 때 한 번이라 다른 인증 읽기와 같이 버킷이 없다.</li>
 * </ul>
 *
 * <h2>{@code PUT /tokens} 가 204 인 이유</h2>
 * <p>등록은 upsert 라 "새로 만들었는가" 가 앱에 의미가 없고, 돌려줄 값도 없다 — 토큰은 앱이 이미
 * 들고 있다. 방별 음소거는 여기 없다 — 멤버십의 속성이라 {@code PUT /api/chat/rooms/{roomId}/mute} 다.
 */
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/push")
public class PushController {

    private final DeviceTokenService deviceTokens;
    private final PushPreferenceService preferences;

    @PutMapping("/tokens")
    public ResponseEntity<Void> register(@CurrentUser User me, @Valid @RequestBody PushTokenRequest body) {
        deviceTokens.register(me.getId(), body.token().strip(), body.platform());
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/settings")
    public PushSettingsResponse settings(@CurrentUser User me) {
        return new PushSettingsResponse(preferences.isEnabled(me.getId()));
    }

    @PutMapping("/settings")
    public PushSettingsResponse update(@CurrentUser User me, @Valid @RequestBody PushSettingsRequest body) {
        return new PushSettingsResponse(preferences.setEnabled(me.getId(), body.enabled()));
    }
}
