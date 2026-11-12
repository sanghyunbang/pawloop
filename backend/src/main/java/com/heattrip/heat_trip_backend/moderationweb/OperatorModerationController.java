package com.heattrip.heat_trip_backend.moderationweb;

import com.heattrip.heat_trip_backend.moderation.ReportCase;
import com.heattrip.heat_trip_backend.moderation.Reports;

import io.swagger.v3.oas.annotations.Hidden;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
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
 * <h2>이번 조각</h2>
 * <p>신고 한 건을 판단할 재료를 보는 것뿐이다. 글을 지우는 것(삭제)과 사람을 내보내는 것(정지)은 다음
 * 조각에서 여기에 더한다.
 */
@Hidden
@RestController
@RequestMapping("/internal/moderation")
public class OperatorModerationController {

    private final Reports reports;

    public OperatorModerationController(Reports reports) {
        this.reports = reports;
    }

    /** 신고 한 건과 그 사본 전부 — 슬랙 알림의 신고 번호 하나로 판단할 수 있게. 없는 번호면 404. */
    @GetMapping("/reports/{reportId}")
    public ReportCase report(@PathVariable("reportId") long reportId) {
        return reports.caseOf(reportId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "그런 신고가 없습니다"));
    }
}
