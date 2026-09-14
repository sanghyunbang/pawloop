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
 * {@code 45_chat_reply.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — #452 답장.
 *
 * <p>가장 중요한 것은 <b>FK 가 같은 표를 가리키고 {@code SET NULL} 인가</b>다. {@code CASCADE} 로
 * 잘못 서면 운영 정리로 원문 한 줄을 지우는 날 그 말에 달린 답장이 전부 사라진다 — 답장은 남의 말이고
 * 원문 연결은 꼬리표다. 그다음이 쌓인 메시지가 그대로인가(컬럼은 NULL 허용).
 *
 * <p>스프링을 띄우지 않는다(#21).
 */
class ChatReplyMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/45_chat_reply.sql";

    private static int dbCounter = 0;

    @Test
    @DisplayName("컬럼·인덱스·같은 표로 가는 SET NULL FK 가 생기고, 쌓인 메시지는 그대로다")
    void addsTheColumnIndexAndSelfForeignKey() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites();
            db.insertMessage(1, 1, "옛 말");

            db.runMigration();

            assertThat(db.query("SELECT is_nullable FROM information_schema.columns "
                    + "WHERE table_schema = DATABASE() AND table_name = 'chat_message' AND column_name = 'reply_to_id'"))
                    .as("있던 메시지는 답장이 아니다 — NULL 허용이어야 한다")
                    .containsExactly("YES");
            assertThat(db.query("SELECT column_name FROM information_schema.statistics "
                    + "WHERE table_schema = DATABASE() AND table_name = 'chat_message' "
                    + "AND index_name = 'idx_chat_reply_to'"))
                    .containsExactly("reply_to_id");
            assertThat(db.query("SELECT referenced_table_name FROM information_schema.referential_constraints "
                    + "WHERE constraint_schema = DATABASE() AND constraint_name = 'fk_chat_reply_to'"))
                    .as("같은 표를 가리킨다")
                    .containsExactly("chat_message");
            assertThat(db.query("SELECT delete_rule FROM information_schema.referential_constraints "
                    + "WHERE constraint_schema = DATABASE() AND constraint_name = 'fk_chat_reply_to'"))
                    .as("원문이 사라져도 답장은 남는다")
                    .containsExactly("SET NULL");
            assertThat(db.query("SELECT IFNULL(reply_to_id, '(null)') FROM chat_message WHERE id = 1"))
                    .as("있던 메시지는 그대로고 답장 연결만 비어 있다")
                    .containsExactly("(null)");
        }
    }

    @Test
    @DisplayName("원문을 하드 삭제하면 답장은 남고 연결만 빈다 — SET NULL")
    void deletingTheOriginalKeepsTheReply() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites();
            db.runMigration();
            db.insertMessage(1, 1, "원문");
            db.exec("INSERT INTO chat_message (id, room_id, room_seq, sender_user_id, sender_name, body, created_at, reply_to_id) "
                    + "VALUES (2, 1, 2, 9, '답하는 사람', '답장', NOW(6), 1)");

            db.exec("DELETE FROM chat_message WHERE id = 1");

            assertThat(db.query("SELECT COUNT(*) FROM chat_message")).containsExactly("1");
            assertThat(db.query("SELECT IFNULL(reply_to_id, '(null)') FROM chat_message WHERE id = 2")).containsExactly("(null)");
        }
    }

    @Test
    @DisplayName("없는 메시지에는 답장할 수 없다 — FK")
    void rejectsAnUnknownOriginal() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites();
            db.runMigration();

            assertThatThrownBy(() -> db.exec("INSERT INTO chat_message (id, room_id, room_seq, sender_user_id, sender_name, body, created_at, reply_to_id) "
                    + "VALUES (2, 1, 1, 9, '답하는 사람', '답장', NOW(6), 999)"))
                    .isInstanceOf(SQLException.class);
        }
    }

    @Test
    @DisplayName("두 번 돌려도 그대로다 — 멱등")
    void secondRunIsIdempotent() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites();
            db.runMigration();
            db.insertMessage(1, 1, "원문");
            db.exec("INSERT INTO chat_message (id, room_id, room_seq, sender_user_id, sender_name, body, created_at, reply_to_id) "
                    + "VALUES (2, 1, 2, 9, '답하는 사람', '답장', NOW(6), 1)");

            db.runMigration();

            assertThat(db.query("SELECT reply_to_id FROM chat_message WHERE id = 2")).containsExactly("1");
            assertThat(db.query("SELECT COUNT(*) FROM information_schema.statistics "
                    + "WHERE table_schema = DATABASE() AND table_name = 'chat_message' AND index_name = 'idx_chat_reply_to'"))
                    .as("인덱스가 두 벌 생기지 않는다").containsExactly("1");
            assertThat(db.query("SELECT COUNT(*) FROM information_schema.referential_constraints "
                    + "WHERE constraint_schema = DATABASE() AND constraint_name = 'fk_chat_reply_to'"))
                    .as("FK 가 두 벌 생기지 않는다").containsExactly("1");
        }
    }

    @Test
    @DisplayName("chat_message 가 없으면 멈춘다 — 11 을 먼저 돌려야 한다")
    void abortsWithoutThePrerequisite() throws Exception {
        try (Fixture db = fixture()) {
            db.exec("CREATE TABLE chat_room (id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY) ENGINE=InnoDB");

            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("11_chat.sql");
        }
    }

    @Test
    @DisplayName("reply_to_id 가 이미 있는데 모양이 다르면 멈춘다 — 조용히 덮지 않는다")
    void abortsOnAColumnWithTheWrongShape() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites();
            db.exec("ALTER TABLE chat_message ADD COLUMN reply_to_id bigint NOT NULL DEFAULT 0");

            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("bigint NULL 이 아니다");
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
            synchronized (ChatReplyMigrationExecutionTest.class) {
                name = "chatreply_test_" + (++dbCounter);
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

        /** chat_room · chat_message 의 최소 형태(11_chat.sql 의 모양을 줄인 것). */
        void createPrerequisites() throws SQLException {
            exec("CREATE TABLE chat_room (id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY, last_seq bigint NOT NULL DEFAULT 0) "
                    + "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
            exec("""
                    CREATE TABLE chat_message (
                      id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
                      room_id bigint NOT NULL,
                      room_seq bigint NOT NULL,
                      sender_user_id bigint NOT NULL,
                      sender_name varchar(255) NOT NULL,
                      content_type varchar(16) NOT NULL DEFAULT 'text',
                      body text NOT NULL,
                      client_msg_id varchar(64) DEFAULT NULL,
                      created_at datetime(6) NOT NULL,
                      deleted_at datetime(6) DEFAULT NULL,
                      UNIQUE KEY uq_chat_room_seq (room_id, room_seq),
                      CONSTRAINT fk_chat_room FOREIGN KEY (room_id) REFERENCES chat_room (id) ON DELETE CASCADE
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
            exec("INSERT INTO chat_room (id, last_seq) VALUES (1, 0)");
        }

        void insertMessage(long id, long seq, String body) throws SQLException {
            exec("INSERT INTO chat_message (id, room_id, room_seq, sender_user_id, sender_name, body, created_at) "
                    + "VALUES (" + id + ", 1, " + seq + ", 7, '보리아빠', '" + body + "', NOW(6))");
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
