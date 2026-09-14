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
 * {@code 40_post_bookmark.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — #451 4번.
 *
 * <h2>여기서 가장 중요한 것</h2>
 * <p><b>FK 둘이 다 {@code CASCADE} 인가.</b> {@code reaction} 은 사람 쪽이 {@code SET NULL}
 * 인데 여기는 아니다 — 저장은 그 사람만 보는 목록이라 탈퇴하면 목록째 사라져야 한다. 반대로
 * 서면(SET NULL) {@code user_id NOT NULL} 과 충돌해 탈퇴 자체가 실패한다.
 *
 * <p>그다음이 <b>유니크와 목록 인덱스</b>다. 유니크가 없으면 멱등 삽입이 중복 행을 만들고,
 * 목록 인덱스가 없으면 "내가 저장한 글" 이 표 전체를 훑는다. {@code SchemaDdlDriftTest} 는
 * 컬럼만 보고 인덱스·FK 는 안 본다.
 *
 * <p>스프링을 띄우지 않는다(#21).
 */
class PostBookmarkMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/40_post_bookmark.sql";

    private static int dbCounter = 0;

    @Test
    @DisplayName("표가 생기고 유니크·목록 인덱스·CASCADE FK 둘이 함께 선다")
    void createsTheTableWithItsIndexesAndCascades() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites();

            db.runMigration();

            assertThat(db.query("SELECT column_name FROM information_schema.columns "
                    + "WHERE table_schema = DATABASE() AND table_name = 'post_bookmark' "
                    + "ORDER BY column_name"))
                    .containsExactly("created_at", "id", "post_id", "user_id");

            assertThat(db.query("SELECT column_name FROM information_schema.statistics "
                    + "WHERE table_schema = DATABASE() AND table_name = 'post_bookmark' "
                    + "AND index_name = 'uq_post_bookmark' AND non_unique = 0 ORDER BY seq_in_index"))
                    .as("한 사람이 한 글을 두 번 저장할 수 없다 — 멱등 삽입이 이 유니크를 딛는다")
                    .containsExactly("post_id", "user_id");

            assertThat(db.query("SELECT column_name FROM information_schema.statistics "
                    + "WHERE table_schema = DATABASE() AND table_name = 'post_bookmark' "
                    + "AND index_name = 'idx_post_bookmark_user' ORDER BY seq_in_index"))
                    .as("내가 저장한 글 목록의 커서 축(created_at, id)이 user_id 뒤에 온다")
                    .containsExactly("user_id", "created_at", "id");

            assertThat(db.query("SELECT constraint_name FROM information_schema.referential_constraints "
                    + "WHERE constraint_schema = DATABASE() AND delete_rule = 'CASCADE' "
                    + "AND constraint_name LIKE 'fk_post_bookmark_%' ORDER BY constraint_name"))
                    .containsExactly("fk_post_bookmark_post", "fk_post_bookmark_user");
        }
    }

    @Test
    @DisplayName("글이 사라지면 저장이 사라지고, 사람이 탈퇴하면 목록째 사라진다")
    void bothSidesCascade() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites();
            db.runMigration();
            db.exec("INSERT INTO users (id, email) VALUES (1, 'a@example.com'), (2, 'b@example.com')");
            db.exec("INSERT INTO post (id, user_id, board, title, body, created_at) VALUES "
                    + "(1, 1, 'free', '첫 글', '본문', NOW(6)), (2, 1, 'free', '둘째 글', '본문', NOW(6))");
            db.exec("INSERT INTO post_bookmark (post_id, user_id, created_at) VALUES "
                    + "(1, 2, NOW(6)), (2, 2, NOW(6)), (1, 1, NOW(6))");

            db.exec("DELETE FROM post WHERE id = 2");
            assertThat(db.query("SELECT COUNT(*) FROM post_bookmark"))
                    .as("없는 글을 가리키는 저장은 남길 이유가 없다")
                    .containsExactly("2");

            db.exec("DELETE FROM users WHERE id = 2");
            assertThat(db.query("SELECT user_id FROM post_bookmark"))
                    .as("""
                            반응은 집계가 남아야 해서 SET NULL 이지만, 저장은 그 사람만 보는 목록이다 — \
                            사람이 없으면 목록도 없다.""")
                    .containsExactly("1");
        }
    }

    @Test
    @DisplayName("같은 사람이 같은 글을 두 번 저장할 수 없다 — 유니크")
    void rejectsADuplicateBookmark() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites();
            db.runMigration();
            db.exec("INSERT INTO users (id, email) VALUES (1, 'a@example.com')");
            db.exec("INSERT INTO post (id, user_id, board, title, body, created_at) VALUES "
                    + "(1, 1, 'free', '첫 글', '본문', NOW(6))");
            db.exec("INSERT INTO post_bookmark (post_id, user_id, created_at) VALUES (1, 1, NOW(6))");

            assertThatThrownBy(() -> db.exec(
                    "INSERT INTO post_bookmark (post_id, user_id, created_at) VALUES (1, 1, NOW(6))"))
                    .isInstanceOf(SQLException.class);
            assertThat(db.query("SELECT COUNT(*) FROM post_bookmark")).containsExactly("1");
        }
    }

    @Test
    @DisplayName("두 번 돌려도 그대로다 — 멱등")
    void secondRunIsIdempotent() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites();
            db.runMigration();
            db.exec("INSERT INTO users (id, email) VALUES (1, 'a@example.com')");
            db.exec("INSERT INTO post (id, user_id, board, title, body, created_at) VALUES "
                    + "(1, 1, 'free', '첫 글', '본문', NOW(6))");
            db.exec("INSERT INTO post_bookmark (post_id, user_id, created_at) VALUES (1, 1, NOW(6))");

            db.runMigration();

            assertThat(db.query("SELECT COUNT(*) FROM post_bookmark")).containsExactly("1");
        }
    }

    @Test
    @DisplayName("post 가 없으면 멈춘다 — 14 를 먼저 돌려야 한다")
    void abortsWithoutThePostTable() throws Exception {
        try (Fixture db = fixture()) {
            db.createUsers();

            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("14_community.sql");
        }
    }

    @Test
    @DisplayName("Hibernate 가 먼저 만든 표(인덱스 이름이 다르다)는 사후 검증이 멈춰 세운다")
    void refusesToPassOverATableHibernateMadeWithoutTheNamedIndexes() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites();
            // dev 에서 앱을 먼저 띄운 모양 — 유니크도 목록 인덱스도 이름이 없거나 다르다.
            db.exec("""
                    CREATE TABLE post_bookmark (
                      created_at datetime(6) NOT NULL,
                      id bigint NOT NULL AUTO_INCREMENT,
                      post_id bigint NOT NULL,
                      user_id bigint NOT NULL,
                      PRIMARY KEY (id)
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);

            assertThatThrownBy(db::runMigration)
                    .as("""
                            IF NOT EXISTS 로 조용히 지나가면 유니크도 FK 도 없는 표가 남는다. \
                            그 상태를 사람이 알아채는 곳이 여기밖에 없다.""")
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("사후 검증");
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
            synchronized (PostBookmarkMigrationExecutionTest.class) {
                name = "postbookmark_test_" + (++dbCounter);
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

        /** FK 가 걸리는 표 둘의 최소 형태. */
        void createPrerequisites() throws SQLException {
            createUsers();
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

        void createUsers() throws SQLException {
            exec("""
                    CREATE TABLE users (
                      id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
                      email varchar(255)
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
