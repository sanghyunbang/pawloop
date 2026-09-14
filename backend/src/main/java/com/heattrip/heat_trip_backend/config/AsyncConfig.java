package com.heattrip.heat_trip_backend.config;

import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableAsync;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;

import java.util.concurrent.RejectedExecutionHandler;

/**
 * {@code @Async} 를 켠다 — 지금 쓰는 곳은 푸시 발송({@code push.service.PushDispatcher}) 하나다 (이슈 #83).
 *
 * <h2>큐는 인메모리 상태다 (#86 원칙 1)</h2>
 * <p>인스턴스가 둘이면 각자 자기 큐를 든다. 사건은 커밋한 인스턴스에서만 발행되므로 <b>같은 알림이
 * 두 번 나가지는 않는다.</b> 다만 인스턴스가 죽으면 그 큐에 남은 알림은 사라진다 — 알림은 최선
 * 노력이고 메시지는 이미 저장돼 있어 다음 폴링이 가져온다. 이 줄을 #86 §2 의 표에 적어 둔다.
 *
 * <h2>넘치면 버린다</h2>
 * <p>큐가 차면 {@code CallerRunsPolicy} 는 <b>요청 스레드가</b> FCM 을 부르게 만든다 — 그 순간 채팅 응답이
 * 발송을 기다리는, 이 설계가 막으려던 바로 그 일이 된다. 그래서 버리고 경고 로그를 남긴다.
 */
@Slf4j
@Configuration
@EnableAsync
public class AsyncConfig {

    public static final String PUSH_EXECUTOR = "pushExecutor";

    /**
     * AI 주간 요약(#486)의 모델 호출 — 통계 요청이 모델을 기다리지 않게 요청 밖에서 돈다.
     * 이름은 {@code walk.ai.WeeklyInsightService} 가 문자열로 든다(모듈 경계 밖의 상수를 참조하지 않으려고).
     */
    public static final String INSIGHT_EXECUTOR = "insightExecutor";

    @Bean(PUSH_EXECUTOR)
    public ThreadPoolTaskExecutor pushExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setThreadNamePrefix("push-");
        executor.setCorePoolSize(2);
        executor.setMaxPoolSize(4);
        executor.setQueueCapacity(1_000);
        executor.setWaitForTasksToCompleteOnShutdown(true);
        executor.setAwaitTerminationSeconds(10);
        RejectedExecutionHandler dropAndWarn = (task, pool) ->
                log.warn("푸시 발송 큐가 찼다 — 알림 하나를 버린다 (대기 {} · 실행 중 {})",
                        pool.getQueue().size(), pool.getActiveCount());
        executor.setRejectedExecutionHandler(dropAndWarn);
        executor.initialize();
        return executor;
    }

    /**
     * 모델 호출은 하나에 몇 초씩 걸리고 돈이다 — 스레드 둘, 대기 50 이면 충분하고, 그 이상은 <b>거절</b>한다
     * (기본 {@code AbortPolicy}). 거절은 부르는 쪽이 받아 "이번 요청은 문장 없이" 로 처리한다 — 조용히 버리면
     * 부르는 쪽의 "만드는 중" 표식이 안 풀린다.
     */
    @Bean(INSIGHT_EXECUTOR)
    public ThreadPoolTaskExecutor insightExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setThreadNamePrefix("ai-insight-");
        executor.setCorePoolSize(1);
        executor.setMaxPoolSize(2);
        executor.setQueueCapacity(50);
        executor.setWaitForTasksToCompleteOnShutdown(true);
        executor.setAwaitTerminationSeconds(15);
        executor.initialize();
        return executor;
    }
}
