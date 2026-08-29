package com.heattrip.heat_trip_backend.user.repository;

import com.heattrip.heat_trip_backend.user.entity.RefreshToken;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.Optional;

/**
 * Refresh Token 원장 접근. (이슈 #9)
 *
 * <p><b>이메일 기반 메서드를 만들지 않는다.</b> 인증 주체는 {@code users.id} 하나이며
 * public {@code findByEmail} 기반 규약은 #5 가 걷어냈다. 이슈 본문에 남아 있는
 * {@code deleteByEmail} 은 그 시절 초안이다 — 되살리지 않는다.
 *
 * <p>수정 쿼리에 {@code @Transactional} 이 <b>메서드마다</b> 붙어 있는 것은 의도다.
 * 재사용 감지는 "전량 폐기를 커밋한 뒤 401 을 던지는" 동작이라, 호출부를 하나의
 * 트랜잭션으로 감싸면 던지는 순간 그 폐기가 <b>함께 롤백된다</b>. 폐기가 각자
 * 커밋되어야 완료 조건 4(재시도 직후 새 RT 도 401)가 실제로 성립한다.
 */
public interface RefreshTokenRepository extends JpaRepository<RefreshToken, Long> {

    /** 회전의 시작점. token_hash 는 UNIQUE 라 많아야 한 행이다. */
    Optional<RefreshToken> findByTokenHash(String tokenHash);

    /**
     * 살아 있을 때만 폐기한다. <b>영향 행 수가 곧 경합의 승패다.</b>
     *
     * <p>{@code 1} 이면 이 요청이 회전 권한을 얻었고, {@code 0} 이면 이미 폐기된
     * 토큰이거나 같은 토큰을 동시에 보낸 다른 요청에 졌다는 뜻이다. 두 경우 모두
     * 서버가 구별할 수단이 없고 대응도 같으므로 <b>한 코드 경로</b>로 합친다.
     *
     * <p>{@code where ... and revokedAt is null} 이 InnoDB 행 잠금 위에서 그대로
     * 원자적 CAS 가 된다 — 별도 락 테이블도, 유예 창도 필요 없다.
     */
    @Transactional
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("update RefreshToken r set r.revokedAt = :now where r.id = :id and r.revokedAt is null")
    int revokeIfLive(@Param("id") Long id, @Param("now") LocalDateTime now);

    /**
     * 그 사용자의 <b>살아 있는</b> RT 를 전부 폐기한다. 전 기기 로그아웃과 재사용 감지가 쓴다.
     *
     * <p>이미 폐기된 행의 {@code revoked_at} 을 덮어쓰지 않는 이유: 최초 폐기 시각이
     * 사건 기록이다. 나중에 덮어쓰면 언제 무슨 일이 있었는지 알 수 없게 된다.
     */
    @Transactional
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("update RefreshToken r set r.revokedAt = :now where r.userId = :userId and r.revokedAt is null")
    int revokeAllByUserId(@Param("userId") Long userId, @Param("now") LocalDateTime now);

    /**
     * 탈퇴 정리. 폐기가 아니라 삭제다 — 사용자가 사라지면 원장에 남길 이유가 없다.
     *
     * <p>파생 쿼리가 아니라 {@code @Query} 인 이유: 파생 삭제는 Spring Data 가 대상 행을
     * 전부 SELECT 해 영속화한 뒤 {@code EntityManager.remove} 를 <b>행마다</b> 부른다
     * (실측: {@code delete from refresh_token where id=?} 가 행 수만큼). 폐기 두 건은
     * 이미 단일 벌크 UPDATE 인데 삭제만 N+1 이던 것을 맞춘 것이다.
     */
    @Transactional
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("delete from RefreshToken r where r.userId = :userId")
    int deleteByUserId(@Param("userId") Long userId);

    /**
     * 만료 정리. 폐기 여부와 무관하게 지운다 — 만료된 토큰은 어차피 401 이다.
     *
     * <p>야간 정리 잡이 부르는 메서드다. 대상이 "가장 많이 쌓인 시점의 행 전량" 이라
     * 행별 DELETE 가 가장 나쁘게 작용하던 자리다 — 한 트랜잭션 안에서 N번 왕복하며
     * InnoDB 행 잠금이 누적된다. 단일 벌크 DELETE 한 문장으로 보낸다.
     *
     * <p>한 번에 지우는 양을 {@code LIMIT} 으로 잘라 잠금 시간을 줄이는 것은 아직 하지
     * 않았다 — JPQL 에 {@code LIMIT} 이 없어 네이티브 쿼리 + 반복이 필요하고, 그 형태가
     * 정당해지는 행 수(수십만 건)에 아직 도달하지 않았다. 도달하면 #14 와 함께 본다.
     */
    @Transactional
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("delete from RefreshToken r where r.expiresAt < :cutoff")
    int deleteByExpiresAtBefore(@Param("cutoff") LocalDateTime cutoff);
}
