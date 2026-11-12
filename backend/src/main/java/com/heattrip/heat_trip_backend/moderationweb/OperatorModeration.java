package com.heattrip.heat_trip_backend.moderationweb;

import com.heattrip.heat_trip_backend.community.CommunityTakedown;
import com.heattrip.heat_trip_backend.moderation.ModerationActions;
import com.heattrip.heat_trip_backend.moderation.ReportCase;
import com.heattrip.heat_trip_backend.moderation.ReportTarget;
import com.heattrip.heat_trip_backend.moderation.Reports;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.util.ArrayList;
import java.util.List;
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
 * 메시지를 지우는 운영자 길은 그쪽에서 붙인다. 그때까지 채팅에서 문제를 일으킨 사람은 정지(다음 조각)로 막는다 —
 * 정지된 사람은 채팅도 못 보내고 못 읽는다. '기각' 은 채팅 신고에도 된다.
 */
@Service
public class OperatorModeration {

    static final String REMOVE = "remove";
    static final String DISMISS = "dismiss";
    static final int MAX_REASON = 500;
    static final int MAX_ACTOR = 64;

    private final Reports reports;
    private final ModerationActions actions;
    private final CommunityTakedown takedown;

    public OperatorModeration(Reports reports, ModerationActions actions, CommunityTakedown takedown) {
        this.reports = reports;
        this.actions = actions;
        this.takedown = takedown;
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
}
