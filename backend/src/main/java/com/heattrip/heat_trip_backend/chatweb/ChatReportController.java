package com.heattrip.heat_trip_backend.chatweb;

import com.heattrip.heat_trip_backend.chat.ChatReportService;
import com.heattrip.heat_trip_backend.chat.ChatReportView;
import com.heattrip.heat_trip_backend.user.CurrentUser;
import com.heattrip.heat_trip_backend.user.entity.User;

import lombok.RequiredArgsConstructor;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 메시지 신고 — 이슈 #82.
 *
 * <p>이 클래스가 {@code chat} 패키지 밖에 있는 이유는 {@code chatweb/package-info} 에 있다.
 *
 * <h2>인가 (📌 #86 원칙 4)</h2>
 * <ul>
 *   <li><b>인증</b> — {@code SecurityConfig} 의 {@code anyRequest().authenticated()} 로
 *       떨어진다. {@code publicMatchers} 에 {@code /api/chat} 은 없다.</li>
 *   <li><b>멤버십</b> — {@code ChatReportService} 가 살아 있는 멤버인지 본다. 없는 방과
 *       남의 방이 같은 답(403)인 것은 {@code ChatRoomController} 와 같은 이유다.</li>
 *   <li><b>rate limit</b> — {@code chat-report} 버킷에 <b>등재했다</b>. 채팅 경로 넷이
 *       한동안 표에 없어서 한도가 사실상 무한이었던 적이 있고(#80 이 고쳤다), 표에 없는
 *       경로는 한도가 0 이 아니라 무한이다. 신고는 <b>쓰기</b>이고 한 사람이 같은 방을
 *       계속 신고하면 표가 그만큼 늘어난다.</li>
 * </ul>
 *
 * <h2>응답에 신고자가 없다</h2>
 * <p>{@link ChatReportResponse} 는 {@code reportId} 와 {@code createdAt} 둘뿐이다.
 * 신고자 신원은 물론이고 <b>피신고자 id 도 돌려주지 않는다</b> — 신고를 성공시킨 쪽은 이미
 * 누구를 신고했는지 알고, 서버가 그것을 되돌려 줄 이유가 없다(#82 완료 조건 2).
 *
 * <h2>조회 경로가 없다</h2>
 * <p>{@code GET} 이 없다. 신고를 읽어야 하는 사람은 운영자인데 관리자 인증이 아직 없고,
 * 그것 없이 열면 신고 내용이 누구에게나 보인다({@code ChatReportService#findReport} javadoc).
 */
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/chat")
public class ChatReportController {

    private final ChatReportService reportService;

    /**
     * 이 방의 메시지 몇 개를 신고한다.
     *
     * <p>201 인 이유는 <b>기록이 하나 생기기 때문</b>이다. 200 으로 두면 "접수됐다" 와
     * "이미 있었다" 가 구분되지 않는다.
     *
     * <p><b>가리기·방 나가기를 여기서 하지 않는다.</b> 앱의 신고 화면에 체크박스로 두되
     * 기본값은 꺼져 있고, 켰으면 앱이 그 경로를 <b>따로</b> 부른다. 카카오처럼 신고에
     * 자동 차단을 묶으면 가족방에서 되돌릴 수 없는 사고가 된다({@code ChatReportService}).
     */
    @PostMapping("/rooms/{roomId}/reports")
    public ResponseEntity<ChatReportResponse> report(@PathVariable("roomId") long roomId,
                                                     @RequestBody ChatReportRequest request,
                                                     @CurrentUser User me) {
        ChatReportView report = reportService.report(
                roomId, me.getId(), request.roomSeqs(), request.reason(), request.memo());

        return ResponseEntity.status(HttpStatus.CREATED)
                .body(new ChatReportResponse(report.id(), report.createdAt().toString()));
    }
}
