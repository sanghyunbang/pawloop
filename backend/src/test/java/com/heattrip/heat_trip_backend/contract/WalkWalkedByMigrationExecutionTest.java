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
 * {@code 49_walk_walked_by.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — #563.
 *
 * <h2>왜 실행 테스트인가</h2>
 *
 * <p>이 스크립트가 하는 일 셋 중 둘을 {@code ddl-auto=validate} 도 {@code SchemaDdlDriftTest}
 * 도 안 본다.
 *
 * <ol>
 *   <li><b>FK 의 삭제 규칙.</b> {@code SET NULL} 이어야 한다 — {@code CASCADE} 면 탈퇴 한
 *       번에 그 사람이 걸어 준 산책이 통째로 사라진다. 이건 문자열이 아니라 <b>실제로
 *       지워 봐야</b> 안다.</li>
 *   <li><b>옛 행 채우기.</b> {@code walked_by} 를 {@code dog.user_id} 로 채운다. 안 채우면
 *       마이그레이션 전의 모든 산책이 "누가 걸었는지 모름" 이 된다.</li>
 *   <li>멱등 — 두 번 돌려도 같은 상태로 끝나야 하고, <b>이미 채운 값을 덮으면 안 된다.</b></li>
 * </ol>
 *
 * <p>표는 {@code 01_schema.sql} 의 DDL 을 그대로 심되 {@code walk} 는 이 스크립트가 돌기
 * <b>전</b> 모양이다({@code walked_by} 없음). 스프링을 띄우지 않는다(#21).
 */
class WalkWalkedByMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/49_walk_walked_by.sql";

    private static int dbCounter = 0;

    @Test
    @DisplayName("컬럼이 생기고 FK 가 ON DELETE SET NULL 로 걸린다")
    void addsTheColumnAndForeignKey() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true);

            db.runMigration();

            assertThat(db.columns("walk")).contains("walked_by");
            assertThat(db.nullable("walk", "walked_by"))
                    .as("NOT NULL 이면 탈퇴가 산책을 지운다 — SET NULL 을 걸 수조차 없다")
                    .isEqualTo("YES");
            assertThat(db.walkedByForeignKeys()).containsExactly("fk_walk_walkedby|SET NULL");
        }
    }

    @Test
    @DisplayName("옛 행을 아이 주인으로 채운다 — 지어내기가 아니라 그 시절 규칙의 결과다")
    void fillsOldRowsWithTheDogOwner() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true);
            db.seed();
            db.exec("INSERT INTO walk (id, dog_id, client_walk_id, started_at, distance_m, duration_s, created_at) "
                    + "VALUES (1, 1, 'ck-1', NOW(6), 1200, 900, NOW(6))");

            db.runMigration();

            assertThat(db.walkedBy(1))
                    .as("""
                            이 마이그레이션 전에는 남의 아이로 산책을 저장할 수 없었다. \
                            그래서 그때의 '아이 주인' 이 곧 '걸은 사람' 이다.""")
                    .isEqualTo("1");
        }
    }

    @Test
    @DisplayName("두 번 돌려도 같고, 이미 채운 값을 덮지 않는다 — 멱등")
    void secondRunKeepsWhatIsAlreadyThere() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true);
            db.seed();
            db.exec("INSERT INTO walk (id, dog_id, client_walk_id, started_at, distance_m, duration_s, created_at) "
                    + "VALUES (1, 1, 'ck-1', NOW(6), 1200, 900, NOW(6))");

            db.runMigration();
            // 마이그레이션 뒤에 아빠(2)가 엄마 아이를 산책시킨 상황.
            db.exec("UPDATE walk SET walked_by = 2 WHERE id = 1");
            db.runMigration();

            assertThat(db.walkedBy(1))
                    .as("덮어쓰면 남이 걸어 준 산책이 전부 아이 주인 것으로 둔갑한다")
                    .isEqualTo("2");
            assertThat(db.walkedByForeignKeys()).containsExactly("fk_walk_walkedby|SET NULL");
        }
    }

    @Test
    @DisplayName("걸은 사람이 탈퇴해도 산책은 남는다 — walked_by 만 NULL 이 된다")
    void deletingTheWalkerKeepsTheWalk() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true);
            db.seed();
            // 아빠(2)가 엄마(1) 아이를 산책시킨 행.
            db.exec("INSERT INTO walk (id, dog_id, client_walk_id, started_at, distance_m, duration_s, created_at) "
                    + "VALUES (1, 1, 'ck-1', NOW(6), 1200, 900, NOW(6))");
            db.runMigration();
            db.exec("UPDATE walk SET walked_by = 2 WHERE id = 1");

            db.exec("DELETE FROM users WHERE id = 2");

            assertThat(db.count("walk"))
                    .as("CASCADE 였다면 아빠 탈퇴 한 번에 이 산책이 사라졌을 것이다")
                    .isEqualTo(1);
            assertThat(db.walkedBy(1)).isEqualTo("NULL");
        }
    }

    @Test
    @DisplayName("walk 표가 없으면 아무것도 바꾸기 전에 멈춘다 — 12_walk.sql 이 먼저다")
    void abortsWhenWalkTableIsMissing() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(false);

            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("12_walk.sql");
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
            synchronized (WalkWalkedByMigrationExecutionTest.class) {
                name = "walk_walked_by_test_" + (++dbCounter);
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

        /** {@code 01_schema.sql} 대로 — 단 {@code walk} 는 49 가 돌기 <b>전</b> 모양이다. */
        void createTables(boolean withWalk) throws SQLException {
            exec("""
                    CREATE TABLE users (
                      id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
                      email varchar(255) DEFAULT NULL,
                      role varchar(20) NOT NULL,
                      created_at datetime(6) DEFAULT NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
            exec("""
                    CREATE TABLE dog (
                      birth date DEFAULT NULL,
                      neutered bit(1) NOT NULL DEFAULT b'0',
                      created_at datetime(6) NOT NULL,
                      id bigint NOT NULL AUTO_INCREMENT,
                      user_id bigint NOT NULL,
                      size varchar(10) NOT NULL DEFAULT 'small',
                      species varchar(10) NOT NULL DEFAULT 'dog',
                      breed varchar(50) DEFAULT NULL,
                      name varchar(50) NOT NULL,
                      avatar varchar(255) DEFAULT NULL,
                      PRIMARY KEY (id),
                      KEY idx_dog_user (user_id),
                      CONSTRAINT fk_dog_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
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
                          client_walk_id varchar(64) NOT NULL,
                          memo varchar(500) DEFAULT NULL,
                          PRIMARY KEY (id),
                          UNIQUE KEY uq_walk_client (dog_id, client_walk_id),
                          CONSTRAINT fk_walk_dog FOREIGN KEY (dog_id) REFERENCES dog (id) ON DELETE CASCADE
                        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                        """);
            }
        }

        /** 엄마(1)와 아빠(2), 엄마가 등록한 보리(1). */
        void seed() throws SQLException {
            exec("INSERT INTO users (id, email, role, created_at) "
                    + "VALUES (1, 'mom@example.com', 'ROLE_USER', NOW(6))");
            exec("INSERT INTO users (id, email, role, created_at) "
                    + "VALUES (2, 'dad@example.com', 'ROLE_USER', NOW(6))");
            exec("INSERT INTO dog (id, user_id, name, size, species, neutered, created_at) "
                    + "VALUES (1, 1, '보리', 'small', 'dog', 0, NOW(6))");
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

        String nullable(String table, String column) throws SQLException {
            return query("SELECT is_nullable FROM information_schema.columns "
                    + "WHERE table_schema = DATABASE() AND table_name = '" + table + "' "
                    + "AND column_name = '" + column + "'").stream()
                    .findFirst().orElse("(없음)");
        }

        /** {@code 이름|삭제규칙} — walk 에서 users 로 가는 FK 전부. */
        List<String> walkedByForeignKeys() throws SQLException {
            return query("SELECT CONCAT(constraint_name, '|', delete_rule) "
                    + "FROM information_schema.referential_constraints "
                    + "WHERE constraint_schema = DATABASE() AND table_name = 'walk' "
                    + "AND referenced_table_name = 'users' ORDER BY constraint_name");
        }

        String walkedBy(long id) throws SQLException {
            return query("SELECT IFNULL(walked_by, 'NULL') FROM walk WHERE id = " + id).stream()
                    .findFirst().orElse("(없음)");
        }

        int count(String table) throws SQLException {
            return query("SELECT COUNT(*) FROM " + table).stream()
                    .findFirst().map(Integer::parseInt).orElse(-1);
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
