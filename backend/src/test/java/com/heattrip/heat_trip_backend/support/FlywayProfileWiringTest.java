package com.heattrip.heat_trip_backend.support;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 프로필이 Flyway 를 <b>실제로 그렇게 켜 두었는가</b> — 이슈 #592.
 *
 * <h2>왜 따로 재나</h2>
 *
 * <p>{@link FlywayBuildsTheSchemaTest} 는 Flyway 를 <b>코드에서 직접 조립해</b> 돌린다
 * ({@code baselineOnMigrate(true)} 를 손으로 준다). 그래서 동작은 보증하지만 <b>설정 파일은 한
 * 글자도 안 본다.</b> 누군가 {@code application-prod.properties} 의 값을 바꿔도 그 검사는 초록이다.
 *
 * <p>그 구멍이 특히 위험한 이유는, 틀렸을 때 <b>운영에서만</b> 드러나기 때문이다.
 *
 * <ul>
 *   <li>{@code baseline-on-migrate=false} → 자료가 든 DB 에 {@code V1} 을 다시 돌리려 들고
 *       {@code CREATE TABLE} 이 터진다. <b>부팅 실패</b>
 *   <li>{@code enabled=false} → 마이그레이션이 조용히 안 돈다. 다음 배포가
 *       {@code validate} 로 죽는다
 *   <li>dev 가 {@code update} 로 돌아가면 → 옛 표에 컬럼을 몰래 얹어 마이그레이션을 막는다.
 *       그 사고가 실제로 있었다
 * </ul>
 *
 * <p>그래서 여기서는 <b>파일에 적힌 글자</b>를 읽는다.
 */
class FlywayProfileWiringTest {

    private static final Path RESOURCES =
            TestProjectPaths.backendDir().resolve("src/main/resources");

    @Test
    @DisplayName("dev·prod 둘 다 Flyway 가 켜져 있고 기준점 규칙이 같다")
    void bothProfilesRunFlyway() {
        for (String profile : new String[] {"dev", "prod"}) {
            String text = read(RESOURCES.resolve("application-%s.properties".formatted(profile)));

            assertThat(text)
                    .as("%s: Flyway 가 안 켜져 있다 — 마이그레이션이 조용히 안 돈다", profile)
                    .contains("spring.flyway.enabled=${SPRING_FLYWAY_ENABLED:true}");
            assertThat(text)
                    .as("""
                            %s: baseline-on-migrate 가 없다 — 자료가 든 DB 에 V1 을 다시 돌리려 들고 \
                            CREATE TABLE 이 터진다(부팅 실패).""", profile)
                    .contains("spring.flyway.baseline-on-migrate=true");
            assertThat(text)
                    .as("%s: 기준점 번호가 없다", profile)
                    .contains("spring.flyway.baseline-version=1");
            assertThat(text)
                    .as("%s: 적용된 파일이 바뀌어도 그냥 뜨게 된다 — V 파일은 고치는 것이 아니다", profile)
                    .contains("spring.flyway.validate-on-migrate=true");
        }
    }

    @Test
    @DisplayName("dev 도 validate 다 — update 로 돌아가지 않았다")
    void devNoLongerLetsHibernateChangeTables() {
        String dev = read(RESOURCES.resolve("application-dev.properties"));

        assertThat(dev)
                .as("""
                        dev 가 ddl-auto=update 로 돌아갔다. 그러면 Hibernate 가 옛 표에 컬럼·FK 를 \
                        몰래 얹어 마이그레이션을 막는다 — prod 는 validate 라 죽지만 dev 는 조용히 \
                        망가진다. 둘은 같은 경로여야 한다.""")
                .contains("spring.jpa.hibernate.ddl-auto=${SPRING_JPA_HIBERNATE_DDL_AUTO:validate}")
                .doesNotContain("SPRING_JPA_HIBERNATE_DDL_AUTO:update");
    }

    @Test
    @DisplayName("테스트에서는 꺼 둔다 — 엔티티가 만든 표와 겹치지 않게")
    void testsKeepItOff() {
        String test = read(TestProjectPaths.backendDir()
                .resolve("src/test/resources/application-test.properties"));

        assertThat(test)
                .as("""
                        테스트에서 Flyway 를 켜면 ddl-auto=create-drop 이 만든 표와 겹친다. \
                        빈 DB 경로는 FlywayBuildsTheSchemaTest 가 컨테이너를 따로 띄워 잰다.""")
                .contains("spring.flyway.enabled=false");
    }

    private static String read(Path path) {
        try {
            return Files.readString(path, StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException("읽지 못했다: " + path, e);
        }
    }
}
