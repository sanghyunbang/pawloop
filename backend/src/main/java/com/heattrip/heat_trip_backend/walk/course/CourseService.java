package com.heattrip.heat_trip_backend.walk.course;

import com.heattrip.heat_trip_backend.walk.CourseAttachment;
import com.heattrip.heat_trip_backend.walk.entity.Walk;
import com.heattrip.heat_trip_backend.walk.repository.WalkRepository;
import com.heattrip.heat_trip_backend.walk.service.WalkPath;

import lombok.RequiredArgsConstructor;

import org.springframework.data.domain.Limit;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

/**
 * 코스 — 이슈 #339.
 *
 * <h2>선은 서버가 자른다</h2>
 * <p>앱이 자른 선을 받지 않는다. 받으면 "양 끝 100m 를 버린다" 는 약속을 <b>앱 버전마다</b>
 * 다시 지켜야 하고, 안 자르는 옛 앱 하나가 그 사람의 집 앞을 공개한다. 그래서 여기서
 * {@code walk.path} 를 읽어 {@link CoursePath#trimEnds} 를 지난 것만 저장한다.
 *
 * <h2>남의 것과 없는 것은 같은 404</h2>
 * <p>산책도 코스도 소유권 조건이 쿼리 안에 있다. 여기서 갈라 주면 "그 번호는 있는데 남의
 * 것" 이 응답으로 새어 나간다.
 */
@Service
@RequiredArgsConstructor
public class CourseService implements CourseAttachment {

    /** 목록 한 장의 크기. 코스는 한 사람이 수십 개를 만들 것이라 커서를 두지 않는다. */
    private static final int MINE_LIMIT = 100;

    /** 지도가 받아 가는 공개 코스의 최대 개수. 앱이 여기서 가까운 20개를 고른다. */
    private static final int PUBLIC_LIMIT = 300;

    /** 저장 순서를 그대로 두되 중복은 지운다 — 태그가 셋뿐이라 정렬을 강요하지 않는다. */
    private static final Set<String> ALLOWED_TAGS = Set.of("leash", "poopbag", "shade");

    private final CourseRepository courses;
    private final WalkRepository walks;

    /** "우리 집 식구는 누구인가" — group 모듈의 공개 표면(#563). */
    private final com.heattrip.heat_trip_backend.group.FamilyMembership family;

    /** 산책 하나를 코스로. 이미 만든 산책이어도 막지 않는다 — 이름이 다른 코스일 수 있다. */
    @Transactional
    public CourseResponse create(long userId, CourseRequest request) {
        // 우리 집 산책이면 코스로 만들 수 있다(#563). 아빠가 걸은 보리 산책을 엄마가
        // 코스로 남기는 것이 정상이다 — 같은 길을 같이 걷는다.
        Walk walk = walks.findInHouseholdById(request.walkId(), family.householdUserIds(userId))
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "그 산책을 찾을 수 없습니다."));

        List<List<Double>> full = WalkPath.toPoints(walk.getPath());
        if (full == null || full.size() < 2) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "경로가 없는 산책은 코스로 만들 수 없습니다.");
        }

        List<List<Double>> trimmed = CoursePath.trimEnds(full);
        if (trimmed == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "시작·끝 " + CoursePath.TRIM_METERS + "m 를 빼면 남는 길이 없습니다. "
                            + "300m 쯤은 걸어야 코스로 남길 수 있어요.");
        }

        Course course = Course.builder()
                .userId(userId)
                .walkId(walk.getId())
                .name(request.name().strip())
                .note(blankToNull(request.note()))
                .tags(joinTags(request.tags()))
                .path(WalkPath.toLineString(trimmed))
                .distanceM((int) Math.round(CoursePath.lengthMeters(trimmed)))
                .durationS(walk.getDurationS())
                .visibility(Course.PUBLIC.equals(request.visibility()) ? Course.PUBLIC : Course.PRIVATE)
                .build();

        return CourseResponse.withPath(courses.save(course), userId);
    }

    /** 내 코스 목록. 선은 빼고 시작점만 준다 — 목록에 선 수십 개를 실을 이유가 없다. */
    @Transactional(readOnly = true)
    public List<CourseResponse> mine(long userId) {
        return courses.findMine(userId, Limit.of(MINE_LIMIT)).stream()
                .map(course -> CourseResponse.summary(course, userId))
                .toList();
    }

    /** 하나. 내 것이거나 공개된 것만. 남의 비공개는 <b>없는 것과 같은 404</b>. */
    @Transactional(readOnly = true)
    public CourseResponse one(long userId, long courseId) {
        return courses.findVisible(courseId, userId)
                .map(course -> CourseResponse.withPath(course, userId))
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "그 코스를 찾을 수 없습니다."));
    }

    /**
     * 공개 코스 한 벌 — 지도의 "이웃 코스".
     *
     * <p>좌표를 받지 않는다. 앱이 이 목록에서 가까운 것을 <b>기기에서</b> 고른다(#235).
     */
    @Transactional(readOnly = true)
    public List<CourseResponse> publicCourses(long userId) {
        return courses.findPublic(Limit.of(PUBLIC_LIMIT)).stream()
                .map(course -> CourseResponse.summary(course, userId))
                .toList();
    }

    /** 공개 범위 바꾸기. 내 코스만. */
    @Transactional
    public CourseResponse changeVisibility(long userId, long courseId, String visibility) {
        Course course = courses.findVisible(courseId, userId)
                .filter(found -> found.getUserId() == userId)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "그 코스를 찾을 수 없습니다."));
        course.changeVisibility(visibility);
        return CourseResponse.withPath(courses.save(course), userId);
    }

    /** 지우기. 내 코스만 — 남의 것은 0행이 지워지고 404 다. */
    @Transactional
    public void delete(long userId, long courseId) {
        Course course = courses.findVisible(courseId, userId)
                .filter(found -> found.getUserId() == userId)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "그 코스를 찾을 수 없습니다."));
        courses.delete(course);
    }

    // ─────────────────── 밖으로 내놓는 표면 (CourseAttachment) ───────────────────

    /** 카드에 싣는 점의 상한. 카드 크기의 그림에는 이만큼이면 충분하다. */
    private static final int CARD_POINTS = 40;

    @Override
    @Transactional(readOnly = true)
    public Optional<AttachedCourse> forAttaching(long courseId, long userId) {
        return courses.findById(courseId)
                .filter(course -> course.getUserId() == userId)
                .filter(Course::isPublic)
                .map(CourseService::toCard);
    }

    @Override
    @Transactional(readOnly = true)
    public Map<Long, AttachedCourse> cards(Collection<Long> courseIds) {
        if (courseIds == null || courseIds.isEmpty()) {
            return Map.of();
        }
        Map<Long, AttachedCourse> out = new LinkedHashMap<>();
        for (Course course : courses.findPublicByIds(courseIds)) {
            out.put(course.getId(), toCard(course));
        }
        return out;
    }

    private static AttachedCourse toCard(Course course) {
        return new AttachedCourse(
                course.getId(),
                course.getName(),
                course.getDistanceM(),
                CoursePath.simplify(WalkPath.toPoints(course.getPath()), CARD_POINTS));
    }

    private static String joinTags(List<String> tags) {
        if (tags == null || tags.isEmpty()) {
            return null;
        }
        Set<String> kept = new LinkedHashSet<>();
        for (String tag : tags) {
            if (tag != null && ALLOWED_TAGS.contains(tag.strip())) {
                kept.add(tag.strip());
            }
        }
        return kept.isEmpty() ? null : String.join(",", kept);
    }

    private static String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value.strip();
    }
}
