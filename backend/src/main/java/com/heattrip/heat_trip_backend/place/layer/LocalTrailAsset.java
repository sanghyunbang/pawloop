package com.heattrip.heat_trip_backend.place.layer;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.place.dto.PlaceDto;
import com.heattrip.heat_trip_backend.place.dto.TrailRouteDto;

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
 * <h2>선이 없다 — 그래도 입을 닫지는 않는다 (#619)</h2>
 * <p>원본의 {@code 경로정보} 는 {@code 산수교→월성마을→황점마을} 꼴의 <b>글</b>이라
 * {@code trail_route} 에 넣을 선이 없다. 그래서 이 출처의 코스는 지도에 <b>점</b>으로만
 * 뜬다 — 두루누비는 선을 그리고, 이쪽은 시작점과 경유지 이름을 준다.
 *
 * <p>예전에는 그 "경유지 이름" 을 아무 데서도 안 줬다. {@code /trails/{id}/route} 가
 * <b>404</b> 였고 앱은 아예 묻지도 않아서, 사용자가 동네 길을 눌러도 <b>아무 일도 안 났다</b>
 * (2026-09-17 에 사장님이 그렇게 신고했다). 지금은 {@link #route(String)} 가 그 이름들을
 * 답한다 — 선 대신 거쳐 가는 곳이다.
 */
@Component
public class LocalTrailAsset {

    private static final Logger log = LoggerFactory.getLogger(LocalTrailAsset.class);

    /** 자산 경로. {@code build_local_trails.py} 의 출력과 같아야 한다. */
    static final String PATH = "data/local_trails.json";

    /**
     * 두루누비의 코스 번호({@code T_CRS_…})와 안 겹치게 하는 접두어.
     *
     * <p>앱은 {@code contentId} 에서 {@code trail:} 를 떼고 코스 번호로 쓰므로, 이 두 글자가
     * 곧 "이건 동네 길이다" 라는 표시가 된다 — {@link #route(String)} 가 그걸로 가른다.
     */
    static final String COURSE_PREFIX = "lt";

    /** 두루누비와 안 겹치게 하는 접두어. */
    static final String ID_PREFIX = PlaceDto.SOURCE_TRAIL + ":" + COURSE_PREFIX;

    private final ObjectMapper objectMapper;

    public LocalTrailAsset(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    /**
     * 코스 번호 하나의 <b>경유지</b> — 이슈 #619. 선이 없는 대신 거쳐 가는 곳의 이름이다.
     *
     * <p>{@code courseId} 는 앱이 {@code contentId} 에서 {@code trail:} 를 떼고 보내는 값이라
     * {@code lt…} 로 시작한다. 두루누비({@code T_CRS_…})는 여기 것이 아니라 바로 빈 값이다 —
     * <b>자산을 읽지도 않는다.</b> 그 판단이 없으면 두루누비 코스 하나를 물을 때마다 1,302개를
     * 훑게 된다.
     *
     * <p>경유지 글이 비어 있으면 {@code Optional.empty()} 다. 조각이 0개인 답을 주는 것은
     * "이 길은 아무 데도 안 간다" 는 뜻이 되어 404 보다 나쁘다.
     */
    public Optional<TrailRouteDto> route(String courseId) {
        if (courseId == null || !courseId.startsWith(COURSE_PREFIX)) {
            return Optional.empty();
        }
        JsonNode t = index().get(courseId.strip());
        if (t == null) {
            return Optional.empty();
        }
        List<String> stops = LocalTrailWaypoints.split(t.path("waypoints").asText(""));
        if (stops.isEmpty()) {
            return Optional.empty();
        }
        Integer lengthM = PlaceDto.metersOf(
                t.hasNonNull("lengthKm") ? t.path("lengthKm").asDouble() : null);
        return Optional.of(TrailRouteDto.ofStops(
                courseId.strip(), t.path("name").asText(""), lengthM == null ? 0 : lengthM, stops));
    }

    /**
     * 코스 번호 → 그 길. 처음 물을 때 한 번 만든다.
     *
     * <p>자산은 커밋된 파일이라 돌아가는 동안 안 바뀐다. {@code volatile} 한 번 쓰기로 충분하고,
     * 둘이 동시에 들어와 두 번 만들어도 같은 것이 나온다 — 자물쇠를 걸 이유가 없다.
     */
    private Map<String, JsonNode> index() {
        Map<String, JsonNode> built = byCourseId;
        if (built != null) {
            return built;
        }
        Map<String, JsonNode> fresh = new LinkedHashMap<>();
        for (JsonNode t : trailsNode()) {
            String id = t.path("id").asText("");
            if (!id.isBlank()) {
                fresh.put(courseIdOf(id), t);
            }
        }
        byCourseId = fresh;
        return fresh;
    }

    private volatile Map<String, JsonNode> byCourseId;

    /**
     * 자산의 {@code trails} 배열. 파일이 없거나 깨졌으면 <b>빈 배열</b>이다 — 부팅을 막지 않는다.
     *
     * <p>{@link #load()} 와 {@link #index()} 가 같은 읽기를 쓰게 모아 둔 것이다. 두 곳이 따로
     * 읽으면 한쪽만 고쳐져 <b>목록에는 있는데 눌러도 없는 길</b>이 생긴다.
     */
    private JsonNode trailsNode() {
        JsonNode root;
        try (InputStream in = new ClassPathResource(PATH).getInputStream()) {
            root = objectMapper.readTree(new String(in.readAllBytes(), StandardCharsets.UTF_8));
        } catch (IOException e) {
            log.warn("동네 길 자산을 읽지 못했다 — {} ({})", PATH, e.getClass().getSimpleName());
            return objectMapper.createArrayNode();
        }
        JsonNode trails = root.path("trails");
        if (!trails.isArray()) {
            log.warn("동네 길 자산에 trails 배열이 없다 — {}", PATH);
            return objectMapper.createArrayNode();
        }
        return trails;
    }

    /**
     * 자산의 {@code localtrail:1a87…} 를 앱이 보내는 코스 번호 {@code lt1a87…} 로.
     *
     * <p>{@code contentId} 도 이 값으로 만든다({@link #toPlace}). <b>한 군데서 나와야</b>
     * 목록의 항목과 그 항목을 눌렀을 때 묻는 번호가 갈리지 않는다.
     */
    private static String courseIdOf(String assetId) {
        return COURSE_PREFIX + assetId.substring(assetId.lastIndexOf(':') + 1);
    }

    /** 자산 안의 길 전부. 파일이 없거나 깨졌으면 빈 목록 — 부팅을 막지 않는다. */
    public List<PlaceDto> load() {
        JsonNode trails = trailsNode();
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
        log.info("동네 길 자산 — 담은 곳 {} · 건너뜀 {}", places.size(), skipped);
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
                PlaceDto.SOURCE_TRAIL + ":" + courseIdOf(id),
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
                summaryOf(t),
                PlaceDto.metersOf(t.hasNonNull("lengthKm") ? t.path("lengthKm").asDouble() : null));
    }

    /**
     * 카드 한 줄에 들어가는 요약 — {@code 3.4km · 약 1시간 30분}.
     *
     * <h3>경유지를 안 쓴다</h3>
     * <p>예전에는 {@code waypoints} 의 앞 세 곳을 이어 붙이고 {@code →…} 로 잘랐다. 화면이
     * 그 줄을 다시 한 줄로 자르므로 사용자에게는 <b>"화살표 화살표 있다가 끊긴"</b> 문장으로
     * 보였다(실제로 사장님이 그렇게 신고했다).
     *
     * <p>고쳐 쓰기도 어렵다. 1,302개 원본의 구분자가 <b>일곱 가지</b>다 —
     * {@code →}(1008) · {@code -}(208) · {@code ~}(52) · {@code ,}(48) · {@code ->}(13) ·
     * {@code >} · {@code ∼}. 게다가 {@code 둘레길(연화산유원지~송이재입구~연화산유원지)} 처럼
     * 괄호가 걸쳐 있어 어떤 기준으로 잘라도 <b>반쪽짜리 이름</b>이 남는다. 그래서 카드에서는
     * 빼고, 확실한 두 값(거리·시간)만 적는다.
     *
     * <h3>여덟 시간을 넘는 시간은 안 적는다</h3>
     * <p>1,302개 중 315개가 다섯 시간을 넘고 가장 긴 것은 <b>88시간</b>이다. 국토종주급 코스의
     * 완주 시간이라 "이 길을 산책하는 데 걸리는 시간" 이 아니다. 카드에 "약 88시간" 이 뜨면
     * 사용자는 값이 깨진 줄 안다. <b>지어내지 않고 빼는 쪽</b>을 고른다 — 거리는 그대로 남아
     * 얼마나 긴 길인지는 말해 준다.
     */
    static String summaryOf(JsonNode t) {
        List<String> parts = new ArrayList<>(3);
        if (t.hasNonNull("lengthKm")) {
            double km = t.path("lengthKm").asDouble();
            parts.add(km == Math.floor(km)
                    ? String.format(Locale.KOREA, "%.0fkm", km)
                    : String.format(Locale.KOREA, "%.1fkm", km));
        }
        if (t.hasNonNull("minutes")) {
            int minutes = t.path("minutes").asInt();
            if (minutes > 0 && minutes <= MAX_SHOWN_MINUTES) {
                parts.add("약 " + humanMinutes(minutes));
            }
        }
        return parts.isEmpty() ? null : String.join(" · ", parts);
    }

    /** 이 시간을 넘으면 카드에 안 적는다 — 산책 시간이 아니라 완주 시간이다. */
    static final int MAX_SHOWN_MINUTES = 480;

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
