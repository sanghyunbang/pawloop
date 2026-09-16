package com.heattrip.heat_trip_backend.support;

import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.output.MigrateResult;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.utility.DockerImageName;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.LinkedHashSet;
import java.util.Set;
import java.util.TreeSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * <b>빈 DB 에 앱을 올리면 Flyway 가 스키마를 만든다</b> — 이슈 #592.
 *
 * <h2>왜 전용 컨테이너인가</h2>
 *
 * <p>다른 통합 테스트는 {@link AbstractMySqlIntegrationTest} 가 {@code ddl-auto=create-drop} 으로
 * <b>엔티티에서</b> 표를 만든다. 공유 컨테이너에 Flyway 까지 걸면 같은 표를 두 번 만들려 든다.
 * 그래서 여기만 컨테이너를 따로 띄운다 — 몇 초를 더 쓰지만, 이 검사가 재려는 것이 바로
 * <b>"아무것도 없는 곳에서 시작할 때"</b> 라서 그 값을 다른 것과 섞으면 안 된다.
 *
 * <h2>무엇을 지키나</h2>
 *
 * <ol>
 *   <li>빈 DB → {@code V1} 이 <b>실제로 돈다</b>. 표가 생기고 이력이 남는다
 *   <li>표가 이미 있는 DB → <b>안 돌고 기준점만 찍는다</b>. 지금 dev 와 앞으로 옮겨 올 운영이
 *       이 경로다 — 이 PR 로 아무것도 안 바뀌어야 한다
 *   <li>{@code V1} 이 만드는 표가 파일에 적힌 것과 <b>정확히 같다</b>
 * </ol>
 */
class FlywayBuildsTheSchemaTest {

    private static final String MIGRATIONS = "classpath:db/migration";

    /** {@code V1__baseline.sql} 에서 읽는다 — 숫자를 손으로 적으면 파일이 줄어도 초록이 된다. */
    private static final Path BASELINE =
            TestProjectPaths.backendDir().resolve("src/main/resources/db/migration/V1__baseline.sql");

    private static final MySQLContainer<?> MYSQL =
            new MySQLContainer<>(DockerImageName.parse(MySqlServerSpec.IMAGE))
                    .withDatabaseName("flyway_probe")
                    .withUsername("heattrip")
                    .withPassword("heattrip")
                    .withUrlParam("characterEncoding", "UTF-8");

    static {
        MYSQL.start();
    }

    /**
     * 스키마를 만들고 지우므로 <b>root 로 붙는다.</b>
     *
     * <p>컨테이너의 앱 사용자({@code heattrip})는 제 DB 하나에만 권한이 있어서 {@code CREATE
     * DATABASE} 가 "Access denied" 다. Testcontainers 는 root 비밀번호를 같은 값으로 넣는다.
     */
    private static final String ROOT = "root";

    @Test
    @DisplayName("빈 DB 에서 V1 이 돌아 표가 생긴다")
    void emptyDatabaseGetsTheSchema() throws Exception {
        String schema = freshSchema("empty_start");

        MigrateResult result = flywayFor(schema).migrate();

        assertThat(result.migrationsExecuted)
                .as("빈 DB 인데 아무것도 안 돌았다 — 그러면 표가 없는 채로 앱이 뜬다")
                .isEqualTo(1);
        assertThat(tablesIn(schema))
                .as("V1 이 만드는 표와 실제로 생긴 표가 다르다")
                .containsExactlyInAnyOrderElementsOf(tablesDeclaredInBaseline());
    }

    @Test
    @DisplayName("V1 은 지금 엔티티를 담고 있다 — 마지막 마이그레이션까지 들어 있다")
    void baselineIsCurrent() throws Exception {
        String schema = freshSchema("current_check");
        flywayFor(schema).migrate();

        // #585 가 더한 마지막 컬럼. 기준점이 낡으면 새 서버만 옛 스키마로 뜬다.
        assertThat(columnsOf(schema, "dog")).contains("character_key");
        assertThat(tablesIn(schema)).contains("care_item");
    }

