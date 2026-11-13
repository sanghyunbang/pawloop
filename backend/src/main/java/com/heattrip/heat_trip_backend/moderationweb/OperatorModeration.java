package com.heattrip.heat_trip_backend.moderationweb;

import com.heattrip.heat_trip_backend.community.CommunityTakedown;
import com.heattrip.heat_trip_backend.moderation.ModerationActions;
import com.heattrip.heat_trip_backend.moderation.ReportCase;
import com.heattrip.heat_trip_backend.moderation.ReportTarget;
import com.heattrip.heat_trip_backend.moderation.Reports;
import com.heattrip.heat_trip_backend.moderation.SuspensionStatus;
import com.heattrip.heat_trip_backend.user.KnownUsers;
import com.heattrip.heat_trip_backend.user.UserSessions;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.Optional;

/**
 * 신고 한 건을 처리한다 — 이슈 #718. 운영자 경로({@link OperatorModerationController})만 부른다.
 *
 * <h2>한 트랜잭션</h2>
 * <p>지우는 것과 "지웠다" 를 적는 것이 함께 커밋된다. 한쪽만 남으면 기록 없이 사라진 글이나, 기록만 있고 남아
 * 있는 글이 생긴다. 사진·영상 파일은 커밋 뒤에 저장소에서 지운다(작성자 삭제와 같은 길).
 *
 * <h2>한 신고에 판단은 한 번</h2>
 * <p>이미 지웠거나 기각한 신고를 다시 처리하면 409 다. 같은 글을 다른 신고로 다시 지우려 하면 그 글은 이미 없으므로
 * {@code alreadyGone} 에 들어가고 기록은 안 늘어난다.
 *
 * <h2>채팅은 아직</h2>
 * <p>채팅 메시지 신고를 '지움' 으로 처리하면 409 이고 아무것도 쓰지 않는다. 채팅 코드는 따로 손으로 짜는 영역이라
 * 메시지를 지우는 운영자 길은 그쪽에서 붙인다. 그때까지 채팅에서 문제를 일으킨 사람은 정지로 막는다 — 정지된
 * 사람은 채팅도 못 보내고 못 읽는다. '기각' 은 채팅 신고에도 된다.
 *
 * <h2>정지 — 셋째 조각</h2>
 * <p>정지는 사람에게 거는 것이라 신고가 없어도 된다. 신고 번호를 함께 주면 <b>그 신고의 대상이 바로 이 사람인지</b>
 * 확인한다 — 번호를 잘못 옮겨 엉뚱한 사람을 내보내는 일을 막는다. 정지하면 그 사람의 refresh 토큰을 전부 폐기하고
 * (다음 로그인 연장을 끊는다) 그 뒤의 요청은 {@code AccountSuspensionFilter} 가 막는다. 정지 중에 다시 정지하거나
 * 정지 아닌 사람을 풀면 409 다 — 기간을 바꾸려면 풀고 다시 건다. 줄이 둘 남아 무엇을 했는지가 그대로 보인다.
 */
@Service
public class OperatorModeration {

    static final String REMOVE = "remove";
    static final String DISMISS = "dismiss";
    static final int MAX_REASON = 500;
    static final int MAX_ACTOR = 64;
    /** 기간 정지의 상한 — 10년. 그보다 길면 무기한(기간을 비움)이 뜻에 맞다. */
    static final int MAX_DAYS = 3_650;

    private final Reports reports;
    private final ModerationActions actions;
    private final CommunityTakedown takedown;
    private final KnownUsers users;
    private final UserSessions sessions;

    public OperatorModeration(Reports reports, ModerationActions actions, CommunityTakedown takedown,
                              KnownUsers users, UserSessions sessions) {
        this.reports = reports;
        this.actions = actions;
        this.takedown = takedown;
        this.users = users;
        this.sessions = sessions;
    }

