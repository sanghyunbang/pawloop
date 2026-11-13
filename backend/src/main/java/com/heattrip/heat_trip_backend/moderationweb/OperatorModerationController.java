package com.heattrip.heat_trip_backend.moderationweb;

import com.heattrip.heat_trip_backend.moderation.ReportCase;
import com.heattrip.heat_trip_backend.moderation.Reports;

import io.swagger.v3.oas.annotations.Hidden;

import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

/**
 * 운영자 경로 — 신고를 보고 처리한다. 이슈 #718.
 *
 * <h2>누가 부르나</h2>
 * <p><b>앱도 사용자도 아니다.</b> {@code /internal/**} 는 앱 컨테이너 안의 루프백 커넥터로 들어온 요청만
 * 통과한다({@code config.OperatorChannel}, {@code SecurityConfig} 의 첫 규칙). 운영자는 서버에 들어가
 * {@code backend/scripts/moderate.sh} 로 부른다. 그래서 여기에는 "누가 관리자인가" 를 가리는 코드가 없다 —
 * 그 판정을 들어온 문이 대신한다.
 *
 * <h2>계약에 없다</h2>
 * <p>앱이 부르는 경로가 아니라 {@code openapi.yaml} 에 적지 않고, 생성되는 문서에서도 숨긴다
 * ({@link Hidden}). 공개 저장소의 계약을 읽는 사람에게 "부를 수 없는 경로" 를 보여 줄 이유가 없다.
 *
 * <h2>무엇이 되나</h2>
 * <p>신고 한 건을 보고, 신고된 글·댓글을 지우거나 기각한다. 사람을 내보내는 것(정지)은 다음 조각에서 더한다.
 */
@Hidden
@RestController
@RequestMapping("/internal/moderation")
public class OperatorModerationController {

    private final Reports reports;
    private final OperatorModeration moderation;

    public OperatorModerationController(Reports reports, OperatorModeration moderation) {
        this.reports = reports;
        this.moderation = moderation;
    }

    /** 신고 한 건과 그 사본 전부 — 슬랙 알림의 신고 번호 하나로 판단할 수 있게. 없는 번호면 404. */
    @GetMapping("/reports/{reportId}")
    public ReportCase report(@PathVariable("reportId") long reportId) {
        return reports.caseOf(reportId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "그런 신고가 없습니다"));
    }

    /**
     * 신고를 처리한다 — {@code decision=remove}(신고된 글·댓글을 지움) 또는 {@code dismiss}(지울 것 없음).
     *
     * <p>본문은 JSON 이 아니라 form 이다. 운영 스크립트가 bash 에서 부르므로 따옴표·줄바꿈이 섞인 사유를 JSON 으로
     * 이스케이프하다 깨지는 일을 없앤다({@code curl --data-urlencode}). {@code actor} 는 서버에 들어간 계정 이름을
     * 스크립트가 채운다. 판단과 결과의 규칙은 {@link OperatorModeration} 에 있다.
     */
    @PostMapping(path = "/reports/{reportId}/resolve", consumes = MediaType.APPLICATION_FORM_URLENCODED_VALUE)
    public OperatorModeration.Resolution resolve(@PathVariable("reportId") long reportId,
                                                 @RequestParam("decision") String decision,
                                                 @RequestParam("reason") String reason,
                                                 @RequestParam("actor") String actor) {
        return moderation.resolve(reportId, decision, reason, actor);
    }
}
