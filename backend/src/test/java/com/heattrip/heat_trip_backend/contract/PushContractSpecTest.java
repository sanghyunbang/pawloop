package com.heattrip.heat_trip_backend.contract;

import com.heattrip.heat_trip_backend.chatweb.ChatMuteResponse;
import com.heattrip.heat_trip_backend.push.controller.PushController;
import com.heattrip.heat_trip_backend.push.dto.PushSettingsResponse;
import com.heattrip.heat_trip_backend.push.dto.PushTokenRequest;
import com.heattrip.heat_trip_backend.push.entity.DeviceToken;
import com.heattrip.heat_trip_backend.support.TestProjectPaths;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.yaml.snakeyaml.Yaml;

import java.io.IOException;
import java.lang.reflect.Method;
import java.lang.reflect.RecordComponent;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Push 계약이 <b>도는 코드</b>와 같은 것을 말하는지 본다 — 이슈 #83.
 *
 * <ul>
 *   <li><b>경로</b> — 계약의 {@code /api/push/tokens}(PUT) · {@code /api/push/settings}(GET·PUT)와
 *       컨트롤러의 매핑이 같다. 방 음소거는 {@code /api/chat/rooms/{roomId}/mute}(PUT)다.</li>
 *   <li><b>platform enum</b> — 계약의 둘과 서버의 {@code @Pattern} 이 같은 집합이다. 갈리면 앱이 보낸
 *       값을 서버가 400 으로 거절한다.</li>
 *   <li><b>응답 필드</b> — {@code PushSettings}·{@code RoomMute} 의 프로퍼티가 응답 레코드의
 *       컴포넌트와 같다.</li>
 * </ul>
 *
 * <p>스프링 컨텍스트를 띄우지 않는다(#21).
 */
class PushContractSpecTest {

    private static Map<String, Object> spec;

    @BeforeAll
    @SuppressWarnings("unchecked")
    static void loadContract() throws IOException {
        String yaml = Files.readString(
                TestProjectPaths.requireFile("../docs/04-api/openapi.yaml"), StandardCharsets.UTF_8);
        spec = new Yaml().load(yaml);
    }

    @Test
    @DisplayName("계약의 /api/push/tokens 는 PUT 하나, /api/push/settings 는 GET·PUT 이고 컨트롤러도 그 셋뿐이다")
    void pathsMatchTheController() {
        assertThat(operations("/api/push/tokens")).containsExactly("put");
        assertThat(operations("/api/push/settings")).containsExactlyInAnyOrder("get", "put");
        assertThat(PushController.class.getAnnotation(RequestMapping.class).value()).containsExactly("/api/push");

        Set<String> mapped = new LinkedHashSet<>();
        for (Method m : PushController.class.getDeclaredMethods()) {
            if (m.isAnnotationPresent(GetMapping.class)) {
                mapped.add("GET " + m.getAnnotation(GetMapping.class).value()[0]);
            }
            if (m.isAnnotationPresent(PutMapping.class)) {
                mapped.add("PUT " + m.getAnnotation(PutMapping.class).value()[0]);
            }
        }
        assertThat(mapped).containsExactlyInAnyOrder("PUT /tokens", "GET /settings", "PUT /settings");
    }

    @Test
    @DisplayName("방 음소거는 PUT /api/chat/rooms/{roomId}/mute 이고 RoomMute 는 응답 레코드와 같은 두 필드다")
    void muteEndpointIsDeclared() {
        assertThat(operations("/api/chat/rooms/{roomId}/mute")).containsExactly("put");
        assertThat(propertyNames("RoomMute")).containsExactlyInAnyOrderElementsOf(componentNames(ChatMuteResponse.class));
        assertThat(required("RoomMute")).containsExactlyInAnyOrder("roomId", "muted");
        assertThat(required("RoomMuteInput")).containsExactly("muted");
    }

    @Test
    @DisplayName("platform enum 이 계약과 서버 @Pattern 에서 같은 집합이다 — android · ios")
    @SuppressWarnings("unchecked")
    void platformEnumMatchesTheValidationPattern() {
        Map<String, Object> platform = (Map<String, Object>) properties("PushTokenInput").get("platform");
        assertThat((List<String>) platform.get("enum")).containsExactlyInAnyOrder("android", "ios");
        assertThat(Arrays.asList(PushTokenRequest.PLATFORM_PATTERN.split("\\|")))
                .containsExactlyInAnyOrderElementsOf((List<String>) platform.get("enum"));
    }

    @Test
    @DisplayName("PushTokenInput 은 token·platform 둘 다 필수이고 token 의 상한이 엔티티와 같다")
    @SuppressWarnings("unchecked")
    void tokenInputMatchesTheEntity() {
        assertThat(required("PushTokenInput")).containsExactlyInAnyOrder("token", "platform");
        Map<String, Object> token = (Map<String, Object>) properties("PushTokenInput").get("token");
        assertThat(token.get("maxLength")).isEqualTo(DeviceToken.TOKEN_MAX_LENGTH);
    }

    @Test
    @DisplayName("PushSettings 의 프로퍼티가 PushSettingsResponse 의 필드와 같고 전부 required 다")
    void settingsSchemaMatchesTheRecord() {
        assertThat(propertyNames("PushSettings"))
                .containsExactlyInAnyOrderElementsOf(componentNames(PushSettingsResponse.class));
        assertThat(required("PushSettings")).containsExactlyInAnyOrderElementsOf(propertyNames("PushSettings"));
        assertThat(required("PushSettingsInput")).containsExactly("enabled");
    }

    @Test
    @DisplayName("쓰기 셋은 401 과 429 를 선언한다 — group-write 버킷이다")
    void writesDeclareRateLimiting() {
        for (String[] op : new String[][] {
                {"/api/push/tokens", "put"}, {"/api/push/settings", "put"}, {"/api/chat/rooms/{roomId}/mute", "put"}}) {
            assertThat(statusCodes(op[0], op[1]))
                    .as("%s %s", op[1].toUpperCase(), op[0])
                    .contains("401", "429");
        }
        assertThat(statusCodes("/api/push/settings", "get")).contains("401").doesNotContain("429");
    }

    // ─────────────────────────── 계약 읽기 ───────────────────────────

    @SuppressWarnings("unchecked")
    private static List<String> operations(String path) {
        Map<String, Object> paths = (Map<String, Object>) spec.get("paths");
        Map<String, Object> item = (Map<String, Object>) paths.get(path);
        assertThat(item).as("계약에 %s 가 없다", path).isNotNull();
        List<String> out = new ArrayList<>();
        for (String key : item.keySet()) {
            if (!"parameters".equals(key)) {
                out.add(key);
            }
        }
        return out;
    }

    @SuppressWarnings("unchecked")
    private static Set<String> statusCodes(String path, String method) {
        Map<String, Object> paths = (Map<String, Object>) spec.get("paths");
        Map<String, Object> op = (Map<String, Object>) ((Map<String, Object>) paths.get(path)).get(method);
        return ((Map<String, Object>) op.get("responses")).keySet();
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> schema(String name) {
        Map<String, Object> components = (Map<String, Object>) spec.get("components");
        Map<String, Object> schemas = (Map<String, Object>) components.get("schemas");
        Map<String, Object> found = (Map<String, Object>) schemas.get(name);
        assertThat(found).as("계약에 스키마 %s 가 없다", name).isNotNull();
        return found;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> properties(String schema) {
        return (Map<String, Object>) schema(schema).get("properties");
    }

    private static Set<String> propertyNames(String schema) {
        return properties(schema).keySet();
    }

    @SuppressWarnings("unchecked")
    private static List<String> required(String schema) {
        List<String> required = (List<String>) schema(schema).get("required");
        return required == null ? List.of() : required;
    }

    private static List<String> componentNames(Class<? extends Record> record) {
        return Arrays.stream(record.getRecordComponents()).map(RecordComponent::getName).toList();
    }
}
