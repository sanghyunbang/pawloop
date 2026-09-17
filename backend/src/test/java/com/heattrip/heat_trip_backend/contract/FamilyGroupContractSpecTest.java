package com.heattrip.heat_trip_backend.contract;

import com.heattrip.heat_trip_backend.chatweb.ChatInviteController;
import com.heattrip.heat_trip_backend.group.controller.GroupController;
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
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 가족 그룹·초대 계약이 <b>실제로 도는 코드</b>와 같은 것을 말하는지 본다 — 이슈 #75.
 *
 * <h2>이 이슈가 계약에서 걷어낸 것</h2>
 * <p>계약에는 ADR-0011 이전의 모양이 셋 남아 있었고 그 정리를 이 이슈가 소유했다.
 * <ul>
 *   <li>{@code POST /api/groups/join} — 초대코드가 {@code family_group.invite_code} 컬럼이던
 *       시절의 경로. 지금 참여는 {@code POST /api/chat/invites/{code}/join} 하나다.</li>
 *   <li>{@code Group.inviteCode} — 그룹당 코드 하나가 영구히 사는 모양.</li>
 *   <li>{@code GroupRole} 의 소문자 {@code owner}/{@code member} — 값의 출처가
 *       {@code chat_room_member.role} 하나인데 표기가 둘이었다.</li>
 * </ul>
 * <p>셋 다 {@code x-implementation-status: superseded-by-adr-0011} 로 표시돼 있었다.
 * 표시는 <b>임시 조치</b>이고, 표시를 남긴 채로도 문서는 계속 렌더링된다 — 그래서 지워졌는지를
 * 여기서 잡는다.
 *
 * <h2>경로 목록을 손으로 적지 않는다</h2>
 * <p>컨트롤러의 애너테이션에서 읽는다. 손으로 적으면 코드가 아니라 <b>사본과 문서</b>를
 * 대조하게 되어 둘이 나란히 낡은 채 초록불이 된다
 * ({@code OpenApiAuthContractTest} 가 응답 DTO 의 JSON 키를 Jackson 에서 읽는 것과 같은 이유다).
 *
 * <p>스프링 컨텍스트를 띄우지 않는다. 문서를 읽고 클래스를 리플렉션으로 볼 뿐이다(#21).
 */
class FamilyGroupContractSpecTest {

    private static Map<String, Object> spec;
    private static String raw;

    @SuppressWarnings("unchecked")
    @BeforeAll
    static void loadContract() throws IOException {
        // 파일이 없으면 requireFile 이 여기서 던진다. skip 이 아니다 — 못 읽고 통과하면
        // 이 테스트는 아무것도 지키지 않으면서 초록불만 낸다.
        raw = Files.readString(
                TestProjectPaths.requireFile("../docs/04-api/openapi.yaml"), StandardCharsets.UTF_8);
        spec = (Map<String, Object>) new Yaml().load(raw);
    }

    // ─────────────────── A. 코드 ↔ 계약 ───────────────────

    @Test
    @DisplayName("이 이슈가 연 경로가 계약에 그대로 등재돼 있다 — 경로 목록은 컨트롤러에서 읽는다")
    void everyEndpointThisIssueOpened_isDeclaredInTheContract() {
        Set<String> declared = declaredOperations();
        List<String> implemented = new ArrayList<>();
        implemented.addAll(operationsOf(GroupController.class));
        implemented.addAll(operationsOf(ChatInviteController.class));

        // 이 숫자는 **리플렉션이 실제로 읽었는가**를 재는 것이지 경로 개수를 얼리는 것이
        // 아니다. 0 이면 아래 `containsAll` 이 빈 목록을 통과시켜 이 검사가 아무것도 안 지킨다.
        // 경로가 늘면 여기도 같이 는다 — 2026-09 에 초대코드 조회(GET …/invites)가 들어와
        // 다섯에서 여섯이 됐다(#625).
        assertThat(implemented)
                .as("컨트롤러에서 매핑을 하나도 못 읽었다면 이 검사는 아무것도 지키지 않는다")
                .hasSize(6);
        assertThat(declared)
                .as("""
                        계약에 없는 경로는 앱이 존재를 모른다 — design-first 라 앱은 이 파일을 보고 만든다.
                        경로 변수 이름까지 같아야 한다: 계약이 {roomId} 인데 코드가 {id} 면 생성된 \
                        클라이언트의 시그니처가 틀린다.""")
                .containsAll(implemented);
    }

    // ─────────────────── B. 걷어낸 옛 모양 ───────────────────

    @Test
    @DisplayName("POST /api/groups/join 이 계약에서 사라졌다 — 참여 경로는 초대코드 하나다")
    void theOldGroupJoinPath_isGone() {
        assertThat(paths())
                .as("""
                        이 경로는 초대코드가 family_group.invite_code 컬럼이던 시절의 것이다. \
                        남겨 두면 앱 팀이 둘 중 무엇을 부를지 매번 물어야 하고, 목 서버(Prism)로는 \
                        통과하지만 실서버에서는 404 다 (ADR-0011 · 이슈 #75).""")
                .doesNotContainKey("/api/groups/join");
        assertThat(paths())
                .as("대신 들어온 경로가 없으면 참여할 방법 자체가 사라진 것이다")
                .containsKey("/api/chat/invites/{code}/join");
    }

    @Test
    @DisplayName("Group 에 inviteCode 가 없고 roomId·members 가 있다 — 초대코드는 방에 붙는다")
    void groupSchema_carriesTheRoomInsteadOfACode() {
        Map<String, Object> properties = asMap(schema("Group").get("properties"));

        assertThat(properties)
                .as("""
                        그룹 응답에 코드를 하나 실으면 '그룹당 코드 하나' 라는 옛 모양이 앱 화면에서 \
                        되살아난다. 만료·사용횟수·회수를 걸 자리가 없는 모양이다.""")
                .doesNotContainKey("inviteCode");
        assertThat(properties)
                .as("roomId 가 없으면 초대 발급 경로(POST /api/chat/rooms/{roomId}/invites)로 갈 열쇠가 없다")
                .containsKeys("roomId", "members", "id", "name", "createdAt");
    }

    @Test
    @DisplayName("GroupRole 이 chat_room_member.role 과 같은 표기다 — OWNER · MEMBER")
    void groupRoleEnum_matchesTheMembershipTable() {
        assertThat(stringList(asMap(spec("GroupRole")).get("enum")))
                .as("""
                        값의 출처는 chat_room_member.role 하나다. 계약만 소문자로 적으면 API 계층이 \
                        두 표기를 옮겨 적어야 하고, 그 변환을 빠뜨린 곳이 조용히 생긴다.""")
                .containsExactlyInAnyOrder("OWNER", "MEMBER");
    }

    @Test
    @DisplayName("Groups·Chat 의 초대 경로에 superseded 표식과 '미구현' 서술이 남아 있지 않다")
    void noSupersededMarkersRemainOnTheImplementedPaths() {
        for (String path : List.of("/api/groups", "/api/groups/me",
                "/api/chat/rooms/{roomId}/invites",
                "/api/chat/rooms/{roomId}/invites/{code}",
                "/api/chat/invites/{code}/join")) {
            Map<String, Object> operations = asMap(paths().get(path));
            for (Map.Entry<String, Object> operation : operations.entrySet()) {
                if (!(operation.getValue() instanceof Map)) {
                    continue;   // parameters 처럼 오퍼레이션이 아닌 항목
                }
                Map<String, Object> body = asMap(operation.getValue());
                assertThat(body)
                        .as("기계가 읽는 미구현 표식이 남으면 클라이언트 생성기가 %s 를 건너뛴다", path)
                        .doesNotContainKey("x-implementation-status");
                assertThat(String.valueOf(body.get("description")))
                        .as("'미구현' 이 현재형으로 남으면 앱 팀이 이 경로를 피한다 — %s", path)
                        .doesNotContain("미구현");
            }
        }

        assertThat(raw)
                .as("superseded 표식은 임시 조치였다. 이 이슈가 그 정리의 소유자다")
                .doesNotContain("superseded-by-adr-0011");
    }

    @Test
    @DisplayName("계약이 발급 경로에 본문을 요구하지 않는다 — 서버가 받지 않는 값을 광고하면 안 된다")
    void theIssuePath_doesNotAdvertiseARequestBodyTheServerIgnores() {
        Map<String, Object> issue = asMap(asMap(paths().get("/api/chat/rooms/{roomId}/invites"))
                .get("post"));

        assertThat(issue)
                .as("""
                        유효기간·사용 횟수를 정하는 곳은 ChatLimits 하나다. 계약이 expiresAt·maxUses 를 \
                        받는다고 적어 두면 앱은 보낸 값이 반영된다고 믿고, 서버는 조용히 무시한다.
                        그 문은 요금제가 생기는 날 ChatLimits 와 함께 연다.""")
                .doesNotContainKey("requestBody");
    }

    @Test
    @DisplayName("참여 경로가 410 을 선언한다 — 만료·회수가 200/404 로 뭉개지지 않는다")
    void theJoinPath_declaresTheGoneResponses() {
        Map<String, Object> join = asMap(asMap(paths().get("/api/chat/invites/{code}/join"))
                .get("post"));
        Map<String, Object> responses = asMap(join.get("responses"));

        assertThat(responses)
                .as("""
                        만료·회수는 '있었는데 이제 없다' 라서 410 이다. 계약이 이 상태를 선언하지 않으면 \
                        앱은 오지 않는 코드를 기다리거나 404 로 뭉개서 '잘못된 링크' 로 보여 준다.""")
                .containsKeys("200", "403", "404", "409", "410");
    }

    // ─────────────────────────── 파싱 유틸 ───────────────────────────

    /** 계약이 선언한 {@code "METHOD /path"} 집합. */
    private static Set<String> declaredOperations() {
        Set<String> declared = new LinkedHashSet<>();
        for (Map.Entry<String, Object> path : paths().entrySet()) {
            for (Map.Entry<String, Object> operation : asMap(path.getValue()).entrySet()) {
                if (operation.getValue() instanceof Map) {
                    declared.add(operation.getKey().toUpperCase() + " " + path.getKey());
                }
            }
        }
        return declared;
    }

    /** 컨트롤러의 애너테이션에서 읽은 {@code "METHOD /path"} 목록. */
    private static List<String> operationsOf(Class<?> controller) {
        String base = controller.isAnnotationPresent(RequestMapping.class)
                ? firstOrEmpty(controller.getAnnotation(RequestMapping.class).value())
                : "";

        List<String> operations = new ArrayList<>();
        for (Method method : controller.getDeclaredMethods()) {
            if (method.isSynthetic()) {
                continue;
            }
            if (method.isAnnotationPresent(PostMapping.class)) {
                operations.add("POST " + base
                        + firstOrEmpty(method.getAnnotation(PostMapping.class).value()));
            }
            if (method.isAnnotationPresent(GetMapping.class)) {
                operations.add("GET " + base
                        + firstOrEmpty(method.getAnnotation(GetMapping.class).value()));
            }
            if (method.isAnnotationPresent(DeleteMapping.class)) {
                operations.add("DELETE " + base
                        + firstOrEmpty(method.getAnnotation(DeleteMapping.class).value()));
            }
            if (method.isAnnotationPresent(PutMapping.class)) {
                operations.add("PUT " + base
                        + firstOrEmpty(method.getAnnotation(PutMapping.class).value()));
            }
        }
        return operations;
    }

    private static String firstOrEmpty(String[] values) {
        return values.length == 0 ? "" : values[0];
    }

    private static Map<String, Object> paths() {
        return asMap(spec.get("paths"));
    }

    private static Map<String, Object> schema(String name) {
        return asMap(spec(name));
    }

    private static Object spec(String schemaName) {
        return asMap(asMap(spec.get("components")).get("schemas")).get(schemaName);
    }

    private static List<String> stringList(Object raw) {
        assertThat(raw).as("enum 이 없다 — 값 집합을 선언하지 않으면 무엇이든 유효해진다").isNotNull();
        List<String> values = new ArrayList<>();
        for (Object value : (List<?>) raw) {
            values.add(String.valueOf(value));
        }
        return values;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> asMap(Object raw) {
        assertThat(raw).as("계약에서 기대한 맵을 찾지 못했다").isInstanceOf(Map.class);
        return (Map<String, Object>) raw;
    }
}
