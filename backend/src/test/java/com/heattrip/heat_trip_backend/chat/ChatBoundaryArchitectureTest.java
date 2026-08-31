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
 * <h2>다섯 자리를 잠근다</h2>
 * <ul>
 *   <li><b>§A 엔티티 매핑</b> — 리플렉션으로 필드가 실제로 가리키는 타입을 본다.</li>
 *   <li><b>§B 소스</b> — chat 의 main 소스 어디에도 다른 도메인 패키지 이름이 나오면 안 된다.</li>
 *   <li><b>§C 쿼리 문자열</b> — {@code FROM}·{@code JOIN} 뒤에 chat 밖의 표·엔티티가 오면 안 된다.</li>
 *   <li><b>§D 정본 DDL</b> — {@code mysql/init/01_schema.sql} 을 <b>빈 DB 에 실제로 적용해</b>
 *       {@code information_schema} 를 읽는다.</li>
 *   <li><b>§E 반대 방향</b>(이슈 #75) — {@code family_group} 도 chat 을 참조하지 않고,
 *       밖에서 chat 을 부를 때는 <b>공개 표면</b>만 부른다.</li>
 * </ul>
 *
 * <h2>§E 가 왜 §A~§D 와 다른 것을 보는가</h2>
 * <p>§A~§D 는 전부 "chat 이 밖을 안 본다" 다. 그런데 #75 가 <b>밖이 chat 을 부르는 방향</b>을
 * 열었다 — 가족 그룹을 만들면 같은 트랜잭션에서 방과 방장이 생기고, 그 호출은 group 에서
 * chat 으로 간다. 허용한 방향이지만 <b>무엇을 부를 수 있는가</b>는 정해야 한다.
 * 정하지 않으면 다음 사람이 {@code ChatRoomMemberRepository} 를 직접 주입받고,
 * 그 순간 chat 의 저장 구조가 남의 모듈의 컴파일 의존이 된다
 * ({@code backend/docs/architecture/ModularMonolithMigrationPlan.md} 가 글로만 정해 뒀던 규칙이
 * 이것이고, 📌 #86 원칙 6 이 "강제 장치가 0건" 이라고 적은 자리다).
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
    @DisplayName("chat_* 의 FK 는 전부 chat 안쪽을 가리킨다 — 정본 스키마를 빈 DB 에 적용해서 본다")
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
                            넷보다 적으면 경계 안쪽 FK 까지 끊어진 것이고, 다른 이름이 끼면 \
                            users·family_group·dog 로 나간 것이다 (ADR-0011 결정 4).
                            chat_message → users 가 여기 끼는 것이 #78 완료 조건 6 이 막는 것이다 — \
                            ON DELETE CASCADE 면 탈퇴 한 번에 그 사람이 방에 쓴 말이 전부 사라진다.
                            chat_reported_message 는 #82 가 더한 것이고 여전히 chat 안쪽이다.
                            반대로 chat_report 가 이 목록에 없는 것도 의도다 — chat_room 으로
                            FK 를 내면 방을 지우는 것으로 신고 기록을 지울 수 있게 된다.""")
                    .containsExactlyInAnyOrder(
                            "chat_message → chat_room",
                            "chat_reported_message → chat_report",
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
            assertThat(uniqueColumnSets(db, "chat_message"))
                    .as("""
                            (room_id, room_seq) 는 순서·델타·미읽음 셋의 유일한 근거다. 같은 방에 \
                            같은 seq 가 둘이면 afterSeq 폴링이 어느 쪽을 줬는지 알 수 없고, 클라이언트는 \
                            받지 못한 쪽을 영영 못 받는다 (#78 완료 조건 5 · ADR-0011 결정 2).
                            (room_id, sender_user_id, client_msg_id) 는 재전송 멱등의 근거다 — \
                            없으면 지하철에서 타임아웃된 전송이 같은 말을 두 줄로 남긴다 \
                            (#79 완료 조건 3·8). 범위에서 sender_user_id 를 빼면 같은 방의 다른 \
                            멤버가 같은 키를 썼을 때 그 사람의 메시지가 조용히 사라진다 — 서버가 \
                            200 과 함께 남의 메시지를 돌려주므로 앱은 성공으로 읽고 재시도조차 \
                            하지 않는다 (#79).""")
                    .contains("room_id,room_seq", "room_id,sender_user_id,client_msg_id");
        }
    }

    @Test
    @DisplayName("정본 스키마의 chat_message 가 (room_id, room_seq) 로 정렬·범위 조회할 인덱스를 갖는다")
    void committedSchema_keepsTheIndexThatMakesSeqTheCursor() throws Exception {
        try (ScratchDatabase db = ScratchDatabase.withCommittedSchema()) {
            assertThat(db.queryStrings("""
                    SELECT GROUP_CONCAT(column_name ORDER BY seq_in_index)
                    FROM information_schema.statistics
                    WHERE table_schema = DATABASE() AND table_name = 'chat_message'
                    GROUP BY index_name
                    """))
                    .as("""
                            #79 의 델타 폴링은 (room_id, room_seq) 범위 스캔이다. 그 인덱스가 없으면 \
                            방 하나를 폴링할 때마다 chat_message 전체를 훑고, 그래도 답은 맞아서 \
                            아무도 모른다 — 느려질 뿐이다 (#78 완료 조건 7).
                            id 를 커서로 되돌리려는 사람이 가장 먼저 지우는 것이 이 인덱스다.""")
                    .contains("room_id,room_seq");
        }
    }

    // ─────────────────── E. 반대 방향 — 밖에서 chat 을 부를 때 (이슈 #75) ───────────────────

    @Test
    @DisplayName("family_group 엔티티의 어떤 필드도 chat 을 가리키지 않는다 — 화살표는 chat_room → family_group 한쪽이다")
    void familyGroupEntity_pointsAtNothingInChat() throws Exception {
        Class<?> familyGroup = Class.forName(FAMILY_GROUP_CLASS);

        assertThat(familyGroup.isAnnotationPresent(Entity.class))
                .as("%s 이 엔티티가 아니면 이 검사는 아무것도 지키지 않는다", FAMILY_GROUP_CLASS)
                .isTrue();

        List<String> offenders = new ArrayList<>();
        for (Field field : familyGroup.getDeclaredFields()) {
            if (field.isSynthetic()) {
                continue;
            }
            Class<?> target = targetTypeOf(field);
            if (target != null && target.getName().startsWith(CHAT_PACKAGE + ".")) {
                offenders.add("FamilyGroup." + field.getName() + " → " + target.getName());
            }
        }

        assertThat(offenders)
                .as("""
                        방을 가리키는 필드를 여기 두면 화살표가 양방향이 되고, 그때부터 두 표는 \
                        어느 쪽도 혼자 못 움직인다.
                        방이 origin_kind='FAMILY' · origin_ref=<이 행의 id> 로 그룹을 불투명하게 \
                        가리키는 것이 유일한 통로다 (ADR-0011).""")
                .isEmpty();
    }

    @Test
    @DisplayName("chat 밖의 소스는 chat 의 공개 표면만 부른다 — chat.entity·chat.repository 는 부르지 못한다")
    void outsideSources_nameOnlyThePublishedSurfaceOfChat() throws IOException {
        Set<String> published = publishedChatTypeNames();
        List<String> offenders = new ArrayList<>();

        for (Path file : mainSourceFilesOutsideChat()) {
            String[] lines = stripComments(Files.readString(file, StandardCharsets.UTF_8))
                    .split("\\R", -1);
            for (int i = 0; i < lines.length; i++) {
                Matcher m = CHAT_MEMBER_REFERENCE.matcher(lines[i]);
                while (m.find()) {
                    if (!published.contains(m.group(1))) {
                        offenders.add("%s:%d  %s".formatted(
                                file.getFileName(), i + 1, lines[i].strip()));
                    }
                }
            }
        }

        assertThat(offenders)
                .as("""
                        #75 가 group → chat 방향을 열었다. 허용한 방향이지만 부를 수 있는 것은 \
                        chat 패키지 바로 아래의 타입(ChatRoomService 와 Chat*View 레코드)뿐이다.
                        chat.entity·chat.repository 를 직접 부르면 chat 의 저장 구조가 남의 모듈의 \
                        컴파일 의존이 되고, 지연 로딩된 연관을 트랜잭션 밖에서 건드리는 사고도 \
                        같은 문에서 들어온다.
                        필요한 것이 지금 공개 표면에 없다면 메서드를 하나 더하는 것이 맞다 — \
                        리포지토리를 꺼내 쓰는 것이 아니라.""")
                .isEmpty();
    }

    @Test
    @DisplayName("그 공개 표면 검사가 실제로 잡는다 — chat 클래스 이름을 하나도 못 모으면 공허하게 통과한다")
    void thePublishedSurfaceScannerActuallyCatchesAReachIntoTheInternals() throws IOException {
        Set<String> published = publishedChatTypeNames();

        assertThat(published)
                .as("공개 표면이 비어 있으면 위 검사는 모든 참조를 위반으로 보거나(오탐) "
                        + "패키지 구조가 바뀐 것이다")
                .contains("ChatRoomService");
        assertThat(published)
                .as("하위 패키지 이름이 공개 표면에 섞이면 그 안의 무엇이든 부를 수 있게 된다")
                .doesNotContain("entity", "repository");

        assertThat(firstGroupsIn(CHAT_MEMBER_REFERENCE,
                "import com.heattrip.heat_trip_backend.chat.repository.ChatRoomMemberRepository;"))
                .as("리포지토리 직접 주입이 안 걸리면 이 게이트는 아무것도 지키지 않는다")
                .containsExactly("repository");
        assertThat(firstGroupsIn(CHAT_MEMBER_REFERENCE,
                "private final com.heattrip.heat_trip_backend.chat.entity.ChatRoom room;"))
                .as("완전수식명으로 엔티티를 드는 것도 같은 위반이다")
                .containsExactly("entity");
        assertThat(firstGroupsIn(CHAT_MEMBER_REFERENCE,
                "import com.heattrip.heat_trip_backend.chat.ChatRoomService;"))
                .as("공개 표면 호출이 여기서 걸리면 group 이 방을 열 방법이 없어진다")
                .containsExactly("ChatRoomService");
    }

    @Test
    @DisplayName("정본 스키마에서 family_group 은 FK 를 내지 않고, 받는 것은 care_log·walk_note 둘뿐이다")
    void committedSchema_keepsFamilyGroupAndChatUnlinked() throws Exception {
        try (ScratchDatabase db = ScratchDatabase.withCommittedSchema()) {
            assertThat(db.queryStrings("""
                    SELECT CONCAT(table_name, ' → ', referenced_table_name)
                    FROM information_schema.referential_constraints
                    WHERE constraint_schema = DATABASE()
                      AND table_name = 'family_group'
                    ORDER BY constraint_name
                    """))
                    .as("""
                            나가는 FK 는 0개여야 한다. family_group → chat_room 은 07 의 §D 그물 \
                            밖이다 — 이 표를 만드는 순간이 그 FK 를 걸고 싶어지는 순간이라 여기서 \
                            본다 (ADR-0011 · 이슈 #75).""")
                    .isEmpty();

            assertThat(db.queryStrings("""
                    SELECT CONCAT(table_name, ' → ', referenced_table_name)
                    FROM information_schema.referential_constraints
                    WHERE constraint_schema = DATABASE()
                      AND referenced_table_name = 'family_group'
                    ORDER BY table_name, constraint_name
                    """))
                    .as("""
                            들어오는 FK 는 **이 목록 그대로**여야 한다 (이슈 #76 이 이 단언을 넓혔다).
                            #75 시점에는 0개였고 그때 'walk_note·care_log 가 들어오면 이 단언을 그 \
                            표들로 넓힌다' 고 적어 뒀다 — 케어는 chat 경계 밖이라 FK 를 정상적으로 \
                            건다.
                            새 이름이 여기 늘어나면 그건 자동 통과가 아니라 이 목록을 고치는 판단이 \
                            있었다는 뜻이어야 한다. 특히 chat_* 가 여기 끼면 ADR-0011 결정 4 가 \
                            깨진 것이다 — containsExactly 라 그 순간 빨간불이다.""")
                    .containsExactly("care_log → family_group", "walk_note → family_group");

            assertThat(db.queryStrings("""
                    SELECT CONCAT(table_name, ' → ', referenced_table_name)
                    FROM information_schema.referential_constraints
                    WHERE constraint_schema = DATABASE()
                      AND ((table_name IN ('care_log', 'walk_note')
                            AND referenced_table_name LIKE 'chat\\_%')
                        OR (table_name LIKE 'chat\\_%'
                            AND referenced_table_name IN ('care_log', 'walk_note')))
                    ORDER BY table_name, constraint_name
                    """))
                    .as("""
                            케어와 chat 사이에는 양방향 모두 FK 가 없다. 케어는 그룹 단위로 공유되고 \
                            방에서는 **인가만** 받는다 — 표끼리 묶으면 방 삭제가 케어 기록 삭제 순서에 \
                            묶이고, 산책 크루 방이 케어 컬럼을 NULL 로 들고 다니게 된다 \
                            (ADR-0011 결정 4 · 이슈 #76).""")
                    .isEmpty();

            assertThat(db.queryStrings("""
                    SELECT table_name FROM information_schema.tables
                    WHERE table_schema = DATABASE() AND table_name IN ('family_group', 'group_member')
                    ORDER BY table_name
                    """))
                    .as("""
                            멤버십 표는 chat_room_member 하나다 (ADR-0011 결정 1). group_member 를 \
                            두면 '가족인데 방에 없는 사람'·'방에 있는데 가족이 아닌 사람' 이라는 상태가 \
                            생기고, 그걸 막는 코드를 영원히 쓴다.
                            family_group 이 목록에 없다면 정본 스키마에서 표가 빠진 것이다.""")
                    .containsExactly("family_group");
        }
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private static final String FAMILY_GROUP_CLASS =
            APP_PACKAGE + ".group.entity.FamilyGroup";

    private static final String MAIN_SOURCE_DIR = "src/main/java/com/heattrip/heat_trip_backend";

    /** {@code com.heattrip.heat_trip_backend.chat.<무엇>} 에서 그 {@code <무엇>} 을 집는다. */
    private static final Pattern CHAT_MEMBER_REFERENCE = Pattern.compile(
            "\\b" + Pattern.quote(CHAT_PACKAGE) + "\\.(\\w+)");

    /** chat 패키지 <b>바로 아래</b>의 타입 이름 — 밖에서 부를 수 있는 것은 이것뿐이다. */
    private static Set<String> publishedChatTypeNames() throws IOException {
        Path root = TestProjectPaths.requireDirectory(CHAT_SOURCE_DIR);
        try (Stream<Path> files = Files.list(root)) {
            return files.filter(p -> p.toString().endsWith(".java"))
                    .map(p -> p.getFileName().toString())
                    .map(name -> name.substring(0, name.length() - ".java".length()))
                    .collect(java.util.stream.Collectors.toCollection(LinkedHashSet::new));
        }
    }

    /** chat 패키지를 뺀 main 소스 전부. */
    private static List<Path> mainSourceFilesOutsideChat() throws IOException {
        Path root = TestProjectPaths.requireDirectory(MAIN_SOURCE_DIR);
        Path chat = TestProjectPaths.requireDirectory(CHAT_SOURCE_DIR);
        try (Stream<Path> files = Files.walk(root)) {
            List<Path> found = files
                    .filter(p -> p.toString().endsWith(".java"))
                    .filter(p -> !p.startsWith(chat))
                    .sorted()
                    .toList();
            if (found.isEmpty()) {
                throw new IllegalStateException(root + " 아래에 chat 밖 자바 소스가 없다.");
            }
            return found;
        }
    }

    /** 한 줄에서 정규식의 첫 그룹을 전부 모은다. 위 검사와 자기검증이 같은 코드를 쓴다. */
    private static List<String> firstGroupsIn(Pattern pattern, String line) {
        List<String> found = new ArrayList<>();
        Matcher m = pattern.matcher(line);
        while (m.find()) {
            found.add(m.group(1));
        }
        return found;
    }

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
