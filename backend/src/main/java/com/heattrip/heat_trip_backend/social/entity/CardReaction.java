package com.heattrip.heat_trip_backend.social.entity;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

/**
 * 감정 카드에 대한 "감정 리액션".
 * 좋아요가 아니라 3종 감정 반응(SAME/CHEER/CALM)이며, 한 사용자는 카드별·타입별로 1회만 토글한다.
 * (cardId, userId, reactionType) 조합에 유니크 제약을 둬 중복 삽입을 막는다.
 */
@Entity
@Table(
        name = "card_reaction",
        uniqueConstraints = @UniqueConstraint(
                name = "uk_card_reaction_card_user_type",
                columnNames = {"card_id", "user_id", "reaction_type"}
        )
)
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class CardReaction {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "card_id", nullable = false)
    private Long cardId;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    /** SAME | CHEER | CALM */
    @Column(name = "reaction_type", nullable = false)
    private String reactionType;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    public void onCreate() {
        this.createdAt = LocalDateTime.now();
    }
}
