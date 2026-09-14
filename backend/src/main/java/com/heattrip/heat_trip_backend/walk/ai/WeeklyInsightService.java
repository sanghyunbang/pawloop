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
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.Optional;

/**
 * AI 주간 요약 — 이슈 #486. 통계 응답에 {@code aiSummary} 를 얹는다.
 *
 * <p>순서: 모델이 없으면 그대로 → 이 주의 행이 있고 입력이 같으면 그 문장(버린 것이면 null) →
 * 다시 만드는 횟수 · 하루 상한을 넘겼으면 마지막 문장 → 모델을 부른다 → 숫자 검사 → 저장.
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
     * 먼저 말해 두면 버리는 일이 드물다. 질책 금지는 페르소나 P3(바쁜 보호자, #349).
     */
    static final String SYSTEM = """
            너는 반려견 보호자를 돕는 산책 코치다. 아래 '데이터'만 근거로 이번 주 산책을 한국어로 정리한다.
            형식: 첫 줄과 둘째 줄은 이번 주를 요약하는 문장 하나씩(합쳐서 90자 안팎), 셋째 줄은 다음 며칠의 제안 한 문장.
            규칙:
            - 숫자는 데이터에 적힌 것만 쓴다. 데이터에 없는 거리 · 횟수 · 시간 · 시각 · 날짜를 만들지 않는다.
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
                                Clock clock) {
        this.model = model;
        this.insights = insights;
        this.entityManager = entityManager;
        this.dogs = dogs;
        this.props = props;
        this.clock = clock;
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
        if (row.isPresent() && (row.get().getInputHash().equals(hash)
                || row.get().getCalls() >= props.maxRegenerations())) {
            return stats.withAiSummary(summaryOf(row.get()));
        }
        if (!counter.tryAcquire(today, props.dailyCap())) {
            log.info("[AI 주간 요약] 하루 상한 {}회에 닿았다 — 오늘은 1단계 문장만 (user {})", props.dailyCap(), userId);
            return stats.withAiSummary(row.map(WeeklyInsightService::summaryOf).orElse(null));
        }

        Optional<String> answer = model.complete(SYSTEM, input.render());
        if (answer.isEmpty()) {
            // 망 · 시간 초과 — 행을 남기지 않아 다음 요청이 다시 시도한다(하루 상한이 재시도를 묶는다).
            return stats.withAiSummary(row.map(WeeklyInsightService::summaryOf).orElse(null));
        }
        String text = answer.get();
        if (!InsightNumberGuard.allowed(text, input.render())) {
            log.info("[AI 주간 요약] 입력에 없는 숫자가 있어 버린다 (user {}, week {})", userId, stats.weekStart());
            text = null;
        }
        WeeklyInsight saved = store(row.orElse(null), userId, dogKey, stats.weekStart(), hash, text);
        return stats.withAiSummary(summaryOf(saved));
    }

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

    private static WalkStatsResponse.AiSummary summaryOf(WeeklyInsight row) {
        if (row.getText() == null) {
            return null;
        }
        return new WalkStatsResponse.AiSummary(row.getText(), row.getGeneratedAt().toInstant(ZoneOffset.UTC));
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
