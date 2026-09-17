package com.heattrip.heat_trip_backend.user.signup;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.Optional;

/** 인증 대기 가입 — 이슈 #635. */
public interface PendingSignupRepository extends JpaRepository<PendingSignup, Long> {

    Optional<PendingSignup> findByEmail(String email);

    /**
     * 만료된 대기 행을 지운다.
     *
     * <p>안 지우면 이메일 주소와 비밀번호 해시가 <b>쓸 일이 없는데도</b> 계속 쌓인다.
     * 개인정보를 필요 이상으로 보관하지 않는다는 처리방침과도 어긋난다.
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("delete from PendingSignup p where p.expiresAt < :now")
    int deleteExpired(@Param("now") LocalDateTime now);
}
