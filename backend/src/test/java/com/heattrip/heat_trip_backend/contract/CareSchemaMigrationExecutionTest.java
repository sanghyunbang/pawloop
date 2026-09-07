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
 * {@code 08_care_log.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — 이슈 #76.
 *
 * <h2>왜 필요한가</h2>
 * <p>{@code mysql/init/01_schema.sql} 은 <b>빈 DB</b> 를 세우는 파일이라 이미 돌고 있는 운영
 * DB 에는 실행하지 않는다. 그래서 살아 있는 DB 에 {@code care_log}·{@code walk_note} 를 넣는
 * 경로는 {@code post-start/08} 하나뿐이고, prod 는 {@code ddl-auto=validate} 라 이 스크립트가
 * 틀리면 <b>앱이 부팅에 실패한다.</b> {@code FamilyGroupSchemaMigrationExecutionTest}(#75)가
 * 07 에 대해 하는 일을 08 에 대해 한다.
 *
 * <p>08 은 07 과 다른 것을 한 가지 더 본다 — <b>FK 가 실제로 걸렸는지</b>다. 07 의 표는 FK 가
 * 0개인 것이 요점이었지만 여기는 chat 경계 밖이라 FK 를 정상적으로 건다. 그리고
 * {@code ddl-auto=validate} 도 {@code SchemaDdlDriftTest} 도 <b>FK 를 보지 않으므로</b>,
 * 여기서 안 보면 아무도 안 알려준다.
 *
 * <p>스프링을 띄우지 않는다 — 필요한 것이 <b>그 표가 아직 없는 DB</b> 라서다. 공유 컨테이너
 * 안에 테스트마다 별도 데이터베이스를 만든다. 컨텍스트를 하나도 늘리지 않는다(#21).
 */
class CareSchemaMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/08_care_log.sql";
    private static final String PARENTS = "mysql/post-start/07_family_group.sql";
    private static final String RUNBOOK = "mysql/README.md";

    /** 데이터베이스 이름 충돌을 피하기 위한 카운터. 컨테이너 하나를 여러 테스트가 공유한다. */
    private static int dbCounter = 0;

    // ─────────────────────────── 테스트 ───────────────────────────

    @Test
    @DisplayName("빈 DB(부모 표만 있는)에 돌리면 두 표가 생기고 FK 넷이 걸린다")
    void migration_createsBothTablesWithTheirForeignKeys() throws Exception {
        try (Fixture db = fixture()) {
            db.createParents();
            db.runMigration();

            assertThat(db.tables()).contains("care_log", "walk_note");
            assertThat(db.columns("care_log"))
                    .as("이슈가 정한 컬럼 여덟이다. title·value·photo 는 M4 이고 지금 넣지 않는다")
                    .containsExactly("created_at", "dog_id", "done_by", "group_id", "id",
                            "memo", "occurred_at", "type");
            assertThat(db.columns("walk_note"))
                    .as("그룹당 한 장이라 created_at 이 아니라 updated_by·updated_at 이다")
                    .containsExactly("body", "group_id", "id", "updated_at", "updated_by");

            assertThat(db.foreignKeys())
                    .as("""
                            여기는 chat 경계 밖이라 FK 를 정상적으로 건다 — 걸지 않으면 그룹을 지운 뒤 \
                            아무도 못 보는 행이 남고, 탈퇴한 계정의 기록이 이름 없이 떠돈다.
                            ddl-auto=validate 도 SchemaDdlDriftTest 도 FK 를 안 본다. 여기서 안 보면 \
                            아무도 안 알려준다.""")
                    .containsExactlyInAnyOrder(
                            "care_log → family_group",
                            "care_log → users",
                            "walk_note → family_group",
                            "walk_note → users");
        }
    }

    @Test
    @DisplayName("08 은 care_log.dog_id 를 nullable 로만 만들고 dog 로 가는 FK 는 걸지 않는다 — 그건 22 가 건다")
    void dogId_isNullableAndUnreferenced() throws Exception {
        try (Fixture db = fixture()) {
            db.createParents();
            db.runMigration();

            assertThat(db.query("""
                    SELECT is_nullable FROM information_schema.columns
                    WHERE table_schema = DATABASE() AND table_name = 'care_log'
                      AND column_name = 'dog_id'
                    """))
                    .as("""
                            NOT NULL 로 두면 이 앱은 이 표에 한 행도 못 넣는다 — 쓰기 경로가 아직 \
                            dogId 를 안 받아서 값이 항상 NULL 이기 때문이다(#154 · 받는 날의 전제는 \
                            #209 Dogs-high-3). 22 의 SET NULL FK 도 NULL 허용 컬럼에만 걸 수 있다.""")
                    .containsExactly("YES");

            assertThat(db.query("""
                    SELECT table_name FROM information_schema.referential_constraints
                    WHERE constraint_schema = DATABASE() AND referenced_table_name = 'dog'
                    """))
                    .as("""
                            08 은 dog FK 를 걸지 않는다 — CareLog 가 스칼라 Long 이던 때 Hibernate 가 \
                            안 만들던 제약이었고, #154 가 매핑을 바꾼 뒤 22_care_log_dog_fk.sql 이 \
                            건다(CareLogDogFkMigrationExecutionTest). 08 혼자 돌린 DB 에 FK 가 \
                            생기면 22 와 겹친다.""")
                    .isEmpty();
        }
    }

    @Test
    @DisplayName("users 로 가는 FK 둘은 ON DELETE SET NULL 이다 — 탈퇴가 가족 기록을 지우지 않는다")
    void theTwoUserForeignKeys_setNullInsteadOfCascading() throws Exception {
        try (Fixture db = fixture()) {
            db.createParents();
            db.runMigration();

            assertThat(db.deleteRuleOf("fk_carelog_doneby"))
                    .as("""
                            CASCADE 면 엄마가 탈퇴하는 순간 '오늘 엄마가 산책을 다녀왔다' 가 아빠 \
                            화면에서도 사라진다 — 이 표가 막으려던 산책 누락이 그 자리에서 생긴다.""")
                    .isEqualTo("SET NULL");
            assertThat(db.deleteRuleOf("fk_walknote_updatedby"))
                    .as("""
                            walk_note 는 가족 전원이 보는 안전 메모다. '마지막으로 고친 사람' 이라는 \
                            메타데이터 하나 때문에 그룹 소유 문서를 지우면, 남은 가족의 화면은 한 번도 \
                            안 쓴 그룹과 구별되지 않는다.""")
                    .isEqualTo("SET NULL");

            assertThat(db.query("""
                    SELECT CONCAT(table_name, '.', column_name)
                    FROM information_schema.columns
                    WHERE table_schema = DATABASE() AND is_nullable = 'NO'
                      AND ((table_name = 'care_log'  AND column_name = 'done_by')
                        OR (table_name = 'walk_note' AND column_name = 'updated_by'))
                    """))
                    .as("SET NULL 은 NULL 허용 컬럼에만 걸 수 있다 — 둘은 함께 움직인다")
                    .isEmpty();
        }
    }

    @Test
    @DisplayName("옛 CASCADE 모양으로 이미 만들어진 표는 이 스크립트가 SET NULL 로 고친다")
    void anExistingCascadeShape_isConvertedInPlace() throws Exception {
        try (Fixture db = fixture()) {
            db.createParents();
            // 2026-08 이전의 08 이 만들던 모양 그대로다.
            db.exec("""
                    CREATE TABLE walk_note (
                        id         BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
                        group_id   BIGINT       NOT NULL,
                        body       VARCHAR(500) NOT NULL,
                        updated_by BIGINT       NOT NULL,
                        updated_at DATETIME(6)  NOT NULL,
                        UNIQUE KEY uq_walknote_group (group_id),
                        KEY fk_walknote_updatedby (updated_by),
                        CONSTRAINT fk_walknote_group FOREIGN KEY (group_id)
                          REFERENCES family_group (id) ON DELETE CASCADE,
                        CONSTRAINT fk_walknote_updatedby FOREIGN KEY (updated_by)
                          REFERENCES users (id) ON DELETE CASCADE
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);

            db.exec("INSERT INTO family_group (id, name, created_at) VALUES (1, '가족', NOW(6))");
            db.exec("INSERT INTO users (id, role) VALUES (1, 'ROLE_USER')");
            db.exec("INSERT INTO walk_note (group_id, body, updated_by, updated_at) "
                    + "VALUES (1, '계단 피하기', 1, NOW(6))");

            db.runMigration();

            assertThat(db.deleteRuleOf("fk_walknote_updatedby"))
                    .as("""
                            CREATE TABLE IF NOT EXISTS 는 이미 있는 표를 고치지 않는다. 그래서 이 \
                            스크립트를 CASCADE 시절에 한 번 돌린 DB 는 §B 없이는 영원히 CASCADE 로 \
                            남는다 — 그 DB 에서는 탈퇴 한 번이 가족의 메모를 지운다.""")
                    .isEqualTo("SET NULL");

            db.exec("DELETE FROM users WHERE id = 1");

            assertThat(db.query("SELECT body FROM walk_note"))
                    .as("고친 뒤에는 사람이 사라져도 메모가 남는다 — 이게 이 ALTER 가 실제로 사는 값이다")
                    .containsExactly("계단 피하기");
            assertThat(db.query("SELECT IFNULL(updated_by, 'NULL') FROM walk_note"))
                    .as("이름만 잃는다. 응답에서는 '알 수 없음' 으로 나간다(CareDoerResponse.WITHDRAWN)")
                    .containsExactly("NULL");
        }
    }

    @Test
    @DisplayName("walk_note 는 그룹당 한 장이다 — UNIQUE(group_id) 가 두 번째 행을 거절한다")
    void walkNote_isOneSheetPerGroupAndTheDatabaseEnforcesIt() throws Exception {
        try (Fixture db = fixture()) {
            db.createParents();
            db.runMigration();

            db.exec("INSERT INTO family_group (id, name, created_at) VALUES (1, '가족', NOW(6))");
            db.exec("INSERT INTO users (id, role) VALUES (1, 'ROLE_USER')");
            db.exec("INSERT INTO walk_note (group_id, body, updated_by, updated_at) "
                    + "VALUES (1, '첫 장', 1, NOW(6))");

            assertThatThrownBy(() -> db.exec(
                    "INSERT INTO walk_note (group_id, body, updated_by, updated_at) "
                            + "VALUES (1, '두 번째 장', 1, NOW(6))"))
                    .as("""
                            '있으면 고치고 없으면 만든다' 는 확인-후-쓰기라 정확히 동시에 오는 두 \
                            요청이 둘 다 없다고 볼 수 있다. 그때 두 번째를 거절하는 것은 이 제약이다 \
                            (📌 #86 원칙 5 — 마지막 방어선은 DB).""")
                    .isInstanceOf(SQLException.class);
        }
    }

    @Test
    @DisplayName("CHECK 제약이 계약에 없는 케어 종류를 거절한다 — 애플리케이션 검증을 지나쳐도")
    void anUnknownCareType_isRejectedByTheDatabase() throws Exception {
        try (Fixture db = fixture()) {
            db.createParents();
            db.runMigration();

            db.exec("INSERT INTO users (id, role) VALUES (1, 'ROLE_USER')");

            assertThatThrownBy(() -> db.exec(
                    "INSERT INTO care_log (type, done_by, occurred_at, created_at) "
                            + "VALUES ('grooming', 1, NOW(6), NOW(6))"))
                    .as("""
                            CareType 의 목록이 계약이고, 그 계약을 DB 가 마지막으로 받친다. \
                            손으로 INSERT 하는 사람이나 M4 의 새 코드가 종류를 늘릴 때 여기가 먼저 \
                            막고, 그러면 계약·CHECK·enum 셋을 함께 넓히게 된다 — #340 의 poop·pee 가\
                            29_care_type_poop.sql 로 간 이유다. 08 은 다섯 그대로 둔다.""")
                    .isInstanceOf(SQLException.class);
        }
    }

    @Test
    @DisplayName("두 번 돌려도 성공한다 — 재실행이 안전하다")
    void migration_isIdempotentAgainstRealMySql() throws Exception {
        try (Fixture db = fixture()) {
            db.createParents();
            db.runMigration();
            db.runMigration();   // ERROR 1050(표 중복)이 나면 실패한다

            assertThat(db.tables()).contains("care_log", "walk_note");
        }
    }

    @Test
    @DisplayName("부모 표가 없으면 아무것도 만들지 않고 중단한다 — errno 150 대신 사람 말로")
    void withoutTheParentTables_itAbortsBeforeCreatingAnything() throws Exception {
        try (Fixture db = fixture()) {
            assertThatThrownBy(db::runMigration)
                    .as("""
                            07 을 건너뛰고 08 을 돌리는 것이 실제로 일어나는 실수다. FK 실패의 기본 \
                            메시지(errno 150)는 무엇이 없는지 안 알려준다.""")
                    .isInstanceOf(SQLException.class);

            assertThat(db.tables())
                    .as("중단은 '아무것도 안 바뀐 채로' 여야 한다 — 반쯤 만들어진 스키마가 더 나쁘다")
                    .doesNotContain("care_log", "walk_note");
        }
    }

    @Test
    @DisplayName("옛 계획대로 dog_id NOT NULL 인 care_log 가 있으면 중단한다")
    void aLegacyCareLogWithNotNullDogId_aborts() throws Exception {
        try (Fixture db = fixture()) {
            db.createParents();
            // docs/03-database/schema.md §17 이 오래 적어 온 계획 모양이다.
            db.exec("""
                    CREATE TABLE care_log (
                        id      BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
                        dog_id  BIGINT NOT NULL,
                        done_by BIGINT NOT NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);

            assertThatThrownBy(db::runMigration)
                    .as("""
                            CREATE TABLE IF NOT EXISTS 는 이미 있는 표를 고치지 않는다. 이 관문이 \
                            없으면 스크립트가 조용히 성공하고, 그 표에는 이 앱이 한 행도 못 넣는다 — \
                            dog_id 를 채울 값이 없기 때문이다.""")
                    .isInstanceOf(SQLException.class);
        }
    }

    @Test
    @DisplayName("옛 목록 모양(created_at)의 walk_note 가 있으면 중단한다 — 지금은 그룹당 한 장이다")
    void aLegacyListShapedWalkNote_aborts() throws Exception {
        try (Fixture db = fixture()) {
            db.createParents();
            db.exec("""
                    CREATE TABLE walk_note (
                        id         BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
                        group_id   BIGINT       NOT NULL,
                        body       VARCHAR(500) NOT NULL,
                        created_at DATETIME(6)  NOT NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);

            assertThatThrownBy(db::runMigration)
                    .as("""
                            그 모양에는 updated_by 가 없다 — '누가 고쳤는지' 를 보여 줄 수 없고, \
                            엔티티가 요구하는 컬럼이 없어 prod 부팅(validate)이 실패한다.""")
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
                .contains("post-start\\08_care_log.sql");
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
            synchronized (CareSchemaMigrationExecutionTest.class) {
                name = "care_mig_test_" + (++dbCounter);
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
         * 부모 표 둘을 세운다.
         *
         * <p>{@code family_group} 은 <b>저장소의 07 스크립트를 그대로</b> 돌린다 — 베껴 쓰면
         * 07 이 깨져도 여기는 초록불이다. {@code users} 는 컬럼이 20개가 넘고 이 테스트가 쓰는
         * 것은 {@code id} 뿐이라 최소 모양으로 만든다(정본은 {@code mysql/init/01_schema.sql}).
         */
        void createParents() throws Exception {
            runScript(PARENTS);
            exec("""
                    CREATE TABLE users (
                        id   BIGINT      NOT NULL AUTO_INCREMENT PRIMARY KEY,
                        role VARCHAR(20) NOT NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
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

        /** {@code care_log}·{@code walk_note} 가 거는 FK 를 "자식 → 부모" 로. */
        List<String> foreignKeys() throws SQLException {
            return query("""
                    SELECT CONCAT(table_name, ' → ', referenced_table_name)
                    FROM information_schema.referential_constraints
                    WHERE constraint_schema = DATABASE()
                      AND table_name IN ('care_log', 'walk_note')
                    ORDER BY table_name, constraint_name
                    """);
        }

        /** 그 FK 의 삭제 규칙({@code CASCADE}·{@code SET NULL}·{@code NO ACTION}). */
        String deleteRuleOf(String constraint) throws SQLException {
            return query("""
                    SELECT delete_rule FROM information_schema.referential_constraints
                    WHERE constraint_schema = DATABASE() AND constraint_name = '%s'
                    """.formatted(constraint)).stream().findFirst().orElse("(FK 없음)");
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
