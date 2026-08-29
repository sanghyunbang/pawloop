package com.heattrip.heat_trip_backend.support;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.sql.Connection;
import java.sql.DriverManager;
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
import org.testcontainers.containers.MySQLContainer;

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

    private static final String COMMITTED = "mysql/init/01_schema.sql";

    private static final String REGENERATE = """
            재생성:
              cd backend
              ./gradlew exportSchema
              (또는) 엔티티 변경분을 mysql/init/01_schema.sql 에 직접 반영""";

    @Autowired
    private DataSource dataSource;

    @Test
    @DisplayName("커밋된 운영 스키마를 빈 DB 에 적용하면 엔티티가 만드는 것과 같은 테이블이 나온다")
    void committedSchema_producesTheSameTables() throws Exception {
        Map<String, List<String>> fromEntities = describe(dataSource.getConnection(), null);

        try (ScratchDatabase db = ScratchDatabase.withCommittedSchema()) {
            Map<String, List<String>> fromSql = describe(db.connection, null);

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
        Map<String, List<String>> fromEntities = describe(dataSource.getConnection(), null);

        try (ScratchDatabase db = ScratchDatabase.withCommittedSchema()) {
            Map<String, List<String>> fromSql = describe(db.connection, null);

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
    @DisplayName("커밋된 스키마가 CREATE TABLE 로 되어 있다 — post-start 는 전부 ALTER 라 이 파일이 전제를 만든다")
    void committedSchema_createsRatherThanAlters() throws Exception {
        String sql = Files.readString(
                TestProjectPaths.requireFile(COMMITTED), StandardCharsets.UTF_8);

        assertThat(statements(sql).stream().filter(s -> s.startsWith("create table")).count())
                .as("빈 운영 DB 를 세울 수 있어야 한다 — 그게 이 파일의 존재 이유다 (#58)")
                .isGreaterThan(20);
        assertThat(sql).containsIgnoringCase("create table users");
        assertThat(sql)
                .as("#9 가 만든 refresh 토큰 원장도 들어 있어야 한다")
                .containsIgnoringCase("create table refresh_token");
    }

    // ─────────────────────────── 지그 ───────────────────────────

    /** 테이블명 → "컬럼 타입 널허용" 목록. 이름순으로 정렬해 순서 차이를 지운다. */
    private static Map<String, List<String>> describe(Connection connection, String unused)
            throws SQLException {
        Map<String, List<String>> out = new LinkedHashMap<>();
        try (connection;
             Statement st = connection.createStatement();
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

    private static List<String> statements(String ddl) {
        String withoutComments = Arrays.stream(ddl.split("\\R"))
                .filter(line -> !line.strip().startsWith("--"))
                .collect(Collectors.joining("\n"));
        return Arrays.stream(withoutComments.split(";"))
                .map(s -> s.replaceAll("\\s+", " ").strip().toLowerCase())
                .filter(s -> !s.isEmpty())
                .toList();
    }

    /** 커밋된 스키마만 적용한 일회용 데이터베이스. */
    private static final class ScratchDatabase implements AutoCloseable {
        private static int counter = 0;

        private final String name;
        private final Connection connection;

        static ScratchDatabase withCommittedSchema() throws Exception {
            ScratchDatabase db = new ScratchDatabase();
            String sql = Files.readString(
                    TestProjectPaths.requireFile(COMMITTED), StandardCharsets.UTF_8);
            try (Statement st = db.connection.createStatement()) {
                for (String statement : statements(sql)) {
                    st.execute(statement);
                }
            }
            return db;
        }

        private ScratchDatabase() throws SQLException {
            MySQLContainer<?> mysql = MySqlTestContainer.instance();
            synchronized (SchemaDdlDriftTest.class) {
                name = "schema_check_" + (++counter);
            }
            // 앱 계정에는 CREATE DATABASE 권한이 없다 — root 로 붙는다(#56 에서 실측).
            String serverUrl = mysql.getJdbcUrl().replaceAll("/[^/?]+(\\?|$)", "/$1");
            try (Connection admin = DriverManager.getConnection(
                    serverUrl, "root", mysql.getPassword());
                 Statement st = admin.createStatement()) {
                st.execute("DROP DATABASE IF EXISTS " + name);
                st.execute("CREATE DATABASE " + name + " CHARACTER SET utf8mb4");
            }
            connection = DriverManager.getConnection(
                    serverUrl.replaceFirst("/(\\?|$)", "/" + name + "$1"),
                    "root", mysql.getPassword());
        }

        @Override
        public void close() throws SQLException {
            try (Statement st = connection.createStatement()) {
                st.execute("DROP DATABASE IF EXISTS " + name);
            } finally {
                connection.close();
            }
        }
    }
}
