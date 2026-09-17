package com.heattrip.heat_trip_backend.user.signup;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.LocalDateTime;

import com.heattrip.heat_trip_backend.user.UserTime;
import com.heattrip.heat_trip_backend.user.verification.AttemptCounting;

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
/*
 * 유니크·인덱스를 **엔티티에 적는다.** mysql/init/01_schema.sql 은 이 엔티티들에서 뽑는
 * 파일이라, 여기 없으면 재생성할 때마다 그 줄이 사라진다 — 그리고 SchemaDdlDriftTest 는
 * 컬럼과 FK 만 보고 인덱스는 안 봐서, 사라진 것을 아무도 못 본다.
 */
@Entity
@Table(
        name = "pending_signup",
        uniqueConstraints = {
                @UniqueConstraint(name = "uq_pending_signup_email", columnNames = {"email"})
        },
        indexes = {
                @Index(name = "idx_pending_signup_expires", columnList = "expires_at")
        }
)
@Getter
@Setter
@Builder
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
public class PendingSignup implements AttemptCounting {

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
}
