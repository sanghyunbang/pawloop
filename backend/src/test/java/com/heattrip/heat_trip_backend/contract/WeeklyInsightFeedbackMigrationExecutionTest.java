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
 * {@code 46_weekly_insight_feedback.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — AI 요약 👍/👎(#486 후속).
 *
 * <p>재는 것은 셋이다: 컬럼 둘이 NULL 허용으로 생겨 쌓인 요약이 그대로인가, CHECK 가 {@code up}·{@code down}
 * 밖의 값을 막는가, 두 번 돌려도 그대로인가. 스프링을 띄우지 않는다(#21).
 */
class WeeklyInsightFeedbackMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/46_weekly_insight_feedback.sql";

    private static int dbCounter = 0;

    @Test
    @DisplayName("feedback · feedback_at 이 NULL 허용으로 생기고 CHECK 가 서며, 쌓인 요약은 그대로다")
    void addsTheColumnsAndTheCheck() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites();
            db.insertInsight(1, "이번 주는 잘 걸었어요.");

            db.runMigration();

            assertThat(db.query("SELECT column_name FROM information_schema.columns "
                    + "WHERE table_schema = DATABASE() AND table_name = 'weekly_insight' "
                    + "AND column_name IN ('feedback', 'feedback_at') AND is_nullable = 'YES' ORDER BY column_name"))
                    .containsExactly("feedback", "feedback_at");
            assertThat(db.query("SELECT constraint_name FROM information_schema.table_constraints "
                    + "WHERE table_schema = DATABASE() AND table_name = 'weekly_insight' AND constraint_type = 'CHECK'"))
                    .contains("ck_weekly_insight_feedback");
            assertThat(db.query("SELECT IFNULL(feedback, '(null)') FROM weekly_insight WHERE id = 1"))
                    .as("있던 요약은 아직 평가가 없다")
                    .containsExactly("(null)");
        }
    }

    @Test
    @DisplayName("up · down 만 들어간다 — 다른 값은 CHECK 가 막는다")
    void checkAllowsOnlyUpAndDown() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites();
            db.runMigration();
            db.insertInsight(1, "문장");

            db.exec("UPDATE weekly_insight SET feedback = 'up', feedback_at = NOW(6) WHERE id = 1");
            db.exec("UPDATE weekly_insight SET feedback = 'down' WHERE id = 1");
            db.exec("UPDATE weekly_insight SET feedback = NULL, feedback_at = NULL WHERE id = 1");

            assertThatThrownBy(() -> db.exec("UPDATE weekly_insight SET feedback = 'meh' WHERE id = 1"))
                    .isInstanceOf(SQLException.class);
        }
    }

    @Test
    @DisplayName("두 번 돌려도 그대로다 — 멱등")
    void secondRunIsIdempotent() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites();
            db.runMigration();
            db.insertInsight(1, "문장");
            db.exec("UPDATE weekly_insight SET feedback = 'up', feedback_at = NOW(6) WHERE id = 1");

            db.runMigration();

            assertThat(db.query("SELECT feedback FROM weekly_insight WHERE id = 1")).containsExactly("up");
            assertThat(db.query("SELECT COUNT(*) FROM information_schema.table_constraints "
                    + "WHERE table_schema = DATABASE() AND table_name = 'weekly_insight' "
                    + "AND constraint_type = 'CHECK' AND constraint_name = 'ck_weekly_insight_feedback'"))
                    .as("CHECK 가 두 벌 생기지 않는다").containsExactly("1");
        }
    }

    @Test
    @DisplayName("weekly_insight 가 없으면 멈춘다 — 44 를 먼저 돌려야 한다")
    void abortsWithoutThePrerequisite() throws Exception {
        try (Fixture db = fixture()) {
            db.exec("CREATE TABLE users (id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY) ENGINE=InnoDB");

            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("44_weekly_insight.sql");
        }
    }

    @Test
    @DisplayName("feedback 이 이미 있는데 모양이 다르면 멈춘다 — 조용히 덮지 않는다")
    void abortsOnAColumnWithTheWrongShape() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites();
            db.exec("ALTER TABLE weekly_insight ADD COLUMN feedback int NOT NULL DEFAULT 0");

            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("사람이 확인하라");
        }
    }

    // ─────────────────────────── 지그 ─────────────────

    private static Fixture fixture() throws SQLException {
        return new Fixture();
    }

    private static final class Fixture implements AutoCloseable {

        private final String name;
        private final Connection connection;

        Fixture() throws SQLException {
            MySQLContainer<?> mysql = MySqlTestContainer.instance();
            synchronized (WeeklyInsightFeedbackMigrationExecutionTest.class) {
                name = "insight_feedback_mig_" + (++dbCounter);
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

        /** users · weekly_insight — 44 가 만드는 모양 그대로. */
        void createPrerequisites() throws SQLException {
            exec("CREATE TABLE users (id bigint NOT NULL AUTO_INCREMENT, email varchar(255) NOT NULL, "
                    + "PRIMARY KEY (id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci");
            exec("""
                    CREATE TABLE weekly_insight (
                      id bigint NOT NULL AUTO_INCREMENT,
                      user_id bigint NOT NULL,
                      dog_id bigint NOT NULL,
                      week_start date NOT NULL,
                      input_hash varchar(64) NOT NULL,
                      model varchar(64) NOT NULL,
                      text text,
                      calls int NOT NULL,
                      generated_at datetime(6) NOT NULL,
                      PRIMARY KEY (id),
                      UNIQUE KEY uq_weekly_insight (user_id, dog_id, week_start),
                      KEY idx_weekly_insight_generated (generated_at),
                      CONSTRAINT fk_weekly_insight_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
                    """);
            exec("INSERT INTO users (id, email) VALUES (1, 'a@example.com')");
        }

        void insertInsight(long id, String text) throws SQLException {
            exec("INSERT INTO weekly_insight (id, user_id, dog_id, week_start, input_hash, model, text, calls, generated_at) "
                    + "VALUES (" + id + ", 1, 0, '2026-09-14', 'h', 'fake', '" + text + "', 1, NOW(6))");
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
