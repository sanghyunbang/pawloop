package com.heattrip.heat_trip_backend.push.entity;

import com.heattrip.heat_trip_backend.push.PushTime;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.LocalDateTime;

/**
 * 사용자별 알림 설정 — "전체 끄기" 하나 (이슈 #83).
 *
 * <p>행이 없으면 켜진 것이다. 그래서 가입 때 행을 만들지 않고, 처음 끄는 순간 생긴다.
 * 방별 음소거는 여기 없다 — 멤버십의 속성이라 {@code chat_room_member.muted_at} 이다.
 */
@Entity
@Table(name = "push_preference")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class PushPreference {

    /** {@code users.id} 값 — FK 없음. */
    @Id
    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Builder.Default
    @Column(name = "enabled", nullable = false)
    private boolean enabled = true;

    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;

    @PrePersist
    @PreUpdate
    void stamp() {
        updatedAt = PushTime.nowUtc();
    }
}
