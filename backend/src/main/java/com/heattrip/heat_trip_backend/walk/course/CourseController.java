package com.heattrip.heat_trip_backend.walk.course;

import com.heattrip.heat_trip_backend.user.CurrentUser;
import com.heattrip.heat_trip_backend.user.entity.User;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Pattern;

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
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.validation.annotation.Validated;

import java.util.List;

/**
 * 코스 — 이슈 #339. 계약은 {@code docs/04-api/openapi.yaml} 의 {@code /api/courses} 다.
 *
 * <h2>인가 (📌 #86 원칙 4)</h2>
 * <ul>
 *   <li><b>인증</b> — 다섯 경로 모두 {@code anyRequest().authenticated()} 다.
 *       공개 코스도 로그인한 사람에게만 준다: 지도의 "이웃 코스" 는 로그인 뒤 화면이고,
 *       비인증으로 열면 그 목록이 곧 크롤링 대상이 된다.</li>
 *   <li><b>소유권</b> — {@code CourseService} 가 쿼리 안에서 판정한다. 남의 비공개 코스와
 *       없는 코스는 <b>같은 404</b> 다.</li>
 *   <li><b>rate limit</b> — 쓰기 셋은 {@code walk-write} 버킷에 얹는다
 *       ({@code ApiRateLimitFilter}). 코스 저장은 산책 저장과 같은 성격이고, 따로 숫자를
 *       정할 근거가 아직 없다.</li>
 * </ul>
 */
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/courses")
@Validated
public class CourseController {

    private final CourseService courses;

    /** 산책 하나를 코스로. 선은 서버가 베껴 와 양 끝 100m 를 자른다. */
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public CourseResponse create(@CurrentUser User me, @Valid @RequestBody CourseRequest request) {
        return courses.create(me.getId(), request);
    }

    /** 내 코스 목록. 선은 빼고 시작점만 온다. */
    @GetMapping("/me")
    public List<CourseResponse> mine(@CurrentUser User me) {
        return courses.mine(me.getId());
    }

    /**
     * 공개 코스 한 벌 — 지도의 "이웃 코스".
     *
     * <p>좌표 파라미터가 <b>없다.</b> 가까운 것을 고르는 일은 기기에서 한다(A안 #235).
     */
    @GetMapping("/public")
    public List<CourseResponse> publicCourses(@CurrentUser User me) {
        return courses.publicCourses(me.getId());
    }

    /** 하나 — 선을 실어 준다. 내 것이거나 공개된 것만. */
    @GetMapping("/{courseId}")
    public CourseResponse one(@CurrentUser User me, @PathVariable long courseId) {
        return courses.one(me.getId(), courseId);
    }

    /** 공개 범위 바꾸기. */
    @PutMapping("/{courseId}/visibility")
    public CourseResponse changeVisibility(
            @CurrentUser User me,
            @PathVariable long courseId,
            @Valid @RequestBody VisibilityRequest request) {
        return courses.changeVisibility(me.getId(), courseId, request.visibility());
    }

    /** 지우기. */
    @DeleteMapping("/{courseId}")
    public ResponseEntity<Void> delete(@CurrentUser User me, @PathVariable long courseId) {
        courses.delete(me.getId(), courseId);
        return ResponseEntity.noContent().build();
    }

    /** 공개 범위 하나만 바꾸는 본문. */
    public record VisibilityRequest(
            @Pattern(regexp = "private|public", message = "공개 범위는 private 또는 public 입니다.")
            String visibility) {
    }
}
