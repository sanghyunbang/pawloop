package com.heattrip.heat_trip_backend.care.controller;

import com.heattrip.heat_trip_backend.OAuth.principal.CurrentUser;
import com.heattrip.heat_trip_backend.care.dto.CareLogRequest;
import com.heattrip.heat_trip_backend.care.dto.CareLogResponse;
import com.heattrip.heat_trip_backend.care.dto.WalkNoteRequest;
import com.heattrip.heat_trip_backend.care.dto.WalkNoteResponse;
import com.heattrip.heat_trip_backend.care.entity.CareType;
import com.heattrip.heat_trip_backend.care.service.CareService;
import com.heattrip.heat_trip_backend.user.entity.User;

import lombok.RequiredArgsConstructor;

import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;
import java.util.List;

/**
 * 오늘의 케어 공유와 산책 주의사항 — 이슈 #76.
 * 계약은 {@code docs/04-api/openapi.yaml} 의 {@code /api/groups/{groupId}/care-logs} ·
 * {@code /walk-notes} 다.
 *
 * <h2>인가 (📌 #86 원칙 4)</h2>
 * <ul>
 *   <li><b>인증</b> — 네 경로 모두 {@code SecurityConfig} 의 {@code anyRequest().authenticated()}
 *       가 받는다. {@code publicMatchers} 에 {@code /api/groups} 는 없다. 여기에 줄을 더하지
 *       않는 것이 판단이다 — {@code GroupController} 가 같은 이유로 더하지 않았고, 적으면
 *       "인증 필요" 를 두 곳에서 관리하게 된다.</li>
 *   <li><b>그룹 멤버십</b> — {@code CareService.requireMemberGroup} 가 판정한다. 멤버가
 *       아니면 403 이고, 그 판정의 원본은 {@code chat_room_member} 하나다.
 *       {@code @PreAuthorize} 를 쓰지 않는 이유는 {@code ChatRoomService.requireOwner} 와
 *       같다 — 필요한 것은 토큰의 role 이 아니라 <b>이 그룹에서의 소속</b>이라 DB 를 봐야 한다.</li>
 *   <li><b>rate limit</b> — <b>쓰기 둘({@code POST care-logs} · {@code PUT walk-notes})은
 *       {@code group-write} 버킷</b>이다({@code ApiRateLimitFilter.resolveRule}). 요청 한 건이
 *       행을 만들거나 가족 모두가 보는 문서를 통째로 바꾸기 때문이다. <b>읽기 둘은 넣지
 *       않았다</b> — {@code GET /api/groups/me} 가 표 밖인 것과 같은 판단이고, 표에 없는
 *       경로는 한도가 0 이 아니라 <b>무한</b>이라는 것을 알고 미룬 것이다. 읽기까지 재는
 *       것은 앱의 폴링 주기가 정해지는 M2.6 에서 함께 판단한다.</li>
 * </ul>
 *
 * <p>인증 주체는 {@code @CurrentUser} 가 해석한다 — 컨트롤러가 Authorization 헤더를 다시
 * 읽지 않는다(#5). {@code doneBy} 를 본문으로 받지 않는 이유도 같은 자리다.
 */
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/groups/{groupId}")
public class CareController {

    private final CareService care;

    /**
     * 그 그룹의 하루치 케어. {@code date} 를 생략하면 <b>오늘</b>이다.
     *
     * <p>{@code date} 가 날짜 모양이 아니면 400 이다({@code @DateTimeFormat} 이 걸러
     * {@code MethodArgumentTypeMismatchException} 을 던지고 전역 처리기가 옮긴다).
     * {@code type} 도 다섯 중 하나가 아니면 400 이다.
     *
     * <p><b>{@code type} 을 {@code CareType} 으로 직접 받지 않는 것은 의도다.</b> 스프링의
     * 기본 enum 변환은 {@code Enum.valueOf} 라 <b>자바 상수 이름</b>({@code MEAL})을 찾는다 —
     * 계약이 정한 값은 소문자 {@code meal} 이므로 그대로 두면 정상 요청이 400 이 된다.
     * {@link CareType#of} 를 거치면 본문(Jackson)과 쿼리 파라미터가 <b>같은 한 벌</b>의
     * 문자열을 쓴다.
     */
    @GetMapping("/care-logs")
    public List<CareLogResponse> careLogs(
            @CurrentUser User user,
            @PathVariable long groupId,
            @RequestParam(required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date,
            @RequestParam(required = false) String type) {
        return care.logsOf(groupId, date, type == null ? null : CareType.of(type), user.getId());
    }

    /**
     * 케어 한 건 기록. <b>같은 종류가 오늘 이미 있어도 저장한다</b> — 완료 조건 2.
     * 확인 문구는 앱이 만든다. 그 판단의 근거는 {@code CareService.record} 의 javadoc.
     */
    @PostMapping("/care-logs")
    @ResponseStatus(HttpStatus.CREATED)
    public CareLogResponse record(@CurrentUser User user,
                                  @PathVariable long groupId,
                                  @RequestBody CareLogRequest request) {
        return care.record(groupId, request, user);
    }

    /** 산책 주의사항 한 장. 아직 없으면 빈 본문이다 — 404 가 아니다. */
    @GetMapping("/walk-notes")
    public WalkNoteResponse walkNotes(@CurrentUser User user, @PathVariable long groupId) {
        return care.walkNoteOf(groupId, user.getId());
    }

    /** 산책 주의사항 전체 교체. 그룹당 한 장이라 {@code PUT} 이다. */
    @PutMapping("/walk-notes")
    public WalkNoteResponse replaceWalkNotes(@CurrentUser User user,
                                             @PathVariable long groupId,
                                             @RequestBody WalkNoteRequest request) {
        return care.replaceWalkNote(groupId, request == null ? null : request.body(), user);
    }
}
