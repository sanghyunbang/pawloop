package com.heattrip.heat_trip_backend.support;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import javax.sql.DataSource;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 커밋된 운영 스키마가 JPA 엔티티와 어긋나지 않는지 잠근다 — 이슈 #58.
 *
 * <h2>왜 이 파일이 필요했나</h2>
 * <p>{@code backend/mysql/init/} 이 <b>비어 있었다.</b> 저장소 전체에 {@code CREATE TABLE} 이
 * 하나도 없었고, 운영은 {@code ddl-auto=validate} 라 아무것도 만들지 않는다. 즉
 * <b>빈 운영 DB 에 이 앱을 올릴 방법이 저장소에 없었다.</b> 새 환경 구축도 재해 복구도
 * 경로가 없고, {@code mysql/post-start/*.sql} 은 전부 {@code ALTER TABLE} 이라 테이블이
 * 이미 있다고 전제한다.
 *
 * <h2>무엇을 비교하는가</h2>
 * <p>DDL <b>텍스트</b>가 아니라 <b>결과 스키마</b>를 비교한다.
 *
 * <ol>
 *   <li><b>A</b> — Hibernate 가 지금 엔티티로 만든 스키마(이 테스트가 붙어 있는 DB)</li>
 *   <li><b>B</b> — 저장소의 {@code mysql/init/01_schema.sql} 을 빈 DB 에 적용한 결과</li>
 * </ol>
 *
 * <p>둘의 {@code information_schema} 를 대조한다. 텍스트 비교를 안 하는 이유는 Hibernate 가
 * 실행마다 문장 순서·공백을 바꿔서, 엔티티가 그대로인데도 빨간불이 나는 테스트가 되기
 * 때문이다. 며칠이면 아무도 안 믿게 된다.
 *
 * <p>(처음에는 Hibernate 의 {@code schema-generation.scripts} 로 뽑은 파일을 읽어 비교하려
 * 했는데 <b>그 파일은 EntityManagerFactory 가 닫힐 때 플러시된다</b> — 같은 실행 안에서는
 * 읽을 수 없다. 실측으로 확인하고 이 방식으로 바꿨다.)
 */
@SpringBootTest
class SchemaDdlDriftTest extends AbstractMySqlIntegrationTest {

    private static final String COMMITTED = ScratchDatabase.COMMITTED_SCHEMA;

    private static final String REGENERATE = """
            재생성:
              cd backend
              ./gradlew test --tests '*SchemaDdlDriftTest*'
              cp build/generated-schema.sql mysql/init/01_schema.sql""";

    @Autowired
    private DataSource dataSource;

    @Test
    @DisplayName("커밋된 운영 스키마를 빈 DB 에 적용하면 엔티티가 만드는 것과 같은 테이블이 나온다")
    void committedSchema_producesTheSameTables() throws Exception {
        Map<String, List<String>> fromEntities;
        try (Connection live = dataSource.getConnection()) {
            fromEntities = describe(live);
        }

        try (ScratchDatabase db = ScratchDatabase.withCommittedSchema()) {
            Map<String, List<String>> fromSql = describe(db.connection());

            assertThat(fromSql.keySet())
                    .as("커밋된 스키마에 없는 테이블이다. 운영 DB 를 새로 세우면 이만큼이 빠진 채로 "
                            + "만들어지고 ddl-auto=validate 가 부팅을 막는다.%n%s", REGENERATE)
                    .containsAll(fromEntities.keySet());

            assertThat(fromEntities.keySet())
                    .as("엔티티에 없는 테이블이 커밋된 스키마에 있다. 지운 엔티티의 잔재이거나 "
                            + "손으로 넣은 것이다.%n%s", REGENERATE)
                    .containsAll(fromSql.keySet());
        }
    }

    @Test
    @DisplayName("테이블마다 컬럼 이름·타입·널 허용까지 같다 — 이름만 맞고 정의가 다르면 validate 가 막는다")
    void committedSchema_producesTheSameColumns() throws Exception {
        Map<String, List<String>> fromEntities;
        try (Connection live = dataSource.getConnection()) {
            fromEntities = describe(live);
        }

        try (ScratchDatabase db = ScratchDatabase.withCommittedSchema()) {
            Map<String, List<String>> fromSql = describe(db.connection());

            List<String> mismatched = new ArrayList<>();
            for (var entry : fromEntities.entrySet()) {
                List<String> other = fromSql.get(entry.getKey());
                if (other != null && !other.equals(entry.getValue())) {
                    mismatched.add(entry.getKey() + "\n    엔티티: " + entry.getValue()
                            + "\n    스키마: " + other);
                }
            }

            assertThat(mismatched)
                    .as("이름은 같은데 정의가 다른 테이블이다. ddl-auto=validate 는 컬럼 타입 차이로 "
                            + "부팅을 거부한다.%n%s", REGENERATE)
                    .isEmpty();
        }
    }

    @Test
    @DisplayName("FK 의 삭제 규칙까지 같다 — 엔티티만 CASCADE 로 바뀌면 다음 재생성에서 조용히 넘어간다")
    void committedSchema_producesTheSameDeleteRules() throws Exception {
        // 위 두 테스트는 **컬럼**만 본다. FK 의 ON DELETE 는 컬럼 정의가 아니라
        // referential_constraints 에 있어서 거기 안 걸리고, ddl-auto=validate 도 안 본다
        // (50_care_item.sql 의 D 절이 같은 말을 한다). 그래서 @OnDelete 를 SET_NULL 에서
        // CASCADE 로 바꿔도 아무 게이트가 안 울리고, 다음 재생성 때 정본에 실려 새 운영
        // DB 부터 **지운 아이가 그 집의 할 일 목록을 데려간다.** 실측으로 확인했다(#560).
        Map<String, List<String>> fromEntities;
        try (Connection live = dataSource.getConnection()) {
            fromEntities = deleteRules(live);
        }

        try (ScratchDatabase db = ScratchDatabase.withCommittedSchema()) {
            Map<String, List<String>> fromSql = deleteRules(db.connection());

            List<String> mismatched = new ArrayList<>();
            for (var entry : fromEntities.entrySet()) {
                List<String> other = fromSql.get(entry.getKey());
                if (!entry.getValue().equals(other)) {
                    mismatched.add(entry.getKey() + "\n    엔티티: " + entry.getValue()
                            + "\n    스키마: " + other);
                }
            }

            assertThat(mismatched)
                    .as("엔티티와 정본의 ON DELETE 가 다르다. 컬럼은 같아서 위 테스트도 validate 도 "
                            + "안 막지만, 지우는 순간의 결과가 다르다.%n%s", REGENERATE)
                    .isEmpty();
        }
    }

    @Test
    @DisplayName("커밋된 스키마가 CREATE TABLE 로 되어 있다 — post-start 는 전부 ALTER 라 이 파일이 전제를 만든다")
    void committedSchema_createsRatherThanAlters() throws Exception {
        String sql = Files.readString(
                TestProjectPaths.requireFile(COMMITTED), StandardCharsets.UTF_8);

        assertThat(statements(sql).stream()
                .filter(s -> s.startsWith("create table"))
                .count())
                .as("빈 운영 DB 를 세울 수 있어야 한다 — 그게 이 파일의 존재 이유다 (#58)")
                .isGreaterThan(20);
        // SHOW CREATE TABLE 은 식별자를 백틱으로 감싼다 — `users` 처럼.
        assertThat(sql).containsIgnoringCase("create table `users`");
        assertThat(sql)
                .as("#9 가 만든 refresh 토큰 원장도 들어 있어야 한다")
                .containsIgnoringCase("create table `refresh_token`");

        // #74 — 방·멤버십·초대 3표. 이름으로 못 박는 이유는 위 두 테스트가 '엔티티가 만드는
        // 것과 같은가' 만 보기 때문이다. 엔티티를 통째로 지우면 그 둘은 여전히 초록불이다.
        assertThat(sql)
                .as("ADR-0011 이 정한 방 표다. 없으면 빈 운영 DB 에 채팅을 올릴 방법이 없다")
                .containsIgnoringCase("create table `chat_room`");
        assertThat(sql)
                .as("멤버십 표는 이것 하나다 — group_member 를 따로 만들지 않는다")
                .containsIgnoringCase("create table `chat_room_member`");
        assertThat(sql)
                .as("초대코드는 그룹 행의 컬럼이 아니라 별도 표다 (만료·사용횟수·회수)")
                .containsIgnoringCase("create table `chat_room_invite`");
    }

    @Test
    @DisplayName("지금 엔티티로 만든 DDL 을 build/generated-schema.sql 로 뽑아 둔다 — 재생성용")
    void exportCurrentSchema() throws Exception {
        // 단언이 아니라 **생성기**다. 위 두 테스트가 빨간불이면 이 파일을
        // mysql/init/01_schema.sql 로 복사하면 된다.
        //
        // Hibernate 의 schema-generation.scripts 를 쓰지 않는 이유: 그 파일은
        // EntityManagerFactory 가 닫힐 때 플러시돼서 같은 실행 안에서는 읽을 수 없고,
        // 게다가 덮어쓰지 않고 append 한다(실측: 52 → 104 → 156). 살아 있는 DB 에서
        // SHOW CREATE TABLE 로 뽑으면 그 두 문제가 다 없고, 무엇보다 **MySQL 이
        // 실제로 만든 모양** 그대로다.
        StringBuilder ddl = new StringBuilder(HEADER);
        int tables = 0;

        try (Connection live = dataSource.getConnection();
             Statement st = live.createStatement()) {
            List<String> names = new ArrayList<>();
            try (ResultSet rs = st.executeQuery("""
                    SELECT table_name FROM information_schema.tables
                    WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE'
                    ORDER BY table_name
                    """)) {
                while (rs.next()) {
                    names.add(rs.getString(1));
                }
            }
            for (String name : names) {
                try (ResultSet rs = st.executeQuery("SHOW CREATE TABLE `" + name + "`")) {
                    if (rs.next()) {
                        ddl.append(stripVolatile(rs.getString(2))).append(";\n\n");
                        tables++;
                    }
                }
            }
        }

        ddl.append(FOOTER);

        Path out = TestProjectPaths.backendDir().resolve("build/generated-schema.sql");
        Files.createDirectories(out.getParent());
        Files.writeString(out, ddl, StandardCharsets.UTF_8);

        assertThat(tables)
                .as("뽑은 테이블이 없으면 이 생성기는 아무것도 하지 않은 것이다")
                .isGreaterThan(20);
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private static final String HEADER = """
            -- ========================================================================
            -- 01_schema.sql — 운영 스키마 정본 (이슈 #58)
            --
            -- **손으로 고치지 않는다.** 지금 JPA 엔티티가 만드는 스키마를 그대로 뽑은 것이다.
            --
            --   cd backend
            --   ./gradlew test --tests '*SchemaDdlDriftTest*'
            --   cp build/generated-schema.sql mysql/init/01_schema.sql
            --
            -- SchemaDdlDriftTest 가 이 파일과 엔티티가 어긋나면 CI 를 빨간불로 만든다.
            --
            -- ------------------------------------------------------------------------
            -- 왜 이 파일이 생겼나
            --
            -- 예전에는 mysql/init/ 이 비어 있었다. 저장소 전체에 CREATE TABLE 이 하나도
            -- 없었고 prod 는 ddl-auto=validate 라 아무것도 만들지 않는다. 즉 **빈 운영 DB 에
            -- 이 앱을 올릴 방법이 저장소에 없었다** — 새 환경 구축도 재해 복구도 경로가
            -- 없고, post-start/*.sql 은 전부 ALTER TABLE 이라 테이블이 있다고 전제한다.
            --
            -- ------------------------------------------------------------------------
            -- 실행 순서
            --
            --   1. 이 파일 (mysql/init) — 컨테이너가 새 볼륨으로 처음 뜰 때 자동 실행
            --   2. mysql/post-start/01~05 — 사람이 번호 순으로 (mysql/README.md)
            --
            -- 이미 돌고 있는 DB 에는 실행하지 마라. '처음 세울 때' 파일이다.
            --
            -- ------------------------------------------------------------------------
            -- FOREIGN_KEY_CHECKS 를 왜 끄는가
            --
            -- 테이블이 이름순으로 나열돼 있어서, users 를 참조하는 테이블이 users 보다
            -- 먼저 나온다. 그대로 실행하면 "Failed to open the referenced table 'users'"
            -- 로 죽는다(실측). 순서를 위상정렬하는 대신 검사를 잠시 끈다 — 스키마 복원의
            -- 표준 방식이고, 마지막 줄에서 반드시 되돌린다.
            -- ========================================================================

            SET FOREIGN_KEY_CHECKS = 0;

            """;

    private static final String FOOTER = "SET FOREIGN_KEY_CHECKS = 1;\n";

    /**
     * 테이블명 → "컬럼 타입 널허용" 목록. 이름순으로 정렬해 순서 차이를 지운다.
     *
     * <p><b>커넥션을 닫지 않는다.</b> 소유권은 호출부에 있다 — 처음에 여기서 닫았더니
     * 일회용 DB 를 정리할 때 {@code ConnectionIsClosedException} 이 났다(실측).
     */
    /**
     * 표마다 "FK 이름 → 삭제 규칙" 목록. {@link #describe} 가 안 보는 축이다.
     *
     * <p>{@code update_rule} 은 안 본다 — 우리는 PK 를 갱신하지 않아서 전부 {@code NO ACTION}
     * 이고, 넣으면 재는 것 없이 목록만 길어진다.
     */
    private static Map<String, List<String>> deleteRules(Connection connection) throws SQLException {
        Map<String, List<String>> out = new LinkedHashMap<>();
        try (Statement st = connection.createStatement();
             ResultSet rs = st.executeQuery("""
                     SELECT table_name, constraint_name, delete_rule
                     FROM information_schema.referential_constraints
                     WHERE constraint_schema = DATABASE()
                     ORDER BY table_name, constraint_name
                     """)) {
            while (rs.next()) {
                out.computeIfAbsent(rs.getString(1).toLowerCase(), k -> new ArrayList<>())
                        .add(rs.getString(2).toLowerCase() + " " + rs.getString(3).toUpperCase());
            }
        }
        return out;
    }

    private static Map<String, List<String>> describe(Connection connection) throws SQLException {
        Map<String, List<String>> out = new LinkedHashMap<>();
        try (Statement st = connection.createStatement();
             ResultSet rs = st.executeQuery("""
                     SELECT table_name, column_name, column_type, is_nullable
                     FROM information_schema.columns
                     WHERE table_schema = DATABASE()
                     ORDER BY table_name, column_name
                     """)) {
            while (rs.next()) {
                out.computeIfAbsent(rs.getString(1).toLowerCase(), k -> new ArrayList<>())
                        .add(rs.getString(2).toLowerCase() + " "
                                + rs.getString(3).toLowerCase() + " " + rs.getString(4));
            }
        }
        return out;
    }

    /**
     * <b>비교용</b> 분리기. 순서·공백·대소문자 차이를 지운다. 실행에 쓰지 마라.
     *
     * <p>실행용 분리기는 {@link ScratchDatabase} 안에 있다 — 소문자화하면
     * {@code ENUM('IN_PROGRESS','NEW','RESOLVED')} 가 소문자로 바뀌어 스키마 자체가 달라진다.
     */
    private static List<String> statements(String ddl) {
        String withoutComments = Arrays.stream(ddl.split("\\R"))
                .filter(line -> !line.strip().startsWith("--"))
                .collect(Collectors.joining("\n"));
        return Arrays.stream(withoutComments.split(";"))
                .map(s -> s.replaceAll("\\s+", " ").strip().toLowerCase())
                .filter(s -> !s.isEmpty())
                .toList();
    }


    /**
     * 실행마다 달라지는 것을 뺀다 — 지금은 {@code AUTO_INCREMENT=N} 하나다.
     *
     * <p>{@code SHOW CREATE TABLE} 은 그 표의 <b>다음 자동 증가 값</b>을 함께 뱉는다.
     * 그 숫자는 테스트가 몇 행을 넣었느냐에 따라 매번 달라지므로, 그대로 정본에 넣으면
     * <b>스키마가 안 바뀌었는데도 재생성할 때마다 diff 가 난다.</b> 실제로 컬럼 하나를
     * 더한 변경에 그 줄 셋이 딸려 왔다. (#155)
     *
     * <p>정본은 "이 스키마가 어떤 모양인가" 를 말해야 하고, 다음 id 가 몇인지는 그
     * 모양이 아니다.
     */
    private static String stripVolatile(String ddl) {
        return ddl.replaceAll(" AUTO_INCREMENT=\\d+", "");
    }
}
