package com.heattrip.heat_trip_backend.contract;

import com.heattrip.heat_trip_backend.support.MySqlTestContainer;
import com.heattrip.heat_trip_backend.support.TestProjectPaths;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.testcontainers.containers.MySQLContainer;

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

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * {@code 21_users_drop_consent_columns.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — #190 후속.
 *
 * <h2>왜 실행 테스트인가</h2>
 * <p>이 스크립트는 <b>값을 옮기고 나서 컬럼을 지운다.</b> 옮기기가 틀리면 — 버전을 잃거나,
 * 시각이 어긋나거나, 동의 안 한 사람이 동의한 것으로 적히거나 — 그 뒤의 DROP 이 증거를
 * 지운다. 되돌릴 수 없다. 그래서 값으로 잰다: 옮겨진 행의 버전·시각·agreed 가 원래 칸의
 * 값과 같은지.
 *
 * <p>사람 셋을 심는다. 전부 동의한 사람(버전·시각 있음), 필수만 동의한 사람(버전 없음 —
 * 옛 기본값 v1.0 이 들어가야 한다), 아무것도 안 적힌 소셜 가입자(한 행도 안 생겨야 한다).
 */
class UsersConsentColumnsDropMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/21_users_drop_consent_columns.sql";

    private static final List<String> OLD_COLUMNS = List.of(
            "agree_tos", "agree_privacy", "agree_marketing",
            "tos_version", "privacy_version", "marketing_version",
            "tos_agreed_at", "privacy_agreed_at", "marketing_agreed_at");

    private static int dbCounter = 0;

    @Test
    @DisplayName("옮기고 지운다 — 동의한 사람의 버전·시각이 user_consent 에 그대로 남고 아홉 컬럼이 사라진다")
    void movesValuesThenDropsColumns() throws Exception {
        try (Fixture db = fixture()) {
            db.createUsersWithOldColumns();
            db.createUserConsent();
            db.seedThreeUsers();

            db.runMigration();

            assertThat(db.columns("users")).doesNotContainAnyElementsOf(OLD_COLUMNS);
            assertThat(db.count("users")).as("행은 건드리지 않는다").isEqualTo(3);

            // 1번: 셋 다 동의, 버전·시각 있음 → 셋 다 그대로 옮겨진다
            assertThat(db.consents(1)).containsExactlyInAnyOrder(
                    "TERMS|v1.2|1|2026-09-01 01:02:03.000000",
                    "PRIVACY|v1.3|1|2026-09-01 01:02:03.000000",
                    "MARKETING|v1.0|1|2026-09-02 04:05:06.000000");
            // 2번: 필수만, 버전 없음 → 옛 코드의 기본값 v1.0, 시각은 가입 시각
            assertThat(db.consents(2)).containsExactlyInAnyOrder(
                    "TERMS|v1.0|1|2026-08-15 00:00:00.000000",
                    "PRIVACY|v1.0|1|2026-08-15 00:00:00.000000");
            // 3번: 소셜 가입자, 전부 NULL → 아무것도 안 생긴다
            assertThat(db.consents(3))
                    .as("적힌 적 없는 동의를 '동의했다' 로 만들면 안 된다 — 그 사람은 다음 로그인에 동의 화면을 본다")
                    .isEmpty();
        }
    }

    @Test
    @DisplayName("이미 user_consent 에 있는 문서는 다시 옮기지 않는다 — 두 행이 되면 이력이 거짓이 된다")
    void doesNotDuplicateExistingConsentRows() throws Exception {
        try (Fixture db = fixture()) {
            db.createUsersWithOldColumns();
            db.createUserConsent();
            db.seedThreeUsers();
            db.exec("INSERT INTO user_consent (user_id, kind, version, agreed, created_at) "
                    + "VALUES (1, 'TERMS', 'v1.2', 1, '2026-09-03 00:00:00')");

            db.runMigration();

            assertThat(db.consents(1).stream().filter(c -> c.startsWith("TERMS|")))
                    .as("앱이 이미 적은 TERMS 행 하나만 남아야 한다")
                    .hasSize(1);
            assertThat(db.consents(1)).hasSize(3);
        }
    }

    @Test
    @DisplayName("user_consent 가 없으면 시작하지 않는다 — 옮길 곳이 없는데 지우면 증빙이 사라진다")
    void abortsWithoutUserConsentTable() throws Exception {
        try (Fixture db = fixture()) {
            db.createUsersWithOldColumns();
            db.seedThreeUsers();

            // 사전 점검에서 멈춰야 한다. 이 확인이 없어도 옮기기(INSERT)가 없는 표에 부딪혀
            // 죽긴 하는데, 그건 "멈춤" 이 아니라 "사고" 다 — 메시지로 구분한다(빨간불 증명 D).
            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("19_user_consent.sql");

            assertThat(db.columns("users"))
                    .as("멈췄으면 컬럼도 값도 그대로여야 한다")
                    .containsAll(OLD_COLUMNS);
        }
    }

    @Test
    @DisplayName("컬럼이 일부만 남아 있으면 멈춘다 — 어느 값이 남았는지 사람이 봐야 한다")
    void abortsWhenColumnsArePartiallyGone() throws Exception {
        try (Fixture db = fixture()) {
            db.createUsersWithOldColumns();
            db.createUserConsent();
            db.seedThreeUsers();
            db.exec("ALTER TABLE users DROP COLUMN marketing_agreed_at");

            // 사전 점검의 문장이어야 한다. 이 가드를 빼도 옮기기·DROP 이 "아홉일 때만" 이라
            // 아무것도 안 하고 사후 검증에서 죽는데, 그러면 사람이 보는 메시지가 "사후 검증
            // 실패" 라 무엇을 봐야 하는지 모른다(빨간불 증명 B).
            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("일부만");

            assertThat(db.columns("users")).contains("agree_tos", "tos_version");
            assertThat(db.count("user_consent")).as("옮기기도 시작하면 안 된다").isZero();
        }
    }

    @Test
    @DisplayName("두 번 돌려도 같은 상태로 끝난다 — 컬럼이 이미 없으면 지나간다")
    void isIdempotent() throws Exception {
        try (Fixture db = fixture()) {
            db.createUsersWithOldColumns();
            db.createUserConsent();
            db.seedThreeUsers();

            db.runMigration();
            int consentsAfterFirst = db.count("user_consent");
            db.runMigration();

            assertThat(db.columns("users")).doesNotContainAnyElementsOf(OLD_COLUMNS);
            assertThat(db.count("user_consent")).isEqualTo(consentsAfterFirst).isEqualTo(5);
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
            synchronized (UsersConsentColumnsDropMigrationExecutionTest.class) {
                name = "users_consent_drop_test_" + (++dbCounter);
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

        /** 삭제 직전 {@code 01_schema.sql} 의 users 에서 이 검사에 필요한 컬럼만. 아홉은 그대로. */
        void createUsersWithOldColumns() throws SQLException {
            exec("""
                    CREATE TABLE users (
                      id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
                      email varchar(255) DEFAULT NULL,
                      role varchar(20) NOT NULL,
                      created_at datetime(6) DEFAULT NULL,
                      agree_tos bit(1) DEFAULT NULL,
                      agree_privacy bit(1) DEFAULT NULL,
                      agree_marketing bit(1) DEFAULT NULL,
                      tos_version varchar(255) DEFAULT NULL,
                      privacy_version varchar(255) DEFAULT NULL,
                      marketing_version varchar(255) DEFAULT NULL,
                      tos_agreed_at datetime(6) DEFAULT NULL,
                      privacy_agreed_at datetime(6) DEFAULT NULL,
                      marketing_agreed_at datetime(6) DEFAULT NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
        }

        /** 19 가 만드는 표 — {@code 01_schema.sql} 의 DDL 그대로. */
        void createUserConsent() throws SQLException {
            exec("""
                    CREATE TABLE user_consent (
                      agreed bit(1) NOT NULL,
                      created_at datetime(6) NOT NULL,
                      id bigint NOT NULL AUTO_INCREMENT,
                      user_id bigint NOT NULL,
                      kind varchar(16) NOT NULL,
                      version varchar(16) NOT NULL,
                      PRIMARY KEY (id),
                      KEY idx_user_consent_user (user_id, id),
                      CONSTRAINT chk_user_consent_kind CHECK (kind in ('TERMS','PRIVACY','LOCATION','MARKETING'))
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
        }

        void seedThreeUsers() throws SQLException {
            // 1: 이메일 가입, 셋 다 동의, 버전·시각 있음
            exec("INSERT INTO users (id, email, role, created_at, agree_tos, agree_privacy, agree_marketing, "
                    + "tos_version, privacy_version, marketing_version, tos_agreed_at, privacy_agreed_at, marketing_agreed_at) "
                    + "VALUES (1, 'all@example.com', 'ROLE_USER', '2026-09-01 01:02:03', 1, 1, 1, "
                    + "'v1.2', 'v1.3', 'v1.0', '2026-09-01 01:02:03', '2026-09-01 01:02:03', '2026-09-02 04:05:06')");
            // 2: 이메일 가입, 필수만, 버전·시각 없음(옛 코드가 버전을 안 적던 시절)
            exec("INSERT INTO users (id, email, role, created_at, agree_tos, agree_privacy, agree_marketing) "
                    + "VALUES (2, 'req@example.com', 'ROLE_USER', '2026-08-15 00:00:00', 1, 1, 0)");
            // 3: 소셜 가입 — 아홉 칸 전부 NULL
            exec("INSERT INTO users (id, email, role, created_at) "
                    + "VALUES (3, 'social@example.com', 'ROLE_USER', '2026-08-20 00:00:00')");
        }

        void runMigration() throws Exception {
            String sql = Files.readString(
                    TestProjectPaths.requireFile(SCRIPT), StandardCharsets.UTF_8);
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

        List<String> columns(String table) throws SQLException {
            return query("SELECT column_name FROM information_schema.columns "
                    + "WHERE table_schema = DATABASE() AND table_name = '" + table + "' "
                    + "ORDER BY column_name");
        }

        /** {@code kind|version|agreed|created_at} — 값을 통째로 견준다. */
        List<String> consents(long userId) throws SQLException {
            return query("SELECT CONCAT(kind, '|', version, '|', agreed + 0, '|', "
                    + "DATE_FORMAT(created_at, '%Y-%m-%d %H:%i:%s.%f')) "
                    + "FROM user_consent WHERE user_id = " + userId + " ORDER BY id");
        }

        int count(String table) throws SQLException {
            return query("SELECT COUNT(*) FROM " + table).stream()
                    .findFirst().map(Integer::parseInt).orElse(-1);
        }

        List<String> query(String sql) throws SQLException {
            List<String> out = new ArrayList<>();
            try (Statement st = connection.createStatement();
                 ResultSet rs = st.executeQuery(sql)) {
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
