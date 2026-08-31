package com.heattrip.heat_trip_backend.security;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

/**
 * 고정 창 카운터. 열쇠 하나가 한 창에서 몇 번 왔는지 세고, 지난 창을 치운다. (이슈 #80)
 *
 * <p><b>왜 클래스로 뺐나.</b> {@code ApiRateLimitFilter} 안에 있던 것을 그대로 꺼냈다.
 * #80 이 <b>인증 뒤에서 사용자 단위로 세는</b> 두 번째 필터를 요구하는데, 세는 방법은 같고
 * 열쇠만 다르다. 복사하면 창 계산과 청소 규칙이 두 벌이 되고, 한쪽만 고치는 날이 온다.
 *
 * <p><b>인스턴스를 공유하지 않는다.</b> 필터마다 하나씩 갖는다. 열쇠에 버킷 이름이 들어가므로
 * 섞여도 충돌하지는 않지만, 나눠 두면 한쪽의 맵 크기가 다른 쪽의 청소 주기에 영향을 주지 않는다.
 *
 * <p><b>인스턴스가 둘이 되면 실효 한도가 두 배다.</b> 맵이 프로세스 안에 있기 때문이다.
 * 채팅과 무관하게 지금 이미 있는 문제이고, {@code docs/02-architecture/refresh-token-redis.md}
 * 에 적혀 있다. 여기서 고치지 않는다 — 고치려면 공유 저장소가 필요하고 그건 별개 결정이다.
 */
class RateLimitWindow {

    private record CounterWindow(long startedAtEpochSecond, int count) {}

    private final Map<String, CounterWindow> counters = new ConcurrentHashMap<>();

    /** 마지막으로 스테일 항목을 훑은 창. 같은 창에서 두 번 훑지 않기 위한 것뿐이다. */
    private final AtomicLong lastSweptWindow = new AtomicLong(Long.MIN_VALUE);

    /**
     * 이 요청을 통과시켜도 되는가.
     *
     * @param key 카운터 열쇠. 무엇으로 만들지는 부르는 쪽이 정한다 — 그게 #80 의 핵심이다
     * @param limit 창당 허용 횟수
     * @param currentWindow {@code epochSecond / windowSeconds}
     * @return 한도 안이면 {@code true}
     */
    boolean tryAcquire(String key, int limit, long currentWindow) {
        CounterWindow result = counters.compute(key, (ignored, current) -> {
            if (current == null || current.startedAtEpochSecond() != currentWindow) {
                return new CounterWindow(currentWindow, 1);
            }
            return new CounterWindow(current.startedAtEpochSecond(), current.count() + 1);
        });

        if (result != null && result.count() > limit) {
            return false;
        }

        cleanupStaleEntries(currentWindow);
        return true;
    }

    /**
     * 지난 창의 항목을 치운다. <b>창이 바뀔 때만</b> 훑는다. (이슈 #14)
     *
     * <p>예전에는 차단되지 않은 <b>모든 요청</b>이 맵 전체를 순회했다. 그 상태에서 카운터
     * 열쇠를 공격자가 정할 수 있었으므로 맵을 부풀린 만큼 요청당 CPU 가 함께 올라갔다 —
     * 실측으로 맵 크기가 2배가 되자 요청당 비용이 3.7배가 됐다. 인증 없이 보낼 수 있는
     * 요청으로 서버 CPU 를 증폭시킬 수 있다는 뜻이다.
     *
     * <p>열쇠 위조를 막은 것이 근본 수정이고, 이 게이트는 그 위의 두 번째 벽이다.
     * 창 하나에 순회 한 번이면 정리 주기는 그대로이고 요청당 비용은 O(1) 이 된다.
     */
    private void cleanupStaleEntries(long currentWindow) {
        long previous = lastSweptWindow.get();
        if (previous == currentWindow) {
            return;
        }
        // 진 쪽은 그냥 건너뛴다. 청소는 다음 요청이 해도 되는 일이라 재시도할 이유가 없다.
        if (!lastSweptWindow.compareAndSet(previous, currentWindow)) {
            return;
        }
        counters.entrySet().removeIf(entry -> entry.getValue().startedAtEpochSecond() + 2 < currentWindow);
    }

    /** 테스트가 카운터 상태를 보기 위한 것. 운영 코드는 쓰지 않는다. */
    int trackedKeyCount() {
        return counters.size();
    }
}
