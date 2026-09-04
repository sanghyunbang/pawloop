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
 * {@code 15_report.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — 이슈 #166.
 *
 * <h2>왜 필요한가</h2>
 * <p>{@code mysql/init/01_schema.sql} 은 <b>빈 DB</b> 를 세우는 파일이라 이미 돌고 있는 운영
 * DB 에는 실행하지 않는다. 살아 있는 DB 에 {@code report}·{@code report_snapshot} 을 넣는
 * 경로는 {@code post-start/15} 하나뿐이고, prod 는 {@code ddl-auto=validate} 라 이 스크립트가
 * 틀리면 <b>앱이 부팅에 실패한다.</b>
 *
 * <p>그리고 {@code SchemaDdlDriftTest} 도 {@code ddl-auto=validate} 도 <b>FK 삭제 규칙과
 * CHECK 을 보지 않는다.</b> 여기서 안 보면 아무도 안 알려준다 — {@code CommunitySchemaMigration
 * ExecutionTest} 가 같은 이유로 있다.
 *
 * <p>스프링을 띄우지 않는다. 필요한 것이 <b>그 표가 아직 없는 DB</b> 라서다(#21).
 */
class ReportSchemaMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/15_report.sql";

    /** 데이터베이스 이름 충돌을 피하기 위한 카운터. 컨테이너 하나를 여러 테스트가 공유한다. */
    private static int dbCounter = 0;

    // ─────────────────────────── 테스트 ───────────────────────────

    @Test
    @DisplayName("빈 DB(users 만 있는)에 돌리면 표 둘이 생긴다")
    void migration_createsBothTables() throws Exception {
        try (Fixture db = fixture()) {
            db.createParents();
            db.runMigration();

            assertThat(db.tables())
                    .as("하나라도 빠지면 ddl-auto=validate 가 부팅을 막는다")
                    .contains("report", "report_snapshot");
        }
    }

    @Test
    @DisplayName("스냅샷은 신고가 사라지면 함께 사라진다 — 부모 없는 본문이 남으면 안 된다")
    void snapshotCascadesWithTheReport() throws Exception {
        try (Fixture db = fixture()) {
            db.createParents();
            db.runMigration();

            assertThat(db.deleteRuleOf("fk_report_snapshot_report"))
                    .as("""
                            RESTRICT 면 신고를 못 지우고, SET NULL 이면 어느 신고의 사본인지 \
                            모르는 채 본문만 쌓인다. comment·reaction 이 post 에 대해 같은 \
                            이유로 CASCADE 다.""")
                    .isEqualTo("CASCADE");

            db.seedOneReport();
            assertThat(db.count("report_snapshot")).isEqualTo(1);

            db.exec("DELETE FROM report WHERE id = 1");
            assertThat(db.count("report_snapshot"))
                    .as("신고를 지웠으면 사본도 없어야 한다")
                    .isZero();
        }
    }

    @Test
    @DisplayName("users 로 FK 를 걸지 않는다 — 탈퇴해도 누가 신고했는지가 남아야 한다")
    void noForeignKeyToUsers() throws Exception {
        try (Fixture db = fixture()) {
            db.createParents();
            db.runMigration();

            assertThat(db.foreignKeys())
                    .as("""
                            FK 는 report_snapshot → report 하나뿐이다. users 로 걸면 \
                            SET NULL 이든 CASCADE 든 탈퇴한 사람의 신고 이력이 사라지고, \
                            운영자가 '이 사람이 반복 신고당했다' 를 셀 수 없게 된다.""")
                    .containsExactly("report_snapshot → report");
        }
    }

    @Test
    @DisplayName("값이 정해진 세 컬럼에 CHECK 이 걸린다 — 서비스를 안 지나는 경로가 무방비면 안 된다")
    void valuesAreLockedByChecks() throws Exception {
        try (Fixture db = fixture()) {
            db.createParents();
            db.runMigration();

            assertThat(db.checks())
                    .containsExactlyInAnyOrder(
                            "chk_report_reason", "chk_report_snapshot_role",
                            "chk_report_target_type");

            db.seedOneReport();
            assertThatThrownBy(() -> db.exec(
                    "INSERT INTO report (target_type, target_id, reporter_user_id, reason, created_at) "
                            + "VALUES ('community_post', 2, 1, '광고', NOW(6))"))
                    .as("한글 사유가 들어가면 운영자가 세는 숫자가 그 순간부터 틀어진다")
                    .isInstanceOf(SQLException.class);

            assertThatThrownBy(() -> db.exec(
                    "INSERT INTO report (target_type, target_id, reporter_user_id, reason, created_at) "
                            + "VALUES ('emotion_card', 2, 1, 'spam', NOW(6))"))
                    .as("아직 안 여는 대상 종류는 CHECK 이 막는다 — 여는 날 여기를 함께 고친다")
                    .isInstanceOf(SQLException.class);
        }
    }

    @Test
    @DisplayName("author_name 이 users.nickname 과 같은 255 다 — 좁으면 그 사람 글을 아무도 신고 못 한다")
    void authorNameIsAsWideAsNickname() throws Exception {
        try (Fixture db = fixture()) {
            db.createParents();
            db.runMigration();

            assertThat(db.columnLength("report_snapshot", "author_name"))
                    .as("""
                            #170 이 post.handle 을 50 으로 잡아 51자 닉네임을 가진 사람의 모든 \
                            글쓰기가 영구히 500 이 된 적이 있다. 참조하는 쪽이 원본보다 좁으면 안 된다.""")
                    .isEqualTo(255);
            assertThat(db.columnLength("report_snapshot", "title"))
                    .as("post.title 과 같은 폭이어야 긴 제목이 잘리지 않는다")
                    .isEqualTo(200);
        }
    }

    @Test
    @DisplayName("같은 사람이 같은 글을 두 번 신고할 수 있다 — 글이 수정되기 때문이다")
    void duplicateReportsAreAllowed() throws Exception {
        try (Fixture db = fixture()) {
            db.createParents();
            db.runMigration();
            db.exec("INSERT INTO users (id, role) VALUES (1, 'USER')");

            db.exec("INSERT INTO report (target_type, target_id, reporter_user_id, reason, created_at) "
                    + "VALUES ('community_post', 7, 1, 'spam', NOW(6))");
            db.exec("INSERT INTO report (target_type, target_id, reporter_user_id, reason, created_at) "
                    + "VALUES ('community_post', 7, 1, 'abuse', NOW(6))");

            assertThat(db.count("report"))
                    .as("""
                            UNIQUE 를 걸면 작성자가 신고 뒤 본문을 더 나쁜 것으로 고쳤을 때 \
                            (#211 이 PATCH 를 열었다) 재신고가 막히고, 운영자에게 남는 기록은 \
                            고치기 전 본문뿐이다. chat_report 에도 UNIQUE 가 없다.""")
                    .isEqualTo(2);
        }
    }

    @Test
    @DisplayName("두 번 돌려도 같은 상태로 끝난다")
    void migrationIsIdempotent() throws Exception {
        try (Fixture db = fixture()) {
            db.createParents();
            db.runMigration();
            db.runMigration();

            assertThat(db.tables()).contains("report", "report_snapshot");
            assertThat(db.checks()).hasSize(3);
        }
    }

    @Test
    @DisplayName("나중에 컬럼이 늘어도 다시 돌아간다 — 사후 검증이 개수가 아니라 이름을 센다")
    void migrationStaysRerunnableAfterAColumnIsAdded() throws Exception {
        // 런북이 "전부 멱등이라 이미 적용된 항목은 아무 변경 없이 메시지만 출력합니다" 라고
        // 약속한다(mysql/README.md). 그런데 사후 검증이 표의 **전체 컬럼 수**를 리터럴과
        // 견주면, 다음 마이그레이션이 컬럼을 하나 더하는 순간 그 약속이 깨진다 — 그 뒤로
        // 이 스크립트가 ABORT 한다.
        //
        // #254(chat_report 흡수)가 정확히 report_snapshot 에 컬럼을 더하는 작업이라,
        // 그날 이 자리가 터진다. 여기서 그 미래를 흉내 내 재 둔다 (#267).
        try (Fixture db = fixture()) {
            db.createParents();
            db.runMigration();

            db.exec("ALTER TABLE report_snapshot ADD COLUMN target_ordinal BIGINT NULL");
            db.exec("ALTER TABLE report ADD COLUMN handled_at DATETIME(6) NULL");

            db.runMigration();

            assertThat(db.tables()).contains("report", "report_snapshot");
            assertThat(db.checks())
                    .as("재실행이 제약을 건드리지 않는다")
                    .hasSize(3);
        }
    }
    @Test
    @DisplayName("users 가 없으면 한 글자도 안 바꾸고 멈춘다")
    void migrationAbortsWithoutUsers() throws Exception {
        try (Fixture db = fixture()) {
            assertThatThrownBy(db::runMigration)
                    .as("사전 점검이 걸리면 표가 하나도 안 생겨야 한다")
                    .isInstanceOf(SQLException.class);

            assertThat(db.tables()).doesNotContain("report", "report_snapshot");
        }
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
            synchronized (ReportSchemaMigrationExecutionTest.class) {
                name = "report_mig_test_" + (++dbCounter);
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

        /** {@code users} 는 이 스크립트의 사전 점검이 존재만 본다 — 최소 모양으로 만든다. */
        void createParents() throws Exception {
            exec("""
                    CREATE TABLE users (
                        id   BIGINT      NOT NULL AUTO_INCREMENT PRIMARY KEY,
                        role VARCHAR(20) NOT NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
        }

        /** 신고 하나와 그 사본 하나. */
        void seedOneReport() throws SQLException {
            exec("INSERT INTO users (id, role) VALUES (1, 'USER')");
            exec("INSERT INTO report (id, target_type, target_id, reporter_user_id, reason, created_at) "
                    + "VALUES (1, 'community_post', 7, 1, 'spam', NOW(6))");
            exec("INSERT INTO report_snapshot (report_id, role, body, occurred_at) "
                    + "VALUES (1, 'target', '본문', NOW(6))");
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

        List<String> foreignKeys() throws SQLException {
            return query("""
                    SELECT CONCAT(table_name, ' → ', referenced_table_name)
                    FROM information_schema.referential_constraints
                    WHERE constraint_schema = DATABASE()
                      AND table_name IN ('report', 'report_snapshot')
                    ORDER BY table_name, constraint_name
                    """);
        }

        List<String> checks() throws SQLException {
            return query("""
                    SELECT constraint_name FROM information_schema.table_constraints
                    WHERE constraint_schema = DATABASE() AND constraint_type = 'CHECK'
                      AND constraint_name LIKE 'chk_report%'
                    ORDER BY constraint_name
                    """);
        }

        int columnLength(String table, String column) throws SQLException {
            return query("""
                    SELECT character_maximum_length FROM information_schema.columns
                    WHERE table_schema = DATABASE() AND table_name = '%s' AND column_name = '%s'
                    """.formatted(table, column)).stream()
                    .findFirst().map(Integer::parseInt).orElse(-1);
        }

        /**
         * FK 의 삭제 규칙.
         *
         * <p>{@code ON DELETE} 를 안 적은 FK 를 MySQL 은 {@code RESTRICT} 로 동작시키면서
         * {@code information_schema} 에는 <b>{@code NO ACTION} 으로 적는다</b>(실측).
         */
        String deleteRuleOf(String constraint) throws SQLException {
            return query("""
                    SELECT delete_rule FROM information_schema.referential_constraints
                    WHERE constraint_schema = DATABASE() AND constraint_name = '%s'
                    """.formatted(constraint)).stream().findFirst().orElse("(FK 없음)");
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
