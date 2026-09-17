package com.heattrip.heat_trip_backend.support;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.stream.Collectors;

import javax.sql.DataSource;

import com.heattrip.heat_trip_backend.consent.ConsentKind;
import com.heattrip.heat_trip_backend.consent.entity.UserConsent;
import com.heattrip.heat_trip_backend.consent.repository.UserConsentRepository;
import com.heattrip.heat_trip_backend.user.entity.User;

import org.springframework.beans.factory.annotation.Autowired;
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

    /**
     * {@link #consented(User)} 가 쓰는 저장소. 스프링 컨텍스트가 없는 하위 클래스에서는
     * 주입되지 않으므로 {@code required = false} 다 — 그런 테스트는 이 메서드를 부르지 않는다.
     */
    @Autowired(required = false)
    private UserConsentRepository consentRowsForTests;

    /**
     * 시드한 사용자를 <b>필수 약관에 동의한 평범한 사용자</b>로 만든다 — 이슈 #660.
     *
     * <pre>
     *   User user = consented(users.save(User.builder()... .build()));
     * </pre>
     *
     * <h2>왜 이것이 필요해졌나</h2>
     *
     * <p>2026-09-18 부터 서버가 동의를 강제한다({@code security.ConsentRequiredFilter}). 동의하지
     * 않은 토큰으로 {@code /api/**} 를 부르면 403 이다. 그런데 통합 테스트의 시드 사용자는
     * {@code users} 행만 만들고 동의는 남기지 않았다 — 그래서 이 필터를 넣자 <b>455건이 빨간불</b>이
     * 됐다.
     *
     * <p>그 빨간불은 <b>버그가 아니라 사실</b>이다: 지금까지 모든 인증 API 가 동의 없이 열려 있었다는
     * 것을 테스트가 그대로 보여 준 것이다. 그러니 고칠 곳은 필터가 아니라 <b>시드</b>다 — 실제
     * 사용자는 동의 화면을 지나야 여기까지 온다.
     *
     * <h2>전부에 자동으로 걸지 않는 이유</h2>
     *
     * <p>"모든 시드 사용자를 자동으로 동의시킨다" 로 만들면 편하지만, 그러면
     * <b>동의하지 않은 사용자를 만들 방법이 사라진다</b> — {@code ConsentRequiredIntegrationTest} 가
     * 재는 것이 바로 그 상태다. 자물쇠를 재는 테스트가 자물쇠를 못 만드는 셈이 된다. 그래서
     * 손으로 부른다.
     *
     * @return 받은 사용자 그대로. 시드 한 줄을 감싸 쓸 수 있게 돌려준다
     */
    protected <T extends User> T consented(T user) {
        LocalDateTime now = LocalDateTime.now(ZoneOffset.UTC);
        List<UserConsent> rows = new ArrayList<>();
        // MARKETING 은 선택이라 안 적는다 — 필수만 채워야 "필수만 봐야 한다" 가 함께 잠긴다.
        for (ConsentKind kind : List.of(ConsentKind.TERMS, ConsentKind.PRIVACY, ConsentKind.LOCATION)) {
            rows.add(UserConsent.builder()
                    .userId(user.getId())
                    .kind(kind.name())
                    .version("v1.0")
                    .agreed(true)
                    .createdAt(now)
                    .build());
        }
        consentRowsForTests.saveAll(rows);
        return user;
    }

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
