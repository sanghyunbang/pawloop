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
 * {@code 30_users_neighborhood.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — 이슈 #342.
 *
 * <h2>여기서만 보는 것</h2>
 * <p><b>좌표 컬럼이 안 생기는 것</b>이다. 이 기능이 위치기반서비스 신고 전에도 사는 이유가
 * "사용자가 고른 이름이고 좌표가 아니다" 하나인데, 그 선을 지키는 장치가 코드 리뷰밖에
 * 없었다. 스크립트의 사후 검증이 {@code users} 에 좌표 컬럼이 없는 것을 세고, 이 테스트가
 * 그 검증이 실제로 막는지를 본다.
 *
 * <p>{@code ddl-auto=validate} 는 <b>없어야 할 컬럼</b>을 보지 않는다 — 누가 좌표 컬럼을
 * 더해도 부팅은 그대로 뜬다.
 *
 * <p>스프링을 띄우지 않는다. 공유 컨테이너 안에 테스트마다 별도 데이터베이스를 만든다(#21).
 */
class UsersNeighborhoodMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/30_users_neighborhood.sql";
    private static final String RUNBOOK = "mysql/README.md";

    private static int dbCounter = 0;

    // ─────────────────────────── 테스트 ───────────────────────────

    @Test
    @DisplayName("컬럼과 인덱스가 생기고, 앞자리 LIKE 가 그 인덱스를 탄다")
    void migration_addsTheColumnAndAnIndexThatPrefixSearchCanUse() throws Exception {
        try (Fixture db = fixture()) {
            db.createUsers();

            db.runMigration();

            assertThat(db.query("""
                    SELECT CONCAT(data_type, '(', character_maximum_length, ') ', is_nullable)
                    FROM information_schema.columns
                    WHERE table_schema = DATABASE() AND table_name = 'users'
                      AND column_name = 'neighborhood_code'
                    """))
                    .as("열 자리 코드다 — 정수로 두면 제주(50)·세종(36)의 앞자리 0 이 사라진다")
                    .containsExactly("varchar(10) YES");

            assertThat(db.query("""
                    SELECT index_name FROM information_schema.statistics
                    WHERE table_schema = DATABASE() AND table_name = 'users'
                      AND index_name = 'idx_users_neighborhood'
                    """))
                    .isNotEmpty();

            db.exec("INSERT INTO users (id, role, neighborhood_code) VALUES (1, 'ROLE_USER', '1120052000')");
            db.exec("INSERT INTO users (id, role, neighborhood_code) VALUES (2, 'ROLE_USER', '1111051500')");
            db.exec("INSERT INTO users (id, role) VALUES (3, 'ROLE_USER')");

            assertThat(db.query("SELECT id FROM users WHERE neighborhood_code LIKE '11200%' ORDER BY id"))
                    .as("커뮤니티의 '우리 동네' 가 이 모양으로 구(區)를 훑는다")
                    .containsExactly("1");
        }
    }

    @Test
    @DisplayName("좌표 컬럼이 있으면 중단한다 — 이 표에 위치를 두지 않는 것이 A안의 선이다")
    void aCoordinateColumnAborts() throws Exception {
        try (Fixture db = fixture()) {
            db.createUsers();
            // 누군가 "지도 중심을 서버가 알면 편하다" 며 더한 모양이다.
            db.exec("ALTER TABLE users ADD COLUMN neighborhood_lat DOUBLE NULL");

            assertThatThrownBy(db::runMigration)
                    .as("""
                            사용자가 고른 동네가 위치정보가 아닌 이유는 '단말이 잰 값이 아니다' \
                            하나다. 좌표가 이 표에 들어오는 순간 그 문장이 거짓이 되고, \
                            ddl-auto=validate 는 '없어야 할 컬럼' 을 안 본다.""")
                    .isInstanceOf(SQLException.class);
        }
    }

    @Test
    @DisplayName("쌓인 사용자가 있어도 행을 잃지 않는다")
    void existingRowsSurvive() throws Exception {
        try (Fixture db = fixture()) {
            db.createUsers();
            db.exec("INSERT INTO users (id, role) VALUES (1, 'ROLE_USER'), (2, 'ROLE_USER')");

            db.runMigration();

            assertThat(db.query("SELECT COUNT(*) FROM users")).containsExactly("2");
            assertThat(db.query("SELECT IFNULL(neighborhood_code, 'NULL') FROM users ORDER BY id"))
                    .as("옛 사용자는 동네가 없다 — 고르기 전에는 null 이 정상이다")
                    .containsExactly("NULL", "NULL");
        }
    }

    @Test
    @DisplayName("두 번 돌려도 성공한다 — 재실행이 안전하다")
    void migration_isIdempotent() throws Exception {
        try (Fixture db = fixture()) {
            db.createUsers();
            db.runMigration();
            db.runMigration();

            assertThat(db.query("""
                    SELECT COUNT(*) FROM information_schema.columns
                    WHERE table_schema = DATABASE() AND table_name = 'users'
                      AND column_name = 'neighborhood_code'
                    """)).containsExactly("1");
        }
    }

    @Test
    @DisplayName("users 가 없으면 중단한다")
    void withoutUsers_itAborts() throws Exception {
        try (Fixture db = fixture()) {
            assertThatThrownBy(db::runMigration).isInstanceOf(SQLException.class);
        }
    }

    @Test
    @DisplayName("런북(mysql/README.md)이 이 파일의 실행 커맨드를 담고 있다")
    void runbook_listsThisScript() throws Exception {
        String runbook = Files.readString(
                TestProjectPaths.requireFile(RUNBOOK), StandardCharsets.UTF_8);

        assertThat(runbook)
                .as("실행 순서에 없는 스크립트는 아무도 돌리지 않는다 — prod 는 validate 라 부팅이 실패한다")
                .contains("post-start\\30_users_neighborhood.sql");
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private static Fixture fixture() throws SQLException {
        return new Fixture();
    }

    private static final class Fixture implements AutoCloseable {

        private final String name;
        private final Connection connection;

        Fixture() throws SQLException {
            MySQLContainer<?> mysql = MySqlTestContainer.instance();
            synchronized (UsersNeighborhoodMigrationExecutionTest.class) {
                name = "hood_mig_test_" + (++dbCounter);
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
         * {@code users} 를 최소 모양으로 세운다.
         *
         * <p>정본({@code mysql/init/01_schema.sql})은 표 48개를 한 번에 만드는 파일이라
         * 여기서 통째로 돌리면 이 테스트가 스키마 전체에 묶인다. 이 스크립트가 보는 것은
         * {@code users} 하나뿐이다.
         */
        void createUsers() throws SQLException {
            exec("""
                    CREATE TABLE users (
                        id   BIGINT      NOT NULL AUTO_INCREMENT PRIMARY KEY,
                        role VARCHAR(20) NOT NULL
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
