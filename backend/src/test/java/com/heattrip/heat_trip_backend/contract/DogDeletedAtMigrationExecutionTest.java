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
 * {@code 23_dog_deleted_at.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — #156.
 *
 * <p>더하는 것은 컬럼 하나지만 그 컬럼이 곧 "지운 아이가 되살아나지 않는다" 의 전부다.
 * 모양이 틀리면(NULL 허용이 아니거나 정밀도가 다르면) 엔티티의 {@code validate} 가 부팅에서
 * 죽거나, 살아 있는 아이가 "지워진 것" 으로 읽힌다. 그래서 information_schema 로 모양을 재고,
 * 이미 있는 행의 값이 그대로인지 본다. 스프링을 띄우지 않는다(#21).
 */
class DogDeletedAtMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/23_dog_deleted_at.sql";

    private static int dbCounter = 0;

    @Test
    @DisplayName("deleted_at 이 datetime(6) NULL 허용으로 생기고, 있던 행은 전부 NULL 이다")
    void addsANullableDeletedAtColumn() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true);
            db.seedDog();

            db.runMigration();

            assertThat(db.columnShape("deleted_at"))
                    .as("SET 되기 전에는 전부 살아 있어야 한다 — NOT NULL 이면 살아 있는 아이가 없다")
                    .isEqualTo("datetime|6|YES");
            assertThat(db.query("SELECT CONCAT(name, '|', IFNULL(deleted_at, 'NULL')) FROM dog"))
                    .as("이 스크립트는 누구도 지우지 않는다")
                    .containsExactly("초코|NULL");
        }
    }

    @Test
    @DisplayName("두 번 돌려도 같은 상태다 — 멱등")
    void secondRunIsIdempotent() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true);

            db.runMigration();
            db.runMigration();

            assertThat(db.columns("dog")).containsOnlyOnce("deleted_at");
            assertThat(db.columnShape("deleted_at")).isEqualTo("datetime|6|YES");
        }
    }

    @Test
    @DisplayName("dog 표가 없으면 멈춘다 — 11_dog.sql 이 먼저다")
    void abortsWhenDogTableIsMissing() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(false);

            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("11_dog.sql");
        }
    }

    @Test
    @DisplayName("같은 이름의 컬럼이 다른 모양으로 있으면 고치지 않고 멈춘다 — 사람이 봐야 한다")
    void abortsWhenTheColumnExistsWithAnotherShape() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true);
            db.exec("ALTER TABLE dog ADD COLUMN deleted_at date NULL");

            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("사람이 확인하라");

            assertThat(db.columnShape("deleted_at"))
                    .as("멈췄으면 손대지 않았어야 한다")
                    .isEqualTo("date|NULL|YES");
        }
    }

    @Test
    @DisplayName("이미 지워진 아이가 있는 표에 다시 돌려도 그 표시는 그대로다")
    void keepsExistingMarks() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true);
            db.seedDog();
            db.runMigration();
            db.exec("UPDATE dog SET deleted_at = '2026-09-06 01:02:03.000000' WHERE id = 1");

            db.runMigration();

            assertThat(db.query("SELECT DATE_FORMAT(deleted_at, '%Y-%m-%d %H:%i:%s') FROM dog WHERE id = 1"))
                    .containsExactly("2026-09-06 01:02:03");
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
            synchronized (DogDeletedAtMigrationExecutionTest.class) {
                name = "dog_deleted_at_test_" + (++dbCounter);
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

        /** {@code 01_schema.sql} 의 dog 에서 23 이 더하기 <b>전</b> 모양. users 는 필요한 컬럼만. */
        void createTables(boolean withDog) throws SQLException {
            exec("""
                    CREATE TABLE users (
                      id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
                      email varchar(255) DEFAULT NULL,
                      role varchar(20) NOT NULL,
                      created_at datetime(6) DEFAULT NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
            if (withDog) {
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
                          CONSTRAINT fk_dog_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
                          CONSTRAINT ck_dog_size CHECK (size in ('small','medium','large')),
                          CONSTRAINT ck_dog_species CHECK (species in ('dog','cat','other'))
                        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                        """);
            }
        }

        void seedDog() throws SQLException {
            exec("INSERT INTO users (id, email, role, created_at) "
                    + "VALUES (1, 'owner@example.com', 'ROLE_USER', NOW(6))");
            exec("INSERT INTO dog (id, user_id, name, size, species, neutered, created_at) "
                    + "VALUES (1, 1, '초코', 'small', 'dog', 0, NOW(6))");
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

        /** {@code 타입|정밀도|NULL허용} — 없으면 {@code (없음)}. */
        String columnShape(String column) throws SQLException {
            return query("SELECT CONCAT(data_type, '|', IFNULL(datetime_precision, 'NULL'), '|', is_nullable) "
                    + "FROM information_schema.columns "
                    + "WHERE table_schema = DATABASE() AND table_name = 'dog' AND column_name = '" + column + "'")
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
