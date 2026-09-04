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
import jakarta.persistence.Lob;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;

import org.hibernate.annotations.Check;
import org.hibernate.annotations.OnDelete;
import org.hibernate.annotations.OnDeleteAction;

import java.time.LocalDateTime;

/**
 * 신고 시점의 사본 한 줄 — 이슈 #166.
 *
 * <h2>왜 사본인가</h2>
 * <p><b>원본이 지워진 뒤에 읽는 기록이다.</b> 참조만 남기면 작성자가 글을 지우는 순간
 * 운영자가 무엇을 판단해야 하는지 알 수 없다.
 *
 * <h2>{@code role} 이 대상과 맥락을 가른다</h2>
 * <p>댓글을 신고하면 <b>부모 글을 {@code context} 로 함께</b> 벤다. 댓글 한 줄만 남으면 무슨
 * 글에 달린 말인지 모르고, 글을 지우면 {@code fk_comment_post} 가 CASCADE 라 댓글이 함께
 * 사라져 되짚을 수도 없다. 채팅 신고가 같은 이유로 앞뒤 {@code roomSeq} 범위를 남긴다.
 *
 * <h2>신고가 사라지면 함께 사라진다</h2>
 * <p>{@code ON DELETE CASCADE}. 부모 없는 사본이 남으면 어느 신고의 것인지 모르는 채 본문만
 * 쌓인다 — {@code comment}·{@code reaction} 이 {@code post} 에 대해 같은 이유로 CASCADE 다.
 */
@Entity
@Table(name = "report_snapshot", indexes = {
        @Index(name = "idx_report_snapshot_report", columnList = "report_id"),
        // report 에서 내려온 인덱스다 (#254). "이 글이 몇 번 신고당했나" 를 세던 자리가
        // 부모에서 자식으로 옮겨졌으므로 인덱스도 함께 옮긴다.
        @Index(name = "idx_report_snapshot_target", columnList = "target_type, target_id"),
})
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PRIVATE)
@Builder
@Check(name = "chk_report_snapshot_role", constraints = "role in ('target','context')")
@Check(name = "chk_report_snapshot_target_type",
        constraints = "target_type in ('community_post','community_comment',"
                + "'chat_message','chat_room')")
// **대상 줄에는 본문이 있어야 한다.** 좌표만 남은 대상은 원본이 지워지면 아무것도 못
// 말하는데, 그것이 이 표가 존재하는 이유다. 맥락 줄은 좌표만일 수 있다 — 채팅의 방이
// 그렇다(신고당하지 않은 사람의 말을 한 줄도 안 베면서 방 id 만 남긴다).
@Check(name = "chk_report_snapshot_target_has_body",
        constraints = "role <> 'target' or body is not null")
public class ReportSnapshot {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "report_id", nullable = false,
            foreignKey = @ForeignKey(name = "fk_report_snapshot_report"))
    @OnDelete(action = OnDeleteAction.CASCADE)
    private Report report;

    /** {@code target} 또는 {@code context}. */
    @Column(name = "role", nullable = false, length = 8)
    private String role;

    /**
     * 무엇을 가리키나 — 이슈 #254 로 {@code report} 부모에서 내려왔다.
     *
     * <p>채팅 신고가 한 건에 메시지 셋까지라 부모 한 칸으로는 안 담겼다. 맥락 줄도 좌표를
     * 든다 — 좌표 없는 사본은 "어느 글의 무엇이었나" 를 못 말한다.
     */
    @Column(name = "target_type", nullable = false, length = 24)
    private String targetType;

    /** 그 도메인 안의 id. <b>FK 는 없다</b> — 원본이 지워져도 신고는 남아야 한다. */
    @Column(name = "target_id", nullable = false)
    private long targetId;

    /**
     * 그 도메인 안의 순번. 채팅은 {@code room_seq}, 커뮤니티는 {@code null} 이다.
     *
     * <p><b>맥락 범위를 이 값으로 다시 센다.</b> 채팅의 {@code context_from/to_seq} 는
     * 대상들의 {@code room_seq} 와 반경 상수에서 완전히 유도되는 파생값이라 따로 안 담는다.
     */
    @Column(name = "target_ordinal")
    private Long targetOrdinal;

    /** 그 글·댓글을 쓴 사람. 탈퇴했으면 {@code null}. */
    @Column(name = "author_user_id")
    private Long authorUserId;

    /**
     * 신고 시점 표시 이름.
     *
     * <p><b>폭은 {@code users.nickname} 과 같은 255 다.</b> #170 이 {@code post.handle} 을 50
     * 으로 잡아 51자 닉네임을 가진 사람의 모든 글쓰기가 영구히 500 이 된 적이 있다. 여기서
     * 좁으면 그 사람이 쓴 글을 <b>아무도 신고할 수 없게</b> 된다.
     */
    @Column(name = "author_name", length = 255)
    private String authorName;

    /** 글이면 제목, 댓글이면 {@code null}. 폭은 {@code post.title} 과 같은 200 이다. */
    @Column(name = "title", length = 200)
    private String title;

    /**
     * 신고 시점 본문.
     *
     * <p><b>대상 줄은 반드시 있다</b> — {@code chk_report_snapshot_target_has_body} 가
     * DB 에서 막는다. 좌표만 담는 맥락 줄(채팅의 방)은 {@code null} 이라 컬럼 자체는
     * nullable 이다.
     */
    @Lob
    @Column(name = "body", columnDefinition = "text")
    private String body;

    /**
     * 본문의 종류. 채팅만 채운다 — 커뮤니티는 {@code null} 이다.
     *
     * <p>이미지 신고와 글 신고가 구분되지 않으면 운영자가 무엇을 봐야 하는지 모른다.
     * 오늘 앱은 {@code text} 만 보내지만, 값이 하나라서 안 담는 것과 담을 자리가 없어서
     * 못 담는 것은 다르다 — 신고는 증거이고, 증거는 나중에 늘릴 수 없다.
     */
    @Column(name = "content_type", length = 16)
    private String contentType;

    /** 그 글·댓글이 쓰인 시각. 담긴 값이 UTC 다. */
    @Column(name = "occurred_at", nullable = false)
    private LocalDateTime occurredAt;
}
