package com.heattrip.heat_trip_backend.docs;

import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

import com.fasterxml.jackson.databind.BeanDescription;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.OAuth.controller.OAuthLoginController;
import com.heattrip.heat_trip_backend.user.dto.UserResponse;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.yaml.snakeyaml.Yaml;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 계약({@code docs/04-api/openapi.yaml})의 인증 스키마가 <b>실제 코드</b>와 같은 것을
 * 말하는지 대조한다 — 이슈 #15.
 *
 * <h2>{@code AuthContractSpecTest} 와 무엇이 다른가</h2>
 * <p>그쪽은 "계약 문서가 스스로 모순되지 않는가"(required 가 있는가, 미구현 표식이
 * 남았는가)를 본다. 여기는 <b>계약과 코드의 집합이 같은가</b>를 본다 — 응답 DTO 의 JSON 키
 * 집합, 공급자 화이트리스트. 두 집합이 갈라지면 계약만 보고 만든 클라이언트가 조용히 깨진다.
 *
 * <h2>ADR-0010 을 계약 파일에 잠근다</h2>
 * <p>"네이버 보류" 는 ADR 산문으로만 두면 되돌아온다. {@code parameters.Provider} 와
 * {@code User.provider} 의 enum 에 {@code naver} 를 다시 넣으면 여기서 빨간불이 난다
 * (완료 조건 8). 코드 쪽 화이트리스트({@code OAuthLoginController.SUPPORTED_PROVIDERS})도 같은
 * 집합이어야 한다 — 한쪽만 넓히면 계약에 없는 값이 302 로 통과한다.
 *
 * <p>스프링 컨텍스트를 띄우지 않는다. 문서를 읽고 클래스를 리플렉션으로 볼 뿐이다.
 */
class OpenApiAuthContractTest {

    private static Map<String, Object> spec;
    private static String raw;

    @SuppressWarnings("unchecked")
    @BeforeAll
    static void loadContract() {
        // 파일이 없으면 여기서 던진다. skip 이 아니다 (완료 조건 10).
        raw = RepositoryDocs.requireDoc("04-api/openapi.yaml");
        spec = (Map<String, Object>) new Yaml().load(raw);
    }

    // ─────────────────── A. 공급자 집합 — ADR-0010 의 실행 가능한 형태 ───────────────────

    @Test
    @DisplayName("경로 파라미터 Provider 의 enum 이 ADR-0010(kakao·google) + ADR-0022(apple) 과 정확히 같다")
    void providerParameterEnum_matchesAdr0010() {
        assertThat(providerParameterEnum())
                .as("naver 를 되돌리면 여기서 빨간불이 난다 — 보류는 산문이 아니라 계약이다 (완료 조건 8). apple 은 #301")
                .containsExactly("kakao", "google", "apple");
    }

    @Test
    @DisplayName("User.provider 의 enum 에서 naver 만 빠지고 local·null 은 남는다")
    void userProviderEnum_dropsOnlyNaver() {
        List<String> values = enumOf(schema("User"), "provider");

        assertThat(values)
                .as("보류 대상은 naver 하나다. enum 을 통째로 지우면 이메일 가입자와 백필 전 옛 행을 표현할 수 없다")
                .containsExactlyInAnyOrder("local", "kakao", "google", "apple", "null");
    }

    @Test
    @DisplayName("계약이 네이버 보류의 근거로 ADR-0010 을 가리킨다")
    void providerParameter_pointsAtTheDecisionRecord() {
        // 계약만 읽는 사람이 "왜 네이버가 없지" 를 검색할 수 있어야 한다. 번호가 없으면 못 찾는다.
        assertThat(providerParameterDescription())
                .as("결정 기록으로 가는 길이 없으면 6개월 뒤에 같은 논의가 반복된다")
                .contains("ADR-0010");
    }

    @Test
    @DisplayName("코드의 공급자 화이트리스트가 계약의 Provider enum 과 같은 집합이다")
    void supportedProviders_matchTheContractEnum() {
        // docs/02-architecture/backend/auth.md 가 이 불변식을 글로 적어 두었다. 글은 지켜지지 않는다.
        // 여기서만 넓히면 계약에 없는 값이 302 로 통과하고, 여기서만 좁히면 계약이 거짓을 광고한다.
        assertThat(supportedProvidersFromCode())
                .as("계약 enum 과 OAuthLoginController.SUPPORTED_PROVIDERS 가 갈라졌다")
                .containsExactlyInAnyOrderElementsOf(providerParameterEnum());
    }

    // ─────────────────── B. /auth/me 200 스키마 ↔ 응답 DTO ───────────────────

