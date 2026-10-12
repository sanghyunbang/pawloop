package com.heattrip.heat_trip_backend.moderation;

import com.heattrip.heat_trip_backend.moderation.entity.Block;
import com.heattrip.heat_trip_backend.moderation.repository.BlockRepository;

import org.springframework.context.ApplicationEventPublisher;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.Clock;
import java.util.HashSet;
import java.util.Set;

/**
 * 가리기 — 이슈 #82 완료 조건 3. {@code chat} 모듈의 공개 표면이다.
 *
 * <h2>가리기는 삭제가 아니다</h2>
 * <p>가린 사람의 메시지를 <b>목록에서 빼지 않는다.</b> 빼면 그 {@code room_seq} 가
 * 클라이언트에 도달하지 않고, 미읽음이 {@code room.last_seq − member.last_read_seq}
 * 뺄셈이라 <b>읽음 커서가 그 번호를 못 넘어 뱃지가 영원히 안 지워진다.</b> 소프트 삭제된
 * 메시지를 톰스톤으로 그대로 내려주는 것과 <b>정확히 같은 이유</b>다(ADR-0011).
 *
 * <p>그래서 여기가 답하는 것은 "누구를 접어야 하는가" 하나이고, 접는 것은 응답을 만드는
 * 쪽의 일이다({@code ChatMessages}).
 *
 * <h2>본문을 지워서 내리지 않는다</h2>
 * <p>가려진 자리에 "보기" 가 있다(#82). 눌렀을 때 요청을 한 번 더 보내야 한다면 그 요청은
 * <b>가린 사람만 부르는 경로</b>가 되어 인가를 또 하나 만들어야 한다. 본문은 그대로
 * 내려보내고 앱이 접는다.
 *
 * <p><b>한계를 그대로 적는다.</b> 이 방식은 "안 보이게 하는 것" 이지 "안 받는 것" 이
 * 아니다. 앱을 뜯으면 가려진 본문을 읽을 수 있다. 여기서 막으려는 것은 <b>보고 싶지 않은
 * 말이 눈에 들어오는 것</b>이고, 그것과 기밀은 다른 문제다.
 *
 * <h2>커뮤니티는 다르다 — 목록에서 뺀다</h2>
 * <p>위의 "빼지 않는다" 는 <b>채팅</b>의 이유다(미읽음 커서). 커뮤니티 목록에는 그런 커서가 없고,
 * 애플 지침 1.2 가 "차단한 사람의 콘텐츠는 피드에서 즉시 사라져야 한다" 고 요구한다. 그래서
 * {@code community} 는 이 클래스가 답한 {@link #blockedBy} 를 목록 쿼리의 조건으로 넣어 아예 안
 * 내려준다 — 판단은 그쪽 javadoc 에 있다. 여기는 "누구를" 에만 답하는 것이 그대로다.
 *
 * <h2>차단하면 운영자에게 알린다</h2>
 * <p>1.2 의 또 하나의 조건이다 — 차단은 개발자에게도 알려야 한다. 이 모듈은 아무도 못 부르므로
 * {@link UserBlocked} 를 발행하고, 듣는 쪽이 슬랙으로 알린다({@link Reports} 와 같은 모양).
 */
@Service
@Transactional(readOnly = true)
public class Blocks {

    private final BlockRepository blocks;
    private final Clock clock;

    /**
     * "차단됐다" 를 밖으로 말하는 유일한 통로. 누가 듣는지 모르고, 듣는 쪽이 없어도 서버는 뜬다 —
     * {@link Reports} 의 같은 필드와 같은 판단이다.
     */
    private final ApplicationEventPublisher events;

    public Blocks(BlockRepository blocks, Clock clock, ApplicationEventPublisher events) {
        this.blocks = blocks;
        this.clock = clock;
        this.events = events;
    }

    /**
     * 이 사람이 가린 사람들.
     *
     * <p>메시지 한 장(최대 100건)마다 <b>한 번</b> 부른다. 메시지마다 "가렸나" 를 물으면
     * 100건 조회에 쿼리가 101개다 — {@code ChatSenderNames} 가 같은 함정을 이미 피해 뒀다.
     */
    public Set<Long> blockedBy(long blockerUserId) {
        return new HashSet<>(blocks.findBlockedIdsOf(blockerUserId));
    }

    /**
     * 가린다. 이미 가려 뒀으면 아무것도 바꾸지 않는다.
     *
     * <p><b>자기 자신은 못 가린다.</b> 허용하면 자기 메시지가 자기 화면에서 접히고, 그건
     * 사용자가 원할 수 있는 상태가 아니라 실수다.
     *
     * <p><b>새로 가렸을 때만</b> {@link UserBlocked} 를 발행한다. 트랜잭션 <b>안</b>에서 내고, 듣는 쪽이
     * {@code AFTER_COMMIT} 으로 받으므로 롤백이면 안 나간다. 이미 가려 둔 사람이면 바뀐 것이 없으니
     * 알릴 것도 없다.
     *
     * @return 이번에 새로 가렸으면 {@code true}, 이미 가려져 있었으면 {@code false}
     */
    @Transactional
    public boolean block(long blockerUserId, long blockedUserId) {
        if (blockerUserId == blockedUserId) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "자기 자신은 가릴 수 없습니다.");
        }
        if (blocks.existsByBlockerUserIdAndBlockedUserId(blockerUserId, blockedUserId)) {
            return false;
        }

        try {
            Block saved = blocks.save(Block.builder()
                    .blockerUserId(blockerUserId)
                    .blockedUserId(blockedUserId)
                    .createdAt(ModerationTime.nowUtc(clock))
                    .build());
            events.publishEvent(new UserBlocked(saved.getId(), blockerUserId, blockedUserId,
                    ModerationTime.toInstant(saved.getCreatedAt())));
            return true;
        } catch (DataIntegrityViolationException alreadyBlocked) {
            // 두 요청이 동시에 통과했다. UNIQUE 가 마지막 방어선이고, 여기서는 그것을
            // 오류로 올리지 않는다 — 결과가 "가려져 있다" 로 같기 때문이다 (📌 #86 원칙 5).
            return false;
        }
    }

    /**
     * 가리기를 푼다.
     *
     * <p>없던 것을 풀어도 성공이다 — 계약이 204 하나만 선언했고, 있고 없고를 상태 코드로
     * 알려 주면 <b>가려 뒀는지를 응답으로 물어볼 수 있게</b> 된다.
     */
    @Transactional
    public void unblock(long blockerUserId, long blockedUserId) {
        blocks.deleteBlock(blockerUserId, blockedUserId);
    }
}
