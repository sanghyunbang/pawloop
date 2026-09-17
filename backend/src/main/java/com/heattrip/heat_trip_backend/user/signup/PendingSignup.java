package com.heattrip.heat_trip_backend.user.signup;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.LocalDateTime;

import com.heattrip.heat_trip_backend.user.UserTime;

/**
 * 인증을 기다리는 가입 한 건 — 이슈 #635.
 *
 * <p><b>사용자가 아니다.</b> 코드가 맞을 때 비로소 {@code users} 행이 생긴다. 이 표에 있는
 * 동안에는 로그인도, 이메일 중복 판정도 이 행과 무관하다 — 남이 내 주소로 시도만 해 놓고
 * 그 주소를 막아 두는 일이 없어야 한다.
 *
 * <p>비밀번호와 코드는 <b>둘 다 해시</b>다. 이 표를 읽을 수 있는 사람이 남의 메일함 없이
 * 가입을 마칠 수 있으면 인증이라고 할 수 없다.
 */
@Entity
@Table(name = "pending_signup")
@Getter
@Setter
@Builder
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
public class PendingSignup {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** 이메일 하나에 대기 행 하나(UNIQUE). 다시 요청하면 옛 행을 덮어쓴다. */
    @Column(name = "email", nullable = false, length = 255)
    private String email;

    @Column(name = "password_hash", nullable = false, length = 255)
    private String passwordHash;

    @Column(name = "nickname", nullable = false, length = 100)
    private String nickname;

    @Column(name = "code_hash", nullable = false, length = 255)
    private String codeHash;

    @Column(name = "expires_at", nullable = false)
    private LocalDateTime expiresAt;

    @Column(name = "attempts", nullable = false)
    @Builder.Default
    private int attempts = 0;

    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    /** 빌더가 값을 넣으면 이 가드를 비켜 간다 — UTC 로 눕힌다(#248). */
    @PrePersist
    void stampCreatedAt() {
        if (createdAt == null) {
            createdAt = UserTime.nowUtc();
        }
    }

    public boolean isExpired(LocalDateTime now) {
        return expiresAt.isBefore(now);
    }
}
