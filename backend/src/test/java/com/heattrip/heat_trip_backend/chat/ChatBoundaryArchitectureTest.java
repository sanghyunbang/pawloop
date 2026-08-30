package com.heattrip.heat_trip_backend.chat;

import com.heattrip.heat_trip_backend.support.TestProjectPaths;

import jakarta.persistence.Entity;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.JoinColumns;
import jakarta.persistence.JoinTable;
import jakarta.persistence.ManyToMany;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToMany;
import jakarta.persistence.OneToOne;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.lang.annotation.Annotation;
import java.lang.reflect.Field;
import java.lang.reflect.ParameterizedType;
import java.lang.reflect.Type;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * chat 경계 밖으로 나가는 참조가 <b>0개</b>인지 잠근다 — 이슈 #74, 근거 ADR-0011 결정 4.
 *
 * <h2>왜 이 테스트가 필요한가</h2>
 * <p>"chat 은 {@code users}·{@code family_group}·{@code dog} 에 FK 를 걸지 않는다" 는 결정은
 * 문서에만 적혀 있으면 몇 달 뒤 사라진다. 📌 #86 원칙 6 이 "규칙은 코드로 지킨다" 를 적으면서
 * 바로 이 경우를 예로 들었다 — <b>"몇 달 뒤 누군가 chat_message 에서 users 를 조인하고,
 * 설계가 조용히 사라진다."</b> 그래서 규칙과 같은 커밋에 장치를 넣는다.
 *
 * <p>기존 게이트로는 안 잡힌다. {@code SchemaDdlDriftTest} 의 {@code describe()} 는
 * {@code table_name}·{@code column_name}·{@code column_type}·{@code is_nullable} 넷만 읽는다 —
 * <b>FK 도 UNIQUE 도 인덱스도 안 본다.</b> {@code ddl-auto=validate} 도 마찬가지다.
 *
 * <h2>ArchUnit 을 넣지 않은 이유</h2>
 * <p>이 저장소에 ArchUnit 도 Spring Modulith 도 없다({@code build.gradle} 확인). 새 의존성
 * 하나를 들이는 값과 여기서 얻는 것을 비교했다.
 * <ul>
 *   <li>검사할 대상이 <b>한 패키지</b>이고 규칙이 셋이다. ArchUnit 의 강점(수십 개 규칙,
 *       레이어 그래프)이 쓰이지 않는다.</li>
 *   <li>이 저장소에는 이미 소스를 훑는 테스트가 여럿 있다 —
 *       {@code IntegrationTestsRunOnMySqlTest}(베이스 클래스 상속 강제)·{@code DocDriftTest}·
 *       {@code SpecTestInputsDeclaredTest}. 읽는 사람이 처음 보는 도구가 아니다.</li>
 *   <li>ArchUnit 은 <b>바이트코드</b>만 본다. 아래 §C 가 검사하는 것은 손으로 고칠 수 있는
 *       {@code mysql/init/01_schema.sql} 이라 어차피 별도 장치가 필요하다.</li>
 * </ul>
 * <p>대신 문자열 grep 으로 때우지 않았다. §A 는 <b>리플렉션</b>으로 실제 매핑을 본다 —
 * {@code @JoinColumn} 이라는 글자를 찾는 것과 "이 필드가 가리키는 타입이 chat 밖인가" 는
 * 다른 질문이고, 뒤엣것만 규칙을 실제로 표현한다.
 *
 * <h2>스프링을 띄우지 않는다</h2>
 * <p>클래스와 파일만 읽으면 되는 일이라 순수 JUnit 이다. 애너테이션이 한 글자만 달라도
 * 컨텍스트 캐시 키가 갈라져 하나 더 뜬다(#21) — 여기서 그걸 늘릴 이유가 없다.
 */
class ChatBoundaryArchitectureTest {

    private static final String CHAT_PACKAGE = "com.heattrip.heat_trip_backend.chat";
    private static final String APP_PACKAGE = "com.heattrip.heat_trip_backend";
    private static final String CHAT_SOURCE_DIR =
            "src/main/java/com/heattrip/heat_trip_backend/chat";
    private static final String COMMITTED_SCHEMA = "mysql/init/01_schema.sql";

    /** 경계 밖으로 나가면 안 되는 JPA 연관 애너테이션. */
    private static final List<Class<? extends Annotation>> ASSOCIATION_ANNOTATIONS = List.of(
            ManyToOne.class, OneToOne.class, OneToMany.class, ManyToMany.class,
            JoinColumn.class, JoinColumns.class, JoinTable.class);

    // ─────────────────── A. 엔티티 매핑 (리플렉션) ───────────────────

    @Test
    @DisplayName("chat 엔티티의 어떤 필드도 chat 밖의 우리 클래스를 가리키지 않는다")
    void chatEntities_referenceNothingOutsideTheChatPackage() throws Exception {
        List<Class<?>> entities = chatClasses().stream()
                .filter(c -> c.isAnnotationPresent(Entity.class))
                .toList();

        assertThat(entities)
                .as("chat 엔티티를 하나도 못 찾았다면 이 검사는 아무것도 지키지 않는다 — "
                        + "패키지가 옮겨졌는지 확인하라")
                .isNotEmpty();

        List<String> offenders = new ArrayList<>();
        for (Class<?> entity : entities) {
            for (Field field : entity.getDeclaredFields()) {
                if (field.isSynthetic()) {
                    continue;
                }
                Class<?> target = targetTypeOf(field);
                if (target == null || !target.getName().startsWith(APP_PACKAGE)) {
                    continue;   // String·Long·LocalDateTime 등 우리 클래스가 아닌 것
                }
                if (target.getName().startsWith(CHAT_PACKAGE + ".")) {
                    continue;   // 경계 안. FK 를 걸어도 된다
                }
                offenders.add("%s.%s → %s%s".formatted(
                        entity.getSimpleName(), field.getName(), target.getName(),
                        associationNamesOn(field).isEmpty()
                                ? ""
                                : " " + associationNamesOn(field)));
            }
        }

        assertThat(offenders)
                .as("""
                        chat 엔티티가 경계 밖을 가리킨다. users·family_group·dog 은 값(Long)으로만 든다 \
                        — refresh_token.user_id(#9)가 같은 방식이다.
                        FK 를 걸면 탈퇴 경로가 DB 삭제 순서에 묶이고, ON DELETE CASCADE 면 탈퇴 한 번에 \
                        남의 대화·멤버십이 사라진다 (ADR-0011 결정 4).""")
                .isEmpty();
    }

    @Test
    @DisplayName("chat 엔티티에 남아 있는 연관 매핑은 전부 chat 안쪽을 가리킨다 — 경계 안 FK 는 건다")
    void chatEntities_stillKeepTheirInsideBoundaryForeignKeys() throws Exception {
        // 위 검사가 "연관 매핑을 전부 지워도" 통과한다는 것을 막는다.
        // 방이 지워지면 멤버십·초대도 함께 지워져야 하고, 그건 FK 가 하는 일이다.
        long associations = chatClasses().stream()
                .filter(c -> c.isAnnotationPresent(Entity.class))
                .flatMap(c -> Arrays.stream(c.getDeclaredFields()))
                .filter(f -> !associationNamesOn(f).isEmpty())
                .count();

        assertThat(associations)
                .as("chat_room_member.room_id 와 chat_room_invite.room_id 는 chat_room 을 가리키는 "
                        + "FK 다. 둘 다 사라졌다면 경계 안쪽까지 끊어진 것이다")
                .isGreaterThanOrEqualTo(2);
    }

    // ─────────────────── B. import (소스 스캔) ───────────────────

    @Test
    @DisplayName("chat 의 main 소스는 다른 도메인 패키지를 import 하지 않는다 — origin_ref 를 역참조할 방법 자체를 없앤다")
    void chatSources_importNoOtherDomainPackage() throws IOException {
        List<String> offenders = new ArrayList<>();

        for (Path file : chatSourceFiles()) {
            String source = Files.readString(file, StandardCharsets.UTF_8);
            for (String line : source.split("\\R")) {
                String stripped = line.strip();
                if (!stripped.startsWith("import ")) {
                    continue;
                }
                String imported = stripped
                        .substring("import ".length())
                        .replace("static ", "")
                        .replace(";", "")
                        .strip();
                if (imported.startsWith(APP_PACKAGE) && !imported.startsWith(CHAT_PACKAGE + ".")) {
                    offenders.add(file.getFileName() + " → " + imported);
                }
            }
        }

        assertThat(offenders)
                .as("""
                        origin_kind/origin_ref 는 불투명 문자열 쌍이다. chat 이 그 값을 파싱하거나 \
                        역참조하거나 존재를 확인하는 순간 경계가 사라진다.
                        그걸 하려면 반드시 다른 도메인의 리포지터리·엔티티를 import 해야 하므로, \
                        import 를 막는 것이 그 행동을 막는 가장 좁은 자리다.
                        방향은 한쪽이다 — GlobalExceptionHandler 가 chat 의 예외를 import 하는 것은 맞고, \
                        chat 이 밖을 import 하는 것은 아니다 (ADR-0011 결정 4).""")
                .isEmpty();
    }

    @Test
    @DisplayName("chat 은 오류 봉투를 따로 만들지 않는다 — GlobalExceptionHandler.ErrorResponse 하나다")
    void chatSources_doNotCopyTheErrorEnvelope() throws IOException {
        List<String> offenders = new ArrayList<>();

        for (Path file : chatSourceFiles()) {
            String source = stripComments(Files.readString(file, StandardCharsets.UTF_8));
            if (source.contains("traceId")) {
                offenders.add(file.getFileName() + " 이 traceId 를 직접 든다");
            }
            if (source.matches("(?s).*\\b(record|class)\\s+\\w*Error(Response|Body)\\b.*")) {
                offenders.add(file.getFileName() + " 이 오류 봉투를 새로 선언한다");
            }
        }

        assertThat(offenders)
                .as("봉투는 GlobalExceptionHandler.ErrorResponse({error:{code,message,traceId}}) 하나다. "
                        + "ApiRateLimitFilter 도 그걸 그대로 재사용한다 — 사본을 만들면 한쪽만 낡는다")
                .isEmpty();
    }

    // ─────────────────── C. 정본 DDL (파일 스캔) ───────────────────

    @Test
    @DisplayName("정본 스키마의 chat_* 표에는 chat 경계 밖을 가리키는 FOREIGN KEY 가 없다")
    void committedSchema_hasNoForeignKeyOutOfChat() throws IOException {
        Map<String, String> chatTables = chatTableDefinitions();

        assertThat(chatTables.keySet())
                .as("정본 스키마에 세 표가 있어야 이 검사가 의미를 갖는다 (%s)", COMMITTED_SCHEMA)
                .contains("chat_room", "chat_room_member", "chat_room_invite");

        Pattern references = Pattern.compile("references\\s+`?(\\w+)`?", Pattern.CASE_INSENSITIVE);
        List<String> offenders = new ArrayList<>();
        int seen = 0;

        for (var entry : chatTables.entrySet()) {
            Matcher m = references.matcher(entry.getValue());
            while (m.find()) {
                seen++;
                String referenced = m.group(1).toLowerCase();
                if (!referenced.startsWith("chat_")) {
                    offenders.add(entry.getKey() + " → " + referenced);
                }
            }
        }

        assertThat(offenders)
                .as("""
                        엔티티가 아니라 커밋된 DDL 을 손으로 고쳐도 경계는 똑같이 깨진다. \
                        운영 DB 를 새로 세우는 파일이 그거라서다 (#58).
                        users·family_group·dog 로 나가는 FK 는 0개여야 한다 (ADR-0011 결정 4).""")
                .isEmpty();
        assertThat(seen)
                .as("chat_room_member·chat_room_invite → chat_room FK 두 개는 있어야 한다. "
                        + "0 이면 이 검사가 빈 문자열을 훑고 통과한 것이다")
                .isGreaterThanOrEqualTo(2);
    }

    // ─────────────────────────── 지그 ───────────────────────────

    /** chat 패키지의 main 소스 파일 전부. 하나도 없으면 던진다 — 빈 목록을 훑고 통과하지 않는다. */
    private static List<Path> chatSourceFiles() throws IOException {
        Path root = TestProjectPaths.requireDirectory(CHAT_SOURCE_DIR);
        try (Stream<Path> files = Files.walk(root)) {
            List<Path> found = files.filter(p -> p.toString().endsWith(".java")).sorted().toList();
            if (found.isEmpty()) {
                throw new IllegalStateException(root + " 아래에 자바 소스가 없다.");
            }
            return found;
        }
    }

    /** chat 패키지의 클래스를 소스 파일 목록에서 그대로 읽어 온다 — 새 엔티티가 자동으로 포함된다. */
    private static List<Class<?>> chatClasses() throws Exception {
        Path root = TestProjectPaths.requireDirectory(CHAT_SOURCE_DIR);
        List<Class<?>> classes = new ArrayList<>();
        for (Path file : chatSourceFiles()) {
            String relative = root.relativize(file).toString()
                    .replace('\\', '.').replace('/', '.');
            String simple = relative.substring(0, relative.length() - ".java".length());
            classes.add(Class.forName(CHAT_PACKAGE + "." + simple));
        }
        return classes;
    }

    /** 필드가 실제로 가리키는 타입. 컬렉션이면 원소 타입을 본다. */
    private static Class<?> targetTypeOf(Field field) {
        if (Collection.class.isAssignableFrom(field.getType())) {
            Type generic = field.getGenericType();
            if (generic instanceof ParameterizedType parameterized) {
                Type[] args = parameterized.getActualTypeArguments();
                if (args.length == 1 && args[0] instanceof Class<?> element) {
                    return element;
                }
            }
            return null;
        }
        return field.getType();
    }

    private static List<String> associationNamesOn(Field field) {
        return ASSOCIATION_ANNOTATIONS.stream()
                .filter(field::isAnnotationPresent)
                .map(a -> "@" + a.getSimpleName())
                .toList();
    }

    /** 정본 스키마에서 {@code chat_} 으로 시작하는 표의 본문만 뽑는다(표 이름 → 본문). */
    private static Map<String, String> chatTableDefinitions() throws IOException {
        String sql = Files.readString(
                TestProjectPaths.requireFile(COMMITTED_SCHEMA), StandardCharsets.UTF_8);
        Pattern create = Pattern.compile(
                "create\\s+table\\s+`?(chat_\\w+)`?\\s*\\((.*?)\\n\\)\\s*engine",
                Pattern.CASE_INSENSITIVE | Pattern.DOTALL);
        Matcher m = create.matcher(sql);
        Map<String, String> out = new java.util.LinkedHashMap<>();
        while (m.find()) {
            out.put(m.group(1).toLowerCase(), m.group(2));
        }
        return out;
    }

    /** 주석을 걷는다 — 주석 속 예시 문구가 검사에 걸리면 그 테스트는 며칠 안에 지워진다. */
    private static String stripComments(String source) {
        return source
                .replaceAll("(?s)/\\*.*?\\*/", "")
                .replaceAll("//[^\\n]*", "");
    }
}
