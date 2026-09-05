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
 * {@code 20_drop_chat_report.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — 이슈 #281.
 *
 * <h2>왜 실행 테스트인가</h2>
 * <p>이 스크립트는 표를 <b>지운다.</b> 더하는 스크립트는 틀려도 validate 가 부팅을 막아
 * 주지만, 지우는 스크립트가 틀리면 — 행이 있는데 지나가거나, 멈춘다면서 반쯤 지우거나 —
 * 아무도 안 막아 준다. 지운 것은 되돌릴 수 없다. 그래서 여기서 네 가지를 실제로 돌려 본다.
 *
 * <ol>
 *   <li>두 표가 비어 있으면 지운다. 새 신고 표({@code report}·{@code report_snapshot})는 그대로다.</li>
 *   <li>행이 하나라도 있으면 <b>한 글자도 안 바꾸고</b> 멈춘다 — 부모에만 있어도, 자식에도 있어도.</li>
 *   <li>새 신고 표가 없으면 시작하지 않는다 — 옛 표를 지우면 신고를 적을 곳이 없어진다.</li>
 *   <li>두 번 돌려도 같은 상태로 끝난다.</li>
 * </ol>
 *
 * <p>옛 표는 {@code 01_schema.sql} 의 옛 판 DDL 그대로 만든다(FK·UNIQUE 포함). 모양이 다르면
 * 자식 행을 넣는 경우가 실제와 달라진다.
 */
class ChatReportDropMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/20_drop_chat_report.sql";

    private static int dbCounter = 0;

    @Test
    @DisplayName("두 표가 비어 있으면 지운다 — 새 신고 표 둘은 그대로다")
    void dropsBothTablesWhenEmpty() throws Exception {
        try (Fixture db = fixture()) {
            db.createNewReportTables();
            db.createOldChatReportTables();

            db.runMigration();

            assertThat(db.tables())
                    .doesNotContain("chat_report", "chat_reported_message")
                    .contains("report", "report_snapshot");
        }
    }

    @Test
    @DisplayName("chat_report 에 행이 있으면 멈추고 한 글자도 안 바꾼다 — 신고는 다시 만들 수 없다")
    void abortsWhenTheParentHasRows() throws Exception {
        try (Fixture db = fixture()) {
            db.createNewReportTables();
            db.createOldChatReportTables();
            db.seedOneOldReport(false);

            assertThatThrownBy(db::runMigration)
                    .as("행이 있는데 지나가면 신고 기록이 소리 없이 사라진다")
                    .isInstanceOf(SQLException.class);

            assertThat(db.tables()).contains("chat_report", "chat_reported_message");
            assertThat(db.count("chat_report")).isEqualTo(1);
        }
    }

    @Test
    @DisplayName("사본 표(chat_reported_message)에 행이 있어도 멈춘다 — 부모만 보면 안 된다")
    void abortsWhenTheChildHasRows() throws Exception {
        try (Fixture db = fixture()) {
            db.createNewReportTables();
            db.createOldChatReportTables();
            db.seedOneOldReport(true);

            assertThatThrownBy(db::runMigration).isInstanceOf(SQLException.class);

            assertThat(db.tables()).contains("chat_report", "chat_reported_message");
            assertThat(db.count("chat_reported_message")).isEqualTo(1);
        }
    }

    @Test
    @DisplayName("새 신고 표가 없으면 시작하지 않는다 — 옛 표를 지우면 신고를 적을 곳이 없어진다")
    void abortsWithoutTheNewReportTables() throws Exception {
        try (Fixture db = fixture()) {
            db.createOldChatReportTables();

            assertThatThrownBy(db::runMigration)
                    .as("15_report.sql 이 안 돈 DB 다. 사전 점검에서 멈춰야 한다")
                    .isInstanceOf(SQLException.class);

            assertThat(db.tables())
                    .as("멈췄으면 옛 표가 그대로 있어야 한다 — 지운 뒤 멈추는 것은 멈춤이 아니다")
                    .contains("chat_report", "chat_reported_message");
        }
    }

    @Test
    @DisplayName("두 번 돌려도 같은 상태로 끝난다 — 표가 이미 없으면 지나간다")
    void isIdempotent() throws Exception {
        try (Fixture db = fixture()) {
            db.createNewReportTables();
            db.createOldChatReportTables();

            db.runMigration();
            db.runMigration();

            assertThat(db.tables())
                    .doesNotContain("chat_report", "chat_reported_message")
                    .contains("report", "report_snapshot");
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
            synchronized (ChatReportDropMigrationExecutionTest.class) {
                name = "chat_report_drop_test_" + (++dbCounter);
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

        /** 새 신고 표. 이 스크립트는 존재만 보므로 컬럼은 최소로 둔다. */
        void createNewReportTables() throws SQLException {
            exec("CREATE TABLE report (id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY) "
                    + "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
            exec("CREATE TABLE report_snapshot (id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY) "
                    + "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
        }

        /** 옛 표 둘 — #281 직전 {@code 01_schema.sql} 의 DDL 그대로. */
        void createOldChatReportTables() throws SQLException {
            exec("""
                    CREATE TABLE `chat_report` (
                      `context_from_seq` bigint NOT NULL,
                      `context_to_seq` bigint NOT NULL,
                      `created_at` datetime(6) NOT NULL,
                      `id` bigint NOT NULL AUTO_INCREMENT,
                      `reported_user_id` bigint NOT NULL,
                      `reporter_user_id` bigint NOT NULL,
                      `room_id` bigint NOT NULL,
                      `reason` varchar(16) NOT NULL,
                      `memo` varchar(500) DEFAULT NULL,
                      PRIMARY KEY (`id`),
                      KEY `idx_chat_report_reported` (`reported_user_id`),
                      KEY `idx_chat_report_reporter` (`reporter_user_id`),
                      KEY `idx_chat_report_room` (`room_id`)
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
                    """);
            exec("""
                    CREATE TABLE `chat_reported_message` (
                      `id` bigint NOT NULL AUTO_INCREMENT,
                      `message_id` bigint DEFAULT NULL,
                      `report_id` bigint NOT NULL,
                      `room_seq` bigint NOT NULL,
                      `sender_user_id` bigint NOT NULL,
                      `sent_at` datetime(6) NOT NULL,
                      `content_type` varchar(16) NOT NULL,
                      `body` text NOT NULL,
                      `sender_name` varchar(255) NOT NULL,
                      PRIMARY KEY (`id`),
                      UNIQUE KEY `uq_chat_reported_msg` (`report_id`,`room_seq`),
                      CONSTRAINT `fk_chat_reported_msg_report` FOREIGN KEY (`report_id`)
                        REFERENCES `chat_report` (`id`) ON DELETE CASCADE
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
                    """);
        }

        void seedOneOldReport(boolean withSnapshot) throws SQLException {
            exec("INSERT INTO chat_report (id, context_from_seq, context_to_seq, created_at, "
                    + "reported_user_id, reporter_user_id, room_id, reason, memo) "
                    + "VALUES (1, 1, 11, NOW(6), 2, 1, 1, 'abuse', NULL)");
            if (withSnapshot) {
                exec("INSERT INTO chat_reported_message (id, message_id, report_id, room_seq, "
                        + "sender_user_id, sent_at, content_type, body, sender_name) "
                        + "VALUES (1, 6, 1, 6, 2, NOW(6), 'text', '본문', '트롤')");
            }
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

        List<String> tables() throws SQLException {
            return query("""
                    SELECT table_name FROM information_schema.tables
                    WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE'
                    ORDER BY table_name
                    """);
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
