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
import java.util.Map;
import java.util.stream.Collectors;

import com.heattrip.heat_trip_backend.support.MySqlTestContainer;
import com.heattrip.heat_trip_backend.support.TestProjectPaths;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.testcontainers.containers.MySQLContainer;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * {@code 04_users_social_account_model.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — 이슈 #26 후속(#7).
 *
 * <h2>왜 필요한가</h2>
 * <p>{@link UserSchemaMigrationSpecTest} 는 파일이 제자리에 있는지, 핵심 문장이 남아 있는지만
 * 본다. 그건 <b>텍스트 드리프트</b>를 잡지 스크립트가 실제로 무엇을 하는지는 모른다.
 * 특히 백필 파싱 규칙({@code SUBSTRING_INDEX}/{@code LOCATE})은 지금까지
 * <b>CI 가 한 번도 검증하지 않았다</b> — 사람이 손으로 컨테이너를 띄워 확인했을 뿐이다.
 * 그 확인은 저장소에 남지 않으므로 다음 사람에게는 없는 것과 같다.
 *
 * <h2>왜 스프링을 띄우지 않는가</h2>
 * <p>이 테스트가 필요로 하는 것은 <b>레거시 스키마</b>다 — {@code provider}/{@code social_id}/
 * {@code role} 이 <b>없고</b> {@code username} 과 {@code NOT NULL} 인 {@code email} 만 있는
 * 마이그레이션 <i>이전</i> 모양. JPA 엔티티가 만드는 스키마는 이미 마이그레이션 <i>이후</i>라
 * 쓸 수 없다. 그래서 공유 컨테이너 안에 <b>테스트마다 별도 데이터베이스</b>를 만들고
 * 레거시 테이블을 손으로 세운 뒤 스크립트를 돌린다. 스프링 컨텍스트가 필요 없으므로
 * {@code AbstractMySqlIntegrationTest} 도 상속하지 않는다(그건 데이터소스를 갈아끼우는 용도다).
 *
 * <p>스크립트는 저장소의 <b>운영 파일 그대로</b>를 읽어 실행한다. 테스트용으로 베껴 쓰면
 * 운영 스크립트가 깨져도 초록불이다.
 */
class UserSchemaMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/04_users_social_account_model.sql";

    /** 데이터베이스 이름 충돌을 피하기 위한 카운터. 컨테이너 하나를 여러 테스트가 공유한다. */
    private static int dbCounter = 0;

    // ─────────────────────────── 테스트 ───────────────────────────

    @Test
    @DisplayName("레거시 username 을 (provider, social_id) 로 정확히 쪼갠다 — 구글 sub 의 '_' 도 살린다")
    void backfill_splitsLegacyUsername() throws Exception {
        try (Fixture db = legacyFixture()) {
            db.insertLegacyUser(1, "kakao_1234567890", "a@example.com");
            db.insertLegacyUser(2, "google_1_2_3", "b@example.com");   // sub 안에 '_' 가 더 있다
            db.insertLegacyUser(3, "naver_n-1", "c@example.com");
            db.insertLegacyUser(4, "bori", "d@example.com");            // '_' 없음 → local
            db.insertLegacyUser(5, "unknown_9", "e@example.com");       // 모르는 공급자 → local

            db.runMigration();

            assertThat(db.socialKeys())
                    .as("첫 '_' 앞이 provider, 뒤가 통째로 social_id 다. 'google_1_2_3' 을 "
                            + "('google','1') 로 자르면 구글 계정이 서로 충돌한다")
                    .containsExactly(
                            Map.entry("kakao", "1234567890"),
                            Map.entry("google", "1_2_3"),
                            Map.entry("naver", "n-1"),
                            Map.entry("local", ""),
                            Map.entry("local", ""));
        }
    }

    @Test
    @DisplayName("두 번 돌려도 성공한다 — 재실행이 안전하다")
    void migration_isIdempotentAgainstRealMySql() throws Exception {
        try (Fixture db = legacyFixture()) {
            db.insertLegacyUser(1, "kakao_1234567890", "a@example.com");

            db.runMigration();
            db.runMigration();   // 여기서 ERROR 1060(중복 컬럼) 이 나면 실패한다

            assertThat(db.socialKeys()).containsExactly(Map.entry("kakao", "1234567890"));
        }
    }

    @Test
    @DisplayName("같은 (provider, social_id) 를 두 번 넣으면 DB 가 거부한다 — 완료 조건 5")
    void uniqueConstraint_isEnforcedByTheDatabase() throws Exception {
        try (Fixture db = legacyFixture()) {
            db.insertLegacyUser(1, "kakao_1234567890", "a@example.com");
            db.runMigration();

            assertThatThrownBy(() -> db.exec(
                    "INSERT INTO users (id, username, email, provider, social_id, role) "
                            + "VALUES (99, 'x', 'x@example.com', 'kakao', '1234567890', 'ROLE_USER')"))
                    .as("코드의 조합 규칙이 아니라 DB 가 막아야 한 소셜 계정 = 한 행이 보장된다")
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("Duplicate entry");
        }
    }

    @Test
    @DisplayName("이메일이 없는 계정을 여럿 만들 수 있다 — UNIQUE 인덱스에서 NULL 은 서로 다른 값이다")
    void nullEmails_doNotCollide() throws Exception {
        try (Fixture db = legacyFixture()) {
            db.insertLegacyUser(1, "kakao_1", "a@example.com");
            db.runMigration();

            // 카카오 이메일 미동의자가 여럿 생기는 상황. email 이 UNIQUE 인데도 NULL 은 충돌하지 않는다.
            db.exec("INSERT INTO users (id, username, email, provider, social_id, role) "
                    + "VALUES (10, 'k10', NULL, 'kakao', '10', 'ROLE_USER')");
            db.exec("INSERT INTO users (id, username, email, provider, social_id, role) "
                    + "VALUES (11, 'k11', NULL, 'kakao', '11', 'ROLE_USER')");

            assertThat(db.count("SELECT COUNT(*) FROM users WHERE email IS NULL")).isEqualTo(2);
        }
    }

    @Test
    @DisplayName("중복 소셜 계정이 있으면 users 를 한 글자도 바꾸지 않고 중단한다")
    void duplicateSocialAccounts_abortBeforeTouchingUsers() throws Exception {
        try (Fixture db = legacyFixture()) {
            db.insertLegacyUser(1, "kakao_1234567890", "a@example.com");
            db.insertLegacyUser(2, "kakao_1234567890", "b@example.com");   // 같은 소셜 계정 두 행

            assertThatThrownBy(db::runMigration)
                    .as("제약을 못 거는 데이터를 만나면 아무것도 바꾸기 전에 멈춰야 한다")
                    .isInstanceOf(SQLException.class);

            assertThat(db.columnNames())
                    .as("중단했는데 컬럼이 생겼다면 '반쯤 적용된' 상태다 — 되돌릴 수 없다")
                    .doesNotContain("provider", "social_id", "role");
            assertThat(db.isEmailNullable())
                    .as("email 도 건드리지 않아야 한다")
                    .isFalse();
        }
    }

    @Test
    @DisplayName("social_id 가 191자를 넘으면 중단한다 — 잘라서 저장하지 않는다")
    void oversizedSocialId_aborts() throws Exception {
        try (Fixture db = legacyFixture()) {
            db.insertLegacyUser(1, "kakao_" + "9".repeat(200), "a@example.com");

            assertThatThrownBy(db::runMigration)
                    .as("그냥 통과시키면 그 행이 다음 문장에서 provider='local' 로 잘못 표시된다")
                    .isInstanceOf(SQLException.class);

            assertThat(db.columnNames()).doesNotContain("provider");
        }
    }

    @Test
    @DisplayName("컬럼만 있고 제약이 없는 '반쯤 적용된' DB 에서도 중복을 잡아낸다")
    void halfAppliedDatabase_isStillGuarded() throws Exception {
        try (Fixture db = legacyFixture()) {
            // 지난번 실행이 A(컬럼 추가)까지만 하고 C(제약)에서 죽은 상태를 흉내낸다.
            db.exec("ALTER TABLE users ADD COLUMN provider VARCHAR(20) NULL");
            db.exec("ALTER TABLE users ADD COLUMN social_id VARCHAR(191) NULL");
            db.exec("ALTER TABLE users ADD COLUMN role VARCHAR(20) NOT NULL DEFAULT 'ROLE_USER'");
            db.exec("INSERT INTO users (id, username, email, provider, social_id, role) "
                    + "VALUES (1, 'k1', 'a@example.com', 'kakao', '999', 'ROLE_USER')");
            db.exec("INSERT INTO users (id, username, email, provider, social_id, role) "
                    + "VALUES (2, 'k2', 'b@example.com', 'kakao', '999', 'ROLE_USER')");

            assertThatThrownBy(db::runMigration)
                    .as("이미 들어와 있는 중복도 사전 점검이 봐야 한다")
                    .isInstanceOf(SQLException.class);
        }
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private static Fixture legacyFixture() throws SQLException {
        return new Fixture();
    }

    /**
     * 공유 컨테이너 안의 <b>일회용 데이터베이스</b> 하나. 마이그레이션 이전 모양의
     * {@code users} 테이블을 세워 둔다. {@link #close()} 가 데이터베이스를 통째로 지운다.
     */
    private static final class Fixture implements AutoCloseable {

        private final String name;
        private final Connection connection;

        Fixture() throws SQLException {
            MySQLContainer<?> mysql = MySqlTestContainer.instance();
            synchronized (UserSchemaMigrationExecutionTest.class) {
                name = "mig_test_" + (++dbCounter);
            }
            // 앱 계정(heattrip)에는 CREATE DATABASE 권한이 없다 — Testcontainers 는 지정한
            // 데이터베이스에만 권한을 준다("Access denied for user 'heattrip'@'%' to database ..." 로
            // 실측 확인). 일회용 DB 를 만들어야 하므로 root 로 붙는다. MySQLContainer 는
            // MYSQL_ROOT_PASSWORD 를 getPassword() 와 같은 값으로 준다.
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

            // 마이그레이션 '이전' 모양 — provider·social_id·role 이 없고 email 이 NOT NULL 이다.
            exec("""
                CREATE TABLE users (
                    id       BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
                    username VARCHAR(255) NULL,
                    email    VARCHAR(255) NOT NULL,
                    CONSTRAINT UK_email UNIQUE (email)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                """);
        }

        void insertLegacyUser(int id, String username, String email) throws SQLException {
            exec("INSERT INTO users (id, username, email) VALUES ("
                    + id + ", '" + username + "', '" + email + "')");
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

        void exec(String sql) throws SQLException {
            try (Statement st = connection.createStatement()) {
                st.execute(sql);
            }
        }

        /** id 순으로 (provider, social_id) 를 모은다. social_id 가 NULL 이면 빈 문자열. */
        List<Map.Entry<String, String>> socialKeys() throws SQLException {
            List<Map.Entry<String, String>> out = new ArrayList<>();
            try (Statement st = connection.createStatement();
                 ResultSet rs = st.executeQuery(
                         "SELECT provider, COALESCE(social_id, '') FROM users ORDER BY id")) {
                while (rs.next()) {
                    out.add(Map.entry(rs.getString(1), rs.getString(2)));
                }
            }
            return out;
        }

        List<String> columnNames() throws SQLException {
            List<String> out = new ArrayList<>();
            try (Statement st = connection.createStatement();
                 ResultSet rs = st.executeQuery("SHOW COLUMNS FROM users")) {
                while (rs.next()) {
                    out.add(rs.getString(1));
                }
            }
            return out;
        }

        boolean isEmailNullable() throws SQLException {
            try (Statement st = connection.createStatement();
                 ResultSet rs = st.executeQuery(
                         "SELECT IS_NULLABLE FROM information_schema.columns "
                                 + "WHERE table_schema = DATABASE() AND table_name = 'users' "
                                 + "AND column_name = 'email'")) {
                return rs.next() && "YES".equals(rs.getString(1));
            }
        }

        int count(String sql) throws SQLException {
            try (Statement st = connection.createStatement(); ResultSet rs = st.executeQuery(sql)) {
                return rs.next() ? rs.getInt(1) : -1;
            }
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
     * 세미콜론으로 문장을 나눈다. 줄 주석({@code --}, {@code #})은 먼저 걷어낸다.
     *
     * <p>이 스크립트의 임시 프로시저 본문은 문장 하나뿐이라 단순 분리로 충분하다.
     * 본문에 세미콜론이 여럿인 프로시저가 생기면 이 분리기부터 고쳐야 한다.
     */
    private static List<String> splitStatements(String script) {
        String withoutComments = Arrays.stream(script.split("\\R"))
                .map(String::strip)
                .filter(line -> !line.startsWith("--") && !line.startsWith("#"))
                .collect(Collectors.joining("\n"));
        return Arrays.stream(withoutComments.split(";"))
                .map(String::strip)
                .filter(s -> !s.isEmpty())
                .toList();
    }
}
