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
 * {@code 41_post_dog.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — #451 5번.
 *
 * <p>가장 중요한 것은 <b>FK 가 {@code SET NULL} 인가</b>다. {@code CASCADE} 로 잘못 서면 아이를
 * 물리 삭제하는 날 그 아이가 찍힌 글이 통째로 사라진다 — 글은 사람이 쓴 것이고 아이 연결은
 * 꼬리표다. 그다음이 인덱스의 열 순서 — 사진첩 목록이 {@code (dog_id, created_at, id)} 로
 * 내려간다.
 *
 * <p>스프링을 띄우지 않는다(#21).
 */
class PostDogMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/41_post_dog.sql";

    private static int dbCounter = 0;

    @Test
    @DisplayName("컬럼·인덱스·SET NULL FK 가 생기고, 쌓인 글은 그대로다")
    void addsTheColumnIndexAndForeignKey() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites();
            db.exec("INSERT INTO users (id) VALUES (1)");
            db.exec("INSERT INTO post (id, user_id, board, title, body, created_at) VALUES "
                    + "(1, 1, 'free', '옛 글', '본문', NOW(6))");

            db.runMigration();

            assertThat(db.query("SELECT is_nullable FROM information_schema.columns "
                    + "WHERE table_schema = DATABASE() AND table_name = 'post' AND column_name = 'dog_id'"))
                    .as("있던 글은 아이가 없다 — NULL 허용이어야 한다")
                    .containsExactly("YES");
            assertThat(db.query("SELECT column_name FROM information_schema.statistics "
                    + "WHERE table_schema = DATABASE() AND table_name = 'post' "
                    + "AND index_name = 'idx_post_dog' ORDER BY seq_in_index"))
                    .as("사진첩 목록의 커서 축이 dog_id 뒤에 온다")
                    .containsExactly("dog_id", "created_at", "id");
            assertThat(db.query("SELECT delete_rule FROM information_schema.referential_constraints "
                    + "WHERE constraint_schema = DATABASE() AND constraint_name = 'fk_post_dog'"))
                    .as("아이가 사라져도 글은 남는다")
                    .containsExactly("SET NULL");
            assertThat(db.query("SELECT IFNULL(dog_id, '(null)') FROM post WHERE id = 1"))
                    .as("있던 글은 그대로고 아이 연결만 비어 있다")
                    .containsExactly("(null)");
        }
    }

    @Test
    @DisplayName("아이를 지우면 글은 남고 연결만 빈다 — SET NULL")
    void deletingTheDogKeepsThePost() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites();
            db.runMigration();
            db.exec("INSERT INTO users (id) VALUES (1)");
            db.exec("INSERT INTO dog (id, user_id, name) VALUES (7, 1, '보리')");
            db.exec("INSERT INTO post (id, user_id, dog_id, board, title, body, created_at) VALUES "
                    + "(1, 1, 7, 'brag', '보리 사진', '본문', NOW(6))");

            db.exec("DELETE FROM dog WHERE id = 7");

            assertThat(db.query("SELECT COUNT(*) FROM post")).containsExactly("1");
            assertThat(db.query("SELECT IFNULL(dog_id, '(null)') FROM post WHERE id = 1")).containsExactly("(null)");
        }
    }

    @Test
    @DisplayName("없는 아이는 붙일 수 없다 — FK")
    void rejectsAnUnknownDog() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites();
            db.runMigration();
            db.exec("INSERT INTO users (id) VALUES (1)");

            assertThatThrownBy(() -> db.exec("INSERT INTO post (id, user_id, dog_id, board, title, body, created_at) "
                    + "VALUES (1, 1, 999, 'free', '글', '본문', NOW(6))"))
                    .isInstanceOf(SQLException.class);
        }
    }

    @Test
    @DisplayName("두 번 돌려도 그대로다 — 멱등")
    void secondRunIsIdempotent() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites();
            db.runMigration();
            db.exec("INSERT INTO users (id) VALUES (1)");
            db.exec("INSERT INTO dog (id, user_id, name) VALUES (7, 1, '보리')");
            db.exec("INSERT INTO post (id, user_id, dog_id, board, title, body, created_at) VALUES "
                    + "(1, 1, 7, 'brag', '보리 사진', '본문', NOW(6))");

            db.runMigration();

            assertThat(db.query("SELECT dog_id FROM post WHERE id = 1")).containsExactly("7");
            assertThat(db.query("SELECT COUNT(*) FROM information_schema.statistics "
                    + "WHERE table_schema = DATABASE() AND table_name = 'post' AND index_name = 'idx_post_dog'"))
                    .as("인덱스가 두 벌 생기지 않는다").containsExactly("3");
        }
    }

    @Test
    @DisplayName("post 나 dog 가 없으면 멈춘다 — 14·11 을 먼저 돌려야 한다")
    void abortsWithoutThePrerequisites() throws Exception {
        try (Fixture db = fixture()) {
            db.exec("CREATE TABLE users (id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY) ENGINE=InnoDB");
            db.exec("CREATE TABLE dog (id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY, user_id bigint, name varchar(30)) ENGINE=InnoDB");

            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("14_community.sql");
        }
    }

    @Test
    @DisplayName("dog_id 가 이미 있는데 모양이 다르면 멈춘다 — 조용히 덮지 않는다")
    void abortsOnAColumnWithTheWrongShape() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites();
            db.exec("ALTER TABLE post ADD COLUMN dog_id bigint NOT NULL DEFAULT 0");

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
            synchronized (PostDogMigrationExecutionTest.class) {
                name = "postdog_test_" + (++dbCounter);
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

        /** users · dog · post 의 최소 형태. */
        void createPrerequisites() throws SQLException {
            exec("CREATE TABLE users (id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
            exec("""
                    CREATE TABLE dog (
                      id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
                      user_id bigint DEFAULT NULL,
                      name varchar(30) NOT NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
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