    @Transactional
    public Resolution resolve(long reportId, String decision, String reason, String actor) {
        String why = required("reason", reason, MAX_REASON);
        String who = required("actor", actor, MAX_ACTOR);
        if (!REMOVE.equals(decision) && !DISMISS.equals(decision)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "decision 은 remove 또는 dismiss 입니다");
        }
        ReportCase report = reports.caseOf(reportId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "그런 신고가 없습니다"));
        List<ModerationActions.Decision> earlier = actions.decisionsOf(reportId);
        if (!earlier.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "이미 처리한 신고입니다 — " + earlier.get(0).kind() + " (" + earlier.get(0).at() + ")");
        }

        if (DISMISS.equals(decision)) {
            long actionId = actions.recordDismissal(reportId, why, who);
            return new Resolution(reportId, DISMISS, List.of(actionId), List.of(), List.of());
        }

        if (report.targets().stream().anyMatch(t -> !isCommunity(t.targetType()))) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "채팅 신고는 아직 '지움' 으로 처리할 수 없습니다 — 작성자 정지로 막습니다");
        }
        List<Long> actionIds = new ArrayList<>();
        List<Target> removed = new ArrayList<>();
        List<Target> alreadyGone = new ArrayList<>();
        for (ReportCase.Line target : report.targets()) {
            Optional<CommunityTakedown.Removed> copy = remove(target);
            if (copy.isEmpty()) {
                alreadyGone.add(new Target(target.targetType(), target.targetId()));
                continue;
            }
            CommunityTakedown.Removed c = copy.get();
            actionIds.add(actions.recordRemoval(reportId, new ModerationActions.Removal(c.targetType(), c.targetId(),
                    c.authorUserId(), c.authorName(), c.title(), c.body(), c.occurredAt()), why, who));
            removed.add(new Target(c.targetType(), c.targetId()));
        }
        return new Resolution(reportId, REMOVE, actionIds, removed, alreadyGone);
    }

    /**
     * 사람을 정지한다.
     *
     * @param reportId 근거가 된 신고 — 주면 그 신고의 대상이 이 사람인지 확인한다. 없어도 된다
     * @param days     기간(1~{@value #MAX_DAYS}일). 비우면 무기한
     */
    @Transactional
    public Standing suspend(long userId, Long reportId, Integer days, String reason, String actor) {
        String why = required("reason", reason, MAX_REASON);
        String who = required("actor", actor, MAX_ACTOR);
        if (days != null && (days < 1 || days > MAX_DAYS)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "days 는 1~" + MAX_DAYS + " 입니다 — 무기한이면 비워 두세요");
        }
        requireUser(userId);
        if (reportId != null) {
            ReportCase report = reports.caseOf(reportId)
                    .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "그런 신고가 없습니다"));
            if (!Objects.equals(report.reportedUserId(), userId)) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                        "신고 #" + reportId + " 의 대상은 사용자 #" + report.reportedUserId() + " 입니다");
            }
        }
        Optional<SuspensionStatus.Suspension> current = actions.currentSuspensionOf(userId);
        if (current.isPresent()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "이미 정지 중입니다 — " + until(current.get()) + ". 기간을 바꾸려면 풀고 다시 거세요");
        }
        actions.recordSuspension(reportId, userId, days == null ? null : Duration.ofDays(days), why, who);
        sessions.endAll(userId);
        return standing(userId);
    }

    /** 정지를 푼다. 정지 중이 아니면 409. */
    @Transactional
    public Standing lift(long userId, String reason, String actor) {
        String why = required("reason", reason, MAX_REASON);
        String who = required("actor", actor, MAX_ACTOR);
        requireUser(userId);
        if (actions.currentSuspensionOf(userId).isEmpty()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "정지 중인 사람이 아닙니다");
        }
        actions.recordLift(userId, why, who);
        return standing(userId);
    }

    /** 한 사람의 지금 상태와 받은 조치. 탈퇴한 사람이어도 기록은 보인다. */
    @Transactional(readOnly = true)
    public Standing standing(long userId) {
        Optional<SuspensionStatus.Suspension> current = actions.currentSuspensionOf(userId);
        return new Standing(userId, users.byId(userId).isPresent(), current.isPresent(),
                current.map(SuspensionStatus.Suspension::since).orElse(null),
                current.map(SuspensionStatus.Suspension::endsAt).orElse(null),
                actions.historyOf(userId));
    }

    private void requireUser(long userId) {
        if (users.byId(userId).isEmpty()) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "그런 사용자가 없습니다");
        }
    }

    private static String until(SuspensionStatus.Suspension suspension) {
        return suspension.endsAt() == null ? "무기한" : suspension.endsAt() + " 까지";
    }

    private Optional<CommunityTakedown.Removed> remove(ReportCase.Line target) {
        if (ReportTarget.Type.COMMUNITY_POST.wireValue().equals(target.targetType())) {
            return takedown.removePost(target.targetId());
        }
        return takedown.removeComment(target.targetId());
    }

    private static boolean isCommunity(String targetType) {
        return ReportTarget.Type.COMMUNITY_POST.wireValue().equals(targetType)
                || ReportTarget.Type.COMMUNITY_COMMENT.wireValue().equals(targetType);
    }

    private static String required(String name, String value, int max) {
        String v = value == null ? "" : value.strip();
        if (v.isEmpty() || v.length() > max) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, name + " 는 1~" + max + "자입니다");
        }
        return v;
    }

    /**
     * 처리 결과.
     *
     * @param actionIds   남긴 조치 기록의 id 들
     * @param removed     이번에 지운 것
     * @param alreadyGone 이미 없던 것 — 기록을 안 남겼다
     */
    public record Resolution(long reportId, String decision, List<Long> actionIds,
                             List<Target> removed, List<Target> alreadyGone) {
    }

    /** 글·댓글 하나 — 신고 사본과 같은 낱말의 종류와 id. */
    public record Target(String targetType, long targetId) {
    }

    /**
     * 한 사람의 지금 상태.
     *
     * @param exists    계정이 있는가 — 탈퇴했으면 {@code false} 이고 기록만 남아 있다
     * @param suspended 지금 정지 중인가
     * @param since     정지한 시각(UTC) — 정지 중일 때만
     * @param endsAt    풀리는 시각(UTC) — 무기한이거나 정지 중이 아니면 {@code null}
     * @param history   받은 조치, 최근 것부터 스무 줄
     */
    public record Standing(long userId, boolean exists, boolean suspended, Instant since, Instant endsAt,
                           List<ModerationActions.Entry> history) {
    }
}
