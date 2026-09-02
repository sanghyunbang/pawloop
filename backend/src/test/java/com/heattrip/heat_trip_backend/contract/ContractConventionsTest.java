package com.heattrip.heat_trip_backend.contract;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import com.heattrip.heat_trip_backend.support.TestProjectPaths;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.yaml.snakeyaml.Yaml;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 계약이 스스로 선언한 규약을 <b>전부 도는</b> 검사 — ADR-0017 · 이슈 #24.
 *
 * <h2>왜 이 테스트가 따로 있는가</h2>
 * <p>규약은 이미 여러 번 정해졌고 여러 번 다시 벌어졌다. {@code required} 는
 * {@code Dog}·{@code Walk}·{@code User} 에서 채워졌는데, 그 뒤 M2.5~M2.7 에서 들어온
 * {@code ChatRoom}·{@code CareLog}·{@code GroupMember} 는 <b>같은 자리가 다시 비었다.</b>
 *
 * <p>이유는 검사가 <b>이름을 손으로 적고 있었기</b> 때문이다 —
 * {@link AuthContractSpecTest} 는 {@code AuthTokens}·{@code User}·{@code Page} 셋만 대조한다.
 *
 * <pre>
 *   손으로 적은 목록은 목록에 없는 것을 못 본다.
 *   그래서 새 스키마는 언제나 통과한다.
 * </pre>
 *
 * <p>여기서는 이름을 적지 않는다. {@code paths} 를 훑어 <b>응답으로 도달 가능한 스키마를 전부
 * 모으고</b>, 오퍼레이션을 <b>전부 돈다.</b> 새 스키마가 규약을 어기고 들어오면 그날 빨간불이다.
 *
 * <h2>느슨하게 잡는다</h2>
 * <p>{@code required} 에 <b>무엇이</b> 들어 있는지는 안 본다 — 있는지만 본다. 최소집합은
 * 응답 DTO 에서 뽑는 것이라 이 테스트가 판단할 수 없고, 여기서 목록까지 고정하면 필드를
 * 하나 더할 때마다 두 곳을 고쳐야 한다. 이 테스트가 지키는 것은 <b>"빠뜨리지 않았다"</b> 하나다.
 *
 * <p>네트워크를 타지 않는다. 저장소 안의 파일만 읽는다.
 */
class ContractConventionsTest {

    private static Map<String, Object> spec;
    private static Map<String, Object> schemas;
    private static Map<String, Object> paths;

    /** HTTP 메서드가 아닌 경로 수준 키. {@code paths./x.parameters} 는 오퍼레이션이 아니다. */
    private static final Set<String> HTTP_METHODS =
            Set.of("get", "post", "put", "patch", "delete", "head", "options", "trace");

    @BeforeAll
    @SuppressWarnings("unchecked")
    static void loadContract() throws IOException {
        String raw = Files.readString(
                TestProjectPaths.requireFile("../docs/04-api/openapi.yaml"), StandardCharsets.UTF_8);
        spec = (Map<String, Object>) new Yaml().load(raw);

        paths = (Map<String, Object>) spec.get("paths");
        schemas = (Map<String, Object>) ((Map<String, Object>) spec.get("components")).get("schemas");

        // 하나라도 못 읽으면 아래 단언들이 조용히 통과한다. skip 이 아니라 fail 이다.
        assertThat(paths).as("계약에서 paths 를 못 읽었다").isNotNull().isNotEmpty();
        assertThat(schemas).as("계약에서 components.schemas 를 못 읽었다").isNotNull().isNotEmpty();
    }

    // ─────────────── 규약 1 — 응답 스키마는 required 를 선언한다 ───────────────

