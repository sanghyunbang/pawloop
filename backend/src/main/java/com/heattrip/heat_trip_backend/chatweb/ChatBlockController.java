package com.heattrip.heat_trip_backend.chatweb;

import com.heattrip.heat_trip_backend.chat.ChatBlocks;
import com.heattrip.heat_trip_backend.user.CurrentUser;
import com.heattrip.heat_trip_backend.user.entity.User;

import lombok.RequiredArgsConstructor;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 가리기 — 이슈 #82 완료 조건 3. 계약은 {@code /api/chat/blocks} 다.
 *
 * <p>이 클래스가 {@code chat} 패키지 밖에 있는 이유는 {@code chatweb/package-info} 에 있다.
 *
 * <h2>인가 (📌 #86 원칙 4)</h2>
 * <ul>
 *   <li><b>인증</b> — {@code SecurityConfig} 의 {@code anyRequest().authenticated()} 로
 *       떨어진다.</li>
 *   <li><b>멤버십을 안 본다.</b> 가리기는 <b>내 화면의 설정</b>이고 방과 무관하다. 같은
 *       방에 있는지 확인하면, 확인에 성공/실패하는 것 자체가 <b>"그 사람과 같은 방에
 *       있는가" 를 알려 주는 오라클</b>이 된다.</li>
 *   <li><b>대상이 실재하는지도 안 본다.</b> 없는 id 를 가려도 아무 일이 안 일어난다.
 *       확인하면 {@code users} 를 훑어 계정 존재를 가려낼 수 있다 — {@code chat} 이
 *       {@code users} 를 못 보는 것(경계)이 여기서는 그대로 방어가 된다.</li>
 *   <li><b>rate limit</b> — {@code chat-report} 와 같은 버킷을 <b>쓰지 않는다.</b> 아래
 *       {@code block} javadoc 참조.</li>
 * </ul>
 */
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/chat/blocks")
public class ChatBlockController {

    private final ChatBlocks blocks;

    /**
     * 이 사람을 가린다.
     *
     * <p>201 은 <b>"가려져 있다"</b> 는 뜻이다. 이미 가려 뒀어도 201 이다 — 없던 것과 있던
     * 것을 상태 코드로 나누면 앱이 두 갈래를 다뤄야 하는데, 사용자에게는 결과가 같다.
     *
     * <p><b>rate limit 표에 없다.</b> #86 원칙 4 가 요구하는 등재를 여기서 안 한 것은
     * <b>미룬 것이지 안전한 것이 아니다</b> — 표에 없는 경로는 한도가 0 이 아니라 무한이다.
     * 여기는 앞 필터의 {@code auth} 버킷도 안 걸린다. 다만 이 경로가 만드는 행은 사용자당
     * 대상당 <b>최대 하나</b>(UNIQUE)라, 반복 호출이 표를 늘리지 못한다. 신고와 갈리는
     * 지점이 그것이다.
     */
    @PostMapping
    public ResponseEntity<Void> block(@RequestBody ChatBlockRequest request,
                                      @CurrentUser User me) {
        blocks.block(me.getId(), request.requireUserId());
        return ResponseEntity.status(HttpStatus.CREATED).build();
    }

    /**
     * 가리기를 푼다.
     *
     * <p>없던 것을 풀어도 204 다. 있고 없고를 상태 코드로 알려 주면 <b>가려 뒀는지를 응답으로
     * 물어볼 수 있게</b> 된다 — 본인만 아는 상태여야 한다.
     */
    @DeleteMapping("/{userId}")
    public ResponseEntity<Void> unblock(@PathVariable("userId") long userId,
                                        @CurrentUser User me) {
        blocks.unblock(me.getId(), userId);
        return ResponseEntity.noContent().build();
    }
}
