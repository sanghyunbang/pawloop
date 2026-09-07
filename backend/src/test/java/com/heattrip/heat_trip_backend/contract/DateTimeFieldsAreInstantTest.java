package com.heattrip.heat_trip_backend.contract;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.lang.reflect.Field;
import java.lang.reflect.RecordComponent;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.time.Instant;
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

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 계약이 {@code format: date-time} 이라고 적은 필드를 서버가 <b>{@link Instant} 로</b> 내는지
 * 본다 — 이슈 #248.
 *
 * <h2>왜 타입으로 재는가</h2>
 * <p>{@code format: date-time} 은 RFC3339 <b>오프셋</b>이 있어야 성립한다. 잭슨은
 * {@code LocalDateTime} 을 오프셋 없이 직렬화하고({@code "2026-09-03T08:33:44.533941"}),
 * 앱의 {@code DateTime.parse} 는 그런 문자열을 <b>기기 지역 시각</b>으로 읽는다 — 해외에
 * 있는 가족이 보면 그만큼 어긋난 시각이 그려진다.
 *
 * <p>도메인마다 HTTP 통합 테스트가 응답 본문을 보고 있지만, 그건 <b>그 도메인만</b> 본다.
 * 새 스키마에 {@code format: date-time} 이 하나 붙는 날 아무도 그 필드를 안 본다. 여기는
 * <b>계약을 목록의 출처로 삼아</b> 빠짐없이 훑는다.
 *
 * <h2>계약에만 있는 것도 목록에 적는다</h2>
 * <p>{@code ChatRoomMember} 는 계약에 있지만 서버가 만드는 응답이 없다 —
 * {@code ChatRoom.members} 가 미구현이다({@code ChatRoomResponse} javadoc). 그런 것을
 * {@link #NOT_PRODUCED} 에 <b>이유와 함께</b> 적는다. 구현이 붙는 날 이 목록에서 빼면 되고,
 * 안 빼면 {@link #everySchemaIsAccountedFor} 가 아니라 사람이 놓친다 — 그래서 이유를 적는다.
 *
 * <p>스프링을 안 띄운다(#21). 계약 파일과 클래스만 읽는다.
 */
class DateTimeFieldsAreInstantTest {

    /** 계약의 스키마 → 그 모양을 실제로 내보내는 타입. */
    private static final Map<String, Class<?>> PRODUCERS = Map.ofEntries(
            Map.entry("CareLog", com.heattrip.heat_trip_backend.care.dto.CareLogResponse.class),
            Map.entry("WalkNote", com.heattrip.heat_trip_backend.care.dto.WalkNoteResponse.class),
            Map.entry("ChatInvite", com.heattrip.heat_trip_backend.chat.ChatInviteView.class),
            Map.entry("ChatMessage", com.heattrip.heat_trip_backend.chatweb.ChatMessageResponse.class),
            Map.entry("ChatRoom", com.heattrip.heat_trip_backend.chatweb.ChatRoomResponse.class),
            Map.entry("Consent", com.heattrip.heat_trip_backend.consent.dto.ConsentResponse.class),
            Map.entry("Comment", com.heattrip.heat_trip_backend.community.dto.CommentResponse.class),
            Map.entry("Post", com.heattrip.heat_trip_backend.community.dto.PostResponse.class),
            Map.entry("Group", com.heattrip.heat_trip_backend.group.dto.GroupResponse.class),
            Map.entry("GroupMember", com.heattrip.heat_trip_backend.group.dto.GroupMemberResponse.class),
            Map.entry("ReportReceipt", com.heattrip.heat_trip_backend.moderation.ReportReceipt.class),

            Map.entry("User", com.heattrip.heat_trip_backend.user.dto.UserResponse.class),
            Map.entry("Walk", com.heattrip.heat_trip_backend.walk.dto.WalkResponse.class),
            Map.entry("Course", com.heattrip.heat_trip_backend.walk.course.CourseResponse.class),
            Map.entry("WalkSafetyNow", com.heattrip.heat_trip_backend.walksafety.dto.WalkSafetyNowResponse.class),
            Map.entry("WalkInput", com.heattrip.heat_trip_backend.walk.dto.WalkRequest.class));

    /**
     * 계약에는 있는데 <b>서버가 만드는 자리가 없는</b> 스키마. 이유를 반드시 적는다.
     */
    private static final Map<String, String> NOT_PRODUCED = Map.of(
            "ChatRoomMember",
            "ChatRoom.members 가 미구현이다 — 방 상세는 M2.6 의 다른 이슈이고, "
                    + "ChatRoomResponse 에 members 필드가 없다");

    /**
     * 계약이 선언했지만 그 타입에 없는 필드. <b>서버가 안 싣는다</b>는 뜻이고, 여기서는
     * 타입을 잴 것이 없다.
     */
    private static final Set<String> NOT_CARRIED = Set.of(
            // ChatRoomInvite 는 revoked_at 을 갖지만 뷰로 안 내보낸다 — 회수 여부는 410 으로
            // 답하고, 시각을 실으면 "언제 회수됐나" 가 코드를 들고 있는 쪽에 보인다.
            "ChatInvite.revokedAt");

    private static Map<String, Set<String>> contractFields;

    @BeforeAll
    static void readContract() {
        contractFields = dateTimeFieldsOf(readRepositoryFile("../docs/04-api/openapi.yaml"));
    }

    @Test
    @DisplayName("계약의 date-time 필드를 서버가 Instant 로 낸다 — LocalDateTime 이면 오프셋이 없다")
    void everyDateTimeFieldIsAnInstant() {
        assertThat(contractFields)
                .as("계약에서 format: date-time 을 하나도 못 읽었다면 이 검사는 아무것도 지키지 않는다")
                .isNotEmpty();

        List<String> offenders = new ArrayList<>();
        contractFields.forEach((schema, fields) -> {
            Class<?> producer = PRODUCERS.get(schema);
            if (producer == null) {
                return;   // 다음 테스트가 목록 누락을 잡는다
            }
            Map<String, Class<?>> declared = componentTypesOf(producer);
            for (String field : fields) {
                if (NOT_CARRIED.contains(schema + "." + field)) {
                    continue;
                }
                Class<?> type = declared.get(field);
                if (type == null) {
                    offenders.add("%s.%s → %s 에 그 필드가 없다 (NOT_CARRIED 에 이유와 함께 적거나 실어라)"
                            .formatted(schema, field, producer.getSimpleName()));
                } else if (type != Instant.class) {
                    offenders.add("%s.%s → %s.%s 가 %s 다"
                            .formatted(schema, field, producer.getSimpleName(), field,
                                    type.getSimpleName()));
                }
            }
        });

        assertThat(offenders)
                .as("""
                        잭슨은 LocalDateTime 을 오프셋 없이 직렬화한다. 계약의 \
                        format: date-time 은 RFC3339 오프셋을 요구하므로 그 순간 서버가 계약 \
                        위반이고, 앱은 그것을 기기 지역 시각으로 읽어 해외에 있는 가족에게 \
                        어긋난 시각을 그린다 (#248 · #247 · #209).""")
                .isEmpty();
    }

    @Test
    @DisplayName("date-time 을 가진 스키마를 하나도 안 빠뜨렸다 — 계약이 늘면 여기가 먼저 빨간불이다")
    void everySchemaIsAccountedFor() {
        Set<String> unaccounted = new LinkedHashSet<>(contractFields.keySet());
        unaccounted.removeAll(PRODUCERS.keySet());
        unaccounted.removeAll(NOT_PRODUCED.keySet());

        assertThat(unaccounted)
                .as("""
                        계약에 format: date-time 필드를 가진 스키마가 새로 생겼다. 그것을 내는 \
                        타입을 PRODUCERS 에 적거나, 서버가 안 만드는 것이면 NOT_PRODUCED 에 \
                        **이유와 함께** 적어라. 안 적으면 그 필드만 조용히 검사 밖에 남는다.""")
                .isEmpty();

        Set<String> stale = new LinkedHashSet<>(PRODUCERS.keySet());
        stale.addAll(NOT_PRODUCED.keySet());
        stale.removeAll(contractFields.keySet());

        assertThat(stale)
                .as("계약에서 사라진 스키마가 목록에 남아 있다 — 죽은 항목은 다음 사람을 헷갈리게 한다")
                .isEmpty();
    }

    // ─────────────────────────── 도구 ───────────────────────────

    /** 스키마 이름 → {@code format: date-time} 인 속성들. */
    private static Map<String, Set<String>> dateTimeFieldsOf(String yaml) {
        // 스네이크야멜로 읽으면 "어느 속성 아래의 format 인가" 를 잃는다 — 인라인 표기
        // ({ type: string, format: date-time })와 블록 표기가 섞여 있어서다. 두 줄 규칙이 더 곧다.
        Pattern schemaHead = Pattern.compile("^    ([A-Za-z][A-Za-z0-9]*):\\s*$");
        Pattern propertyHead = Pattern.compile("^        ([A-Za-z][A-Za-z0-9_]*):");

        Map<String, Set<String>> found = new LinkedHashMap<>();
        String schema = null;
        String property = null;
        boolean inSchemas = false;

        for (String line : yaml.split("\\R")) {
            if (line.startsWith("  schemas:")) {
                inSchemas = true;
                continue;
            }
            if (!inSchemas) {
                continue;
            }
            Matcher head = schemaHead.matcher(line);
            if (head.matches()) {
                schema = head.group(1);
                property = null;
                continue;
            }
            Matcher prop = propertyHead.matcher(line);
            if (prop.find()) {
                property = prop.group(1);
            }
            if (line.contains("format: date-time") && schema != null && property != null) {
                found.computeIfAbsent(schema, key -> new LinkedHashSet<>()).add(property);
            }
        }
        return found;
    }

    /** 레코드면 컴포넌트, 아니면 인스턴스 필드. {@code UserResponse} 는 롬복 클래스다. */
    private static Map<String, Class<?>> componentTypesOf(Class<?> type) {
        Map<String, Class<?>> declared = new LinkedHashMap<>();
        if (type.isRecord()) {
            for (RecordComponent component : type.getRecordComponents()) {
                declared.put(component.getName(), component.getType());
            }
        } else {
            for (Field field : type.getDeclaredFields()) {
                if (!java.lang.reflect.Modifier.isStatic(field.getModifiers())) {
                    declared.put(field.getName(), field.getType());
                }
            }
        }
        assertThat(declared)
                .as("%s 에서 필드를 하나도 못 읽었다면 이 검사는 아무것도 지키지 않는다",
                        type.getSimpleName())
                .isNotEmpty();
        return declared;
    }

    private static String readRepositoryFile(String relativePath) {
        try {
            return Files.readString(
                    TestProjectPaths.requireFile(relativePath), StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException(relativePath + " 를 읽지 못했다", e);
        }
    }
}
