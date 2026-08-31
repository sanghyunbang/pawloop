package com.heattrip.heat_trip_backend.chatweb;

import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import lombok.RequiredArgsConstructor;

import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 메시지의 {@code senderUserId} 를 <b>화면에 쓸 이름</b>으로 바꾼다 — 이슈 #78 완료 조건 3·4.
 *
 * <h2>이 클래스가 chat 밖에 있는 것이 요점이다</h2>
 * <p>이슈 본문의 두 요구가 그대로는 함께 성립하지 않는다.
 * <ul>
 *   <li>완료 조건 4 — 닉네임을 바꾸면 <b>과거 메시지 응답도</b> 새 닉네임으로 나온다.
 *       그러려면 응답을 만들 때 {@code users} 의 <b>현재</b> 값을 읽어야 한다.</li>
 *   <li>그런데 {@code ChatBoundaryArchitectureTest} 의 §B·§C 가 chat 의 main 소스에서
 *       {@code users} 를 이름으로 부르는 것도 조인하는 것도 막는다(ADR-0011 결정 4).</li>
 * </ul>
 *
 * <p>그래서 <b>이름 해석을 chat 밖으로 뺀다.</b> chat 은 {@code senderUserId} 만 돌려주고
 * (그리고 보낸 시점 스냅샷을 따로 들고), 이름은 여기서 붙인다. 새로 만든 규약이 아니라
 * 이 저장소가 이미 두 번 한 것이다 — {@code FamilyGroupService.nicknamesOf} 가 가족 멤버
 * 목록에, {@code CareDoerResponse.of} 가 케어 수행자에 같은 일을 한다(#76). 그 선례가
 * {@code ChatRoomService.isLiveMember}(밖이 chat 에게 <b>인가</b>를 묻는다)와 짝을 이룬다:
 * 멤버십은 chat 이 알고, 이름은 chat 이 모른다.
 *
 * <p>고르지 않은 다른 길과 그 대가를 적어 둔다.
 * <ul>
 *   <li><b>chat 에 {@code SenderNames} 포트를 선언하고 구현을 밖에서 꽂는다</b> — 경계는
 *       지켜지지만, 같은 규칙({@link User#displayName()})을 부르는 자리가 이 저장소에 이미
 *       셋인데 그중 하나만 포트를 통하게 된다. 방향이 헷갈리는 쪽이 더 비싸다고 봤다.</li>
 *   <li><b>스냅샷({@code chat_message.sender_name})을 응답에 그대로 쓴다</b> — 완료 조건 4 를
 *       포기하는 것이다. 카카오·라인이 그렇게 하지 않고, 이슈가 그 둘을 근거로 들었다.</li>
 * </ul>
 *
 * <h2>문구를 여기 적지 않는다</h2>
 * <p>탈퇴한 사람의 자리는 {@link User#UNKNOWN_DISPLAY_NAME}("알 수 없음")이다. 문자열을
 * 여기 다시 쓰지 않고 그 상수를 가리키는 이유는 {@code FamilyGroupService} 와 같다 — 같은
 * 화면 안에서 한 사람이 두 이름으로 보이는 것을 막는다.
 *
 * <h2>부르는 자리는 {@link ChatMessages} 다</h2>
 * <p>이 클래스만 만들어 두고 테스트만 부르면 완료 조건 3·4 는 "테스트가 직접 부른다" 로만
 * 성립하고 <b>응답 경로에는 아무것도 안 붙는다</b> — 그 상태가 #74 의 {@code AuthCode.role}
 * (매번 쓰지만 아무도 안 읽는 값)과 같은 모양이다. 조립을 {@link ChatMessages} 에 두면 #79
 * 는 거기에 HTTP 만 붙이면 되고, 스냅샷을 응답에 잘못 싣는 길이 처음부터 없다.
 *
 * <p><b>"익명" 도 "탈퇴한 사용자" 도 아니다.</b> 앞의 것은 앱에서 이미 "본인이 이름을 안
 * 붙인 것" 을 뜻하고({@code feed_screen.dart:132} "표시 이름 (비우면 익명)"), 뒤의 것은
 * 방 안 모두에게 "이 사람이 나갔다" 를 알리는 것이라 본인이 동의한 적 없는 공개다(#78).
 */
@Component
@RequiredArgsConstructor
public class ChatSenderNames {

    private final UserRepository users;

    /**
     * 사용자 id → 화면에 쓸 이름. <b>한 번의 조회로 모은다.</b>
     *
     * <p>메시지마다 {@code findById} 를 부르면 50건 조회에 쿼리가 51개 나간다. 폴링이라
     * 그 곱셈이 그대로 초당 부하가 된다.
     *
     * @return 요청한 id 전부에 대해 값이 있는 맵. {@code users} 에 없는 id 는
     *         {@link User#UNKNOWN_DISPLAY_NAME} 이다 — 부르는 쪽이 {@code null} 을 다시
     *         처리하지 않게 여기서 채운다
     */
    @Transactional(readOnly = true)
    public Map<Long, String> of(Collection<Long> userIds) {
        List<Long> ids = userIds.stream().distinct().toList();
        Map<Long, String> names = new LinkedHashMap<>();
        for (User user : users.findAllById(ids)) {
            names.put(user.getId(), user.displayName());
        }
        for (Long id : ids) {
            names.putIfAbsent(id, User.UNKNOWN_DISPLAY_NAME);
        }
        return names;
    }

    /** 한 사람. 목록을 만들 때는 {@link #of(Collection)} 을 써야 쿼리가 하나로 끝난다. */
    @Transactional(readOnly = true)
    public String of(long userId) {
        return of(List.of(userId)).get(userId);
    }
}
