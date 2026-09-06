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
}
