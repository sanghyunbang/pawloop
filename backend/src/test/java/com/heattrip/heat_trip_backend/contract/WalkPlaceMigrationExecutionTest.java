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
 * {@code 26_walk_place.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — #338.
 *
 * <p>더하는 것은 컬럼 셋과 인덱스 하나지만, 그 셋이 곧 "자주 가는 곳" 의 근거다. 폭이 다르면
 * 엔티티의 {@code validate} 가 부팅에서 죽고, 이미 있는 산책의 값이 흔들리면 "그날 거기를
 * 걸었다" 가 바뀐다. 그래서 information_schema 로 모양을 재고, 있던 행이 그대로인지 본다.
 * 스프링을 띄우지 않는다(#21).
 */
class WalkPlaceMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/26_walk_place.sql";

    private static int dbCounter = 0;

    @Test
    @DisplayName("place_source/place_content_id/place_name 이 NULL 허용으로 생기고, 있던 산책은 전부 NULL 이다")
    void addsThreeNullablePlaceColumns() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true);
            db.seedWalk();

            db.runMigration();

            assertThat(db.columnShape("place_source"))
                    .as("옛 산책에는 장소가 없다 — NOT NULL 이면 그 행들이 저장될 수 없다")
                    .isEqualTo("varchar|16|YES");
            assertThat(db.columnShape("place_content_id")).isEqualTo("varchar|64|YES");
            assertThat(db.columnShape("place_name")).isEqualTo("varchar|120|YES");

            assertThat(db.query("SELECT CONCAT(client_walk_id, '|', IFNULL(place_name, 'NULL')) FROM walk"))
                    .as("이 스크립트는 장소를 지어내지 않는다")
                    .containsExactly("walk-0001|NULL");
        }
    }

    @Test
    @DisplayName("idx_walk_place 가 (place_source, place_content_id) 순서로 생긴다 — 묶어 세는 순서다")
    void addsTheGroupingIndex() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true);

            db.runMigration();

            assertThat(db.query("SELECT column_name FROM information_schema.statistics "
                    + "WHERE table_schema = DATABASE() AND table_name = 'walk' "
                    + "AND index_name = 'idx_walk_place' ORDER BY seq_in_index"))
                    .containsExactly("place_source", "place_content_id");
        }
    }

    @Test
    @DisplayName("두 번 돌려도 같은 상태다 — 멱등")
    void secondRunIsIdempotent() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true);

            db.runMigration();
            db.runMigration();

            assertThat(db.columns("walk"))
                    .containsOnlyOnce("place_source")
                    .containsOnlyOnce("place_content_id")
                    .containsOnlyOnce("place_name");
            assertThat(db.query("SELECT COUNT(DISTINCT index_name) FROM information_schema.statistics "
                    + "WHERE table_schema = DATABASE() AND table_name = 'walk' AND index_name = 'idx_walk_place'"))
                    .containsExactly("1");
        }
    }

    @Test
    @DisplayName("walk 표가 없으면 멈춘다 — 12_walk.sql 이 먼저다")
    void abortsWhenWalkTableIsMissing() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(false);

            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("12_walk.sql");
        }
    }

    @Test
    @DisplayName("같은 이름의 컬럼이 다른 폭으로 있으면 고치지 않고 멈춘다 — 사람이 봐야 한다")
    void abortsWhenAColumnExistsWithAnotherShape() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true);
            db.exec("ALTER TABLE walk ADD COLUMN place_name varchar(30) NULL");

            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("사람이 확인하라");

            assertThat(db.columnShape("place_name"))
                    .as("멈췄으면 손대지 않았어야 한다")
                    .isEqualTo("varchar|30|YES");
            assertThat(db.columns("walk"))
                    .as("한 컬럼에서 멈췄으면 나머지도 안 만든다")
                    .doesNotContain("place_source");
        }
    }

    @Test
    @DisplayName("이미 붙인 장소가 있는 표에 다시 돌려도 그 값은 그대로다")
    void keepsExistingPlaces() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true);
            db.seedWalk();
            db.runMigration();
            db.exec("UPDATE walk SET place_source = 'kto', place_content_id = '2733967', "
                    + "place_name = '서울숲' WHERE id = 1");

            db.runMigration();

            assertThat(db.query("SELECT CONCAT(place_source, '|', place_content_id, '|', place_name) "
                    + "FROM walk WHERE id = 1"))
                    .containsExactly("kto|2733967|서울숲");
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
            synchronized (WalkPlaceMigrationExecutionTest.class) {
                name = "walk_place_test_" + (++dbCounter);
            }
            // 앱 계정에는 CREATE DATABASE 권한이 없다 — root 로 붙는다(#56 에서 실측).
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

        /**
         * {@code 01_schema.sql} 의 walk 에서 26 이 더하기 <b>전</b> 모양. 경로 컬럼은 빼도 된다 —
         * 이 스크립트가 보는 것은 표의 존재와 place_* 컬럼뿐이다.
         */
        void createTables(boolean withWalk) throws SQLException {
            exec("""
                    CREATE TABLE dog (
                      id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
                      name varchar(50) NOT NULL,
                      created_at datetime(6) NOT NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
            if (withWalk) {
                exec("""
                        CREATE TABLE walk (
                          distance_m int NOT NULL,
                          duration_s int NOT NULL,
                          created_at datetime(6) NOT NULL,
                          dog_id bigint NOT NULL,
                          ended_at datetime(6) DEFAULT NULL,
                          id bigint NOT NULL AUTO_INCREMENT,
                          started_at datetime(6) NOT NULL,
                          weather varchar(30) DEFAULT NULL,
                          client_walk_id varchar(64) NOT NULL,
                          memo varchar(500) DEFAULT NULL,
                          path_t json DEFAULT NULL,
                          PRIMARY KEY (id),
                          UNIQUE KEY uq_walk_client (dog_id, client_walk_id),
                          KEY idx_walk_dog (dog_id, started_at),
                          CONSTRAINT fk_walk_dog FOREIGN KEY (dog_id) REFERENCES dog (id) ON DELETE CASCADE
                        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                        """);
            }
        }

        void seedWalk() throws SQLException {
            exec("INSERT INTO dog (id, name, created_at) VALUES (1, '초코', NOW(6))");
            exec("INSERT INTO walk (id, dog_id, client_walk_id, started_at, distance_m, duration_s, created_at) "
                    + "VALUES (1, 1, 'walk-0001', NOW(6), 1200, 900, NOW(6))");
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

        /** {@code 타입|폭|NULL허용} — 없으면 {@code (없음)}. */
        String columnShape(String column) throws SQLException {
            return query("SELECT CONCAT(data_type, '|', IFNULL(character_maximum_length, 'NULL'), '|', is_nullable) "
                    + "FROM information_schema.columns "
                    + "WHERE table_schema = DATABASE() AND table_name = 'walk' AND column_name = '" + column + "'")
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
