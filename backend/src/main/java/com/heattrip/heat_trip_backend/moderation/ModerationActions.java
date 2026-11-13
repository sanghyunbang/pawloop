package com.heattrip.heat_trip_backend.moderation;

import com.heattrip.heat_trip_backend.moderation.entity.ModerationAction;
import com.heattrip.heat_trip_backend.moderation.repository.ModerationActionRepository;
import com.heattrip.heat_trip_backend.moderation.repository.ReportRepository;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;

/**
 * 운영자 조치를 적는다 — 이슈 #718. 표는 {@link ModerationAction}, 덧붙이기만 한다.
 *
 * <p>이 모듈은 글을 모른다({@code allowedDependencies = {}}). 무엇을 지울지·지웠는지는 부르는 쪽
 * ({@code moderationweb}) 이 커뮤니티에 묻고, 여기에는 그 결과를 {@link Removal} 로 넘겨 남기기만 한다.
 */
@Service
@Transactional(readOnly = true)
public class ModerationActions {

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
}
