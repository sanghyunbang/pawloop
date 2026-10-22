package com.heattrip.heat_trip_backend.place.layer;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Optional;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.place.dto.PlaceDto;
import com.heattrip.heat_trip_backend.place.dto.TrailRouteDto;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 동네 길을 눌렀을 때 줄 것이 있는가 — 이슈 #619. <b>커밋된 자산 전체</b>를 본다.
 *
 * <p>이 검사가 막는 것은 "목록에는 있는데 눌러도 아무 일도 안 나는 길" 이다. 그것이
 * 2026-09-17 에 신고가 들어온 그 화면이다. 표본 하나로는 못 잡는다 — 자산이 1,302개고
 * 경유지 글의 모양이 제각각이라, 한 줄만 보면 나머지 1,301개가 어떤지 아무것도 모른다.
 */
class LocalTrailAssetRouteTest {

    private final LocalTrailAsset asset = new LocalTrailAsset(new ObjectMapper());

    @Test
    @DisplayName("목록의 항목을 그대로 눌러도 답이 온다 — contentId 와 코스 번호가 안 갈린다")
    void everyListedTrailAnswersWhenAsked() {
        List<PlaceDto> listed = asset.load();
        assertThat(listed).as("자산이 비면 이 검사는 아무것도 안 본다").hasSizeGreaterThan(1_000);

        List<String> silent = listed.stream()
                .map(p -> p.contentId().substring("trail:".length()))
                .filter(courseId -> asset.route(courseId).isEmpty())
                .toList();

        assertThat(silent)
                .as("이 코스들은 목록에 뜨지만 누르면 줄 것이 없다 — %d/%d", silent.size(), listed.size())
                .isEmpty();
    }

    @Test
    @DisplayName("답에는 거쳐 가는 곳이 둘 이상 들어 있다 — 조각 하나짜리 '경로' 는 경로가 아니다")
    void mostAnswersCarryARealSequence() {
        List<PlaceDto> listed = asset.load();

        long single = listed.stream()
                .map(p -> asset.route(p.contentId().substring("trail:".length())))
                .flatMap(Optional::stream)
                .filter(r -> r.waypoints().size() < 2)
                .count();

        // 원본이 통째로 한 문장인 코스가 스물쯤 있다(2026-09-17 에 셈). 그것까지 없애려면
        // 원본을 고쳐야 하므로, 늘지 않는 것만 잠근다.
        assertThat(single)
                .as("경유지를 못 쪼갠 코스가 늘었다 — 자르는 규칙이 약해졌는지 본다")
                .isLessThanOrEqualTo(25);
    }

    @Test
    @DisplayName("선이 없다고 말한다 — points 는 빈 배열이고 hasLine 은 거짓이다")
    void localTrailsSayTheyHaveNoLine() {
        PlaceDto any = asset.load().get(0);
        TrailRouteDto route = asset.route(any.contentId().substring("trail:".length())).orElseThrow();

        assertThat(route.hasLine()).isFalse();
        assertThat(route.pointCount()).isZero();
        assertThat(route.points())
                .as("null 이면 앱이 파싱에서 갈린다 — 빈 배열이어야 한다")
                .isEqualTo("[]");
        assertThat(route.name()).isEqualTo(any.title());
    }

    @Test
    @DisplayName("두루누비 코스 번호로는 자산을 읽지도 않는다 — 여기 것이 아니다")
    void durunubiCourseIdsAreNotOurs() {
        assertThat(asset.route("T_CRS_MNG0000005671")).isEmpty();
        assertThat(asset.route("")).isEmpty();
        assertThat(asset.route(null)).isEmpty();
    }

    @Test
    @DisplayName("괄호 짝이 깨진 조각은 손에 꼽는다 — 원본이 구)군산세관 처럼 적은 자리뿐이다")
    void splittingLeavesAlmostNoBrokenNames() {
        long broken = asset.load().stream()
                .map(p -> asset.route(p.contentId().substring("trail:".length())))
                .flatMap(Optional::stream)
                .filter(r -> r.waypoints().stream()
                        .anyMatch(s -> count(s, '(') != count(s, ')')))
                .count();

        // 2026-09-17 에 재면 셋이다. 괄호 깊이를 안 세면 서른하나가 된다 —
        // 이 숫자가 그 규칙이 살아 있다는 증거다.
        assertThat(broken)
                .as("짝이 깨진 이름이 늘었다 — 괄호 깊이를 세는 규칙이 무너졌는지 본다")
                .isLessThanOrEqualTo(5);
    }

    private static long count(String s, char c) {
        return s.chars().filter(ch -> ch == c).count();
    }
}
