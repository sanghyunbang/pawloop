package com.heattrip.heat_trip_backend.chat.repository;

import com.heattrip.heat_trip_backend.chat.entity.ChatRoom;

import jakarta.persistence.LockModeType;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Optional;

/**
 * 방 조회. 출처 쌍으로 찾는 것이 유일한 진입점이다 — 이슈 #74.
 *
 * <p>{@code findByOriginKindAndOriginRef} 는 조회일 뿐 <b>확인-후-쓰기의 근거가 아니다.</b>
 * "없으면 만든다" 를 이 조회로 판정하면 두 요청이 동시에 통과한다. 중복을 막는 것은
 * {@code UNIQUE (origin_kind, origin_ref)} 이고, 진 쪽은 예외를 받는다(ADR-0011 · 원칙 5).
 */
public interface ChatRoomRepository extends JpaRepository<ChatRoom, Long> {

    Optional<ChatRoom> findByOriginKindAndOriginRef(String originKind, String originRef);

    /**
     * 이 방의 <b>멤버가 바뀌는 트랜잭션</b>을 한 줄로 세운다 — 이 저장소의 첫 명시적 락이다.
     *
     * <h2>왜 락인가 — 원칙 5 의 1·2번으로는 안 됐다</h2>
     * <p>📌 #86 원칙 5 는 유니크 제약 → 조건부 UPDATE 의 영향 행 수 → 락 순서로 시도하라고
     * 한다. 참여 경로는 앞의 둘을 이미 쓰고 있었고, 그 상태로 <b>실제 스레드를 띄워 보니
     * 둘 다 500 을 냈다.</b>
     * <ul>
     *   <li>서로 다른 사람이 서로 다른 코드로 같은 방에 동시 참여 →
     *       {@code Deadlock found when trying to get lock} → 500. 4명 동시에 3명이 졌다.
     *       {@code ChatRoomMemberRepository#insertMemberIfRoomHasSpace} 가 같은 문장 안에서
     *       {@code chat_room_member} 를 room_id 범위로 훑으면서(정원 세는 서브쿼리) 같은
     *       범위에 INSERT 하기 때문이다.</li>
     *   <li>같은 사람이 같은 코드로 동시 참여 → {@code Duplicate entry ... uq_chat_member}
     *       → 500. 뒤에 온 요청이 "멤버 아님" 스냅샷을 들고 초대 행 잠금을 기다렸다가,
     *       풀린 뒤에도 그 낡은 값으로 INSERT 로 내려갔기 때문이다.</li>
     * </ul>
     * <p>둘 다 계약에 없는 코드이고(참여 오퍼레이션은 200·401·403·404·409·410 만 선언한다),
     * 뒤의 것은 <b>이미 가입에 성공한 사람에게 실패 화면을 보여 준다.</b>
     *
     * <h2>락 순서 — 바꾸면 데드락이 돌아온다</h2>
     * <p>원칙 5 가 요구하는 대로 못 박는다. 참여 트랜잭션은 <b>언제나</b> 이 순서로 잠근다.
     * <pre>
     *   chat_room (이 메서드)  →  chat_room_invite (consumeOneUse)  →  chat_room_member (INSERT/UPDATE)
     * </pre>
     * <p>발급({@code issueInvite})과 회수({@code revokeInvite})는 {@code chat_room_invite}
     * 하나만 잡으므로 순환이 생기지 않는다. <b>새 경로가 이 셋 중 둘 이상을 잡게 되면
     * 반드시 같은 순서로 잡아라.</b> {@code chat_room.last_seq} 발급(#78)이 그 첫 후보다.
     *
     * <p>락 범위는 참여 트랜잭션 하나이고 그 안에서 <b>밖으로 나가는 호출을 하지 않는다</b> —
     * {@code innodb_lock_wait_timeout} 기본 50초 때문에 느린 호출 하나가 그 방의 참여를
     * 전부 막는다(원칙 5).
     *
     * <p>락으로 만든 결과는 {@code UNIQUE (room_id, user_id)} 가 한 번 더 받친다. 락이
     * 빠지거나 순서가 틀려도 데이터가 오염되지는 않는다 — 그때 나는 것이 위의 500 이다.
     *
     * @return 방이 있으면 그 행(잠긴 상태), 없으면 비어 있다
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select r from ChatRoom r where r.id = :id")
    Optional<ChatRoom> lockForMemberChange(@Param("id") Long id);
}
