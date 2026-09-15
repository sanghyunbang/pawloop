package com.heattrip.heat_trip_backend.walk.ai;

import com.heattrip.heat_trip_backend.dog.DogOwnership;
import com.heattrip.heat_trip_backend.dog.DogProfileView;
import com.heattrip.heat_trip_backend.user.entity.User;
import jakarta.persistence.EntityManager;
import com.heattrip.heat_trip_backend.walk.dto.WalkStatsResponse;
import com.heattrip.heat_trip_backend.walk.entity.WeeklyInsight;
import com.heattrip.heat_trip_backend.walk.repository.WeeklyInsightRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executor;
import java.util.concurrent.RejectedExecutionException;
import java.util.NoSuchElementException;

/**
 * AI 주간 요약 — 이슈 #486. 통계 응답에 {@code aiSummary} 를 얹는다.
 *
 * <p>순서: 모델이 없으면 그대로 → 이 주의 행이 있고 <b>입력이 같으면</b> 그 문장(버린 것이면 null) →
 * 아니면 모델을 부른다(하루 상한 둘) → 숫자 검사 → 저장.
 *
 * <p><b>입력이 다른 문장은 안 내보낸다</b>(#538). 그 문장은 다른 숫자로 쓴 것이라 이번 주를 더 이상
 * 설명하지 않는다. 만드는 중이거나 상한에 닿았으면 {@code aiSummary} 는 {@code null} 이고 앱은 카드를
 * 그리지 않는다 — 규칙으로 만든 "이번 주 요약" 카드가 그대로 있으니 숫자를 잃지는 않는다.
 *
 * <p>통계 계산(트랜잭션)과 모델 호출(망)을 섞지 않는다 — 컨트롤러가 통계를 받은 뒤 이것을 부른다.
 * 저장은 {@code REQUIRES_NEW} 라 읽기 전용 트랜잭션에 묻히지 않는다.
 */
@Service
public class WeeklyInsightService {

    private static final Logger log = LoggerFactory.getLogger(WeeklyInsightService.class);
    private static final ZoneId KST = ZoneId.of("Asia/Seoul");

    /**
     * 모델에 주는 규칙. 숫자는 입력에 있는 것만 — 어겨도 {@link InsightNumberGuard} 가 버리지만, 규칙을
     * 먼저 말해 두면 버리는 일이 드물다. 요일도 같다({@link InsightWeekdayGuard}, #543) — 걸은 요일만
     * 말하라고 먼저 시키고, 어긴 문장을 버린다. 질책 금지는 페르소나 P3(바쁜 보호자, #349).
     */
    static final String SYSTEM = """
            너는 반려견 보호자를 돕는 산책 코치다. 아래 '데이터'만 근거로 이번 주 산책을 한국어로 정리한다.
            형식: 첫 줄과 둘째 줄은 이번 주를 요약하는 문장 하나씩(합쳐서 90자 안팎), 셋째 줄은 다음 며칠의 제안 한 문장.
            규칙:
            - 숫자는 데이터에 적힌 것만 쓴다. 데이터에 없는 거리 · 횟수 · 시간 · 시각 · 날짜를 만들지 않는다.
            - 요일은 '요일별 km' 가 0 이 아닌 요일만 말한다. 안 걸은 요일은 제안에서도 이름 대신 '주말' · '남은 날'로 쓴다.
            - 시간대(새벽 · 아침 · 낮 · 저녁)도 '시간대별 횟수' 에 적힌 대로만 말한다. 0회인 시간대는 제안에만 쓴다.
            - 장소 이름 · 아이 이름 · 날씨를 지어내지 않는다. 아이는 '우리 아이'라고 부른다.
            - 질책하지 않는다. '부족했어요', '못 했어요' 같은 말 대신 제안형으로 쓴다.
            - 이모지 · 머리말 · 번호 · 따옴표 없이 문장만 쓴다.
            """;

    private final WeeklyInsightModel model;
    private final WeeklyInsightRepository insights;
    private final EntityManager entityManager;
    private final DogOwnership dogs;
    private final WeeklyInsightProperties props;
    private final Clock clock;
    private final DailyCounter counter = new DailyCounter();
    private final PerRowDailyCounter perRow = new PerRowDailyCounter();

    /** {@code AsyncConfig.INSIGHT_EXECUTOR} — 모듈 경계 밖의 상수를 참조하지 않으려고 문자열로 든다. */
    static final String INSIGHT_EXECUTOR = "insightExecutor";

    /** 요청 밖에서 만드는 일. 동기 모드({@code async=false})면 요청 안에서 그대로 돈다. */
    private final Executor executor;

    /** 지금 만드는 중인 (사용자 · 아이 · 주). 같은 것을 여러 요청이 동시에 부르면 모델은 한 번만. */
    private final Set<String> inFlight = ConcurrentHashMap.newKeySet();

