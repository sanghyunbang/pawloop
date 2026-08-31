package com.heattrip.heat_trip_backend.place.service;

import com.heattrip.heat_trip_backend.place.KtoBudgetProperties;
import com.heattrip.heat_trip_backend.place.repository.KtoCallBudgetRepository;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDate;
import java.time.ZoneId;

/**
 * KTO 로 나가는 모든 호출이 지나는 문 — 이슈 #40 완료 조건 6.
 *
 * <h2>이 클래스가 없으면 상한이 없다</h2>
 * <p>KTO 일 한도는 <b>1,000콜</b>이다. 넘기면 그날 남은 시간 동안 지도 탭이 죽고,
 * 앱을 새로 배포해야 고칠 수 있는 종류의 사고가 아니라 <b>다음 날까지 기다리는</b> 사고다.
 *
 * <p>그래서 여기가 <b>예측이 아니라 게이트</b>다. "이 정도면 안 넘을 것 같다" 가 아니라,
 * 이 메서드를 통과하지 못하면 아웃바운드 호출이 <b>일어나지 않는다.</b>
 *
 * <h2>왜 DB 인가</h2>
 * <p>{@code AtomicInteger} 로 두면 세 가지가 한꺼번에 깨진다.
 * <ul>
 *   <li><b>재기동.</b> 배포할 때마다 0 이 된다. 하루 세 번 배포하면 상한이 3,000 이다.</li>
 *   <li><b>인스턴스.</b> 두 대면 각자 1,000 을 센다.</li>
 *   <li><b>관측.</b> 어제 몇 콜을 썼는지 물을 수 없다.</li>
 * </ul>
 *
 * <h2>fail-closed</h2>
 * <p>예약이 <b>어떤 이유로든</b> 실패하면 호출하지 않는다 — DB 가 죽었을 때 "일단 부르고
 * 보자" 로 열어 두면, 그 순간이 정확히 카운터가 없는 순간이다.
 *
 * <h2>실패해도 환불하지 않는다</h2>
 * <p>KTO 호출이 타임아웃 나도 예약은 되돌리지 않는다. 환불하면 <b>타임아웃을 유도하는
 * 것만으로 무한히 호출</b>할 수 있고, 무엇보다 상대는 실패한 호출도 센다.
 *
 * <h2>날 경계는 KST 다</h2>
 * <p>{@code LocalDate} 를 <b>Java 에서</b> 만들어 넘긴다. DB 세션 타임존을 믿지 않는다 —
 * 운영과 로컬이 다를 수 있고, 그 차이는 날 경계에서만 드러나서 찾기 어렵다.
 *
 * <p><b>상대의 리셋 시각은 모른다.</b> KST 자정인지 UTC 자정인지 확인하지 못했고, 그래서
 * 일 총량을 1,000 이 아니라 <b>500</b> 으로 잡았다 — 경계가 어긋나면 상대의 어떤 24시간
 * 창에 우리의 두 날이 겹쳐 들어올 수 있기 때문이다({@link KtoBudgetProperties} 참조).
 */
@Service
public class KtoCallBudget {

    private static final Logger log = LoggerFactory.getLogger(KtoCallBudget.class);

    /** 한국 표준시. 우리 날 경계의 기준이다. */
    private static final ZoneId KST = ZoneId.of("Asia/Seoul");

    private final KtoCallBudgetRepository budgets;
    private final KtoBudgetProperties properties;
    private final Clock clock;

    public KtoCallBudget(KtoCallBudgetRepository budgets,
                         KtoBudgetProperties properties,
                         Clock clock) {
        this.budgets = budgets;
        this.properties = properties;
        this.clock = clock;
    }

    /**
     * 호출 {@code units} 개를 예약한다.
     *
     * <h2>{@code REQUIRES_NEW} 인 이유</h2>
     * <p>예약은 <b>아웃바운드 호출보다 먼저 커밋</b>돼야 한다. 요청 트랜잭션에 얹으면
     * 그 트랜잭션이 나중에 롤백될 때 예약도 함께 사라지는데, <b>호출은 이미 나갔다.</b>
     * 그러면 우리 카운터가 상대보다 작아지고 상한이 조용히 무너진다.
     *
     * @param units 이 작업이 실제로 낼 아웃바운드 호출 수.
     *              상세는 {@code detailCommon2 + detailPetTour2} 라 <b>2</b> 다
     * @return 예약했으면 {@code true}. {@code false} 면 <b>호출하지 마라</b>
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public boolean tryAcquire(KtoPool pool, int units) {
        LocalDate today = LocalDate.now(clock.withZone(KST));
        int cap = capOf(pool);

        try {
            budgets.ensureRow(today, pool.wireValue());
            boolean granted = budgets.reserve(today, pool.wireValue(), units, cap) == 1;
            if (!granted) {
                log.warn("KTO 호출 예산 소진 — pool={} cap={} (KST {})", pool.wireValue(), cap, today);
            }
            return granted;
        } catch (RuntimeException e) {
            // fail-closed. 여기서 열어 두면 그 순간이 정확히 카운터가 없는 순간이다.
            log.error("KTO 호출 예산 예약 실패 — 호출하지 않는다. pool={}", pool.wireValue(), e);
            return false;
        }
    }

    /**
     * 이 풀을 오늘치 전부 소진한 것으로 닫는다.
     *
     * <p>KTO 가 한도 초과({@code resultCode=22})나 키 미등록({@code 30})을 말했을 때 부른다.
     * <b>상대의 말을 우리 카운터보다 믿는다</b> — 우리 계산이 맞더라도 상대가 아니라고 하면
     * 아닌 것이고, 그 상태로 계속 두드리면 차단당한다.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void closeForToday(KtoPool pool, String reason) {
        LocalDate today = LocalDate.now(clock.withZone(KST));
        try {
            budgets.ensureRow(today, pool.wireValue());
            budgets.close(today, pool.wireValue(), capOf(pool));
            log.error("KTO 가 거절했다 — 오늘({} KST) {} 풀을 닫는다. 사유={}",
                    today, pool.wireValue(), reason);
        } catch (RuntimeException e) {
            log.error("풀을 닫지 못했다. pool={}", pool.wireValue(), e);
        }
    }

    private int capOf(KtoPool pool) {
        return switch (pool) {
            case NEARBY -> properties.getNearbyMaxCallsPerDay();
            case DETAIL -> properties.getDetailMaxCallsPerDay();
        };
    }
}
