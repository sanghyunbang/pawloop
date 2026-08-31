package com.heattrip.heat_trip_backend.contract;

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

import com.heattrip.heat_trip_backend.support.MySqlTestContainer;
import com.heattrip.heat_trip_backend.support.TestProjectPaths;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.testcontainers.containers.MySQLContainer;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * {@code 09_chat_message.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — 이슈 #78.
 *
 * <h2>왜 필요한가</h2>
 * <p>{@code mysql/init/01_schema.sql} 은 <b>빈 DB</b> 를 세우는 파일이다. 이미 돌고 있는
 * 운영 DB 에는 실행하지 않는다. 그래서 지금 살아 있는 DB 에 {@code chat_message} 를 넣는
 * 경로는 {@code post-start/09} 하나뿐이고, prod 는 {@code ddl-auto=validate} 라 이 스크립트가
 * 틀리면 <b>앱이 부팅에 실패한다.</b> {@code ChatRoomSchemaMigrationExecutionTest}(#74)가
 * 06 에 대해 하는 일을 09 에 대해 한다.
 *
 * <p>09 가 06 과 다르게 보는 것이 하나 있다 — <b>부모 표가 없을 때 멈추는가.</b> 06 은
 * 자기가 만드는 세 표가 전부라 순서 의존이 없었지만, 이 표는 {@code chat_room} 에 FK 를
 * 건다. 순서를 지키지 않은 실행이 조용히 절반만 성공하면 그게 더 나쁘다.
 *
 * <p>그리고 {@code ddl-auto=validate} 도 {@code SchemaDdlDriftTest} 도 <b>UNIQUE 를 보지
 * 않는다.</b> {@code uq_chat_room_seq} 가 빠진 채 배포해도 앱은 멀쩡히 뜨고, 발급이 틀린
 * 날 조용히 메시지 하나가 사라진다. 여기서 안 보면 아무도 안 알려준다.
 *
 * <p>스프링을 띄우지 않는다 — 필요한 것이 <b>그 표가 아직 없는 DB</b> 라서다. 공유 컨테이너
 * 안에 테스트마다 별도 데이터베이스를 만든다. 컨텍스트를 하나도 늘리지 않는다(#21).
 */
class ChatMessageSchemaMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/09_chat_message.sql";
    private static final String PARENT = "mysql/post-start/06_chat_rooms.sql";
    private static final String RUNBOOK = "mysql/README.md";

    /** 데이터베이스 이름 충돌을 피하기 위한 카운터. 컨테이너 하나를 여러 테스트가 공유한다. */
    private static int dbCounter = 0;

    // ─────────────────────────── 테스트 ───────────────────────────

    @Test
    @DisplayName("방 표가 있는 DB 에 돌리면 chat_message 와 컬럼 열이 생긴다")
    void migration_createsTheMessageTableWithEveryColumn() throws Exception {
        try (Fixture db = fixture()) {
            db.createParent();
            db.runMigration();

            assertThat(db.tables()).contains("chat_message");
            assertThat(db.columns("chat_message"))
                    .as("이슈 #78 이 정한 컬럼 열이다. 하나라도 빠지면 ddl-auto=validate 가 부팅을 막는다")
                    .containsExactly("body", "client_msg_id", "content_type", "created_at",
                            "deleted_at", "id", "room_id", "room_seq", "sender_name",
                            "sender_user_id");
        }
    }

    @Test
    @DisplayName("UNIQUE 둘이 컬럼 쌍 그대로 걸린다 — 이름만 맞고 한 컬럼만 걸린 UNIQUE 는 통과시키지 않는다")
    void migration_putsBothUniqueConstraintsOnTheColumnPairs() throws Exception {
        try (Fixture db = fixture()) {
            db.createParent();
            db.runMigration();

            assertThat(db.uniqueIndexColumns("chat_message", "uq_chat_room_seq"))
                    .as("""
                            (room_id) 하나에만 걸리면 한 방에 메시지가 한 줄만 들어가고, \
                            (room_seq) 하나에만 걸리면 서로 다른 방이 같은 번호를 못 쓴다. \
                            둘 다 이 스크립트가 성공한 것처럼 끝난 뒤에야 드러난다.""")
                    .containsExactly("room_id", "room_seq");
            assertThat(db.uniqueIndexColumns("chat_message", "uq_chat_msg_client"))
                    .as("재전송 멱등의 근거다 (#79 완료 조건 3·8)")
                    .containsExactly("room_id", "client_msg_id");
            assertThat(db.indexColumns("chat_message", "idx_chat_sender"))
                    .as("신고 처리에서 '이 사람이 무엇을 썼나' 를 물을 때 쓰는 인덱스다")
                    .containsExactly("sender_user_id");
        }
    }

    @Test
    @DisplayName("멱등키가 NULL 인 행은 여러 줄 들어간다 — UNIQUE 가 멱등키 없는 전송을 막지 않는다")
    void theClientIdUnique_doesNotBlockMessagesWithoutAKey() throws Exception {
        try (Fixture db = fixture()) {
            db.createParent();
            db.runMigration();
            db.exec("INSERT INTO chat_room (origin_kind, origin_ref, name, tag) "
                    + "VALUES ('FAMILY', '1', '우리 가족', '가족')");

            db.exec(insertMessage(1, null));
            db.exec(insertMessage(2, null));

            assertThat(db.query("SELECT COUNT(*) FROM chat_message"))
                    .as("MySQL 의 UNIQUE 인덱스는 NULL 을 여러 번 허용한다 — 그 성질에 기대고 있다")
                    .containsExactly("2");

            assertThatThrownBy(() -> db.exec(insertMessage(3, "same-key")
                    + "; " + insertMessage(4, "same-key")))
                    .as("키가 있으면 같은 방에 두 번 들어가지 못한다")
                    .isInstanceOf(SQLException.class);
        }
    }

    @Test
    @DisplayName("두 번 돌려도 성공한다 — 재실행이 안전하다")
    void migration_isIdempotentAgainstRealMySql() throws Exception {
        try (Fixture db = fixture()) {
            db.createParent();
            db.runMigration();
            db.runMigration();   // ERROR 1050(표 중복)·1061(인덱스 중복)이 나면 실패한다

            assertThat(db.tables()).contains("chat_message");
        }
    }

    @Test
    @DisplayName("만든 FK 는 chat_room 을 가리키는 하나뿐이고, chat 밖으로 나가는 FK 는 0개다")
    void migration_keepsEveryForeignKeyInsideTheChatBoundary() throws Exception {
        try (Fixture db = fixture()) {
            db.createParent();
            db.runMigration();

            assertThat(db.foreignKeysOfMessage())
                    .as("""
                            경계 안 FK 는 건다 — 방이 지워지면 그 방의 대화도 갈 곳이 없다.
                            sender_user_id 에 users FK 를 거는 것은 반대다: ON DELETE CASCADE 면 \
                            탈퇴 한 번에 그 사람이 방에 쓴 말이 전부 사라진다 (ADR-0011 결정 4).""")
                    .containsExactly("chat_message → chat_room");
        }
    }

    @Test
    @DisplayName("chat_room 이 없으면 아무것도 만들지 않고 멈춘다 — 06 을 먼저 돌리라고 말한다")
    void migration_abortsWhenTheParentTableIsMissing() throws Exception {
        try (Fixture db = fixture()) {
            assertThatThrownBy(db::runMigration)
                    .as("""
                            FK 를 빼고 만들어 두는 선택지는 없다 — 방이 지워졌는데 그 방의 메시지가 \
                            남으면 아무도 볼 수 없는 행이 영원히 쌓인다. 순서를 어긴 실행이 절반만 \
                            성공하는 것보다 여기서 멈추는 쪽이 낫다.""")
                    .isInstanceOf(SQLException.class);

            assertThat(db.tables())
                    .as("멈췄는데 표가 생겼다면 '반쯤 적용된' 상태다")
                    .doesNotContain("chat_message");
        }
    }

    @Test
    @DisplayName("누가 users FK 를 손으로 걸어 두면 다음 실행이 중단된다 — 운영 DB 에서도 경계를 지킨다")
    void migration_abortsWhenAForeignKeyLeftTheBoundary() throws Exception {
        try (Fixture db = fixture()) {
            db.createParent();
            db.runMigration();

            db.exec("CREATE TABLE users (id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY) "
                    + "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
            db.exec("ALTER TABLE chat_message ADD CONSTRAINT fk_chat_message_user "
                    + "FOREIGN KEY (sender_user_id) REFERENCES users (id)");

            assertThatThrownBy(db::runMigration)
                    .as("""
                            탈퇴 경로가 DB 삭제 순서에 묶인다. 저장소 쪽은 \
                            ChatBoundaryArchitectureTest 가 같은 것을 잡는다 (#78 완료 조건 6).""")
                    .isInstanceOf(SQLException.class);
        }
    }

    @Test
    @DisplayName("이미 있는 chat_message 에 중복 (room_id, room_seq) 가 있으면 아무것도 바꾸지 않고 중단한다")
    void duplicateRoomSeqs_abortBeforeTouchingAnything() throws Exception {
        try (Fixture db = fixture()) {
            db.createParent();
            // 지난번에 Hibernate 의 ddl-auto=update 가 UNIQUE 없이 만들어 둔 상태를 흉내낸다.
            db.exec("""
                    CREATE TABLE chat_message (
                        id             BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
                        room_id        BIGINT       NOT NULL,
                        room_seq       BIGINT       NOT NULL,
                        sender_user_id BIGINT       NOT NULL,
                        sender_name    VARCHAR(255) NOT NULL,
                        content_type   VARCHAR(16)  NOT NULL DEFAULT 'text',
                        body           TEXT         NOT NULL,
                        client_msg_id  VARCHAR(64)  NULL,
                        created_at     DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
                        deleted_at     DATETIME(6)  NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
            db.exec(insertMessage(1, null));
            db.exec(insertMessage(1, null));

            assertThatThrownBy(db::runMigration)
                    .as("제약을 못 거는 데이터를 만나면 아무것도 바꾸기 전에 멈춰야 한다")
                    .isInstanceOf(SQLException.class);

            assertThat(db.uniqueIndexColumns("chat_message", "uq_chat_room_seq"))
                    .as("중단했는데 제약이 걸렸다면 사전 점검이 지나간 뒤에 멈춘 것이다")
                    .isEmpty();
        }
    }

    @Test
    @DisplayName("런북(mysql/README.md)이 이 파일의 실행 커맨드를 담고 있다")
    void runbook_listsThisScript() throws Exception {
        String runbook = Files.readString(
                TestProjectPaths.requireFile(RUNBOOK), StandardCharsets.UTF_8);

        assertThat(runbook)
                .as("실행 순서에 없는 스크립트는 아무도 돌리지 않는다 — 그러면 운영 DB 에 표가 안 생기고 "
                        + "prod 는 ddl-auto=validate 라 부팅이 실패한다")
                .contains("post-start\\09_chat_message.sql");
    }

    // ─────────────────────────── 지그 ───────────────────────────

    /** 방 1번에 메시지 한 줄. 번호와 멱등키만 바꾼다. */
    private static String insertMessage(long seq, String clientMsgId) {
        return ("INSERT INTO chat_message "
                + "(room_id, room_seq, sender_user_id, sender_name, body, client_msg_id) "
                + "VALUES (1, %d, 7, '보호자', '안녕하세요', %s)")
                .formatted(seq, clientMsgId == null ? "NULL" : "'" + clientMsgId + "'");
    }

    private static Fixture fixture() throws SQLException {
        return new Fixture();
    }

    /** 공유 컨테이너 안의 <b>일회용 데이터베이스</b> 하나. {@link #close()} 가 통째로 지운다. */
    private static final class Fixture implements AutoCloseable {

        private final String name;
        private final Connection connection;

        Fixture() throws SQLException {
            MySQLContainer<?> mysql = MySqlTestContainer.instance();
            synchronized (ChatMessageSchemaMigrationExecutionTest.class) {
                name = "chat_msg_mig_test_" + (++dbCounter);
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
         * 부모 표를 세운다 — <b>저장소의 06 스크립트를 그대로</b> 돌린다.
         *
         * <p>{@code chat_room} 을 여기서 손으로 만들면 06 이 깨져도 이 테스트는 초록불이고,
         * 무엇보다 09 가 실제로 만나게 될 모양(06 이 만든 그것)과 다를 수 있다.
         */
        void createParent() throws Exception {
            runScript(PARENT);
        }

        /** 저장소의 운영 스크립트를 그대로 한 커넥션에서 순서대로 실행한다. */
        void runMigration() throws Exception {
            runScript(SCRIPT);
        }

        private void runScript(String path) throws Exception {
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
                for (String statement : sql.split(";")) {
                    if (!statement.isBlank()) {
                        st.execute(statement);
                    }
                }
            }
        }

        List<String> tables() throws SQLException {
            return query("""
                    SELECT table_name FROM information_schema.tables
                    WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE'
                    ORDER BY table_name
                    """);
        }

        List<String> columns(String table) throws SQLException {
            return query("""
                    SELECT column_name FROM information_schema.columns
                    WHERE table_schema = DATABASE() AND table_name = '%s'
                    ORDER BY column_name
                    """.formatted(table));
        }

        /** 이름이 붙은 UNIQUE 인덱스의 컬럼을 순서대로. UNIQUE 가 아니면 빈 목록이다. */
        List<String> uniqueIndexColumns(String table, String index) throws SQLException {
            return query("""
                    SELECT column_name FROM information_schema.statistics
                    WHERE table_schema = DATABASE() AND table_name = '%s'
                      AND index_name = '%s' AND non_unique = 0
                    ORDER BY seq_in_index
                    """.formatted(table, index));
        }

        /** 이름이 붙은 인덱스의 컬럼을 순서대로. UNIQUE 여부는 보지 않는다. */
        List<String> indexColumns(String table, String index) throws SQLException {
            return query("""
                    SELECT column_name FROM information_schema.statistics
                    WHERE table_schema = DATABASE() AND table_name = '%s' AND index_name = '%s'
                    ORDER BY seq_in_index
                    """.formatted(table, index));
        }

        /** {@code chat_message} 가 내보내는 FK 를 "자식 → 부모" 로. */
        List<String> foreignKeysOfMessage() throws SQLException {
            return query("""
                    SELECT CONCAT(table_name, ' → ', referenced_table_name)
                    FROM information_schema.referential_constraints
                    WHERE constraint_schema = DATABASE() AND table_name = 'chat_message'
                    ORDER BY constraint_name
                    """);
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

    /** 세미콜론으로 문장을 나눈다. 줄 주석은 먼저 걷는다 — 주석 안의 DOWN SQL 이 실행되면 안 된다. */
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
