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
 * {@code 27_course.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — #339.
 *
 * <p>이 표에서 틀리면 아픈 것은 두 FK 다. {@code users} 가 CASCADE 여야 탈퇴한 사람의 코스가
 * 남지 않고, {@code walk} 가 <b>SET NULL</b> 이어야 산책 기록을 지운 사람이 자기 코스까지
 * 잃지 않는다. 그래서 information_schema 의 {@code delete_rule} 을 직접 읽는다.
 * 스프링을 띄우지 않는다(#21).
 */
class CourseMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/27_course.sql";

    private static int dbCounter = 0;

    @Test
    @DisplayName("course 표가 생기고 FK 둘이 CASCADE · SET NULL 이다")
    void createsTheCourseTable() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true, true);

            db.runMigration();

            assertThat(db.columns("course")).contains(
                    "id", "user_id", "walk_id", "name", "note", "tags",
                    "path", "distance_m", "duration_s", "visibility", "created_at");
            assertThat(db.deleteRule("fk_course_user")).isEqualTo("CASCADE");
            assertThat(db.deleteRule("fk_course_walk"))
                    .as("산책을 지워도 코스는 남아야 한다")
                    .isEqualTo("SET NULL");
        }
    }

    @Test
    @DisplayName("산책을 지우면 코스의 walk_id 만 비고 코스는 남는다")
    void keepsTheCourseWhenTheWalkIsDeleted() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true, true);
            db.runMigration();
            db.seedCourse();

            db.exec("DELETE FROM walk WHERE id = 1");

            assertThat(db.query("SELECT CONCAT(name, '|', IFNULL(walk_id, 'NULL')) FROM course"))
                    .containsExactly("서울숲 한 바퀴|NULL");
        }
    }

    @Test
    @DisplayName("사람이 탈퇴하면 코스도 함께 사라진다 — 그 사람의 글이다")
    void removesCoursesWithTheUser() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true, true);
            db.runMigration();
            db.seedCourse();

            db.exec("DELETE FROM users WHERE id = 1");

            assertThat(db.query("SELECT COUNT(*) FROM course")).containsExactly("0");
        }
    }

    @Test
    @DisplayName("공개 범위는 둘 중 하나여야 한다 — CHECK 가 막는다")
    void rejectsAnUnknownVisibility() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true, true);
            db.runMigration();
            db.seedCourse();

            assertThatThrownBy(() -> db.exec("UPDATE course SET visibility = 'friends' WHERE id = 1"))
                    .isInstanceOf(SQLException.class);
        }
    }

    @Test
    @DisplayName("두 번 돌려도 같은 상태다 — 멱등")
    void secondRunIsIdempotent() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true, true);

            db.runMigration();
            db.runMigration();

            assertThat(db.query("SELECT COUNT(*) FROM information_schema.tables "
                    + "WHERE table_schema = DATABASE() AND table_name = 'course'"))
                    .containsExactly("1");
        }
    }

    @Test
    @DisplayName("users 나 walk 가 없으면 멈춘다 — 앞 스크립트가 먼저다")
    void abortsWithoutItsPrerequisites() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true, false);

            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("12_walk.sql");
        }
    }

    @Test
    @DisplayName("같은 이름의 표가 컬럼이 모자란 채로 있으면 멈춘다 — 사람이 봐야 한다")
    void abortsWhenAPartialTableExists() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true, true);
            db.exec("CREATE TABLE course (id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY, "
                    + "name varchar(60) NOT NULL)");

            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("사람이 확인하라");

            assertThat(db.columns("course"))
                    .as("멈췄으면 손대지 않았어야 한다")
                    .containsExactly("id", "name");
        }
    }

    // ─────────────────────────── 픽스처 ─────────────────

    private static Fixture fixture() throws SQLException {
        return new Fixture();
    }

    private static final class Fixture implements AutoCloseable {

        private final String name;
        private final Connection connection;

        Fixture() throws SQLException {
            MySQLContainer<?> mysql = MySqlTestContainer.instance();
            synchronized (CourseMigrationExecutionTest.class) {
                name = "course_test_" + (++dbCounter);
            }
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

        void createTables(boolean withUsers, boolean withWalk) throws SQLException {
            if (withUsers) {
                exec("""
                        CREATE TABLE users (
                          id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
                          email varchar(255) DEFAULT NULL,
                          role varchar(20) NOT NULL,
                          created_at datetime(6) DEFAULT NULL
                        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                        """);
            }
            if (withWalk) {
                exec("""
                        CREATE TABLE dog (
                          id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
                          name varchar(50) NOT NULL
                        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                        """);
                exec("""
                        CREATE TABLE walk (
                          id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
                          dog_id bigint NOT NULL,
                          client_walk_id varchar(64) NOT NULL,
                          started_at datetime(6) NOT NULL,
                          distance_m int NOT NULL,
                          duration_s int NOT NULL,
                          created_at datetime(6) NOT NULL,
                          CONSTRAINT fk_walk_dog FOREIGN KEY (dog_id) REFERENCES dog (id) ON DELETE CASCADE
                        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                        """);
            }
        }

        void seedCourse() throws SQLException {
            exec("INSERT INTO users (id, email, role, created_at) "
                    + "VALUES (1, 'owner@example.com', 'ROLE_USER', NOW(6))");
            exec("INSERT INTO dog (id, name) VALUES (1, '초코')");
            exec("INSERT INTO walk (id, dog_id, client_walk_id, started_at, distance_m, duration_s, created_at) "
                    + "VALUES (1, 1, 'walk-0001', NOW(6), 1200, 900, NOW(6))");
            exec("INSERT INTO course (id, user_id, walk_id, name, path, distance_m, duration_s, "
                    + "visibility, created_at) VALUES (1, 1, 1, '서울숲 한 바퀴', "
                    // SRID 4326 의 WKT 는 기본이 (위도 경도) 순서다. 계약과 같은 (경도 위도) 로 적으려면
                    // axis-order 를 말해 줘야 한다 — 안 그러면 "위도 127" 이라고 거절당한다.
                    + "ST_GeomFromText('LINESTRING(127.04 37.54, 127.05 37.55)', 4326, 'axis-order=long-lat'), 400, 900, "
                    + "'private', NOW(6))");
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

        String deleteRule(String constraint) throws SQLException {
            return query("SELECT delete_rule FROM information_schema.referential_constraints "
                    + "WHERE constraint_schema = DATABASE() AND constraint_name = '" + constraint + "'")
                    .stream().findFirst().orElse("(없음)");
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
