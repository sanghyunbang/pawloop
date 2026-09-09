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
 * {@code 35_schedule_care_log.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — #420.
 *
 * <h2>여기서 가장 중요한 것</h2>
 * <p><b>FK 가 없는 것</b>이다. 있으면 다음 {@code 01_schema.sql} 재생성에서 사라지고
 * (그 파일은 엔티티에서 뽑는데 엔티티는 {@code care.entity.CareLog} 를 들 수 없다),
 * 그러면 새로 세운 DB 와 마이그레이션한 DB 의 제약이 갈린다. 오류는 안 난다.
 *
 * <p>그리고 <b>옛 표에 컬럼을 더하지 않는 것</b>이다. 감정 여행 시절의 {@code schedule}
 * (여행 일정)이 아직 남아 있을 수 있고({@code 34_schedule.sql} 이 옮긴다), 그 표에 컬럼을
 * 더하면 엉뚱한 표가 늘어난다.
 *
 * <p>스프링을 띄우지 않는다(#21).
 */
class ScheduleCareLogMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/35_schedule_care_log.sql";

    private static int dbCounter = 0;

    @Test
    @DisplayName("care_log_id 가 NULL 을 받는 컬럼으로 생기고, FK 는 안 생긴다")
    void addsANullableColumnWithoutAForeignKey() throws Exception {
        try (Fixture db = fixture()) {
            db.createScheduleTable();

            db.runMigration();

            assertThat(db.query("SELECT is_nullable FROM information_schema.columns "
                    + "WHERE table_schema = DATABASE() AND table_name = 'schedule' "
                    + "AND column_name = 'care_log_id'"))
                    .containsExactly("YES");
            assertThat(db.query("SELECT COUNT(*) FROM information_schema.key_column_usage "
                    + "WHERE table_schema = DATABASE() AND table_name = 'schedule' "
                    + "AND column_name = 'care_log_id' AND referenced_table_name IS NOT NULL"))
                    .as("""
                            FK 를 걸면 01_schema.sql 재생성에서 사라진다 — 엔티티가 \
                            care.entity.CareLog 를 들 수 없기 때문이다. 그때부터 새 DB 와 \
                            마이그레이션한 DB 의 제약이 갈리고, 오류는 안 난다.""")
                    .containsExactly("0");
        }
    }

    @Test
    @DisplayName("이미 있으면 지나간다 — 멱등")
    void secondRunIsIdempotent() throws Exception {
        try (Fixture db = fixture()) {
            db.createScheduleTable();
            db.runMigration();
            db.exec("INSERT INTO schedule (id, owner_kind, owner_ref, kind, title, on_date, "
                    + "status, version, created_at, care_log_id) "
                    + "VALUES (1, 'group', 3, 'vet', '보리 병원', '2026-10-03', 'done', 0, NOW(6), 42)");

            db.runMigration();

            assertThat(db.query("SELECT care_log_id FROM schedule WHERE id = 1"))
                    .as("두 번째 실행이 이미 이어 둔 값을 건드리면 안 된다")
                    .containsExactly("42");
        }
    }

    @Test
    @DisplayName("34 가 만든 schedule 이 없으면 멈춘다 — 옛 여행 일정표에 컬럼을 더하지 않는다")
    void abortsWithoutTheNewScheduleTable() throws Exception {
        try (Fixture db = fixture()) {
            // 감정 여행 시절의 옛 표. owner_kind 가 없다.
            db.exec("""
                    CREATE TABLE schedule (
                      schedule_id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
                      title varchar(100) DEFAULT NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);

            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("34_schedule.sql");

            assertThat(db.columns("schedule"))
                    .as("멈췄으면 손대지 않았어야 한다")
                    .containsExactly("schedule_id", "title");
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
            synchronized (ScheduleCareLogMigrationExecutionTest.class) {
                name = "schedcare_test_" + (++dbCounter);
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

        /** 34 가 만드는 표의 최소 형태. 이 검사가 보는 것은 컬럼 하나가 붙는가다. */
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
                      created_at datetime(6) NOT NULL
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

        List<String> columns(String table) throws SQLException {
            return query("SELECT column_name FROM information_schema.columns "
                    + "WHERE table_schema = DATABASE() AND table_name = '" + table + "' "
                    + "ORDER BY ordinal_position");
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
