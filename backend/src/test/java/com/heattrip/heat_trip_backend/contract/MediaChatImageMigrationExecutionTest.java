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
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * {@code 43_media_chat_image.sql} 을 빈 DB 에 실제로 돌린다 — 이슈 #452 (채팅 말풍선 사진).
 *
 * <p>42 와 다른 점 하나를 잰다: 값을 <b>끝이 아니라 알파벳 자리</b>에 넣어 결과가
 * {@code mysql/init/01_schema.sql}(새로 만드는 DB)과 <b>글자까지 같은지</b>. 옮긴 DB 와 새 DB 의
 * {@code SHOW CREATE TABLE} 이 다르면 그 차이는 아무 검사도 잡지 못한 채 남는다 — 그래서
 * 기대값을 손으로 적지 않고 정본 파일에서 읽는다.
 */
class MediaChatImageMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/43_media_chat_image.sql";
    private static final String CANONICAL_SCHEMA = "mysql/init/01_schema.sql";

    /** 42 까지 적용된 표 — 이 스크립트가 받는 모양. */
    private static final String AFTER_42 =
            "enum('JOURNEY_IMAGE','POST_IMAGE','POST_VIDEO','PROFILE_IMAGE','REVIEW_IMAGE','WALK_IMAGE')";

    /** 42 를 건너뛴 표 — 받지 않는다. */
    private static final String BEFORE_42 =
            "enum('JOURNEY_IMAGE','POST_IMAGE','POST_VIDEO','PROFILE_IMAGE','REVIEW_IMAGE')";

    private static int dbCounter = 0;

    @Test
    @DisplayName("CHAT_IMAGE 가 더해진 결과가 01_schema.sql 의 category 와 글자까지 같다 — 옮긴 DB 와 새 DB 가 같은 표")
    void migratedColumnEqualsTheCanonicalSchema() throws Exception {
        try (Fixture db = fixture()) {
            db.createTable(AFTER_42);
            db.exec("INSERT INTO media_objects (id, category, media_key, owner_id, size, status, created_at) VALUES "
                    + "(1, 'WALK_IMAGE', 'walks/1/a.jpg', '1', 10, 'ready', NOW(6))");

            db.runMigration();

            assertThat(db.categoryType())
                    .as("기대값은 손으로 적은 것이 아니라 정본에서 읽은 것이다")
                    .isEqualTo(canonicalCategoryType());
            assertThat(db.categoryType()).startsWith("enum('CHAT_IMAGE',");
            assertThat(db.query("SELECT category FROM media_objects WHERE id = 1"))
                    .as("표를 다시 쓰더라도 쌓인 행의 값은 그대로다").containsExactly("WALK_IMAGE");
            db.exec("INSERT INTO media_objects (id, category, media_key, owner_id, size, status, created_at) VALUES "
                    + "(2, 'CHAT_IMAGE', 'chats/1/b.jpg', '1', 10, 'ready', NOW(6))");
            assertThat(db.query("SELECT category FROM media_objects WHERE id = 2")).containsExactly("CHAT_IMAGE");
        }
    }

    @Test
    @DisplayName("두 번 돌려도 그대로다 — 멱등")
    void secondRunIsIdempotent() throws Exception {
        try (Fixture db = fixture()) {
            db.createTable(AFTER_42);
            db.runMigration();
            db.exec("INSERT INTO media_objects (id, category, media_key, owner_id, size, status, created_at) VALUES "
                    + "(1, 'CHAT_IMAGE', 'chats/1/a.jpg', '1', 10, 'ready', NOW(6))");

            db.runMigration();

            assertThat(db.query("SELECT category FROM media_objects WHERE id = 1")).containsExactly("CHAT_IMAGE");
            assertThat(db.categoryType()).isEqualTo(canonicalCategoryType());
        }
    }

    @Test
    @DisplayName("42 를 건너뛴 표(WALK_IMAGE 없음)에는 대지 않는다 — 값 목록을 통째로 쓰므로 그 값이 빠진 채 굳는다")
    void abortsWhenWalkImageIsMissing() throws Exception {
        try (Fixture db = fixture()) {
            db.createTable(BEFORE_42);

            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("42_media_walk_image.sql");
            assertThat(db.categoryType()).as("아무것도 안 바꿨다").isEqualTo(BEFORE_42);
        }
    }

    @Test
    @DisplayName("media_objects 가 없으면 멈춘다 — 01_schema.sql 이 먼저다")
    void abortsWithoutTheTable() throws Exception {
        try (Fixture db = fixture()) {
            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("01_schema.sql");
        }
    }

    @Test
    @DisplayName("category 가 ENUM 이 아니면 멈춘다 — 조용히 덮지 않는다")
    void abortsWhenTheColumnIsNotAnEnum() throws Exception {
        try (Fixture db = fixture()) {
            db.createTable("varchar(255)");
            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("사람이 확인하라");
        }
    }

    // ─────────────────────────── 지그 ─────────────────

    /** 정본 {@code 01_schema.sql} 의 {@code media_objects.category} 타입 — 문장 그대로. */
    private static String canonicalCategoryType() throws Exception {
        String ddl = Files.readString(TestProjectPaths.requireFile(CANONICAL_SCHEMA), StandardCharsets.UTF_8);
        Matcher m = Pattern.compile("`category` (enum\\([^)]*\\)) NOT NULL").matcher(ddl);
        assertThat(m.find()).as("01_schema.sql 에 media_objects.category ENUM 이 있어야 한다").isTrue();
        return m.group(1);
    }

    private static Fixture fixture() throws SQLException {
        return new Fixture();
    }

    private static final class Fixture implements AutoCloseable {
        private final String name;
        private final Connection connection;

        Fixture() throws SQLException {
            MySQLContainer<?> mysql = MySqlTestContainer.instance();
            synchronized (MediaChatImageMigrationExecutionTest.class) {
                name = "chatimage_test_" + (++dbCounter);
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

        void createTable(String categoryType) throws SQLException {
            exec("""
                    CREATE TABLE media_objects (
                      id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
                      category %s NOT NULL,
                      media_key varchar(512) NOT NULL,
                      owner_id varchar(255) NOT NULL,
                      size bigint NOT NULL,
                      status varchar(16) NOT NULL,
                      ref_type varchar(255) DEFAULT NULL,
                      ref_id varchar(255) DEFAULT NULL,
                      created_at datetime(6) NOT NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """.formatted(categoryType));
        }

        String categoryType() throws SQLException {
            return query("SELECT column_type FROM information_schema.columns "
                    + "WHERE table_schema = DATABASE() AND table_name = 'media_objects' AND column_name = 'category'")
                    .get(0);
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
