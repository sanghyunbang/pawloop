package com.heattrip.heat_trip_backend.support;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.DatabaseMetaData;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Stream;

import javax.sql.DataSource;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 통합 테스트가 <b>실제 MySQL</b> 위에서 도는지 잠근다 — 이슈 #49.
 *
 * <h2>왜 이 테스트가 있나</h2>
 * <p>예전에는 {@code application-test.properties} 의 H2({@code MODE=MySQL})가 모든
 * 스프링 테스트의 기본 데이터소스였고, 실 MySQL 을 쓰는 것은 검색 테스트 한 클래스뿐이었다.
 * H2 는 근사치다 — FULLTEXT {@code MATCH ... AGAINST}, 공간 함수, 콜레이션·대소문자 규칙,
 * {@code information_schema} 의 세부가 전부 다르다. 그 위에서 초록불이 나도
 * 운영에서 같은 결과가 나온다는 보장이 없다.</p>
 *
 * <p>이 테스트는 두 가지를 본다.</p>
 * <ol>
 *   <li><b>실행 중인 데이터소스가 정말 MySQL 인가</b> — 드라이버가 아니라
 *       살아 있는 커넥션의 {@link DatabaseMetaData} 에게 직접 묻는다.</li>
 *   <li><b>새로 생긴 스프링 테스트가 베이스 클래스를 빼먹지 않았는가</b> — 소스를 훑어
 *       {@code @SpringBootTest}/{@code @DataJpaTest} 를 쓰면서
 *       {@link AbstractMySqlIntegrationTest} 를 상속하지 않은 클래스를 찾는다.</li>
 * </ol>
 *
 * <p>2번이 없으면 다음 사람이 베이스 클래스를 잊었을 때 <b>조용히 H2 로 돌아간다</b>.
 * 그건 초록불이 거짓말을 하는 형태라 가장 나쁘다.</p>
 */
@SpringBootTest
@AutoConfigureMockMvc
class IntegrationTestsRunOnMySqlTest extends AbstractMySqlIntegrationTest {

    @Autowired
    private DataSource dataSource;

    @Test
    @DisplayName("살아 있는 커넥션이 붙어 있는 곳은 H2 가 아니라 실제 MySQL 8 이다")
    void dataSource_isRealMySql() throws Exception {
        try (var connection = dataSource.getConnection()) {
            DatabaseMetaData meta = connection.getMetaData();

            assertThat(meta.getDatabaseProductName())
                    .as("드라이버 설정이 아니라 실제로 붙은 서버에게 물었다. H2 면 여기서 걸린다")
                    .isEqualTo("MySQL");
            assertThat(meta.getDatabaseMajorVersion())
                    .as("운영과 같은 메이저 버전이어야 문법·함수 차이가 의미를 갖는다")
                    .isEqualTo(8);
        }
    }

    @Test
    @DisplayName("2글자 한국어 FULLTEXT 검색이 가능한 서버 설정이다 — H2 로는 표현조차 안 되는 것")
    void server_supportsShortTokenFulltext() throws Exception {
        try (var connection = dataSource.getConnection();
             var statement = connection.createStatement();
             var rs = statement.executeQuery("SHOW VARIABLES LIKE 'innodb_ft_min_token_size'")) {

            assertThat(rs.next()).as("MySQL 이 아니면 이 변수 자체가 없다").isTrue();
            assertThat(rs.getString(2))
                    .as("compose 와 같은 값이어야 한다. 3 이면 '카페' 같은 2글자 검색이 조용히 0건이 된다")
                    .isEqualTo("2");
        }
    }

    @Test
    @DisplayName("스프링 컨텍스트를 띄우는 모든 테스트가 MySQL 베이스 클래스를 상속한다")
    void everySpringTest_extendsTheMySqlBase() throws IOException {
        Path testRoot = TestProjectPaths.requireDirectory("src/test/java");
        List<String> offenders = new ArrayList<>();

        try (Stream<Path> files = Files.walk(testRoot)) {
            for (Path file : files.filter(p -> p.toString().endsWith(".java")).toList()) {
                String source = Files.readString(file, StandardCharsets.UTF_8);
                boolean bootsSpring = source.contains("@SpringBootTest") || source.contains("@DataJpaTest");
                boolean extendsBase = source.contains("extends AbstractMySqlIntegrationTest");
                // 베이스 클래스 자신과, 애너테이션을 문자열로만 언급하는 파일은 뺀다.
                boolean isBaseItself = file.getFileName().toString().equals("AbstractMySqlIntegrationTest.java");
                boolean onlyMentions = !source.contains("\n@SpringBootTest") && !source.contains("\n@DataJpaTest");

                if (bootsSpring && !extendsBase && !isBaseItself && !onlyMentions) {
                    offenders.add(testRoot.relativize(file).toString());
                }
            }
        }

        assertThat(offenders)
                .as("상속을 빼먹으면 그 테스트만 조용히 다른 DB 로 돈다. 실 MySQL 로 통일한 이유가 사라진다 (#49)")
                .isEmpty();
    }
}
