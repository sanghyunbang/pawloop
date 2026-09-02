package com.heattrip.heat_trip_backend.community.entity;

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
import jakarta.persistence.Lob;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

import org.hibernate.annotations.OnDelete;
import org.hibernate.annotations.OnDeleteAction;

import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

/**
 * 커뮤니티 댓글 한 줄 — 이슈 #169, 문서는 {@code docs/03-database/schema.md §8}.
 *
 * <h2>글이 사라지면 함께 사라진다</h2>
 * <p>{@code post} 로의 FK 가 {@code ON DELETE CASCADE} 다. 안 그러면 지운 글의 댓글이
 * <b>부모 없는 행</b>으로 남아 어느 목록에도 안 뜨면서 자리만 차지한다 — 나중에 세면
 * 댓글 수가 맞지 않고, 왜 안 맞는지 아무도 모른다.
 *
 * <p><b>{@code users} 로의 FK 는 CASCADE 가 아니다.</b> 탈퇴 한 번에 그 사람의 댓글이 전부
 * 사라지면 <b>남의 글에서 대화가 끊긴다</b> — 답글이 무엇에 답한 것인지 알 수 없게 된다.
 * {@code Post} 와 같은 판단이다.
 *
 * <h2>{@code handle} 은 저장 전용이다</h2>
 * <p>{@code Post.handle} 과 같은 이유다 — 응답의 {@code author} 는 {@code PersonRef} 로
 * <b>조회 시점의 현재 닉네임</b>을 싣는다(ADR-0017 규약 5).
 *
 * <p>2026-09 이전 계약의 {@code Comment.author} 에는 <b>사용자 식별자가 아예 없었다</b>.
 * {@code {nickname}} 뿐이라 "내 댓글인가" 판별·프로필 이동·차단이 계약상 불가능했고,
 * 앱은 {@code post_detail_screen.dart} 에서 문자열 {@code '나'} 를 내 댓글 표식으로 쓰고
 * 있었다. {@code PersonRef} 가 그것을 고쳤다.
 *
 * <h2>수정·삭제 컬럼이 없다</h2>
 * <p>{@code updated_at}·{@code deleted_at} 을 넣지 않았다. 계약에 그 오퍼레이션이 없고
 * (#211 {@code Community-medium-4}), <b>넣는 날은 컬럼 추가가 아니라 삭제 정책 결정</b>이다 —
 * 지운 댓글 자리를 목록에서 어떻게 다룰지가 먼저다. 채팅이 {@code deleted_at} 을 두면서
 * 그 질문을 함께 답한 것과 같은 자리다.
 */
@Entity
@Table(
        name = "comment",
        indexes = {
                // 댓글 목록도 커서다 — 계약이 (created_at, id) 로 내려간다.
                @Index(name = "idx_comment_post_created", columnList = "post_id, created_at, id")
        })
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PRIVATE)
@Builder
public class Comment {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** 대상 글. 글이 사라지면 이 행도 사라진다 — 클래스 javadoc 참조. */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "post_id", nullable = false,
            foreignKey = @ForeignKey(name = "fk_comment_post"))
    @OnDelete(action = OnDeleteAction.CASCADE)
    private Post post;

    /** 작성자. 탈퇴해도 댓글은 남는다 — 클래스 javadoc 참조. */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "user_id", nullable = false,
            foreignKey = @ForeignKey(name = "fk_comment_user"))
    private User user;

    @Lob
    @Column(name = "body", nullable = false, columnDefinition = "text")
    private String body;

    /** 작성 시점 닉네임 스냅샷. <b>응답에는 안 싣는다</b> — 클래스 javadoc 참조. */
    @Column(name = "handle", length = 50)
    private String handle;

    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    /** {@code Post} 와 같은 이유로 서버 시계에서 채운다 — 커서의 첫 축이다. */
    @PrePersist
    void onCreate() {
        if (createdAt == null) {
            createdAt = LocalDateTime.now();
        }
    }
}
