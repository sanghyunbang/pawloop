package com.heattrip.heat_trip_backend.support;

import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.utility.DockerImageName;

/**
 * 테스트 전체가 공유하는 MySQL 8.0 컨테이너 하나.
 *
 * <h2>왜 {@code @Container} 가 아니라 싱글턴인가</h2>
 * <p>{@code @Testcontainers} + {@code @Container} 는 (static 이어도) <b>테스트 클래스마다</b>
 * 라이프사이클을 관리한다. MySQL 기동은 수 초가 들고, 이슈 #22 가 "CI 실행 시간 PR당 5분 이내"를
 * 걸어 두었다. 그래서 Testcontainers 문서가 권하는 싱글턴 패턴을 쓴다 —
 * JVM 당 한 번만 뜨고, 여러 테스트 클래스가 같은 인스턴스를 쓴다.</p>
 *
 * <p>{@code stop()} 은 부르지 않는다. Testcontainers 의 Ryuk 사이드카가 JVM 종료 시
 * 컨테이너를 정리한다.</p>
 *
 * <p>Docker 가 없으면 여기서 <b>크게 실패한다</b>. 일부러 그렇게 뒀다. 조용히 건너뛰면
 * FULLTEXT 검색 경로가 다시 "CI 에서 한 번도 검증되지 않는" 상태로 돌아가는데,
 * 그건 초록불이 거짓말을 하는 형태라 지금보다 나쁘다.</p>
 */
public final class MySqlTestContainer {

    private static final MySQLContainer<?> CONTAINER =
            new MySQLContainer<>(DockerImageName.parse(MySqlServerSpec.IMAGE))
                    .withDatabaseName("heat_trip_test")
                    .withUsername("heattrip")
                    .withPassword("heattrip")
                    // compose 와 같은 서버 플래그. 특히 --innodb-ft-min-token-size=2 가 없으면
                    // 2글자 한국어 FULLTEXT 검색이 조용히 0건이 된다. MySqlServerSpec 참조.
                    .withCommand(MySqlServerSpec.command())
                    // 한글 시드/검색어가 커넥션 단계에서 깨지지 않도록 명시한다.
                    .withUrlParam("characterEncoding", "UTF-8");

    static {
        CONTAINER.start();
    }

    /** 이미 기동된 공유 컨테이너. */
    public static MySQLContainer<?> instance() {
        return CONTAINER;
    }

    private MySqlTestContainer() {
    }
}
