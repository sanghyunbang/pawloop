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
 * {@code 48_chat_reaction.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — #452.
 *
 * <h2>여기서 가장 중요한 것</h2>
 * <p><b>{@code user_id} 에 FK 가 없는가.</b> 있으면 탈퇴 경로가 DB 삭제 순서에 묶이고,
 * {@code CASCADE} 면 탈퇴 한 번에 남의 대화에 남아 있던 반응이 사라진다(ADR-0011 결정 4).
 * 이 표를 손으로 만드는 사람이 가장 자연스럽게 하는 일이 {@code users} 로 FK 를 내는 것이라
 * 스크립트의 사후 검증이 그것을 센다 — 그 검사가 진짜로 막는지를 여기서 잰다.
 *
 * <p>그다음이 <b>유니크 셋</b>이다. 없으면 멱등 삽입이 같은 반응을 여러 줄 만들어 집계가 늘고,
 * {@code (message_id, user_id)} 둘로 줄면 라디오가 되어 종류를 하나만 누를 수 있다.
 * {@code SchemaDdlDriftTest} 는 컬럼만 보고 인덱스·FK 는 안 본다.
 *
 * <p>스프링을 띄우지 않는다(#21).
 */
class ChatReactionMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/48_chat_reaction.sql";

    private static int dbCounter = 0;

    @Test
    @DisplayName("표가 생기고 유니크 셋과 CASCADE FK 하나가 선다 — chat 밖으로 나가는 FK 는 없다")
    void createsTheTableWithItsUniqueAndCascade() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites();

            db.runMigration();

            assertThat(db.query("SELECT column_name FROM information_schema.columns "
                    + "WHERE table_schema = DATABASE() AND table_name = 'chat_message_reaction' "
                    + "ORDER BY column_name"))
                    .containsExactly("created_at", "id", "kind", "message_id", "user_id");

            assertThat(db.query("SELECT column_name FROM information_schema.statistics "
                    + "WHERE table_schema = DATABASE() AND table_name = 'chat_message_reaction' "
                    + "AND index_name = 'uq_chat_reaction' AND non_unique = 0 ORDER BY seq_in_index"))
                    .as("""
                            셋이라야 한 사람이 한 말에 여러 종류를 누를 수 있다. 둘로 줄이면 라디오가 되고, \
                            아예 없으면 멱등 삽입이 같은 반응을 여러 줄 만든다.""")
                    .containsExactly("message_id", "user_id", "kind");

            assertThat(db.query("SELECT CONCAT(constraint_name, ' → ', referenced_table_name, ' ', delete_rule) "
                    + "FROM information_schema.referential_constraints "
                    + "WHERE constraint_schema = DATABASE() AND table_name = 'chat_message_reaction'"))
                    .as("""
                            users 로 FK 를 내면 탈퇴 한 번에 남의 대화에 남은 반응이 사라진다 \
                            (ADR-0011 결정 4). chat 의 모든 표가 사람을 id 로만 안다.""")
                    .containsExactly("fk_chat_reaction_message → chat_message CASCADE");
        }
    }

    @Test
    @DisplayName("말이 정말로 사라지면 반응도 사라진다 — 톰스톤(소프트 삭제)은 서버가 따로 거둔다")
    void reactionsDieWithTheMessageRow() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites();
            db.runMigration();
            db.seedTwoMessages();
            db.exec("INSERT INTO chat_message_reaction (message_id, user_id, kind, created_at) VALUES "
                    + "(1, 7, 'like', NOW(6)), (1, 8, 'check', NOW(6)), (2, 7, 'like', NOW(6))");

            db.exec("DELETE FROM chat_message WHERE id = 1");

            assertThat(db.query("SELECT message_id FROM chat_message_reaction"))
                    .as("없는 말을 가리키는 반응은 남길 이유가 없다")
                    .containsExactly("2");
        }
    }

    @Test
    @DisplayName("같은 사람이 같은 말에 같은 종류를 두 번 넣을 수 없다 — 이 유니크가 멱등을 딛는다")
    void rejectsADuplicateReaction() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites();
            db.runMigration();
            db.seedTwoMessages();
            db.exec("INSERT INTO chat_message_reaction (message_id, user_id, kind, created_at) "
                    + "VALUES (1, 7, 'like', NOW(6))");

            assertThatThrownBy(() -> db.exec(
                    "INSERT INTO chat_message_reaction (message_id, user_id, kind, created_at) "
                            + "VALUES (1, 7, 'like', NOW(6))"))
                    .isInstanceOf(SQLException.class);

            db.exec("INSERT INTO chat_message_reaction (message_id, user_id, kind, created_at) "
                    + "VALUES (1, 7, 'heart', NOW(6))");
            assertThat(db.query("SELECT COUNT(*) FROM chat_message_reaction"))
                    .as("종류가 다르면 같은 사람이 같은 말에 또 누를 수 있다")
                    .containsExactly("2");
        }
    }

    @Test
    @DisplayName("두 번 돌려도 그대로다 — 멱등")
    void secondRunIsIdempotent() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites();
            db.runMigration();
            db.seedTwoMessages();
            db.exec("INSERT INTO chat_message_reaction (message_id, user_id, kind, created_at) "
                    + "VALUES (1, 7, 'like', NOW(6))");

            db.runMigration();

            assertThat(db.query("SELECT COUNT(*) FROM chat_message_reaction")).containsExactly("1");
        }
    }

    @Test
    @DisplayName("chat_message 가 없으면 멈춘다 — 11 을 먼저 돌려야 한다")
    void abortsWithoutTheMessageTable() throws Exception {
        try (Fixture db = fixture()) {
            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("11_chat.sql");
        }
    }

    @Test
    @DisplayName("Hibernate 가 먼저 만든 표(유니크도 FK 도 없다)는 사후 검증이 멈춰 세운다")
    void refusesToPassOverATableHibernateMadeWithoutTheConstraints() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites();
            // dev 에서 앱을 먼저 띄운 모양 — 표는 있는데 유니크도 FK 도 없다.
            db.exec("""
                    CREATE TABLE chat_message_reaction (
                      id bigint NOT NULL AUTO_INCREMENT,
                      message_id bigint NOT NULL,
                      user_id bigint NOT NULL,
                      kind varchar(20) NOT NULL,
                      created_at datetime(6) NOT NULL,
                      PRIMARY KEY (id)
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);

            assertThatThrownBy(db::runMigration)
                    .as("""
                            조용히 지나가면 유니크도 CASCADE 도 없는 표가 남는다 — 같은 반응이 여러 줄 \
                            쌓이고, 지워진 말의 반응이 영원히 남는다. 그 상태를 사람이 알아채는 곳이 여기뿐이다.""")
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("사후 검증");
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
            synchronized (ChatReactionMigrationExecutionTest.class) {
                name = "chatreaction_test_" + (++dbCounter);
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

        /** FK 가 걸리는 표의 최소 형태 — 방과 말. 사람 표는 안 만든다(FK 가 없어야 정상이다). */
        void createPrerequisites() throws SQLException {
            exec("""
                    CREATE TABLE chat_room (
                      id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
                      last_seq bigint NOT NULL DEFAULT 0,
                      last_change_seq bigint NOT NULL DEFAULT 0
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
            exec("""
                    CREATE TABLE chat_message (
                      id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
                      room_id bigint NOT NULL,
                      room_seq bigint NOT NULL,
                      sender_user_id bigint NOT NULL,
                      body text NOT NULL,
                      created_at datetime(6) NOT NULL,
                      change_seq bigint DEFAULT NULL,
                      CONSTRAINT fk_chat_room FOREIGN KEY (room_id) REFERENCES chat_room (id) ON DELETE CASCADE
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
        }

        void seedTwoMessages() throws SQLException {
            exec("INSERT INTO chat_room (id, last_seq) VALUES (1, 2)");
            exec("INSERT INTO chat_message (id, room_id, room_seq, sender_user_id, body, created_at) VALUES "
                    + "(1, 1, 1, 7, '보리 밥 줬어요', NOW(6)), (2, 1, 2, 8, '고마워요', NOW(6))");
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
