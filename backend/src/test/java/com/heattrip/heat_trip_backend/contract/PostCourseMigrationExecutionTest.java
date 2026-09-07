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
 * {@code 28_post_course.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — #339.
 *
 * <p>여기서 틀리면 아픈 것은 FK 의 삭제 규칙 하나다. {@code CASCADE} 로 들어가면 코스 하나를
 * 지우다 <b>거기 붙은 글이 통째로 사라진다.</b> 글은 사람이 쓴 문장이고 코스는 거기 붙은
 * 그림이라, 그림이 사라져도 글은 남아야 한다. 그래서 {@code delete_rule} 을 직접 읽는다.
 */
class PostCourseMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/28_post_course.sql";

    private static int dbCounter = 0;

    @Test
    @DisplayName("course_id 가 NULL 허용으로 생기고 FK 가 SET NULL 이다")
    void addsANullableCourseIdWithSetNull() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true, true);
            db.seed();

            db.runMigration();

            assertThat(db.columnShape("course_id")).isEqualTo("bigint|YES");
            assertThat(db.deleteRule("fk_post_course")).isEqualTo("SET NULL");
            assertThat(db.query("SELECT CONCAT(title, '|', IFNULL(course_id, 'NULL')) FROM post"))
                    .as("이 스크립트는 글에 코스를 붙이지 않는다")
                    .containsExactly("서울숲 다녀왔어요|NULL");
        }
    }

    @Test
    @DisplayName("코스를 지워도 글은 남고 연결만 빈다")
    void keepsThePostWhenTheCourseIsDeleted() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true, true);
            db.seed();
            db.runMigration();
            db.exec("UPDATE post SET course_id = 1 WHERE id = 1");

            db.exec("DELETE FROM course WHERE id = 1");

            assertThat(db.query("SELECT CONCAT(title, '|', IFNULL(course_id, 'NULL')) FROM post"))
                    .containsExactly("서울숲 다녀왔어요|NULL");
        }
    }

    @Test
    @DisplayName("두 번 돌려도 같은 상태다 — 멱등")
    void secondRunIsIdempotent() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true, true);

            db.runMigration();
            db.runMigration();

            assertThat(db.columns("post")).containsOnlyOnce("course_id");
            assertThat(db.query("SELECT COUNT(*) FROM information_schema.referential_constraints "
                    + "WHERE constraint_schema = DATABASE() AND constraint_name = 'fk_post_course'"))
                    .containsExactly("1");
        }
    }

    @Test
    @DisplayName("course 표가 없으면 멈춘다 — 27 이 먼저다")
    void abortsWithoutTheCourseTable() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true, false);

            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("27_course.sql");
        }
    }

    @Test
    @DisplayName("같은 이름의 컬럼이 다른 타입으로 있으면 멈춘다")
    void abortsWhenTheColumnHasAnotherType() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true, true);
            db.exec("ALTER TABLE post ADD COLUMN course_id varchar(20) NULL");

            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("사람이 확인하라");

            assertThat(db.columnShape("course_id")).isEqualTo("varchar|YES");
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
            synchronized (PostCourseMigrationExecutionTest.class) {
                name = "post_course_test_" + (++dbCounter);
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

        void createTables(boolean withPost, boolean withCourse) throws SQLException {
            exec("""
                    CREATE TABLE users (
                      id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
                      email varchar(255) DEFAULT NULL,
                      role varchar(20) NOT NULL,
                      created_at datetime(6) DEFAULT NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
            if (withPost) {
                exec("""
                        CREATE TABLE post (
                          id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
                          user_id bigint DEFAULT NULL,
                          board varchar(20) NOT NULL,
                          title varchar(200) NOT NULL,
                          body text NOT NULL,
                          created_at datetime(6) NOT NULL,
                          CONSTRAINT fk_post_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE SET NULL
                        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                        """);
            }
            if (withCourse) {
                exec("""
                        CREATE TABLE course (
                          id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
                          user_id bigint NOT NULL,
                          name varchar(60) NOT NULL,
                          distance_m int NOT NULL,
                          duration_s int NOT NULL,
                          visibility varchar(10) NOT NULL DEFAULT 'private',
                          created_at datetime(6) NOT NULL,
                          CONSTRAINT fk_course_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
                        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                        """);
            }
        }

        void seed() throws SQLException {
            exec("INSERT INTO users (id, email, role, created_at) "
                    + "VALUES (1, 'owner@example.com', 'ROLE_USER', NOW(6))");
            exec("INSERT INTO post (id, user_id, board, title, body, created_at) "
                    + "VALUES (1, 1, 'walk_review', '서울숲 다녀왔어요', '좋았습니다', NOW(6))");
            exec("INSERT INTO course (id, user_id, name, distance_m, duration_s, visibility, created_at) "
                    + "VALUES (1, 1, '서울숲 한 바퀴', 400, 900, 'public', NOW(6))");
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

        /** {@code 타입|NULL허용} — 없으면 {@code (없음)}. */
        String columnShape(String column) throws SQLException {
            return query("SELECT CONCAT(data_type, '|', is_nullable) FROM information_schema.columns "
                    + "WHERE table_schema = DATABASE() AND table_name = 'post' AND column_name = '" + column + "'")
                    .stream().findFirst().orElse("(없음)");
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
