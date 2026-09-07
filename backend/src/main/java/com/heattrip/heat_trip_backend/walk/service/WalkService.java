package com.heattrip.heat_trip_backend.walk.service;

import com.heattrip.heat_trip_backend.dog.entity.Dog;
import com.heattrip.heat_trip_backend.dog.DogOwnership;
import com.heattrip.heat_trip_backend.walk.dto.WalkPageResponse;
import com.heattrip.heat_trip_backend.walk.dto.WalkRequest;
import com.heattrip.heat_trip_backend.walk.dto.WalkResponse;
import com.heattrip.heat_trip_backend.walk.dto.WalkStatsResponse;
import com.heattrip.heat_trip_backend.walk.entity.Walk;
import com.heattrip.heat_trip_backend.walk.repository.WalkRepository;
import com.heattrip.heat_trip_backend.walk.repository.WalkTotals;

import lombok.RequiredArgsConstructor;

import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.data.domain.Limit;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.Clock;
import java.time.DayOfWeek;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.time.temporal.TemporalAdjusters;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

/**
 * 산책 기록 — 이슈 #145. 계약은 {@code /api/walks} 다.
 *
 * <h2>남의 것과 없는 것을 구분하지 않는다</h2>
 * <p>둘 다 404 다. 403 은 "그 id 는 존재한다" 를 알려 주는 셈이라, id 를 훑어 남이 산책을
 * 몇 번 했는지 셀 수 있다. 소유자 조건이 전부 쿼리 안에 있어서 서비스에 그 분기가 없다.
 *
 * <h2>주 경계는 KST 이고, Java 가 만든다</h2>
 * <p>MySQL 의 {@code WEEKDAY()}·{@code CURDATE()} 를 쓰지 않는다. 그것들은 세션 시간대를
 * 읽는데, 이 저장소의 JDBC URL 은 {@code serverTimezone=Asia/Seoul} 인 반면
 * <b>컨테이너 시계는 UTC</b> 다(실측). #40 에서 예산 테스트가 <b>00:00–09:00 KST 에만</b>
 * 빨간불이 나던 것이 정확히 그 종류의 함정이었다.
 *
 * <p>그래서 여기서 KST 로 이번 주 월요일 0시를 만들고, 그것을 UTC 벽시계로 눕혀 범위
 * 조건으로 넘긴다. 요일별로 접는 것도 Java 가 한다.
 */
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class WalkService {

    /** 우리 주 경계의 기준. */
    private static final ZoneId KST = ZoneId.of("Asia/Seoul");

    /**
     * 한 산책의 거리 상한(m).
     *
     * <p>200km 는 <b>관측이 아니다.</b> 하루 산책으로 말이 되는 범위의 바깥 경계로 잡았다.
     * 이 검사는 "말이 되는 값인가" 만 말하지 <b>"진짜 걸었는가" 는 말해 주지 않는다</b> —
     * 이 값들은 전부 앱이 스스로 신고한 것이다.
     */
    public static final int MAX_DISTANCE_M = 200_000;

    /** 한 산책의 시간 상한(초). 24시간이다. */
    public static final int MAX_DURATION_S = 86_400;

    /**
     * 시작 시각이 미래여도 되는 여유.
     *
     * <p>0 으로 두면 기기 시계가 몇 초 빠른 것만으로 정상 저장이 거절된다. 5분은 그 흔한
     * 어긋남을 덮으면서 "내일 산책" 을 미리 넣는 것은 막는 값이다.
     */
    private static final Duration FUTURE_TOLERANCE = Duration.ofMinutes(5);

    /** "자주 가는 곳" 에 싣는 개수. 계약이 maxItems 5 로 선언했다. */
    private static final int TOP_PLACES = 5;

    /** 목록 한 장의 기본·최대 크기. 계약이 선언한 값이다. */
    private static final int DEFAULT_LIMIT = 20;
    private static final int MAX_LIMIT = 100;

    private final WalkRepository walks;
    private final DogOwnership dogs;
    private final Clock clock;

    // ─────────────────────────── 저장 ───────────────────────────

    /**
     * 산책 하나를 저장한다.
     *
     * <h2>같은 것을 두 번 보내도 두 줄이 되지 않는다</h2>
     * <p>먼저 {@code clientWalkId} 로 찾아보고, 있으면 <b>그 행을 그대로</b> 돌려준다.
     * 없으면 넣는데, 그 사이에 다른 요청이 같은 키로 먼저 넣었을 수 있어서
     * {@link DataIntegrityViolationException} 을 잡아 <b>다시 찾는다.</b> "먼저 보고 넣는다"
     * 만으로는 동시 요청 둘을 막지 못한다 — 막는 것은 {@code uq_walk_client} 다.
     *
     * @return 새로 저장했으면 {@code true} 가 함께 온다(201), 재전송이면 {@code false}(200)
     */
    @Transactional
    public Saved save(long userId, WalkRequest request) {
        Dog dog = dogs.requireMineEntity(userId, request.dogId());
        validate(request);

        Optional<Walk> existing =
                walks.findByClientKey(dog.getId(), request.clientWalkId(), userId);
        if (existing.isPresent()) {
            return new Saved(WalkResponse.withPath(existing.get()), false);
        }

        Walk walk = Walk.builder()
                .dog(dog)
                .clientWalkId(request.clientWalkId())
                .startedAt(Walk.utc(request.startedAt()))
                .endedAt(request.endedAt() == null ? null : Walk.utc(request.endedAt()))
                .distanceM(request.distanceM())
                .durationS(request.durationS())
                .path(WalkPath.toLineString(request.path()))
                .pathT(WalkPath.toPathTimes(request.path(), request.pathT()))
                .memo(blankToNull(request.memo()))
                .weather(blankToNull(request.weather()))
                // 이름이 없으면 출처와 id 도 버린다 — 이름 없는 참조는 화면에 그릴 것이 없다(#338).
                .placeName(blankToNull(request.placeName()))
                .placeSource(request.placeName() == null || request.placeName().isBlank()
                        ? null : blankToNull(request.placeSource()))
                .placeContentId(request.placeName() == null || request.placeName().isBlank()
                        ? null : blankToNull(request.placeContentId()))
                .build();

        try {
            return new Saved(WalkResponse.withPath(walks.saveAndFlush(walk)), true);
        } catch (DataIntegrityViolationException concurrentDuplicate) {
            // uq_walk_client 가 막았다. 같은 산책이므로 이미 들어간 것을 준다.
            return walks.findByClientKey(dog.getId(), request.clientWalkId(), userId)
                    .map(saved -> new Saved(WalkResponse.withPath(saved), false))
                    .orElseThrow(() -> concurrentDuplicate);
        }
    }

    /** 저장 결과. {@code created} 가 참이면 201, 거짓이면 재전송이라 200 이다. */
    public record Saved(WalkResponse walk, boolean created) {
    }

    private void validate(WalkRequest request) {
        Instant now = clock.instant();

        if (request.distanceM() < 0 || request.distanceM() > MAX_DISTANCE_M) {
            throw new IllegalArgumentException(
                    "거리는 0m 이상 " + (MAX_DISTANCE_M / 1000) + "km 이하여야 합니다.");
        }
        if (request.durationS() < 0 || request.durationS() > MAX_DURATION_S) {
            throw new IllegalArgumentException("소요 시간은 0초 이상 24시간 이하여야 합니다.");
        }
        if (request.startedAt().isAfter(now.plus(FUTURE_TOLERANCE))) {
            throw new IllegalArgumentException("시작 시각이 미래일 수 없습니다.");
        }
        if (request.endedAt() != null && request.endedAt().isBefore(request.startedAt())) {
            throw new IllegalArgumentException("종료 시각이 시작 시각보다 앞설 수 없습니다.");
        }
        if (request.hasHalfPlaceRef()) {
            // 반쪽짜리 참조는 이름만 있는 것과 같으면서 있는 척한다 — 화면이 그 장소로 못 간다(#338).
            throw new IllegalArgumentException("장소 출처와 식별자는 함께 보내야 합니다.");
        }
        // 경로의 모양·좌표 순서는 WalkPath 가 본다. 여기서 부르지 않는 이유는 저장 직전에
        // 한 번만 변환하기 위해서다 — 두 번 순회할 이유가 없다.
    }

    // ─────────────────────────── 조회 ───────────────────────────

    /**
     * 내 산책 목록. 정렬은 {@code (createdAt, id)} 내림차순이다 — {@code startedAt} 이 아니다.
     *
     * <p>{@code startedAt} 은 앱이 보낸 값이라, 오프라인에 쌓아 둔 산책이 며칠 뒤 과거
     * 시각으로 들어온다. 그걸 커서로 쓰면 <b>이미 발급된 커서보다 아래 날짜의 행이 영원히
     * 건너뛰어진다.</b>
     *
     * <p>목록에는 <b>경로를 싣지 않는다</b> — 한 산책이 수천 점이라 응답이 메가바이트가 된다.
     */
    public WalkPageResponse page(long userId, Long dogId, String cursor, Integer limit) {
        if (dogId != null) {
            dogs.requireMine(userId, dogId);
        }
        int size = clamp(limit);

        // 한 줄 더 읽어서 hasMore 를 정한다. 별도 count 쿼리는 다음 장을 여는 사이에 값이
        // 바뀌고, 두 번 읽는 비용이 한 줄 더 읽는 비용보다 크다.
        Limit fetch = Limit.of(size + 1);
        List<Walk> rows = WalkCursor.parse(cursor)
                .map(c -> walks.findPageAfter(userId, dogId, c.createdAt(), c.id(), fetch))
                .orElseGet(() -> walks.findPage(userId, dogId, fetch));

        boolean hasMore = rows.size() > size;
        if (hasMore) {
            rows = rows.subList(0, size);
        }

        String next = hasMore && !rows.isEmpty()
                ? WalkCursor.of(rows.get(rows.size() - 1))
                : null;

        return new WalkPageResponse(rows.stream().map(WalkResponse::summary).toList(), next, hasMore);
    }

    /** 상세. 경로가 여기에만 실린다. 남의 것과 없는 것이 같은 404 다. */
    public WalkResponse detail(long userId, long walkId) {
        return walks.findMineById(walkId, userId)
                .map(WalkResponse::withPath)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND));
    }

    /**
     * 회고 글 교체 — 이슈 #187.
     *
     * <p><b>없는 산책과 남의 산책이 똑같이 404 다.</b> {@code detail}·{@code delete} 와 같은
     * 규칙이다 — 403 을 주면 "그 id 는 존재한다" 를 알려 주는 셈이라 id 를 훑어 남의 기록
     * 수를 셀 수 있다.
     *
     * <p>바뀐 뒤의 산책을 그대로 돌려준다. 앱이 저장 후 다시 조회하지 않아도 화면을 갱신할
     * 수 있어야 하고, 서버가 눕힌 값(빈 문자열 → {@code null})을 앱이 짐작하지 않게 한다.
     */
    @Transactional
    public WalkResponse rewriteMemo(long userId, long walkId, String memo) {
        Walk walk = walks.findMineById(walkId, userId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND));
        walk.rewriteMemo(memo);
        // 경로를 실어 돌려준다 — 이 응답을 받는 곳이 상세 화면이고, 거기는 경로를 그린다.
        return WalkResponse.withPath(walk);
    }

    /** 삭제. 남의 산책은 0행이 지워지고 그것이 404 다. */
    @Transactional
    public void delete(long userId, long walkId) {
        if (walks.deleteMine(walkId, userId) == 0) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND);
        }
    }

    // ─────────────────────────── 통계 ───────────────────────────

    /**
     * 이번 주(KST 월~일)와 전체 기간을 한 번에.
     *
     * <p>화면 둘이 이 응답 하나로 채워진다 — {@code me_screen} 의 "총 산책 / 총 거리 /
     * 이번주" 와 {@code myrecords_screen} 의 전체 기간 요약이다.
     */
    public WalkStatsResponse stats(long userId, Long dogId) {
        if (dogId != null) {
            dogs.requireMine(userId, dogId);
        }

        ZonedDateTime weekStart = clock.instant().atZone(KST)
                .with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
                .toLocalDate().atStartOfDay(KST);
        LocalDateTime fromUtc = Walk.utc(weekStart.toInstant());
        LocalDateTime toUtc = Walk.utc(weekStart.plusWeeks(1).toInstant());

        List<Walk> week = walks.findStartedBetween(userId, dogId, fromUtc, toUtc);

        double[] perDay = new double[7];
        // 초로 모았다가 마지막에 분으로 내린다. 요일마다 분으로 내려 더하면 하루 7분 짜리
        // 산책 다섯 번이 5분이 아니라 0분이 된다(#341).
        long[] perDaySeconds = new long[7];
        for (Walk walk : week) {
            // 월요일이 0 이다. 계약의 weekKm 이 "월~일 길이 7" 이라고 선언했다.
            int index = walk.startedAtInstant().atZone(KST).getDayOfWeek().getValue() - 1;
            perDay[index] += walk.getDistanceM() / 1000.0;
            perDaySeconds[index] += walk.getDurationS();
        }

        List<Double> weekKm = new ArrayList<>(7);
        double totalKm = 0;
        for (double km : perDay) {
            weekKm.add(round(km));
            totalKm += km;
        }
        List<Integer> weekMinutes = new ArrayList<>(7);
        for (long seconds : perDaySeconds) {
            weekMinutes.add((int) (seconds / 60));
        }
        int walkCount = week.size();

        WalkTotals all = walks.sumAllTime(userId, dogId);

        return new WalkStatsResponse(
                weekStart.toLocalDate(),
                weekStart.toLocalDate().plusDays(6),
                weekKm,
                weekMinutes,
                round(totalKm),
                walkCount,
                // 건수가 0 이면 나누지 않는다. 계약이 그 경우 0 이라고 선언했다.
                walkCount == 0 ? 0 : round(totalKm / walkCount),
                round(all.meters() / 1000.0),
                all.walks(),
                (int) (all.seconds() / 60),
                topPlaces(userId, dogId));
    }

    /**
     * 자주 간 곳 상위 다섯 (#338).
     *
     * <p><b>카탈로그에서 고른 곳만 센다.</b> 손으로 적은 이름은 계약의 {@code PlaceRef} 를
     * 만들 수 없어서(출처·id 가 없다) 여기 들어가지 못한다 — 기록 카드에는 그대로 보인다.
     * 전체 기간이다. 이번 주로 자르면 대부분의 사람에게 늘 한두 개만 남는다.
     */
    private List<WalkStatsResponse.TopPlace> topPlaces(long userId, Long dogId) {
        return walks.topPlaces(userId, dogId, Limit.of(TOP_PLACES)).stream()
                .map(row -> new WalkStatsResponse.TopPlace(
                        new WalkStatsResponse.PlaceRef(row.source(), row.contentId(), row.title()),
                        (int) row.count()))
                .toList();
    }

    // ─────────────────────────── 지그 ───────────────────────────

    /**
     * 소수점 둘째 자리까지. 0.1m 를 화면에 그릴 이유가 없고, 자르지 않으면
     * {@code 2.4000000000000004} 같은 값이 그대로 앱에 간다.
     */
    private static double round(double km) {
        return Math.round(km * 100) / 100.0;
    }

    private static int clamp(Integer limit) {
        if (limit == null || limit <= 0) {
            return DEFAULT_LIMIT;
        }
        return Math.min(limit, MAX_LIMIT);
    }

    private static String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value.strip();
    }
}
