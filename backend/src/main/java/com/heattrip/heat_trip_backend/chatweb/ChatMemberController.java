package com.heattrip.heat_trip_backend.chatweb;

import com.heattrip.heat_trip_backend.chat.ChatRoomService;
import com.heattrip.heat_trip_backend.user.CurrentUser;
import com.heattrip.heat_trip_backend.user.entity.User;

import lombok.RequiredArgsConstructor;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 강퇴와 재입장 금지 해제 — 이슈 #82 완료 조건 4 · 10.
 *
 * <p>이 클래스가 {@code chat} 패키지 밖에 있는 이유는 {@code chatweb/package-info} 에 있다.
 *
 * <h2>인가 (📌 #86 원칙 4)</h2>
 * <ul>
 *   <li><b>인증</b> — {@code SecurityConfig} 의 {@code anyRequest().authenticated()}.</li>
 *   <li><b>방장만</b> — 판정은 {@code ChatRoomService.requireOwner} 한 곳이다.
 *       {@code @PreAuthorize} 를 쓰지 않는 이유는 그 javadoc 과 같다: 필요한 것은 토큰의
 *       role 이 아니라 <b>이 방에서의 역할</b>이라 DB 를 봐야 한다.</li>
 *   <li><b>남의 방은 403</b> — 없는 방과 같은 답이다. 대상이 그 방에 없으면 404 인데,
 *       그건 <b>방장이 부르는 것</b>이라 방 존재 여부가 새지 않는다.</li>
 *   <li><b>rate limit</b> — 표에 없다. 방장만 부를 수 있고 한 방의 정원이 유한이라 반복
 *       호출이 만들 수 있는 상태가 유한하다. <b>미룬 것이지 안전한 것이 아니다</b> —
 *       표에 없는 경로는 한도가 0 이 아니라 무한이다.</li>
 * </ul>
 *
 * <h2>{@code DELETE .../members/me}(방 나가기)는 여기 없다</h2>
 * <p>계약에 선언되어 있지만 이 이슈의 범위가 아니다. 강퇴와 나가기는 <b>다른 동작</b>이다 —
 * 나가기는 재입장 금지를 걸지 않는다. 같은 메서드로 묶으면 그 차이가 조건문 하나로 숨는다.
 */
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/chat/rooms/{roomId}")
public class ChatMemberController {

    private final ChatRoomService chatRooms;

    /**
     * 이 사람을 방에서 내보낸다. <b>방장만.</b>
     *
     * <p>이미 나가 있어도 204 다. 있고 없고를 상태 코드로 나누면 앱이 두 갈래를 다뤄야
     * 하는데 방장에게는 결과가 같다 — "그 사람은 이 방에 없다".
     *
     * <p>멤버 행을 <b>지우지 않는다.</b> 지우면 재입장 금지를 걸 자리가 사라진다
     * ({@code ChatRoomService#removeMember}).
     */
    @DeleteMapping("/members/{userId}")
    public ResponseEntity<Void> remove(@PathVariable("roomId") long roomId,
                                       @PathVariable("userId") long userId,
                                       @CurrentUser User me) {
        chatRooms.removeMember(roomId, me.getId(), userId);
        return ResponseEntity.noContent().build();
    }

    /**
     * 재입장 금지를 푼다. <b>방장만.</b>
     *
     * <p>강퇴 확인 문구가 "방 설정에서 다시 풀 수 있습니다" 라고 <b>약속한다.</b> 그 약속을
     * 지킬 자리가 이것이다.
     *
     * <p><b>푸는 것은 금지뿐이고 멤버십은 아니다.</b> 풀어도 방에 자동으로 돌아오지 않고,
     * 그 사람이 초대코드로 다시 들어와야 한다.
     */
    @DeleteMapping("/bans/{userId}")
    public ResponseEntity<Void> allowRejoin(@PathVariable("roomId") long roomId,
                                            @PathVariable("userId") long userId,
                                            @CurrentUser User me) {
        chatRooms.allowRejoin(roomId, me.getId(), userId);
        return ResponseEntity.noContent().build();
    }
}