    /**
     * {@code user} 는 {@link EntityManager#getReference} 로 잇는다 — 사용자 모듈의 저장소(내부 패키지)를
     * 부르지 않는다. 아이는 {@link DogOwnership}(dog 모듈의 공개 표면)에서 크기 · 나이대만 받는다.
     * 둘 다 모듈 경계 기준선(96)을 지키려는 자리다(#97 · #98).
     */
    public WeeklyInsightService(WeeklyInsightModel model,
                                WeeklyInsightRepository insights,
                                EntityManager entityManager,
                                DogOwnership dogs,
                                WeeklyInsightProperties props,
                                Clock clock,
                                @Qualifier(INSIGHT_EXECUTOR) Executor executor) {
        this.model = model;
        this.insights = insights;
        this.entityManager = entityManager;
        this.dogs = dogs;
        this.props = props;
        this.clock = clock;
        this.executor = executor;
    }

    /** 통계에 {@code aiSummary} 를 얹어 돌려준다. 실패 · 꺼짐 · 상한이면 {@code null} 인 채로. */
    public WalkStatsResponse attach(long userId, Long dogId, WalkStatsResponse stats) {
        if (!model.available()) {
            return stats;
        }
        LocalDate today = LocalDate.now(clock.withZone(KST));
        WeeklyInsightInput input = WeeklyInsightInput.of(stats, dogs.profileOf(userId, dogId), today);
        String hash = input.hash();
        long dogKey = dogId == null ? WeeklyInsight.ALL_DOGS : dogId;

        Optional<WeeklyInsight> row = insights.findByUser_IdAndDogKeyAndWeekStart(userId, dogKey, stats.weekStart());
        // **입력이 같을 때만** 저장된 문장을 쓴다(#538). 해시가 다르면 그 문장은 다른 숫자로 쓴 것이고,
        // 그대로 내보내면 바로 위 "이번 주 요약" 카드와 다른 말을 한다.
        if (row.isPresent() && row.get().getInputHash().equals(hash)) {
            return stats.withAiSummary(summaryOf(row.get()));
        }
        String key = jobKey(userId, dogKey, stats.weekStart());
        if (inFlight.contains(key)) {
            // 이미 만드는 중 — 모델을 또 부르지도, 하루 상한을 또 쓰지도 않는다.
            return pending(stats);
        }
        // 한 줄의 하루 상한을 먼저 본다. 서버 상한을 먼저 쓰면, 여기서 막힐 요청이 남의 몫을 한 칸 깎는다.
        if (!perRow.tryAcquire(today, key, props.perRowDailyCap())) {
            log.info("[AI 주간 요약] 이 요약의 하루 상한 {}회에 닿았다 — 오늘은 카드 없이 (user {})",
                    props.perRowDailyCap(), userId);
            return stats;
        }
        if (!counter.tryAcquire(today, props.dailyCap())) {
            log.info("[AI 주간 요약] 하루 상한 {}회에 닿았다 — 오늘은 1단계 문장만 (user {})", props.dailyCap(), userId);
            return stats;
        }

        Job job = new Job(userId, dogKey, stats.weekStart(), input, hash, row.orElse(null));
        if (!props.async()) {
            // 동기 — 테스트와 비상 스위치. 요청이 모델을 기다린다.
            generate(job);
            return stats.withAiSummary(insights.findByUser_IdAndDogKeyAndWeekStart(userId, dogKey, stats.weekStart())
                    // 못 만들었으면(모델 실패) 행은 옛 해시 그대로다 — 그 문장은 안 내보낸다.
                    .filter(saved -> saved.getInputHash().equals(hash))
                    .map(WeeklyInsightService::summaryOf).orElse(null));
        }
        // 비동기 — 요청은 "만드는 중" 만 붙여 바로 돌아간다. 문장은 실행기가 적고, 앱이 잠시 뒤 한 번
        // 더 읽는다. 옛 문장은 안 싣는다 — 여기까지 온 것은 숫자가 바뀌었다는 뜻이다(#538).
        if (inFlight.add(key)) {
            try {
                executor.execute(() -> {
                    try {
                        generate(job);
                    } finally {
                        inFlight.remove(key);
                    }
                });
            } catch (RejectedExecutionException full) {
                inFlight.remove(key);
                log.warn("[AI 주간 요약] 실행기 큐가 찼다 — 이번 요청은 문장 없이 (user {})", userId);
            }
        }
        return pending(stats);
    }

    /**
     * 만드는 중 — 앱이 잠시 뒤 한 번 더 읽는다("AI 요약을 만들고 있어요").
     *
     * <p><b>옛 문장을 함께 싣지 않는다</b>(#538). 여기까지 온 것은 숫자가 바뀌었다는 뜻이고, 그 문장은
     * 이번 주를 더 이상 설명하지 않는다.
     */
    private static WalkStatsResponse pending(WalkStatsResponse stats) {
        return stats.withAiSummaryPending(true);
    }

    private static String jobKey(long userId, long dogKey, LocalDate weekStart) {
        return userId + ":" + dogKey + ":" + weekStart;
    }

