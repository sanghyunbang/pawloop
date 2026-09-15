package com.heattrip.heat_trip_backend.walk.controller;

import com.heattrip.heat_trip_backend.user.CurrentUser;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.walk.dto.WalkMemoRequest;
import com.heattrip.heat_trip_backend.walk.dto.InsightFeedbackRequest;
import com.heattrip.heat_trip_backend.walk.dto.WalkPageResponse;
import com.heattrip.heat_trip_backend.walk.dto.WalkRequest;
import com.heattrip.heat_trip_backend.walk.dto.WalkResponse;
import com.heattrip.heat_trip_backend.walk.dto.WalkStatsResponse;
import com.heattrip.heat_trip_backend.walk.service.WalkService;
import com.heattrip.heat_trip_backend.walk.ai.WeeklyInsightService;

import jakarta.validation.Valid;

import lombok.RequiredArgsConstructor;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/**
 * 산책 기록 — 이슈 #145. 계약은 {@code docs/04-api/openapi.yaml} 의 {@code /api/walks} 다.
 *
 * <h2>인가 (📌 #86 원칙 4)</h2>
 * <ul>
 *   <li><b>인증</b> — 다섯 경로 모두 {@code SecurityConfig} 의
 *       {@code anyRequest().authenticated()} 가 받는다. {@code publicMatchers} 에 줄을 더하지
 *       않는 것이 판단이다 — {@code DogController}·{@code CareController} 와 같다.</li>
 *   <li><b>소유권</b> — {@code WalkService} 가 쿼리 안에서 판정한다. 남의 산책과 없는
 *       산책은 <b>같은 404</b> 다.</li>
 *   <li><b>rate limit</b> — <b>쓰기 둘({@code POST} · {@code DELETE})은 새 버킷
 *       {@code walk-write}</b> 다({@code ApiRateLimitFilter.resolveRule}). {@code group-write}
 *       에 얹지 않은 이유는 성격이 다르기 때문이다 — 산책 저장은 <b>오프라인 큐가 한 번에
 *       여러 건을 밀어 넣는다.</b> 하루 못 보낸 것이 쌓였다가 한꺼번에 나가는 것이 정상
 *       동작이라, 그룹 생성과 같은 숫자로 묶으면 <b>정상 사용자가 자기 기록을 못 올린다.</b>
 *       <br>
 *       <b>읽기 셋은 표에 넣지 않았다</b> — 표에 없는 경로는 한도가 0 이 아니라 <b>무한</b>
 *       이다. 미룬 것이지 안전한 것이 아니고, 숫자를 정하려면 앱이 이 셋을 언제 얼마나
 *       부르는지부터 정해져야 한다(홈·기록·통계 세 화면이 진입할 때마다 부른다).</li>
 * </ul>
 *
 * <p>인증 주체는 {@code @CurrentUser} 가 해석한다 — 컨트롤러가 Authorization 헤더를 다시
 * 읽지 않는다(#5).
 */
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/walks")
public class WalkController {

    private final WalkService walks;
    private final WeeklyInsightService insights;

    /**
     * 내 산책 목록. <b>경로는 실리지 않는다</b> — 상세에서만 준다.
     *
     * <p>정렬은 {@code (createdAt, id)} 내림차순이라 "걸은 순서" 가 아니라 <b>"기록된 순서"</b>
     * 다. 이유는 {@code WalkCursor} javadoc 에 있다.
     */
    @GetMapping
    public WalkPageResponse list(@CurrentUser User user,
                                 @RequestParam(required = false) Long dogId,
                                 @RequestParam(required = false) String cursor,
                                 @RequestParam(required = false) Integer limit) {
        return walks.page(user.getId(), dogId, cursor, limit);
    }

    /**
     * 저장.
     *
     * <p><b>재전송은 새 줄을 만들지 않는다.</b> 같은 {@code clientWalkId} 로 이미 저장된
     * 것이 있으면 <b>200 + 그 행</b>이고, 처음이면 201 이다. 앱은 둘을 같게 취급하면 된다.
     */
    @PostMapping
    public ResponseEntity<WalkResponse> save(@CurrentUser User user,
                                             @Valid @RequestBody WalkRequest request) {
        // 걸은 사람을 서비스가 다시 안 읽는다 — 토큰이 이미 준 것을 그대로 넘긴다(#563).
        // CareController 가 doneBy 를 같은 방식으로 넘긴다.
        WalkService.Saved saved = walks.save(user, request);
        return ResponseEntity
                .status(saved.created() ? HttpStatus.CREATED : HttpStatus.OK)
                .body(saved.walk());
    }

    /** 이번 주(KST 월~일) + 전체 기간. 화면 둘이 이 하나로 채워진다. */
    @GetMapping("/stats/weekly")
    public WalkStatsResponse stats(@CurrentUser User user,
                                   @RequestParam(required = false) Long dogId) {
        // AI 주간 요약(#486)은 통계 트랜잭션 밖에서 얹는다 — 모델 호출은 망이다.
        return insights.attach(user.getId(), dogId, walks.stats(user.getId(), dogId));
    }

    /**
     * AI 요약 👍/👎 — #486 후속. {@code value} 가 {@code null} 이면 지운다. 내 요약이 아니면 404.
     *
     * <p>{@code walk-write} 버킷이다({@code ApiRateLimitFilter}) — 눌렀다 뗐다 하는 일이라 저장만큼 잦지 않다.
     */
    @PutMapping("/insights/{insightId}/feedback")
    public WalkStatsResponse.AiSummary rateInsight(@CurrentUser User user,
                                                  @PathVariable long insightId,
                                                  @RequestBody InsightFeedbackRequest request) {
        return insights.rate(user.getId(), insightId, request.value());
    }

    /** 상세. 경로가 여기에만 실린다. */
    @GetMapping("/{walkId}")
    public WalkResponse detail(@CurrentUser User user, @PathVariable long walkId) {
        return walks.detail(user.getId(), walkId);
    }

    /**
     * 회고 글 교체 — 이슈 #187.
     *
     * <p>하위 리소스 PUT 이다. {@code PATCH /api/walks/{walkId}} 로 두면 "필드를 안 보냈다"
     * 와 "null 로 지워라" 를 구분해야 하는데, 바꿀 필드가 하나뿐이라 그 복잡도가 값을 못
     * 한다. {@code PUT /api/groups/{groupId}/walk-notes} 가 같은 모양이다.
     *
     * <p><b>{@code walk-write} 버킷에 등록돼 있다</b>({@code ApiRateLimitFilter}).
     * 표에 없는 경로는 한도가 0 이 아니라 무한이다.
     */
    @PutMapping("/{walkId}/memo")
    public WalkResponse rewriteMemo(@CurrentUser User user,
                                    @PathVariable long walkId,
                                    @Valid @RequestBody WalkMemoRequest request) {
        return walks.rewriteMemo(user.getId(), walkId, request.memo());
    }

    /**
     * 삭제.
     *
     * <p>멱등키가 있어 같은 산책을 두 번 저장할 수는 없으므로, <b>잘못 저장한 것을 사용자가
     * 지울 길이 반드시 있어야 한다.</b>
     */
    @DeleteMapping("/{walkId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@CurrentUser User user, @PathVariable long walkId) {
        walks.delete(user.getId(), walkId);
    }
}
