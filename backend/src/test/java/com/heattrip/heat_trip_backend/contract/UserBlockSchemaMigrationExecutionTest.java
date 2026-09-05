package com.heattrip.heat_trip_backend.contract;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.stream.Collectors;

import com.heattrip.heat_trip_backend.support.MySqlTestContainer;
import com.heattrip.heat_trip_backend.support.TestProjectPaths;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.testcontainers.containers.MySQLContainer;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * {@code 16_user_block.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — 이슈 #166.
 *
 * <h2>왜 이제야 있나</h2>
 * <p>이 스크립트는 실행 테스트가 없었다. 2026-09-05 에 사장님 dev DB 에 돌리다 <b>멈췄다</b> —
 * 표 이름은 {@code user_block} 으로 바뀌었는데 인덱스 이름은 {@code uq_chat_block} 그대로였고,
 * 사후 검증이 {@code uq_user_block} 을 못 찾아 ABORT 했다. 반쯤 적용된 채로 멈춘 것이다.
 *
 * <p>원인은 {@code information_schema.statistics} 를 {@code COUNT(*)} 로 센 것이다. 그 표는
 * <b>인덱스의 컬럼마다 한 행</b>이라, 두 컬럼짜리 {@code uq_chat_block} 은 2 가 나온다.
 * {@code = 1} 로 견주니 인덱스를 바꾸는 문장이 한 번도 안 돌았다.
 *
 * <p>{@code SchemaDdlDriftTest} 도 {@code ddl-auto=validate} 도 <b>인덱스 이름을 안 본다.</b>
 * 여기서 안 보면 아무도 안 알려준다 — 그래서 실제로 아무도 안 알려줬다.
 */
class UserBlockSchemaMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/16_user_block.sql";

    private static int dbCounter = 0;

    @Test
    @DisplayName("두 컬럼짜리 유니크 인덱스도 이름이 바뀐다 — statistics 는 컬럼마다 한 행이다")
    void aTwoColumnUniqueIndexIsRenamedToo() throws Exception {
        try (Fixture db = fixture()) {
            db.createOldTable();
            db.runMigration();

            assertThat(db.tables()).contains("user_block").doesNotContain("chat_block");
            assertThat(db.indexNames("user_block"))
                    .as("""
                            COUNT(*) 로 세면 두 컬럼 인덱스는 2 라 '= 1' 이 거짓이고, 이름 바꾸는 \
                            문장이 안 돈다. 그 뒤 사후 검증이 uq_user_block 을 못 찾아 멈춘다 — \
                            표 이름은 이미 바뀐 채로. dev DB 에서 실제로 그렇게 멈췄다.""")
                    .contains("uq_user_block")
                    .doesNotContain("uq_chat_block");
        }
    }

    @Test
    @DisplayName("유니크가 유니크로 남는다 — 이름만 바꾸고 제약을 잃으면 같은 사람을 두 번 가릴 수 있다")
    void theUniqueConstraintSurvivesTheRename() throws Exception {
        try (Fixture db = fixture()) {
            db.createOldTable();
            db.runMigration();
            db.exec("INSERT INTO user_block (blocker_user_id, blocked_user_id, created_at) VALUES (1, 2, NOW(6))");

            assertThatThrownBy(() -> db.exec(
                    "INSERT INTO user_block (blocker_user_id, blocked_user_id, created_at) VALUES (1, 2, NOW(6))"))
                    .isInstanceOf(SQLException.class);
        }
    }

    @Test
    @DisplayName("두 번 돌려도 같은 상태로 끝난다")
    void migrationIsIdempotent() throws Exception {
        try (Fixture db = fixture()) {
            db.createOldTable();
            db.runMigration();
            db.runMigration();

            assertThat(db.tables()).contains("user_block").doesNotContain("chat_block");
            assertThat(db.indexNames("user_block")).contains("uq_user_block");
        }
    }

    @Test
    @DisplayName("이미 옮겨진 DB 에서도 통과한다 — 새 DB 는 01_schema.sql 이 user_block 을 바로 만든다")
    void aFreshSchemaPassesWithoutDoingAnything() throws Exception {
        try (Fixture db = fixture()) {
            db.exec("""
                    CREATE TABLE user_block (
                        id              BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
                        blocker_user_id BIGINT NOT NULL,
                        blocked_user_id BIGINT NOT NULL,
                        created_at      DATETIME(6) NOT NULL,
                        UNIQUE KEY uq_user_block (blocker_user_id, blocked_user_id)
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);

            db.runMigration();

            assertThat(db.indexNames("user_block")).contains("uq_user_block");
        }
    }

    @Test
    @DisplayName("옛 표와 새 표가 둘 다 있으면 한 글자도 안 바꾸고 멈춘다 — 어느 쪽이 정본인지 사람이 정한다")
    void migrationAbortsWhenBothTablesExist() throws Exception {
        try (Fixture db = fixture()) {
            db.createOldTable();
            db.exec("CREATE TABLE user_block (id BIGINT PRIMARY KEY)");

            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("둘 다 있다");

            assertThat(db.tables()).contains("chat_block", "user_block");
        }
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private static Fixture fixture() throws SQLException {
        return new Fixture();
    }

    private static final class Fixture implements AutoCloseable {

        private final String name;
        private final Connection connection;

        Fixture() throws SQLException {
            MySQLContainer<?> mysql = MySqlTestContainer.instance();
            synchronized (UserBlockSchemaMigrationExecutionTest.class) {
                name = "user_block_mig_test_" + (++dbCounter);
            }
            String serverUrl = mysql.getJdbcUrl().replaceAll("/[^/?]+(\\?|$)", "/$1");
            try (Connection admin = DriverManager.getConnection(serverUrl, "root", mysql.getPassword());
                 Statement st = admin.createStatement()) {
                st.execute("DROP DATABASE IF EXISTS " + name);
                st.execute("CREATE DATABASE " + name + " CHARACTER SET utf8mb4");
            }
            connection = DriverManager.getConnection(
                    serverUrl.replaceFirst("/(\\?|$)", "/" + name + "$1"), "root", mysql.getPassword());
        }

        /**
         * 옮기기 전의 표. <b>유니크가 두 컬럼</b>인 것이 이 테스트의 요점이다 — 정본
         * {@code 01_schema.sql} 의 {@code uq_user_block (blocker_user_id, blocked_user_id)} 와 같다.
         */
        void createOldTable() throws SQLException {
            exec("""
                    CREATE TABLE chat_block (
                        id              BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
                        blocker_user_id BIGINT NOT NULL,
                        blocked_user_id BIGINT NOT NULL,
                        created_at      DATETIME(6) NOT NULL,
                        UNIQUE KEY uq_chat_block (blocker_user_id, blocked_user_id)
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
        }

        void runMigration() throws Exception {
            String sql = Files.readString(TestProjectPaths.requireFile(SCRIPT), StandardCharsets.UTF_8);
            try (Statement st = connection.createStatement()) {
                for (String statement : splitStatements(sql)) {
                    st.execute(statement);
                }
            }
        }

        void exec(String sql) throws SQLException {
            try (Statement st = connection.createStatement()) {
                st.execute(sql);
            }
        }

        List<String> tables() throws SQLException {
            return query("SELECT table_name FROM information_schema.tables "
                    + "WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE' ORDER BY table_name");
        }

        /** 인덱스 <b>이름</b>들. 컬럼마다 한 행이라 DISTINCT 로 센다 — 스크립트가 틀린 자리가 그것이다. */
        List<String> indexNames(String table) throws SQLException {
            return query("SELECT DISTINCT index_name FROM information_schema.statistics "
                    + "WHERE table_schema = DATABASE() AND table_name = '" + table + "' ORDER BY index_name");
        }

        List<String> query(String sql) throws SQLException {
            List<String> out = new ArrayList<>();
            try (Statement st = connection.createStatement(); ResultSet rs = st.executeQuery(sql)) {
                while (rs.next()) {
                    out.add(rs.getString(1));
                }
            }
            return out;
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

    private static List<String> splitStatements(String script) {
        String withoutComments = Arrays.stream(script.split("\\R"))
                .map(String::strip)
                .filter(line -> !line.startsWith("--") && !line.startsWith("#"))
                .collect(Collectors.joining("\n"));
        return Arrays.stream(withoutComments.split(";"))
                .map(String::strip)
                .filter(statement -> !statement.isEmpty())
                .toList();
    }
}
