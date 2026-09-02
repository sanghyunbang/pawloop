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
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

import org.hibernate.annotations.OnDelete;
import org.hibernate.annotations.OnDeleteAction;

import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

/**
 * 글에 누른 반응 하나 — 이슈 #169, ADR-0016 결정 2, 문서는 {@code docs/03-database/schema.md §9}.
 *
 * <h2>사용자당 글마다 <b>여럿</b>이다</h2>
 * <p>{@code UNIQUE (post_id, user_id, type)} 이 이 표의 불변식이다. 도움돼요·귀여워요·공감은
 * <b>서로 배타적인 개념이 아니다</b> — 한 글이 도움도 되고 귀엽기도 하다.
 *
 * <p>{@code (post_id, user_id)} 로 좁히면 라디오가 되고, 나중에 넓히려면 계약의 파괴적
 * 변경이다. 반대로 지금 넓게 두었다가 좁히려면 <b>행을 지우는 마이그레이션</b>이라 어느
 * 반응을 남길지 제품이 다시 답해야 한다. <b>넓은 쪽이 되돌리기 싸다.</b>
 *
 * <h2>이 UNIQUE 가 멱등을 딛는다</h2>
 * <p>계약의 쓰기는 토글이 아니라 둘이다.
 *
 * <pre>
 *   POST   /api/community/posts/{postId}/reactions/{type}   이미 눌렀어도 200
 *   DELETE /api/community/posts/{postId}/reactions/{type}   안 눌렀어도 200
 * </pre>
 *
 * <p>2026-09 이전에는 {@code POST .../reactions} 하나가 <b>토글</b>이었다. 요청에 의도가
 * 없어서 <b>네트워크 재시도 한 번이 사용자의 반응을 조용히 되돌렸다.</b> 모양은
 * {@code POST /api/chat/blocks} + {@code DELETE /api/chat/blocks/{userId}} 와 같다.
 *
 * <p>동시성으로 이 UNIQUE 가 깨지면 그것은 <b>"이미 눌렀다" 와 같은 뜻</b>이므로 삼키고
 * 최신 집계를 돌려준다. 그게 멱등의 정의다.
 *
 * <h2>카운트는 "몇 번" 이지 "몇 명" 이 아니다</h2>
 * <p>한 사람이 셋을 다 누를 수 있다. 화면이 "7명이 공감했어요" 로 읽히게 쓰면 거짓말이 된다.
 *
 * <h2>{@code @Check} 를 걸지 않는다</h2>
 * <p>{@code CareLog.type} 은 걸었는데 여기는 안 건다. 반응 종류는 <b>제품이 늘릴 수 있는
 * 목록</b>이고(계약의 {@code ReactionType} 이 단일 출처다), 값이 늘 때마다 마이그레이션이
 * 따라오면 그 자체가 비용이다. 케어 종류는 다섯으로 굳었고 늘리는 날이 M4 로 못 박혀 있다 —
 * 그 차이가 이 판단을 가른다.
 */
@Entity
@Table(
        name = "reaction",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_reaction",
                columnNames = {"post_id", "user_id", "type"}),
        indexes = 
                // 탈퇴 시 SET NULL 이 훑는 자리. uq_reaction 의 왼쪽 접두가 post_id 라
                // user_id 단독으로는 그 인덱스를 못 쓴다.
                @Index(name = "idx_reaction_user", columnList = "user_id"))
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PRIVATE)
@Builder
public class Reaction {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** 대상 글. 글이 사라지면 이 행도 사라진다. */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "post_id", nullable = false,
            foreignKey = @ForeignKey(name = "fk_reaction_post"))
    @OnDelete(action = OnDeleteAction.CASCADE)
    private Post post;

    /**
     * 누른 사람. <b>탈퇴하면 {@code null} 이 되고 집계는 남는다</b>({@code ON DELETE SET NULL}).
     *
     * <p>{@code uq_reaction} 의 두 번째 컬럼이라, 탈퇴한 사람의 반응이 {@code null} 로 눕는 순간
     * <b>같은 글에 여러 탈퇴자의 같은 반응이 공존할 수 있다.</b> 그래도 집계는 맞다 — 세는 것은
     * 행 수이지 사람 수가 아니다(클래스 javadoc).
     */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id",
            foreignKey = @ForeignKey(name = "fk_reaction_user"))
    @OnDelete(action = OnDeleteAction.SET_NULL)
    private User user;

    /** {@code help} · {@code cute} · {@code empathy}. 계약의 {@code ReactionType} 이 단일 출처다. */
    @Column(name = "type", nullable = false, length = 20)
    private String type;

    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    @PrePersist
    void onCreate() {
        if (createdAt == null) {
            createdAt = LocalDateTime.now();
        }
    }
}
