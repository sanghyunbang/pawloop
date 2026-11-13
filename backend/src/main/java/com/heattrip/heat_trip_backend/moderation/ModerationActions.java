package com.heattrip.heat_trip_backend.moderation;

import com.heattrip.heat_trip_backend.moderation.entity.ModerationAction;
import com.heattrip.heat_trip_backend.moderation.repository.ModerationActionRepository;
import com.heattrip.heat_trip_backend.moderation.repository.ReportRepository;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import java.util.Set;

/**
 * 운영자 조치를 적는다 — 이슈 #718. 표는 {@link ModerationAction}, 덧붙이기만 한다.
 *
 * <p>이 모듈은 글을 모른다({@code allowedDependencies = {}}). 무엇을 지울지·지웠는지는 부르는 쪽
 * ({@code moderationweb}) 이 커뮤니티에 묻고, 여기에는 그 결과를 {@link Removal} 로 넘겨 남기기만 한다.
 *
 * <p>정지 판정({@link SuspensionStatus})도 여기서 한다 — 정지·해제가 같은 표의 줄이라서다.
 */
@Service
@Transactional(readOnly = true)
public class ModerationActions implements SuspensionStatus {

    /** 사람의 지금 상태를 정하는 두 종류 — 마지막 것이 이긴다. */
    private static final Set<String> STANDING_KINDS = Set.of(ModerationAction.SUSPEND, ModerationAction.LIFT);

    private final ModerationActionRepository actions;
    private final ReportRepository reports;
    private final Clock clock;

    public ModerationActions(ModerationActionRepository actions, ReportRepository reports, Clock clock) {
        this.actions = actions;
        this.reports = reports;
        this.clock = clock;
    }

    /** 이 신고에 이미 내린 판단(지움·기각). 비어 있으면 아직 판단하지 않았다. */
    public List<Decision> decisionsOf(long reportId) {
        return actions.findDecisionsOf(reportId).stream()
                .map(a -> new Decision(a.getId(), a.getKind(), a.getTargetType(), a.getTargetId(),
                        ModerationTime.toInstant(a.getCreatedAt())))
                .toList();
    }

    /** 신고된 글·댓글을 지웠다 — 지우기 직전의 사본과 함께. */
    @Transactional
    public long recordRemoval(long reportId, Removal removal, String reason, String actor) {
        return actions.save(ModerationAction.builder()
                .kind(ModerationAction.REMOVE)
                .report(reports.getReferenceById(reportId))
                .subjectUserId(removal.authorUserId())
                .targetType(removal.targetType())
                .targetId(removal.targetId())
                .authorName(removal.authorName())
                .title(removal.title())
                .body(removal.body())
                .occurredAt(removal.occurredAt() == null ? null
                        : LocalDateTime.ofInstant(removal.occurredAt(), ZoneOffset.UTC))
                .reason(reason)
                .actor(actor)
                .createdAt(ModerationTime.nowUtc(clock))
                .build()).getId();
    }

    /**
     * 사람을 정지한다. {@code length} 가 비면 무기한이다. 끝나는 시각은 기록하는 시각과 <b>같은 시계</b>로 잰다 —
     * 둘이 다른 시계면 "7일 정지" 가 기록상 7일이 아니게 된다.
     *
     * @param reportId 이 정지의 근거가 된 신고(없으면 {@code null})
     */
    @Transactional
    public long recordSuspension(Long reportId, long userId, Duration length, String reason, String actor) {
        LocalDateTime now = ModerationTime.nowUtc(clock);
        return actions.save(ModerationAction.builder()
                .kind(ModerationAction.SUSPEND)
                .report(reportId == null ? null : reports.getReferenceById(reportId))
                .subjectUserId(userId)
                .endsAt(length == null ? null : now.plus(length))
                .reason(reason)
                .actor(actor)
                .createdAt(now)
                .build()).getId();
    }

    /** 정지를 푼다. 그 뒤로는 마지막 줄이 해제라 정지 판정이 비어 있다. */
    @Transactional
    public long recordLift(long userId, String reason, String actor) {
        return actions.save(ModerationAction.builder()
                .kind(ModerationAction.LIFT)
                .subjectUserId(userId)
                .reason(reason)
                .actor(actor)
                .createdAt(ModerationTime.nowUtc(clock))
                .build()).getId();
    }

    @Override
    public Optional<Suspension> currentSuspensionOf(long userId) {
        LocalDateTime now = ModerationTime.nowUtc(clock);
        return actions.findFirstBySubjectUserIdAndKindInOrderByIdDesc(userId, STANDING_KINDS)
                .filter(last -> ModerationAction.SUSPEND.equals(last.getKind()))
                .filter(suspension -> suspension.getEndsAt() == null || suspension.getEndsAt().isAfter(now))
                .map(suspension -> new Suspension(suspension.getId(),
                        ModerationTime.toInstant(suspension.getCreatedAt()),
                        suspension.getEndsAt() == null ? null : ModerationTime.toInstant(suspension.getEndsAt())));
    }

    /** 이 사람이 받은 조치 — 최근 것부터 스무 줄. 지운 글의 본문은 싣지 않는다(신고 한 건 보기에서 본다). */
    public List<Entry> historyOf(long userId) {
        return actions.findTop20BySubjectUserIdOrderByIdDesc(userId).stream()
                .map(a -> new Entry(a.getId(), a.getKind(),
                        a.getReport() == null ? null : a.getReport().getId(),
                        a.getTargetType(), a.getTargetId(),
                        a.getEndsAt() == null ? null : ModerationTime.toInstant(a.getEndsAt()),
                        a.getReason(), a.getActor(), ModerationTime.toInstant(a.getCreatedAt())))
                .toList();
    }

    /** 신고를 살펴봤고 지울 것이 없다. */
    @Transactional
    public long recordDismissal(long reportId, String reason, String actor) {
        return actions.save(ModerationAction.builder()
                .kind(ModerationAction.DISMISS)
                .report(reports.getReferenceById(reportId))
                .reason(reason)
                .actor(actor)
                .createdAt(ModerationTime.nowUtc(clock))
                .build()).getId();
    }

    /**
     * 지우기 직전의 글·댓글 — 커뮤니티가 돌려준 사본을 그대로 옮긴 것.
     *
     * @param targetType   {@code community_post} · {@code community_comment}
     * @param authorUserId 쓴 사람(탈퇴했으면 {@code null})
     */
    public record Removal(String targetType, long targetId, Long authorUserId, String authorName,
                          String title, String body, Instant occurredAt) {
    }

    /** 이미 내린 판단 한 줄. */
    public record Decision(long actionId, String kind, String targetType, Long targetId, Instant at) {
    }

    /**
     * 한 사람이 받은 조치 한 줄.
     *
     * @param endsAt 정지가 풀리는 시각(UTC) — 정지 줄에만, 무기한이면 {@code null}
     */
    public record Entry(long actionId, String kind, Long reportId, String targetType, Long targetId,
                        Instant endsAt, String reason, String actor, Instant at) {
    }
}
