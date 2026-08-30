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
 * {@code 07_family_group.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — 이슈 #75.
 *
 * <h2>왜 필요한가</h2>
 * <p>{@code mysql/init/01_schema.sql} 은 <b>빈 DB</b> 를 세우는 파일이라 이미 돌고 있는 운영
 * DB 에는 실행하지 않는다. 그래서 살아 있는 DB 에 {@code family_group} 을 넣는 경로는
 * {@code post-start/07} 하나뿐이고, prod 는 {@code ddl-auto=validate} 라 이 스크립트가 틀리면
 * <b>앱이 부팅에 실패한다.</b> {@code ChatRoomSchemaMigrationExecutionTest}(#74)가 06 에 대해
 * 하는 일을 07 에 대해 한다.
 *
 * <p>스프링을 띄우지 않는다 — 필요한 것이 <b>그 표가 아직 없는 DB</b> 라서다. 공유 컨테이너
 * 안에 테스트마다 별도 데이터베이스를 만든다. 컨텍스트를 하나도 늘리지 않는다(#21).
 */
class FamilyGroupSchemaMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/07_family_group.sql";
    private static final String RUNBOOK = "mysql/README.md";

    /** 데이터베이스 이름 충돌을 피하기 위한 카운터. 컨테이너 하나를 여러 테스트가 공유한다. */
    private static int dbCounter = 0;

    // ─────────────────────────── 테스트 ───────────────────────────

    @Test
    @DisplayName("빈 DB 에 돌리면 family_group 이 컬럼 셋으로 생기고, FK 는 하나도 없다")
    void migration_createsTheTableWithNoForeignKeysAtAll() throws Exception {
        try (Fixture db = fixture()) {
            db.runMigration();

            assertThat(db.tables()).containsExactly("family_group");
            assertThat(db.columns("family_group"))
                    .as("컬럼이 셋뿐인 것이 이 표의 요점이다 — 초대코드도 멤버십도 여기 없다")
                    .containsExactly("created_at", "id", "name");
            assertThat(db.foreignKeys())
                    .as("""
                            chat_room 으로 가는 FK 를 두면 화살표가 양방향이 되고 두 표는 어느 쪽도 \
                            혼자 못 움직인다. 방이 origin_kind/origin_ref 로 이 표를 불투명하게 \
                            가리키는 것이 유일한 통로다 (ADR-0011).""")
                    .isEmpty();
        }
    }

    @Test
    @DisplayName("두 번 돌려도 성공한다 — 재실행이 안전하다")
    void migration_isIdempotentAgainstRealMySql() throws Exception {
        try (Fixture db = fixture()) {
            db.runMigration();
            db.runMigration();   // ERROR 1050(표 중복)이 나면 실패한다

            assertThat(db.tables()).hasSize(1);
        }
    }

    @Test
    @DisplayName("옛 invite_code 컬럼이 남아 있으면 아무것도 바꾸지 않고 중단한다")
    void legacyInviteCodeColumn_abortsBeforeTouchingAnything() throws Exception {
        try (Fixture db = fixture()) {
            // ADR-0011 이전 정의를 흉내낸다 — 그룹당 코드 하나가 영구히 사는 모양이다.
            db.exec("""
                    CREATE TABLE family_group (
                        id          BIGINT      NOT NULL AUTO_INCREMENT PRIMARY KEY,
                        name        VARCHAR(50) NOT NULL,
                        invite_code VARCHAR(12) NOT NULL,
                        created_at  DATETIME(6) NOT NULL,
                        UNIQUE KEY uq_group_invite (invite_code)
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);

            assertThatThrownBy(db::runMigration)
                    .as("""
                            CREATE TABLE IF NOT EXISTS 는 이미 있는 표를 고치지 않는다. \
                            이 관문이 없으면 스크립트가 조용히 성공하고, 옛 컬럼은 그대로 남아 \
                            초대코드가 두 곳에 사는 상태가 된다.""")
                    .isInstanceOf(SQLException.class);
        }
    }

    @Test
    @DisplayName("이미 있는 표에 컬럼이 빠져 있으면 중단한다 — validate 가 부팅에서 잡기 전에 여기서 잡는다")
    void missingColumnsOnAnExistingTable_abort() throws Exception {
        try (Fixture db = fixture()) {
            db.exec("CREATE TABLE family_group (id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY) "
                    + "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

            assertThatThrownBy(db::runMigration)
                    .as("반쯤 맞는 표를 통과시키면 그 차이는 prod 부팅에서야 드러난다")
                    .isInstanceOf(SQLException.class);
        }
    }

    @Test
    @DisplayName("누가 group_member 표를 만들어 두면 중단한다 — 멤버십 표는 chat_room_member 하나다")
    void aSecondMembershipTable_aborts() throws Exception {
        try (Fixture db = fixture()) {
            db.runMigration();

            db.exec("CREATE TABLE group_member (id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY) "
                    + "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

            assertThatThrownBy(db::runMigration)
                    .as("""
                            둘을 두면 '가족인데 방에 없는 사람'·'방에 있는데 가족이 아닌 사람' 이라는 \
                            상태가 생기고, 그걸 막는 코드를 영원히 쓴다 (ADR-0011 결정 1).
                            산문으로만 정해 둔 결정은 6개월 뒤 사라진다 — 그래서 마이그레이션이 \
                            운영 DB 에서도 이걸 본다.""")
                    .isInstanceOf(SQLException.class);
        }
    }

    @Test
    @DisplayName("누가 chat_room 에서 family_group 으로 FK 를 걸어 두면 중단한다 — 운영 DB 에서도 경계를 지킨다")
    void aForeignKeyFromChatIntoTheGroup_aborts() throws Exception {
        try (Fixture db = fixture()) {
            db.runMigration();

            db.exec("""
                    CREATE TABLE chat_room (
                        id         BIGINT      NOT NULL AUTO_INCREMENT PRIMARY KEY,
                        origin_ref VARCHAR(64) NOT NULL,
                        group_id   BIGINT      NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
            db.exec("ALTER TABLE chat_room ADD CONSTRAINT fk_chat_room_group "
                    + "FOREIGN KEY (group_id) REFERENCES family_group (id)");

            assertThatThrownBy(db::runMigration)
                    .as("""
                            방이 가족 그룹을 FK 로 알면 산책 크루 방은 그 컬럼을 NULL 로 들고 다녀야 \
                            하고, 가족 그룹 삭제가 방 삭제 순서에 묶인다 (ADR-0011 결정 4).
                            06 이 'chat 밖으로 나가는 FK 0개' 로 같은 것을 보지만, 이 표를 만드는 \
                            순간이 그 FK 를 걸고 싶어지는 순간이라 07 도 본다.""")
                    .isInstanceOf(SQLException.class);
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
                .contains("post-start\\07_family_group.sql");
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
            synchronized (FamilyGroupSchemaMigrationExecutionTest.class) {
                name = "group_mig_test_" + (++dbCounter);
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

        /** {@code family_group} 이 걸거나 받는 FK 를 "자식 → 부모" 로. */
        List<String> foreignKeys() throws SQLException {
            return query("""
                    SELECT CONCAT(table_name, ' → ', referenced_table_name)
                    FROM information_schema.referential_constraints
                    WHERE constraint_schema = DATABASE()
                      AND (table_name = 'family_group' OR referenced_table_name = 'family_group')
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
