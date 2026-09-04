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
 * {@code 18_place_catalog.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — 이슈 #273.
 *
 * <h2>왜 필요한가</h2>
 * <p>{@code mysql/init/01_schema.sql} 은 <b>빈 DB</b> 를 세우는 파일이라 이미 돌고 있는 운영
 * DB 에는 실행하지 않는다. 살아 있는 DB 에 {@code place_catalog} 를 넣는 경로는
 * {@code post-start/18} 하나뿐이고, prod 는 {@code ddl-auto=validate} 라 이 스크립트가
 * 틀리면 <b>앱이 부팅에 실패한다.</b>
 *
 * <p>그리고 {@code SchemaDdlDriftTest} 도 {@code ddl-auto=validate} 도 <b>CHECK 제약을
 * 보지 않는다.</b> 이 표에서 CHECK 가 지키는 것이 "행이 하나" 라는 설계 전체다 —
 * 없으면 인스턴스 둘이 동시에 갱신할 때 행이 둘이 되고, 앱은 {@code id = 1} 만 읽으므로
 * 나머지가 조용히 유령이 된다. 여기서 안 보면 아무도 안 알려준다.
 *
 * <p>스프링을 띄우지 않는다. 필요한 것이 <b>그 표가 아직 없는 DB</b> 라서다(#21).
 */
class PlaceCatalogSchemaMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/18_place_catalog.sql";

    /** 데이터베이스 이름 충돌을 피하기 위한 카운터. 컨테이너 하나를 여러 테스트가 공유한다. */
    private static int dbCounter = 0;

    // ─────────────────────────── 테스트 ───────────────────────────

    @Test
    @DisplayName("빈 DB 에 돌리면 표가 생긴다 — 부모 표가 필요 없다")
    void migrationCreatesTheTable() throws Exception {
        try (Fixture db = fixture()) {
            db.runMigration();

            assertThat(db.tables())
                    .as("빠지면 ddl-auto=validate 가 부팅을 막는다")
                    .contains("place_catalog");
            assertThat(db.columns("place_catalog")).containsExactlyInAnyOrder(
                    "id", "payload", "etag", "item_count", "total_count",
                    "fetched_at", "failed_at", "fail_streak");
        }
    }

    @Test
    @DisplayName("두 번째 행을 DB 가 막는다 — 이 표의 설계 전체가 '행이 하나' 다")
    void aSecondRowIsRejected() throws Exception {
        try (Fixture db = fixture()) {
            db.runMigration();
            db.insertCatalog(1);

            assertThatThrownBy(() -> db.insertCatalog(2))
                    .as("""
                            CHECK 가 없으면 인스턴스 둘이 동시에 갱신할 때 행이 둘이 되고, \
                            앱은 id = 1 만 읽으므로 나머지가 조용히 유령이 된다. 어느 것이 \
                            답인지 코드 어디에도 안 적혀 있게 된다.""")
                    .isInstanceOf(SQLException.class);

            assertThat(db.count("place_catalog")).isEqualTo(1);
        }
    }

    @Test
    @DisplayName("payload 가 LONGTEXT 다 — MEDIUMTEXT 면 데이터가 커지는 날 조용히 잘린다")
    void payloadIsLongtext() throws Exception {
        try (Fixture db = fixture()) {
            db.runMigration();

            assertThat(db.dataType("place_catalog", "payload"))
                    .as("""
                            한 벌이 2.83MB 다(9,684곳, 실측 2026-09-04). MEDIUMTEXT 는 16MB 라 \
                            지금은 들어가지만 여섯 배로 늘면 잘린다 — 잘린 JSON 은 파싱 오류가 \
                            아니라 읽히는 순간까지 정상으로 보인다.""")
                    .isEqualTo("longtext");
        }
    }

    @Test
    @DisplayName("FK 가 하나도 없다 — 담긴 contentId 는 KTO 가 준 문자열이지 우리 표의 키가 아니다")
    void thereAreNoForeignKeys() throws Exception {
        try (Fixture db = fixture()) {
            db.runMigration();

            assertThat(db.foreignKeys())
                    .as("places 표에 FK 를 걸면 KTO 가 새로 만든 장소를 적재 전까지 캐시할 수 없다")
                    .isEmpty();
        }
    }

    @Test
    @DisplayName("두 번 돌려도 같은 상태로 끝난다")
    void migrationIsIdempotent() throws Exception {
        try (Fixture db = fixture()) {
            db.runMigration();
            db.insertCatalog(1);
            db.runMigration();

            assertThat(db.tables()).contains("place_catalog");
            assertThat(db.checks()).containsExactly("chk_place_catalog_singleton");
            assertThat(db.count("place_catalog"))
                    .as("런북이 '이미 적용된 항목은 아무 변경 없이' 라고 약속한다")
                    .isEqualTo(1);
        }
    }

    @Test
    @DisplayName("나중에 컬럼이 늘어도 다시 돌아간다 — 사후 검증이 개수가 아니라 이름을 센다")
    void migrationStaysRerunnableAfterAColumnIsAdded() throws Exception {
        // 런북이 "전부 멱등" 이라고 약속한다(mysql/README.md). 사후 검증이 표의 **전체
        // 컬럼 수**를 리터럴과 견주면, 다음 마이그레이션이 컬럼을 하나 더하는 순간 그
        // 약속이 깨진다 — 그 뒤로 이 스크립트가 ABORT 한다 (#267 이 같은 것을 재 뒀다).
        try (Fixture db = fixture()) {
            db.runMigration();
            db.exec("ALTER TABLE place_catalog ADD COLUMN source VARCHAR(16) NULL");

            db.runMigration();

            assertThat(db.columns("place_catalog")).contains("payload", "etag", "source");
        }
    }

    @Test
    @DisplayName("Hibernate 가 먼저 만든 표에 CHECK 를 붙인다 — ddl-auto=update 는 제약을 안 붙인다")
    void theCheckIsAddedToATableThatAlreadyExists() throws Exception {
        // dev 는 ddl-auto=update 라 앱이 먼저 뜨면 Hibernate 가 표를 만들어 둔다.
        // 그때 만들어진 표에 CHECK 가 없을 수 있고, update 는 나중에 붙여 주지 않는다.
        try (Fixture db = fixture()) {
            db.exec("""
                    CREATE TABLE place_catalog (
                        id          INT          NOT NULL,
                        payload     LONGTEXT     NOT NULL,
                        etag        VARCHAR(64)  NOT NULL,
                        item_count  INT          NOT NULL,
                        total_count INT          NOT NULL DEFAULT 0,
                        fetched_at  DATETIME(6)  NOT NULL,
                        failed_at   DATETIME(6)  NULL,
                        fail_streak INT          NOT NULL DEFAULT 0,
                        PRIMARY KEY (id)
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
            assertThat(db.checks()).as("전제 — 이 표에는 아직 제약이 없다").isEmpty();

            db.runMigration();

            assertThat(db.checks()).containsExactly("chk_place_catalog_singleton");
            assertThatThrownBy(() -> db.insertCatalog(2))
                    .as("붙였으면 실제로 막아야 한다 — 이름만 있고 안 막으면 없는 것과 같다")
                    .isInstanceOf(SQLException.class);
        }
    }

    @Test
    @DisplayName("행이 둘 이상이면 한 글자도 안 바꾸고 멈춘다 — 어느 것이 정본인지 사람이 정한다")
    void migrationAbortsWhenThereAreTwoRows() throws Exception {
        try (Fixture db = fixture()) {
            // CHECK 없이 만들어진 표에 행이 둘 쌓인 상태. 그대로 통과시키면 앱은 id = 1 만
            // 읽으므로 나머지가 조용히 유령이 된다.
            db.exec("""
                    CREATE TABLE place_catalog (
                        id          INT          NOT NULL,
                        payload     LONGTEXT     NOT NULL,
                        etag        VARCHAR(64)  NOT NULL,
                        item_count  INT          NOT NULL,
                        total_count INT          NOT NULL DEFAULT 0,
                        fetched_at  DATETIME(6)  NOT NULL,
                        failed_at   DATETIME(6)  NULL,
                        fail_streak INT          NOT NULL DEFAULT 0,
                        PRIMARY KEY (id)
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
            db.insertCatalog(1);
            db.insertCatalog(2);

            assertThatThrownBy(db::runMigration)
                    .as("""
                            **메시지까지 본다.** 여기서 SQLException 만 확인하면 이 검사가                             사전 점검을 안 재게 된다 — 사전 점검을 통째로 지워도 §B 의                             ALTER 가 CHECK 를 못 걸어 어차피 예외가 나기 때문이다(실측).                             그러면 운영자가 보는 것은 "무엇을 어떻게 하라" 가 아니라                             MySQL 의 ERROR 3819 뿐이다.""")
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("행이 둘 이상이다");

            assertThat(db.checks())
                    .as("멈췄으면 스키마는 한 글자도 안 바뀌어야 한다")
                    .isEmpty();
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
            synchronized (PlaceCatalogSchemaMigrationExecutionTest.class) {
                name = "place_catalog_mig_test_" + (++dbCounter);
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

        void insertCatalog(int id) throws SQLException {
            exec("INSERT INTO place_catalog "
                    + "(id, payload, etag, item_count, total_count, fetched_at) "
                    + "VALUES (" + id + ", '[]', 'deadbeef', 0, 0, NOW(6))");
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

        /** 그 표의 컬럼 이름들. 이름으로 재야 컬럼이 늘어도 안 깨진다 (#267). */
        List<String> columns(String table) throws SQLException {
            return query("SELECT column_name FROM information_schema.columns "
                    + "WHERE table_schema = DATABASE() AND table_name = '" + table + "' "
                    + "ORDER BY column_name");
        }

        String dataType(String table, String column) throws SQLException {
            return query("""
                    SELECT data_type FROM information_schema.columns
                    WHERE table_schema = DATABASE() AND table_name = '%s' AND column_name = '%s'
                    """.formatted(table, column)).stream().findFirst().orElse("(컬럼 없음)");
        }

        List<String> foreignKeys() throws SQLException {
            return query("""
                    SELECT constraint_name FROM information_schema.referential_constraints
                    WHERE constraint_schema = DATABASE() AND table_name = 'place_catalog'
                    ORDER BY constraint_name
                    """);
        }

        List<String> checks() throws SQLException {
            return query("""
                    SELECT constraint_name FROM information_schema.table_constraints
                    WHERE constraint_schema = DATABASE() AND constraint_type = 'CHECK'
                      AND table_name = 'place_catalog'
                    ORDER BY constraint_name
                    """);
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
