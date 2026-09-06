package com.heattrip.heat_trip_backend.push.metrics;

import com.heattrip.heat_trip_backend.push.fcm.FcmSendResult;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.stereotype.Component;

/**
 * 발송 결과를 센다 — 실기기 도착은 자동화할 수 없으니(#83) 남는 관측은 "우리가 몇 개를 넘겼고
 * FCM 이 몇 개를 받아 줬는가" 다.
 *
 * <ul>
 *   <li>{@code push.tokens{result=delivered|failed|unregistered}} — 토큰 단위</li>
 *   <li>{@code push.dispatch{outcome=sent|skipped|failed}} — 사건 단위. {@code skipped} 는 보낼 토큰이
 *       없던 것(모두 음소거·끔·토큰 없음)이고 {@code failed} 는 우리 코드가 던진 것이다</li>
 * </ul>
 */
@Component
public class PushMetrics {

    private final Counter delivered;
    private final Counter failed;
    private final Counter unregistered;
    private final Counter dispatchSent;
    private final Counter dispatchSkipped;
    private final Counter dispatchFailed;

    public PushMetrics(MeterRegistry registry) {
        this.delivered = Counter.builder("push.tokens").tag("result", "delivered").register(registry);
        this.failed = Counter.builder("push.tokens").tag("result", "failed").register(registry);
        this.unregistered = Counter.builder("push.tokens").tag("result", "unregistered").register(registry);
        this.dispatchSent = Counter.builder("push.dispatch").tag("outcome", "sent").register(registry);
        this.dispatchSkipped = Counter.builder("push.dispatch").tag("outcome", "skipped").register(registry);
        this.dispatchFailed = Counter.builder("push.dispatch").tag("outcome", "failed").register(registry);
    }

    public void record(FcmSendResult result) {
        delivered.increment(result.delivered());
        failed.increment(result.failed());
        unregistered.increment(result.unregistered().size());
        dispatchSent.increment();
    }

    public void skipped() {
        dispatchSkipped.increment();
    }

    public void dispatchFailed() {
        dispatchFailed.increment();
    }
}
