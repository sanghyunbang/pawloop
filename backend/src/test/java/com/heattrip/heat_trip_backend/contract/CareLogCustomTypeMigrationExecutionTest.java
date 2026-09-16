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
 * {@code 51_care_log_custom_type.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — #560.
 *
 * <h2>왜 실행 테스트인가</h2>
 *
 * <p>이 스크립트가 하는 일 중 어느 것도 {@code ddl-auto=validate} 가 전부 보지는 않는다.
 *
 * <ol>
 *   <li><b>{@code type} 이 NULL 을 받는가.</b> 이건 validate 도 보지만, 그때는 이미
 *       <b>부팅이 막힌 뒤</b>다 — 스크립트를 안 돌리고 배포하면 서버가 안 뜬다.</li>
 *   <li><b>직접 만든 항목의 기록이 실제로 들어가는가.</b> 종류 없이 항목만 든 행이다 —
 *       이 한 줄이 들어가는 것이 이 마이그레이션의 존재 이유다.</li>
 *   <li><b>일곱 값 제약을 흘리지 않았는가.</b> 넓히면서 {@code ck_carelog_type} 을 잃으면
 *       오타가 조용히 저장된다.</li>
 *   <li>멱등 — 두 번 돌려도 같은 상태여야 한다.</li>
 * </ol>
 *
 * <p>표는 {@code 50} 이 돈 <b>뒤</b> 모양이다({@code care_item} 있음 · {@code care_log.type} 은
 * 아직 {@code NOT NULL}). 스프링을 띄우지 않는다(#21).
 */
class CareLogCustomTypeMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/51_care_log_custom_type.sql";

    private static int dbCounter = 0;

    @Test
    @DisplayName("type 이 NULL 을 받게 된다 — 안 그러면 새 서버가 아예 안 뜬다")
    void typeBecomesNullable() throws Exception {
        try (Fixture db = new Fixture()) {
            db.createTables(true);
            assertThat(db.nullable("care_log", "type")).isEqualTo("NO");

            db.runMigration();

            assertThat(db.nullable("care_log", "type"))
                    .as("prod 는 validate 라 엔티티가 nullable 인데 컬럼이 NOT NULL 이면 부팅이 막힌다")
                    .isEqualTo("YES");
        }
    }

    @Test
    @DisplayName("직접 만든 항목의 기록이 들어간다 — 종류 없이 항목만으로")
    void aCustomItemLogFits() throws Exception {
        try (Fixture db = new Fixture()) {
            db.createTables(true);
            db.seed();
            db.runMigration();

            db.exec("INSERT INTO care_log (id, group_id, care_item_id, occurred_at, created_at) "
                    + "VALUES (1, 1, 100, NOW(6), NOW(6))");

            assertThat(db.typeOf(1))
                    .as("이 한 줄이 들어가는 것이 이 마이그레이션의 존재 이유다")
                    .isEqualTo("NULL");
        }
    }

    @Test
    @DisplayName("종류도 항목도 없는 행을 DB 는 못 막는다 — 그래서 서버가 막는다는 것을 여기 적어 둔다")
    void anOrphanLogIsNotStoppedByTheDatabase() throws Exception {
        try (Fixture db = new Fixture()) {
            db.createTables(true);
            db.seed();
            db.runMigration();

            // CHECK (type IS NOT NULL OR care_item_id IS NOT NULL) 을 걸려고 했는데 MySQL 이
            // 거절했다 — SET NULL 로 값을 쓰는 FK 가 걸린 컬럼은 CHECK 에서 못 읽는다.
            // 이 단언은 "막힌다" 가 아니라 "안 막힌다" 를 적는다: 사실이 그렇고, 그래서 그
            // 불변식은 CareService.record 가 진다(CareLogByItemIntegrationTest 가 잰다).
            db.exec("INSERT INTO care_log (id, group_id, occurred_at, created_at) "
                    + "VALUES (2, 1, NOW(6), NOW(6))");

            assertThat(db.typeOf(2))
                    .as("MySQL 이 이 CHECK 를 받게 되거나 FK 규칙이 바뀌면 여기가 빨간불이 된다")
                    .isEqualTo("NULL");
            assertThat(db.checkNames("care_log"))
                    .as("ck_carelog_source 가 생겼다면 위 서술이 낡은 것이다 — 제약을 걸고 이 테스트를 뒤집어라")
                    .containsExactly("ck_carelog_type");
        }
    }

    @Test
    @DisplayName("옛 기록은 한 행도 안 바뀐다 — 넓히는 변경이다")
    void theOldRowsAreUntouched() throws Exception {
        try (Fixture db = new Fixture()) {
            db.createTables(true);
            db.seed();
            db.exec("INSERT INTO care_log (id, group_id, type, occurred_at, created_at) "
                    + "VALUES (10, 1, 'meal', NOW(6), NOW(6))");
            db.exec("INSERT INTO care_log (id, group_id, type, occurred_at, created_at) "
                    + "VALUES (11, 1, 'walk', NOW(6), NOW(6))");

            db.runMigration();

            assertThat(db.typeOf(10)).isEqualTo("meal");
            assertThat(db.typeOf(11))
                    .as("산책 트래킹이 남기는 줄이다 — 이게 바뀌면 산책 화면이 통째로 빈다")
                    .isEqualTo("walk");
            assertThat(db.count("care_log")).isEqualTo(2);
        }
    }

    @Test
    @DisplayName("일곱 값 제약을 흘리지 않았다 — 넓히면서 잃으면 오타가 조용히 저장된다")
    void theSevenValueCheckSurvives() throws Exception {
        try (Fixture db = new Fixture()) {
            db.createTables(true);
            db.seed();
            db.runMigration();

            assertThatThrownBy(() -> db.exec(
                    "INSERT INTO care_log (id, group_id, type, occurred_at, created_at) "
                            + "VALUES (20, 1, 'brush', NOW(6), NOW(6))"))
                    .hasMessageContaining("ck_carelog_type");
        }
    }

    @Test
    @DisplayName("두 번 돌려도 같다 — 멱등")
    void isIdempotent() throws Exception {
        try (Fixture db = new Fixture()) {
            db.createTables(true);
            db.seed();
            db.runMigration();
            db.runMigration();

            assertThat(db.nullable("care_log", "type")).isEqualTo("YES");
            assertThat(db.checkNames("care_log")).containsExactly("ck_carelog_type");
        }
    }

    @Test
    @DisplayName("care_item_id 가 없으면 아무것도 바꾸기 전에 멈춘다 — 50 이 먼저다")
    void abortsWhenTheItemColumnIsMissing() throws Exception {
        try (Fixture db = new Fixture()) {
            db.createTables(false);

            assertThatThrownBy(db::runMigration)
                    .hasMessageContaining("50_care_item.sql");

            assertThat(db.nullable("care_log", "type"))
                    .as("멈췄으면 한 글자도 안 바뀌어야 한다")
                    .isEqualTo("NO");
        }
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private static final class Fixture implements AutoCloseable {

        private final String name;
        private final Connection connection;

        Fixture() throws SQLException {
            MySQLContainer<?> mysql = MySqlTestContainer.instance();
            synchronized (CareLogCustomTypeMigrationExecutionTest.class) {
                name = "care_log_custom_test_" + (++dbCounter);
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

        /**
         * {@code 50} 이 돈 뒤의 모양.
         *
         * @param withItemColumn {@code false} 면 {@code care_item_id} 가 없다 — 50 을 안 돌린
         *                       DB 를 흉내 내어 §0 이 멈추는지 본다
         */
        void createTables(boolean withItemColumn) throws SQLException {
            exec("""
                    CREATE TABLE family_group (
                      created_at datetime(6) NOT NULL,
                      id bigint NOT NULL AUTO_INCREMENT,
                      name varchar(50) NOT NULL,
                      PRIMARY KEY (id)
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
            exec("""
                    CREATE TABLE care_item (
                      daily_target int DEFAULT NULL,
                      sort_order int NOT NULL,
                      archived_at datetime(6) DEFAULT NULL,
                      created_at datetime(6) NOT NULL,
                      dog_id bigint DEFAULT NULL,
                      group_id bigint NOT NULL,
                      id bigint NOT NULL AUTO_INCREMENT,
                      system_type varchar(10) DEFAULT NULL,
                      icon varchar(20) NOT NULL,
                      name varchar(20) NOT NULL,
                      PRIMARY KEY (id),
                      UNIQUE KEY uq_careitem_system (group_id, system_type),
                      CONSTRAINT fk_careitem_group FOREIGN KEY (group_id)
                        REFERENCES family_group (id) ON DELETE CASCADE
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
            exec("""
                    CREATE TABLE care_log (
                      created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
                      group_id bigint DEFAULT NULL,
                      %s
                      id bigint NOT NULL AUTO_INCREMENT,
                      occurred_at datetime(6) NOT NULL,
                      type varchar(10) NOT NULL,
                      memo varchar(500) DEFAULT NULL,
                      PRIMARY KEY (id),
                      %s
                      CONSTRAINT ck_carelog_type CHECK (type IN ('water','meal','walk','med','vet','poop','pee')),
                      CONSTRAINT fk_carelog_group FOREIGN KEY (group_id)
                        REFERENCES family_group (id) ON DELETE SET NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """.formatted(
                    withItemColumn ? "care_item_id bigint DEFAULT NULL," : "",
                    withItemColumn
                            ? "CONSTRAINT fk_carelog_item FOREIGN KEY (care_item_id) "
                                    + "REFERENCES care_item (id) ON DELETE SET NULL,"
                            : ""));
        }

        /** 가족 하나(보리네 1)와 그 집의 직접 만든 항목 하나(100 · 양치). */
        void seed() throws SQLException {
            exec("INSERT INTO family_group (id, name, created_at) VALUES (1, '보리네', NOW(6))");
            exec("INSERT INTO care_item (id, group_id, name, icon, sort_order, created_at) "
                    + "VALUES (100, 1, '양치', 'tooth', 7, NOW(6))");
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

        String nullable(String table, String column) throws SQLException {
            return query("SELECT is_nullable FROM information_schema.columns "
                    + "WHERE table_schema = DATABASE() AND table_name = '" + table + "' "
                    + "AND column_name = '" + column + "'").stream()
                    .findFirst().orElse("(없음)");
        }

        String typeOf(long logId) throws SQLException {
            return query("SELECT IFNULL(type, 'NULL') FROM care_log WHERE id = " + logId)
                    .stream().findFirst().orElse("(없음)");
        }

        List<String> checkNames(String table) throws SQLException {
            return query("SELECT tc.constraint_name FROM information_schema.table_constraints tc "
                    + "WHERE tc.constraint_schema = DATABASE() AND tc.table_name = '" + table + "' "
                    + "AND tc.constraint_type = 'CHECK' ORDER BY tc.constraint_name");
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

    /**
     * {@code ;} 로 자른다 — 이 스크립트에는 프로시저 본문이 한 줄짜리라 구분자 전환이 없다.
     * {@code CareItemMigrationExecutionTest} 와 같은 판단이다.
     */
    private static List<String> splitStatements(String sql) {
        String withoutComments = Arrays.stream(sql.split("\\R"))
                .filter(line -> !line.strip().startsWith("--"))
                .collect(Collectors.joining("\n"));
        return Arrays.stream(withoutComments.split(";"))
                .map(String::strip)
                .filter(statement -> !statement.isEmpty())
                .toList();
    }
}
