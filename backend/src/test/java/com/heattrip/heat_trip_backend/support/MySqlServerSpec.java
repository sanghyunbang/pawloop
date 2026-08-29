package com.heattrip.heat_trip_backend.support;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 테스트용 MySQL 컨테이너가 떠야 하는 <b>단 하나의</b> 사양 정의.
 *
 * <p>이 값들은 {@code backend/docker-compose.yml} 의 {@code mysql} 서비스와 반드시 같아야 한다.
 * 갈라지면 {@link MySqlComposeParityTest} 가 실패한다. 주석으로 "맞춰두세요"라고 적어두는 대신
 * 테스트가 강제한다.</p>
 *
 * <h2>왜 기본값으로 띄우면 안 되는가</h2>
 * <p>{@code --innodb-ft-min-token-size} 의 MySQL 기본값은 3이다. InnoDB FULLTEXT 인덱스는
 * 이 값보다 짧은 토큰을 <b>아예 색인하지 않고</b>, BOOLEAN MODE 검색어도 같은 기준으로 버린다.
 * 기본값으로 띄우면 "카페" 같은 2글자 한국어 키워드 검색이 예외 없이 <b>조용히 0건</b>을 반환한다.
 * 그러면 {@code MATCH ... AGAINST} 를 검증하려는 테스트가 "통과는 하는데 아무것도 못 잡는"
 * 상태가 된다 — H2 로 돌리던 예전보다 나쁘다. 이슈 #26 참조.</p>
 */
public final class MySqlServerSpec {

    /** compose 의 mysql 서비스와 같은 이미지. */
    public static final String IMAGE = "mysql:8.0";

    /** compose 파일 경로(backend 루트 기준)와 그 안에서 비교할 서비스 이름. */
    public static final String COMPOSE_FILE = "docker-compose.yml";
    public static final String COMPOSE_SERVICE = "mysql";

    /**
     * mysqld 서버 플래그. compose 의 {@code command:} 와 순서까지 같아야 한다.
     *
     * <p>순서를 포함해 비교하는 이유: 같은 플래그가 두 번 나오면 MySQL 은 뒤의 값을 쓴다.
     * 순서를 무시하고 집합으로만 비교하면 그 차이를 놓친다.</p>
     */
    public static final List<String> MYSQLD_FLAGS = List.of(
            "--character-set-server=utf8mb4",
            "--collation-server=utf8mb4_0900_ai_ci",
            "--max_allowed_packet=16777216",
            "--innodb-ft-min-token-size=2");

    /**
     * 플래그가 실제로 서버에 먹었는지 확인할 때 쓰는 (시스템 변수 → 기대값) 표.
     *
     * <p>플래그를 넘기는 것과 서버가 그 값으로 뜨는 것은 다른 문제다. 살아 있는 서버에
     * {@code SHOW VARIABLES} 로 되물어야 "넘겼다고 믿었는데 안 먹은" 경우를 잡는다.</p>
     */
    public static Map<String, String> expectedServerVariables() {
        Map<String, String> expected = new LinkedHashMap<>();
        for (String flag : MYSQLD_FLAGS) {
            int eq = flag.indexOf('=');
            if (eq < 0) {
                throw new IllegalStateException(
                        "값이 없는 서버 플래그는 SHOW VARIABLES 로 확인할 수 없다: " + flag);
            }
            String name = flag.substring("--".length(), eq).replace('-', '_');
            expected.put(name, flag.substring(eq + 1));
        }
        return expected;
    }

    /** Testcontainers 의 {@code withCommand(...)} 에 넘길 명령. compose 와 같은 형태. */
    public static String[] command() {
        List<String> command = new ArrayList<>();
        command.add("mysqld");
        command.addAll(MYSQLD_FLAGS);
        return command.toArray(String[]::new);
    }

    private MySqlServerSpec() {
    }
}