    @Test
    @DisplayName("GET /auth/me 200 의 User 속성 집합이 UserResponse 의 JSON 키 집합과 정확히 같다")
    void authMeSchema_matchesTheResponseDto() {
        assertThat(authMeOkSchemaRef())
                .as("200 이 User 를 가리키지 않으면 아래 대조가 다른 것을 보게 된다")
                .isEqualTo("#/components/schemas/User");

        Set<String> contract = asMap(schema("User").get("properties")).keySet();

        // 키 목록을 테스트에 다시 적지 않는다. 적으면 코드가 아니라 사본과 문서를 대조하게 되어
        // 둘이 나란히 낡은 채 초록불이 된다. Jackson 이 실제로 직렬화할 이름을 그대로 쓴다.
        assertThat(contract)
                .as("계약을 옛 모양({id, provider, nickname, isNew})으로 되돌리면 여기서 빨간불이 난다 (완료 조건 7)")
                .containsExactlyInAnyOrderElementsOf(jsonKeysOf(UserResponse.class));
    }

    @Test
    @DisplayName("계약이 딥링크에 토큰을 싣는다고 현재형으로 말하는 곳이 없다")
    void contract_neverHandsTokensThroughTheQueryString() {
        // #14 가 걷어낸 상태를 잠근다. 되돌아오면 액세스 토큰이 302 의 Location 헤더·브라우저
        // 히스토리에 남는다.
        //
        // 통째로 금지하지 않는 이유: openapi.yaml 에는 "2026-08 이전에는 이 딥링크가
        // `?token=…` 이었습니다(#9)" 라는 **이력 서술**이 한 줄 있다. 그건 지워야 할 거짓이
        // 아니라 남겨야 할 맥락이다 — 지우면 왜 1회용 코드로 바꿨는지가 사라진다.
        // .github/scripts/check-docs-drift.sh 가 쓰는 것과 같은 규칙이다.
        List<String> currentTense = raw.lines()
                .filter(line -> line.contains("?token="))
                .filter(line -> !line.contains("이전에는") && !line.contains("예전"))
                .toList();

        assertThat(currentTense)
                .as("소셜 딥링크는 1회용 코드 교환이다 (#14, ADR-0009). 이력 서술이라면 '이전에는' 을 붙여라")
                .isEmpty();
    }

    // ─────────────────────────── 파싱 유틸 ───────────────────────────

    private static List<String> providerParameterEnum() {
        Map<String, Object> provider =
                asMap(asMap(asMap(spec.get("components")).get("parameters")).get("Provider"));
        return stringList(asMap(provider.get("schema")).get("enum"));
    }

    private static String providerParameterDescription() {
        Map<String, Object> provider =
                asMap(asMap(asMap(spec.get("components")).get("parameters")).get("Provider"));
        return String.valueOf(provider.get("description"));
    }

    private static String authMeOkSchemaRef() {
        Map<String, Object> get = asMap(asMap(asMap(spec.get("paths")).get("/auth/me")).get("get"));
        Map<String, Object> ok = asMap(asMap(get.get("responses")).get("200"));
        Map<String, Object> json = asMap(asMap(ok.get("content")).get("application/json"));
        return String.valueOf(asMap(json.get("schema")).get("$ref"));
    }

    private static Map<String, Object> schema(String name) {
        return asMap(asMap(asMap(spec.get("components")).get("schemas")).get(name));
    }

    private static List<String> enumOf(Map<String, Object> schema, String property) {
        return stringList(asMap(asMap(schema.get("properties")).get(property)).get("enum"));
    }

    /** YAML 의 {@code null} 은 자바 null 로 들어온다. 문자열 {@code "null"} 로 눕혀 비교한다. */
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

    /** Jackson 이 실제로 쓸 JSON 프로퍼티 이름. 값 직렬화 없이 이름만 뽑는다. */
    private static Set<String> jsonKeysOf(Class<?> type) {
        ObjectMapper mapper = new ObjectMapper();
        BeanDescription description = mapper.getSerializationConfig()
                .introspect(mapper.constructType(type));
        Set<String> names = description.findProperties().stream()
                .map(property -> property.getName())
                .collect(Collectors.toSet());
        assertThat(names).as("%s 에서 JSON 키를 하나도 못 읽었다", type.getSimpleName()).isNotEmpty();
        return names;
    }

    /** {@code OAuthLoginController.SUPPORTED_PROVIDERS} — private static 이라 리플렉션으로 읽는다. */
    @SuppressWarnings("unchecked")
    private static List<String> supportedProvidersFromCode() {
        try {
            Field field = OAuthLoginController.class.getDeclaredField("SUPPORTED_PROVIDERS");
            field.setAccessible(true);
            return (List<String>) field.get(null);
        } catch (ReflectiveOperationException e) {
            throw new AssertionError(
                    "OAuthLoginController.SUPPORTED_PROVIDERS 를 읽지 못했다 — 이름이 바뀌었다면 "
                            + "계약 enum 과의 대조가 사라진다. 이 테스트도 함께 고쳐라.", e);
        }
    }
}
