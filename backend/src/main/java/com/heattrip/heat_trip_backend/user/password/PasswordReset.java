package com.heattrip.heat_trip_backend.user.password;

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
 * 진행 중인 비밀번호 재설정 한 건 — 이슈 #635 조각 ③.
 *
 * <p>이 행이 있다고 해서 <b>아무것도 바뀌지 않았다.</b> 코드가 맞을 때 비로소
 * {@code users.password} 가 바뀐다. 그래서 남이 내 주소로 재설정을 걸어 놓아도 내 계정은
 * 그대로다 — 나는 메일 한 통을 받을 뿐이다.
 *
 * <p>코드는 해시다. 이 표를 읽을 수 있는 사람이 남의 메일함 없이 남의 비밀번호를 바꿀 수
 * 있으면 인증이라고 할 수 없다.
 */
/*
 * 유니크·인덱스를 **엔티티에 적는다.** mysql/init/01_schema.sql 은 이 엔티티들에서 뽑는
 * 파일이라, 여기 없으면 재생성할 때마다 그 줄이 사라진다 — 그리고 SchemaDdlDriftTest 는
 * 컬럼과 FK 만 보고 인덱스는 안 봐서, 사라진 것을 아무도 못 본다.
 */
@Entity
@Table(
        name = "password_reset",
        uniqueConstraints = {
                @UniqueConstraint(name = "uq_password_reset_user", columnNames = {"user_id"})
        },
        indexes = {
                @Index(name = "idx_password_reset_expires", columnList = "expires_at")
        }
)
@Getter
@Setter
@Builder
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
public class PasswordReset implements AttemptCounting {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * 한 사람에 살아 있는 재설정 하나(UNIQUE).
     *
     * <p>이메일이 아니라 id 인 것은 의도다 — 이메일은 바뀔 수 있고, 바뀌는 순간 살아 있는
     * 재설정이 주인을 잃는다. FK 를 안 거는 이유는 마이그레이션 머리말에 있다.
     */
    @Column(name = "user_id", nullable = false)
    private Long userId;

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
