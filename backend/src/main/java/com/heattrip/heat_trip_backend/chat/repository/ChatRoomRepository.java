package com.heattrip.heat_trip_backend.chat.repository;

import com.heattrip.heat_trip_backend.chat.entity.ChatRoom;

import jakarta.persistence.LockModeType;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
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
     *   chat_room  →  chat_room_invite  →  chat_room_member  →  chat_message
     *   (이 메서드)     (consumeOneUse)     (INSERT/UPDATE)      (전송 INSERT)
     * </pre>
     * <p>발급({@code issueInvite})과 회수({@code revokeInvite})는 {@code chat_room_invite}
     * 하나만 잡으므로 순환이 생기지 않는다. <b>새 경로가 이 넷 중 둘 이상을 잡게 되면
     * 반드시 같은 순서로 잡아라.</b>
     *
     * <p><b>{@code chat_message} 를 맨 뒤에 둔 것이 #78 의 판단이다.</b> 전송 경로
     * ({@code ChatRoomService#postMessage})는 {@link #assignNextSeq} 로 <b>첫 칸</b>을 잡고
     * 메시지를 넣으므로 넷 중 첫째와 넷째만 쓴다 — 참여 경로가 쓰는 앞의 셋과 같은
     * 방향의 부분열이라 순환이 없다. 메시지 행은 언제나 덧붙이기만 하고 방보다 먼저
     * 잠길 일이 없어서 맨 뒤가 자연스러운 자리다. 반대로 <b>메시지를 먼저 잠그고 방을
     * 잠그는 경로를 하나라도 만들면</b> 그 순간 데드락이 가능해진다.
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

    /**
     * 이 방의 다음 {@code room_seq} 를 발급한다 — 이슈 #78. <b>한 문장이 잠금이자 증가다.</b>
     *
     * <h2>왜 읽고 더해서 쓰지 않는가 — 실측</h2>
     * <p>가장 자연스러운 판은 방을 읽어 {@code lastSeq + 1} 을 쓰는 것이다. 그렇게 짜고
     * 스레드 20개를 같은 방에 붙였더니 <b>20개 중 17개가 죽었다</b>(성공 3건) —
     * {@code Duplicate entry '1-1' for key 'chat_message.uq_chat_room_seq'} 와
     * {@code '1-2'}. 두 트랜잭션이 같은 값을 읽고 같은 번호를 쓰기 때문이고,
     * {@code READ_COMMITTED} 에서도 <b>평범한 SELECT 는 잠그지 않는다.</b>
     * ({@code ChatMessageIntegrationTest} 의 20스레드 테스트가 그 자리다.)
     *
     * <p>{@code UPDATE … SET last_seq = last_seq + 1} 로 고쳐도 <b>절반만</b> 낫는다.
     * 증가 자체는 원자적이지만 <b>내가 받은 번호가 몇인지</b>를 다시 SELECT 로 읽어야 하고,
     * 그 사이에 남이 또 올렸으면 남의 번호를 읽는다. 두 문장 사이를 닫는 것은 이 문장이
     * 잡는 행 잠금인데, 그러면 잠금에 기대는 이유를 주석에 적어야 유지된다.
     *
     * <p>그래서 MySQL 이 문서로 제시한 방식을 그대로 쓴다 —
     * {@code LAST_INSERT_ID(expr)} 는 값을 <b>세션에 기억시키면서</b> 그대로 돌려준다.
     * 증가와 "내 번호" 가 한 문장에 있고, 세션 값이라 다른 커넥션이 끼어들 수 없다.
     * https://dev.mysql.com/doc/refman/8.0/en/information-functions.html#function_last-insert-id
     *
     * <h2>락 순서</h2>
     * <p>이 문장이 잡는 것은 {@code chat_room} 행의 배타 잠금이고 커밋까지 쥔다.
     * {@link #lockForMemberChange} 가 못 박은 순서의 <b>첫 칸</b>이 그것이라, 전송 경로와
     * 참여 경로가 같은 방향으로 줄을 선다:
     * {@code chat_room → chat_room_invite → chat_room_member → chat_message}.
     *
     * <h2>계측 자리</h2>
     * <p>방 단위 직렬화라 방이 시끄러우면 여기서 기다린다. 그 대기를 볼 이름은
     * <b>{@code chat.seq.assign}</b> Timer 다 — 이름만 여기 잡아 두고, 실제 계측은 rate
     * limit 이슈에서 함께 붙인다(#78 "무엇을" 마지막 항목). 그때 볼 것은 평균이 아니라
     * p99 와 {@code innodb_lock_wait_timeout}(기본 50초) 근처의 꼬리다.
     *
     * @return 1 이면 발급했고, 0 이면 그런 방이 없다. 발급한 값은
     *         {@link #lastAssignedSeq()} 로 <b>같은 트랜잭션 안에서</b> 읽는다
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query(value = "UPDATE chat_room SET last_seq = LAST_INSERT_ID(last_seq + 1) WHERE id = ?1",
            nativeQuery = true)
    int assignNextSeq(long roomId);

    /**
     * 바로 앞 {@link #assignNextSeq} 가 이 세션에 남긴 번호.
     *
     * <p><b>{@code assignNextSeq} 직후에, 같은 트랜잭션에서, AUTO_INCREMENT INSERT 보다
     * 먼저 불러야 한다.</b> {@code LAST_INSERT_ID()} 는 세션 하나에 값 하나이고,
     * {@code chat_message} INSERT 가 그 값을 자기 {@code id} 로 덮어쓴다.
     *
     * <p>{@code CAST(... AS SIGNED)} 를 씌우는 이유는 타입이다 — {@code LAST_INSERT_ID()} 는
     * {@code BIGINT UNSIGNED} 라 드라이버가 {@code BigInteger} 를 줄 수 있고, 그러면
     * {@code Long} 으로 받는 이 시그니처가 실행 시점에 깨진다.
     */
    @Query(value = "SELECT CAST(LAST_INSERT_ID() AS SIGNED)", nativeQuery = true)
    long lastAssignedSeq();

    /**
     * 방의 {@code origin_kind} 만. <b>메트릭 태그 하나를 위한 것이다.</b> (이슈 #80)
     *
     * <p>엔티티를 읽지 않는 이유가 있다. {@code postMessage} 는 방을 프록시로만 든다 —
     * 엔티티를 읽어 오면 그 스냅샷의 낡은 {@code last_seq} 가 플러시 순서에 따라
     * {@link #assignNextSeq} 를 덮어쓸 여지가 생긴다. 그 판단을 메트릭 때문에 뒤집지 않는다.
     *
     * <p><b>비용을 정직하게 적는다.</b> 이건 전송 경로에 붙는 <b>추가 왕복 한 번</b>이다.
     * PK 조회라 싸지만 0은 아니다. 잠금을 잡기 <b>전에</b> 부르므로 직렬화 구간을 늘리지는
     * 않는다. 값이 필요한 이유는 방 종류가 둘이기 때문이다(가족 · 산책 크루, ADR-0011) —
     * 태그가 없으면 "산책 크루 채팅이 죽었는데 가족 채팅이 멀쩡한 상태" 를 구분할 수 없다.
     */
    @Query("select r.originKind from ChatRoom r where r.id = :id")
    Optional<String> findOriginKindById(@Param("id") long id);
}
