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
 * {@code 14_community.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — 이슈 #169, ADR-0016.
 *
 * <h2>왜 필요한가</h2>
 * <p>{@code mysql/init/01_schema.sql} 은 <b>빈 DB</b> 를 세우는 파일이라 이미 돌고 있는 운영
 * DB 에는 실행하지 않는다. 살아 있는 DB 에 {@code post}·{@code comment}·{@code reaction} 을
 * 넣는 경로는 {@code post-start/14} 하나뿐이고, prod 는 {@code ddl-auto=validate} 라 이
 * 스크립트가 틀리면 <b>앱이 부팅에 실패한다.</b>
 *
 * <p>{@code SchemaDdlDriftTest} 는 <b>빈 DB 에 정본을 적용한 결과</b>를 본다. 이 테스트는
 * <b>운영 DB 에 마이그레이션을 적용한 결과</b>를 본다 — 둘이 같아야 하는데 확인하는 곳이
 * 다르다. 그리고 둘 다 <b>FK 삭제 규칙과 UNIQUE 를 보지 않으므로</b>, 여기서 안 보면
 * 아무도 안 알려준다.
 *
 * <p>스프링을 띄우지 않는다 — 필요한 것이 <b>그 표가 아직 없는 DB</b> 라서다. 공유 컨테이너
 * 안에 테스트마다 별도 데이터베이스를 만든다. 컨텍스트를 하나도 늘리지 않는다(#21).
 */
class CommunitySchemaMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/14_community.sql";
    private static final String RUNBOOK = "mysql/README.md";

    /** 데이터베이스 이름 충돌을 피하기 위한 카운터. 컨테이너 하나를 여러 테스트가 공유한다. */
    private static int dbCounter = 0;

    // ─────────────────────────── 테스트 ───────────────────────────

    @Test
    @DisplayName("빈 DB(users 만 있는)에 돌리면 표 셋이 생기고 FK 다섯이 걸린다")
    void migration_createsThreeTablesWithTheirForeignKeys() throws Exception {
        try (Fixture db = fixture()) {
            db.createParents();
            db.runMigration();

            assertThat(db.tables())
                    .as("표 셋이 다 서야 한다 — 하나라도 빠지면 ddl-auto=validate 가 부팅을 막는다")
                    .contains("post", "comment", "reaction");

            assertThat(db.foreignKeys())
                    .as("""
                            FK 다섯이다. comment·reaction 이 각각 post 와 users 로, post 가 users 로 간다. \
                            ddl-auto=validate 도 SchemaDdlDriftTest 도 FK 를 보지 않으므로 \
                            여기서 안 보면 빠진 채로 배포된다.""")
                    .containsExactlyInAnyOrder(
                            "comment → post", "comment → users",
                            "post → users",
                            "reaction → post", "reaction → users");
        }
    }

    @Test
    @DisplayName("reaction 의 UNIQUE 는 세 컬럼이다 — 사용자당 글마다 여러 반응이다")
    void reaction_allowsSeveralTypesFromTheSamePerson() throws Exception {
        try (Fixture db = fixture()) {
            db.createParents();
            db.runMigration();
            db.seedOnePost();

            db.exec("INSERT INTO reaction (post_id, user_id, type, created_at) "
                    + "VALUES (1, 1, 'help', NOW(6))");
            db.exec("INSERT INTO reaction (post_id, user_id, type, created_at) "
                    + "VALUES (1, 1, 'cute', NOW(6))");

            assertThat(db.count("reaction"))
                    .as("""
                            도움돼요·귀여워요·공감은 서로 배타적인 개념이 아니다 — 한 글이 도움도 되고 \
                            귀엽기도 하다(ADR-0016 결정 2). UNIQUE 를 (post_id, user_id) 로 좁히면 \
                            여기서 두 번째가 거절되고 반응이 라디오가 된다.""")
                    .isEqualTo(2);
        }
    }

    @Test
    @DisplayName("같은 반응을 두 번 넣으면 UNIQUE 가 거절한다 — 멱등한 POST 가 이것을 딛는다")
    void reaction_rejectsTheSameTypeTwice() throws Exception {
        try (Fixture db = fixture()) {
            db.createParents();
            db.runMigration();
            db.seedOnePost();

            db.exec("INSERT INTO reaction (post_id, user_id, type, created_at) "
                    + "VALUES (1, 1, 'help', NOW(6))");

            assertThatThrownBy(() -> db.exec(
                    "INSERT INTO reaction (post_id, user_id, type, created_at) "
                            + "VALUES (1, 1, 'help', NOW(6))"))
                    .as("""
                            POST .../reactions/{type} 는 이미 눌렀어도 200 이다. 그 멱등이 \
                            애플리케이션의 선조회가 아니라 이 제약 위에 서야 동시 요청에도 안 깨진다.""")
                    .hasMessageContaining("uq_reaction");
        }
    }

    @Test
    @DisplayName("글이 사라지면 댓글과 반응도 사라진다 — 부모 없는 행을 남기지 않는다")
    void deletingAPost_takesItsCommentsAndReactions() throws Exception {
        try (Fixture db = fixture()) {
            db.createParents();
            db.runMigration();
            db.seedOnePost();
            db.exec("INSERT INTO comment (post_id, user_id, body, created_at) "
                    + "VALUES (1, 1, '댓글', NOW(6))");
            db.exec("INSERT INTO reaction (post_id, user_id, type, created_at) "
                    + "VALUES (1, 1, 'help', NOW(6))");

            db.exec("DELETE FROM post WHERE id = 1");

            assertThat(db.count("comment"))
                    .as("""
                            남으면 어느 목록에도 안 뜨면서 자리만 차지한다. 나중에 세면 댓글 수가 \
                            맞지 않고 왜 안 맞는지 아무도 모른다.""")
                    .isZero();
            assertThat(db.count("reaction")).isZero();
        }
    }

    @Test
    @DisplayName("users 로 가는 FK 셋은 CASCADE 가 아니다 — 탈퇴가 남의 글에서 대화를 끊지 않는다")
    void userForeignKeys_doNotCascade() throws Exception {
        try (Fixture db = fixture()) {
            db.createParents();
            db.runMigration();

            for (String fk : List.of("fk_post_user", "fk_comment_user", "fk_reaction_user")) {
                assertThat(db.deleteRuleOf(fk))
                        .as("""
                                %s 가 CASCADE 면 탈퇴 한 번에 그 사람이 쓴 글이 전부 사라지고, \
                                거기 달린 남의 댓글도 함께 사라진다. 탈퇴한 사람을 어떻게 보여 줄지는 \
                                표시 계층의 문제이지 저장 계층의 문제가 아니다.""", fk)
                        .isEqualTo("NO ACTION");
            }
        }
    }

    @Test
    @DisplayName("두 번 돌려도 성공한다 — 재실행이 안전하다")
    void migration_isIdempotent() throws Exception {
        try (Fixture db = fixture()) {
            db.createParents();
            db.runMigration();
            db.runMigration();

            assertThat(db.tables()).contains("post", "comment", "reaction");
        }
    }

    @Test
    @DisplayName("users 가 없으면 아무것도 만들지 않고 중단한다 — errno 150 대신 사람 말로")
    void migration_abortsWithoutTheParentTable() throws Exception {
        try (Fixture db = fixture()) {
            assertThatThrownBy(db::runMigration)
                    .as("사전 점검이 없으면 FK 생성이 errno 150 으로 죽는데, 그 메시지로는 "
                            + "무엇을 먼저 돌려야 하는지 알 수 없다")
                    .hasMessageContaining("04_users_social_account_model.sql");

            assertThat(db.tables())
                    .as("사전 점검에서 걸리면 스키마는 한 글자도 바뀌지 않아야 한다")
                    .doesNotContain("post", "comment", "reaction");
        }
    }

    @Test
    @DisplayName("reaction 이 두 컬럼 UNIQUE 로 이미 서 있으면 중단한다 — 사용자당 하나 모양이다")
    void migration_abortsOnASingleReactionShape() throws Exception {
        try (Fixture db = fixture()) {
            db.createParents();
            // ADR-0016 이전 설계(단수 반응)로 만들어진 표. 그대로 통과시키면 앱이 두 번째
            // 반응을 눌렀을 때 조용히 실패한다.
            db.exec("""
                    CREATE TABLE reaction (
                        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
                        post_id BIGINT NOT NULL,
                        user_id BIGINT NOT NULL,
                        type VARCHAR(20) NOT NULL,
                        created_at DATETIME(6) NOT NULL,
                        CONSTRAINT uq_reaction UNIQUE (post_id, user_id)
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);

            assertThatThrownBy(db::runMigration)
                    .as("ADR-0016 결정 2 와 반대 모양이다 — 손으로 확인해야 한다")
                    .hasMessageContaining("uq_reaction");
        }
    }

    @Test
    @DisplayName("중단 메시지가 한글 그대로 읽힌다 — SET NAMES 가 없으면 ERROR 1366 만 남는다")
    void abortMessage_survivesTheClientCharset() throws Exception {
        try (Fixture db = fixture()) {
            // 클라이언트 문자셋을 일부러 한글을 못 담는 것으로 바꾼다. 윈도우 mysql 클라이언트의
            // 기본이 euckr 라 실제로 이 상황이 난다(실측 2026-09-02).
            //
            // 스크립트가 SET NAMES utf8mb4 로 스스로 고정하지 않으면, 중단이 걸리는 순간
            // 정작 이유는 안 보이고 ERROR 1366 (Incorrect string value) 만 남는다 —
            // "왜 멈췄나" 를 알려 주려고 쓴 메시지가 "왜 멈췄는지 모르게" 만든다.
            db.exec("SET NAMES latin1");

            assertThatThrownBy(db::runMigration)
                    .as("인코딩 오류가 아니라 사람이 읽을 수 있는 중단 사유가 나와야 한다")
                    .hasMessageContaining("users 표가 없다");
        }
    }

    @Test
    @DisplayName("런북(mysql/README.md)이 이 파일의 실행 커맨드를 담고 있다")
    void runbook_listsThisScript() throws Exception {
        String runbook = Files.readString(
                TestProjectPaths.requireFile(RUNBOOK), StandardCharsets.UTF_8);

        assertThat(runbook)
                .as("""
                        런북에 없는 스크립트는 새 환경을 세울 때 통째로 빠진다 — \
                        13_walk_path_t.sql 이 실제로 그렇게 빠져 있었다(#169 에서 등재).""")
                .contains("14_community.sql");
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
            synchronized (CommunitySchemaMigrationExecutionTest.class) {
                name = "community_mig_test_" + (++dbCounter);
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
         * 부모 표를 세운다.
         *
         * <p>{@code users} 는 컬럼이 20개가 넘고 이 테스트가 쓰는 것은 {@code id} 뿐이라 최소
         * 모양으로 만든다(정본은 {@code mysql/init/01_schema.sql}).
         */
        void createParents() throws Exception {
            exec("""
                    CREATE TABLE users (
                        id   BIGINT      NOT NULL AUTO_INCREMENT PRIMARY KEY,
                        role VARCHAR(20) NOT NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
        }

        /** 자식 표를 시험할 최소 데이터 — 사용자 하나와 글 하나. */
        void seedOnePost() throws SQLException {
            exec("INSERT INTO users (id, role) VALUES (1, 'USER')");
            exec("INSERT INTO post (id, user_id, board, title, body, created_at) "
                    + "VALUES (1, 1, 'free', '제목', '본문', NOW(6))");
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

        /** 커뮤니티 표 셋이 거는 FK 를 "자식 → 부모" 로. */
        List<String> foreignKeys() throws SQLException {
            return query("""
                    SELECT CONCAT(table_name, ' → ', referenced_table_name)
                    FROM information_schema.referential_constraints
                    WHERE constraint_schema = DATABASE()
                      AND table_name IN ('post', 'comment', 'reaction')
                    ORDER BY table_name, constraint_name
                    """);
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
