package com.heattrip.heat_trip_backend.push.repository;

import com.heattrip.heat_trip_backend.push.entity.DeviceToken;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.Collection;
import java.util.List;
import java.util.Optional;

public interface DeviceTokenRepository extends JpaRepository<DeviceToken, Long> {

    Optional<DeviceToken> findByToken(String token);

    /** 살아 있는 토큰 — 오래 안 보인 것이 앞이다. 상한을 넘칠 때 앞에서부터 폐기한다. */
    List<DeviceToken> findByUserIdAndRevokedAtIsNullOrderByLastSeenAtAscIdAsc(Long userId);

    List<DeviceToken> findByUserIdInAndRevokedAtIsNull(Collection<Long> userIds);

    List<DeviceToken> findByUserId(Long userId);

    /**
     * 사용자의 살아 있는 토큰을 전부 폐기한다 — 로그아웃(전 기기). 멱등이다.
     *
     * @return 폐기한 행 수
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("update DeviceToken t set t.revokedAt = :now where t.userId = :userId and t.revokedAt is null")
    int revokeAllOf(@Param("userId") Long userId, @Param("now") LocalDateTime now);

    /** FCM 이 죽었다고 답한 토큰들. 이미 폐기된 것은 그대로 둔다. */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("update DeviceToken t set t.revokedAt = :now where t.token in :tokens and t.revokedAt is null")
    int revokeTokens(@Param("tokens") Collection<String> tokens, @Param("now") LocalDateTime now);

    /** 탈퇴 — 개인정보라 행을 지운다. */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("delete from DeviceToken t where t.userId = :userId")
    int deleteAllOf(@Param("userId") Long userId);
}
