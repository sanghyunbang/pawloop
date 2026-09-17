package com.heattrip.heat_trip_backend.user.password;

import com.heattrip.heat_trip_backend.user.verification.ExpiringRows;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.Optional;

/** 진행 중인 비밀번호 재설정 — 이슈 #635 조각 ③. */
public interface PasswordResetRepository extends JpaRepository<PasswordReset, Long>, ExpiringRows {

    Optional<PasswordReset> findByUserId(Long userId);

    /**
     * 만료된 재설정 행을 지운다.
     *
     * <p>{@link ExpiringRows} 의 선언을 여기서 다시 적는 것은 지울 엔티티 이름이 여기에만
     * 있기 때문이다. 부르는 쪽({@code VerificationPurgeScheduler})은 인터페이스만 본다.
     */
    @Override
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("delete from PasswordReset r where r.expiresAt < :now")
    int deleteExpired(@Param("now") LocalDateTime now);

    @Override
    default String rowName() {
        return "비밀번호 재설정";
    }
}
