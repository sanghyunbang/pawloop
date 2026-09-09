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
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * {@code 34_schedule.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — #418.
 *
 * <h2>여기서 가장 중요한 것</h2>
 * <p><b>지우기 규칙이다.</b> 이 표에는 사람이 손으로 적어 둔 것이 들어간다 — 병원 예약,
 * 약 먹이는 날, 누가 맡기로 했는지. 아이를 보내거나 가족 한 명이 탈퇴했을 때 그 계획이
 * 통째로 사라지면 <b>오류 없이</b> 사라진다. 아무도 모른 채로 배포된다.
 *
 * <p>그래서 {@code dog} 와 {@code assignee} 는 {@code SET NULL} 이어야 하고
 * ({@code care_log.dog_id} 가 #154 에서 고른 것과 같은 답), 그것을 표 정의가 아니라
 * <b>실제로 지워 보고</b> 확인한다.
 *
 * <p>{@code at_time} 이 {@code NULL} 을 받는 것도 같은 종류다 — 못 받으면 "이번 주말 목욕"
 * 이 {@code 00:00} 이 되고, 화면은 사용자가 안 정한 시각을 정한 것처럼 그린다.
 *
 * <h2>같은 이름의 옛 표가 운영 DB 에 있다</h2>
 * <p>감정 여행 시절의 {@code schedule}(여행 일정)이 코드 없이 표만 남아 있다 — dev DB 에서
 * 실측했다. 이 스크립트는 그것을 <b>지우지 않고</b> {@code schedule_legacy_journey} 로
 * 옮긴다. 여기서 그 경로를 실제로 돌려 보는 이유는, 옮기다 {@code journey.schedule_id} 의
 * FK 가 <b>새 표를 가리키게 되면</b> 남의 표에 남의 id 가 붙기 때문이다 — 오류 없이.
 *
 * <p>스프링을 띄우지 않는다(#21).
 */
class ScheduleMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/34_schedule.sql";

    private static int dbCounter = 0;

    @Test
    @DisplayName("schedule 표가 컬럼 17개와 인덱스 둘로 생긴다")
    void createsTheTable() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites(true, true);

            db.runMigration();

            assertThat(db.columns("schedule")).containsExactly(
                    "assignee", "at_time", "created_at", "created_by", "dog_id", "done_at",
                    "id", "kind", "memo", "on_date", "owner_kind", "owner_ref", "status",
                    "title", "updated_at", "updated_by", "version");
            assertThat(db.indexes("schedule"))
                    .contains("idx_schedule_owner_date", "idx_schedule_dog_date");
        }
    }

    @Test
    @DisplayName("아이를 보내도 그 계획은 남는다 — dog_id 만 비워진다")
    void keepsTheScheduleWhenTheDogIsGone() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites(true, true);
            db.runMigration();
            db.seedPeopleAndDogs();
            db.exec(insert("'dog'", "1", "1", "'vet'", "'보리 병원'", "'2026-10-03'", "'10:30'",
                    "2", "1"));

            db.exec("DELETE FROM dog WHERE id = 1");

            assertThat(db.query("SELECT CONCAT(title, '/', IFNULL(dog_id, 'null')) FROM schedule"))
                    .as("계획은 남고 아이 자리만 비어야 한다")
                    .containsExactly("보리 병원/null");
        }
    }

    @Test
    @DisplayName("담당자가 탈퇴해도 그 일은 남는다 — assignee 만 비워진다")
    void keepsTheScheduleWhenTheAssigneeLeaves() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites(true, true);
            db.runMigration();
            db.seedPeopleAndDogs();
            db.exec(insert("'group'", "7", "1", "'vet'", "'보리 병원'", "'2026-10-03'", "'10:30'",
                    "2", "1"));

            db.exec("DELETE FROM users WHERE id = 2");

            assertThat(db.query(
                    "SELECT CONCAT(title, '/', IFNULL(assignee, 'null')) FROM schedule"))
                    .as("담당자가 사라졌다고 그 일이 남아 있다는 사실까지 지우면 안 된다")
                    .containsExactly("보리 병원/null");
        }
    }

    @Test
    @DisplayName("적은 사람이 탈퇴하면 그 사람이 적은 일정은 함께 사라진다")
    void cascadesFromTheAuthor() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites(true, true);
            db.runMigration();
            db.seedPeopleAndDogs();
            db.exec(insert("'dog'", "1", "1", "'walk'", "'저녁 산책'", "'2026-10-03'", "NULL",
                    "NULL", "1"));

            db.exec("DELETE FROM users WHERE id = 1");

            assertThat(db.query("SELECT COUNT(*) FROM schedule")).containsExactly("0");
        }
    }

    @Test
    @DisplayName("at_time 이 비어도 들어간다 — \"이번 주말 목욕\" 이 00:00 이 되면 안 된다")
    void acceptsAScheduleWithoutATime() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites(true, true);
            db.runMigration();
            db.seedPeopleAndDogs();

            assertThatCode(() -> db.exec(insert("'dog'", "1", "1", "'bath'", "'주말 목욕'",
                    "'2026-10-04'", "NULL", "NULL", "1"))).doesNotThrowAnyException();

            assertThat(db.query("SELECT IFNULL(at_time, 'null') FROM schedule"))
                    .containsExactly("null");
        }
    }

    @Test
    @DisplayName("모르는 owner_kind · kind · status 는 CHECK 가 막는다")
    void rejectsUnknownVocabulary() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites(true, true);
            db.runMigration();
            db.seedPeopleAndDogs();

            assertThatThrownBy(() -> db.exec(insert("'family'", "7", "NULL", "'vet'", "'x'",
                    "'2026-10-03'", "NULL", "NULL", "1")))
                    .as("owner_kind 는 셋뿐이다")
                    .isInstanceOf(SQLException.class);
            assertThatThrownBy(() -> db.exec(insert("'dog'", "1", "1", "'grooming'", "'x'",
                    "'2026-10-03'", "NULL", "NULL", "1")))
                    .as("kind 는 일곱뿐이다 — 앱의 wire 값과 같은 문자열이다")
                    .isInstanceOf(SQLException.class);
            assertThatThrownBy(() -> db.exec(
                    "INSERT INTO schedule (owner_kind, owner_ref, kind, title, on_date, status, "
                            + "version, created_by, created_at) VALUES "
                            + "('dog', 1, 'vet', 'x', '2026-10-03', 'cancelled', 0, 1, NOW(6))"))
                    .as("status 는 셋뿐이다")
                    .isInstanceOf(SQLException.class);
        }
    }

    @Test
    @DisplayName("room 은 미리 열어 둔 값이라 표는 받는다 — 거절은 서비스가 한다")
    void acceptsTheReservedRoomOwner() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites(true, true);
            db.runMigration();
            db.seedPeopleAndDogs();

            assertThatCode(() -> db.exec(insert("'room'", "11", "NULL", "'walk'", "'합동 산책'",
                    "'2026-10-05'", "'09:00'", "NULL", "1"))).doesNotThrowAnyException();
        }
    }

    @Test
    @DisplayName("두 번 돌려도 줄이 늘지 않는다 — 멱등")
    void secondRunIsIdempotent() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites(true, true);
            db.runMigration();
            db.seedPeopleAndDogs();
            db.exec(insert("'dog'", "1", "1", "'med'", "'심장사상충'", "'2026-10-01'", "NULL",
                    "NULL", "1"));

            db.runMigration();

            assertThat(db.query("SELECT title FROM schedule"))
                    .as("두 번째 실행이 사람이 적어 둔 것을 건드리면 안 된다")
                    .containsExactly("심장사상충");
        }
    }

    @Test
    @DisplayName("users 나 dog 가 없으면 멈춘다 — 앞 스크립트가 먼저다")
    void abortsWithoutItsPrerequisites() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites(true, false);

            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("01_users.sql");
        }
    }

    @Test
    @DisplayName("같은 이름의 표가 컬럼이 모자란 채로 있으면 멈춘다 — 사람이 봐야 한다")
    void abortsWhenAPartialTableExists() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites(true, true);
            db.exec("CREATE TABLE schedule (id bigint NOT NULL PRIMARY KEY)");

            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("사람이 확인하라");

            assertThat(db.columns("schedule"))
                    .as("멈췄으면 손대지 않았어야 한다")
                    .containsExactly("id");
        }
    }


    // ─────────────────── 같은 이름의 옛 표 ───────────────────

    @Test
    @DisplayName("옛 여행 일정 표를 지우지 않고 옆으로 옮긴다 — 행도 FK 도 그대로 따라간다")
    void parksTheLegacyTravelTableInsteadOfDroppingIt() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites(true, true);
            db.createLegacyScheduleWithJourney();

            db.runMigration();

            assertThat(db.query("SELECT title FROM schedule_legacy_journey ORDER BY schedule_id"))
                    .as("사람이 적어 둔 행이다. 지우는 것은 이 마이그레이션이 결정할 일이 아니다")
                    .containsExactly("부산 2박 3일");
            assertThat(db.query(
                    "SELECT referenced_table_name FROM information_schema.key_column_usage "
                            + "WHERE table_schema = DATABASE() AND table_name = 'journey' "
                            + "AND referenced_table_name IS NOT NULL"))
                    .as("""
                            RENAME TABLE 이 FK 를 함께 옮긴다. 안 옮겨져 journey 가 새 schedule 을 \
                            가리키면 남의 표에 남의 id 가 붙고, 그건 오류 없이 일어난다.""")
                    .containsExactly("schedule_legacy_journey");
            assertThat(db.columns("schedule"))
                    .as("그 자리에는 새 표가 서야 한다")
                    .contains("owner_kind", "owner_ref", "on_date");
        }
    }

    @Test
    @DisplayName("옛 표를 옮긴 DB 에서 두 번 돌려도 그대로다")
    void isIdempotentAfterParkingTheLegacyTable() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites(true, true);
            db.createLegacyScheduleWithJourney();

            db.runMigration();
            db.runMigration();

            assertThat(db.query("SELECT COUNT(*) FROM schedule_legacy_journey"))
                    .containsExactly("1");
            assertThat(db.query("SELECT COUNT(*) FROM schedule")).containsExactly("0");
        }
    }

    @Test
    @DisplayName("옛 표가 있는데 옮겨 둔 자리도 이미 차 있으면 멈춘다 — 사람이 봐야 한다")
    void abortsWhenTheParkingSpotIsTaken() throws Exception {
        try (Fixture db = fixture()) {
            db.createPrerequisites(true, true);
            db.createLegacyScheduleWithJourney();
            db.exec("CREATE TABLE schedule_legacy_journey (schedule_id bigint PRIMARY KEY)");

            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("사람이 확인하라");

            assertThat(db.query("SELECT COUNT(*) FROM schedule"))
                    .as("멈췄으면 옛 표가 제자리에 그대로 있어야 한다")
                    .containsExactly("1");
        }
    }

    // ─────────────────────────── 지그 ─────────────────

    private static String insert(String ownerKind, String ownerRef, String dogId, String kind,
                                 String title, String onDate, String atTime, String assignee,
                                 String createdBy) {
        return "INSERT INTO schedule (owner_kind, owner_ref, dog_id, kind, title, on_date, "
                + "at_time, assignee, status, version, created_by, created_at) VALUES ("
                + String.join(", ", ownerKind, ownerRef, dogId, kind, title, onDate, atTime,
                        assignee, "'planned'", "0", createdBy, "NOW(6)") + ")";
    }

    private static Fixture fixture() throws SQLException {
        return new Fixture();
    }

    private static final class Fixture implements AutoCloseable {

        private final String name;
        private final Connection connection;

        Fixture() throws SQLException {
            MySQLContainer<?> mysql = MySqlTestContainer.instance();
            synchronized (ScheduleMigrationExecutionTest.class) {
                name = "schedule_test_" + (++dbCounter);
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

        void createPrerequisites(boolean withUsers, boolean withDog) throws SQLException {
            if (withUsers) {
                exec("""
                        CREATE TABLE users (
                          id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
                          nickname varchar(50) NOT NULL
                        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                        """);
            }
            if (withDog) {
                exec("""
                        CREATE TABLE dog (
                          id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
                          name varchar(50) NOT NULL,
                          deleted_at datetime(6) DEFAULT NULL
                        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                        """);
            }
        }

        /**
         * 감정 여행 시절의 {@code schedule} 과 그것을 가리키는 {@code journey} — #94 가 코드만
         * 지우고 표는 남긴 것들이다. 컬럼 구성은 dev DB 에서 실측한 그대로다.
         */
        void createLegacyScheduleWithJourney() throws SQLException {
            exec("""
                    CREATE TABLE schedule (
                      schedule_id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
                      user_id bigint NOT NULL,
                      title varchar(100) DEFAULT NULL,
                      content varchar(1000) DEFAULT NULL,
                      date_from date DEFAULT NULL,
                      date_to date DEFAULT NULL,
                      created_at datetime(6) DEFAULT NULL,
                      updated_at datetime(6) DEFAULT NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
            exec("""
                    CREATE TABLE journey (
                      id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
                      schedule_id bigint DEFAULT NULL,
                      CONSTRAINT fk_journey_schedule FOREIGN KEY (schedule_id)
                        REFERENCES schedule (schedule_id) ON DELETE SET NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
            exec("INSERT INTO schedule (schedule_id, user_id, title) VALUES (1, 1, '부산 2박 3일')");
            exec("INSERT INTO journey (id, schedule_id) VALUES (1, 1)");
        }

        /** 사람 둘(엄마·아빠) · 아이 하나(보리). */
        void seedPeopleAndDogs() throws SQLException {
            exec("INSERT INTO users (id, nickname) VALUES (1, '엄마'), (2, '아빠')");
            exec("INSERT INTO dog (id, name) VALUES (1, '보리')");
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
                    + "ORDER BY column_name");
        }

        List<String> indexes(String table) throws SQLException {
            return query("SELECT DISTINCT index_name FROM information_schema.statistics "
                    + "WHERE table_schema = DATABASE() AND table_name = '" + table + "'");
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
