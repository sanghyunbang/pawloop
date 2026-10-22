package com.heattrip.heat_trip_backend.place.layer;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.place.dto.PlaceDto;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;

/**
 * 반려견 놀이터 — 저장소에 넣어 둔 자산을 읽는다 (이슈 #346).
 *
 * <h2>왜 API 가 아닌가</h2>
 * <p>다른 레이어와 달리 <b>전국 표준데이터가 없다.</b> 공공데이터포털에서 "반려견 놀이터"
 * 로 찾으면 시·군·구가 각자 올린 파일이 나온다 — 고양·성남·파주·동대문구·서초구 등. 전국을
 * 한 API 로 주는 곳이 없다.
 *
 * <p>그래서 파일을 사람이 받아 {@code backend/tools/build_playgrounds.py} 로 합친다.
 * 갱신 주기가 "파일이 늘 때" 라 스케줄이 아니라 <b>배포가 갱신</b>이다.
 *
 * <h2>지금은 적다</h2>
 * <p>고양시 6곳으로 시작한다. 지자체 파일을 하나 더 받아 {@code backend/tools/data/} 에
 * 두고 스크립트를 다시 돌리면 <b>코드를 안 고치고</b> 늘어난다.
 */
@Component
public class PlaygroundAsset {

    private static final Logger log = LoggerFactory.getLogger(PlaygroundAsset.class);

    /** 자산 경로. {@code build_playgrounds.py} 의 출력과 같아야 한다. */
    static final String PATH = "data/playgrounds.json";

    private final ObjectMapper objectMapper;

    public PlaygroundAsset(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    /** 자산 안의 놀이터 전부. 파일이 없거나 깨졌으면 빈 목록 — 부팅을 막지 않는다. */
    public List<PlaceDto> load() {
        JsonNode root;
        try (InputStream in = new ClassPathResource(PATH).getInputStream()) {
            root = objectMapper.readTree(new String(in.readAllBytes(), StandardCharsets.UTF_8));
        } catch (IOException e) {
            log.warn("놀이터 자산을 읽지 못했다 — {} ({})", PATH, e.getClass().getSimpleName());
            return List.of();
        }

        JsonNode items = root.path("playgrounds");
        if (!items.isArray()) {
            log.warn("놀이터 자산에 playgrounds 배열이 없다 — {}", PATH);
            return List.of();
        }

        List<PlaceDto> places = new ArrayList<>(items.size());
        int skipped = 0;
        for (JsonNode node : items) {
            PlaceDto place = toPlace(node);
            if (place == null) {
                skipped++;
                continue;
            }
            places.add(place);
        }
        log.info("놀이터 자산 — 담은 곳 {} · 건너뜀 {} · 기준일 {}",
                places.size(), skipped, root.path("version").asText("?"));
        return places;
    }

    private PlaceDto toPlace(JsonNode node) {
        String id = node.path("id").asText("");
        String name = node.path("name").asText("");
        double lat = node.path("lat").asDouble(0);
        double lng = node.path("lng").asDouble(0);
        if (id.isBlank() || name.isBlank() || lat == 0 || lng == 0) {
            return null;
        }
        return new PlaceDto(
                id,
                name,
                PlaceDto.SOURCE_PLAYGROUND,
                PlaceDto.SOURCE_PLAYGROUND,
                null,
                lat,
                lng,
                node.path("addr").asText(""),
                emptyToNull(node.path("tel").asText("")),
                null,
                null,
                // 요약을 비운다. 여기 넣던 `org` 는 **관리 부서 이름**이라
                // "농업기술센터 농산유통과" 같은 값이 반려견 놀이터 카드에 그대로 떴다 —
                // 실제로 걸어 보니 "무슨 농업 공사냐" 는 말이 나왔다. 데이터는 맞지만
                // 사용자가 읽을 문장이 아니다. 전화번호는 그대로 두므로 문의할 길은 남는다.
                null);
    }

    private static String emptyToNull(String s) {
        return s == null || s.isBlank() ? null : s;
    }
}