    /**
     * 모델을 부르고 결과를 적는다 — 비동기 모드면 실행기 스레드에서, 동기 모드면 요청 안에서. <b>던지지 않는다</b>:
     * 실패는 행을 남기지 않아 다음 요청이 다시 시도한다(하루 상한이 재시도를 묶는다).
     */
    void generate(Job job) {
        try {
            Optional<String> answer = model.complete(SYSTEM, job.input().render());
            if (answer.isEmpty()) {
                return;
            }
            String text = answer.get();
            String input = job.input().render();
            if (!InsightNumberGuard.allowed(text, input)) {
                log.info("[AI 주간 요약] 입력에 없는 숫자가 있어 버린다 (user {}, week {})", job.userId(), job.weekStart());
                text = null;
            } else if (!InsightWeekdayGuard.allowed(text, input)) {
                log.info("[AI 주간 요약] 안 걸은 요일을 말해서 버린다 (user {}, week {})", job.userId(), job.weekStart());
                text = null;
            }
            store(job.existing(), job.userId(), job.dogKey(), job.weekStart(), job.hash(), text);
        } catch (RuntimeException e) {
            log.warn("[AI 주간 요약] 만들기 실패 (user {}, week {}): {}", job.userId(), job.weekStart(), e.toString());
        }
    }

    /** 만들 것 하나 — 요청 스레드가 읽어 둔 값들. {@code existing} 은 그 주의 행(없으면 null). */
    record Job(long userId, long dogKey, LocalDate weekStart, WeeklyInsightInput input, String hash,
               WeeklyInsight existing) { }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    protected WeeklyInsight store(WeeklyInsight existing, long userId, long dogKey, LocalDate weekStart,
                                  String hash, String text) {
        LocalDateTime now = LocalDateTime.now(clock.withZone(ZoneOffset.UTC));
        if (existing != null) {
            WeeklyInsight managed = insights.findById(existing.getId()).orElse(existing);
            managed.regenerated(hash, model.name(), text, now);
            return insights.save(managed);
        }
        User user = entityManager.getReference(User.class, userId);
        return insights.save(WeeklyInsight.first(user, dogKey, weekStart, hash, model.name(), text, now));
    }

    /**
     * 👍/👎(#486 후속) — 내 요약 행에 평가를 남기거나({@code up}·{@code down}) 지운다({@code null}).
     * 남의 요약과 없는 요약은 구별 없이 404, 다른 값은 400. 다음 통계 응답의 {@code aiSummary.feedback} 이 이 값이다.
     */
    @Transactional
    public WalkStatsResponse.AiSummary rate(long userId, long insightId, String value) {
        String normalized = validFeedback(value);
        WeeklyInsight row = insights.findById(insightId)
                .filter(candidate -> candidate.getUser().getId().equals(userId))
                .orElseThrow(() -> new NoSuchElementException("요약을 찾을 수 없습니다."));
        row.rate(normalized, LocalDateTime.now(clock.withZone(ZoneOffset.UTC)));
        return summaryOf(row);
    }

    private static String validFeedback(String value) {
        if (value == null) {
            return null;
        }
        if (WeeklyInsight.FEEDBACK_UP.equals(value) || WeeklyInsight.FEEDBACK_DOWN.equals(value)) {
            return value;
        }
        throw new IllegalArgumentException("평가는 up 이나 down 입니다.");
    }

    private static WalkStatsResponse.AiSummary summaryOf(WeeklyInsight row) {
        if (row.getText() == null) {
            return null;
        }
        return new WalkStatsResponse.AiSummary(row.getId(), row.getText(),
                row.getGeneratedAt().toInstant(ZoneOffset.UTC), row.getFeedback());
    }

    /**
     * 요약 하나(사람 · 아이 · 주)가 하루에 모델을 부른 횟수 — 이슈 #538.
     *
     * <p>{@link DailyCounter} 와 같은 결이고 열쇠만 다르다. 한 사람이 서버 하루치를 혼자 쓰지 못하게
     * 막는 자리다. 날이 바뀌면 <b>표를 통째로 비운다</b> — 그래야 열쇠가 무한정 쌓이지 않는다.
     */
    static final class PerRowDailyCounter {
        private LocalDate day;
        private final java.util.Map<String, Integer> calls = new java.util.HashMap<>();

        synchronized boolean tryAcquire(LocalDate today, String key, int cap) {
            if (!today.equals(day)) {
                day = today;
                calls.clear();
            }
            int used = calls.getOrDefault(key, 0);
            if (used >= cap) {
                return false;
            }
            calls.put(key, used + 1);
            return true;
        }
    }

    /** 하루 호출 횟수 — 서버 하나의 메모리. 재시작하면 0 이지만, 상한의 목적(폭주 방지)에는 충분하다. */
    static final class DailyCounter {
        private LocalDate day;
        private int calls;

        synchronized boolean tryAcquire(LocalDate today, int cap) {
            if (!today.equals(day)) {
                day = today;
                calls = 0;
            }
            if (calls >= cap) {
                return false;
            }
            calls++;
            return true;
        }
    }
}
