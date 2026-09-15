package com.heattrip.heat_trip_backend.contract;

import com.heattrip.heat_trip_backend.chatweb.ChatMessagePageResponse;
import com.heattrip.heat_trip_backend.chatweb.ChatMessageResponse;
import com.heattrip.heat_trip_backend.chatweb.ChatRoomController;
import com.heattrip.heat_trip_backend.chatweb.ChatRoomResponse;
import com.heattrip.heat_trip_backend.support.TestProjectPaths;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.yaml.snakeyaml.Yaml;

import java.io.IOException;
import java.lang.reflect.Method;
import java.lang.reflect.RecordComponent;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 채팅 계약이 <b>실제로 도는 코드</b>와 같은 것을 말하는지 본다 — 이슈 #79.
 *
 * <h2>이 이슈가 계약에서 고친 것</h2>
 * <p>네 경로는 계약에 <b>선언만</b> 되어 있었고 구현이 없었다. 선언만 있는 동안 실제와 어긋난
 * 것 넷을 함께 고쳤다.
 * <ul>
 *   <li><b>전송에 {@code 200} 이 없었다.</b> 본문은 "같은 키가 다시 오면 처음 배정한
 *       {@code roomSeq} 를 그대로 돌려줍니다" 라고 적어 놓고 응답 목록에는 201 만 있었다 —
 *       앱은 응답 코드 목록을 보고 분기를 만든다.</li>
 *   <li><b>{@code clientMsgId} 가 필수</b>였다. 실제로는 없으면 멱등을 요구하지 않는 전송이고,
 *       필수로 두면 "한 번만 보낼 것" 에도 앱이 키를 지어내야 한다.</li>
 *   <li><b>{@code beforeSeq} 가 "내림차순" 이었다.</b> 방향에 따라 순서가 갈리면 클라이언트가
 *       어느 파라미터를 보냈는지에 따라 정렬을 달리해야 한다. 서버가 한 번 뒤집는다.</li>
 *   <li><b>조회·전송이 {@code 429} 를 선언</b>하고 있었다. 네 경로는 rate limit 표에 없다 —
 *       즉 한도가 0 이 아니라 무한이다(#80 이 소유). 계약이 429 를 선언하면 앱은 있지도 않은
 *       한도를 다루는 코드를 짠다.</li>
 * </ul>
 *
 * <h2>경로와 필드를 손으로 적지 않는다</h2>
 * <p>경로는 컨트롤러의 애너테이션에서, 응답 필드는 레코드 컴포넌트에서 읽는다. 손으로 적으면
 * 코드가 아니라 <b>사본과 문서</b>를 대조하게 되어 둘이 나란히 낡은 채 초록불이 된다
 * ({@code CareContractSpecTest} 가 같은 이유로 그렇게 한다).
 *
 * <p>스프링 컨텍스트를 띄우지 않는다. 문서를 읽고 클래스를 리플렉션으로 볼 뿐이다(#21).
 */
class ChatContractSpecTest {

    private static Map<String, Object> spec;

    private static final String MESSAGES = "/api/chat/rooms/{roomId}/messages";
    private static final String READ = "/api/chat/rooms/{roomId}/read";

    @SuppressWarnings("unchecked")
    @BeforeAll
    static void loadContract() throws IOException {
        // 파일이 없으면 requireFile 이 여기서 던진다. skip 이 아니다 — 못 읽고 통과하면
        // 이 테스트는 아무것도 지키지 않으면서 초록불만 낸다.
        String raw = Files.readString(
                TestProjectPaths.requireFile("../docs/04-api/openapi.yaml"), StandardCharsets.UTF_8);
        spec = (Map<String, Object>) new Yaml().load(raw);
    }

    // ─────────────────── A. 코드 ↔ 계약 ───────────────────

    @Test
    @DisplayName("컨트롤러의 여덟 매핑(#79 넷 + #197 삭제 + #83 음소거 + #452 반응 둘)이 계약에 그대로 등재돼 있다 — 경로 목록은 컨트롤러에서 읽는다")
    void everyEndpointThisIssueOpened_isDeclaredInTheContract() {
        List<String> implemented = operationsOf(ChatRoomController.class);

        assertThat(implemented)
                .as("컨트롤러에서 매핑을 하나도 못 읽었다면 이 검사는 아무것도 지키지 않는다")
                .hasSize(8);
        assertThat(declaredOperations())
                .as("""
                        계약에 없는 경로는 앱이 존재를 모른다 — design-first 라 앱은 이 파일을 보고 만든다.
                        경로 변수 이름까지 같아야 한다: 계약이 {roomId} 인데 코드가 {id} 면 생성된 \
                        클라이언트의 시그니처가 틀린다.""")
                .containsAll(implemented);
    }

    // ─────────────────── B. 응답 모양 ───────────────────

    @Test
    @DisplayName("ChatMessagePage 의 속성 집합이 ChatMessagePageResponse 의 필드 집합과 정확히 같다")
    void messagePageSchema_matchesTheResponseRecord() {
        assertThat(propertyNames("ChatMessagePage"))
                .as("""
                        공용 Page(nextCursor)를 쓰지 않는다 — 커서가 roomSeq 라 다음 커서는 \
                        클라이언트가 이미 들고 있고, 정작 스스로 알 수 없는 것은 방의 lastSeq 다.""")
                .containsExactlyInAnyOrderElementsOf(componentNames(ChatMessagePageResponse.class));
    }

    @Test
    @DisplayName("ChatMessage 스키마가 ChatMessageResponse 의 필드를 전부 담는다 — clientMsgId 는 없다")
    void messageSchema_carriesEveryFieldWeActuallySend() {
        assertThat(propertyNames("ChatMessage"))
                .containsAll(componentNames(ChatMessageResponse.class))
                .as("멱등키는 클라이언트가 만든 값이라 돌려줄 이유가 없고, 실으면 같은 방의 "
                        + "다른 사람에게 남의 키가 보인다")
                .doesNotContain("clientMsgId");
    }

    @Test
    @DisplayName("ChatRoom 스키마가 ChatRoomResponse 의 필드를 전부 담는다")
    void roomSchema_carriesEveryFieldWeActuallySend() {
        assertThat(propertyNames("ChatRoom"))
                .as("""
                        #75 가 비워 뒀던 lastReadSeq·unread·myRole·lastMessage 를 #79 가 채운다. \
                        계약과 응답 DTO 가 갈리면 앱이 없는 필드를 읽거나 있는 필드를 모른다.""")
                .containsAll(componentNames(ChatRoomResponse.class));
    }

    // ─────────────────── C. 멱등 · 워터마크 · ETag ───────────────────

    @Test
    @DisplayName("전송은 201 과 200 을 함께 선언한다 — 재전송은 409 가 아니라 200 이다")
    void sendingDeclaresBothCreatedAndTheIdempotentOk() {
        assertThat(statusCodesOf(MESSAGES, "post"))
                .as("""
                        재시도한 클라이언트 입장에서 그 요청은 성공했고, 실제로 그 말은 방에 들어가 \
                        있다. 409 를 주면 앱은 실패 화면을 띄우면서 정작 메시지는 보이는 상태가 된다.""")
                .contains("201", "200")
                .doesNotContain("409");
    }

    @Test
    @DisplayName("전송 본문에 필수가 없다 — clientMsgId 는 멱등이 선택이라, body 는 사진 메시지(#452)의 캡션이라")
    void nothingInTheSendBodyIsRequired() {
        assertThat(requiredFieldsOfRequestBody(MESSAGES, "post"))
                .as("""
                        UNIQUE 는 NULL 을 겹침으로 보지 않는다. 필수로 두면 '한 번만 보낼 것' 에도 \
                        앱이 키를 지어내야 하고, 그렇게 지어낸 키는 재시도에서 같은 값이 아니다. \
                        body 는 사진 메시지가 생기면서 빠졌다 — 글자 메시지의 빈 본문은 서버가 400 으로 막는다.""")
                .isEmpty();
    }

    @Test
    @SuppressWarnings("unchecked")
    @DisplayName("사진 메시지(#452): 요청의 mediaId 는 선택이고, ChatMessage.media 는 PostMedia 아니면 null 이다")
    void photoMessageIsInTheContract() {
        assertThat(requestBodyProperties(MESSAGES, "post")).containsKeys("mediaId", "contentType", "body");
        Map<String, Object> properties = (Map<String, Object>) schema("ChatMessage").get("properties");
        Map<String, Object> media = (Map<String, Object>) properties.get("media");
        assertThat(media).as("글의 PostMedia 와 같은 모양이라 앱이 같은 파서를 쓴다").isNotNull();
        List<Map<String, Object>> oneOf = (List<Map<String, Object>>) media.get("oneOf");
        assertThat(oneOf).extracting(option -> option.containsKey("$ref") ? option.get("$ref") : option.get("type"))
                .containsExactlyInAnyOrder("#/components/schemas/PostMedia", "null");
    }

    @Test
    @DisplayName("메시지 조회는 304 를 선언하고 ETag 헤더를 문서화한다")
    void pollingDeclaresNotModified() {
        assertThat(statusCodesOf(MESSAGES, "get"))
                .as("ShallowEtagHeaderFilter 를 쓰지 않는다 — chat_room 한 행만 읽고 끝낸다")
                .contains("304");
        assertThat(responseHeaderNames(MESSAGES, "get", "200"))
                .as("앱이 되보낼 값이 무엇인지 계약이 말해야 한다")
                .contains("ETag");
        assertThat(parameterRefsOf(MESSAGES, "get"))
                .as("If-None-Match 를 선언하지 않으면 앱은 304 를 받을 방법을 모른다")
                .contains("#/components/parameters/IfNoneMatch");
    }

    @Test
    @DisplayName("limit 의 기본값은 50 이고 상한은 100 이다 — 공용 Limit 과 다른 파라미터다")
    void chatUsesItsOwnPageSize() {
        Map<String, Object> schema = parameterSchema("ChatLimit");

        assertThat(schema.get("default"))
                .as("채팅 첫 진입은 최신 50건이다(이슈 #79). 공용 Limit 의 기본값 20 과 다르다")
                .isEqualTo(50);
        assertThat(schema.get("maximum"))
                .as("상한이 없으면 limit=100000 이 방 전체를 한 장에 담는다")
                .isEqualTo(100);
    }

    @Test
    @DisplayName("읽음 응답이 lastReadSeq 와 unread 를 함께 준다 — 보낸 값이 아니라 쓰인 값이다")
    void readAnswersWithWhatWasActuallyWritten() {
        assertThat(responseProperties(READ, "post", "200").keySet())
                .as("""
                        GREATEST 로 무시됐는지 LEAST 로 잘렸는지 앱이 알아야 낙관적으로 그린 뱃지를 \
                        되맞출 수 있다.""")
                .containsExactlyInAnyOrder("lastReadSeq", "unread");
    }

    // ─────────────────── D. 한도 표 (📌 #86 원칙 4) ───────────────────

    @Test
    @DisplayName("표 밖의 일곱 경로는 429 를 선언하지 않는다 — 음소거(#83)만 group-write 라 예외다")
    void noneOfTheFourDeclaresRateLimiting() {
        for (String operation : operationsOf(ChatRoomController.class)) {
            if (operation.endsWith("/mute")) {
                // PUT .../mute 는 #83 이 group-write 버킷에 넣었다 — 계약도 429 를 선언한다.
                // PushContractSpecTest.writesDeclareRateLimiting 이 그쪽을 잰다.
                continue;
            }
            String[] parts = operation.split(" ", 2);
            assertThat(statusCodesOf(parts[1], parts[0].toLowerCase()))
                    .as("""
                            %s 는 ApiRateLimitFilter.resolveRule 의 표에 없다 — 즉 한도가 0 이 \
                            아니라 무한이다. 계약이 429 를 선언하면 앱은 있지도 않은 한도를 다루는 \
                            코드를 짠다. 버킷은 #80 이 소유하고, 그때 이 단언을 뒤집는다.""",
                            operation)
                    .doesNotContain("429");
        }
    }

    @Test
    @DisplayName("방 id 를 받는 셋은 403 을 선언하고, 방 목록은 선언하지 않는다")
    void onlyTheRoomScopedPathsDeclareForbidden() {
        for (String method : List.of("get", "post")) {
            assertThat(statusCodesOf(MESSAGES, method))
                    .as("%s %s — 남의 방도 없는 방도 같은 403 이다(완료 조건 5)", method, MESSAGES)
                    .contains("403", "401");
        }
        assertThat(statusCodesOf(READ, "post")).contains("403", "401");

        assertThat(statusCodesOf("/api/chat/rooms", "get"))
                .as("""
                        방 목록은 roomId 를 받지 않으므로 403 을 낼 대상이 없다. 답의 범위 자체가 \
                        내 멤버십이라 남의 방이 섞여 들어올 문이 없다.""")
                .containsExactlyInAnyOrder("200", "401");
    }

    // ─────────────────────────── 지그 ───────────────────────────

    @SuppressWarnings("unchecked")
    private static Map<String, Object> paths() {
        return (Map<String, Object>) spec.get("paths");
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> componentsOf(String kind) {
        Map<String, Object> components = (Map<String, Object>) spec.get("components");
        return (Map<String, Object>) components.get(kind);
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> schema(String name) {
        Map<String, Object> found = (Map<String, Object>) componentsOf("schemas").get(name);
        assertThat(found).as("계약에 %s 스키마가 없다", name).isNotNull();
        return found;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> parameterSchema(String parameterName) {
        Map<String, Object> parameter =
                (Map<String, Object>) componentsOf("parameters").get(parameterName);
        assertThat(parameter).as("계약에 %s 파라미터가 없다", parameterName).isNotNull();
        return (Map<String, Object>) parameter.get("schema");
    }

    @SuppressWarnings("unchecked")
    private static Set<String> propertyNames(String schemaName) {
        return new LinkedHashSet<>(
                ((Map<String, Object>) schema(schemaName).get("properties")).keySet());
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> operation(String path, String method) {
        Map<String, Object> byMethod = (Map<String, Object>) paths().get(path);
        assertThat(byMethod).as("계약에 %s 경로가 없다", path).isNotNull();
        Map<String, Object> found = (Map<String, Object>) byMethod.get(method);
        assertThat(found).as("계약에 %s %s 가 없다", method, path).isNotNull();
        return found;
    }

    @SuppressWarnings("unchecked")
    private static Set<String> statusCodesOf(String path, String method) {
        return ((Map<String, Object>) operation(path, method).get("responses")).keySet();
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> response(String path, String method, String status) {
        Map<String, Object> responses =
                (Map<String, Object>) operation(path, method).get("responses");
        Map<String, Object> found = (Map<String, Object>) responses.get(status);
        assertThat(found).as("계약의 %s %s 에 %s 응답이 없다", method, path, status).isNotNull();
        return found;
    }

    @SuppressWarnings("unchecked")
    private static Set<String> responseHeaderNames(String path, String method, String status) {
        Map<String, Object> headers =
                (Map<String, Object>) response(path, method, status).get("headers");
        return headers == null ? Set.of() : headers.keySet();
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> responseProperties(String path, String method,
                                                          String status) {
        Map<String, Object> content =
                (Map<String, Object>) response(path, method, status).get("content");
        Map<String, Object> json = (Map<String, Object>) content.get("application/json");
        Map<String, Object> schema = (Map<String, Object>) json.get("schema");
        return (Map<String, Object>) schema.get("properties");
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> requestBodyProperties(String path, String method) {
        Map<String, Object> requestBody =
                (Map<String, Object>) operation(path, method).get("requestBody");
        Map<String, Object> content = (Map<String, Object>) requestBody.get("content");
        Map<String, Object> json = (Map<String, Object>) content.get("application/json");
        Map<String, Object> schema = (Map<String, Object>) json.get("schema");
        return (Map<String, Object>) schema.get("properties");
    }

    @SuppressWarnings("unchecked")
    private static List<String> requiredFieldsOfRequestBody(String path, String method) {
        Map<String, Object> requestBody =
                (Map<String, Object>) operation(path, method).get("requestBody");
        Map<String, Object> content = (Map<String, Object>) requestBody.get("content");
        Map<String, Object> json = (Map<String, Object>) content.get("application/json");
        Map<String, Object> schema = (Map<String, Object>) json.get("schema");
        return (List<String>) schema.get("required");
    }

    @SuppressWarnings("unchecked")
    private static List<String> parameterRefsOf(String path, String method) {
        List<String> refs = new ArrayList<>();
        List<Object> declared = (List<Object>) operation(path, method).get("parameters");
        if (declared == null) {
            return refs;
        }
        for (Object parameter : declared) {
            Object ref = ((Map<String, Object>) parameter).get("$ref");
            if (ref != null) {
                refs.add(ref.toString());
            }
        }
        return refs;
    }

    /** 계약이 선언한 {@code METHOD /path} 전부. */
    @SuppressWarnings("unchecked")
    private static Set<String> declaredOperations() {
        Set<String> found = new LinkedHashSet<>();
        for (var entry : paths().entrySet()) {
            for (String method : ((Map<String, Object>) entry.getValue()).keySet()) {
                if (!"parameters".equals(method)) {
                    found.add(method.toUpperCase() + " " + entry.getKey());
                }
            }
        }
        return found;
    }

    /** 컨트롤러의 매핑을 {@code METHOD /path} 로 눕힌다 — 클래스의 {@code @RequestMapping} 을 앞에 붙인다. */
    private static List<String> operationsOf(Class<?> controller) {
        String base = controller.isAnnotationPresent(RequestMapping.class)
                ? controller.getAnnotation(RequestMapping.class).value()[0]
                : "";
        List<String> found = new ArrayList<>();
        for (Method method : controller.getDeclaredMethods()) {
            if (method.isAnnotationPresent(GetMapping.class)) {
                found.add("GET " + base + method.getAnnotation(GetMapping.class).value()[0]);
            }
            if (method.isAnnotationPresent(PostMapping.class)) {
                found.add("POST " + base + method.getAnnotation(PostMapping.class).value()[0]);
            }
            if (method.isAnnotationPresent(PutMapping.class)) {
                found.add("PUT " + base + method.getAnnotation(PutMapping.class).value()[0]);
            }
            if (method.isAnnotationPresent(DeleteMapping.class)) {
                found.add("DELETE " + base + method.getAnnotation(DeleteMapping.class).value()[0]);
            }
        }
        return found;
    }

    /** 응답 레코드의 필드 이름. Jackson 이 그대로 JSON 키로 쓴다. */
    private static Set<String> componentNames(Class<?> record) {
        Set<String> names = new LinkedHashSet<>();
        for (RecordComponent component : record.getRecordComponents()) {
            names.add(component.getName());
        }
        return names;
    }
}
