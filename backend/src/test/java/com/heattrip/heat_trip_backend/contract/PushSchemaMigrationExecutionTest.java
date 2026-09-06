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
 * {@code 25_push.sql} 을 <b>진짜 MySQL</b> 에 돌려 본다 — 이슈 #83. 스크립트가 만든 모양이 엔티티가
 * 요구하는 모양과 같아야 prod 의 {@code ddl-auto=validate} 가 부팅을 막지 않는다.
 */
class PushSchemaMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/25_push.sql";

    private static int dbCounter = 0;

    @Test
    @DisplayName("muted_at 이 붙고 device_token · push_preference 가 엔티티와 같은 컬럼으로 생긴다")
    void createsEverythingTheEntitiesExpect() throws Exception {
        try (Fixture db = fixture()) {
            db.createMemberTableAsOf06();

            db.runMigration();

            assertThat(db.columnShape("chat_room_member", "muted_at")).isEqualTo("datetime|NULL|YES");
            assertThat(db.columns("device_token")).containsExactlyInAnyOrder(
                    "id", "user_id", "token", "platform", "created_at", "last_seen_at", "revoked_at");
            assertThat(db.columnShape("device_token", "token")).isEqualTo("varchar|512|NO");
            assertThat(db.columnShape("device_token", "revoked_at")).isEqualTo("datetime|NULL|YES");
            assertThat(db.constraintNames("device_token"))
                    .contains("uk_device_token_token", "chk_device_token_platform");
            assertThat(db.columns("push_preference")).containsExactlyInAnyOrder("user_id", "enabled", "updated_at");
            assertThat(db.columnShape("push_preference", "enabled")).isEqualTo("bit|NULL|NO");
        }
    }

    @Test
    @DisplayName("token 이 겹치면 UNIQUE 가, platform 이 둘 밖이면 CHECK 가 막는다")
    void constraintsHold() throws Exception {
        try (Fixture db = fixture()) {
            db.createMemberTableAsOf06();
            db.runMigration();

            db.exec("INSERT INTO device_token (user_id, token, platform, created_at, last_seen_at) "
                    + "VALUES (1, 'tok-1', 'android', NOW(6), NOW(6))");
            assertThatThrownBy(() -> db.exec("INSERT INTO device_token (user_id, token, platform, created_at, last_seen_at) "
                    + "VALUES (2, 'tok-1', 'ios', NOW(6), NOW(6))"))
                    .as("같은 토큰이 둘이면 UNIQUE 가 막는다 — 등록이 upsert 인 이유다")
                    .isInstanceOf(SQLException.class);
            assertThatThrownBy(() -> db.exec("INSERT INTO device_token (user_id, token, platform, created_at, last_seen_at) "
                    + "VALUES (1, 'tok-2', 'web', NOW(6), NOW(6))"))
                    .as("android · ios 밖은 CHECK 가 막는다")
                    .isInstanceOf(SQLException.class);
        }
    }

    @Test
    @DisplayName("두 번 돌려도 같다 — 멱등")
    void runningTwiceIsHarmless() throws Exception {
        try (Fixture db = fixture()) {
            db.createMemberTableAsOf06();
            db.runMigration();
            db.exec("INSERT INTO push_preference (user_id, enabled, updated_at) VALUES (7, b'0', NOW(6))");

            db.runMigration();

            assertThat(db.columns("chat_room_member")).containsOnlyOnce("muted_at");
            assertThat(db.query("SELECT user_id FROM push_preference")).containsExactly("7");
        }
    }

    @Test
    @DisplayName("chat_room_member 가 없으면 멈춘다 — 06 이 먼저다")
    void abortsWhenTheMemberTableIsMissing() throws Exception {
        try (Fixture db = fixture()) {
            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("06_chat_rooms.sql");
            assertThat(db.tables()).doesNotContain("device_token", "push_preference");
        }
    }

    @Test
    @DisplayName("muted_at 이 다른 모양으로 이미 있으면 한 글자도 안 바꾸고 멈춘다")
    void abortsWhenMutedAtHasAnotherShape() throws Exception {
        try (Fixture db = fixture()) {
            db.createMemberTableAsOf06();
            db.exec("ALTER TABLE chat_room_member ADD COLUMN muted_at varchar(8) NULL");

            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("muted_at");
            assertThat(db.tables()).doesNotContain("device_token", "push_preference");
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
            synchronized (PushSchemaMigrationExecutionTest.class) {
                name = "push_migration_test_" + (++dbCounter);
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

        /** 06 이 만든 뒤 09·10 이 손댄 결과 — 이 스크립트가 보는 컬럼만 든 최소 모양이다. */
        void createMemberTableAsOf06() throws SQLException {
            exec("""
                    CREATE TABLE chat_room_member (
                      id bigint NOT NULL AUTO_INCREMENT,
                      room_id bigint NOT NULL,
                      user_id bigint NOT NULL,
                      role varchar(10) NOT NULL DEFAULT 'MEMBER',
                      joined_at datetime(6) NOT NULL,
                      last_read_seq bigint NOT NULL DEFAULT 0,
                      removed_at datetime(6) DEFAULT NULL,
                      removed_by bigint DEFAULT NULL,
                      rejoin_blocked bit(1) NOT NULL DEFAULT b'0',
                      PRIMARY KEY (id),
                      UNIQUE KEY uq_chat_member (room_id, user_id)
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
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

        List<String> tables() throws SQLException {
            return query("SELECT table_name FROM information_schema.tables WHERE table_schema = DATABASE() ORDER BY table_name");
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
