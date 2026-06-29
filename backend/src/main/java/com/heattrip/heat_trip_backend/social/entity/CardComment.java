package com.heattrip.heat_trip_backend.social.entity;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

/**
 * 감정 카드에 달린 댓글.
 * handle 이 null 이면 프론트에서 "익명"으로 표시한다. 본문은 짧은 텍스트(최대 280자)로 제한한다.
 */
@Entity
@Table(name = "card_comment")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class CardComment {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "card_id", nullable = false)
    private Long cardId;

    /** 작성자(현재 인증 사용자)의 PK. */
    @Column(name = "user_id", nullable = false)
    private Long userId;

    /** 표시용 이름(닉네임). null이면 프론트에서 "익명"으로 표시. */
    @Column(name = "handle")
    private String handle;

    /** 짧은 본문(최대 280자). */
    @Column(name = "body", length = 280, nullable = false)
    private String body;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    public void onCreate() {
        this.createdAt = LocalDateTime.now();
    }
}
