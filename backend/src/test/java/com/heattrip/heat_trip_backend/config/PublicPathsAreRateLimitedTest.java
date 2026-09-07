package com.heattrip.heat_trip_backend.config;

import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;


import com.heattrip.heat_trip_backend.security.ApiRateLimitFilter;
import com.heattrip.heat_trip_backend.security.RateLimitProperties;

import com.fasterxml.jackson.databind.ObjectMapper;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * <b>인증이 없는 경로에는 한도라도 있어야 한다</b> — 이슈 #232.
 *
 * <h2>무엇이 문제였나</h2>
 * <p>{@code SecurityConfig.PUBLIC_MATCHERS} 에 있는 경로는 <b>인증이라는 방어선이 없다.</b>
 * 남은 방어선이 레이트리밋 하나뿐인데, {@code ApiRateLimitFilter.resolveRule} 의 표에
 * <b>없으면 한도가 0 이 아니라 무한</b>이다({@code resolveRule} 이 {@code null} 을 주면
 * 필터가 그대로 통과시킨다).
 *
 * <p>그래서 {@code PUBLIC_MATCHERS} 에 한 줄을 더하면서 그쪽을 안 고치면 <b>인증도 한도도
 * 없는 경로</b>가 조용히 생긴다. 실제로 감정 여행 시절의 {@code /api/explore/**} 가 그 상태였다 —
 * 매핑 일곱 중 <b>다섯</b>이 아무 버킷에도 안 걸려 있었다(그 컨트롤러는 #94 로 지웠다).
 *
 * <h2>어떻게 재는가</h2>
 * <p><b>필터를 실제로 돌린다.</b> 한도를 1 로 두고 같은 경로를 두 번 부르면 버킷에 걸린
 * 경로만 429 가 된다. {@code resolveRule} 은 private 이고, 규칙 문자열을 손으로 옮겨 적으면
 * 사본과 문서를 대조하는 셈이라 둘이 나란히 낡는다.
 *
 * <p>경로도 손으로 안 적는다 — 공개 매처마다 대표 요청을 {@code sampleFor} 가 정하고,
 * 매처가 늘면 그 switch 가 빠진 것을 잡는다.
 */
class PublicPathsAreRateLimitedTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    /**
     * 한도가 없어도 되는 공개 경로 — <b>이유를 여기 적는다.</b>
     *
     * <p>목록에 넣는 것은 "지금 안 해도 된다" 가 아니라 <b>"재는 것이 뜻이 없다"</b> 여야
     * 한다. 그렇지 않으면 이 검사는 예외 목록을 늘리는 것으로 언제든 통과시킬 수 있다.
     */
    private static final Map<String, String> UNMETERED_ON_PURPOSE = new LinkedHashMap<>(Map.of(
            "/", "정적 루트. 핸들러가 없어 DispatcherServlet 이 바로 404 를 낸다",
            "/error", "오류 포워딩 자리. 여기에 한도를 걸면 진짜 오류가 429 로 덮인다",
            "/actuator/health/**", "헬스체크. 로드밸런서가 초당 부르는 경로라 한도가 곧 장애다",
            "/actuator/info", "같은 이유",
            "/actuator/prometheus", "스크레이퍼가 주기적으로 부른다. 한도는 곧 지표 구멍이다",
            "/v3/api-docs/**", "문서. app.security.docs-public 이 켜졌을 때만 열린다",
            "/swagger-ui.html", "같은 이유",
            "/swagger-ui/**", "같은 이유"));

    // ─────────────────── 공개 경로 전체 ───────────────────

    @Test
    @DisplayName("PUBLIC_MATCHERS 의 모든 경로가 한도를 갖는다 — 면제는 이유와 함께 적는다")
    void everyPublicMatcherIsMeteredOrExemptWithAReason() throws Exception {
        List<String> unmetered = new ArrayList<>();

        for (String pattern : allPublicPatterns()) {
            if (UNMETERED_ON_PURPOSE.containsKey(pattern)) {
                continue;
            }
            Sample sample = sampleFor(pattern);
            if (secondCallStatus(sample.method(), sample.path()) != 429) {
                unmetered.add(pattern + " → " + sample.method() + " " + sample.path());
            }
        }

        assertThat(unmetered)
                .as("""
                        인증이 없는 경로에는 한도라도 있어야 한다. 면제하려면 \
                        UNMETERED_ON_PURPOSE 에 **이유와 함께** 적어라 — 그러지 않으면 이 \
                        검사는 목록을 늘리는 것으로 언제든 통과시킬 수 있다 (📌 #86 원칙 4).""")
                .isEmpty();
    }

    @Test
    @DisplayName("면제 목록에 죽은 항목이 없다 — PUBLIC_MATCHERS 에서 빠진 경로가 남아 있으면 안 된다")
    void theExemptionListHasNoDeadEntries() {
        Set<String> declared = Set.copyOf(allPublicPatterns());

        assertThat(UNMETERED_ON_PURPOSE.keySet())
                .as("""
                        공개 목록에서 빠진 경로가 면제 목록에 남아 있으면, 그 이름이 다시 \
                        공개될 때 아무도 안 보고 통과한다.""")
                .allSatisfy(pattern -> assertThat(declared).contains(pattern));
    }

    // ─────────────────── 도구 ───────────────────

    /**
     * 지금 공개되는 경로 전부.
     *
     * <p>{@code DOCS_MATCHERS} 를 함께 읽는 이유는 그것이 <b>조건부로 공개되기</b> 때문이다 —
     * {@code app.security.docs-public} 이 켜진 환경에서는 그 셋도 인증이 없다.
     */
    private static List<String> allPublicPatterns() {
        List<String> all = new ArrayList<>(SecurityConfig.PUBLIC_MATCHERS);
        all.addAll(SecurityConfig.DOCS_MATCHERS);
        return all;
    }

    /** 패턴 하나를 대표하는 요청. */
    private record Sample(String method, String path) { }

    /**
     * 공개 패턴 → 대표 요청.
     *
     * <p>손으로 적는 유일한 자리다. 패턴은 여덟이고 좀처럼 안 바뀌며, <b>안 적으면 새 패턴이
     * 조용히 검사 밖으로 나간다</b> — 그래서 모르는 패턴은 예외를 던진다.
     */
    private static Sample sampleFor(String pattern) {
        return switch (pattern) {
            case "/oauth2/**" -> new Sample("GET", "/oauth2/authorization/kakao");
            // 소셜 공급자가 돌려보내는 자리. 여기가 무제한이면 코드 교환을 무한히 시도할 수 있다.
            case "/login/**" -> new Sample("GET", "/login/oauth2/code/kakao");
            case "/auth/signup" -> new Sample("POST", "/auth/signup");
            case "/auth/login" -> new Sample("POST", "/auth/login");
            case "/auth/oauth/**" -> new Sample("POST", "/auth/oauth/kakao/callback");
            case "/auth/token/refresh" -> new Sample("POST", "/auth/token/refresh");
            case "/api/places/nearby" -> new Sample("GET", "/api/places/nearby");
            case "/api/places/*" -> new Sample("GET", "/api/places/126508");
            case "/api/places/trails/*/route" -> new Sample("GET", "/api/places/trails/T_ROUTE_1/route");
            // 산책 안전 지수(#336). 인증이 없으므로 IP 한도가 유일한 문지기다.
            // 쿼리(?nx=&ny=)는 붙이지 않는다 — MockHttpServletRequest 는 그것까지 requestURI 로
            // 삼아서 규칙에 안 걸리고, "한도가 없다" 는 엉뚱한 실패가 된다.
            case "/api/walk-safety/now" -> new Sample("GET", "/api/walk-safety/now");
            default -> throw new AssertionError(
                    "공개 패턴 '" + pattern + "' 의 대표 요청이 없다. "
                            + "여기에 더하거나 UNMETERED_ON_PURPOSE 에 이유와 함께 적어라.");
        };
    }

    /** 정규식이 섞인 매핑 경로를 실제로 부를 수 있는 경로로. */
    private static String sampleOf(String mappingPath) {
        return mappingPath
                .replace("{id:\\d+}", "12")
                .replace("{contentId:\\d+}", "12");
    }

    /**
     * 한도 1 짜리 필터로 같은 경로를 두 번 부른 뒤의 상태코드.
     *
     * <p>버킷에 걸린 경로면 429, 아니면 200 이다. <b>규칙을 손으로 옮겨 적지 않으려고</b>
     * 필터를 실제로 돌린다.
     */
    private static int secondCallStatus(String method, String path) throws Exception {
        ApiRateLimitFilter filter = new ApiRateLimitFilter(allBucketsAtOne(), MAPPER);
        call(filter, method, path);
        return call(filter, method, path).getStatus();
    }

    /**
     * 모든 버킷을 1 로.
     *
     * <p>어느 버킷에 걸리든 두 번째 요청이 429 가 되게 한다 — 이 검사가 묻는 것은
     * "어떤 버킷인가" 가 아니라 <b>"버킷이 있는가"</b> 다.
     */
    private static RateLimitProperties allBucketsAtOne() throws Exception {
        RateLimitProperties props = new RateLimitProperties();
        props.setEnabled(true);
        props.setWindowSeconds(60);
        for (Method setter : RateLimitProperties.class.getMethods()) {
            if (setter.getName().startsWith("set")
                    && setter.getParameterCount() == 1
                    && setter.getParameterTypes()[0] == int.class) {
                setter.invoke(props, 1);
            }
        }
        props.setWindowSeconds(60); // 위 루프가 이것도 1 로 만든다 — 창은 되돌린다
        return props;
    }

    private static MockHttpServletResponse call(ApiRateLimitFilter filter,
                                                String method, String path) throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest(method, path);
        request.setRemoteAddr("203.0.113.77");
        MockHttpServletResponse response = new MockHttpServletResponse();
        filter.doFilter(request, response, new MockFilterChain());
        return response;
    }

    /** 컨트롤러의 매핑을 {@code METHOD /path} 로 눕힌다. */
    private static List<String> operationsOf(Class<?> controller) {
        String base = controller.isAnnotationPresent(RequestMapping.class)
                ? controller.getAnnotation(RequestMapping.class).value()[0]
                : "";
        List<String> found = new ArrayList<>();
        for (Method method : controller.getDeclaredMethods()) {
            if (method.isAnnotationPresent(GetMapping.class)) {
                found.add("GET " + base + first(method.getAnnotation(GetMapping.class).value()));
            }
            if (method.isAnnotationPresent(PostMapping.class)) {
                found.add("POST " + base + first(method.getAnnotation(PostMapping.class).value()));
            }
        }
        return found;
    }

    private static String first(String[] value) {
        return value.length == 0 ? "" : value[0];
    }
}
