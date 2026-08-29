package com.heattrip.heat_trip_backend.support;

import static org.assertj.core.api.Assertions.assertThat;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.LinkedHashMap;
import java.util.Map;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.testcontainers.containers.MySQLContainer;

/**
 * 테스트 컨테이너 설정이 {@code docker-compose.yml} 과 갈라지면 실패하는 장치.
 *
 * <p>이슈 #26 의 함정: compose 의 mysql 은 기본값이 아닌 서버 플래그로 뜬다. 그중
 * {@code --innodb-ft-min-token-size=2} 가 없으면 "카페" 같은 2글자 한국어 FULLTEXT 검색이
 * <b>예외 없이 0건</b>을 반환한다. 그러면 {@link com.heattrip.heat_trip_backend.explore.web.ExploreSearchSqlLogTest}
 * 가 "통과는 하는데 아무것도 못 잡는" 상태가 된다.</p>
 *
 * <p>그래서 세 지점을 묶어 검사한다.</p>
 * <ol>
 *   <li>compose 의 mysql 서비스 정의</li>
 *   <li>{@link MySqlServerSpec} 상수 — 테스트 컨테이너가 쓰는 값</li>
 *   <li>실제로 떠 있는 컨테이너의 {@code SHOW VARIABLES} 결과</li>
 * </ol>
 * <p>어느 하나라도 어긋나면 여기서 빨간불이 난다.</p>
 */
class MySqlComposeParityTest {

    @Test
    @DisplayName("컨테이너 이미지가 compose 의 mysql 이미지와 같다")
    void imageMatchesCompose() {
        DockerComposeMysqlService compose = DockerComposeMysqlService.read();

        assertThat(compose.image())
                .as("docker-compose.yml 의 mysql 이미지와 MySqlServerSpec.IMAGE 가 갈라졌다. "
                        + "테스트가 운영과 다른 MySQL 버전을 검증하게 된다.")
                .isEqualTo(MySqlServerSpec.IMAGE);
    }

    @Test
    @DisplayName("서버 플래그가 compose 의 mysqld command 와 순서까지 같다")
    void mysqldFlagsMatchCompose() {
        DockerComposeMysqlService compose = DockerComposeMysqlService.read();

        assertThat(compose.mysqldFlags())
                .as("docker-compose.yml 의 mysqld 플래그와 MySqlServerSpec.MYSQLD_FLAGS 가 갈라졌다. "
                        + "특히 --innodb-ft-min-token-size 가 다르면 2글자 한국어 FULLTEXT 검색이 "
                        + "예외 없이 0건이 되어, 되살린 테스트가 아무것도 검증하지 못한다.")
                .containsExactlyElementsOf(MySqlServerSpec.MYSQLD_FLAGS);
    }

    @Test
    @DisplayName("떠 있는 컨테이너가 실제로 그 플래그 값으로 동작한다")
    void runningContainerReportsExpectedVariables() throws Exception {
        Map<String, String> expected = MySqlServerSpec.expectedServerVariables();
        Map<String, String> actual = readServerVariables(expected.keySet());

        assertThat(actual)
                .as("플래그를 넘긴 것과 서버가 그 값으로 뜬 것은 다른 문제다. "
                        + "SHOW VARIABLES 결과가 기대와 다르면 컨테이너가 기본값으로 돌고 있는 것이다.")
                .containsExactlyInAnyOrderEntriesOf(expected);
    }

    private static Map<String, String> readServerVariables(Iterable<String> names) throws Exception {
        MySQLContainer<?> mysql = MySqlTestContainer.instance();
        Map<String, String> values = new LinkedHashMap<>();
        try (Connection connection = DriverManager.getConnection(
                mysql.getJdbcUrl(), mysql.getUsername(), mysql.getPassword())) {
            for (String name : names) {
                try (PreparedStatement ps = connection.prepareStatement("SHOW VARIABLES LIKE ?")) {
                    ps.setString(1, name);
                    try (ResultSet rs = ps.executeQuery()) {
                        if (rs.next()) {
                            values.put(rs.getString(1), rs.getString(2));
                        }
                    }
                }
            }
        }
        return values;
    }
}
