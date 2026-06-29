package com.heattrip.heat_trip_backend.social.entity;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

/**
 * 공유된 "감정 카드" 엔티티.
 * 사용자가 자신의 감정 기록을 opt-in으로 공개하면 한 장의 카드로 "함께" 피드에 노출된다.
 * 개인정보 보호 원칙(opt-in, 가벼움, 댓글 없음)에 따라 본문은 짧은 텍스트로 제한한다.
 */
@Entity
@Table(name = "emotion_card")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class EmotionCard {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** 작성자(현재 인증 사용자)의 PK. JWT에서 식별한 User.getId(). */
    @Column(name = "user_id", nullable = false)
    private Long userId;

    /** 표시용 이름(닉네임). null이면 프론트에서 "익명"으로 표시. */
    @Column(name = "handle")
    private String handle;

    /** 6개 무드 SSOT 한국어 키: 기쁨/슬픔/불안/분노/평온/설렘 */
    @Column(name = "mood_key", nullable = false)
    private String moodKey;

    /** 장소명(선택). */
    @Column(name = "place_name")
    private String placeName;

    /** 추천 장소의 contentid 등 식별자(선택). */
    @Column(name = "place_id")
    private Long placeId;

    /** 짧은 본문(최대 280자). */
    @Column(name = "body", length = 280)
    private String body;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    public void onCreate() {
        this.createdAt = LocalDateTime.now();
    }
}
