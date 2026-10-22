package com.heattrip.heat_trip_backend.moderation;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

/**
 * 게시 전에 거른다 — 이 모듈의 공개 표면이다. 이슈 #681.
 *
 * <h2>왜 이 모듈에 있나</h2>
 * <p>애플 App Review Guideline <b>1.2 (User-Generated Content)</b> 가 요구하는 넷 중 셋이
 * 이미 여기 있다 — 신고({@link Reports}) · 차단({@link Blocks}) · 연락처. 넷째인 거르기만
 * 커뮤니티 안에 두면 채팅이 그것을 못 쓴다. 같은 판정을 두 벌로 두면 한쪽만 낡는다.
 *
 * <p>이 모듈은 여전히 아무 도메인도 안 부른다({@code package-info} 의
 * {@code allowedDependencies = {}}). 무엇을 검사하는지 — 글의 제목인지 댓글인지 말풍선인지 —
 * 는 <b>부르는 쪽이 알고</b>, 여기는 문자열만 받는다. {@link Reports} 가 신고 사본을 값으로만
 * 받는 것과 같은 모양이다.
 *
 * <h2>부르는 자리</h2>
 * <ul>
 *   <li>커뮤니티 글 — {@code CommunityService.create} · {@code updatePost}.
 *       <b>수정도 게시다.</b> 쓸 때만 막으면 빈 글을 올린 뒤 고쳐 넣는 것으로 끝난다.</li>
 *   <li>커뮤니티 댓글 — {@code CommunityService.addComment}</li>
 *   <li>채팅 말풍선 — {@code chatweb.ChatMessages.send}. {@code chat} 모듈은 다른 모듈을
 *       하나도 못 보므로({@code allowedDependencies = {}}) 거르는 자리는 그 앞의
 *       {@code chatweb} 이다 — 이름·가리기·사진이 이미 거기서 붙는다.</li>
 * </ul>
 *
 * <p><b>신고 메모({@link Reports#file})는 안 거른다.</b> 거기 적는 말은 대개 <b>남이 한 말을
 * 옮긴 것</b>이라, 거르면 운영자에게 가야 할 증거가 막힌다. 그 글은 남에게 안 보이고
 * 운영자만 읽는다 — 1.2 가 말하는 "사용자가 서로에게 보이는 내용" 이 아니다.
 *
 * <h2>무엇이 걸렸는지 안 알려 준다</h2>
 * <p>응답은 {@value #REJECTION_MESSAGE} 하나뿐이다. 어느 낱말이 걸렸는지 돌려주면 그것은
 * <b>우회 방법을 알려 주는 것</b>이다 — 한 글자만 바꿔 다시 보내면 되고, 몇 번 반복하면
 * 목록 전체를 뽑아낼 수 있다. 400 하나로 끝낸다.
 *
 * <p>거절이지 삭제가 아니다. 사용자가 쓴 글은 앱에 그대로 남아 있고, 고쳐서 다시 보내면
 * 된다. 저장한 뒤 숨기는 방법도 있었지만 그러면 <b>본인에게는 올라간 것처럼 보이는데
 * 아무도 못 보는 글</b>이 생긴다 — 그건 사용자가 이해할 수 없는 상태다.
 */
@Service
public class ContentFilter {

    /**
     * 걸렸을 때 사람이 보는 문구. 고정이다 — 무엇이 걸렸는지는 여기에도 로그에도 안 싣는다.
     */
    public static final String REJECTION_MESSAGE =
            "올릴 수 없는 표현이 들어 있습니다. 내용을 고쳐서 다시 보내 주세요.";

    /**
     * 걸러 낼 말들. <b>이제 주입받는다</b> — 이슈 #789.
     *
     * <p>예전에는 {@code BannedWords.matches(…)} 를 static 으로 불렀고 목록이 코드에
     * 박혀 있었다. 저장소를 공개로 돌리면 그 목록이 통째로 읽히고, 무엇보다 낱말을
     * 하나 더하려면 빌드와 배포가 필요했다 — 운영하면서 계속 느는 값이 있을 자리가
     * 아니다.
     */
    private final BannedWords bannedWords;

    ContentFilter(BannedWords bannedWords) {
        this.bannedWords = bannedWords;
    }

    /**
     * 하나라도 걸리면 {@code 400} 으로 던진다.
     *
     * <p>{@code null} 은 검사할 것이 없는 자리다 — 안 보낸 필드({@code PATCH} 의 생략)와
     * 캡션 없는 사진 메시지가 그렇다. 비었는지·필수인지는 각 도메인이 이미 본다.
     *
     * @param texts 사용자가 쓴 글들. 제목과 본문처럼 한 요청에 여럿이면 함께 넘긴다
     * @throws ResponseStatusException 400 — 금칙어가 있으면. 이유는 {@value #REJECTION_MESSAGE}
     */
    public void requireClean(String... texts) {
        for (String text : texts) {
            if (bannedWords.matches(text)) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, REJECTION_MESSAGE);
            }
        }
    }
}
