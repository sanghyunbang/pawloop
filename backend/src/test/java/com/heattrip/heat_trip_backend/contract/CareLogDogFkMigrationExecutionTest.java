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
 * {@code 22_care_log_dog_fk.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — #154.
 *
 * <h2>왜 실행 테스트인가</h2>
 * <p>이 스크립트가 거는 것은 FK 와 인덱스다. {@code ddl-auto=validate} 도
 * {@code SchemaDdlDriftTest} 도 FK 를 안 보므로, 여기서 안 재면 "걸었다" 는 말을 아무도
 * 확인하지 않는다. 그리고 <b>삭제 규칙</b>은 information_schema 의 문자열이 아니라
 * <b>실제로 지워 봐야</b> 안다 — dog 한 마리를 지우고, 사용자 한 명을 지워서(dog 이
 * CASCADE 로 따라 지워진다) 케어 기록이 남는지 본다. #154 완료 조건 4 가 그것이다.
 *
 * <p>표는 {@code 01_schema.sql} 의 DDL 을 그대로 심는다 — 단 {@code care_log} 는 이
 * 스크립트가 걸기 <b>전</b> 모양(dog FK 없음)이다. 스프링을 띄우지 않는다(#21).
 */
class CareLogDogFkMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/22_care_log_dog_fk.sql";
    private static final String CARE_SCRIPT = "mysql/post-start/08_care_log.sql";

    private static int dbCounter = 0;

    @Test
    @DisplayName("FK 가 ON DELETE SET NULL 로 걸리고 (dog_id, occurred_at) 인덱스가 생긴다")
    void addsForeignKeyWithSetNullAndIndex() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true);

            db.runMigration();

            assertThat(db.dogForeignKeys())
                    .as("care_log 에서 dog 로 가는 FK 하나 — 이름과 삭제 규칙까지")
                    .containsExactly("fk_carelog_dog|SET NULL");
            assertThat(db.indexColumns("idx_carelog_dog"))
                    .as("""
                            dog 삭제 시 SET NULL 이 훑는 자리이자 "이 반려동물의 케어 기록" 을 기간으로 \
                            훑을 자리다. idx_carelog_group(group_id, occurred_at) 과 같은 모양이다.""")
                    .containsExactly("dog_id", "occurred_at");
            assertThat(db.columns("care_log"))
                    .as("컬럼은 건드리지 않는다 — 08 의 여덟 그대로")
                    .containsExactly("created_at", "dog_id", "done_by", "group_id", "id",
                            "memo", "occurred_at", "type");
        }
    }

    @Test
    @DisplayName("두 번 돌려도 FK·인덱스가 하나씩이다 — 멱등")
    void secondRunIsIdempotent() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true);

            db.runMigration();
            db.runMigration();

            assertThat(db.dogForeignKeys()).containsExactly("fk_carelog_dog|SET NULL");
            assertThat(db.indexColumns("idx_carelog_dog")).containsExactly("dog_id", "occurred_at");
        }
    }

    @Test
    @DisplayName("dog 표가 없으면 아무것도 바꾸기 전에 멈춘다 — 11_dog.sql 이 먼저다")
    void abortsWhenDogTableIsMissing() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(false);

            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("11_dog.sql");

            assertThat(db.indexColumns("idx_carelog_dog"))
                    .as("멈췄으면 인덱스도 안 만들었어야 한다 — 관문은 §0 이다")
                    .isEmpty();
        }
    }

    @Test
    @DisplayName("dog 에 없는 dog_id 를 든 행(고아)이 있으면 지우지 않고 멈춘다")
    void abortsOnOrphanDogIds() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true);
            db.seedUserAndDog();
            // FK 가 아직 없어서 들어갈 수 있는 값 — 누가 손으로 넣은 상황이다.
            db.exec("INSERT INTO care_log (id, dog_id, type, done_by, occurred_at, created_at) "
                    + "VALUES (1, 999, 'meal', 1, NOW(6), NOW(6))");

            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("고아");

            assertThat(db.dogForeignKeys()).isEmpty();
            assertThat(db.careLog(1))
                    .as("고아 행을 고치거나 지우지 않는다 — 어느 값인지 사람이 봐야 한다")
                    .isEqualTo("999|1|meal");
        }
    }

    @Test
    @DisplayName("dog 을 지우면 케어 기록은 남고 dog_id 만 NULL 이 된다 — 완료 조건 4")
    void deletingTheDogKeepsTheCareRecord() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true);
            db.seedUserAndDog();
            db.exec("INSERT INTO care_log (id, dog_id, type, done_by, occurred_at, memo, created_at) "
                    + "VALUES (1, 1, 'meal', 1, NOW(6), '사료 반 컵', NOW(6))");

            db.runMigration();
            db.exec("DELETE FROM dog WHERE id = 1");

            assertThat(db.careLog(1))
                    .as("""
                            케어는 "누가 언제 무엇을 했는가" 의 기록이라 반려동물이 지워져도 그 사실은 \
                            남는다. CASCADE 였다면 이 행이 사라졌을 것이다.""")
                    .isEqualTo("NULL|1|meal");
        }
    }

    @Test
    @DisplayName("사용자 탈퇴가 dog 을 CASCADE 로 지워도 케어 기록은 남는다 — 두 FK 가 이어서 SET NULL 한다")
    void userDeletionCascadesThroughDogAndKeepsTheCareRecord() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true);
            db.seedUserAndDog();
            db.exec("INSERT INTO care_log (id, dog_id, type, done_by, occurred_at, created_at) "
                    + "VALUES (1, 1, 'walk', 1, NOW(6), NOW(6))");

            db.runMigration();
            db.exec("DELETE FROM users WHERE id = 1");

            assertThat(db.count("dog")).as("fk_dog_user 는 CASCADE 다(11_dog.sql)").isZero();
            assertThat(db.careLog(1))
                    .as("""
                            DELETE /auth/me 는 users 를 하드 삭제한다. dog 이 따라 지워지고, 그 삭제가 \
                            care_log.dog_id 를 NULL 로 훑는다. done_by 는 fk_carelog_doneby 가 \
                            같은 방식으로 NULL 로 만든다. 행은 남는다 — 가족의 화면에서 \
                            "오늘 누군가 산책을 다녀왔다" 는 사실이 사라지면 안 된다.""")
                    .isEqualTo("NULL|NULL|walk");
        }
    }

    @Test
    @DisplayName("22 뒤에 08 을 다시 돌려도 멈추지 않는다 — 08 의 경계 검증이 dog FK 를 세지 않는다")
    void rerunningCareMigrationAfterwardsDoesNotAbort() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true);

            db.runMigration();
            db.runScript(CARE_SCRIPT);

            assertThat(db.dogForeignKeys())
                    .as("08 은 2026-09-05 까지 'dog 로 가는 FK 0개' 를 경계 위반으로 막았다. 22 가 건 뒤에는 그 검사가 틀리다")
                    .containsExactly("fk_carelog_dog|SET NULL");
            assertThat(db.tables()).contains("care_log", "walk_note");
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
            synchronized (CareLogDogFkMigrationExecutionTest.class) {
                name = "care_log_dog_fk_test_" + (++dbCounter);
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
         * {@code 01_schema.sql} 의 DDL 대로 — 단 {@code care_log} 는 22 가 걸기 <b>전</b> 모양이다
         * (dog FK 없음). {@code users}·{@code family_group} 은 이 검사에 필요한 컬럼만.
         */
        void createTables(boolean withDog) throws SQLException {
            exec("""
                    CREATE TABLE users (
                      id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
                      email varchar(255) DEFAULT NULL,
                      role varchar(20) NOT NULL,
                      created_at datetime(6) DEFAULT NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
            exec("""
                    CREATE TABLE family_group (
                      created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
                      id bigint NOT NULL AUTO_INCREMENT,
                      name varchar(50) NOT NULL,
                      PRIMARY KEY (id)
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
            exec("""
                    CREATE TABLE care_log (
                      created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
                      dog_id bigint DEFAULT NULL,
                      done_by bigint DEFAULT NULL,
                      group_id bigint DEFAULT NULL,
                      id bigint NOT NULL AUTO_INCREMENT,
                      occurred_at datetime(6) NOT NULL,
                      type varchar(10) NOT NULL,
                      memo varchar(500) DEFAULT NULL,
                      PRIMARY KEY (id),
                      KEY idx_carelog_group (group_id, occurred_at),
                      KEY idx_carelog_doneby (done_by),
                      CONSTRAINT fk_carelog_doneby FOREIGN KEY (done_by) REFERENCES users (id) ON DELETE SET NULL,
                      CONSTRAINT fk_carelog_group FOREIGN KEY (group_id) REFERENCES family_group (id) ON DELETE SET NULL,
                      CONSTRAINT ck_carelog_type CHECK (type in ('water','meal','walk','med','vet'))
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
        }

        void seedUserAndDog() throws SQLException {
            exec("INSERT INTO users (id, email, role, created_at) "
                    + "VALUES (1, 'owner@example.com', 'ROLE_USER', NOW(6))");
            exec("INSERT INTO dog (id, user_id, name, size, species, neutered, created_at) "
                    + "VALUES (1, 1, '초코', 'small', 'dog', 0, NOW(6))");
        }

        void runMigration() throws Exception {
            runScript(SCRIPT);
        }

        void runScript(String path) throws Exception {
            String sql = Files.readString(
                    TestProjectPaths.requireFile(path), StandardCharsets.UTF_8);
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

        List<String> tables() throws SQLException {
            return query("SELECT table_name FROM information_schema.tables "
                    + "WHERE table_schema = DATABASE() ORDER BY table_name");
        }

        List<String> columns(String table) throws SQLException {
            return query("SELECT column_name FROM information_schema.columns "
                    + "WHERE table_schema = DATABASE() AND table_name = '" + table + "' "
                    + "ORDER BY column_name");
        }

        /** {@code 이름|삭제규칙} — care_log 에서 dog 로 가는 FK 전부. */
        List<String> dogForeignKeys() throws SQLException {
            return query("SELECT CONCAT(constraint_name, '|', delete_rule) "
                    + "FROM information_schema.referential_constraints "
                    + "WHERE constraint_schema = DATABASE() AND table_name = 'care_log' "
                    + "AND referenced_table_name = 'dog' ORDER BY constraint_name");
        }

        /** 인덱스의 열을 순서대로. 없으면 빈 목록. */
        List<String> indexColumns(String index) throws SQLException {
            return query("SELECT column_name FROM information_schema.statistics "
                    + "WHERE table_schema = DATABASE() AND table_name = 'care_log' "
                    + "AND index_name = '" + index + "' ORDER BY seq_in_index");
        }

        /** {@code dog_id|done_by|type} — NULL 은 {@code NULL} 로. 값을 통째로 견준다. */
        String careLog(long id) throws SQLException {
            return query("SELECT CONCAT(IFNULL(dog_id, 'NULL'), '|', IFNULL(done_by, 'NULL'), '|', type) "
                    + "FROM care_log WHERE id = " + id).stream()
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
