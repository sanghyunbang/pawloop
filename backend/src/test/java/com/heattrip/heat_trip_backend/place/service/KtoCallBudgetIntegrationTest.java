package com.heattrip.heat_trip_backend.place.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.heattrip.heat_trip_backend.place.KtoBudgetProperties;
import com.heattrip.heat_trip_backend.place.repository.KtoCallBudgetRepository;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import java.util.List;
import java.util.concurrent.Callable;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * 호출 예산 게이트 — 이슈 #40 완료 조건 6.
 *
 * <h2>여기가 지키는 것</h2>
 * <p><b>KTO 로 나가는 호출 수의 상한.</b> 넘기면 그날 남은 시간 동안 지도 탭이 죽고,
 * 앱을 새로 배포해도 안 고쳐진다 — 다음 날까지 기다려야 하는 사고다.
 *
 * <p>그래서 이 테스트는 "코드를 읽으면 맞아 보인다" 로 만족하지 않는다. <b>스레드를 실제로
 * 띄워</b> 동시에 예약하게 하고, 상한을 정확히 그만큼만 통과시키는지 센다.
 *
 * <h2>진짜 MySQL 이어야 한다</h2>
 * <p>예약이 조건부 UPDATE 한 문장이고, 그 판정이 <b>MySQL 클라이언트 플래그</b>에 걸린다 —
 * Connector/J 는 기본이 {@code CLIENT_FOUND_ROWS} 라 값이 안 바뀐 행도 "1행 영향" 으로
 * 돌려준다. 조건을 {@code SET} 에 넣었다면 소진 상태에서도 통과하는데, 그 차이는
 * <b>진짜 MySQL 에서만</b> 드러난다.
 *
 * <h2>애너테이션이 {@code @SpringBootTest} 한 줄뿐인 것은 의도다</h2>
 * <p>{@code ChatMessageIntegrationTest} 와 글자 그대로 같아야 컨텍스트 캐시를 공유한다(#21).
 * {@code @Transactional} 도 없다 — 붙이면 스레드들이 <b>각자의 트랜잭션</b>을 여는 이
 * 테스트의 전제가 사라진다.
 */
@SpringBootTest
class KtoCallBudgetIntegrationTest extends AbstractMySqlIntegrationTest {

    @Autowired
    private KtoCallBudget budget;

    @Autowired
    private KtoCallBudgetRepository budgets;

    @Autowired
    private KtoBudgetProperties properties;

    @Autowired
    private JdbcTemplate jdbc;

    @Autowired
    private PlatformTransactionManager transactionManager;

    /**
     * 리포지토리의 {@code @Modifying} 문장을 직접 부를 때 쓴다.
     *
     * <p>{@code KtoCallBudget} 을 통하면 {@code REQUIRES_NEW} 가 알아서 붙지만, 여기서는
     * <b>SQL 자체의 성질</b>(조건이 WHERE 에 있는가)을 재는 것이라 게이트를 건너뛰고
     * 부른다. 트랜잭션은 스레드마다 따로여야 한다 — 하나로 묶으면 동시성 테스트가
     * 아무것도 안 재게 된다.
     */
    private TransactionTemplate newTransaction() {
        TransactionTemplate template = new TransactionTemplate(transactionManager);
        template.setPropagationBehavior(
                org.springframework.transaction.TransactionDefinition.PROPAGATION_REQUIRES_NEW);
        return template;
    }

    @BeforeEach
    void clearBudget() {
        // 이 표는 하루에 행 두 개라 테스트끼리 반드시 겹친다. 매번 비운다.
        jdbc.update("delete from kto_call_budget");
    }

    @Test
    @DisplayName("상한까지만 통과한다 — 그 다음은 전부 거절이다")
    void grantsExactlyUpToTheCap() {
        int cap = properties.getNearbyMaxCallsPerDay();
        int granted = 0;

        for (int i = 0; i < cap + 10; i++) {
            if (budget.tryAcquire(KtoPool.NEARBY, 1)) {
                granted++;
            }
        }

        assertThat(granted)
                .as("상한을 넘어가는 순간 아웃바운드 호출이 멈춰야 한다. 이게 유일한 장치다")
                .isEqualTo(cap);
    }

    @Test
    @DisplayName("스레드 스무 개가 동시에 예약해도 상한을 못 넘는다 — 조건이 WHERE 에 있어야 성립한다")
    void concurrentReservationsCannotExceedTheCap() throws Exception {
        int cap = 20;
        int threads = 40;
        jdbc.update("insert into kto_call_budget (`day`, pool, used) values (?, 'nearby', 0) "
                + "on duplicate key update used = 0", kstToday());

        CyclicBarrier start = new CyclicBarrier(threads);
        AtomicInteger granted = new AtomicInteger();
        ExecutorService pool = Executors.newFixedThreadPool(threads);

        try {
            List<Callable<Void>> tasks = new java.util.ArrayList<>();
            for (int i = 0; i < threads; i++) {
                tasks.add(() -> {
                    start.await(10, TimeUnit.SECONDS);
                    Integer affected = newTransaction().execute(status -> budgets.reserve(
                            java.time.LocalDate.now(java.time.ZoneId.of("Asia/Seoul")),
                            "nearby", 1, cap));
                    if (affected != null && affected == 1) {
                        granted.incrementAndGet();
                    }
                    return null;
                });
            }
            for (Future<Void> future : pool.invokeAll(tasks, 30, TimeUnit.SECONDS)) {
                future.get();
            }
        } finally {
            pool.shutdownNow();
        }

        assertThat(granted.get())
                .as("""
                        읽어서 비교하고 쓰면 두 문장 사이가 열려 여럿이 같은 값을 읽고 전부
                        통과한다. 조건부 UPDATE 한 문장이라 그 틈이 없다 (📌 #86 원칙 5).
                        """)
                .isEqualTo(cap);
        assertThat(usedOf("nearby")).isEqualTo(cap);
    }

    @Test
    @DisplayName("조건이 WHERE 에 있어야 소진 상태에서 거절된다 — CLIENT_FOUND_ROWS 의 함정")
    void aFullBudgetRejectsEvenThoughMySqlCountsMatchedRows() {
        jdbc.update("insert into kto_call_budget (`day`, pool, used) values (?, 'nearby', 5) "
                + "on duplicate key update used = 5", kstToday());

        Integer affected = newTransaction().execute(status -> budgets.reserve(
                java.time.LocalDate.now(java.time.ZoneId.of("Asia/Seoul")), "nearby", 1, 5));

        assertThat(affected)
                .as("""
                        SET used = IF(used < cap, used+1, used) 로 썼다면 여기가 1 이다 —
                        Connector/J 기본이 CLIENT_FOUND_ROWS 라 값이 안 바뀐 행도 매칭으로
                        세기 때문이다. 그러면 상한이 사라진다.
                        """)
                .isZero();
    }

    @Test
    @DisplayName("그날 행이 없어도 첫 예약이 통과한다 — 자정 직후가 영영 막히면 안 된다")
    void theFirstCallOfTheDayWorks() {
        assertThat(jdbc.queryForObject("select count(*) from kto_call_budget", Integer.class))
                .isZero();

        assertThat(budget.tryAcquire(KtoPool.NEARBY, 1))
                .as("ensureRow 가 없으면 그날 첫 호출이 0행을 받고, 행이 영영 안 생긴다")
                .isTrue();
    }

    @Test
    @DisplayName("상세는 2 단위를 잡는다 — 1건이 2콜이라 1 로 잡으면 상한이 두 배로 무너진다")
    void detailReservesTwoUnits() {
        budget.tryAcquire(KtoPool.DETAIL, 2);

        assertThat(usedOf("detail"))
                .as("detailCommon2 + detailPetTour2 다. 예산도 실제 호출 수와 같아야 한다")
                .isEqualTo(2);
    }

    @Test
    @DisplayName("풀이 서로의 상한을 안 먹는다 — 상세가 지도를 죽이면 안 된다")
    void poolsAreIndependent() {
        int detailCap = properties.getDetailMaxCallsPerDay();
        for (int i = 0; i < detailCap; i += 2) {
            budget.tryAcquire(KtoPool.DETAIL, 2);
        }

        assertThat(budget.tryAcquire(KtoPool.DETAIL, 2)).isFalse();
        assertThat(budget.tryAcquire(KtoPool.NEARBY, 1))
                .as("상세를 다 써도 지도는 살아 있어야 한다. 그래서 버킷이 둘이다")
                .isTrue();
    }

    @Test
    @DisplayName("KTO 가 한도 초과라고 하면 그 풀을 즉시 닫는다 — 상대의 말을 우리 계산보다 믿는다")
    void theUpstreamVerdictWins() {
        assertThat(budget.tryAcquire(KtoPool.NEARBY, 1)).isTrue();

        budget.closeForToday(KtoPool.NEARBY, "resultCode=22");

        assertThat(budget.tryAcquire(KtoPool.NEARBY, 1))
                .as("우리 계산이 맞더라도 상대가 아니라고 하면 아닌 것이다. 계속 두드리면 차단당한다")
                .isFalse();
        assertThat(usedOf("nearby")).isEqualTo(properties.getNearbyMaxCallsPerDay());
    }

    @Test
    @DisplayName("사용량이 DB 에 남는다 — 재기동해도 0 이 되지 않는다는 것이 이 설계의 요점이다")
    void theCounterLivesInTheDatabase() {
        budget.tryAcquire(KtoPool.NEARBY, 1);
        budget.tryAcquire(KtoPool.NEARBY, 1);

        assertThat(usedOf("nearby"))
                .as("""
                        AtomicInteger 였다면 배포할 때마다 0 이 된다 — 하루 세 번 배포하면
                        상한이 구조적으로 3배다. 인스턴스가 둘이면 각자 1,000 을 센다.
                        """)
                .isEqualTo(2);
    }

    /**
     * 오늘(KST) 이 풀이 쓴 수.
     *
     * <p><b>{@code curdate()} 를 쓰면 안 된다.</b> 그건 DB 세션 타임존의 오늘이고, 코드가
     * 세는 것은 <b>KST 의 오늘</b>이다. 컨테이너가 UTC 면 둘이 갈리는 구간이 하루에
     * 9시간 있고, 그 시간대에만 테스트가 빨개진다 — 실제로 06시에 겪었다.
     */
    private int usedOf(String pool) {
        List<Integer> used = jdbc.queryForList(
                "select used from kto_call_budget where `day` = ? and pool = ?",
                Integer.class, kstToday(), pool);
        return used.isEmpty() ? 0 : used.get(0);
    }

    /** 코드가 세는 것과 같은 날짜. {@code KtoCallBudget} 이 쓰는 것과 같아야 한다. */
    private static java.sql.Date kstToday() {
        return java.sql.Date.valueOf(
                java.time.LocalDate.now(java.time.ZoneId.of("Asia/Seoul")));
    }
}
