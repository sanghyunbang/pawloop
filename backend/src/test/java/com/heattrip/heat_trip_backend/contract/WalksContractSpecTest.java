package com.heattrip.heat_trip_backend.contract;

import static org.assertj.core.api.Assertions.assertThat;

import com.heattrip.heat_trip_backend.S3.UploadCategory;
import com.heattrip.heat_trip_backend.support.TestProjectPaths;
import com.heattrip.heat_trip_backend.walk.dto.WalkRequest;
import com.heattrip.heat_trip_backend.walk.dto.WalkResponse;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.yaml.snakeyaml.Yaml;

import java.io.IOException;
import java.lang.reflect.RecordComponent;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 산책 계약({@code openapi.yaml} 의 {@code Walk} · {@code WalkInput}) ↔ 코드({@code WalkResponse} ·
 * {@code WalkRequest}) — 이슈 #450 에서 세웠다.
 *
 * <p>커뮤니티 · 아이 · 케어에는 이 검사가 있었고 산책에는 없었다. 그래서 산책 사진(#450)을 더할 때
 * 계약에서 {@code Walk.media} 를 빼도 아무 검사도 빨개지지 않았다(되돌려서 빨간불 M7). 앱은 이 파일을
 * 보고 만들므로, 계약과 레코드가 갈리면 앱이 없는 필드를 읽거나 있는 필드를 모른다.
 */
class WalksContractSpecTest {

    private static Map<String, Object> spec;

    @SuppressWarnings("unchecked")
    @BeforeAll
    static void loadContract() throws IOException {
        spec = (Map<String, Object>) new Yaml().load(Files.readString(
                TestProjectPaths.requireFile("../docs/04-api/openapi.yaml"), StandardCharsets.UTF_8));
    }

    @Test
    @DisplayName("Walk 의 속성이 WalkResponse 의 필드와 정확히 같다 — media 까지")
    void walkSchema_matchesTheResponseRecord() {
        assertThat(propertyNames("Walk"))
                .containsExactlyInAnyOrderElementsOf(componentNames(WalkResponse.class));
        assertThat(propertyNames("Walk")).as("산책 사진(#450)").contains("media");
    }

    @Test
    @DisplayName("WalkInput 의 속성이 WalkRequest 의 필드와 정확히 같다 — mediaIds 까지")
    void walkInputSchema_matchesTheRequestRecord() {
        assertThat(propertyNames("WalkInput"))
                .containsExactlyInAnyOrderElementsOf(componentNames(WalkRequest.class));
        assertThat(propertyNames("WalkInput")).as("산책 사진(#450)").contains("mediaIds");
    }

    @Test
    @DisplayName("Walk.media 의 항목은 PostMedia 와 같은 모양이다 — 앱이 글 사진과 같은 그림을 그린다")
    void walkMedia_hasTheSameShapeAsPostMedia() {
        assertThat(propertyNames("PostMedia"))
                .containsExactlyInAnyOrderElementsOf(componentNames(WalkResponse.WalkMedia.class));
        Map<String, Object> media = property("Walk", "media");
        assertThat(media.get("type")).isEqualTo("array");
        assertThat(((Map<String, Object>) media.get("items")).get("$ref"))
                .isEqualTo("#/components/schemas/PostMedia");
    }

    @Test
    @DisplayName("mediaIds 의 상한이 코드와 같다 — 한 산책에 열 장")
    void mediaIdsLimit_matchesTheCode() {
        assertThat(property("WalkInput", "mediaIds").get("maxItems")).isEqualTo(WalkRequest.MAX_MEDIA);
    }

    @Test
    @DisplayName("MediaItem.category 의 enum 이 UploadCategory 와 같은 집합이다 — WALK_IMAGE 가 계약에 있다")
    void mediaCategories_matchTheEnum() {
        Set<String> declared = new LinkedHashSet<>((List<String>) property("MediaItem", "category").get("enum"));
        Set<String> code = new LinkedHashSet<>(Arrays.stream(UploadCategory.values()).map(Enum::name).toList());
        assertThat(declared).containsExactlyInAnyOrderElementsOf(code);
    }

    // ─────────────────── 도우미 ───────────────────

    @SuppressWarnings("unchecked")
    private static Map<String, Object> schema(String name) {
        Map<String, Object> components = (Map<String, Object>) spec.get("components");
        Map<String, Object> schemas = (Map<String, Object>) components.get("schemas");
        Map<String, Object> found = (Map<String, Object>) schemas.get(name);
        assertThat(found).as("계약에 %s 스키마가 없다", name).isNotNull();
        return found;
    }

    @SuppressWarnings("unchecked")
    private static Set<String> propertyNames(String schemaName) {
        return new LinkedHashSet<>(((Map<String, Object>) schema(schemaName).get("properties")).keySet());
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> property(String schemaName, String field) {
        Map<String, Object> properties = (Map<String, Object>) schema(schemaName).get("properties");
        Map<String, Object> property = (Map<String, Object>) properties.get(field);
        assertThat(property).as("계약의 %s.%s 가 없다", schemaName, field).isNotNull();
        return property;
    }

    private static Set<String> componentNames(Class<?> record) {
        Set<String> names = new LinkedHashSet<>();
        for (RecordComponent component : record.getRecordComponents()) {
            names.add(component.getName());
        }
        return names;
    }
}
