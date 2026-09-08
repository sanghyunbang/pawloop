package com.heattrip.heat_trip_backend.place.layer;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.place.dto.PlaceDto;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;

/**
 * 동네 길 — 저장소에 넣어 둔 자산을 읽는다 (이슈 #346).
 *
 * <h2>왜 API 가 아닌가</h2>
 * <p>원본은 전국길관광정보표준데이터(공공데이터포털 15017321)이고 <b>갱신주기가 "연간"</b>이다.
 * 1년에 한 번 바뀌는 값을 매달 부를 이유가 없다 — 행정동 목록(#342)에서 내린 것과 같은
 * 판단이다. 한 번 받아 좌표를 붙인 결과를 커밋해 두면 활용신청도, 런타임 외부 호출도,
 * 그 호출이 죽는 날의 빈 지도도 없다.
 *
 * <p>자산을 만드는 것은 {@code backend/tools/build_local_trails.py} 다. 원본에는 <b>좌표가
 * 없어</b>(주소 문자열뿐이다) 그 스크립트가 시작지점 주소를 좌표로 바꾼다.
 *
 * <h2>왜 두루누비와 같은 {@code trail} 로 나가나</h2>
 * <p>사용자에게 둘 다 <b>산책로</b>다. 계약({@code PlaceCategory})과 앱의 칩 목록을 건드리지
 * 않으려고 {@code source}·{@code category} 를 {@code trail} 로 맞춘다. {@code contentId} 만
 * {@code trail:lt…} 로 갈라 두루누비의 {@code trail:T_CRS_…} 와 안 겹치게 한다.
 *
 * <p>{@code place_catalog} 에서는 행을 따로 둔다({@code localtrail}) — 갱신 주기가 다르고,
 * 두루누비가 아픈 날 동네 길까지 사라지면 안 된다.
 *
 * <h2>선이 없다</h2>
 * <p>원본의 {@code 경로정보} 는 {@code 산수교→월성마을→황점마을} 꼴의 <b>글</b>이라
 * {@code trail_route} 에 넣을 선이 없다. 그래서 이 출처의 코스는 지도에 <b>점</b>으로만
 * 뜬다 — 두루누비는 선을 그리고, 이쪽은 시작점과 경유지 이름을 준다.
 */
@Component
public class LocalTrailAsset {

    private static final Logger log = LoggerFactory.getLogger(LocalTrailAsset.class);

    /** 자산 경로. {@code build_local_trails.py} 의 출력과 같아야 한다. */
    static final String PATH = "data/local_trails.json";

    /** 두루누비와 안 겹치게 하는 접두어. */
    static final String ID_PREFIX = PlaceDto.SOURCE_TRAIL + ":lt";

    private final ObjectMapper objectMapper;

    public LocalTrailAsset(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    /** 자산 안의 길 전부. 파일이 없거나 깨졌으면 빈 목록 — 부팅을 막지 않는다. */
    public List<PlaceDto> load() {
        JsonNode root;
        try (InputStream in = new ClassPathResource(PATH).getInputStream()) {
            root = objectMapper.readTree(new String(in.readAllBytes(), StandardCharsets.UTF_8));
        } catch (IOException e) {
            log.warn("동네 길 자산을 읽지 못했다 — {} ({})", PATH, e.getClass().getSimpleName());
            return List.of();
        }

        JsonNode trails = root.path("trails");
        if (!trails.isArray()) {
            log.warn("동네 길 자산에 trails 배열이 없다 — {}", PATH);
            return List.of();
        }

        List<PlaceDto> places = new ArrayList<>(trails.size());
        int skipped = 0;
        for (JsonNode t : trails) {
            PlaceDto place = toPlace(t);
            if (place == null) {
                skipped++;
                continue;
            }
            places.add(place);
        }
        log.info("동네 길 자산 — 담은 곳 {} · 건너뜀 {} · 기준일 {}",
                places.size(), skipped, root.path("version").asText("?"));
        return places;
    }

    private PlaceDto toPlace(JsonNode t) {
        String id = t.path("id").asText("");
        String name = t.path("name").asText("");
        double lat = t.path("lat").asDouble(0);
        double lng = t.path("lng").asDouble(0);
        // 좌표가 0 인 행은 자산에 없어야 하지만, 있으면 지도의 (0,0) 에 점이 찍힌다.
        if (id.isBlank() || name.isBlank() || lat == 0 || lng == 0) {
            return null;
        }
        return new PlaceDto(
                ID_PREFIX + id.substring(id.lastIndexOf(':') + 1),
                name,
                PlaceDto.SOURCE_TRAIL,
                PlaceDto.SOURCE_TRAIL,
                null,
                lat,
                lng,
                t.path("addr").asText(""),
                emptyToNull(t.path("tel").asText("")),
                null,
                null,
                summaryOf(t));
    }

    /** {@code 3.4km · 약 1시간 30분 · 시작 성수교} — 두루누비 요약과 같은 결. */
    static String summaryOf(JsonNode t) {
        List<String> parts = new ArrayList<>(3);
        if (t.hasNonNull("lengthKm")) {
            double km = t.path("lengthKm").asDouble();
            parts.add(km == Math.floor(km)
                    ? String.format(Locale.KOREA, "%.0fkm", km)
                    : String.format(Locale.KOREA, "%.1fkm", km));
        }
        if (t.hasNonNull("minutes")) {
            parts.add("약 " + humanMinutes(t.path("minutes").asInt()));
        }
        String waypoints = t.path("waypoints").asText("");
        if (!waypoints.isBlank()) {
            // 경유지가 길면 앞의 셋만 — 카드 한 줄에 들어가야 한다.
            String[] hops = waypoints.split("→");
            parts.add(hops.length <= 3 ? waypoints : String.join("→", hops[0], hops[1], hops[2]) + "→…");
        }
        return parts.isEmpty() ? null : String.join(" · ", parts);
    }

    /** {@code 90} → {@code 1시간 30분}. 한 시간 미만은 분만. */
    static String humanMinutes(int minutes) {
        if (minutes < 60) {
            return minutes + "분";
        }
        int hours = minutes / 60;
        int rest = minutes % 60;
        return rest == 0 ? hours + "시간" : hours + "시간 " + rest + "분";
    }

    private static String emptyToNull(String s) {
        return s == null || s.isBlank() ? null : s;
    }
}
