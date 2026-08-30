package com.heattrip.heat_trip_backend.chat;

import com.heattrip.heat_trip_backend.support.ScratchDatabase;
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
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
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
 * <h2>네 자리를 잠근다</h2>
 * <ul>
 *   <li><b>§A 엔티티 매핑</b> — 리플렉션으로 필드가 실제로 가리키는 타입을 본다.</li>
 *   <li><b>§B 소스</b> — chat 의 main 소스 어디에도 다른 도메인 패키지 이름이 나오면 안 된다.</li>
 *   <li><b>§C 쿼리 문자열</b> — {@code FROM}·{@code JOIN} 뒤에 chat 밖의 표·엔티티가 오면 안 된다.</li>
 *   <li><b>§D 정본 DDL</b> — {@code mysql/init/01_schema.sql} 을 <b>빈 DB 에 실제로 적용해</b>
 *       {@code information_schema} 를 읽는다.</li>
 * </ul>
 *
 * <h2>세 번 뚫렸던 자리</h2>
 * <p>처음 판은 셋 다 우회가 가능했다. 무엇이 어떻게 뚫렸는지 적어 둔다 — 같은 판단을 다시
 * 하지 않기 위해서다.
 * <ol>
 *   <li><b>§B 가 {@code import } 로 시작하는 줄만 봤다.</b> 자바는 import 없이도 완전수식명으로
 *       어떤 타입이든 쓴다. 가정이 아니라 이 저장소의 평소 문체다 —
 *       {@code ExplorePlaceRepository:37} 의 {@code SELECT NEW com.heattrip...PlaceSummaryDto(} ,
 *       {@code GlobalExceptionHandler} 의
 *       {@code @ExceptionHandler(com.heattrip...ChatLimitViolationException.class)} 가 그렇다.
 *       그래서 <b>줄 단위 import 판정을 버리고 소스 전문에서 패키지 이름을 찾는다.</b>
 *       그러면 import·완전수식명·{@code Map<String, User>} 같은 제네릭 인자가 한 규칙에 들어온다.</li>
 *   <li><b>§C 가 없었다.</b> JPQL 은 엔티티 이름을, 네이티브는 표 이름을 <b>문자열로</b> 쓴다 —
 *       import 도 없고 필드도 아니라 §A·§B 어느 쪽에도 안 걸린다. #86 이 이름 붙인 실패 모드
 *       ("chat_message 에서 users 를 조인")가 정확히 이 모양이다.</li>
 *   <li><b>§D 가 {@code CREATE TABLE} 블록 안만 읽는 정규식이었다.</b> 손으로 스키마를 고치는
 *       사람이 가장 자연스럽게 쓰는 문법이 {@code ALTER TABLE ... ADD CONSTRAINT} 인데 그게
 *       사각지대였고, {@code UNIQUE} 는 아예 안 봤다. 정규식을 늘리는 대신 <b>파일을 빈 DB 에
 *       적용해서 결과를 읽는</b> 쪽으로 바꿨다 — 문법 형태와 무관해진다.</li>
 * </ol>
 *
 * <h2>ArchUnit 을 넣지 않은 이유</h2>
 * <p>이 저장소에 ArchUnit 도 Spring Modulith 도 없다({@code build.gradle} 확인). 새 의존성
 * 하나를 들이는 값과 여기서 얻는 것을 비교했다.
 * <ul>
 *   <li>검사할 대상이 <b>한 패키지</b>이고 규칙이 넷이다. ArchUnit 의 강점(수십 개 규칙,
 *       레이어 그래프)이 쓰이지 않는다.</li>
 *   <li>이 저장소에는 이미 소스를 훑는 테스트가 여럿 있다 —
 *       {@code IntegrationTestsRunOnMySqlTest}(베이스 클래스 상속 강제)·{@code DocDriftTest}·
 *       {@code SpecTestInputsDeclaredTest}. 읽는 사람이 처음 보는 도구가 아니다.</li>
 *   <li>ArchUnit 은 <b>바이트코드</b>만 본다. §C 의 쿼리 문자열도 §D 의
 *       {@code mysql/init/01_schema.sql} 도 바이트코드에 없다.</li>
 * </ul>
 *
 * <h2>스프링을 띄우지 않는다</h2>
 * <p>§D 는 공유 컨테이너에 일회용 데이터베이스를 하나 만들어 쓴다({@link ScratchDatabase}).
 * 스프링 컨텍스트는 하나도 늘지 않는다(#21).
 */
class ChatBoundaryArchitectureTest {

    private static final String CHAT_PACKAGE = "com.heattrip.heat_trip_backend.chat";
    private static final String APP_PACKAGE = "com.heattrip.heat_trip_backend";
    private static final String CHAT_SOURCE_DIR =
            "src/main/java/com/heattrip/heat_trip_backend/chat";

    /** 경계 밖으로 나가면 안 되는 JPA 연관 애너테이션. */
    private static final List<Class<? extends Annotation>> ASSOCIATION_ANNOTATIONS = List.of(
            ManyToOne.class, OneToOne.class, OneToMany.class, ManyToMany.class,
            JoinColumn.class, JoinColumns.class, JoinTable.class);

    /**
     * 우리 패키지 이름 중 {@code chat} 이 아닌 것. {@code (?!chat\b)} 라서
     * {@code ...chat;}(패키지 선언) 과 {@code ...chat.entity} 는 빠지고
     * {@code ...chatty} 같은 다른 패키지는 걸린다.
     */
    private static final Pattern OUTSIDE_PACKAGE = Pattern.compile(
            "\\b" + Pattern.quote(APP_PACKAGE) + "\\.(?!chat\\b)(\\w+)");

    // ─────────────────── A. 엔티티 매핑 (리플렉션) ───────────────────

    @Test
    @DisplayName("chat 엔티티의 어떤 필드도 chat 밖의 우리 클래스를 가리키지 않는다")
    void chatEntities_referenceNothingOutsideTheChatPackage() throws Exception {
        List<Class<?>> entities = chatEntities();

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
        long associations = chatEntities().stream()
                .flatMap(c -> Arrays.stream(c.getDeclaredFields()))
                .filter(f -> !associationNamesOn(f).isEmpty())
                .count();

        assertThat(associations)
                .as("chat_room_member.room_id 와 chat_room_invite.room_id 는 chat_room 을 가리키는 "
                        + "FK 다. 둘 다 사라졌다면 경계 안쪽까지 끊어진 것이다")
                .isGreaterThanOrEqualTo(2);
    }

    // ─────────────────── B. 소스 전문 (완전수식명 포함) ───────────────────

    @Test
    @DisplayName("chat 의 main 소스 어디에도 다른 도메인 패키지 이름이 없다 — origin_ref 를 역참조할 방법 자체를 없앤다")
    void chatSources_nameNoOtherDomainPackage() throws IOException {
        List<String> offenders = new ArrayList<>();

        for (Path file : chatSourceFiles()) {
            String[] lines = stripComments(Files.readString(file, StandardCharsets.UTF_8))
                    .split("\\R", -1);
            for (int i = 0; i < lines.length; i++) {
                Matcher m = OUTSIDE_PACKAGE.matcher(lines[i]);
                while (m.find()) {
                    offenders.add("%s:%d  %s".formatted(
                            file.getFileName(), i + 1, lines[i].strip()));
                }
            }
        }

        assertThat(offenders)
                .as("""
                        origin_kind/origin_ref 는 불투명 문자열 쌍이다. chat 이 그 값을 파싱하거나 \
                        역참조하거나 존재를 확인하는 순간 경계가 사라진다.
                        import 줄만 보면 완전수식명 한 줄로 뚫린다 — 이 저장소는 실제로 완전수식명을 \
                        쓴다(ExplorePlaceRepository·GlobalExceptionHandler). 그래서 소스 전문을 본다.
                        방향은 한쪽이다 — GlobalExceptionHandler 가 chat 의 예외를 부르는 것은 맞고, \
                        chat 이 밖을 부르는 것은 아니다 (ADR-0011 결정 4).""")
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

    // ─────────────────── C. 쿼리 문자열 (JPQL · 네이티브) ───────────────────

    @Test
    @DisplayName("chat 의 쿼리는 chat 밖의 표·엔티티를 조인하지 않는다 — FK 가 없어도 조인 하나면 경계가 사라진다")
    void chatQueries_joinNothingOutsideTheBoundary() throws Exception {
        Set<String> entityNames = chatEntityNames();
        List<String> offenders = new ArrayList<>();

        for (Path file : chatSourceFiles()) {
            String source = stripComments(Files.readString(file, StandardCharsets.UTF_8));
            for (String query : queryLiteralsIn(source)) {
                for (String outsider : outsideReferencesIn(query, entityNames)) {
                    offenders.add("%s  →  %s   (%s)".formatted(
                            file.getFileName(), outsider, query.strip()));
                }
            }
        }

        assertThat(offenders)
                .as("""
                        JPQL 은 엔티티 이름을, 네이티브는 표 이름을 문자열로 쓴다 — import 도 필드도 \
                        아니라 §A·§B 어느 쪽에도 안 걸린다.
                        FK 가 없어도 조인 하나면 chat 이 남의 스키마에 묶이고, 되돌리려 할 때는 이미 \
                        쿼리가 여럿이다 (📌 #86 원칙 6 이 이 이슈를 만든 근거로 든 문장이 그것이다).
                        chat 표끼리의 조인은 정당하다 — 금지하는 것은 FROM·JOIN 뒤에 chat_ 로 시작하지 \
                        않는 표나 chat 엔티티가 아닌 이름이 오는 것뿐이다.""")
                .isEmpty();
    }

    @Test
    @DisplayName("그 쿼리 검사가 실제로 잡는다 — chat 에 @Query 가 0개여도 장치가 살아 있는지 본다")
    void theQueryScannerActuallyCatchesACrossBoundaryJoin() throws Exception {
        Set<String> entityNames = chatEntityNames();

        // 막아야 하는 것 — 실제로 심어서 통과하는 것을 확인했던 두 모양이다.
        assertThat(outsideReferencesIn(
                "SELECT u.nickname FROM chat_room_member m JOIN users u ON u.id = m.user_id",
                entityNames))
                .as("네이티브 조인이 안 걸리면 이 게이트는 아무것도 지키지 않는다")
                .containsExactly("users");
        assertThat(outsideReferencesIn(
                "select u.nickname from ChatRoomMember m join User u on u.id = m.userId",
                entityNames))
                .as("JPQL 조인이 안 걸리면 이 게이트는 아무것도 지키지 않는다")
                .containsExactly("User");
        assertThat(outsideReferencesIn("UPDATE users SET nickname = ?1", entityNames))
                .as("조회만 막고 쓰기를 열어 두면 같은 결합이 반대 방향으로 생긴다")
                .containsExactly("users");
        assertThat(outsideReferencesIn("SELECT * FROM heat_trip.users", entityNames))
                .as("스키마를 앞에 붙이는 것도 별칭 경로식이 아니다")
                .containsExactly("heat_trip.users");

        // 통과해야 하는 것 — 시끄러운 게이트는 지워진다. chat 안쪽 조인은 정당하다.
        assertThat(outsideReferencesIn(
                "SELECT i.code FROM chat_room_invite i JOIN chat_room r ON r.id = i.room_id",
                entityNames))
                .as("chat 표끼리의 네이티브 조인")
                .isEmpty();
        assertThat(outsideReferencesIn(
                "select m from ChatRoomMember m join fetch m.room r where r.id = :id",
                entityNames))
                .as("별칭으로 시작하는 경로식은 §A 가 이미 잠근다 — join fetch 도 같다")
                .isEmpty();
        assertThat(outsideReferencesIn(
                "UPDATE chat_room SET last_seq = LAST_INSERT_ID(last_seq + 1) WHERE id = ?1",
                entityNames))
                .as("#78 이 넣을 발급 문장이 여기서 걸리면 안 된다")
                .isEmpty();
    }

    @Test
    @DisplayName("그 쿼리 검사가 쿼리를 실제로 뽑아낸다 — 문자열을 하나도 못 찾으면 공허하게 통과한다")
    void theQueryScannerActuallyFindsQueryLiterals() {
        assertThat(queryLiteralsIn("""
                @Query(value = "SELECT u.nickname FROM chat_room_member m "
                        + "JOIN users u ON u.id = m.user_id", nativeQuery = true)
                """))
                .as("이어 붙인 문자열을 못 이으면 FROM 과 표 이름이 갈라져 아무것도 못 잡는다")
                .containsExactly(
                        "SELECT u.nickname FROM chat_room_member m JOIN users u ON u.id = m.user_id");

        assertThat(queryLiteralsIn("String sql = \"\"\"\nselect m from ChatRoomMember m\n\"\"\";"))
                .as("텍스트 블록으로 적은 쿼리도 봐야 한다")
                .hasSize(1);

        assertThat(queryLiteralsIn("throw new IllegalStateException(\"방에서 나갈 수 없다\");"))
                .as("쿼리가 아닌 문자열까지 훑으면 오탐으로 이 게이트가 지워진다")
                .isEmpty();
    }

    // ─────────────────── D. 정본 DDL (빈 DB 에 실제로 적용) ───────────────────

    @Test
    @DisplayName("정본 스키마를 빈 DB 에 적용하면 chat_* 의 FK 는 chat_room 을 가리키는 둘뿐이다")
    void committedSchema_hasNoForeignKeyOutOfChat() throws Exception {
        try (ScratchDatabase db = ScratchDatabase.withCommittedSchema()) {
            assertThat(db.queryStrings("""
                    SELECT CONCAT(table_name, ' → ', referenced_table_name)
                    FROM information_schema.referential_constraints
                    WHERE constraint_schema = DATABASE() AND table_name LIKE 'chat\\_%'
                    ORDER BY table_name, constraint_name
                    """))
                    .as("""
                            엔티티가 아니라 커밋된 DDL 을 손으로 고쳐도 경계는 똑같이 깨진다. \
                            운영 DB 를 새로 세우는 파일이 그거라서다 (#58).
                            파일 텍스트가 아니라 **적용한 결과**를 읽는 이유는 정규식이 \
                            ALTER TABLE ... ADD CONSTRAINT 를 못 봤기 때문이다 — 손으로 고치는 사람이 \
                            가장 자연스럽게 쓰는 문법이 그것이다.
                            둘보다 적으면 경계 안쪽 FK 까지 끊어진 것이고, 다른 이름이 끼면 \
                            users·family_group·dog 로 나간 것이다 (ADR-0011 결정 4).""")
                    .containsExactlyInAnyOrder(
                            "chat_room_invite → chat_room",
                            "chat_room_member → chat_room");
        }
    }

    @Test
    @DisplayName("정본 스키마의 chat_* 표에 UNIQUE 제약이 컬럼 쌍 그대로 살아 있다")
    void committedSchema_keepsTheUniqueConstraintsThatMakeTheseTablesCorrect() throws Exception {
        try (ScratchDatabase db = ScratchDatabase.withCommittedSchema()) {
            assertThat(uniqueColumnSets(db, "chat_room"))
                    .as("""
                            "이 그룹의 방이 이미 있나 보고 없으면 만든다" 를 조건문으로 두면 두 요청이 \
                            동시에 통과해 같은 그룹에 방이 둘 생긴다. 그것을 막는 것은 이 제약 하나다 \
                            (📌 #86 원칙 5 — 확인-후-쓰기는 DB 유니크 제약으로 받친다).
                            ddl-auto=validate 도 SchemaDdlDriftTest 도 UNIQUE 를 안 본다. 이 파일에서 \
                            한 줄을 지운 채 세운 운영 DB 는 아무 데서도 안 걸린다.""")
                    .contains("origin_kind,origin_ref");
            assertThat(uniqueColumnSets(db, "chat_room_member"))
                    .as("한 사람이 같은 방에 멤버십 두 줄을 갖는 순간 미읽음 기준이 갈린다")
                    .contains("room_id,user_id");
            assertThat(uniqueColumnSets(db, "chat_room_invite"))
                    .as("코드 1개 = 행 1개가 깨지면 어느 행을 줄지 미정이 된다 "
                            + "(refresh_token.token_hash 와 같은 계열)")
                    .contains("code");
        }
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

    private static List<Class<?>> chatEntities() throws Exception {
        return chatClasses().stream().filter(c -> c.isAnnotationPresent(Entity.class)).toList();
    }

    /** JPQL 의 {@code FROM} 뒤에 올 수 있는 이름 — chat 엔티티의 단순 이름. */
    private static Set<String> chatEntityNames() throws Exception {
        Set<String> names = new LinkedHashSet<>();
        for (Class<?> entity : chatEntities()) {
            names.add(entity.getSimpleName());
        }
        if (names.isEmpty()) {
            throw new IllegalStateException("chat 엔티티가 하나도 없다 — 쿼리 검사가 공허해진다.");
        }
        return names;
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

    /** 이름이 붙은 UNIQUE 인덱스의 컬럼 목록을 {@code "a,b"} 형태로. PRIMARY 도 포함된다. */
    private static List<String> uniqueColumnSets(ScratchDatabase db, String table) throws Exception {
        return db.queryStrings("""
                SELECT GROUP_CONCAT(column_name ORDER BY seq_in_index)
                FROM information_schema.statistics
                WHERE table_schema = DATABASE() AND table_name = '%s' AND non_unique = 0
                GROUP BY index_name
                """.formatted(table));
    }

    // ── 쿼리 문자열 뽑기 ──

    /** 텍스트 블록. 먼저 떼어 내야 아래 일반 문자열 정규식이 헷갈리지 않는다. */
    private static final Pattern TEXT_BLOCK = Pattern.compile("(?s)\"\"\"(.*?)\"\"\"");

    /** 한 줄짜리 문자열 리터럴. 이스케이프된 따옴표를 넘어간다. */
    private static final Pattern STRING_LITERAL = Pattern.compile("\"((?:\\\\.|[^\"\\\\])*)\"");

    /** {@code "a" + "b"} 를 잇는다. 안 이으면 FROM 과 표 이름이 갈라져 아무것도 못 잡는다. */
    private static final Pattern CONCATENATION = Pattern.compile("\"\\s*\\+\\s*\"");

    /** 쿼리로 볼 문자열 — 동사와 절이 함께 있어야 한다. 산문 메시지를 훑지 않으려는 것이다. */
    private static final Pattern LOOKS_LIKE_A_QUERY = Pattern.compile(
            "(?is)^(?=.*\\b(select|insert|update|delete)\\b)(?=.*\\b(from|join|into|set)\\b).*$");

    /**
     * 소스에서 <b>쿼리로 보이는</b> 문자열만 뽑는다.
     *
     * <p>주석은 호출부가 먼저 걷는다. 이어 붙인 문자열을 잇고, 텍스트 블록도 함께 본다 —
     * {@code @Query} 뿐 아니라 {@code createNativeQuery("…")} 도 같은 그물에 들어온다.
     */
    private static List<String> queryLiteralsIn(String source) {
        List<String> out = new ArrayList<>();
        String rest = source;

        Matcher blocks = TEXT_BLOCK.matcher(rest);
        StringBuilder withoutBlocks = new StringBuilder();
        int last = 0;
        while (blocks.find()) {
            withoutBlocks.append(rest, last, blocks.start());
            collectIfQuery(blocks.group(1), out);
            last = blocks.end();
        }
        withoutBlocks.append(rest.substring(last));

        Matcher literals = STRING_LITERAL.matcher(
                CONCATENATION.matcher(withoutBlocks).replaceAll(""));
        while (literals.find()) {
            collectIfQuery(literals.group(1), out);
        }
        return out;
    }

    private static void collectIfQuery(String candidate, List<String> out) {
        String flattened = candidate.replaceAll("\\s+", " ").strip();
        if (LOOKS_LIKE_A_QUERY.matcher(flattened).matches()) {
            out.add(flattened);
        }
    }

    // ── 쿼리 안에서 경계 밖 이름 찾기 ──

    /** {@code FROM}·{@code JOIN}·{@code UPDATE}·{@code INSERT INTO} 뒤의 이름과 그 별칭. */
    private static final Pattern TABLE_POSITION = Pattern.compile(
            "(?is)\\b(?:from|join|update|insert\\s+into)\\s+"
                    + "([A-Za-z_][\\w$]*(?:\\.[A-Za-z_][\\w$]*)*)"
                    + "(?:\\s+(?:as\\s+)?([A-Za-z_][\\w$]*))?");

    /** 별칭 자리에 올 수 있는 예약어. 이것들을 별칭으로 오해하면 경로식 검사가 헐거워진다. */
    private static final Set<String> CLAUSE_KEYWORDS = Set.of(
            "on", "where", "join", "inner", "left", "right", "outer", "cross", "full",
            "group", "order", "having", "limit", "offset", "set", "values", "union",
            "and", "or", "as", "using", "fetch", "select", "from", "into");

    /**
     * 쿼리에서 <b>chat 경계 밖</b>을 가리키는 이름을 모은다. 정확히 이것만 금지한다.
     *
     * <ol>
     *   <li>{@code chat_} 으로 시작하는 표 이름 — 통과(네이티브 SQL).</li>
     *   <li>chat 엔티티의 단순 이름 — 통과(JPQL).</li>
     *   <li>같은 쿼리가 선언한 별칭으로 시작하는 경로식({@code m.room}) — 통과.
     *       그 경로가 무엇을 가리키는지는 §A 가 리플렉션으로 이미 잠갔다.</li>
     *   <li>나머지 전부 — 위반.</li>
     * </ol>
     */
    private static List<String> outsideReferencesIn(String query, Set<String> chatEntityNames) {
        String normalized = query
                .replaceAll("(?i)\\bon\\s+duplicate\\s+key\\s+update\\b", "on duplicate key")
                .replaceAll("(?i)\\bjoin\\s+fetch\\b", "join");

        Set<String> aliases = new LinkedHashSet<>();
        Matcher aliasScan = TABLE_POSITION.matcher(normalized);
        while (aliasScan.find()) {
            String alias = aliasScan.group(2);
            if (alias != null && !CLAUSE_KEYWORDS.contains(alias.toLowerCase())) {
                aliases.add(alias);
            }
        }

        List<String> offenders = new ArrayList<>();
        Matcher targets = TABLE_POSITION.matcher(normalized);
        while (targets.find()) {
            String name = targets.group(1);
            if (CLAUSE_KEYWORDS.contains(name.toLowerCase())) {
                continue;
            }
            if (name.contains(".")) {
                if (!aliases.contains(name.substring(0, name.indexOf('.')))) {
                    offenders.add(name);
                }
                continue;
            }
            if (!name.toLowerCase().startsWith("chat_") && !chatEntityNames.contains(name)) {
                offenders.add(name);
            }
        }
        return offenders;
    }

    /**
     * 주석을 걷는다 — 주석 속 예시 문구가 검사에 걸리면 그 테스트는 며칠 안에 지워진다.
     *
     * <p>줄 수는 그대로 둔다. 위반을 파일:줄 로 가리켜야 고칠 자리를 찾는다.
     */
    private static String stripComments(String source) {
        Matcher m = Pattern.compile("(?s)/\\*.*?\\*/|//[^\\n]*").matcher(source);
        StringBuilder out = new StringBuilder(source.length());
        int last = 0;
        while (m.find()) {
            out.append(source, last, m.start());
            out.append("\n".repeat((int) m.group().chars().filter(c -> c == '\n').count()));
            last = m.end();
        }
        return out.append(source.substring(last)).toString();
    }
}
