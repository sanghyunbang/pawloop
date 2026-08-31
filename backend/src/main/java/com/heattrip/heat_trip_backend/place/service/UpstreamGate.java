package com.heattrip.heat_trip_backend.place.service;

import com.heattrip.heat_trip_backend.place.KtoBudgetProperties;

import org.springframework.stereotype.Component;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Semaphore;
import java.util.function.Supplier;

/**
 * KTO 로 나가는 호출의 동시성 문 — 이슈 #40.
 *
 * <h2>왜 필요한가</h2>
 * <p>이 프록시는 <b>인증 없는 공개 경로</b> 뒤에 있다({@code security: []}). 캐시가 빈 셀에
 * 요청이 몰리면 두 가지가 한꺼번에 일어난다.
 *
 * <ol>
 *   <li><b>같은 셀을 여러 번 부른다.</b> 200개 요청이 같은 빈 셀에 오면 200콜이 나가고
 *       하루치 예산이 한 번에 사라진다.</li>
 *   <li><b>톰캣 스레드가 전부 묶인다.</b> KTO 가 느려지면 그 소켓을 기다리는 스레드가
 *       요청 수만큼 쌓이고, 그러면 <b>서버의 다른 모든 경로가 함께 멈춘다.</b></li>
 * </ol>
 *
 * <h2>기다리지 않는다</h2>
 * <p>둘 다 <b>대기 없이</b> 막는다.
 * <ul>
 *   <li>{@link Semaphore#tryAcquire()} — 자리가 없으면 즉시 포기한다. {@code acquire()} 로
 *       기다리면 스레드가 묶이는 것은 똑같고, 막으려던 것을 안 막는 셈이다.</li>
 *   <li>{@code inFlight} 에 {@link ConcurrentHashMap#putIfAbsent} — 같은 키를 이미 누가
 *       받고 있으면 <b>기다리지 않고</b> 물러난다. 부르는 쪽은 그때 오래된 스냅샷을 주거나
 *       빈 목록을 준다.</li>
 * </ul>
 *
 * <p>"기다렸다가 그 결과를 같이 쓰는" 판({@code cache.get(key, loader)})이 더 나아 보이지만,
 * 그러면 대기 시간이 loader 시간과 같아져서 <b>찬 셀 하나에 몰린 200 요청이 톰캣 스레드
 * 200개를 6초 묶는다.</b> 오래된 답을 즉시 주는 쪽이 낫다.
 *
 * <h2>인스턴스마다 한 벌이다</h2>
 * <p>이 문은 프로세스 안에 있다. 인스턴스가 둘이면 동시 호출이 최대 12 이고 같은 셀을
 * 둘이 받을 수 있다. <b>총량은 여전히 {@link KtoCallBudget} 이 막는다</b> — 그쪽은 DB 행이라
 * 인스턴스 수와 무관하다. 여기가 막는 것은 총량이 아니라 <b>순간의 폭주</b>다.
 */
@Component
public class UpstreamGate {

    private final Semaphore slots;
    private final Map<String, Boolean> inFlight = new ConcurrentHashMap<>();

    public UpstreamGate(KtoBudgetProperties properties) {
        this.slots = new Semaphore(properties.getMaxConcurrentUpstreamCalls());
    }

    /**
     * 이 키의 아웃바운드 작업을 <b>내가</b> 맡는다면 실행한다.
     *
     * @return 실행했으면 그 결과, 자리가 없거나 남이 이미 받고 있으면 {@code null}
     */
    public <T> T runIfOwner(String key, Supplier<T> work) {
        if (inFlight.putIfAbsent(key, Boolean.TRUE) != null) {
            return null;
        }
        try {
            if (!slots.tryAcquire()) {
                return null;
            }
            try {
                return work.get();
            } finally {
                slots.release();
            }
        } finally {
            inFlight.remove(key);
        }
    }

    /** 지금 밖으로 나가 있는 호출 수. 테스트와 관측용이다. */
    int inFlightCount() {
        return inFlight.size();
    }
}