    @Test
    @DisplayName("표가 이미 있으면 안 돌고 기준점만 찍는다 — 지금 dev·운영이 이 경로다")
    void populatedDatabaseIsOnlyBaselined() throws Exception {
        String schema = freshSchema("already_there");
        // "이미 쓰고 있는 DB" 를 흉내 낸다. 표 하나면 충분하다 — Flyway 는 비었는지만 본다.
        exec(schema, "CREATE TABLE something_already_here (id BIGINT PRIMARY KEY)");

        MigrateResult result = flywayFor(schema).migrate();

        assertThat(result.migrationsExecuted)
                .as("""
                        이미 쓰고 있는 DB 에 V1 을 다시 돌리면 CREATE TABLE 이 터지거나 \
                        남의 자료를 덮는다. 기준점만 찍고 지나가야 한다.""")
                .isZero();
        assertThat(tablesIn(schema))
                .as("남의 표를 건드렸다")
                .contains("something_already_here");
        assertThat(appliedVersions(schema))
                .as("기준점이 안 찍혔다 — 다음 부팅이 또 V1 을 돌리려 든다")
                .contains("1");
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private static Flyway flywayFor(String schema) {
        return Flyway.configure()
                .dataSource(urlFor(schema), ROOT, MYSQL.getPassword())
                .locations(MIGRATIONS)
                .baselineOnMigrate(true)
                .baselineVersion("1")
                .validateOnMigrate(true)
                .load();
    }

    /** 검사마다 깨끗한 스키마를 하나씩 쓴다 — 앞 검사가 만든 표가 다음 판정을 흐리면 안 된다. */
    private static String freshSchema(String name) throws SQLException {
        try (Connection connection = DriverManager.getConnection(
                     urlFor(MYSQL.getDatabaseName()), ROOT, MYSQL.getPassword());
             Statement statement = connection.createStatement()) {
            statement.execute("DROP DATABASE IF EXISTS `" + name + "`");
            statement.execute("CREATE DATABASE `" + name + "` "
                    + "DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci");
        }
        return name;
    }

    private static String urlFor(String schema) {
        return "jdbc:mysql://%s:%d/%s?characterEncoding=UTF-8&allowPublicKeyRetrieval=true&useSSL=false"
                .formatted(MYSQL.getHost(), MYSQL.getMappedPort(MySQLContainer.MYSQL_PORT), schema);
    }

    private static void exec(String schema, String sql) throws SQLException {
        try (Connection connection =
                     DriverManager.getConnection(urlFor(schema), ROOT, MYSQL.getPassword());
             Statement statement = connection.createStatement()) {
            statement.execute(sql);
        }
    }

    private static Set<String> tablesIn(String schema) throws SQLException {
        return query(schema,
                "SELECT table_name FROM information_schema.tables WHERE table_schema = '" + schema + "'")
                .stream()
                // Flyway 가 스스로 만드는 이력 표는 스키마 비교에서 뺀다.
                .filter(name -> !name.equals("flyway_schema_history"))
                .collect(java.util.stream.Collectors.toCollection(TreeSet::new));
    }

    private static Set<String> columnsOf(String schema, String table) throws SQLException {
        return query(schema, "SELECT column_name FROM information_schema.columns "
                + "WHERE table_schema = '" + schema + "' AND table_name = '" + table + "'");
    }

    private static Set<String> appliedVersions(String schema) throws SQLException {
        return query(schema, "SELECT version FROM flyway_schema_history");
    }

    private static Set<String> query(String schema, String sql) throws SQLException {
        Set<String> rows = new LinkedHashSet<>();
        try (Connection connection =
                     DriverManager.getConnection(urlFor(schema), ROOT, MYSQL.getPassword());
             Statement statement = connection.createStatement();
             ResultSet resultSet = statement.executeQuery(sql)) {
            while (resultSet.next()) {
                rows.add(resultSet.getString(1));
            }
        }
        return rows;
    }

    /** {@code V1__baseline.sql} 이 만드는 표 이름. 숫자를 손으로 적지 않으려고 파일에서 읽는다. */
    private static Set<String> tablesDeclaredInBaseline() {
        Pattern create = Pattern.compile("(?im)^\\s*CREATE TABLE\\s+`?([a-z_]+)`?");
        Matcher matcher = create.matcher(read(BASELINE));
        Set<String> names = new TreeSet<>();
        while (matcher.find()) {
            names.add(matcher.group(1));
        }
        assertThat(names).as("기준점 파일에서 CREATE TABLE 을 하나도 못 읽었다 — 정규식이 늙었다").isNotEmpty();
        return names;
    }

    private static String read(Path path) {
        try {
            return Files.readString(path, StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException("읽지 못했다: " + path, e);
        }
    }
}
