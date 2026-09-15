package com.heattrip.heat_trip_backend.security;

import com.fasterxml.jackson.databind.ObjectMapper;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.config.BeanDefinition;
import org.springframework.context.annotation.ClassPathScanningCandidateComponentProvider;
import org.springframework.core.type.filter.AnnotationTypeFilter;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestMethod;
import org.springframework.web.bind.annotation.RestController;

import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeSet;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * <b>상태를 바꾸는 경로는 전부 한도 표에 있어야 한다</b> — 이슈 #511.
 *
 * <h2>왜 이 검사가 필요한가</h2>
 * <p>표에 없는 경로는 한도가 0 이 아니라 <b>무한</b>이다 — 두 필터의 {@code resolveRule} 이
 * {@code null} 을 돌려주면 카운터를 건드리지 않고 그대로 통과시킨다. 그래서 "빠뜨렸다" 와
 * "일부러 안 걸었다" 가 코드에서 <b>구별되지 않는다.</b>
 *
 * <p>실제로 그 사고가 여러 번 있었다. {@code POST /auth/signup} 이 무제한이었고,
 * {@code POST /api/groups} 도, {@code POST /api/schedules} 도 그랬다. 매번 사람이 눈으로
 * 찾아냈다. 기존 검사({@code PublicPathsAreRateLimitedTest})는 {@code SecurityConfig} 의
 * <b>공개 경로만</b> 돌기 때문에, 인증이 걸린 쓰기 경로는 어떤 검사도 보지 않았다.
 *
 * <h2>재는 방법 — 규칙을 옮겨 적지 않는다</h2>
 * <p>컨트롤러의 매핑을 긁어 쓰기 경로를 모으고, <b>모든 버킷을 1 로 만든 필터</b>에 같은
 * 요청을 두 번 보낸다. 두 번째가 429 면 어떤 버킷엔가 걸린 것이다. 어느 버킷인지는 묻지
 * 않는다 — 이 검사가 묻는 것은 <b>"버킷이 있는가"</b> 뿐이다.
 *
 * <p>필터가 둘인 것이 요점이다. {@link ApiRateLimitFilter} 는 체인 맨 앞이라 IP 로 세고,
 * {@link ChatRateLimitFilter} 는 인증 뒤라 사용자로 센다. 채팅 전송·신고처럼 한쪽에만 있는
 * 경로가 있으므로 <b>둘 중 하나라도</b> 잡으면 덮인 것이다.
 *
 * <p>스프링을 안 띄운다(#21). 매핑은 {@code @RestController} 를 classpath 에서 훑어 읽는다.
 */
class WriteEndpointsAreRateLimitedTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final String ROOT = "com.heattrip.heat_trip_backend";

    /**
     * <b>일부러 안 거는 자리와 그 이유.</b>
     *
     * <p>여기 적는 것은 "나중에 하자" 가 아니라 <b>"안 거는 것이 맞다"</b> 여야 한다. 미루는
     * 것이라면 이유에 그 이슈 번호를 적는다 — 그래야 다음 사람이 이 목록을 읽고 판단할 수 있다.
     */
    private static final Map<String, String> UNMETERED_ON_PURPOSE = new LinkedHashMap<>();

    static {
        UNMETERED_ON_PURPOSE.put("DELETE /api/chat/messages/{messageId}",
                "내 메시지의 본문을 비우는 소프트 삭제다(#197). 두 번째부터는 아무것도 안 바뀌고"
                        + "(멱등) 행도 안 는다 — ApiRateLimitFilter 의 회수 절에 같은 판단이 적혀 있다.");
        UNMETERED_ON_PURPOSE.put("DELETE /api/chat/rooms/{roomId}/invites/{code}",
                "자기 방의 코드를 죽이는 것뿐이라 반복해도 새로 생기는 것이 없다. 유출 대응을"
                        + " 한도로 막으면 그게 더 나쁘다 — ApiRateLimitFilter 에 같은 문장이 있다.");
    }

    @Test
    @DisplayName("상태를 바꾸는 모든 경로가 한도 표에 있다 — 없으면 한도가 0 이 아니라 무한이다")
    void everyWriteEndpointIsMetered() throws Exception {
        List<String> unmetered = new ArrayList<>();

        for (String operation : writeOperations()) {
            if (UNMETERED_ON_PURPOSE.containsKey(operation)) {
                continue;
            }
            String[] parts = operation.split(" ", 2);
            if (!isMetered(parts[0], sampleOf(parts[1]))) {
                unmetered.add(operation);
            }
        }

        assertThat(unmetered)
                .as("""
                        표에 없는 경로는 한도가 0 이 아니라 **무한**이다. 성격이 같은 버킷에 \
                        등재하거나, 안 거는 것이 맞다면 UNMETERED_ON_PURPOSE 에 **이유와 함께** \
                        적어라 — 그래야 "빠뜨렸다" 와 "일부러" 가 구별된다.""")
                .isEmpty();
    }

    @Test
    @DisplayName("예외 목록의 모든 줄에 이유가 적혀 있다")
    void everyExceptionCarriesItsReason() {
        for (Map.Entry<String, String> entry : UNMETERED_ON_PURPOSE.entrySet()) {
            assertThat(entry.getValue().length())
                    .as("%s 를 왜 안 거는지 한 줄로 적는다", entry.getKey())
                    .isGreaterThan(20);
        }
    }

    @Test
    @DisplayName("예외 목록에 죽은 줄이 없다 — 경로가 사라지면 그 줄도 지운다")
    void noStaleExceptions() {
        List<String> all = writeOperations();

        for (String operation : UNMETERED_ON_PURPOSE.keySet()) {
            assertThat(all)
                    .as("%s 는 이제 없는 경로다 — 예외 목록에서 지워라", operation)
                    .contains(operation);
        }
    }

    @Test
    @DisplayName("쓰기 경로를 실제로 긁어 온다 — 목록이 비면 위 검사는 아무것도 안 지킨다")
    void theScanFindsRealOperations() {
        List<String> all = writeOperations();

        // 훑기가 조용히 0개를 돌려주면 위의 검사가 **빈 목록을 돌며** 초록이 된다.
        // 그 상태는 "전부 덮였다" 와 코드에서 구별되지 않으므로 여기서 먼저 잡는다.
        assertThat(all).hasSizeGreaterThan(40);
        assertThat(all).contains("DELETE /auth/me", "POST /api/blocks");
    }

    // ─────────────────────────── 지그 ───────────────────────────

    /** 두 필터 중 하나라도 이 요청을 세는가. */
    private static boolean isMetered(String method, String path) throws Exception {
        return second429(new ApiRateLimitFilter(allBucketsAtOne(), MAPPER), method, path)
                || second429(new ChatRateLimitFilter(allBucketsAtOne(), MAPPER), method, path);
    }

    private static boolean second429(jakarta.servlet.Filter filter, String method, String path)
            throws Exception {
        call(filter, method, path);
        return call(filter, method, path).getStatus() == 429;
    }

    private static MockHttpServletResponse call(jakarta.servlet.Filter filter,
                                                String method, String path) throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest(method, path);
        request.setRemoteAddr("203.0.113.77");
        MockHttpServletResponse response = new MockHttpServletResponse();
        filter.doFilter(request, response, new MockFilterChain());
        return response;
    }

    /** 모든 버킷을 1 로 — 어느 버킷에 걸리든 두 번째 요청이 429 가 된다. */
    private static RateLimitProperties allBucketsAtOne() throws Exception {
        RateLimitProperties props = new RateLimitProperties();
        props.setEnabled(true);
        for (Method setter : RateLimitProperties.class.getMethods()) {
            if (setter.getName().startsWith("set")
                    && setter.getParameterCount() == 1
                    && setter.getParameterTypes()[0] == int.class) {
                setter.invoke(props, 1);
            }
        }
        props.setWindowSeconds(60); // 위 루프가 창까지 1 로 만든다 — 되돌린다
        return props;
    }

    /** {@code {id}} 같은 자리를 실제로 부를 수 있는 값으로. */
    private static String sampleOf(String pattern) {
        return pattern.replaceAll("\\{[^}]+}", "1");
    }

    /** 우리 컨트롤러의 쓰기 매핑 전부를 {@code METHOD /path} 로 눕힌다. */
    private static List<String> writeOperations() {
        var scanner = new ClassPathScanningCandidateComponentProvider(false);
        scanner.addIncludeFilter(new AnnotationTypeFilter(RestController.class));

        var found = new TreeSet<String>();
        for (BeanDefinition definition : scanner.findCandidateComponents(ROOT)) {
            Class<?> controller;
            try {
                controller = Class.forName(definition.getBeanClassName());
            } catch (ClassNotFoundException e) {
                throw new AssertionError(e);
            }
            if (!isProductionClass(controller)) {
                continue; // 테스트 안의 탐침 컨트롤러는 배포되지 않는다
            }
            String base = basePathOf(controller);
            for (Method method : controller.getDeclaredMethods()) {
                for (String operation : operationsOf(method)) {
                    String[] parts = operation.split(" ", 2);
                    found.add(parts[0] + " " + join(base, parts[1]));
                }
            }
        }
        return new ArrayList<>(found);
    }

    /**
     * 배포되는 클래스인가 — 테스트 소스에도 {@code @RestController} 가 있다
     * ({@code GlobalExceptionHandlerStatusTest} 의 탐침). 그것까지 세면 이 검사가
     * <b>테스트 코드에 한도를 걸라고</b> 말하게 된다.
     */
    private static boolean isProductionClass(Class<?> type) {
        var source = type.getProtectionDomain().getCodeSource();
        if (source == null || source.getLocation() == null) {
            return true; // 알 수 없으면 세는 쪽으로 — 빠뜨리는 것보다 낫다
        }
        return !source.getLocation().toString().replace('\\', '/').contains("/classes/java/test");
    }

    private static String basePathOf(Class<?> controller) {
        RequestMapping mapping = controller.getAnnotation(RequestMapping.class);
        if (mapping == null) {
            return "";
        }
        String[] value = mapping.value().length > 0 ? mapping.value() : mapping.path();
        return value.length == 0 ? "" : value[0];
    }

    private static List<String> operationsOf(Method method) {
        List<String> found = new ArrayList<>();
        if (method.isAnnotationPresent(PostMapping.class)) {
            found.add("POST " + first(pathOf(method.getAnnotation(PostMapping.class).value(),
                    method.getAnnotation(PostMapping.class).path())));
        }
        if (method.isAnnotationPresent(PutMapping.class)) {
            found.add("PUT " + first(pathOf(method.getAnnotation(PutMapping.class).value(),
                    method.getAnnotation(PutMapping.class).path())));
        }
        if (method.isAnnotationPresent(PatchMapping.class)) {
            found.add("PATCH " + first(pathOf(method.getAnnotation(PatchMapping.class).value(),
                    method.getAnnotation(PatchMapping.class).path())));
        }
        if (method.isAnnotationPresent(DeleteMapping.class)) {
            found.add("DELETE " + first(pathOf(method.getAnnotation(DeleteMapping.class).value(),
                    method.getAnnotation(DeleteMapping.class).path())));
        }
        RequestMapping generic = method.getAnnotation(RequestMapping.class);
        if (generic != null) {
            for (RequestMethod verb : generic.method()) {
                if (verb != RequestMethod.GET && verb != RequestMethod.HEAD
                        && verb != RequestMethod.OPTIONS) {
                    found.add(verb.name() + " " + first(pathOf(generic.value(), generic.path())));
                }
            }
        }
        return found;
    }

    private static String[] pathOf(String[] value, String[] path) {
        return value.length > 0 ? value : path;
    }

    private static String first(String[] value) {
        return value.length == 0 ? "" : value[0];
    }

    private static String join(String base, String sub) {
        String joined = (base + sub).replace("//", "/");
        return joined.isEmpty() ? "/" : joined;
    }
}
