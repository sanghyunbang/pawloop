package com.heattrip.heat_trip_backend.chat.repository;

import com.heattrip.heat_trip_backend.chat.entity.ChatRoomInvite;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.Optional;

/**
 * 초대코드 조회·소비·회수 — 이슈 #74·#75.
 *
 * <p>{@code findByCode} 가 유일한 조회 경로다. UNIQUE 라 "코드 1개 = 행 1개" 이고,
 * 그게 깨지면 어느 행을 줄지 미정이 된다({@code refresh_token.token_hash} 와 같은 계열).
 *
 * <h2>쓰기 둘은 전부 조건부 UPDATE 다 — 영향 행 수가 판정이다</h2>
 * <p>{@code RefreshTokenRepository.revokeIfLive}(#9)가 이 저장소에 세운 방식 그대로다.
 * "읽어서 확인하고 자바에서 판단한 뒤 쓴다" 는 두 문장 사이에 다른 요청이 들어오고,
 * 그 창이 실제로 벌어지는 자리가 여기다 — 마지막 한 자리를 두 사람이 동시에 쓰는 순간
 * {@code used_count} 가 상한을 넘는다. 조건을 {@code WHERE} 절에 넣으면 InnoDB 행 잠금
 * 위에서 원자적 CAS 가 되고, 인스턴스가 몇 대든 정확히 한 요청만 1을 받는다
 * (📌 #86 원칙 5).
 */
public interface ChatRoomInviteRepository extends JpaRepository<ChatRoomInvite, Long> {

    Optional<ChatRoomInvite> findByCode(String code);

    /**
     * 코드가 가리키는 방 id <b>하나만</b> 읽는다. 엔티티를 만들지 않는 것이 요점이다.
     *
     * <p>참여 경로가 가장 먼저 부르는 문장이다({@code ChatRoomService.joinByInviteCode}).
     * 방을 잠그려면 방 id 를 알아야 하는데, 그 id 를 얻자고 {@code findByCode} 로 엔티티를
     * 먼저 읽으면 그 엔티티가 <b>영속성 컨텍스트에 눌러앉아</b> 잠금을 얻은 뒤에 다시 읽어도
     * 낡은 값이 그대로 돌아온다(Hibernate 는 이미 관리 중인 인스턴스를 덮어쓰지 않는다).
     * 스칼라 투영은 그 문제가 없다 — 잠금 뒤의 {@code findByCode} 가 DB 를 실제로 읽는다.
     *
     * <p>{@code i.room.id} 는 조인을 만들지 않는다. {@code chat_room_invite.room_id} 를
     * 그대로 읽는다 — 경계를 넘지 않는다.
     */
    @Query("select i.room.id from ChatRoomInvite i where i.code = :code")
    Optional<Long> findRoomIdByCode(@Param("code") String code);

    /** 발급 직후 중복 확인용. 최종 방어선은 {@code UNIQUE (code)} 다. */
    boolean existsByCode(String code);

    /** 회수는 방 안에서만 한다 — 남의 방 코드를 회수하는 경로를 만들지 않기 위해서다. */
    Optional<ChatRoomInvite> findByRoomIdAndCode(Long roomId, String code);

    /**
     * 아직 쓸 수 있을 때만 사용 횟수를 하나 올린다. <b>영향 행 수가 곧 경합의 승패다.</b>
     *
     * <p>{@code 1} 이면 이 요청이 자리 하나를 얻었고, {@code 0} 이면 읽어 본 뒤 쓰기 전에
     * 코드가 만료·폐기됐거나 마지막 자리를 다른 요청이 가져갔다는 뜻이다. 어느 쪽인지는
     * 호출부가 다시 읽어 판정한다 — 그래야 앱에 나가는 코드가 정확해진다.
     *
     * <p><b>이 문장이 참여 경로의 직렬화 지점이기도 하다.</b> 성공한 트랜잭션은 커밋까지
     * 이 초대 행의 배타 잠금을 쥐므로, <b>같은 코드로 동시에 들어오는 참여는 줄을 선다.</b>
     * 정원 검사가 그 뒤에 오는 것이 그래서 의미가 있다.
     *
     * <p>실패하면 호출부가 예외를 던지고 트랜잭션이 통째로 롤백된다 — 즉 <b>참여에 실패한
     * 요청은 사용 횟수를 쓰지 않는다.</b> 이건 {@code revokeIfLive} 와 반대로 호출부와 같은
     * 트랜잭션이어야 성립한다.
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update ChatRoomInvite i
               set i.usedCount = i.usedCount + 1
             where i.id = :id
               and i.revokedAt is null
               and (i.expiresAt is null or i.expiresAt > :now)
               and (i.maxUses is null or i.usedCount < i.maxUses)
            """)
    int consumeOneUse(@Param("id") Long id, @Param("now") LocalDateTime now);

    /**
     * 살아 있을 때만 회수한다. <b>행을 지우지 않는다</b> — 지우면 "회수된 코드" 와
     * "없던 코드" 가 구별되지 않아 410 과 404 가 뭉개진다(#9 의 {@code refresh_token} 과 같은 이유).
     *
     * <p>최초 회수 시각을 덮어쓰지 않는 것도 같은 계열이다 — 그 값이 사건 기록이다.
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("update ChatRoomInvite i set i.revokedAt = :now where i.id = :id and i.revokedAt is null")
    int revokeIfLive(@Param("id") Long id, @Param("now") LocalDateTime now);
}
