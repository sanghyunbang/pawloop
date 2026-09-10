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
 * {@code 38_crew_favor.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — #417.
 *
 * <h2>여기서 가장 중요한 것</h2>
 * <p><b>FK 넷의 삭제 규칙이 서로 다른가.</b> {@code crew_id} 만 {@code CASCADE} 이고 사람·아이
 * 셋은 {@code SET NULL} 이다. 뒤엣것이 {@code CASCADE} 로 잘못 서면 <b>한 사람이 탈퇴할 때
 * 남의 약속이 함께 사라진다</b> — 오류도 안 나고, 사라진 뒤에는 무엇이 있었는지 아무도 모른다.
 *
 * <p>그다음이 CHECK 둘이다. {@code Hibernate} 의 {@code update} 도 prod 의 {@code validate}
 * 도 CHECK 는 안 보므로, 여기서 안 재면 아무 데서도 안 잡힌다.
 *
 * <p>스프링을 띄우지 않는다(#21).
 */
class CrewFavorMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/38_crew_favor.sql";

    private static int dbCounter = 0;

    @Test
    @DisplayName("표가 생기고 CHECK 둘과 목록 인덱스가 함께 선다")
    void createsTheTableWithItsChecksAndIndex() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites();

            db.runMigration();

            assertThat(db.query("SELECT column_name FROM information_schema.columns "
                    + "WHERE table_schema = DATABASE() AND table_name = 'crew_favor' "
                    + "ORDER BY column_name"))
                    .containsExactly("asked_by", "created_at", "crew_id", "dog_id", "id",
                            "note", "on_date", "schedule_id", "slot", "status", "taken_by",
                            "updated_at");

            assertThat(db.query("SELECT constraint_name FROM information_schema.table_constraints "
                    + "WHERE table_schema = DATABASE() AND table_name = 'crew_favor' "
                    + "AND constraint_type = 'CHECK' ORDER BY constraint_name"))
                    .as("""
                            Hibernate 의 update 도 prod 의 validate 도 CHECK 는 안 본다 — \
                            여기서 안 재면 아무 데서도 안 잡힌다.""")
                    .containsExactly("ck_crew_favor_slot", "ck_crew_favor_status");

            assertThat(db.query("SELECT column_name FROM information_schema.statistics "
                    + "WHERE table_schema = DATABASE() AND table_name = 'crew_favor' "
                    + "AND index_name = 'idx_crew_favor_crew' ORDER BY seq_in_index"))
                    .containsExactly("crew_id", "on_date");
        }
    }

    @Test
    @DisplayName("크루를 지우면 부탁이 함께 사라지고, 사람이 사라져도 부탁은 남는다")
    void theCrewCascadesButPeopleDoNot() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites();
            db.runMigration();

            db.exec("INSERT INTO crew (id, name, visibility, capacity, created_at) "
                    + "VALUES (1, '성수 저녁 산책', 'public', 6, NOW(6))");
            db.exec("INSERT INTO users (id, email) VALUES (1, 'a@example.com'), (2, 'b@example.com')");
            db.exec("INSERT INTO dog (id, name) VALUES (1, '보리')");
            db.exec("INSERT INTO crew_favor "
                    + "(id, crew_id, asked_by, taken_by, dog_id, on_date, slot, status, created_at) "
                    + "VALUES (1, 1, 1, 2, 1, '2026-12-24', 'afternoon', 'taken', NOW(6))");

            db.exec("DELETE FROM users WHERE id = 2");
            assertThat(db.query("SELECT IFNULL(taken_by, '(null)') FROM crew_favor WHERE id = 1"))
                    .as("""
                            맡은 사람이 탈퇴했다고 약속까지 지우면, 부탁한 사람은 그 일이 \
                            있었다는 사실조차 모르게 된다.""")
                    .containsExactly("(null)");

            db.exec("DELETE FROM dog WHERE id = 1");
            assertThat(db.query("SELECT COUNT(*) FROM crew_favor")).containsExactly("1");

            db.exec("DELETE FROM crew WHERE id = 1");
            assertThat(db.query("SELECT COUNT(*) FROM crew_favor"))
                    .as("크루가 없는 부탁은 어느 모임의 약속인지 아무도 모른다")
                    .containsExactly("0");
        }
    }

    @Test
    @DisplayName("모르는 시간대와 모르는 상태는 CHECK 가 막는다")
    void rejectsUnknownVocabulary() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites();
            db.runMigration();
            db.exec("INSERT INTO crew (id, name, visibility, capacity, created_at) "
                    + "VALUES (1, '성수 저녁 산책', 'public', 6, NOW(6))");

            assertThatThrownBy(() -> db.exec(insert("'dawn'", "'open'")))
                    .as("아무 문자열이나 시간대가 되면 화면이 그것을 못 그린다")
                    .isInstanceOf(SQLException.class);

            assertThatThrownBy(() -> db.exec(insert("'afternoon'", "'done'")))
                    .as("""
                            끝났는지는 이 표가 모른다 — 그것은 일정의 완료 표시가 말한다. \
                            상태를 하나 더 두면 같은 사실이 두 곳에 산다.""")
                    .isInstanceOf(SQLException.class);

            db.exec(insert("'afternoon'", "'open'"));
            db.exec(insert("'morning'", "'taken'"));
            assertThat(db.query("SELECT COUNT(*) FROM crew_favor")).containsExactly("2");
        }
    }

    @Test
    @DisplayName("두 번 돌려도 그대로다 — 멱등")
    void secondRunIsIdempotent() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites();
            db.runMigration();
            db.exec("INSERT INTO crew (id, name, visibility, capacity, created_at) "
                    + "VALUES (1, '성수 저녁 산책', 'public', 6, NOW(6))");
            db.exec(insert("'evening'", "'open'"));

            db.runMigration();

            assertThat(db.query("SELECT slot FROM crew_favor")).containsExactly("evening");
        }
    }

    @Test
    @DisplayName("crew 가 없으면 멈춘다 — 37 을 먼저 돌려야 한다")
    void abortsWithoutTheCrewTable() throws Exception {
        try (Fixture db = fixture()) {
            db.createUsersAndDog();

            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("37_crew.sql");
        }
    }

    @Test
    @DisplayName("Hibernate 가 CHECK 없이 만들어 둔 표는 사후 검증이 멈춰 세운다")
    void refusesToPassOverATableThatHibernateMadeWithoutChecks() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites();
            // dev 에서 앱을 먼저 띄운 모양 — ddl-auto=update 가 만든 표에는 CHECK 가 없다.
            db.exec("""
                    CREATE TABLE crew_favor (
                      on_date date NOT NULL,
                      asked_by bigint DEFAULT NULL,
                      created_at datetime(6) NOT NULL,
                      crew_id bigint NOT NULL,
                      dog_id bigint DEFAULT NULL,
                      id bigint NOT NULL AUTO_INCREMENT,
                      schedule_id bigint DEFAULT NULL,
                      taken_by bigint DEFAULT NULL,
                      updated_at datetime(6) DEFAULT NULL,
                      slot varchar(10) NOT NULL,
                      status varchar(10) NOT NULL,
                      note varchar(200) DEFAULT NULL,
                      PRIMARY KEY (id)
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);

            assertThatThrownBy(db::runMigration)
                    .as("""
                            IF NOT EXISTS 로 조용히 지나가면 CHECK 도 FK 도 없는 표가 남는다. \
                            그 상태를 사람이 알아채는 곳이 여기밖에 없다.""")
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("사후 검증");
        }
    }

    // ─────────────────────────── 지그 ─────────────────

    private static String insert(String slot, String status) {
        return "INSERT INTO crew_favor (crew_id, on_date, slot, status, created_at) "
                + "VALUES (1, '2026-12-24', " + slot + ", " + status + ", NOW(6))";
    }

    private static Fixture fixture() throws SQLException {
        return new Fixture();
    }

    private static final class Fixture implements AutoCloseable {

        private final String name;
        private final Connection connection;

        Fixture() throws SQLException {
            MySQLContainer<?> mysql = MySqlTestContainer.instance();
            synchronized (CrewFavorMigrationExecutionTest.class) {
                name = "crewfavor_test_" + (++dbCounter);
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

        /** FK 가 걸리는 표 셋의 최소 형태. */
        void createPrerequisites() throws SQLException {
            createUsersAndDog();
            exec("""
                    CREATE TABLE crew (
                      id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
                      name varchar(30) NOT NULL,
                      visibility varchar(10) NOT NULL,
                      capacity int NOT NULL,
                      created_at datetime(6) NOT NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
        }

        void createUsersAndDog() throws SQLException {
            exec("""
                    CREATE TABLE users (
                      id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
                      email varchar(255)
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
            exec("""
                    CREATE TABLE dog (
                      id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
                      name varchar(30) NOT NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
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
