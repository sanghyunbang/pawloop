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
 * {@code 33_walk_dog.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — #343.
 *
 * <h2>여기서 가장 중요한 것</h2>
 * <p><b>이미 쌓인 산책이 채워지는가.</b> 표만 만들고 비워 두면 아이별 통계가 지금까지 걸은
 * 것을 전부 0 으로 말한다 — 사용자가 보기에 그것은 기록이 사라진 것이다. 그리고 오류가
 * 나지 않으므로 <b>아무도 모른 채로 배포된다.</b>
 *
 * <p>나머지 둘은 지우기 규칙(양쪽 CASCADE — 이 표에는 사실이 없고 이음매뿐이다)과 복합 PK
 * (같은 산책에 같은 아이가 두 줄이 되지 않는다)다.
 *
 * <p>스프링을 띄우지 않는다(#21).
 */
class WalkDogMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/33_walk_dog.sql";

    private static int dbCounter = 0;

    @Test
    @DisplayName("walk_dog 표가 생기고 FK 둘이 모두 CASCADE 다")
    void createsTheJoinTable() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true, true);

            db.runMigration();

            assertThat(db.columns("walk_dog")).containsExactly("dog_id", "walk_id");
            assertThat(db.deleteRule("fk_walkdog_walk")).isEqualTo("CASCADE");
            assertThat(db.deleteRule("fk_walkdog_dog")).isEqualTo("CASCADE");
        }
    }

    @Test
    @DisplayName("이미 쌓인 산책이 전부 채워진다 — 안 채우면 아이별 통계가 과거를 0 으로 말한다")
    void backfillsExistingWalks() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true, true);
            db.seedDogsAndWalks();

            db.runMigration();

            assertThat(db.query("SELECT CONCAT(walk_id, ':', dog_id) FROM walk_dog ORDER BY walk_id"))
                    .as("walk 세 줄이 그대로 세 줄이 되어야 한다")
                    .containsExactly("1:1", "2:1", "3:2");
        }
    }

    @Test
    @DisplayName("복합 PK 가 같은 산책·같은 아이를 두 번 못 넣게 한다")
    void rejectsTheSamePairTwice() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true, true);
            db.seedDogsAndWalks();
            db.runMigration();

            assertThatThrownBy(() -> db.exec("INSERT INTO walk_dog (walk_id, dog_id) VALUES (1, 1)"))
                    .isInstanceOf(SQLException.class);
        }
    }

    @Test
    @DisplayName("한 산책에 여러 마리가 들어간다 — 이 표가 있는 이유")
    void holdsSeveralDogsForOneWalk() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true, true);
            db.seedDogsAndWalks();
            db.runMigration();

            db.exec("INSERT INTO walk_dog (walk_id, dog_id) VALUES (1, 2)");

            assertThat(db.query("SELECT dog_id FROM walk_dog WHERE walk_id = 1 ORDER BY dog_id"))
                    .containsExactly("1", "2");
        }
    }

    @Test
    @DisplayName("산책을 지우면 이음매도 사라진다 — 여기에는 남길 사실이 없다")
    void cascadesFromTheWalk() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true, true);
            db.seedDogsAndWalks();
            db.runMigration();

            db.exec("DELETE FROM walk WHERE id = 1");

            assertThat(db.query("SELECT COUNT(*) FROM walk_dog WHERE walk_id = 1"))
                    .containsExactly("0");
        }
    }

    @Test
    @DisplayName("아이 행이 지워지면 이음매도 사라진다")
    void cascadesFromTheDog() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true, true);
            db.seedDogsAndWalks();
            db.runMigration();

            // walk 도 dog 에 CASCADE 라 함께 사라진다. 여기서 보는 것은 이음매가 남지
            // 않는다는 것이다 — 남으면 다음 마이그레이션의 FK 생성이 실패한다.
            db.exec("DELETE FROM dog WHERE id = 2");

            assertThat(db.query("SELECT COUNT(*) FROM walk_dog WHERE dog_id = 2"))
                    .containsExactly("0");
        }
    }

    @Test
    @DisplayName("두 번 돌려도 줄이 늘지 않는다 — 멱등")
    void secondRunIsIdempotent() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true, true);
            db.seedDogsAndWalks();

            db.runMigration();
            db.runMigration();

            assertThat(db.query("SELECT COUNT(*) FROM walk_dog")).containsExactly("3");
        }
    }

    @Test
    @DisplayName("사람이 넣어 둔 이음매를 지우지 않는다 — 두 번째 실행이 목록을 대표 아이로 되돌리면 안 된다")
    void keepsRowsAddedAfterTheFirstRun() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true, true);
            db.seedDogsAndWalks();
            db.runMigration();
            db.exec("INSERT INTO walk_dog (walk_id, dog_id) VALUES (1, 2)");

            db.runMigration();

            assertThat(db.query("SELECT dog_id FROM walk_dog WHERE walk_id = 1 ORDER BY dog_id"))
                    .containsExactly("1", "2");
        }
    }

    @Test
    @DisplayName("walk 이나 dog 가 없으면 멈춘다 — 앞 스크립트가 먼저다")
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
            db.exec("CREATE TABLE walk_dog (walk_id bigint NOT NULL PRIMARY KEY)");

            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("사람이 확인하라");

            assertThat(db.columns("walk_dog"))
                    .as("멈췄으면 손대지 않았어야 한다")
                    .containsExactly("walk_id");
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
            synchronized (WalkDogMigrationExecutionTest.class) {
                name = "walkdog_test_" + (++dbCounter);
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

        void createTables(boolean withDog, boolean withWalk) throws SQLException {
            if (withDog) {
                exec("""
                        CREATE TABLE dog (
                          id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
                          name varchar(50) NOT NULL,
                          deleted_at datetime(6) DEFAULT NULL
                        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                        """);
            }
            if (withWalk) {
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

        /** 아이 둘 · 산책 셋(보리 둘, 초코 하나) — 마이그레이션 이전에 쌓여 있던 것. */
        void seedDogsAndWalks() throws SQLException {
            exec("INSERT INTO dog (id, name) VALUES (1, '보리'), (2, '초코')");
            for (int i = 1; i <= 3; i++) {
                exec("INSERT INTO walk (id, dog_id, client_walk_id, started_at, distance_m, "
                        + "duration_s, created_at) VALUES (" + i + ", " + (i == 3 ? 2 : 1)
                        + ", 'walk-000" + i + "', NOW(6), 1200, 900, NOW(6))");
            }
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
