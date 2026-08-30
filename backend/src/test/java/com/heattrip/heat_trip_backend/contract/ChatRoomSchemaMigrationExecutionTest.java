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
 * {@code 06_chat_rooms.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — 이슈 #74.
 *
 * <h2>왜 필요한가</h2>
 * <p>{@code mysql/init/01_schema.sql} 은 <b>빈 DB</b> 를 세우는 파일이다. 이미 돌고 있는
 * 운영 DB 에는 실행하지 않는다. 그래서 지금 살아 있는 DB 에 세 표를 넣는 경로는
 * {@code post-start/06} 하나뿐이고, prod 는 {@code ddl-auto=validate} 라 이 스크립트가
 * 틀리면 <b>앱이 부팅에 실패한다.</b>
 *
 * <p>그런데 이 스크립트를 실제로 돌려 보지 않으면 아무도 모른다 —
 * {@code SchemaDdlDriftTest} 는 {@code init} 만 보고, {@code validate} 는 UNIQUE 도
 * 인덱스도 FK 도 검사하지 않는다.
 *
 * <h2>왜 스프링을 띄우지 않는가</h2>
 * <p>필요한 것이 <b>세 표가 아직 없는 DB</b> 라서다. JPA 엔티티가 만드는 스키마는 이미
 * 표가 있는 상태라 쓸 수 없다. 그래서 공유 컨테이너 안에 테스트마다 별도 데이터베이스를
 * 만들고 스크립트를 돌린다({@link UserSchemaMigrationExecutionTest} 와 같은 방식).
 * 컨텍스트를 하나도 늘리지 않는다(#21).
 *
 * <p>스크립트는 저장소의 <b>운영 파일 그대로</b>를 읽어 실행한다. 테스트용으로 베껴 쓰면
 * 운영 스크립트가 깨져도 초록불이다.
 */
class ChatRoomSchemaMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/06_chat_rooms.sql";
    private static final String RUNBOOK = "mysql/README.md";

    /** 데이터베이스 이름 충돌을 피하기 위한 카운터. 컨테이너 하나를 여러 테스트가 공유한다. */
    private static int dbCounter = 0;

    // ─────────────────────────── 테스트 ───────────────────────────

    @Test
    @DisplayName("빈 DB 에 돌리면 세 표와 제약이 전부 생긴다")
    void migration_createsAllThreeTablesWithTheirConstraints() throws Exception {
        try (Fixture db = fixture()) {
            db.runMigration();

            assertThat(db.tables())
                    .containsExactlyInAnyOrder("chat_room", "chat_room_member", "chat_room_invite");
            assertThat(db.uniqueIndexColumns("chat_room", "uq_chat_room_origin"))
                    .as("한 컬럼에만 UNIQUE 가 걸리면 같은 그룹에 방이 둘 생기는 것을 못 막는다")
                    .containsExactly("origin_kind", "origin_ref");
            assertThat(db.uniqueIndexColumns("chat_room_member", "uq_chat_member"))
                    .containsExactly("room_id", "user_id");
            assertThat(db.uniqueIndexColumns("chat_room_invite", "uq_chat_invite_code"))
                    .containsExactly("code");
        }
    }

    @Test
    @DisplayName("두 번 돌려도 성공한다 — 재실행이 안전하다")
    void migration_isIdempotentAgainstRealMySql() throws Exception {
        try (Fixture db = fixture()) {
            db.runMigration();
            db.runMigration();   // ERROR 1050(표 중복)·1061(인덱스 중복)이 나면 실패한다

            assertThat(db.tables()).hasSize(3);
        }
    }

    @Test
    @DisplayName("만든 FK 는 chat_room 을 가리키는 둘뿐이고, chat 밖으로 나가는 FK 는 0개다")
    void migration_keepsEveryForeignKeyInsideTheChatBoundary() throws Exception {
        try (Fixture db = fixture()) {
            db.runMigration();

            assertThat(db.foreignKeys())
                    .as("경계 안 FK 는 건다 — 방이 지워지면 멤버십·초대도 함께 지워져야 한다")
                    .containsExactlyInAnyOrder(
                            "chat_room_member → chat_room",
                            "chat_room_invite → chat_room");
        }
    }

    @Test
    @DisplayName("누가 users FK 를 손으로 걸어 두면 다음 실행이 중단된다 — 운영 DB 에서도 경계를 지킨다")
    void migration_abortsWhenAForeignKeyLeftTheBoundary() throws Exception {
        try (Fixture db = fixture()) {
            db.runMigration();

            db.exec("CREATE TABLE users (id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY) "
                    + "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
            db.exec("ALTER TABLE chat_room_member ADD CONSTRAINT fk_chat_member_user "
                    + "FOREIGN KEY (user_id) REFERENCES users (id)");

            assertThatThrownBy(db::runMigration)
                    .as("""
                            탈퇴 경로가 DB 삭제 순서에 묶이고, ON DELETE CASCADE 면 탈퇴 한 번에 \
                            남의 방 멤버십과 미읽음 기준이 사라진다 (ADR-0011 결정 4).
                            저장소 쪽은 ChatBoundaryArchitectureTest 가 같은 것을 잡는다.""")
                    .isInstanceOf(SQLException.class);
        }
    }

    @Test
    @DisplayName("이미 있는 chat_room 에 중복 origin 쌍이 있으면 아무것도 바꾸지 않고 중단한다")
    void duplicateOriginPairs_abortBeforeTouchingAnything() throws Exception {
        try (Fixture db = fixture()) {
            // 지난번에 Hibernate 의 ddl-auto=update 가 UNIQUE 없이 만들어 둔 상태를 흉내낸다.
            db.exec("""
                    CREATE TABLE chat_room (
                        id          BIGINT      NOT NULL AUTO_INCREMENT PRIMARY KEY,
                        origin_kind VARCHAR(20) NOT NULL,
                        origin_ref  VARCHAR(64) NOT NULL,
                        name        VARCHAR(50) NOT NULL,
                        tag         VARCHAR(20) NOT NULL,
                        last_seq    BIGINT      NOT NULL DEFAULT 0,
                        created_at  DATETIME(6) NOT NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
            db.exec("INSERT INTO chat_room (origin_kind, origin_ref, name, tag, created_at) "
                    + "VALUES ('FAMILY', '1', '우리 가족', '가족', NOW(6))");
            db.exec("INSERT INTO chat_room (origin_kind, origin_ref, name, tag, created_at) "
                    + "VALUES ('FAMILY', '1', '우리 가족(중복)', '가족', NOW(6))");

            assertThatThrownBy(db::runMigration)
                    .as("제약을 못 거는 데이터를 만나면 아무것도 바꾸기 전에 멈춰야 한다")
                    .isInstanceOf(SQLException.class);

            assertThat(db.tables())
                    .as("중단했는데 나머지 표가 생겼다면 '반쯤 적용된' 상태다")
                    .containsExactly("chat_room");
        }
    }

    @Test
    @DisplayName("런북(mysql/README.md)이 이 파일의 실행 커맨드를 담고 있다")
    void runbook_listsThisScript() throws Exception {
        String runbook = Files.readString(
                TestProjectPaths.requireFile(RUNBOOK), StandardCharsets.UTF_8);

        assertThat(runbook)
                .as("실행 순서에 없는 스크립트는 아무도 돌리지 않는다 — 그러면 운영 DB 에 표가 안 생긴다")
                .contains("post-start\\06_chat_rooms.sql");
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private static Fixture fixture() throws SQLException {
        return new Fixture();
    }

    /** 공유 컨테이너 안의 <b>일회용 데이터베이스</b> 하나. {@link #close()} 가 통째로 지운다. */
    private static final class Fixture implements AutoCloseable {

        private final String name;
        private final Connection connection;

        Fixture() throws SQLException {
            MySQLContainer<?> mysql = MySqlTestContainer.instance();
            synchronized (ChatRoomSchemaMigrationExecutionTest.class) {
                name = "chat_mig_test_" + (++dbCounter);
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

        /** 저장소의 운영 스크립트를 그대로 한 커넥션에서 순서대로 실행한다. */
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

        List<String> tables() throws SQLException {
            return query("""
                    SELECT table_name FROM information_schema.tables
                    WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE'
                      AND table_name LIKE 'chat\\_%'
                    ORDER BY table_name
                    """);
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

        /** {@code chat_*} 표가 내보내는 FK 를 "자식 → 부모" 로. */
        List<String> foreignKeys() throws SQLException {
            return query("""
                    SELECT CONCAT(table_name, ' → ', referenced_table_name)
                    FROM information_schema.referential_constraints
                    WHERE constraint_schema = DATABASE() AND table_name LIKE 'chat\\_%'
                    ORDER BY table_name
                    """);
        }

        private List<String> query(String sql) throws SQLException {
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
