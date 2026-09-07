package com.heattrip.heat_trip_backend.walksafety.controller;

import com.heattrip.heat_trip_backend.walksafety.dto.WalkSafetyNowResponse;
import com.heattrip.heat_trip_backend.walksafety.service.WalkSafetyService;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.Duration;

/**
 * {@code GET /api/walk-safety/now?nx=61&ny=126} — 인증 없음(#336).
 *
 * <p>왜 인증이 없나: 격자 번호는 좌표는 아니지만 "어디쯤" 이다. 누구의 요청인지 서버가 모르게
 * 두는 것이 위치를 서버에 안 보내는 A안(#235)의 뜻에 가깝다. 대신 IP 기준 한도가 있다
 * ({@code ApiRateLimitFilter} 의 {@code walk-safety} 버킷).
 */
@RestController
@RequestMapping("/api/walk-safety")
public class WalkSafetyController {
    private final WalkSafetyService service;

    public WalkSafetyController(WalkSafetyService service) {
        this.service = service;
    }

    @GetMapping("/now")
    public ResponseEntity<WalkSafetyNowResponse> now(@RequestParam int nx, @RequestParam int ny) {
        WalkSafetyNowResponse body = service.now(nx, ny);
        // 실황은 한 시간 단위다 — 중간 캐시가 10분 들고 있어도 틀리지 않는다.
        return ResponseEntity.ok()
                .cacheControl(CacheControl.maxAge(Duration.ofMinutes(10)).cachePublic())
                .body(body);
    }
}
