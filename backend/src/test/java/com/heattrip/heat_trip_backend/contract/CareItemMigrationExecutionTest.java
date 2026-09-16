package com.heattrip.heat_trip_backend.contract;

import com.heattrip.heat_trip_backend.care.entity.CareItem;
import com.heattrip.heat_trip_backend.group.entity.FamilyGroup;
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
 * {@code 50_care_item.sql} 을 <b>실제 MySQL 에 돌려</b> 검증한다 — #560.
 *
 * <h2>왜 실행 테스트인가</h2>
 *
 * <p>이 스크립트가 하는 일 중 셋을 {@code ddl-auto=validate} 도 {@code SchemaDdlDriftTest}
 * 도 안 본다.
 *
 * <ol>
 *   <li><b>FK 의 삭제 규칙 셋.</b> {@code fk_careitem_group} 은 CASCADE 이고
 *       {@code fk_carelog_item}·{@code fk_careitem_dog} 는 SET NULL 이다. 규칙이 뒤집히면
 *       아이 한 마리를 보낸 것이 목록을 지우거나, 항목을 지운 것이 기록을 지운다 —
 *       <b>실제로 지워 봐야</b> 안다.</li>
 *   <li><b>이미 있는 그룹에 기본 일곱.</b> 안 넣으면 마이그레이션 전에 만든 집은 카드가
 *       통째로 빈다.</li>
 *   <li>멱등 — 두 번 돌려도 일곱이 열넷이 되면 안 된다.</li>
 * </ol>
 *
 * <p>그리고 하나 더 — <b>마이그레이션이 넣는 일곱과 {@link CareItem#defaultsFor} 가 같은가.</b>
 * 둘이 갈라지면 마이그레이션으로 세운 집과 새로 만든 집이 서로 다른 목록을 갖는다. 그건
 * 실행 테스트가 아니면 아무도 안 본다.
 *
 * <p>표는 {@code 01_schema.sql} 의 DDL 을 그대로 심되 {@code care_log} 는 이 스크립트가 돌기
 * <b>전</b> 모양이다({@code care_item_id} 없음). 스프링을 띄우지 않는다(#21).
 */
class CareItemMigrationExecutionTest {

    private static final String SCRIPT = "mysql/post-start/50_care_item.sql";

    private static int dbCounter = 0;

    @Test
    @DisplayName("표와 컬럼이 생기고 FK 셋이 제 삭제 규칙으로 걸린다")
    void createsTheTableAndForeignKeys() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true);

            db.runMigration();

            assertThat(db.tables()).contains("care_item");
            assertThat(db.columns("care_log")).contains("care_item_id");
            assertThat(db.nullable("care_log", "care_item_id"))
                    .as("NOT NULL 이면 옛 기록에 채울 값이 없어 마이그레이션 자체가 죽는다")
                    .isEqualTo("YES");
            assertThat(db.foreignKeys("care_item"))
                    .containsExactly("fk_careitem_dog|SET NULL", "fk_careitem_group|CASCADE");
            assertThat(db.foreignKeys("care_log")).contains("fk_carelog_item|SET NULL");
        }
    }

    @Test
    @DisplayName("이미 있던 집에 기본 일곱이 들어간다 — 안 넣으면 그 집 카드가 통째로 빈다")
    void fillsExistingGroups() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true);
            db.seed();

            db.runMigration();

            assertThat(db.itemNames(1)).containsExactly("물", "밥", "산책", "투약", "병원", "배변", "마킹");
            assertThat(db.itemNames(2)).hasSize(7);
        }
    }

    @Test
    @DisplayName("마이그레이션의 일곱이 CareItem.defaultsFor 와 같다 — 갈라지면 집마다 목록이 다르다")
    void migrationMatchesTheCodeDefaults() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true);
            db.seed();
            db.runMigration();

            List<String> fromCode = CareItem.defaultsFor(FamilyGroup.builder().build()).stream()
                    .map(i -> i.getSortOrder() + "|" + i.getName() + "|" + i.getIcon()
                            + "|" + i.getSystemType().wire())
                    .toList();

            assertThat(db.itemRows(1))
                    .as("마이그레이션으로 세운 집과 새로 만든 집이 서로 다른 목록을 갖는다")
                    .isEqualTo(fromCode);
        }
    }

    @Test
    @DisplayName("두 번 돌려도 일곱이다 — 열넷이 되면 카드에 물이 두 칸이다")
    void isIdempotent() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true);
            db.seed();

            db.runMigration();
            db.runMigration();

            assertThat(db.itemNames(1)).hasSize(7);
        }
    }

    @Test
    @DisplayName("사용자가 만든 항목은 재실행이 안 건드린다 — 이름을 고쳐 둔 것도 그대로다")
    void keepsWhatTheHouseChanged() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true);
            db.seed();
            db.runMigration();
            db.exec("UPDATE care_item SET name = '아침밥' WHERE group_id = 1 AND system_type = 'meal'");
            db.exec("INSERT INTO care_item (group_id, name, icon, system_type, sort_order, created_at) "
                    + "VALUES (1, '양치', 'etc', NULL, 7, NOW(6))");

            db.runMigration();

            assertThat(db.itemNames(1))
                    .as("재실행이 고쳐 둔 이름을 되돌리거나 직접 만든 항목을 지우면 안 된다")
                    .containsExactly("물", "아침밥", "산책", "투약", "병원", "배변", "마킹", "양치");
        }
    }

    @Test
    @DisplayName("직접 만든 항목은 여러 개여도 된다 — 유니크는 기본 일곱만 막는다")
    void allowsManyCustomItems() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true);
            db.seed();
            db.runMigration();

            db.exec("INSERT INTO care_item (group_id, name, icon, system_type, sort_order, created_at) "
                    + "VALUES (1, '양치', 'etc', NULL, 7, NOW(6))");
            db.exec("INSERT INTO care_item (group_id, name, icon, system_type, sort_order, created_at) "
                    + "VALUES (1, '빗질', 'etc', NULL, 8, NOW(6))");

            assertThat(db.itemNames(1)).hasSize(9);
            assertThatThrownBy(() -> db.exec(
                    "INSERT INTO care_item (group_id, name, icon, system_type, sort_order, created_at) "
                            + "VALUES (1, '물 또', 'water', 'water', 9, NOW(6))"))
                    .as("같은 종류가 둘이면 카드에 물이 두 칸 뜬다")
                    .isInstanceOf(SQLException.class);
        }
    }

    @Test
    @DisplayName("항목을 지워도 기록은 남는다 — 이름표만 잃는다")
    void deletingAnItemKeepsItsLogs() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true);
            db.seed();
            db.runMigration();
            db.exec("INSERT INTO care_item (id, group_id, name, icon, system_type, sort_order, created_at) "
                    + "VALUES (99, 1, '양치', 'etc', NULL, 7, NOW(6))");
            db.exec("INSERT INTO care_log (id, group_id, care_item_id, type, occurred_at, created_at) "
                    + "VALUES (1, 1, 99, 'etc_placeholder', NOW(6), NOW(6))");

            db.exec("DELETE FROM care_item WHERE id = 99");

            assertThat(db.count("care_log"))
                    .as("CASCADE 였다면 항목 하나를 지운 것이 그 기록을 통째로 지웠을 것이다")
                    .isEqualTo(1);
            assertThat(db.careItemIdOf(1)).isEqualTo("NULL");
        }
    }

    @Test
    @DisplayName("아이를 보내도 항목은 남는다 — dog_id 만 NULL 이 된다")
    void deletingADogKeepsTheItem() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true);
            db.seed();
            db.runMigration();
            db.exec("INSERT INTO care_item (id, group_id, dog_id, name, icon, system_type, sort_order, created_at) "
                    + "VALUES (99, 1, 1, '심장사상충 약', 'med', NULL, 7, NOW(6))");

            db.exec("DELETE FROM dog WHERE id = 1");

            assertThat(db.itemNames(1)).contains("심장사상충 약");
            assertThat(db.dogIdOfItem(99))
                    .as("CASCADE 였다면 아이 한 마리를 보낸 것이 집의 할 일을 지웠을 것이다")
                    .isEqualTo("NULL");
        }
    }

    @Test
    @DisplayName("가족을 해산하면 목록은 사라진다 — 앞으로 할 일은 남길 것이 없다")
    void deletingTheGroupDropsTheList() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(true);
            db.seed();
            db.runMigration();

            db.exec("DELETE FROM family_group WHERE id = 1");

            assertThat(db.itemNames(1)).isEmpty();
        }
    }

    @Test
    @DisplayName("care_log 표가 없으면 아무것도 바꾸기 전에 멈춘다 — 08_care_log.sql 이 먼저다")
    void abortsWhenCareLogIsMissing() throws Exception {
        try (Fixture db = fixture()) {
            db.createTables(false);

            assertThatThrownBy(db::runMigration)
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("08_care_log.sql");
        }
    }

    // ─────────────────────────── 픽스처 ───────────────────────────

    private static Fixture fixture() throws SQLException {
        return new Fixture();
    }

    private static final class Fixture implements AutoCloseable {

        private final String name;
        private final Connection connection;

        Fixture() throws SQLException {
            MySQLContainer<?> mysql = MySqlTestContainer.instance();
            synchronized (CareItemMigrationExecutionTest.class) {
                name = "care_item_test_" + (++dbCounter);
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
         * {@code 01_schema.sql} 대로 — 단 {@code care_log} 는 50 이 돌기 <b>전</b> 모양이다.
         *
         * <p>{@code care_log.type} 의 CHECK 는 안 건다. 이 테스트가 재는 것은 FK 의 삭제
         * 규칙과 씨앗이지 종류 검증이 아니고, CHECK 를 걸면 "항목을 지워도 기록은 남는다"
         * 를 재려고 넣는 한 줄이 그 제약에 먼저 걸린다.
         */
        void createTables(boolean withCareLog) throws SQLException {
            exec("""
                    CREATE TABLE users (
                      id bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
                      email varchar(255) DEFAULT NULL,
                      role varchar(20) NOT NULL,
                      created_at datetime(6) DEFAULT NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
            exec("""
                    CREATE TABLE family_group (
                      created_at datetime(6) NOT NULL,
                      id bigint NOT NULL AUTO_INCREMENT,
                      name varchar(50) NOT NULL,
                      PRIMARY KEY (id)
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
            exec("""
                    CREATE TABLE dog (
                      birth date DEFAULT NULL,
                      neutered bit(1) NOT NULL DEFAULT b'0',
                      created_at datetime(6) NOT NULL,
                      id bigint NOT NULL AUTO_INCREMENT,
                      user_id bigint NOT NULL,
                      size varchar(10) NOT NULL DEFAULT 'small',
                      species varchar(10) NOT NULL DEFAULT 'dog',
                      breed varchar(50) DEFAULT NULL,
                      name varchar(50) NOT NULL,
                      avatar varchar(255) DEFAULT NULL,
                      PRIMARY KEY (id),
                      KEY idx_dog_user (user_id),
                      CONSTRAINT fk_dog_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                    """);
            if (withCareLog) {
                exec("""
                        CREATE TABLE care_log (
                          created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
                          dog_id bigint DEFAULT NULL,
                          done_by bigint DEFAULT NULL,
                          group_id bigint DEFAULT NULL,
                          id bigint NOT NULL AUTO_INCREMENT,
                          occurred_at datetime(6) NOT NULL,
                          type varchar(20) NOT NULL,
                          memo varchar(500) DEFAULT NULL,
                          PRIMARY KEY (id),
                          KEY idx_carelog_group (group_id, occurred_at),
                          KEY idx_carelog_doneby (done_by),
                          KEY idx_carelog_dog (dog_id, occurred_at),
                          CONSTRAINT fk_carelog_dog FOREIGN KEY (dog_id) REFERENCES dog (id) ON DELETE SET NULL,
                          CONSTRAINT fk_carelog_doneby FOREIGN KEY (done_by) REFERENCES users (id) ON DELETE SET NULL,
                          CONSTRAINT fk_carelog_group FOREIGN KEY (group_id) REFERENCES family_group (id) ON DELETE SET NULL
                        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                        """);
            }
        }

        /** 엄마(1)와 가족 둘(보리네 1 · 옆집 2), 엄마가 등록한 보리(1). */
        void seed() throws SQLException {
            exec("INSERT INTO users (id, email, role, created_at) "
                    + "VALUES (1, 'mom@example.com', 'ROLE_USER', NOW(6))");
            exec("INSERT INTO family_group (id, name, created_at) VALUES (1, '보리네', NOW(6))");
            exec("INSERT INTO family_group (id, name, created_at) VALUES (2, '옆집', NOW(6))");
            exec("INSERT INTO dog (id, user_id, name, size, species, neutered, created_at) "
                    + "VALUES (1, 1, '보리', 'small', 'dog', 0, NOW(6))");
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

        List<String> tables() throws SQLException {
            return query("SELECT table_name FROM information_schema.tables "
                    + "WHERE table_schema = DATABASE() ORDER BY table_name");
        }

        List<String> columns(String table) throws SQLException {
            return query("SELECT column_name FROM information_schema.columns "
                    + "WHERE table_schema = DATABASE() AND table_name = '" + table + "' "
                    + "ORDER BY column_name");
        }

        String nullable(String table, String column) throws SQLException {
            return query("SELECT is_nullable FROM information_schema.columns "
                    + "WHERE table_schema = DATABASE() AND table_name = '" + table + "' "
                    + "AND column_name = '" + column + "'").stream()
                    .findFirst().orElse("(없음)");
        }

        /** {@code 이름|삭제규칙} — 그 표에서 나가는 FK 전부. */
        List<String> foreignKeys(String table) throws SQLException {
            return query("SELECT CONCAT(constraint_name, '|', delete_rule) "
                    + "FROM information_schema.referential_constraints "
                    + "WHERE constraint_schema = DATABASE() AND table_name = '" + table + "' "
                    + "ORDER BY constraint_name");
        }

        List<String> itemNames(long groupId) throws SQLException {
            return query("SELECT name FROM care_item WHERE group_id = " + groupId
                    + " ORDER BY sort_order, id");
        }

        /** {@code 순서|이름|아이콘|종류} — 코드의 기본값과 글자까지 대조하려는 모양. */
        List<String> itemRows(long groupId) throws SQLException {
            return query("SELECT CONCAT(sort_order, '|', name, '|', icon, '|', system_type) "
                    + "FROM care_item WHERE group_id = " + groupId
                    + " AND system_type IS NOT NULL ORDER BY sort_order, id");
        }

        String careItemIdOf(long logId) throws SQLException {
            return query("SELECT IFNULL(care_item_id, 'NULL') FROM care_log WHERE id = " + logId)
                    .stream().findFirst().orElse("(없음)");
        }

        String dogIdOfItem(long itemId) throws SQLException {
            return query("SELECT IFNULL(dog_id, 'NULL') FROM care_item WHERE id = " + itemId)
                    .stream().findFirst().orElse("(없음)");
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
