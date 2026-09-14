package com.heattrip.heat_trip_backend.place.layer;

import com.heattrip.heat_trip_backend.place.GeoDistance;
import com.heattrip.heat_trip_backend.place.dto.PlaceDto;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/**
 * 같은 자리를 두 출처가 가리키면 하나만 남긴다 — 이슈 #411.
 *
 * <h2>무엇이 겹치나</h2>
 * <p>일산호수공원에서 목록을 보면 "일산호수공원 반려견 놀이터"(우리 놀이터 자산)와
 * "일산호수공원 반려견놀이터"(관광공사)가 두 줄이었다. 이름이 한 칸 다르고 좌표가 33m
 * 떨어져 있다. 2026-09-09 한 벌에서 세면 우리 자산 1,308곳 중 19곳이 이렇다 — 1.5% 지만
 * 하필 사람들이 찾는 곳(호수공원 · 유명한 길)이다.
 *
 * <h2>결정 — 사진이 있는 쪽(관광공사)을 남긴다 (사장님, 2026-09-13)</h2>
 * <p>우리 자산(놀이터 · 동네 길)이 관광공사 · 두루누비 · 인허가 항목과 <b>200m 안</b>에서
 * <b>공백을 지운 이름이 같거나 한쪽이 다른 쪽을 포함</b>하면 우리 것을 뺀다. 그쪽에 사진과
 * 상세가 있다. 규칙의 숫자는 이슈가 센 그대로다 — 실제 짝은 6m 부터 155m 까지 흩어져 있었다.
 *
 * <h2>놀이터만 옮겨 단다</h2>
 * <p>우리 놀이터 자산이 관광공사 항목에 밀리면 그 자리의 "놀이터" 배지가 사라져 놀이터 칩으로
 * 못 찾는다 — 이 자산을 만든 이유가 그것이다. 그래서 밀린 관광공사 항목에 {@code category =
 * playground} 를 옮겨 달고 {@code contentTypeId} 를 비운다(앱은 {@code contentTypeId} 를
 * 먼저 보므로 비워야 놀이터로 읽는다). 관광공사에 없는 전화번호가 우리 쪽에 있으면 그것도
 * 옮긴다. <b>동네 길은 옮기지 않는다</b> — "자라섬째즈길" 에 밀린 "자라섬" 은 산책로가 아니라
 * 여행지다.
 *
 * <h2>우리 것끼리는 안 묶는다 · 가게에는 안 진다</h2>
 * <p>규칙은 "우리 자산 대 다른 출처" 다. 두루누비와 인허가는 서로 겹칠 일이 없고, 우리 놀이터
 * 둘이 이웃해 있으면 둘 다 진짜다. 상대는 같은 곳일 수 있는 종류({@link #SAME_PLACE_KINDS})여야
 * 한다 — 길이 쇼핑 · 음식점 · 숙박과 같은 곳일 수는 없다.
 *
 * <p>순수 함수다 — 스프링도 DB 도 모른다. {@link LayerPlaceIndex} 가 출처의 ETag 가 바뀔 때만
 * 다시 부른다.
 */
public final class PlaceDedupe {

    /** 겹침으로 보는 거리. */
    static final double MAX_DISTANCE_M = 200;

    /** "포함" 으로 묶으려면 짧은 쪽이 이만큼은 돼야 한다 — "길" 은 모든 길을 포함한다. */
    static final int MIN_NAME_LENGTH = 2;

    /**
     * 우리 자산(놀이터 · 길)이 <b>같은 곳일 수 있는</b> 상대의 카테고리 — 관광지(12) · 문화(14) ·
     * 레포츠(28) · 여행코스(25) · 걷기길({@code trail}). 쇼핑 · 음식점 · 숙박 · 병원 · 펫샵은
     * 아니다: 실제 한 벌로 돌려 보니 동네 길 "삼청동" 이 139m 안의 쇼핑 "은나무 삼청동점" 에
     * 포함돼 묶였다. 이름 규칙만으로는 그것을 못 가른다.
     */
    static final Set<String> SAME_PLACE_KINDS = Set.of("12", "14", "28", "25", PlaceDto.SOURCE_TRAIL);

    /** 이웃 칸 격자 — 0.005° 는 위도 550m · 경도 440m(서울). 3×3 칸이면 200m 를 덮고 남는다. */
    private static final double CELL_DEG = 0.005;

    private PlaceDedupe() {
    }

    /**
     * 정리한 결과.
     *
     * @param kto       관광공사 한 벌 — 놀이터를 옮겨 단 항목은 사본으로 바뀌어 있다
     * @param layers    관광공사 밖의 레이어 전부 — 다른 출처 그대로 + 살아남은 우리 자산
     * @param overrides 옮겨 단 관광공사 항목, {@code contentId} 로. KTO 셀에서 온 원본을 바꿔 끼울 때 쓴다
     * @param dropped   뺀 우리 자산의 수
     */
    public record Merged(List<PlaceDto> kto,
                         List<PlaceDto> layers,
                         Map<String, PlaceDto> overrides,
                         int dropped) {

        /** KTO 셀에서 온 항목을, 옮겨 단 것이 있으면 그 사본으로 바꾼다. */
        public PlaceDto override(PlaceDto place) {
            return overrides.getOrDefault(place.contentId(), place);
        }
    }

