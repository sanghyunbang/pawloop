package com.heattrip.heat_trip_backend.docs;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import com.heattrip.heat_trip_backend.support.TestProjectPaths;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.yaml.snakeyaml.Yaml;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * {@code api-spec.md} 의 <b>구현 상태 마커</b>가 계약과 같은 말을 하는지 본다 — 이슈 #157.
 *
 * <h2>왜 필요한가</h2>
 * <p>#167 이 찾은 것은 {@code api-spec.md} §6 이 <b>계약에 없는 경로 열 군데</b>를 적고 그중
 * 다섯에 "✅ 구현" 을 붙여 둔 상태였다. 그대로 짜면 404 다. 그 뒤 §6(커뮤니티)과
 * §4(장소)에는 도메인별 스펙 테스트가 생겼지만 <b>나머지 아홉 절은 아무도 안 본다.</b>
 *
 * <h2>왜 문서 전체를 훑지 않나</h2>
 * <p>이슈는 {@code docs/**.md} 전부에서 {@code METHOD /api/...} 를 뽑아 계약과 대조하자고
 * 적었다. <b>실측하니 그 규칙은 문서 여덟에서 25건을 잡는데 참인 것이 0건이다.</b> 전부
 * (a) 부정 서술("…은 없다", "2026-09 이전에는"), (b) 취소선, (c) 계획 표기("재사용 예정",
 * "M4"), (d) 머메이드 노드 문자열, (e) 계약이 안 덮는 실재 경로({@code /api/explore/**} —
 * 레거시 셸의 것이고 #94 가 소유한다) 다.
 *
 * <p>그것을 거르려면 <b>한국어 산문을 읽어야</b> 하고, 그 휴리스틱이 틀리는 날 이 검사는
 * 거짓 빨간불로 사람을 지치게 한다. 대신 <b>구조적 표식</b>을 쓴다 — {@code api-spec.md} 가
 * 절 제목에 ✅·⬜ 를 다는 규약을 이미 갖고 있고, 그것이 정확히 "이 절이 무엇을 주장하는가"
 * 다. 산문을 안 읽고도 주장만 골라낼 수 있다.
 *
 * <h2>세 방향을 본다</h2>
 * <ul>
 *   <li><b>✅ 절의 경로는 계약에 있다.</b> #167 이 찾은 것이 이 방향이다.</li>
 *   <li><b>⬜ 절의 경로는 살아 있지 않다.</b> 계약에 없거나 {@code x-status: planned} 여야
 *       한다 — 계약이 앞서갈 때 문서만 조용히 낡는 것을 막는다.</li>
 *   <li><b>✅ 절이 {@code planned} 를 가리키지 않는다.</b> 계약이 "아직 핸들러가 없다" 고
 *       적은 것을 문서가 "구현" 이라 부르면, 앱이 그것을 짜고 404 를 받는다.</li>
 * </ul>
 *
 * <p>네트워크를 안 탄다. 저장소 안의 두 파일만 읽는다(#21).
 */
class ApiSpecStatusMarkersTest {

    /** {@code GET /api/community/posts?board=...} 꼴. 물음표·백틱·괄호 앞까지가 경로다. */
    private static final Pattern ENDPOINT = Pattern.compile(
            "\\b(GET|POST|PATCH|PUT|DELETE)\\s+(/[^\\s`?)\"']*)");

    private static Map<String, Boolean> declared;
    private static Map<String, String> claimed;
    private static Map<String, String> disclaimed;

    @BeforeAll
    static void read() {
        declared = declaredOperations();
        Map<String, Map<String, String>> sections = sectionsOf(readRepositoryFile("../docs/04-api/api-spec.md"));
        claimed = sections.get("✅");
        disclaimed = sections.get("⬜");
    }

    @Test
    @DisplayName("✅ 로 적은 절의 경로가 전부 계약에 있다 — 없으면 그대로 짠 앱이 404 를 받는다")
    void everyImplementedSectionPointsAtADeclaredOperation() {
        assertThat(claimed)
                .as("✅ 절에서 경로를 하나도 못 읽었다면 이 검사는 아무것도 지키지 않는다")
                .isNotEmpty();

        List<String> offenders = new ArrayList<>();
        claimed.forEach((operation, section) -> {
            if (!declared.containsKey(operation)) {
                offenders.add(operation + "   ← " + section);
            }
        });

        assertThat(offenders)
                .as("""
                        #167 이 찾은 것이 이 방향이다 — §6 이 계약에 없는 경로 열 군데를 적고 \
                        그중 다섯에 "✅ 구현" 을 붙여 뒀다. 그 뒤 §6·§4 만 검사가 생겼고 \
                        나머지 아홉 절은 아무도 안 봤다.""")
                .isEmpty();
    }

    @Test
    @DisplayName("⬜ 로 적은 절의 경로가 살아 있지 않다 — 계약이 앞서가면 문서만 낡는다")
    void everyUnimplementedSectionPointsAtNothingLive() {
        List<String> offenders = new ArrayList<>();
        disclaimed.forEach((operation, section) -> {
            Boolean planned = declared.get(operation);
            if (planned != null && !planned) {
                offenders.add(operation + "   ← " + section);
            }
        });

        assertThat(offenders)
                .as("""
                        ⬜ 는 두 가지를 뜻해 왔다 — "계약에 없다"(§6.4 가 그랬다)와 \
                        "계약엔 있는데 핸들러가 없다"(§3.4·§3.5 는 x-status: planned 를 \
                        괄호에 적는다). 둘 다 통과시키되 **살아 있는 오퍼레이션**은 막는다.""")
                .isEmpty();
    }

    @Test
    @DisplayName("✅ 절이 x-status: planned 를 가리키지 않는다 — 계약이 '아직 없다' 고 적은 것이다")
    void noImplementedSectionPointsAtAPlannedOperation() {
        List<String> offenders = new ArrayList<>();
        claimed.forEach((operation, section) -> {
            if (Boolean.TRUE.equals(declared.get(operation))) {
                offenders.add(operation + "   ← " + section);
            }
        });

        assertThat(offenders)
                .as("""
                        계약이 planned 라고 적은 것을 문서가 "구현" 이라 부르면, 앱이 그것을 \
                        짜고 404 를 받는다. 핸들러가 생긴 날 x-status 를 지우는 것과 문서에 \
                        ✅ 를 다는 것이 같이 일어나야 한다.""")
                .isEmpty();
    }

    // ─────────────────────────── 도구 ───────────────────────────

    /**
     * 계약이 선언한 오퍼레이션 → {@code x-status: planned} 인가.
     *
     * <p>{@code planned} 는 "계약에는 있는데 백엔드 핸들러가 없다" 는 뜻이다. 없는 것과
     * 다르므로 값으로 구별해 든다.
     */
    @SuppressWarnings("unchecked")
    private static Map<String, Boolean> declaredOperations() {
        Map<String, Object> spec = (Map<String, Object>) new Yaml()
                .load(readRepositoryFile("../docs/04-api/openapi.yaml"));
        Map<String, Object> paths = (Map<String, Object>) spec.get("paths");

        Map<String, Boolean> found = new LinkedHashMap<>();
        paths.forEach((path, item) -> ((Map<String, Object>) item).forEach((method, operation) -> {
            if (!METHODS.contains(method)) {
                return;
            }
            Object status = ((Map<String, Object>) operation).get("x-status");
            found.put(method.toUpperCase() + " " + path, "planned".equals(status));
        }));
        return found;
    }

    private static final Set<String> METHODS = Set.of("get", "post", "patch", "put", "delete");

    /**
     * {@code api-spec.md} 를 마커별로 나눈다.
     *
     * <p>절 제목의 ✅·⬜ 를 읽고, 그 아래 본문에서 오퍼레이션을 뽑는다. 마커가 {@code ###} 에
     * 없으면 위 {@code ##} 의 것을 물려받는다 — 도메인 전체에 한 번만 적은 절이 있다.
     *
     * <p><b>인용문({@code >})과 코드펜스는 건너뛴다.</b> 인용문에는 "2026-09 이전 이 절은
     * {@code DELETE /api/community/comments/{commentId}} 를 적었는데" 같은 <b>이력 서술</b>이
     * 들어간다 — 지금의 주장이 아니다. 코드펜스에는 요청 예시가 들어가는데 거기 적힌 경로는
     * 바로 위 절 제목이 이미 말한 것과 같다.
     */
    private static Map<String, Map<String, String>> sectionsOf(String markdown) {
        Map<String, String> claimedHere = new LinkedHashMap<>();
        Map<String, String> disclaimedHere = new LinkedHashMap<>();

        String sectionMarker = null;
        String marker = null;
        String heading = null;
        boolean inFence = false;

        for (String line : markdown.split("\\R")) {
            if (line.startsWith("```")) {
                inFence = !inFence;
                continue;
            }
            if (inFence) {
                continue;
            }
            if (line.startsWith("## ")) {
                sectionMarker = markerOf(line);
                marker = sectionMarker;
                heading = line.strip();
                continue;
            }
            if (line.startsWith("### ")) {
                heading = line.strip();
                String own = markerOf(line);
                marker = own != null ? own : sectionMarker;
                continue;
            }
            if (marker == null || line.stripLeading().startsWith(">")) {
                continue;
            }
            Matcher matcher = ENDPOINT.matcher(line);
            while (matcher.find()) {
                String operation = matcher.group(1) + " " + trimPunctuation(matcher.group(2));
                Map<String, String> target = "✅".equals(marker) ? claimedHere : disclaimedHere;
                target.putIfAbsent(operation, heading);
            }
        }
        return Map.of("✅", claimedHere, "⬜", disclaimedHere);
    }

    private static String markerOf(String heading) {
        if (heading.contains("✅")) {
            return "✅";
        }
        if (heading.contains("⬜")) {
            return "⬜";
        }
        // ⚪(post-MVP)·❌ 는 "계약에 있는지" 를 말하지 않는다 — 제품 범위 표기라 안 센다.
        return null;
    }

    /** 문장 끝의 마침표·쉼표가 경로에 붙어 오는 것을 뗀다. */
    private static String trimPunctuation(String path) {
        String trimmed = path;
        while (!trimmed.isEmpty() && ".,;:".indexOf(trimmed.charAt(trimmed.length() - 1)) >= 0) {
            trimmed = trimmed.substring(0, trimmed.length() - 1);
        }
        return trimmed;
    }

    private static String readRepositoryFile(String relativePath) {
        try {
            return Files.readString(
                    TestProjectPaths.requireFile(relativePath), StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException(relativePath + " 를 읽지 못했다", e);
        }
    }

    /** 쓰이지 않지만 남겨 둔다 — 마커 종류를 한눈에 보게 한다. */
    static final Set<String> KNOWN_MARKERS = new LinkedHashSet<>(List.of("✅", "⬜", "⚪", "❌", "🟡"));
}
