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

import com.heattrip.heat_trip_backend.care.entity.CareType;
import com.heattrip.heat_trip_backend.support.MySqlTestContainer;
import com.heattrip.heat_trip_backend.support.TestProjectPaths;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.testcontainers.containers.MySQLContainer;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * {@code 29_care_type_poop.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — 이슈 #340.
 *
 * <h2>왜 실행까지 하나</h2>
 * <p>이 스크립트가 고치는 것은 표도 컬럼도 아닌 <b>CHECK 제약 하나</b>다. 그런데
 * {@code ddl-auto=validate} 는 CHECK 를 보지 않는다 — 안 돌린 DB 에서도 <b>부팅은 그대로
 * 뜬다.</b> 그러고 나서 사용자가 산책 중에 배변 버튼을 누르는 순간 INSERT 가 거절되고,
 * 로그에는 제약 이름만 남는다.
 *
 * <p>즉 "안 돌렸다" 를 알려 주는 장치가 배포 경로에 하나도 없다. 그래서 여기서
 * <b>08 만 돌린 DB 가 {@code poop} 을 거절하는 것</b>과 <b>29 를 돌린 DB 가 받는 것</b>을
 * 나란히 잰다 — 이 스크립트가 실제로 일하는지를 보는 유일한 자리다.
 *
 * <p>스프링을 띄우지 않는다. 공유 컨테이너 안에 테스트마다 별도 데이터베이스를 만든다(#21).
 * {@code CareSchemaMigrationExecutionTest}(08)와 같은 지그다.
 */
class CareTypePoopMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/29_care_type_poop.sql";
    private static final String CARE_LOG = "mysql/post-start/08_care_log.sql";
    private static final String PARENTS = "mysql/post-start/07_family_group.sql";
    private static final String RUNBOOK = "mysql/README.md";

    /** 데이터베이스 이름 충돌을 피하기 위한 카운터. 컨테이너 하나를 여러 테스트가 공유한다. */
    private static int dbCounter = 0;

    // ─────────────────────────── 테스트 ───────────────────────────

    @Test
    @DisplayName("08 만 돌린 DB 는 poop 을 거절한다 — 29 를 돌리면 받는다")
    void beforeTheScript_poopIsRejected_afterwardsItIsAccepted() throws Exception {
        try (Fixture db = fixture()) {
            db.createCareLog();

            assertThatThrownBy(() -> db.insertCare("poop"))
                    .as("""
                            이 줄이 초록이 아니면 스크립트가 필요 없다는 뜻이다 — 08 의 CHECK 가 \
                            다섯만 받는 것이 이 마이그레이션의 존재 이유다.""")
                    .isInstanceOf(SQLException.class);

            db.runMigration();

            db.insertCare("poop");
            db.insertCare("pee");

            assertThat(db.query("SELECT type FROM care_log ORDER BY type"))
                    .as("배변과 마킹을 나눠 세야 '오늘 몇 번' 이 뜻을 가진다")
                    .containsExactly("pee", "poop");
        }
    }

    @Test
    @DisplayName("넓힌 것이지 연 것이 아니다 — 모르는 값은 그대로 거절한다")
    void unknownTypes_areStillRejected() throws Exception {
        try (Fixture db = fixture()) {
            db.createCareLog();
            db.runMigration();

            assertThatThrownBy(() -> db.insertCare("grooming"))
                    .as("""
                            제약을 아예 없애는 선택도 있었지만 그러면 오타 하나가 조용히 저장된다. \
                            그 값을 읽는 화면은 칸 하나가 비어 보이는 것으로만 알려 준다 \
                            (📌 #86 원칙 5 — 마지막 방어선은 DB).""")
                    .isInstanceOf(SQLException.class);
        }
    }

    @Test
    @DisplayName("대소문자는 DB 가 못 가른다 — 소문자 한 벌을 지키는 것은 CareType.of 의 400 이다")
    void theCheckIsCaseInsensitive_soSpellingIsGuardedByTheApplication() throws Exception {
        try (Fixture db = fixture()) {
            db.createCareLog();

            // 이 스크립트가 만든 성질이 아니다 — 08 만 돌린 DB 에서도 대문자가 들어간다.
            // 컬럼 콜레이션이 utf8mb4_0900_ai_ci(대소문자 구분 없음)라 CHECK 의 IN 이 같게 본다.
            db.insertCare("MEAL");
            db.runMigration();
            db.insertCare("POOP");

            assertThat(db.query("SELECT type FROM care_log ORDER BY type"))
                    .as("실측이다 — 2026-09-07 에 'POOP' 이 CHECK 를 그냥 통과했다")
                    .containsExactly("MEAL", "POOP");

            assertThat(CareType.of("poop")).isEqualTo(CareType.POOP);
            assertThatThrownBy(() -> CareType.of("POOP"))
                    .as("""
                            표기가 한 벌인 것은 DB 가 아니라 여기서 지킨다. 손으로 INSERT 하면                             대문자가 들어갈 수 있고, 그때 그 행은 앱의 tryParse 에서 null 이 돼                             카드 한 칸이 빈다 — 콜레이션을 바꾸는 것은 이 이슈의 일이 아니라서                             여기에 사실만 적어 둔다.""")
                    .isInstanceOf(IllegalArgumentException.class);
        }
    }

    @Test
    @DisplayName("enum 의 일곱 값이 전부 들어간다 — 넓히다 하나를 흘리면 오늘 쓰는 기록이 내일 막힌다")
    void everyCareType_fitsTheWidenedCheck() throws Exception {
        try (Fixture db = fixture()) {
            db.createCareLog();
            db.runMigration();

            for (CareType type : CareType.values()) {
                db.insertCare(type.wire());
            }

            assertThat(db.query("SELECT COUNT(*) FROM care_log"))
                    .as("enum 에서 값을 읽는다 — 여기 목록을 손으로 적으면 다음에 늘릴 때 또 갈린다")
                    .containsExactly(String.valueOf(CareType.values().length));
        }
    }

    @Test
    @DisplayName("쌓인 행이 있어도 넓히기가 성공하고 행 수는 그대로다")
    void existingRows_surviveTheWidening() throws Exception {
        try (Fixture db = fixture()) {
            db.createCareLog();
            db.insertCare("meal");
            db.insertCare("walk");

            db.runMigration();

            assertThat(db.query("SELECT COUNT(*) FROM care_log"))
                    .as("제약을 갈아 끼우는 동안 행을 잃으면 '어제 밥 줬다' 가 사라진다")
                    .containsExactly("2");
        }
    }

    @Test
    @DisplayName("두 번 돌려도 성공한다 — 재실행이 안전하다")
    void migration_isIdempotentAgainstRealMySql() throws Exception {
        try (Fixture db = fixture()) {
            db.createCareLog();
            db.runMigration();
            db.runMigration();   // 이미 일곱 값이면 DROP CHECK 를 건너뛴다

            db.insertCare("poop");
            assertThat(db.query("SELECT type FROM care_log")).containsExactly("poop");
        }
    }

    @Test
    @DisplayName("care_log 가 없으면 중단한다 — 08 을 건너뛴 DB 에 사람 말로 알려 준다")
    void withoutCareLog_itAborts() throws Exception {
        try (Fixture db = fixture()) {
            assertThatThrownBy(db::runMigration)
                    .as("""
                            제약만 고치는 스크립트라 표가 없으면 할 일이 없다. 조용히 성공하면 \
                            런북을 순서대로 돌린 사람이 08 을 건너뛴 것을 모른다.""")
                    .isInstanceOf(SQLException.class);
        }
    }

    @Test
    @DisplayName("런북(mysql/README.md)이 이 파일의 실행 커맨드를 담고 있다")
    void runbook_listsThisScript() throws Exception {
        String runbook = Files.readString(
                TestProjectPaths.requireFile(RUNBOOK), StandardCharsets.UTF_8);

        assertThat(runbook)
                .as("실행 순서에 없는 스크립트는 아무도 돌리지 않는다 — 그러면 배포 뒤 첫 배변 기록이 "
                        + "실패하고, 부팅은 멀쩡해서 아무도 원인을 못 짚는다")
                .contains("post-start\\29_care_type_poop.sql");
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
            synchronized (CareTypePoopMigrationExecutionTest.class) {
                name = "care_type_mig_test_" + (++dbCounter);
            }
            // 앱 계정에는 CREATE DATABASE 권한이 없다 — root 로 붙는다.
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
         * 이 스크립트가 고칠 표를 <b>저장소의 07·08 을 그대로 돌려</b> 세운다.
         *
         * <p>베껴 쓰면 08 의 CHECK 가 바뀌어도 여기는 초록불이라, 이 테스트의 첫 단언
         * ("08 만 돌린 DB 는 poop 을 거절한다")이 거짓이 된다.
         */
        void createCareLog() throws Exception {
            runScript(PARENTS);
            exec("""
                    CREATE TABLE users (
                        id   BIGINT      NOT NULL AUTO_INCREMENT PRIMARY KEY,
                        role VARCHAR(20) NOT NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
            runScript(CARE_LOG);
            exec("INSERT INTO users (id, role) VALUES (1, 'ROLE_USER')");
        }

        void insertCare(String type) throws SQLException {
            exec("INSERT INTO care_log (type, done_by, occurred_at, created_at) "
                    + "VALUES ('" + type + "', 1, NOW(6), NOW(6))");
        }

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
