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
 * {@code 19_user_consent.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — 이슈 #190.
 *
 * <p>{@code SchemaDdlDriftTest} 도 {@code ddl-auto=validate} 도 CHECK·FK·인덱스 이름을 안 본다.
 * 이 표에서는 <b>FK 가 없다는 것</b>이 설계다 — 탈퇴가 증빙을 지우면 안 된다. 여기서 안 보면
 * 아무도 안 알려준다.
 */
class UserConsentSchemaMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/19_user_consent.sql";

    private static int dbCounter = 0;

    @Test
    @DisplayName("빈 DB 에 돌리면 표가 생긴다 — 부모 표가 필요 없다")
    void migrationCreatesTheTable() throws Exception {
        try (Fixture db = fixture()) {
            db.runMigration();

            assertThat(db.tables()).contains("user_consent");
            assertThat(db.columns("user_consent")).containsExactlyInAnyOrder(
                    "id", "user_id", "kind", "version", "agreed", "created_at");
            assertThat(db.indexNames("user_consent")).contains("idx_user_consent_user");
        }
    }

    @Test
    @DisplayName("users 로 FK 가 없다 — 탈퇴가 동의 기록을 지우면 안 된다")
    void thereIsNoForeignKey() throws Exception {
        try (Fixture db = fixture()) {
            db.runMigration();

            assertThat(db.foreignKeys()).isEmpty();
            // users 표가 없어도 행이 들어간다 — 값으로만 가리키기 때문이다.
            db.exec("INSERT INTO user_consent (user_id, kind, version, agreed, created_at) "
                    + "VALUES (42, 'TERMS', 'v1.2', 1, NOW(6))");
            assertThat(db.count("user_consent")).isEqualTo(1);
        }
    }

    @Test
    @DisplayName("모르는 문서 종류는 DB 가 막는다 — 어휘가 넷이다")
    void unknownKindsAreRejected() throws Exception {
        try (Fixture db = fixture()) {
            db.runMigration();

            assertThatThrownBy(() -> db.exec(
                    "INSERT INTO user_consent (user_id, kind, version, agreed, created_at) "
                            + "VALUES (1, 'NEWSLETTER', 'v1.0', 1, NOW(6))"))
                    .as("서비스 상수만 있고 DB 가 비어 있으면 그 상수를 안 거치는 경로가 무방비다")
                    .isInstanceOf(SQLException.class);
        }
    }

    @Test
    @DisplayName("같은 문서에 두 번 동의해도 두 행이다 — 이력이라 UNIQUE 가 없다")
    void repeatedConsentIsHistoryNotConflict() throws Exception {
        try (Fixture db = fixture()) {
            db.runMigration();
            db.exec("INSERT INTO user_consent (user_id, kind, version, agreed, created_at) VALUES (1, 'TERMS', 'v1.2', 1, NOW(6))");
            db.exec("INSERT INTO user_consent (user_id, kind, version, agreed, created_at) VALUES (1, 'TERMS', 'v1.2', 0, NOW(6))");

            assertThat(db.count("user_consent"))
                    .as("철회는 새 행이다 — 덮어쓰면 '언제까지 동의 상태였는지' 가 사라진다")
                    .isEqualTo(2);
        }
    }

    @Test
    @DisplayName("두 번 돌려도 같은 상태로 끝난다")
    void migrationIsIdempotent() throws Exception {
        try (Fixture db = fixture()) {
            db.runMigration();
            db.exec("INSERT INTO user_consent (user_id, kind, version, agreed, created_at) VALUES (1, 'TERMS', 'v1.2', 1, NOW(6))");
            db.runMigration();

            assertThat(db.count("user_consent")).isEqualTo(1);
            assertThat(db.checks()).containsExactly("chk_user_consent_kind");
            assertThat(db.indexNames("user_consent")).contains("idx_user_consent_user");
        }
    }

    @Test
    @DisplayName("Hibernate 가 먼저 만든 표(CHECK·인덱스 없음)도 보정된다")
    void aTableMadeByHibernateGetsItsConstraints() throws Exception {
        try (Fixture db = fixture()) {
            db.exec("""
                    CREATE TABLE user_consent (
                        id         BIGINT      NOT NULL AUTO_INCREMENT PRIMARY KEY,
                        user_id    BIGINT      NOT NULL,
                        kind       VARCHAR(16) NOT NULL,
                        version    VARCHAR(16) NOT NULL,
                        agreed     BIT(1)      NOT NULL,
                        created_at DATETIME(6) NOT NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);

            db.runMigration();

            assertThat(db.checks()).containsExactly("chk_user_consent_kind");
            assertThat(db.indexNames("user_consent")).contains("idx_user_consent_user");
        }
    }

    @Test
    @DisplayName("users 로 FK 가 걸린 표가 있으면 한 글자도 안 바꾸고 멈춘다")
    void migrationAbortsWhenAForeignKeyExists() throws Exception {
        try (Fixture db = fixture()) {
            db.exec("CREATE TABLE users (id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY) ENGINE=InnoDB");
            db.exec("""
                    CREATE TABLE user_consent (
                        id         BIGINT      NOT NULL AUTO_INCREMENT PRIMARY KEY,
                        user_id    BIGINT      NOT NULL,
                        kind       VARCHAR(16) NOT NULL,
                        version    VARCHAR(16) NOT NULL,
                        agreed     BIT(1)      NOT NULL,
                        created_at DATETIME(6) NOT NULL,
                        CONSTRAINT fk_user_consent_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);

            assertThatThrownBy(db::runMigration)
                    .as("CASCADE 면 탈퇴와 함께 증빙이 사라진다 — 사람이 봐야 한다")
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("FK 가 있다");

            assertThat(db.checks()).as("멈췄으면 아무것도 안 바뀌어야 한다").isEmpty();
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
            synchronized (UserConsentSchemaMigrationExecutionTest.class) {
                name = "user_consent_mig_test_" + (++dbCounter);
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

        List<String> columns(String table) throws SQLException {
            return query("SELECT column_name FROM information_schema.columns "
                    + "WHERE table_schema = DATABASE() AND table_name = '" + table + "' ORDER BY column_name");
        }

        List<String> indexNames(String table) throws SQLException {
            return query("SELECT DISTINCT index_name FROM information_schema.statistics "
                    + "WHERE table_schema = DATABASE() AND table_name = '" + table + "' ORDER BY index_name");
        }

        List<String> foreignKeys() throws SQLException {
            return query("SELECT constraint_name FROM information_schema.referential_constraints "
                    + "WHERE constraint_schema = DATABASE() AND table_name = 'user_consent'");
        }

        List<String> checks() throws SQLException {
            return query("SELECT constraint_name FROM information_schema.table_constraints "
                    + "WHERE constraint_schema = DATABASE() AND constraint_type = 'CHECK' "
                    + "AND table_name = 'user_consent' ORDER BY constraint_name");
        }

        int count(String table) throws SQLException {
            return query("SELECT COUNT(*) FROM " + table).stream().findFirst().map(Integer::parseInt).orElse(-1);
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
