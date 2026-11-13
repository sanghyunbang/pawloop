package com.heattrip.heat_trip_backend.moderation.entity;

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
import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.Check;

import java.time.LocalDateTime;

/**
 * 운영자가 한 조치 한 줄 — 이슈 #718. 덧붙이기만 하고 고치거나 지우지 않는다.
 *
 * <h2>무엇을 적나 — {@code kind}</h2>
 * <ul>
 *   <li>{@code remove} — 신고된 글·댓글을 지웠다. <b>지우기 직전의 사본</b>(작성자·제목·본문·시각)을 함께 남긴다.
 *       신고 사본은 신고한 때의 글이라, 그 뒤에 고쳐진 글을 지웠다면 무엇을 지웠는지는 이 줄만 안다.</li>
 *   <li>{@code dismiss} — 신고를 살펴봤고 지울 것이 없다고 판단했다.</li>
 *   <li>{@code suspend} · {@code lift} — 사람을 정지하고 푼다(다음 조각). {@code ends_at} 이 비면 무기한 정지다.</li>
 * </ul>
 *
 * <h2>왜 신고 표의 상태 칸이 아닌가</h2>
 * <p>한 신고에 조치가 여럿일 수 있고(글 삭제와 작성자 정지), 정지·해제는 신고 없이도 일어난다. 그래서 "무엇을
 * 언제 누가 왜" 를 줄마다 남기는 이력 표 하나로 둔다. 사람의 지금 상태는 그 사람의 마지막 정지·해제 줄이다.
 *
 * <h2>사람은 값으로만 가리킨다</h2>
 * <p>{@code subject_user_id} 에 {@code users} 로 가는 FK 가 없다 — {@code report} · {@code user_block} 과 같은
 * 규약이다. 탈퇴가 조치 기록을 지우면 안 된다. 신고로는 FK 를 건다 — 신고는 지워지지 않는다.
 */
@Entity
@Table(name = "moderation_action", indexes = {
        // 정지 판정의 뜨거운 길 — 이 사람의 마지막 정지·해제 한 줄(다음 조각).
        @Index(name = "idx_moderation_action_subject", columnList = "subject_user_id, id"),
        @Index(name = "idx_moderation_action_report", columnList = "report_id")
})
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PRIVATE)
@Builder
@Check(name = "chk_moderation_action_kind", constraints = "kind in ('remove','suspend','lift','dismiss')")
@Check(name = "chk_moderation_action_target_type",
        constraints = "target_type is null or target_type in ('community_post','community_comment','chat_message')")
// 지웠다면 무엇을 지웠는지가 있어야 한다 — 이 표가 존재하는 이유다.
@Check(name = "chk_moderation_action_remove_has_copy",
        constraints = "kind <> 'remove' or (target_type is not null and target_id is not null and body is not null)")
@Check(name = "chk_moderation_action_standing_has_subject",
        constraints = "kind not in ('suspend','lift') or subject_user_id is not null")
@Check(name = "chk_moderation_action_ends_only_on_suspend", constraints = "kind = 'suspend' or ends_at is null")
public class ModerationAction {

    public static final String REMOVE = "remove";
    public static final String DISMISS = "dismiss";
    public static final String SUSPEND = "suspend";
    public static final String LIFT = "lift";

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** {@code remove} · {@code dismiss} · {@code suspend} · {@code lift}. */
    @Column(name = "kind", nullable = false, length = 8)
    private String kind;

    /** 어느 신고에 대한 조치인가. 신고 없이 한 정지·해제면 비어 있다. */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "report_id", foreignKey = @ForeignKey(name = "fk_moderation_action_report"))
    private Report report;

    /** 조치를 받은 사람 — 지운 글의 작성자, 정지된 사람. 값으로만(FK 없음). */
    @Column(name = "subject_user_id")
    private Long subjectUserId;

    /** 지운 대상의 종류 — 신고 사본과 같은 낱말. */
    @Column(name = "target_type", length = 24)
    private String targetType;

    @Column(name = "target_id")
    private Long targetId;

    /** 정지가 끝나는 시각(UTC). {@code suspend} 에만, 비면 무기한. */
    @Column(name = "ends_at")
    private LocalDateTime endsAt;

    /** 지우기 직전의 닉네임. */
    @Column(name = "author_name", length = 255)
    private String authorName;

    @Column(name = "title", length = 200)
    private String title;

    @Column(name = "body", columnDefinition = "text")
    private String body;

    /** 지운 원본이 쓰인 시각(UTC). */
    @Column(name = "occurred_at")
    private LocalDateTime occurredAt;

    /** 왜 — 운영자가 적는다. */
    @Column(name = "reason", nullable = false, length = 500)
    private String reason;

    /** 누가 — 서버에 들어간 계정 이름(스크립트가 채운다). */
    @Column(name = "actor", nullable = false, length = 64)
    private String actor;

    /** 조치한 시각(UTC). */
    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;
}
