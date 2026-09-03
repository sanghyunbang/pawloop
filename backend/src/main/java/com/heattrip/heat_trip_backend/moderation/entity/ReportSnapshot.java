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
})
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PRIVATE)
@Builder
@Check(name = "chk_report_snapshot_role", constraints = "role in ('target','context')")
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

    @Lob
    @Column(name = "body", nullable = false, columnDefinition = "text")
    private String body;

    /** 그 글·댓글이 쓰인 시각. 담긴 값이 UTC 다. */
    @Column(name = "occurred_at", nullable = false)
    private LocalDateTime occurredAt;
}
