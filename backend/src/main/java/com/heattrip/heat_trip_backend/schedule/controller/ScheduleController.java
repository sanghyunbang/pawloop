package com.heattrip.heat_trip_backend.schedule.controller;

import com.heattrip.heat_trip_backend.error.GlobalExceptionHandler.ErrorResponse;
import com.heattrip.heat_trip_backend.schedule.dto.ScheduleConflictResponse;
import com.heattrip.heat_trip_backend.schedule.dto.ScheduleRequest;
import com.heattrip.heat_trip_backend.schedule.dto.ScheduleResponse;
import com.heattrip.heat_trip_backend.schedule.dto.ScheduleUpdateRequest;
import com.heattrip.heat_trip_backend.schedule.entity.ScheduleOwnerKind;
import com.heattrip.heat_trip_backend.schedule.service.ScheduleService;
import com.heattrip.heat_trip_backend.user.CurrentUser;
import com.heattrip.heat_trip_backend.user.entity.User;

import jakarta.validation.Valid;

import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;
import java.util.List;

/**
 * 일정표 — 이슈 #418, 부모 #416.
 *
 * <h2>기간으로 받는다</h2>
 * <p>달력이 묻는 것은 늘 "이 기간" 이다. 페이지 커서를 두지 않는 이유는 한 달치가 수십 건이라
 * 자를 것이 없고, 커서를 두면 화면이 달을 넘길 때마다 커서를 버려야 하기 때문이다.
 *
 * <h2>주인을 안 주면 합쳐 본다</h2>
 * <p>{@code ownerKind} 를 생략하면 <b>내가 볼 수 있는 전부</b>가 온다 — 내 아이들 것과 우리
 * 가족 것. 달력의 기본이 그것이라, 화면이 두 번 부르게 만들지 않는다.
 *
 * <p>인증 주체는 {@code @CurrentUser} 가 해석한다.
 */
@RestController
@RequestMapping("/api/schedules")
public class ScheduleController {

    private final ScheduleService schedules;

    public ScheduleController(ScheduleService schedules) {
        this.schedules = schedules;
    }

    /**
     * 기간 안의 일정.
     *
     * @param ownerKind 없으면 <b>내가 볼 수 있는 전부</b>. 주면 {@code ownerRef} 도 있어야 한다
     * @param dogId     그 아이 것만. {@code ownerKind} 와 <b>겹쳐 쓸 수 있다</b> —
     *                  "우리 가족 일정 중 보리 것"
     */
    @GetMapping
    public List<ScheduleResponse> range(
            @CurrentUser User user,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to,
            @RequestParam(required = false) String ownerKind,
            @RequestParam(required = false) Long ownerRef,
            @RequestParam(required = false) Long dogId) {
        return schedules.range(
                user.getId(), from, to,
                ownerKind == null ? null : ScheduleOwnerKind.of(ownerKind),
                ownerRef, dogId);
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public ScheduleResponse create(@CurrentUser User user,
                                   @Valid @RequestBody ScheduleRequest request) {
        return schedules.create(user, request);
    }

    /**
     * 고친다. <b>{@code version} 이 다르면 409</b> 와 함께 최신 값을 준다.
     *
     * <p>{@code PUT} 이 아니라 {@code PATCH} 인 이유: 화면이 한 칸만 고치는 일이 흔하다
     * (담당자만 바꾸기, 완료 표시만 하기).
     *
     * @param version 마지막으로 본 값. <b>본문이 아니라 쿼리인 이유</b>는
     *                {@link ScheduleUpdateRequest} 의 javadoc 에 있다 — 부분 수정 본문에는
     *                필수 필드를 둘 수 없다(ADR-0017 규약 4)
     */
    @PatchMapping("/{scheduleId}")
    public ScheduleResponse update(@CurrentUser User user,
                                   @PathVariable long scheduleId,
                                   @RequestParam int version,
                                   @Valid @RequestBody ScheduleUpdateRequest request) {
        return schedules.update(user, scheduleId, version, request);
    }

    @DeleteMapping("/{scheduleId}")
    public ResponseEntity<Void> delete(@CurrentUser User user, @PathVariable long scheduleId) {
        schedules.delete(user.getId(), scheduleId);
        return ResponseEntity.noContent().build();
    }

    /**
     * 낙관적 잠금 충돌 — <b>409 와 함께 최신 값</b>.
     *
     * <p>본문 없는 409 를 주면 화면이 한 번 더 물어야 하고 그 사이에 또 바뀔 수 있다.
     * 최신 값을 함께 주면 "○○님이 방금 고쳤어요" 를 그 자리에서 보여 줄 수 있다.
     *
     * <p>그래도 <b>{@code error} 봉투는 그대로</b> 든다 — 앱의 공통 오류 처리가
     * {@code error.code} 로 분기하기 때문이다. 자세한 것은 {@link ScheduleConflictResponse}.
     */
    @ExceptionHandler(ScheduleService.StaleScheduleException.class)
    public ResponseEntity<ScheduleConflictResponse> stale(ScheduleService.StaleScheduleException e) {
        return ResponseEntity.status(HttpStatus.CONFLICT)
                .body(new ScheduleConflictResponse(
                        ErrorResponse.of(HttpStatus.CONFLICT, e.getMessage()).error(),
                        e.current()));
    }
}
