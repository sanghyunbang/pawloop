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
 * {@code 39_post_media.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — #429.
 *
 * <h2>여기서 가장 중요한 것</h2>
 * <p><b>있는 행이 그대로 사는가.</b> 이 스크립트는 표를 만드는 것이 아니라 감정 여행 시절부터
 * 있던 {@code media_objects} 를 넓힌다. 행 수가 바뀌거나 기존 행의 {@code status} 가 비면
 * 운영의 옛 파일이 화면에서 사라지거나 부팅이 {@code validate} 에서 죽는다.
 *
 * <p>그다음이 <b>enum 의 순서</b>다. {@code category} 가 DB enum 이라 값을 더하려면 타입을
 * 통째로 다시 쓰는데, 자바 enum 과 순서가 다르면 정본 재생성과 갈려 {@code SchemaDdlDriftTest}
 * 가 빨개진다 — 그 차이는 이 스크립트를 돌린 운영 DB 에서만 난다.
 *
 * <p>38 과 다른 점 하나 — <b>Hibernate 가 먼저 넓혀 둔 표를 멈추지 않고 고친다.</b> 만드는
 * 것이 아니라 있는 표에 컬럼을 더하는 것이라 고칠 수 있고, dev 에서 앱을 먼저 띄운 사람에게
 * "표를 지우고 다시 하라" 고 하면 그 사람의 사진이 사라진다.
 *
 * <p>스프링을 띄우지 않는다(#21).
 */
class PostMediaMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/39_post_media.sql";

    /** 정본 {@code 01_schema.sql} 의 39 이전 모양 그대로다. 컬럼 순서까지 같다. */
    private static final String LEGACY_TABLE = """
            CREATE TABLE `media_objects` (
              `created_at` datetime(6) NOT NULL,
              `deleted_at` datetime(6) DEFAULT NULL,
              `id` bigint NOT NULL AUTO_INCREMENT,
              `size` bigint NOT NULL,
              `updated_at` datetime(6) DEFAULT NULL,
              `media_key` varchar(512) NOT NULL,
              `content_type` varchar(255) DEFAULT NULL,
              `original_name` varchar(255) DEFAULT NULL,
              `owner_id` varchar(255) NOT NULL,
              `ref_id` varchar(255) DEFAULT NULL,
              `ref_type` varchar(255) DEFAULT NULL,
              `category` enum('JOURNEY_IMAGE','PROFILE_IMAGE','REVIEW_IMAGE') NOT NULL,
              PRIMARY KEY (`id`),
              UNIQUE KEY `UK3pkjswl54cvrded30nci3u45t` (`media_key`),
              KEY `idx_media_owner` (`owner_id`),
              KEY `idx_media_ref` (`ref_type`,`ref_id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
            """;

    /** Hibernate 가 뽑는 순서 — <b>알파벳순</b>이다. 선언 순서가 아니다(2026-09-13 실측). */
    private static final String WIDENED_ENUM =
            "enum('JOURNEY_IMAGE','POST_IMAGE','POST_VIDEO','PROFILE_IMAGE','REVIEW_IMAGE')";

    private static int dbCounter = 0;

    @Test
    @DisplayName("컬럼 다섯이 생기고 enum 이 넓어지고, 있던 행은 ready 로 채워진다")
    void widensTheTableAndKeepsEveryRow() throws Exception {
        try (Fixture db = fixture()) {
            db.exec(LEGACY_TABLE);
            db.exec(legacyRow(1, "journeys/42/2025/09/a_trip.jpg", "JOURNEY_IMAGE"));
            db.exec(legacyRow(2, "profiles/7/2026/01/b_me.jpg", "PROFILE_IMAGE"));

            db.runMigration();

            assertThat(db.query("SELECT column_name FROM information_schema.columns "
                    + "WHERE table_schema = DATABASE() AND table_name = 'media_objects' "
                    + "ORDER BY column_name"))
                    .contains("status", "poster_key", "width", "height", "duration_ms");

            assertThat(db.query("SELECT column_type FROM information_schema.columns "
                    + "WHERE table_schema = DATABASE() AND table_name = 'media_objects' "
                    + "AND column_name = 'category'"))
                    .as("""
                            순서가 정본 재생성과 글자 그대로 같아야 한다 — Hibernate 는 상수를 \
                            알파벳순으로 뽑고 SchemaDdlDriftTest 가 문자열을 그대로 비교한다.""")
                    .containsExactly(WIDENED_ENUM);

            assertThat(db.query("SELECT constraint_name FROM information_schema.table_constraints "
                    + "WHERE table_schema = DATABASE() AND table_name = 'media_objects' "
                    + "AND constraint_type = 'CHECK'"))
                    .as("Hibernate 의 update 도 prod 의 validate 도 CHECK 는 안 본다")
                    .containsExactly("ck_media_status");

            assertThat(db.query("SELECT column_name FROM information_schema.statistics "
                    + "WHERE table_schema = DATABASE() AND table_name = 'media_objects' "
                    + "AND index_name = 'idx_media_orphan' ORDER BY seq_in_index"))
                    .containsExactly("ref_type", "created_at");

            assertThat(db.query("SELECT status FROM media_objects ORDER BY id"))
                    .as("있던 행이 비면 옛 파일이 화면에서 사라진다")
                    .containsExactly("ready", "ready");

            assertThat(db.query("SELECT IFNULL(column_default, '(null)') FROM information_schema.columns "
                    + "WHERE table_schema = DATABASE() AND table_name = 'media_objects' "
                    + "AND column_name = 'status'"))
                    .as("DEFAULT 를 남기면 새로 세운 DB(정본)와 갈리고 validate 는 그 차이를 안 잡는다")
                    .containsExactly("(null)");
        }
    }

    @Test
    @DisplayName("모르는 상태는 CHECK 가 막고, 새 카테고리 둘은 들어간다")
    void rejectsUnknownStatusAndAcceptsNewCategories() throws Exception {
        try (Fixture db = fixture()) {
            db.exec(LEGACY_TABLE);
            db.runMigration();

            assertThatThrownBy(() -> db.exec(newRow(10, "posts/1/x.jpg", "POST_IMAGE", "'done'")))
                    .as("붙었는지는 ref_type 이 말한다 — 상태를 더 두면 같은 사실이 두 곳에 산다")
                    .isInstanceOf(SQLException.class);

            db.exec(newRow(11, "posts/1/y.jpg", "POST_IMAGE", "'ready'"));
            db.exec(newRow(12, "posts-video/1/z.mp4", "POST_VIDEO", "'pending'"));
            assertThat(db.query("SELECT category FROM media_objects ORDER BY id"))
                    .containsExactly("POST_IMAGE", "POST_VIDEO");
        }
    }

    @Test
    @DisplayName("두 번 돌려도 그대로다 — 멱등")
    void secondRunIsIdempotent() throws Exception {
        try (Fixture db = fixture()) {
            db.exec(LEGACY_TABLE);
            db.exec(legacyRow(1, "journeys/42/2025/09/a_trip.jpg", "JOURNEY_IMAGE"));
            db.runMigration();
            db.exec(newRow(2, "posts/1/y.jpg", "POST_IMAGE", "'ready'"));

            db.runMigration();

            assertThat(db.query("SELECT COUNT(*) FROM media_objects")).containsExactly("2");
            assertThat(db.query("SELECT COUNT(*) FROM information_schema.table_constraints "
                    + "WHERE table_schema = DATABASE() AND table_name = 'media_objects' "
                    + "AND constraint_type = 'CHECK'")).containsExactly("1");
        }
    }

    @Test
    @DisplayName("media_objects 가 없으면 멈춘다 — 정본 01_schema.sql 을 먼저 적용해야 한다")
    void abortsWithoutTheTable() throws Exception {
        try (Fixture db = fixture()) {
            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("media_objects");
        }
    }

    @Test
    @DisplayName("Hibernate 가 CHECK 없이 넓혀 둔 표는 멈추지 않고 고친다 — 빈 status 를 채우고 CHECK 를 건다")
    void repairsATableHibernateWidenedWithoutTheCheck() throws Exception {
        try (Fixture db = fixture()) {
            db.exec(LEGACY_TABLE);
            db.exec(legacyRow(1, "journeys/42/2025/09/a_trip.jpg", "JOURNEY_IMAGE"));
            // dev 에서 앱을 먼저 띄운 모양 — ddl-auto=update 가 컬럼과 인덱스는 더하지만
            // CHECK 는 안 걸고, NOT NULL 컬럼에 DEFAULT 가 없어 있던 행은 '' 이 된다.
            db.exec("ALTER TABLE `media_objects` "
                    + "ADD COLUMN `status` varchar(10) NOT NULL, "
                    + "ADD COLUMN `poster_key` varchar(512) DEFAULT NULL, "
                    + "ADD COLUMN `width` int DEFAULT NULL, "
                    + "ADD COLUMN `height` int DEFAULT NULL, "
                    + "ADD COLUMN `duration_ms` int DEFAULT NULL, "
                    + "MODIFY COLUMN `category` " + WIDENED_ENUM + " NOT NULL");
            assertThat(db.query("SELECT status FROM media_objects")).containsExactly("");

            db.runMigration();

            assertThat(db.query("SELECT status FROM media_objects"))
                    .as("빈 상태로 두면 CHECK 를 못 걸고, 그 행은 어느 조회에도 안 잡힌다")
                    .containsExactly("ready");
            assertThat(db.query("SELECT constraint_name FROM information_schema.table_constraints "
                    + "WHERE table_schema = DATABASE() AND table_name = 'media_objects' "
                    + "AND constraint_type = 'CHECK'"))
                    .containsExactly("ck_media_status");
            assertThat(db.query("SELECT COUNT(*) FROM information_schema.statistics "
                    + "WHERE table_schema = DATABASE() AND table_name = 'media_objects' "
                    + "AND index_name = 'idx_media_orphan'"))
                    .containsExactly("2");
        }
    }

    // ─────────────────────────── 지그 ─────────────────

    private static String legacyRow(long id, String key, String category) {
        return "INSERT INTO media_objects (id, created_at, size, media_key, owner_id, category) "
                + "VALUES (" + id + ", NOW(6), 1024, '" + key + "', '42', '" + category + "')";
    }

    private static String newRow(long id, String key, String category, String status) {
        return "INSERT INTO media_objects (id, created_at, size, media_key, owner_id, category, status) "
                + "VALUES (" + id + ", NOW(6), 1024, '" + key + "', '42', '" + category + "', " + status + ")";
    }

    private static Fixture fixture() throws SQLException {
        return new Fixture();
    }

    private static final class Fixture implements AutoCloseable {

        private final String name;
        private final Connection connection;

        Fixture() throws SQLException {
            MySQLContainer<?> mysql = MySqlTestContainer.instance();
            synchronized (PostMediaMigrationExecutionTest.class) {
                name = "postmedia_test_" + (++dbCounter);
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
