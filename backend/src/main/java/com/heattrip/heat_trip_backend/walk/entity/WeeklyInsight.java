package com.heattrip.heat_trip_backend.walk.entity;

import com.heattrip.heat_trip_backend.user.entity.User;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.ForeignKey;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.OnDelete;
import org.hibernate.annotations.OnDeleteAction;
import org.hibernate.annotations.Check;

import java.time.LocalDate;
import java.time.LocalDateTime;

/**
 * AI 주간 요약 한 장 — 사용자 · 아이 · 주(週)에 하나 — 이슈 #486.
 *
 * <p><b>왜 표인가.</b> 모델 호출은 돈이고 느리다. 같은 입력(같은 주 · 같은 산책들)에 두 번 부르지
 * 않으려면 "무엇으로 만들었나"({@code inputHash})가 재시작을 넘어 남아야 한다. 메모리 캐시는 배포
 * 한 번에 비고, 그날 모든 사용자를 다시 부른다.
 *
 * <p><b>{@code inputHash} 가 다른 문장은 안 내보낸다</b>(#538). 그 문장은 다른 숫자로 쓴 것이라 이번
 * 주를 더 이상 설명하지 않는다 — 통계 화면에서 바로 위 "이번 주 요약" 카드와 다른 말을 하게 된다.
 *
 * <p>{@code text} 가 null 인 행은 "만들었는데 버렸다"(숫자 검사 실패 · 빈 답)이다. 그 주에 입력이
 * 그대로면 다시 부르지 않는다 — 같은 입력에 같은 실수를 반복할 이유가 없다. 새 산책이 오면(입력이
 * 바뀌면) 다시 시도한다.
 *
 * <p>{@code dogKey} 는 아이 id 이고 0 은 "모든 아이" 다. NULL 을 쓰면 MySQL 유니크가 NULL 끼리를
 * 다르다고 보아 한 주에 행이 여럿 쌓인다.
 */
@Entity
@Table(
        name = "weekly_insight",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_weekly_insight", columnNames = {"user_id", "dog_id", "week_start"}),
        indexes = @Index(name = "idx_weekly_insight_generated", columnList = "generated_at"))
@Check(name = "ck_weekly_insight_feedback", constraints = "feedback in ('up','down')")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class WeeklyInsight {

    /** "모든 아이" 의 dogKey. */
    public static final long ALL_DOGS = 0L;

    /** 👍 — 이 문장이 도움이 됐다. */
    public static final String FEEDBACK_UP = "up";

    /** 👎 — 아니었다. */
    public static final String FEEDBACK_DOWN = "down";

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** 탈퇴하면 요약도 사라진다 — 그 사람만 보는 문장이다. */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "user_id", nullable = false,
            foreignKey = @ForeignKey(name = "fk_weekly_insight_user"))
    @OnDelete(action = OnDeleteAction.CASCADE)
    private User user;

    @Column(name = "dog_id", nullable = false)
    private long dogKey;

    @Column(name = "week_start", nullable = false)
    private LocalDate weekStart;

    /** 입력({@code WeeklyInsightInput.render()})의 SHA-256 — 같으면 다시 안 부른다. */
    @Column(name = "input_hash", nullable = false, length = 64)
    private String inputHash;

    @Column(name = "model", nullable = false, length = 64)
    private String model;

    /** 모델의 문장. null 이면 만들었다가 버린 것. */
    @Column(name = "text", columnDefinition = "text")
    private String text;

    /**
     * 이 주에 모델을 부른 횟수.
     *
     * <p>예전에는 이 값이 <b>상한의 근거</b>였다(주 3회). 그 상한에 닿으면 옛 문장을 그대로 내보내
     * 카드가 틀린 숫자를 말했다(#538). 지금 상한은 날 단위 둘이고 메모리에서 센다 —
     * 이 값은 <b>남는 기록</b>이다(이 주에 몇 번 다시 썼나).
     */
    @Column(name = "calls", nullable = false)
    private int calls;

    @Column(name = "generated_at", nullable = false)
    private LocalDateTime generatedAt;

    /**
     * 사용자의 평가(#486 후속) — {@link #FEEDBACK_UP} · {@link #FEEDBACK_DOWN} · {@code null}(안 누름).
     * 값이 둘뿐이라 CHECK 로도 잠근다. 문장이 다시 만들어지면 지운다 — 옛 문장에 대한 평가다.
     */
    @Column(name = "feedback", length = 8)
    private String feedback;

    @Column(name = "feedback_at")
    private LocalDateTime feedbackAt;

    public static WeeklyInsight first(User user, long dogKey, LocalDate weekStart,
                                      String inputHash, String model, String text, LocalDateTime at) {
        WeeklyInsight row = new WeeklyInsight();
        row.user = user;
        row.dogKey = dogKey;
        row.weekStart = weekStart;
        row.inputHash = inputHash;
        row.model = model;
        row.text = text;
        row.calls = 1;
        row.generatedAt = at;
        return row;
    }

    /** 입력이 바뀌어 다시 만들었다. */
    public void regenerated(String inputHash, String model, String text, LocalDateTime at) {
        this.inputHash = inputHash;
        this.model = model;
        this.text = text;
        this.calls++;
        this.generatedAt = at;
        // 새 문장이다 — 옛 문장에 대한 평가를 새 문장이 물려받으면 안 된다.
        this.feedback = null;
        this.feedbackAt = null;
    }

    /** 평가를 남기거나({@code up}·{@code down}) 지운다({@code null}). 값 검사는 서비스가 먼저 한다. */
    public void rate(String value, LocalDateTime at) {
        this.feedback = value;
        this.feedbackAt = value == null ? null : at;
    }
}
