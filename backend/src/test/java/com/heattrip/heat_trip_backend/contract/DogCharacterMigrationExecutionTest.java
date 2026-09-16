package com.heattrip.heat_trip_backend.contract;

import com.heattrip.heat_trip_backend.dog.entity.PetCharacter;
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
 * {@code 52_dog_character.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — #585.
 *
 * <h2>왜 실행 테스트인가</h2>
 *
 * <ol>
 *   <li><b>옛 행을 안 건드리는가.</b> 칸만 더하는 변경이라 이미 등록한 아이의 이름 · 사진이
 *       그대로여야 한다 — 그것을 재는 방법은 실제로 넣어 보고 다시 읽는 것뿐이다.</li>
 *   <li><b>사진 칸이 살아 있는가.</b> 두 칸은 함께 살아야 한다(마이그레이션 머리말).</li>
 *   <li><b>고른 값이 실제로 들어가는가.</b> 스무 자 제한이 캐릭터 열쇠말을 자르지 않는지도
 *       여기서 잰다 — 목록 중 가장 긴 것을 넣어 본다.</li>
 *   <li>멱등 — 두 번 돌려도 같은 상태여야 한다.</li>
 * </ol>
 *
 * <p>스프링을 띄우지 않는다(#21).
 */
class DogCharacterMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/52_dog_character.sql";

    private static int dbCounter = 0;

    @Test
    @DisplayName("칸이 생기고 널을 받는다 — 안 그러면 새 서버가 아예 안 뜬다")
    void theColumnAppears() throws Exception {
        try (Fixture db = new Fixture()) {
            db.createDog();
            assertThat(db.columns("dog")).doesNotContain("character_key");

            db.runMigration();

            assertThat(db.columns("dog")).contains("character_key");
            assertThat(db.nullable("dog", "character_key"))
                    .as("안 고른 아이가 대부분이다 — NOT NULL 이면 기존 행이 못 들어간다")
                    .isEqualTo("YES");
        }
    }

    @Test
    @DisplayName("이미 등록한 아이를 한 줄도 안 건드린다 — 이름도 사진도 그대로다")
    void theExistingRowsAreUntouched() throws Exception {
        try (Fixture db = new Fixture()) {
            db.createDog();
            db.exec("INSERT INTO dog (id, user_id, name, size, species, neutered, avatar, created_at) "
                    + "VALUES (1, 7, '보리', 'small', 'dog', 0, 'profiles/7/bori.jpg', NOW(6))");

            db.runMigration();

            assertThat(db.one("SELECT name FROM dog WHERE id = 1")).isEqualTo("보리");
            assertThat(db.one("SELECT avatar FROM dog WHERE id = 1"))
                    .as("사진 칸을 건드리면 올려 둔 사진이 사라진다")
                    .isEqualTo("profiles/7/bori.jpg");
            assertThat(db.one("SELECT IFNULL(character_key, 'NULL') FROM dog WHERE id = 1"))
                    .as("옛 행은 안 고른 것이다 — 화면이 지금과 똑같아야 한다")
                    .isEqualTo("NULL");
        }
    }

    @Test
    @DisplayName("제일 긴 열쇠말도 안 잘린다 — VARCHAR(20) 이 목록을 담는다")
    void theLongestKeyFits() throws Exception {
        try (Fixture db = new Fixture()) {
            db.createDog();
            db.runMigration();

            String longest = Arrays.stream(PetCharacter.values())
                    .map(PetCharacter::wire)
                    .max((a, b) -> Integer.compare(a.length(), b.length()))
                    .orElseThrow();

            db.exec("INSERT INTO dog (id, user_id, name, size, species, neutered, character_key, created_at) "
                    + "VALUES (2, 7, '뭉치', 'small', 'dog', 0, '" + longest + "', NOW(6))");

            assertThat(db.one("SELECT character_key FROM dog WHERE id = 2"))
                    .as("잘리면 앱이 모르는 값으로 읽어 기본 그림으로 떨어진다 — 조용한 실패다")
                    .isEqualTo(longest);
        }
    }

    @Test
    @DisplayName("두 번 돌려도 같다 — 멱등")
    void isIdempotent() throws Exception {
        try (Fixture db = new Fixture()) {
            db.createDog();
            db.runMigration();
            db.runMigration();

            assertThat(db.columns("dog").stream().filter("character_key"::equals).count())
                    .isEqualTo(1);
        }
    }

    @Test
    @DisplayName("dog 표가 없으면 아무것도 바꾸기 전에 멈춘다 — 07 이 먼저다")
    void abortsWhenDogIsMissing() throws Exception {
        try (Fixture db = new Fixture()) {
            assertThatThrownBy(db::runMigration).hasMessageContaining("07_dog.sql");
        }
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private static final class Fixture implements AutoCloseable {

        private final String name;
        private final Connection connection;

        Fixture() throws SQLException {
            MySQLContainer<?> mysql = MySqlTestContainer.instance();
            synchronized (DogCharacterMigrationExecutionTest.class) {
                name = "dog_character_test_" + (++dbCounter);
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

        /** {@code 52} 가 돌기 <b>전</b>의 모양. {@code users} FK 는 안 건다 — 이 스크립트가 안 본다. */
        void createDog() throws SQLException {
            exec("""
                    CREATE TABLE dog (
                      birth date DEFAULT NULL,
                      neutered bit(1) NOT NULL DEFAULT b'0',
                      created_at datetime(6) NOT NULL,
                      deleted_at datetime(6) DEFAULT NULL,
                      id bigint NOT NULL AUTO_INCREMENT,
                      user_id bigint NOT NULL,
                      size varchar(10) NOT NULL DEFAULT 'small',
                      species varchar(10) NOT NULL DEFAULT 'dog',
                      breed varchar(50) DEFAULT NULL,
                      name varchar(50) NOT NULL,
                      avatar varchar(255) DEFAULT NULL,
                      PRIMARY KEY (id)
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
                    + "WHERE table_schema = DATABASE() AND table_name = '" + table + "'");
        }

        String nullable(String table, String column) throws SQLException {
            return query("SELECT is_nullable FROM information_schema.columns "
                    + "WHERE table_schema = DATABASE() AND table_name = '" + table + "' "
                    + "AND column_name = '" + column + "'").stream()
                    .findFirst().orElse("(없음)");
        }

        String one(String sql) throws SQLException {
            return query(sql).stream().findFirst().orElse("(없음)");
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

    /** {@code ;} 로 자른다 — 프로시저 본문이 한 줄짜리라 구분자 전환이 없다. */
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
