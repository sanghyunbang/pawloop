package com.heattrip.heat_trip_backend.chatweb;

import com.heattrip.heat_trip_backend.user.CurrentUser;
import com.heattrip.heat_trip_backend.chat.ChatInviteView;
import com.heattrip.heat_trip_backend.chat.ChatJoinResult;
import com.heattrip.heat_trip_backend.chat.ChatRoomService;
import com.heattrip.heat_trip_backend.user.entity.User;

import lombok.RequiredArgsConstructor;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/**
 * 초대코드 발급 · 회수 · 참여 — 이슈 #75. 계약은 {@code openapi.yaml} 의 {@code /api/chat/**} 다.
 *
 * <p>이 클래스가 {@code chat} 패키지 밖에 있는 이유는 {@code package-info} 에 있다.
 *
 * <h2>경로는 계약을 따른다</h2>
 * <p>이슈 본문은 {@code /chat/rooms/{id}/invites} 로 적었지만 계약({@code openapi.yaml})은
 * {@code /api/chat/rooms/{roomId}/invites} 다. 그 파일이 <b>API 계약의 단일 출처</b>라고
 * 스스로 선언하고 있고, 앱은 계약을 보고 만든다. 그래서 {@code /api} 를 붙인다.
 *
 * <h2>인가 (📌 #86 원칙 4)</h2>
 * <ul>
 *   <li><b>인증</b> — 세 경로 모두 {@code SecurityConfig} 의 {@code anyRequest().authenticated()}
 *       로 떨어진다. {@code publicMatchers} 에 {@code /api/chat} 은 없다. 초대코드를 아는
 *       사람이라도 <b>로그인은 해야 한다</b> — 방에 들어오면 멤버십 행이 생기고 그 행은
 *       {@code users.id} 를 든다.</li>
 *   <li><b>역할</b> — 발급·회수는 방장만이고, 그 판정은 {@code ChatRoomService.requireOwner} 가
 *       한다. {@code @PreAuthorize} 를 쓰지 않은 이유는 그 메서드의 javadoc 에 있다:
 *       여기서 필요한 것은 토큰의 role 이 아니라 <b>이 방에서의 역할</b>이다.</li>
 *   <li><b>rate limit</b> — 셋의 처지가 다르다. <b>발급은 {@code group-write} 버킷</b>이다
 *       ({@code POST /api/groups} 와 공유). 요청 한 건이 "7일 동안 인증 없이 방에 들어올 수
 *       있는 열쇠" 를 하나 만들기 때문이고, 등록 전에는 한 방이 살아 있는 코드 200개를
 *       가질 수 있었다. <b>회수는 넣지 않았다</b> — 자기 방 코드를 죽이는 것뿐이라 반복해도
 *       새로 생기는 것이 없고, 유출 대응을 한도로 막으면 그게 더 나쁘다. <b>참여는 아직
 *       표 밖이다</b> — 이슈 #75 의 NOTE 가 M2.6 으로 미뤘고 그 판단을 따랐다. 표에 없는
 *       경로는 한도가 0 이 아니라 <b>무한</b>이다.</li>
 * </ul>
 *
 * <p><b>초대코드는 경로에 실린다 — 그래서 로그에서 가린다.</b> 계약이 정한 URL 모양이라
 * 경로 자체는 바꾸지 않고, {@code SensitiveDataMasker.maskUri} 가 로그·알림에 나가는
 * 문자열에서 코드 세그먼트를 {@code ***} 로 바꾼다. 가리기 전에는 요청 로그·오류 로그·
 * Slack 알림 셋 다에 코드 원문이 평문으로 남았다.
 */
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/chat")
public class ChatInviteController {

    private final ChatRoomService chatRooms;

    /**
     * 초대코드 발급. 방장만. 기본값은 {@code ChatLimits} 가 답한다(지금은 7일 · 무제한).
     *
     * <p>본문을 받지 않는다. 계약은 {@code expiresAt}·{@code maxUses} 를 선택 필드로 열어
     * 두지만, 지금 그 값을 정하는 것은 {@code ChatLimits} 하나다 — 클라이언트가 보낸 값을
     * 받기 시작하면 한도의 출처가 둘이 되고, 유효기간 무한을 요청하는 것을 서버가 막아야 한다.
     * 그 문은 플랜이 생기는 날 {@code ChatLimits} 와 함께 연다.
     */
    @PostMapping("/rooms/{roomId}/invites")
    @ResponseStatus(HttpStatus.CREATED)
    public ChatInviteView issue(@CurrentUser User user, @PathVariable long roomId) {
        return chatRooms.issueInvite(roomId, user.getId());
    }

    /**
     * 초대코드 회수. 방장만. <b>행을 지우지 않는다</b> — 이유는
     * {@code ChatRoomService.revokeInvite} 의 javadoc 에 있다.
     */
    @DeleteMapping("/rooms/{roomId}/invites/{code}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void revoke(@CurrentUser User user,
                       @PathVariable long roomId,
                       @PathVariable String code) {
        chatRooms.revokeInvite(roomId, code, user.getId());
    }

    /**
     * 초대코드로 입장. 이미 멤버면 아무것도 바꾸지 않고 200 이다.
     *
     * <p>201 이 아니라 200 인 것은 계약 그대로이고 이유도 있다 — 같은 요청이 두 번 와도
     * 응답이 같아야 앱이 재시도를 특별 취급하지 않는다.
     */
    @PostMapping("/invites/{code}/join")
    public ChatRoomResponse join(@CurrentUser User user, @PathVariable String code) {
        // 만 14세 미만은 가족 방에만 들어갈 수 있다(#82 완료 조건 5). 나이대를 방 종류
        // 목록으로 바꾸는 것이 이 패키지의 일이고, 그 목록을 대조하는 것은 chat 이다.
        ChatJoinResult joined = chatRooms.joinByInviteCode(
                code, user.getId(), MinorRoomPolicy.allowedOriginKindsFor(user));
        // 멤버 목록은 memberCount 때문에 어차피 읽는다. #79 가 더한 myRole·lastReadSeq·unread
        // 도 그 목록에서 꺼내므로 추가 쿼리가 0이다.
        return ChatRoomResponse.of(
                joined.room(), chatRooms.liveMembers(joined.room().id()), user.getId());
    }
}
