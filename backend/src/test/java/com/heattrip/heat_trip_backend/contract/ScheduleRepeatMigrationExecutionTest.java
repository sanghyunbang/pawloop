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
 * {@code 36_schedule_repeat.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — #421.
 *
 * <h2>여기서 가장 중요한 것</h2>
 * <p><b>이미 쌓인 일정이 전부 {@code none} 이 되는가.</b> {@code NOT NULL} 컬럼을 더하는
 * 마이그레이션이라 그 값이 안 채워지면 스크립트가 실패하거나, 더 나쁘게는 빈 문자열 같은
 * 값이 들어가 CHECK 를 통과해 버린다.
 *
 * <p>그다음이 <b>DEFAULT 를 떼어 냈는가</b>다. 있는 행을 채우려고 잠깐 빌린 것인데 남겨
 * 두면, 새로 세운 DB(엔티티에서 만든 것)와 마이그레이션한 DB 가 달라진다 —
 * {@code validate} 도 그 차이는 안 잡는다.
 *
 * <p>그리고 <b>지우기 규칙 둘</b>이다. 규칙을 지우면 예외와 옮겨 둔 하루가 함께 사라져야
 * 한다. 안 그러면 무엇의 하루였는지 아무도 모르는 행이 남는다.
 *
 * <p>스프링을 띄우지 않는다(#21).
 */
class ScheduleRepeatMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/36_schedule_repeat.sql";

    private static int dbCounter = 0;

    @Test
    @DisplayName("이미 쌓인 일정이 전부 none 이 되고, DEFAULT 는 안 남는다")
    void backfillsExistingRowsAndDropsTheDefault() throws Exception {
        try (Fixture db = fixture()) {
            db.createScheduleTable();
            db.exec(insert(1, "'2026-10-03'"));
            db.exec(insert(2, "'2026-10-04'"));

            db.runMigration();

            assertThat(db.query("SELECT DISTINCT repeat_kind FROM schedule"))
                    .as("되풀이하지 않던 일정은 전부 none 이다")
                    .containsExactly("none");
            assertThat(db.query("SELECT IFNULL(column_default, '(none)') "
                    + "FROM information_schema.columns WHERE table_schema = DATABASE() "
                    + "AND table_name = 'schedule' AND column_name = 'repeat_kind'"))
                    .as("""
                            DEFAULT 가 남으면 새로 세운 DB 와 갈린다 — 엔티티가 만드는 \
                            컬럼에는 DEFAULT 가 없고, validate 도 그 차이는 안 잡는다.""")
                    .containsExactly("(none)");
        }
    }

    @Test
    @DisplayName("예외 표의 PK 가 (on_date, schedule_id) 다 — Hibernate 가 정한 순서")
    void exceptionTableMatchesTheGeneratedPrimaryKey() throws Exception {
        try (Fixture db = fixture()) {
            db.createScheduleTable();

            db.runMigration();

            assertThat(db.query("SELECT column_name FROM information_schema.statistics "
                    + "WHERE table_schema = DATABASE() AND table_name = 'schedule_exception' "
                    + "AND index_name = 'PRIMARY' ORDER BY seq_in_index"))
                    .as("""
                            반대로 적으면 새로 세운 DB 와 마이그레이션한 DB 의 인덱스가 \
                            갈리고 오류는 안 난다 — walk_dog 이 #343 에서 같은 자리였다.""")
                    .containsExactly("on_date", "schedule_id");
        }
    }

    @Test
    @DisplayName("규칙을 지우면 예외와 옮겨 둔 하루가 함께 사라진다")
    void deletingTheRuleTakesItsExceptionsAndOverrides() throws Exception {
        try (Fixture db = fixture()) {
            db.createScheduleTable();
            db.exec(insert(1, "'2026-10-06'"));
            db.runMigration();
            db.exec("UPDATE schedule SET repeat_kind = 'weekly' WHERE id = 1");
            // 마이그레이션 뒤에 넣는 행이라 repeat_kind 를 직접 준다 — DEFAULT 를 떼어
            // 냈기 때문이다. 그 사실 자체가 위 검사가 재는 것이다.
            db.exec(insertAfter(2, "'2026-10-13'"));
            db.exec("UPDATE schedule SET origin_id = 1 WHERE id = 2");
            db.exec("INSERT INTO schedule_exception (schedule_id, on_date, kind) "
                    + "VALUES (1, '2026-10-13', 'override'), (1, '2026-10-20', 'skip')");

            db.exec("DELETE FROM schedule WHERE id = 1");

            assertThat(db.query("SELECT COUNT(*) FROM schedule_exception"))
                    .as("규칙이 없는 예외는 아무 일도 안 한다")
                    .containsExactly("0");
            assertThat(db.query("SELECT COUNT(*) FROM schedule"))
                    .as("옮겨 둔 하루가 남으면 그것이 무엇의 하루였는지 아무도 모른다")
                    .containsExactly("0");
        }
    }

    @Test
    @DisplayName("모르는 주기와 모르는 예외 종류는 CHECK 가 막는다")
    void rejectsUnknownVocabulary() throws Exception {
        try (Fixture db = fixture()) {
            db.createScheduleTable();
            db.exec(insert(1, "'2026-10-06'"));
            db.runMigration();

            assertThatThrownBy(() ->
                    db.exec("UPDATE schedule SET repeat_kind = 'yearly' WHERE id = 1"))
                    .isInstanceOf(SQLException.class);
            assertThatThrownBy(() -> db.exec("INSERT INTO schedule_exception "
                    + "(schedule_id, on_date, kind) VALUES (1, '2026-10-13', 'moved')"))
                    .isInstanceOf(SQLException.class);
        }
    }

    @Test
    @DisplayName("같은 규칙의 같은 날짜에 예외는 하나뿐이다")
    void oneExceptionPerRuleAndDay() throws Exception {
        try (Fixture db = fixture()) {
            db.createScheduleTable();
            db.exec(insert(1, "'2026-10-06'"));
            db.runMigration();
            db.exec("INSERT INTO schedule_exception (schedule_id, on_date, kind) "
                    + "VALUES (1, '2026-10-13', 'skip')");

            assertThatThrownBy(() -> db.exec("INSERT INTO schedule_exception "
                    + "(schedule_id, on_date, kind) VALUES (1, '2026-10-13', 'override')"))
                    .as("둘이 있으면 펼치기가 그중 무엇을 볼지 정해야 한다")
                    .isInstanceOf(SQLException.class);
        }
    }

    @Test
    @DisplayName("두 번 돌려도 그대로다 — 멱등")
    void secondRunIsIdempotent() throws Exception {
        try (Fixture db = fixture()) {
            db.createScheduleTable();
            db.exec(insert(1, "'2026-10-06'"));
            db.runMigration();
            db.exec("UPDATE schedule SET repeat_kind = 'weekly', repeat_until = '2026-12-31' "
                    + "WHERE id = 1");

            db.runMigration();

            assertThat(db.query("SELECT CONCAT(repeat_kind, '/', repeat_until) FROM schedule"))
                    .as("두 번째 실행이 사람이 정한 규칙을 되돌리면 안 된다")
                    .containsExactly("weekly/2026-12-31");
        }
    }

    @Test
    @DisplayName("34·35 가 안 끝났으면 멈춘다")
    void abortsWithoutTheEarlierMigrations() throws Exception {
        try (Fixture db = fixture()) {
            // care_log_id 가 없다 — 35 를 안 돌린 상태.
            db.exec("""
                    CREATE TABLE schedule (
                      id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
                      owner_kind varchar(10) NOT NULL,
                      on_date date NOT NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);

            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("35_schedule_care_log.sql");
        }
    }

    // ─────────────────────────── 지그 ─────────────────

    /** 마이그레이션 <b>전</b>의 행. `repeat_kind` 컬럼이 아직 없다. */
    private static String insert(int id, String onDate) {
        return "INSERT INTO schedule (id, owner_kind, owner_ref, kind, title, on_date, status, "
                + "version, created_at) VALUES (" + id + ", 'group', 3, 'vet', '보리 병원', "
                + onDate + ", 'planned', 0, NOW(6))";
    }

    /**
     * 마이그레이션 <b>뒤</b>의 행. {@code repeat_kind} 를 직접 준다 — DEFAULT 를 떼어 냈기
     * 때문이다. 안 주면 MySQL 이 거절하고, 그 거절이 곧 "DEFAULT 가 없다" 는 증거다.
     */
    private static String insertAfter(int id, String onDate) {
        return "INSERT INTO schedule (id, owner_kind, owner_ref, kind, title, on_date, status, "
                + "version, created_at, repeat_kind) VALUES (" + id + ", 'group', 3, 'vet', "
                + "'보리 병원', " + onDate + ", 'planned', 0, NOW(6), 'none')";
    }

    private static Fixture fixture() throws SQLException {
        return new Fixture();
    }

    private static final class Fixture implements AutoCloseable {

        private final String name;
        private final Connection connection;

        Fixture() throws SQLException {
            MySQLContainer<?> mysql = MySqlTestContainer.instance();
            synchronized (ScheduleRepeatMigrationExecutionTest.class) {
                name = "schedrepeat_test_" + (++dbCounter);
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

        /** 34·35 가 만들어 둔 표의 최소 형태. */
        void createScheduleTable() throws SQLException {
            exec("""
                    CREATE TABLE schedule (
                      id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
                      owner_kind varchar(10) NOT NULL,
                      owner_ref bigint NOT NULL,
                      kind varchar(10) NOT NULL,
                      title varchar(100) NOT NULL,
                      on_date date NOT NULL,
                      status varchar(10) NOT NULL,
                      version int NOT NULL,
                      created_at datetime(6) NOT NULL,
                      care_log_id bigint DEFAULT NULL
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
