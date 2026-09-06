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
 * {@code 24_place_catalog_layers.sql} 을 진짜 MySQL 에 돌린다 — 이슈 #291.
 *
 * <p>18 이 만든 모양(행 하나, {@code CHECK (id = 1)})에서 출발해 출처별 행이 되는지, 옛 행 1 이
 * {@code kto} 로 남는지, {@code trail_route} 가 생기는지, 두 번 돌려도 같은지, 이상한 행이 있으면
 * 멈추는지를 본다.
 */
class PlaceCatalogLayersMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/24_place_catalog_layers.sql";

    private static int dbCounter = 0;

    @Test
    @DisplayName("옛 행 1 은 kto 가 되고, 둘째·셋째 출처의 행이 들어가며, 넷째 출처는 CHECK 가 막는다")
    void widensTheTableToOneRowPerSource() throws Exception {
        try (Fixture db = fixture()) {
            db.createCatalogAsOf18();
            db.insertCatalog(1, "[{\"contentId\":\"1\"}]");
            db.runMigration();

            assertThat(db.query("SELECT CONCAT(id, '|', source) FROM place_catalog ORDER BY id"))
                    .containsExactly("1|kto");
            assertThat(db.columnShape("place_catalog", "source")).isEqualTo("varchar|16|NO");
            assertThat(db.constraintNames("place_catalog"))
                    .contains("uk_place_catalog_source", "chk_place_catalog_source")
                    .doesNotContain("chk_place_catalog_singleton");

            db.exec("INSERT INTO place_catalog (id, source, payload, etag, item_count, total_count, fetched_at, fail_streak) "
                    + "VALUES (2, 'localdata', '[]', 'e2', 0, 0, NOW(6), 0)");
            db.exec("INSERT INTO place_catalog (id, source, payload, etag, item_count, total_count, fetched_at, fail_streak) "
                    + "VALUES (3, 'durunubi', '[]', 'e3', 0, 0, NOW(6), 0)");
            assertThatThrownBy(() -> db.exec(
                    "INSERT INTO place_catalog (id, source, payload, etag, item_count, total_count, fetched_at, fail_streak) "
                            + "VALUES (4, 'naver', '[]', 'e4', 0, 0, NOW(6), 0)"))
                    .as("허용된 출처 셋 밖은 CHECK 가 막는다")
                    .isInstanceOf(SQLException.class);
            assertThatThrownBy(() -> db.exec(
                    "INSERT INTO place_catalog (id, source, payload, etag, item_count, total_count, fetched_at, fail_streak) "
                            + "VALUES (5, 'kto', '[]', 'e5', 0, 0, NOW(6), 0)"))
                    .as("같은 출처의 행이 둘이면 UNIQUE 가 막는다")
                    .isInstanceOf(SQLException.class);
        }
    }

    @Test
    @DisplayName("trail_route 가 엔티티와 같은 여덟 컬럼으로 생긴다 — FK 없음")
    void createsTrailRoute() throws Exception {
        try (Fixture db = fixture()) {
            db.createCatalogAsOf18();
            db.runMigration();

            assertThat(db.columns("trail_route")).containsExactlyInAnyOrder(
                    "course_id", "name", "point_count", "length_m", "start_lat", "start_lng", "payload", "fetched_at");
            // longtext 의 character_maximum_length 는 4,294,967,295 다 — MEDIUMTEXT(16,777,215)면 데이터가 커지는 날 잘린다.
            assertThat(db.columnShape("trail_route", "payload")).isEqualTo("longtext|4294967295|NO");
            assertThat(db.query("SELECT COUNT(*) FROM information_schema.referential_constraints "
                    + "WHERE constraint_schema = DATABASE() AND table_name = 'trail_route'"))
                    .containsExactly("0");
        }
    }

    @Test
    @DisplayName("두 번 돌려도 같은 상태다 — 멱등")
    void secondRunIsIdempotent() throws Exception {
        try (Fixture db = fixture()) {
            db.createCatalogAsOf18();
            db.insertCatalog(1, "[]");
            db.runMigration();
            db.runMigration();

            assertThat(db.columns("place_catalog")).containsOnlyOnce("source");
            assertThat(db.constraintNames("place_catalog"))
                    .containsOnlyOnce("uk_place_catalog_source")
                    .containsOnlyOnce("chk_place_catalog_source");
            assertThat(db.query("SELECT source FROM place_catalog")).containsExactly("kto");
        }
    }

    @Test
    @DisplayName("place_catalog 가 없으면 멈춘다 — 18 이 먼저다")
    void abortsWhenTheTableIsMissing() throws Exception {
        try (Fixture db = fixture()) {
            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("18_place_catalog.sql");
        }
    }

    @Test
    @DisplayName("id 가 1·2·3 밖인 행이 있으면 한 글자도 안 바꾸고 멈춘다 — 사람이 봐야 한다")
    void abortsOnAnUnknownRow() throws Exception {
        try (Fixture db = fixture()) {
            db.createCatalogAsOf18();
            // 18 의 CHECK 를 먼저 벗겨야 넣을 수 있다 — 누가 손으로 그렇게 했다는 가정이다.
            db.exec("ALTER TABLE place_catalog DROP CHECK chk_place_catalog_singleton");
            db.insertCatalog(7, "[]");

            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("사람이 확인하라");
            assertThat(db.columns("place_catalog")).doesNotContain("source");
        }
    }

    @Test
    @DisplayName("source 가 다른 모양으로 이미 있으면 멈춘다")
    void abortsWhenSourceHasAnotherShape() throws Exception {
        try (Fixture db = fixture()) {
            db.createCatalogAsOf18();
            db.exec("ALTER TABLE place_catalog ADD COLUMN source varchar(8) NULL");

            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("varchar(16)");
            assertThat(db.columnShape("place_catalog", "source")).isEqualTo("varchar|8|YES");
        }
    }

    // ─────────────────────────── 픽스처 ───────────────────────────

    private static Fixture fixture() throws SQLException {
        return new Fixture();
    }

    private static final class Fixture implements AutoCloseable {
        private final String name;
        private final Connection connection;

        Fixture() throws SQLException {
            MySQLContainer<?> mysql = MySqlTestContainer.instance();
            synchronized (PlaceCatalogLayersMigrationExecutionTest.class) {
                name = "place_catalog_layers_test_" + (++dbCounter);
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

        /** 18_place_catalog.sql 이 만든 모양 그대로 — 행 하나, CHECK (id = 1). */
        void createCatalogAsOf18() throws SQLException {
            exec("""
                    CREATE TABLE place_catalog (
                      fail_streak int NOT NULL,
                      id int NOT NULL,
                      item_count int NOT NULL,
                      total_count int NOT NULL,
                      failed_at datetime(6) DEFAULT NULL,
                      fetched_at datetime(6) NOT NULL,
                      etag varchar(64) NOT NULL,
                      payload longtext NOT NULL,
                      PRIMARY KEY (id),
                      CONSTRAINT chk_place_catalog_singleton CHECK ((id = 1))
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
        }

        void insertCatalog(int id, String payload) throws SQLException {
            exec("INSERT INTO place_catalog (id, payload, etag, item_count, total_count, fetched_at, fail_streak) "
                    + "VALUES (" + id + ", '" + payload + "', 'etag" + id + "', 1, 1, NOW(6), 0)");
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

        List<String> columns(String table) throws SQLException {
            return query("SELECT column_name FROM information_schema.columns "
                    + "WHERE table_schema = DATABASE() AND table_name = '" + table + "' ORDER BY column_name");
        }

        String columnShape(String table, String column) throws SQLException {
            return query("SELECT CONCAT(data_type, '|', IFNULL(character_maximum_length, 'NULL'), '|', is_nullable) "
                    + "FROM information_schema.columns WHERE table_schema = DATABASE() "
                    + "AND table_name = '" + table + "' AND column_name = '" + column + "'")
                    .stream().findFirst().orElse("(없음)");
        }

        List<String> constraintNames(String table) throws SQLException {
            return query("SELECT constraint_name FROM information_schema.table_constraints "
                    + "WHERE table_schema = DATABASE() AND table_name = '" + table + "' ORDER BY constraint_name");
        }

        List<String> query(String sql) throws SQLException {
            List<String> out = new ArrayList<>();
            try (Statement st = connection.createStatement(); ResultSet rs = st.executeQuery(sql)) {
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
