package com.heattrip.heat_trip_backend.push.entity;

import com.heattrip.heat_trip_backend.push.PushTime;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.Check;

import java.time.LocalDateTime;

/**
 * 기기 토큰 원장 — 이슈 #83. 한 행이 "이 기기(토큰)는 지금 이 사용자의 것이다" 다.
 *
 * <h2>지우지 않고 {@code revoked_at} 을 찍는다</h2>
 * <p>FCM 이 {@code UNREGISTERED} 를 주거나 사용자가 로그아웃하면 행을 지우는 대신 시각을 찍는다.
 * 지우면 "한 번도 없던 토큰" 과 "죽은 토큰" 을 구별할 수 없다 — {@code refresh_token} 이 같은 이유로
 * 그렇게 한다. 탈퇴만은 행을 지운다 — 개인정보라서다.
 *
 * <h2>토큰이 유일하다</h2>
 * <p>{@code UNIQUE(token)}. 같은 기기에서 다른 계정으로 로그인하면 토큰은 같고 사용자만 바뀐다 —
 * 등록이 upsert 인 이유이고, 그래서 {@code user_id} 는 값만 든다(FK 없음, 이 모듈이 {@code users} 를
 * 모른다).
 */
@Entity
@Table(
        name = "device_token",
        uniqueConstraints = @UniqueConstraint(name = "uk_device_token_token", columnNames = "token"),
        indexes = @Index(name = "idx_device_token_user", columnList = "user_id, revoked_at"))
@Check(name = "chk_device_token_platform", constraints = "platform in ('android','ios')")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class DeviceToken {

    public static final int TOKEN_MAX_LENGTH = 512;

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** {@code users.id} 값만 — FK 없음. */
    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Column(name = "token", nullable = false, length = TOKEN_MAX_LENGTH)
    private String token;

    /** {@code android} 또는 {@code ios}. 계약의 enum 과 같다. */
    @Column(name = "platform", nullable = false, length = 8)
    private String platform;

    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    /** 마지막 등록 시각. 상한을 넘칠 때 이 값이 오래된 것부터 폐기한다. */
    @Column(name = "last_seen_at", nullable = false)
    private LocalDateTime lastSeenAt;

    /** 폐기 시각. {@code null} 이면 살아 있다. */
    @Column(name = "revoked_at")
    private LocalDateTime revokedAt;

    public boolean isActive() {
        return revokedAt == null;
    }

    @PrePersist
    void fillTimestamps() {
        LocalDateTime now = PushTime.nowUtc();
        if (createdAt == null) {
            createdAt = now;
        }
        if (lastSeenAt == null) {
            lastSeenAt = now;
        }
    }
}
