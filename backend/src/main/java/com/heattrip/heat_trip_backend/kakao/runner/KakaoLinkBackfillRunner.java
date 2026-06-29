package com.heattrip.heat_trip_backend.kakao.runner;

import com.heattrip.heat_trip_backend.kakao.service.KakaoLinkBackfillService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;              // [1]
import org.springframework.boot.ApplicationArguments;               // [2]
import org.springframework.boot.ApplicationRunner;                  // [2]
import org.springframework.stereotype.Component;                    // [3]
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;

@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnProperty(
    prefix = "backfill.kakao",
    name = "enabled",
    havingValue = "true",
    matchIfMissing = false   // 프로퍼티가 없으면 기본적으로 실행하고 싶다면 true, 반대면 false
)
public class KakaoLinkBackfillRunner implements ApplicationRunner {
    private final KakaoLinkBackfillService service;
    @Override public void run(ApplicationArguments args) {
        log.info("[Kakao Backfill] start...");
        service.runOnce();
        log.info("[Kakao Backfill] done.");
    }
}
