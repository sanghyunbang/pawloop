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
 * {@code 47_chat_change_feed.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — ADR-0023(#500).
 *
 * <p>재는 것 셋이다: 쌓인 방이 0 에서 시작하는가(NOT NULL DEFAULT 0), 쌓인 메시지가 NULL 로 남는가
 * (한 번도 안 바뀐 말이라 델타가 옛 말을 새로 흘리면 안 된다), 인덱스가 {@code (room_id, change_seq)} 순서인가.
 *
 * <p>스프링을 띄우지 않는다(#21).
 */
class ChatChangeFeedMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/47_chat_change_feed.sql";

    private static int dbCounter = 0;

    @Test
    @DisplayName("컬럼 둘과 인덱스가 생기고, 쌓인 방은 0 · 쌓인 메시지는 NULL 로 남는다")
    void addsTheCountersAndKeepsExistingRows() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites();
            db.exec("INSERT INTO chat_room (id, last_seq) VALUES (1, 2)");
            db.insertMessage(1, 1, "옛 말");
            db.insertMessage(2, 2, "옛 말 둘");

            db.runMigration();

            assertThat(db.query("SELECT column_default FROM information_schema.columns "
                    + "WHERE table_schema = DATABASE() AND table_name = 'chat_room' AND column_name = 'last_change_seq'"))
                    .as("쌓인 방은 '아직 아무것도 안 바뀐 방' 으로 시작한다")
                    .containsExactly("0");
            assertThat(db.query("SELECT last_change_seq FROM chat_room WHERE id = 1")).containsExactly("0");
            assertThat(db.query("SELECT IFNULL(change_seq, '(null)') FROM chat_message ORDER BY id"))
                    .as("한 번도 안 바뀐 말이라 NULL 이어야 한다 — 값이 붙으면 델타가 옛 말을 새로 흘린다")
                    .containsExactly("(null)", "(null)");
            assertThat(db.query("SELECT column_name FROM information_schema.statistics "
                    + "WHERE table_schema = DATABASE() AND table_name = 'chat_message' "
                    + "AND index_name = 'idx_chat_change' ORDER BY seq_in_index"))
                    .as("델타가 '이 방에서 이 번호 뒤' 를 읽는 축 그대로다")
                    .containsExactly("room_id", "change_seq");
        }
    }

    @Test
    @DisplayName("두 번 돌려도 그대로다 — 멱등")
    void secondRunIsIdempotent() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites();
            db.runMigration();
            db.exec("INSERT INTO chat_room (id, last_seq, last_change_seq) VALUES (1, 1, 7)");
            db.insertMessage(1, 1, "말");
            db.exec("UPDATE chat_message SET change_seq = 7 WHERE id = 1");

            db.runMigration();

            assertThat(db.query("SELECT last_change_seq FROM chat_room WHERE id = 1")).containsExactly("7");
            assertThat(db.query("SELECT change_seq FROM chat_message WHERE id = 1")).containsExactly("7");
            assertThat(db.query("SELECT COUNT(DISTINCT index_name) FROM information_schema.statistics "
                    + "WHERE table_schema = DATABASE() AND table_name = 'chat_message' AND index_name = 'idx_chat_change'"))
                    .as("인덱스가 두 벌 생기지 않는다").containsExactly("1");
        }
    }

    @Test
    @DisplayName("chat_room 이나 chat_message 가 없으면 멈춘다 — 11 을 먼저 돌려야 한다")
    void abortsWithoutThePrerequisites() throws Exception {
        try (Fixture db = fixture()) {
            db.exec("CREATE TABLE chat_room (id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY) ENGINE=InnoDB");

            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("11_chat.sql");
        }
    }

    @Test
    @DisplayName("change_seq 가 이미 있는데 모양이 다르면 멈춘다 — 조용히 덮지 않는다")
    void abortsOnAColumnWithTheWrongShape() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites();
            db.exec("ALTER TABLE chat_message ADD COLUMN change_seq varchar(20) NULL");

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
            synchronized (ChatChangeFeedMigrationExecutionTest.class) {
                name = "chatchange_test_" + (++dbCounter);
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

        /** chat_room · chat_message 의 최소 형태(11_chat.sql 의 모양을 줄인 것). */
        void createPrerequisites() throws SQLException {
            exec("CREATE TABLE chat_room (id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY, "
                    + "last_seq bigint NOT NULL DEFAULT 0) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
            exec("""
                    CREATE TABLE chat_message (
                      id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
                      room_id bigint NOT NULL,
                      room_seq bigint NOT NULL,
                      sender_user_id bigint NOT NULL,
                      sender_name varchar(255) NOT NULL,
                      content_type varchar(16) NOT NULL DEFAULT 'text',
                      body text NOT NULL,
                      created_at datetime(6) NOT NULL,
                      deleted_at datetime(6) DEFAULT NULL,
                      UNIQUE KEY uq_chat_room_seq (room_id, room_seq),
                      CONSTRAINT fk_chat_room FOREIGN KEY (room_id) REFERENCES chat_room (id) ON DELETE CASCADE
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
        }

        void insertMessage(long id, long seq, String body) throws SQLException {
            exec("INSERT INTO chat_message (id, room_id, room_seq, sender_user_id, sender_name, body, created_at) "
                    + "VALUES (" + id + ", 1, " + seq + ", 7, '보리아빠', '" + body + "', NOW(6))");
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