    @Test
    @DisplayName("응답으로 도달 가능한 모든 객체 스키마가 required 를 선언한다")
    void everyResponseSchemaDeclaresRequired() {
        Set<String> reachable = schemasReachableFromResponses();

        assertThat(reachable)
                .as("응답에서 도달한 스키마가 이렇게 적을 리 없다 — 순회가 깨졌다는 뜻이다")
                .hasSizeGreaterThan(10);

        List<String> missing = new ArrayList<>();
        for (String name : reachable) {
            Map<String, Object> schema = schemaOf(name);
            if (schema == null || !isObjectSchema(schema)) {
                continue;
            }
            Object required = schema.get("required");
            if (!(required instanceof List<?> list) || list.isEmpty()) {
                missing.add(name);
            }
        }

        assertThat(missing)
                .as("""
                        OpenAPI 에서 required 부재는 "전부 선택" 이다. 그러면 백엔드가 id 를 빼고 \
                        보내도 계약 위반이 아니고, Prism 목 서버가 빈 객체를 내도 합법이며, \
                        코드 생성기가 전 필드를 nullable 로 만들어 앱이 온통 강제 언랩이 된다. \
                        required 는 "서버가 **항상** 채우는 필드" 의 최소집합이고, 그 목록은 \
                        계약이 아니라 **응답 DTO** 에서 뽑는다 — 넣지 말아야 할 것을 넣으면 \
                        그 순간부터 서버가 계약 위반이다(ADR-0017 규약 1).""")
                .isEmpty();
    }

    // ─────────────── 규약 3 — 인증 오퍼레이션은 401 을 선언한다 ───────────────

    @Test
    @DisplayName("인증이 필요한 모든 오퍼레이션이 401 을 선언한다")
    void everyAuthenticatedOperationDeclares401() {
        List<String> missing = new ArrayList<>();

        forEachOperation((label, operation) -> {
            if (!requiresAuthentication(operation)) {
                return;
            }
            if (!responsesOf(operation).containsKey("401")) {
                missing.add(label);
            }
        });

        assertThat(missing)
                .as("""
                        전역 security 가 bearerAuth 인데 일부만 401 을 선언하면, 형제 오퍼레이션 \
                        끼리 오류 계약이 어긋난다 — 그건 설계가 아니라 누락이다. 이 계약을 보고 \
                        만든 앱은 401 을 안 다루고, 토큰이 만료된 순간 화면이 무엇을 할지 \
                        아무도 정하지 않은 상태가 된다(ADR-0017 규약 3).

                        인증이 선택인 경로(security 에 {} 가 있는 것)와 security: [] 는 이 검사 \
                        대상이 아니다.""")
                .isEmpty();
    }

    // "남의 리소스를 403 으로 알려 주지 않는다" 를 403 금지로 검사하지 않는 이유
    //
    // 처음엔 403 을 선언한 오퍼레이션이 0개인지 봤다. 열여덟 자리가 걸렸고, 읽어 보니
    // 그것들이 틀린 게 아니라 규약을 그렇게 적은 내가 틀렸다.
    //
    // Chat·Groups 는 반대로 간다 — 없는 방·없는 그룹도 비멤버와 같은 403 이다. 이유는
    // 같다(openapi.yaml 의 care-logs 설명, ChatRoomService javadoc): 404 로 답하면 id 를
    // 훑어 "있는 가족/없는 가족" 을 가려낼 수 있다.
    //
    // 그러니 불변식은 코드가 아니라 "남의 것과 없는 것이 구별되지 않는다" 이고, 그건
    // 계약의 모양이 아니라 **동작**이다 — 같은 조회가 존재 여부에 따라 다른 코드를 내는지는
    // YAML 을 읽어서 알 수 없다. 두 도메인 다 그 선택을 통합 테스트로 이미 잠갔다.
    // ADR-0017 규약 3 이 표로 적어 둔다.

    // ─────────────── 규약 4 — 부분 수정은 생성 스키마를 재사용하지 않는다 ───────────────

