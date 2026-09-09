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
 * {@code 37_crew.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — #417.
 *
 * <h2>여기서 가장 중요한 것</h2>
 * <p><b>CHECK 둘이 실제로 걸리는가.</b> {@code ck_crew_visibility} 와
 * {@code ck_crew_capacity} 는 <b>Hibernate 의 {@code update} 도 prod 의 {@code validate} 도
 * 안 본다</b>. 즉 이 검사가 없으면 CHECK 가 빠진 채 배포돼도 어디서도 안 잡힌다 —
 * 2026-09-08 에 24·29 가 실제로 그랬다.
 *
 * <p>그다음이 <b>이미 있는 표를 안 건드리는가</b>다. dev 는 {@code ddl-auto=update} 라 앱을
 * 먼저 띄우면 Hibernate 가 표를 자기 방식으로 만들어 두고, 그 뒤 이 스크립트는
 * {@code IF NOT EXISTS} 로 지나간다. 그때 <b>사후 검증이 멈춰 세워야 한다</b> — 지나가면
 * CHECK 없는 표가 남는다.
 *
 * <p>스프링을 띄우지 않는다(#21).
 */
class CrewMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/37_crew.sql";

    private static int dbCounter = 0;

    @Test
    @DisplayName("표가 생기고 동네 인덱스와 CHECK 둘이 함께 선다")
    void createsTheTableWithItsIndexAndChecks() throws Exception {
        try (Fixture db = fixture()) {
            db.createChatRoom();

            db.runMigration();

            assertThat(db.query("SELECT column_name FROM information_schema.columns "
                    + "WHERE table_schema = DATABASE() AND table_name = 'crew' "
                    + "ORDER BY column_name"))
                    .containsExactly("capacity", "created_at", "id", "intro",
                            "name", "neighborhood_code", "updated_at", "visibility");

            assertThat(db.query("SELECT column_name FROM information_schema.statistics "
                    + "WHERE table_schema = DATABASE() AND table_name = 'crew' "
                    + "AND index_name = 'idx_crew_public' ORDER BY seq_in_index"))
                    .as("""
                            우리 동네 목록이 타는 인덱스다. 순서가 뒤집히면 \
                            visibility 로 못 좁히고 전 테이블을 훑는다.""")
                    .containsExactly("visibility", "neighborhood_code");

            assertThat(db.query("SELECT constraint_name FROM information_schema.table_constraints "
                    + "WHERE table_schema = DATABASE() AND table_name = 'crew' "
                    + "AND constraint_type = 'CHECK' ORDER BY constraint_name"))
                    .as("""
                            Hibernate 의 update 도 prod 의 validate 도 CHECK 는 안 본다 — \
                            여기서 안 재면 아무 데서도 안 잡힌다.""")
                    .containsExactly("ck_crew_capacity", "ck_crew_visibility");
        }
    }

    @Test
    @DisplayName("모르는 공개 범위와 말이 안 되는 정원은 CHECK 가 막는다")
    void rejectsUnknownVocabularyAndImpossibleCapacity() throws Exception {
        try (Fixture db = fixture()) {
            db.createChatRoom();
            db.runMigration();

            assertThatThrownBy(() -> db.exec(insert("'secret'", 20)))
                    .as("""
                            아무 문자열이나 공개 범위가 되면 목록 질의가 조용히 아무것도 \
                            안 준다 — 오류가 안 나서 아무도 모른다.""")
                    .isInstanceOf(SQLException.class);

            assertThatThrownBy(() -> db.exec(insert("'public'", 1)))
                    .as("1명짜리 모임은 모임이 아니다")
                    .isInstanceOf(SQLException.class);

            assertThatThrownBy(() -> db.exec(insert("'public'", 101)))
                    .as("100을 넘으면 동네 모임이 아니다")
                    .isInstanceOf(SQLException.class);

            db.exec(insert("'invite'", 2));
            db.exec(insert("'public'", 100));
            assertThat(db.query("SELECT COUNT(*) FROM crew")).containsExactly("2");
        }
    }

    @Test
    @DisplayName("동네가 비어 있어도 들어간다 — 코드로만 들어오는 크루다")
    void allowsACrewWithoutANeighbourhood() throws Exception {
        try (Fixture db = fixture()) {
            db.createChatRoom();
            db.runMigration();

            db.exec("INSERT INTO crew (name, visibility, capacity, created_at) "
                    + "VALUES ('동네 없는 모임', 'invite', 20, NOW(6))");

            assertThat(db.query("SELECT IFNULL(neighborhood_code, '(null)') FROM crew"))
                    .as("동네를 안 고른 사람도 크루를 만들 수 있다 — 코드로만 들어온다")
                    .containsExactly("(null)");
        }
    }

    @Test
    @DisplayName("두 번 돌려도 그대로다 — 멱등")
    void secondRunIsIdempotent() throws Exception {
        try (Fixture db = fixture()) {
            db.createChatRoom();
            db.runMigration();
            db.exec(insert("'public'", 8));

            db.runMigration();

            assertThat(db.query("SELECT CONCAT(visibility, '/', capacity) FROM crew"))
                    .as("두 번째 실행이 사람이 정한 값을 되돌리면 안 된다")
                    .containsExactly("public/8");
        }
    }

    @Test
    @DisplayName("chat_room 이 없으면 멈춘다 — 크루는 방 위에 얹는다")
    void abortsWithoutTheChatRoomTable() throws Exception {
        try (Fixture db = fixture()) {
            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("chat_room");
        }
    }

    @Test
    @DisplayName("Hibernate 가 CHECK 없이 만들어 둔 표는 사후 검증이 멈춰 세운다")
    void refusesToPassOverATableThatHibernateMadeWithoutChecks() throws Exception {
        try (Fixture db = fixture()) {
            db.createChatRoom();
            // dev 에서 앱을 먼저 띄운 모양 — ddl-auto=update 가 만든 표에는 CHECK 가 없다.
            db.exec("""
                    CREATE TABLE crew (
                      capacity int NOT NULL,
                      created_at datetime(6) NOT NULL,
                      id bigint NOT NULL AUTO_INCREMENT,
                      updated_at datetime(6) DEFAULT NULL,
                      neighborhood_code varchar(10) DEFAULT NULL,
                      visibility varchar(10) NOT NULL,
                      name varchar(30) NOT NULL,
                      intro varchar(200) DEFAULT NULL,
                      PRIMARY KEY (id)
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);

            assertThatThrownBy(db::runMigration)
                    .as("""
                            IF NOT EXISTS 로 조용히 지나가면 CHECK 도 인덱스도 없는 표가 \
                            남는다. 그 상태를 사람이 알아채는 곳이 여기밖에 없다.""")
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("사후 검증");
        }
    }

    // ─────────────────────────── 지그 ─────────────────

    private static String insert(String visibility, int capacity) {
        return "INSERT INTO crew (name, neighborhood_code, visibility, capacity, created_at) "
                + "VALUES ('성수동 아침 산책', '1120052000', " + visibility + ", "
                + capacity + ", NOW(6))";
    }

    private static Fixture fixture() throws SQLException {
        return new Fixture();
    }

    private static final class Fixture implements AutoCloseable {

        private final String name;
        private final Connection connection;

        Fixture() throws SQLException {
            MySQLContainer<?> mysql = MySqlTestContainer.instance();
            synchronized (CrewMigrationExecutionTest.class) {
                name = "crew_test_" + (++dbCounter);
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

        /** 크루가 얹히는 표. 사전 점검이 이것을 본다. */
        void createChatRoom() throws SQLException {
            exec("""
                    CREATE TABLE chat_room (
                      id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
                      origin_kind varchar(20) NOT NULL,
                      origin_ref varchar(64) NOT NULL,
                      name varchar(50) NOT NULL,
                      tag varchar(20) NOT NULL
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