    /**
     * @param kto    관광공사 전국 한 벌
     * @param others 관광공사 밖의 다른 출처(인허가 · 두루누비) — 그대로 남는다
     * @param ours   우리 자산(놀이터 · 동네 길) — 겹치면 빠진다
     */
    public static Merged merge(List<PlaceDto> kto, List<PlaceDto> others, List<PlaceDto> ours) {
        Map<Long, List<PlaceDto>> grid = new HashMap<>();
        for (PlaceDto place : kto) {
            grid.computeIfAbsent(cellOf(place), k -> new ArrayList<>()).add(place);
        }
        for (PlaceDto place : others) {
            grid.computeIfAbsent(cellOf(place), k -> new ArrayList<>()).add(place);
        }

        Map<String, PlaceDto> overrides = new LinkedHashMap<>();
        List<PlaceDto> survivors = new ArrayList<>(ours.size());
        int dropped = 0;
        for (PlaceDto mine : ours) {
            PlaceDto winner = findOverlap(mine, grid);
            if (winner == null) {
                survivors.add(mine);
                continue;
            }
            dropped++;
            if (PlaceDto.SOURCE_PLAYGROUND.equals(mine.category())
                    && PlaceDto.SOURCE_KTO.equals(winner.source())) {
                overrides.putIfAbsent(winner.contentId(), transferPlayground(winner, mine));
            }
        }

        List<PlaceDto> mergedKto = new ArrayList<>(kto.size());
        for (PlaceDto place : kto) {
            mergedKto.add(overrides.getOrDefault(place.contentId(), place));
        }
        List<PlaceDto> layers = new ArrayList<>(others.size() + survivors.size());
        layers.addAll(others);
        layers.addAll(survivors);
        return new Merged(List.copyOf(mergedKto), List.copyOf(layers), Map.copyOf(overrides), dropped);
    }

    /** 200m 안에서 이름이 맞는 다른 출처 항목 중 가장 가까운 것. 없으면 {@code null}. */
    private static PlaceDto findOverlap(PlaceDto mine, Map<Long, List<PlaceDto>> grid) {
        String name = normalize(mine.title());
        long latIdx = index(mine.lat());
        long lngIdx = index(mine.lng());
        PlaceDto best = null;
        double bestDistance = Double.MAX_VALUE;
        for (long dLat = -1; dLat <= 1; dLat++) {
            for (long dLng = -1; dLng <= 1; dLng++) {
                List<PlaceDto> bucket = grid.get(key(latIdx + dLat, lngIdx + dLng));
                if (bucket == null) {
                    continue;
                }
                for (PlaceDto other : bucket) {
                    if (!SAME_PLACE_KINDS.contains(other.categoryKey())
                            || !sameName(name, normalize(other.title()))) {
                        continue;
                    }
                    double distance = GeoDistance.metersBetween(mine.lat(), mine.lng(), other.lat(), other.lng());
                    if (distance <= MAX_DISTANCE_M && distance < bestDistance) {
                        best = other;
                        bestDistance = distance;
                    }
                }
            }
        }
        return best;
    }

    /** 공백을 지운 이름이 같거나, 둘 다 두 글자 이상이고 한쪽이 다른 쪽을 포함한다. */
    static boolean sameName(String a, String b) {
        if (a.isEmpty() || b.isEmpty()) {
            return false;
        }
        if (a.equals(b)) {
            return true;
        }
        if (a.length() < MIN_NAME_LENGTH || b.length() < MIN_NAME_LENGTH) {
            return false;
        }
        return a.contains(b) || b.contains(a);
    }

    /** 공백 전부 제거 + 소문자. "반려견 놀이터" 와 "반려견놀이터" 가 같아진다. */
    static String normalize(String title) {
        if (title == null) {
            return "";
        }
        StringBuilder sb = new StringBuilder(title.length());
        for (int i = 0; i < title.length(); i++) {
            char c = title.charAt(i);
            if (!Character.isWhitespace(c)) {
                sb.append(c);
            }
        }
        return sb.toString().toLowerCase(Locale.ROOT);
    }

    /** 관광공사 항목에 놀이터를 옮겨 단 사본 — 사진 · 상세 열쇠(contentId)는 관광공사 것 그대로. */
    private static PlaceDto transferPlayground(PlaceDto winner, PlaceDto mine) {
        return new PlaceDto(winner.contentId(), winner.title(), winner.source(),
                PlaceDto.SOURCE_PLAYGROUND, null, winner.lat(), winner.lng(), winner.addr(),
                winner.tel() != null ? winner.tel() : mine.tel(), winner.image(), null, winner.summary());
    }

    private static long index(double degrees) {
        return (long) Math.floor(degrees / CELL_DEG);
    }

    private static long cellOf(PlaceDto place) {
        return key(index(place.lat()), index(place.lng()));
    }

    private static long key(long latIdx, long lngIdx) {
        // 경도 칸은 360 / 0.005 = 72,000 개뿐이라 백만 배로 벌리면 안 겹친다.
        return latIdx * 1_000_003L + lngIdx;
    }
}