    @Test
    @DisplayName("PATCH 는 생성 스키마를 재사용하지 않고 minProperties 로 빈 본문을 막는다")
    void patchOperationsUseADedicatedSchema() {
        List<String> offenders = new ArrayList<>();

        forEachOperation((label, operation) -> {
            if (!label.startsWith("PATCH ")) {
                return;
            }
            Map<String, Object> body = mapOf(operation.get("requestBody"));
            if (body == null) {
                offenders.add(label + " — requestBody 가 없다");
                return;
            }
            if (!Boolean.TRUE.equals(body.get("required"))) {
                offenders.add(label + " — requestBody.required 가 없어 빈 본문이 합법이다");
            }
            String ref = requestSchemaRef(body);
            if (ref == null) {
                return;
            }
            Map<String, Object> schema = schemaOf(ref);
            if (schema == null) {
                offenders.add(label + " — 본문 스키마 " + ref + " 를 못 찾았다");
                return;
            }
            if (schema.get("required") != null) {
                offenders.add(label + " — 본문 스키마 " + ref + " 에 required 가 있다(생성용 스키마다)");
            }
            if (schema.get("minProperties") == null) {
                offenders.add(label + " — 본문 스키마 " + ref + " 에 minProperties 가 없다");
            }
        });

        assertThat(offenders)
                .as("""
                        부분 수정에 생성용 스키마를 재사용하면 계약대로는 부분 수정이 **불가능**하다 — \
                        생성 스키마의 required 가 전부 따라오기 때문이다. PATCH /api/dogs 가 \
                        `required: [name, size]` 인 DogInput 을 쓰고 있어서, {"neutered": true} 만 \
                        보내는 것이 계약 위반이었다.

                        전용 *Patch 스키마에 minProperties: 1 을 걸고 requestBody.required: true 를 \
                        둔다. UserUpdate 가 그 본이다(ADR-0017 규약 4).""")
                .isEmpty();
    }

    // ─────────────── 규약 6 — 인증이 선택인 경로는 security: [] 가 아니다 ───────────────

    @Test
    @DisplayName("개인화 필드를 돌려주는 오퍼레이션이 security: [] 로 인증을 지우지 않는다")
    void operationsReturningPersonalFieldsKeepOptionalAuth() {
        List<String> offenders = new ArrayList<>();

        forEachOperation((label, operation) -> {
            if (!(operation.get("security") instanceof List<?> security) || !security.isEmpty()) {
                return; // security: [] 인 것만 본다
            }
            // **중첩까지 본다.** 처음엔 응답이 직접 $ref 한 스키마만 봤는데, 그러면
            // 게시글 목록(Page + Post[])에서 Post 안의 ReactionSummary.mine 을 놓친다 —
            // 그게 정확히 이 규약이 잡으라고 만들어진 자리였다. 되돌려 보고서야 알았다.
            Set<String> reachable = new LinkedHashSet<>();
            for (String name : schemasOf(responsesOf(operation))) {
                collectTransitively(name, reachable);
            }
            for (String name : reachable) {
                if (declaresAPersonalField(name)) {
                    offenders.add(label + " — 응답 " + name + " 가 개인화 필드를 가진다");
                }
            }
        });

        assertThat(offenders)
                .as("""
                        security: [] 는 인증을 계약에서 **제거**한다 — 서버가 토큰을 읽지 않아야 \
                        한다는 뜻이다. 그런데 응답에 "내가 누른 반응" 같은 사용자별 필드가 있으면, \
                        계약대로 구현한 서버에서 그 필드는 **영원히 null 인 죽은 필드**가 된다.

                        게스트 읽기는 취향이 아니라 MVP 정의이므로, 지워야 할 것은 그 필드가 아니라 \
                        security: [] 다. 인증이 선택이면 security: [{}, {bearerAuth: []}] 로 \
                        적는다(ADR-0017 규약 6).""")
                .isEmpty();
    }

    // ─────────────────────────── 지그 ───────────────────────────

    /** 응답에서 {@code $ref} 로 도달할 수 있는 컴포넌트 스키마 이름 전부(중첩·allOf·배열 포함). */
    private Set<String> schemasReachableFromResponses() {
        Set<String> seen = new LinkedHashSet<>();
        forEachOperation((label, operation) -> {
            for (String name : schemasOf(responsesOf(operation))) {
                collectTransitively(name, seen);
            }
        });
        return seen;
    }

    private void collectTransitively(String name, Set<String> seen) {
        if (!seen.add(name)) {
            return;
        }
        for (String nested : refsIn(schemaOf(name))) {
            collectTransitively(nested, seen);
        }
    }

    /** {@code responses} 아래에 등장하는 모든 {@code $ref} 스키마 이름. */
    private static Set<String> schemasOf(Object node) {
        Set<String> out = new LinkedHashSet<>();
        out.addAll(refsIn(node));
        return out;
    }

