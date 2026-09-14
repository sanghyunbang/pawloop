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
 * {@code 42_media_walk_image.sql} 을 스프링 없이 실제 MySQL 에 돌린다 — 이슈 #450.
 *
 * <p>ENUM 컬럼에 값을 더하는 마이그레이션이다. 값을 끝에 더하면 InnoDB 가 표를 다시 쓰지 않는다는
 * 것과, 쌓인 행의 값이 그대로라는 것, 두 번 돌려도 그대로라는 것을 본다.
 */
class MediaWalkImageMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/42_media_walk_image.sql";
    private static final String OLD_ENUM =
            "enum('JOURNEY_IMAGE','POST_IMAGE','POST_VIDEO','PROFILE_IMAGE','REVIEW_IMAGE')";
    private static int dbCounter = 0;

    @Test
    @DisplayName("WALK_IMAGE 가 ENUM 끝에 더해지고, 쌓인 행의 값은 그대로다")
    void addsTheValueAndKeepsExistingRows() throws Exception {
        try (Fixture db = fixture()) {
            db.createTable(OLD_ENUM);
            db.exec("INSERT INTO media_objects (id, category, media_key, owner_id, size, status, created_at) VALUES "
                    + "(1, 'POST_IMAGE', 'posts/1/a.jpg', '1', 10, 'ready', NOW(6))");

            db.runMigration();

            assertThat(db.query("SELECT column_type FROM information_schema.columns "
                    + "WHERE table_schema = DATABASE() AND table_name = 'media_objects' AND column_name = 'category'"))
                    .as("값은 끝에 더한다 — 순서를 바꾸면 표를 다시 쓴다")
                    .containsExactly("enum('JOURNEY_IMAGE','POST_IMAGE','POST_VIDEO','PROFILE_IMAGE','REVIEW_IMAGE','WALK_IMAGE')");
            assertThat(db.query("SELECT category FROM media_objects WHERE id = 1")).containsExactly("POST_IMAGE");
            db.exec("INSERT INTO media_objects (id, category, media_key, owner_id, size, status, created_at) VALUES "
                    + "(2, 'WALK_IMAGE', 'walks/1/b.jpg', '1', 10, 'ready', NOW(6))");
            assertThat(db.query("SELECT category FROM media_objects WHERE id = 2")).containsExactly("WALK_IMAGE");
        }
    }

    @Test
    @DisplayName("두 번 돌려도 그대로다 — 멱등")
    void secondRunIsIdempotent() throws Exception {
        try (Fixture db = fixture()) {
            db.createTable(OLD_ENUM);
            db.runMigration();
            db.exec("INSERT INTO media_objects (id, category, media_key, owner_id, size, status, created_at) VALUES "
                    + "(1, 'WALK_IMAGE', 'walks/1/a.jpg', '1', 10, 'ready', NOW(6))");

            db.runMigration();

            assertThat(db.query("SELECT category FROM media_objects WHERE id = 1")).containsExactly("WALK_IMAGE");
            assertThat(db.query("SELECT column_type FROM information_schema.columns "
                    + "WHERE table_schema = DATABASE() AND table_name = 'media_objects' AND column_name = 'category'"))
                    .containsExactly("enum('JOURNEY_IMAGE','POST_IMAGE','POST_VIDEO','PROFILE_IMAGE','REVIEW_IMAGE','WALK_IMAGE')");
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

    private static Fixture fixture() throws SQLException {
        return new Fixture();
    }

    private static final class Fixture implements AutoCloseable {
        private final String name;
        private final Connection connection;

        Fixture() throws SQLException {
            MySQLContainer<?> mysql = MySqlTestContainer.instance();
            synchronized (MediaWalkImageMigrationExecutionTest.class) {
                name = "walkimage_test_" + (++dbCounter);
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

        /** 01_schema.sql 의 media_objects 를 필요한 만큼만 — category 의 모양은 테스트가 정한다. */
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
