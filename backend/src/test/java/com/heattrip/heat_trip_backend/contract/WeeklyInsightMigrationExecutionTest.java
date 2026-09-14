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

/** 44_weekly_insight.sql 을 진짜 MySQL 에 돌려 본다 — 이슈 #486. */
class WeeklyInsightMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/44_weekly_insight.sql";

    private static int dbCounter = 0;

    @Test
    @DisplayName("표가 생기고 (user, dog, week) 유니크 · 날짜 인덱스 · CASCADE FK 가 함께 선다")
    void createsTheTableWithItsIndexesAndCascade() throws Exception {
        try (Fixture db = fixture()) {
            db.createUsers();

            db.runMigration();

            assertThat(db.query("SELECT column_name FROM information_schema.columns "
                    + "WHERE table_schema = DATABASE() AND table_name = 'weekly_insight' ORDER BY column_name"))
                    .containsExactly("calls", "dog_id", "generated_at", "id", "input_hash", "model", "text",
                            "user_id", "week_start");
            assertThat(db.query("SELECT column_name FROM information_schema.statistics "
                    + "WHERE table_schema = DATABASE() AND table_name = 'weekly_insight' "
                    + "AND index_name = 'uq_weekly_insight' AND non_unique = 0 ORDER BY seq_in_index"))
                    .as("한 사람 · 한 아이 · 한 주에 행 하나 — 캐시의 열쇠")
                    .containsExactly("user_id", "dog_id", "week_start");
            assertThat(db.query("SELECT column_name FROM information_schema.statistics "
                    + "WHERE table_schema = DATABASE() AND table_name = 'weekly_insight' "
                    + "AND index_name = 'idx_weekly_insight_generated'"))
                    .containsExactly("generated_at");
            assertThat(db.query("SELECT delete_rule FROM information_schema.referential_constraints "
                    + "WHERE constraint_schema = DATABASE() AND constraint_name = 'fk_weekly_insight_user'"))
                    .containsExactly("CASCADE");
        }
    }

    @Test
    @DisplayName("탈퇴하면 요약도 사라진다 · 같은 주에 두 행은 못 넣는다")
    void cascadesAndKeepsOneRowPerWeek() throws Exception {
        try (Fixture db = fixture()) {
            db.createUsers();
            db.runMigration();
            db.exec("INSERT INTO users (id, email) VALUES (1, 'a@example.com'), (2, 'b@example.com')");
            db.exec("INSERT INTO weekly_insight (user_id, dog_id, week_start, input_hash, model, text, calls, generated_at) VALUES "
                    + "(1, 0, '2026-09-07', 'h1', 'fake', '문장', 1, NOW(6)), (2, 0, '2026-09-07', 'h2', 'fake', NULL, 1, NOW(6))");

            assertThatThrownBy(() -> db.exec("INSERT INTO weekly_insight (user_id, dog_id, week_start, input_hash, model, text, calls, generated_at) VALUES "
                    + "(1, 0, '2026-09-07', 'h3', 'fake', '둘째', 1, NOW(6))"))
                    .isInstanceOf(SQLException.class);

            db.exec("DELETE FROM users WHERE id = 2");
            assertThat(db.query("SELECT user_id FROM weekly_insight")).containsExactly("1");
        }
    }

    @Test
    @DisplayName("두 번 돌려도 그대로다 — 멱등")
    void secondRunIsIdempotent() throws Exception {
        try (Fixture db = fixture()) {
            db.createUsers();
            db.runMigration();
            db.exec("INSERT INTO users (id, email) VALUES (1, 'a@example.com')");
            db.exec("INSERT INTO weekly_insight (user_id, dog_id, week_start, input_hash, model, text, calls, generated_at) VALUES "
                    + "(1, 0, '2026-09-07', 'h1', 'fake', '문장', 1, NOW(6))");

            db.runMigration();

            assertThat(db.query("SELECT COUNT(*) FROM weekly_insight")).containsExactly("1");
        }
    }

    @Test
    @DisplayName("users 가 없으면 멈춘다")
    void abortsWithoutTheUsersTable() throws Exception {
        try (Fixture db = fixture()) {
            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("users");
        }
    }

    @Test
    @DisplayName("Hibernate 가 먼저 만든 표(유니크 · FK 이름이 다르다)는 사후 검증이 멈춰 세운다")
    void refusesATableWithoutTheNamedConstraints() throws Exception {
        try (Fixture db = fixture()) {
            db.createUsers();
            db.exec("""
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
                      PRIMARY KEY (id)
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);

            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("사후 검증");
        }
    }

    private static Fixture fixture() throws SQLException {
        return new Fixture();
    }

    private static final class Fixture implements AutoCloseable {

        private final String name;
        private final Connection connection;

        Fixture() throws SQLException {
            MySQLContainer<?> mysql = MySqlTestContainer.instance();
            synchronized (WeeklyInsightMigrationExecutionTest.class) {
                name = "weekly_insight_mig_" + (++dbCounter);
            }
            // 컨테이너의 일반 계정은 새 DB 를 못 만든다 — root 로(40 과 같은 모양).
            String serverUrl = mysql.getJdbcUrl().replaceAll("/[^/?]+(\\?|$)", "/$1");
            try (Connection admin = DriverManager.getConnection(serverUrl, "root", mysql.getPassword());
                 Statement st = admin.createStatement()) {
                st.execute("DROP DATABASE IF EXISTS " + name);
                st.execute("CREATE DATABASE " + name + " CHARACTER SET utf8mb4");
            }
            connection = DriverManager.getConnection(
                    serverUrl.replaceFirst("/(\\?|$)", "/" + name + "$1"), "root", mysql.getPassword());
        }

        void createUsers() throws SQLException {
            exec("CREATE TABLE users (id bigint NOT NULL AUTO_INCREMENT, email varchar(255) NOT NULL, "
                    + "PRIMARY KEY (id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci");
        }

        void runMigration() throws Exception {
            String sql = Files.readString(TestProjectPaths.requireFile(SCRIPT), StandardCharsets.UTF_8);
            for (String statement : splitStatements(sql)) {
                exec(statement);
            }
        }

        void exec(String sql) throws SQLException {
            try (Statement s = connection.createStatement()) {
                s.execute(sql);
            }
        }

        List<String> query(String sql) throws SQLException {
            List<String> out = new ArrayList<>();
            try (Statement s = connection.createStatement(); ResultSet rs = s.executeQuery(sql)) {
                while (rs.next()) {
                    out.add(rs.getString(1));
                }
            }
            return out;
        }

        @Override
        public void close() throws SQLException {
            MySQLContainer<?> mysql = MySqlTestContainer.instance();
            String serverUrl = mysql.getJdbcUrl().replaceAll("/[^/?]+(\\?|$)", "/$1");
            connection.close();
            try (Connection admin = DriverManager.getConnection(serverUrl, "root", mysql.getPassword());
                 Statement st = admin.createStatement()) {
                st.execute("DROP DATABASE IF EXISTS " + name);
            }
        }

        /** 주석 줄을 걷어낸 뒤 세미콜론으로 나눈다 — 프로시저 본문은 한 줄짜리 SIGNAL 이라 나뉘지 않는다. */
        private static List<String> splitStatements(String sql) {
            String stripped = Arrays.stream(sql.split("\n"))
                    .filter(line -> !line.trim().startsWith("--"))
                    .collect(Collectors.joining("\n"));
            List<String> out = new ArrayList<>();
            for (String part : stripped.split(";")) {
                if (!part.isBlank()) {
                    out.add(part.trim());
                }
            }
            return out;
        }
    }
}