    /** 아무 노드에서나 {@code #/components/schemas/X} 참조를 긁어모은다. */
    @SuppressWarnings("unchecked")
    private static Set<String> refsIn(Object node) {
        Set<String> out = new LinkedHashSet<>();
        if (node instanceof Map<?, ?> map) {
            for (Map.Entry<?, ?> e : map.entrySet()) {
                if ("$ref".equals(e.getKey()) && e.getValue() instanceof String ref) {
                    String prefix = "#/components/schemas/";
                    if (ref.startsWith(prefix)) {
                        out.add(ref.substring(prefix.length()));
                    }
                } else {
                    out.addAll(refsIn(e.getValue()));
                }
            }
        } else if (node instanceof List<?> list) {
            for (Object item : list) {
                out.addAll(refsIn(item));
            }
        }
        return out;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> schemaOf(String name) {
        return (Map<String, Object>) schemas.get(name);
    }

    /**
     * 객체 스키마인가. enum 문자열·배열·{@code allOf} 합성은 아니다.
     *
     * <p>{@code allOf} 를 빼는 이유: 그 스키마의 required 는 합성 대상 쪽에 있고, 여기서
     * 요구하면 같은 목록을 두 번 적게 된다.
     */
    private static boolean isObjectSchema(Map<String, Object> schema) {
        if (schema.containsKey("allOf") || schema.containsKey("oneOf") || schema.containsKey("anyOf")) {
            return false;
        }
        if (!(schema.get("properties") instanceof Map<?, ?> props) || props.isEmpty()) {
            return false;
        }
        Object type = schema.get("type");
        return type == null || "object".equals(type);
    }

    /** 이 스키마가 "요청한 사람이 누구냐" 에 따라 값이 달라지는 필드를 가지는가. */
    private static boolean declaresAPersonalField(String name) {
        Map<String, Object> schema = schemaOf(name);
        if (schema == null || !(schema.get("properties") instanceof Map<?, ?> props)) {
            return false;
        }
        // 지금 계약에 있는 개인화 필드는 ReactionSummary.mine 하나다. 늘어나면 여기 더한다.
        return props.containsKey("mine") || props.containsKey("myRole");
    }

    /** 이 오퍼레이션이 인증을 <b>요구</b>하는가. 선택({})이거나 비었으면 아니다. */
    @SuppressWarnings("unchecked")
    private static boolean requiresAuthentication(Map<String, Object> operation) {
        if ("framework".equals(operation.get("x-status"))) {
            return false; // Spring Security 가 처리하는 경로 — 우리 컨트롤러가 아니다
        }
        Object declared = operation.get("security");
        if (declared == null) {
            return true; // 전역 security 를 상속한다
        }
        if (!(declared instanceof List<?> list) || list.isEmpty()) {
            return false;
        }
        for (Object alternative : list) {
            if (alternative instanceof Map<?, ?> m && m.isEmpty()) {
                return false; // {} 가 있으면 인증 없이도 부를 수 있다
            }
        }
        return true;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> responsesOf(Map<String, Object> operation) {
        Object responses = operation.get("responses");
        return responses instanceof Map ? (Map<String, Object>) responses : Map.of();
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> mapOf(Object node) {
        return node instanceof Map ? (Map<String, Object>) node : null;
    }

    /** {@code requestBody} 안의 스키마가 컴포넌트 참조면 그 이름, 인라인이면 {@code null}. */
    private static String requestSchemaRef(Map<String, Object> requestBody) {
        Set<String> refs = refsIn(requestBody);
        return refs.isEmpty() ? null : refs.iterator().next();
    }

    @SuppressWarnings("unchecked")
    private static void forEachOperation(java.util.function.BiConsumer<String, Map<String, Object>> visitor) {
        for (Map.Entry<String, Object> path : paths.entrySet()) {
            Map<String, Object> item = (Map<String, Object>) path.getValue();
            for (Map.Entry<String, Object> op : item.entrySet()) {
                if (!HTTP_METHODS.contains(op.getKey())) {
                    continue;
                }
                visitor.accept(
                        op.getKey().toUpperCase(java.util.Locale.ROOT) + " " + path.getKey(),
                        (Map<String, Object>) op.getValue());
            }
        }
    }
}
