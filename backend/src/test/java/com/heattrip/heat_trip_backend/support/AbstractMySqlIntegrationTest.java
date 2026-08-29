package com.heattrip.heat_trip_backend.support;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.List;
import java.util.stream.Collectors;

import javax.sql.DataSource;

import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

import org.testcontainers.containers.MySQLContainer;

/**
 * 실제 MySQL 8.0 컨테이너 위에서 도는 통합 테스트의 베이스 클래스.
 *
 * <p>상속하면 Spring 데이터소스가 {@link MySqlTestContainer} 로 갈아끼워진다.
 * {@code src/test/resources/application-test.properties} 의 H2 설정은
 * {@code @DynamicPropertySource} 가 더 높은 우선순위라 여기 값으로 덮인다
 * (그 파일은 이 작업의 소유가 아니라 건드리지 않는다).</p>
 *
 * <p>왜 H2 로는 안 되는가: 검색 쿼리가 {@code MATCH(...) AGAINST (... IN BOOLEAN MODE)} 라는
 * MySQL FULLTEXT 전용 문법을 쓴다. H2 에는 없어서 500 이 났고, 그래서 이슈 #22 가
 * {@code @Tag("mysql")} 로 격리해 뒀다. 이슈 #26 이 그 격리를 걷어낸다.</p>
 */
public abstract class AbstractMySqlIntegrationTest {

    @DynamicPropertySource
    static void mysqlProperties(DynamicPropertyRegistry registry) {
        MySQLContainer<?> mysql = MySqlTestContainer.instance();
        registry.add("spring.datasource.url", mysql::getJdbcUrl);
        registry.add("spring.datasource.username", mysql::getUsername);
        registry.add("spring.datasource.password", mysql::getPassword);
        registry.add("spring.datasource.driver-class-name", mysql::getDriverClassName);
        registry.add("spring.jpa.database-platform", () -> "org.hibernate.dialect.MySQLDialect");
        // 스키마 전체 DDL 이 리포지토리에 없어서(운영 mysql/init 은 커밋되지 않는다)
        // 엔티티에서 만든다. FULLTEXT 인덱스는 Hibernate 가 만들어 주지 않으므로
        // 운영과 같은 스크립트를 따로 적용한다 — applyOperationalSqlScript(...) 참조.
        registry.add("spring.jpa.hibernate.ddl-auto", () -> "create-drop");
    }

    /**
     * 리포지토리에 있는 <b>운영 SQL 스크립트</b>를 그대로 컨테이너에 적용한다.
     *
     * <p>테스트용으로 DDL 을 따로 베껴 쓰지 않는 이유: 베껴 쓰면 운영 스크립트가 깨져도
     * 테스트는 초록불이다. 같은 파일을 돌려야 스크립트가 깨졌을 때 CI 가 잡는다.</p>
     *
     * <p>{@code PREPARE}/{@code EXECUTE} 와 세션 변수({@code SET @x := ...})를 쓰는
     * 스크립트가 있어서 모든 문장을 <b>한 커넥션</b>에서 순서대로 실행한다.</p>
     *
     * @param dataSource        대상 데이터소스
     * @param relativeScriptPath backend 루트 기준 스크립트 경로
     */
    protected static void applyOperationalSqlScript(DataSource dataSource, String relativeScriptPath) {
        Path script = TestProjectPaths.requireFile(relativeScriptPath);
        List<String> statements = splitStatements(readScript(script));
        if (statements.isEmpty()) {
            throw new IllegalStateException(script + " 에 실행할 문장이 없다.");
        }
        try (var connection = dataSource.getConnection();
             var statement = connection.createStatement()) {
            for (String sql : statements) {
                statement.execute(sql);
            }
        } catch (Exception e) {
            throw new IllegalStateException("운영 SQL 스크립트 적용 실패: " + script, e);
        }
    }

    private static String readScript(Path script) {
        try {
            return Files.readString(script, StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new IllegalStateException(script + " 를 읽지 못했다.", e);
        }
    }

    /**
     * 세미콜론으로 문장을 나눈다. 이 스크립트들에는 문자열 리터럴 안에 세미콜론이 없어서
     * 단순 분리로 충분하다. 줄 주석({@code -- }, {@code #})은 먼저 걷어낸다.
     */
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
