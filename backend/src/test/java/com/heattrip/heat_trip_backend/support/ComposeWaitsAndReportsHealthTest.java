package com.heattrip.heat_trip_backend.support;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.yaml.snakeyaml.Yaml;

import java.io.IOException;
import java.io.Reader;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/**
 * compose 가 <b>기다리는가</b>, 그리고 <b>건강을 말하는가</b> — 이슈 #601.
 *
 * <h2>기다리기</h2>
 *
 * <p>{@code depends_on: - mysql} 은 <b>컨테이너가 시작됐는지만</b> 본다. 접속을 받을 준비가
 * 됐는지는 안 본다. 그래서 첫 부팅에서 앱이 먼저 붙었다가 Flyway 가
 *
 * <pre>Unable to obtain connection from database: Communications link failure</pre>
 *
 * <p>로 죽고, {@code restart} 로 회복한다. 결과는 맞지만 첫 부팅 로그에 30초와 긴 스택
 * 트레이스가 남는다. 2026-09-16 첫 staging 배포에서 <b>진짜 실패를 이 트레이스 뒤에서 한 번 더
 * 파내야 했다.</b> {@code mysql} 에는 이미 {@code healthcheck} 가 있으니 기다리면 된다.
 *
 * <h2>건강 말하기</h2>
 *
 * <p>도커는 {@code healthcheck} 가 <b>정의된</b> 컨테이너에만 {@code (healthy)} 를 붙인다.
 * 없으면 {@code Up} 만 찍는다 — 그리고 {@code Up} 은 "프로세스가 살아 있다" 까지만 말한다.
 *
 * <pre>
 * NAME               CREATED          STATUS
 * heattrip-backend   4 minutes ago    Up 13 seconds            &lt;- 죽었다 살아나기를 반복 중
 * heattrip-mysql     4 minutes ago    Up 4 minutes (healthy)
 * </pre>
 *
 * <p>앱이 계속 죽고 있다는 것을 {@code CREATED} 와 {@code Up} 의 <b>차이</b>로만 알 수 있었다.
 * 사람이 그 차이를 알아채야 하는 표는 상태 표가 아니다.
 *
 * <h2>서비스마다 재는 이유</h2>
 *
 * <p>앱 하나만 물으면 다음에 붙는 서비스가 같은 구멍으로 들어온다. 그래서 {@code services} 를
 * 훑어 <b>전부</b> 본다 — 새 서비스를 더하는 사람이 여기서 한 번 멈춘다.
 */
class ComposeWaitsAndReportsHealthTest {

    /** prod 에서만 얹는 덧붙임. Caddy 와 DB 볼륨 분리가 여기 있다 (#609). */
    private static final String PROD_COMPOSE_FILE = "docker-compose.prod.yml";

    /**
     * 앱이 <b>두 벌</b>이다 — 블루/그린 (이슈 #787). 둘 다 같은 조건을 지켜야 한다.
     *
     * <p>compose 의 YAML 앵커로 한 벌을 베껴 쓰고 있어서 지금은 자동으로 같지만,
     * <b>앵커를 풀고 한쪽만 고치는 날</b>이 이 검사가 막는 자리다. 배포 중에 green 이
     * 준비 안 된 DB 에 붙어 죽으면, 앞단이 그쪽으로 보내는 순간 서비스가 끊긴다.
     */
    @ParameterizedTest(name = "{0}")
    @ValueSource(strings = {"app-blue", "app-green"})
    @DisplayName("앱 두 벌 다 DB 가 healthy 가 될 때까지 기다린다 — 시작만 기다리지 않는다")
    void appWaitsUntilTheDatabaseIsHealthy(String serviceName) {
        Map<String, Object> app = service(serviceName);

        Object dependsOn = app.get("depends_on");

        assertThat(dependsOn)
                .as("""
                        depends_on 이 목록 형태다. 그러면 컨테이너가 "시작됐다" 까지만 기다리고, \
                        앱이 준비 안 된 DB 에 붙었다 죽는다 (#601).""")
                .isInstanceOf(Map.class);

        Object mysql = ((Map<?, ?>) dependsOn).get("mysql");
        assertThat(mysql).as("depends_on 에 mysql 이 없다").isInstanceOf(Map.class);

        assertThat(((Map<?, ?>) mysql).get("condition"))
                .as("""
                        mysql 에는 healthcheck 가 이미 있다. service_healthy 로 기다리지 않으면 \
                        첫 부팅 로그가 Flyway 스택 트레이스로 덮인다 (#601).""")
                .isEqualTo("service_healthy");
    }

    @Test
    @DisplayName("서비스마다 healthcheck 가 있다 — 없으면 Up 만 찍힌다")
    void everyServiceReportsItsOwnHealth() {
        Map<String, Object> services = services();

        List<String> silent = new ArrayList<>();
        for (Map.Entry<String, Object> entry : services.entrySet()) {
            Object definition = entry.getValue();
            if (!(definition instanceof Map<?, ?> service) || !(service.get("healthcheck") instanceof Map)) {
                silent.add(entry.getKey());
            }
        }

        assertThat(silent)
                .as("""
                        healthcheck 가 없는 서비스는 `docker compose ps` 에 Up 만 찍는다. \
                        죽었다 살아나기를 반복해도 Up 이라, CREATED 와의 차이로만 알 수 있다 (#601).""")
                .isEmpty();
    }

    /**
     * prod 에서만 얹는 덧붙임 파일도 같은 규칙을 받는다 — 이슈 #609.
     *
     * <p>이 검사가 처음에는 {@code docker-compose.yml} 만 읽었다. 그 상태로 prod 덧붙임에
     * Caddy 를 더하면 <b>그 서비스는 검사를 빠져나간다</b> — 바로 위 "서비스마다 재는 이유"
     * 가 말한 그 구멍이, 파일이 늘어나는 축에서 그대로 다시 생긴다.
     */
    @Test
    @DisplayName("prod 덧붙임의 서비스도 healthcheck 를 갖는다")
    void everyProdServiceReportsItsOwnHealth() {
        Map<String, Object> services = servicesOf(PROD_COMPOSE_FILE);

        List<String> silent = new ArrayList<>();
        for (Map.Entry<String, Object> entry : services.entrySet()) {
            Object definition = entry.getValue();
            if (!(definition instanceof Map<?, ?> service)) {
                continue;
            }
            // 덧붙임은 기존 서비스의 일부만 고칠 수 있다. base 에 이미 healthcheck 가 있는
            // 서비스는 여기서 다시 적지 않는다 — 새로 등장한 서비스만 본다.
            if (servicesOf(MySqlServerSpec.COMPOSE_FILE).containsKey(entry.getKey())) {
                continue;
            }
            if (!(service.get("healthcheck") instanceof Map)) {
                silent.add(entry.getKey());
            }
        }

        assertThat(silent)
                .as("""
                        prod 에서만 뜨는 서비스에 healthcheck 가 없다. `docker compose ps` 가 \
                        Up 만 찍어서, 죽었다 살아나기를 반복해도 사람이 알아채기 어렵다 (#601).""")
                .isEmpty();
    }

    /**
     * prod 는 DB 를 서버 디스크가 아니라 별도 EBS 볼륨에 둔다 — 이슈 #609.
     *
     * <p>부팅 스크립트를 고치면 인스턴스가 교체되고 root 볼륨은 사라진다. 이 덧붙임이
     * 없으면 <b>배포할 때마다 DB 가 날아간다.</b> staging 에서 하루에 세 번 날렸다.
     */
    @Test
    @DisplayName("prod 덧붙임이 DB 데이터를 별도 볼륨으로 보낸다")
    void prodPutsTheDatabaseOnItsOwnDisk() {
        Object volumes = load(TestProjectPaths.requireFile(PROD_COMPOSE_FILE)).get("volumes");
        assertThat(volumes).as("prod 덧붙임에 volumes 블록이 없다").isInstanceOf(Map.class);

        Object mysqlData = ((Map<?, ?>) volumes).get("mysql_data");
        assertThat(mysqlData)
                .as("mysql_data 를 다시 정의하지 않는다 — 그러면 DB 가 서버 디스크에 남는다")
                .isInstanceOf(Map.class);

        Object opts = ((Map<?, ?>) mysqlData).get("driver_opts");
        assertThat(opts).as("driver_opts 가 없다 — 저장 위치가 안 바뀐다").isInstanceOf(Map.class);
        assertThat(((Map<?, ?>) opts).get("device"))
                .as("DB 를 별도로 마운트한 디스크(/mnt/data)로 보내지 않는다 (#609)")
                .isEqualTo("/mnt/data/mysql");
    }

    /** compose 의 {@code services} 블록. */
    private static Map<String, Object> services() {
        return servicesOf(MySqlServerSpec.COMPOSE_FILE);
    }

    private static Map<String, Object> servicesOf(String relativePath) {
        Path composeFile = TestProjectPaths.requireFile(relativePath);
        Object servicesNode = load(composeFile).get("services");
        if (!(servicesNode instanceof Map<?, ?> services)) {
            throw new IllegalStateException(composeFile + " 에 services 블록이 없다.");
        }

        Map<String, Object> byName = new LinkedHashMap<>();
        services.forEach((key, value) -> byName.put(String.valueOf(key), value));

        if (byName.isEmpty()) {
            throw new IllegalStateException(
                    composeFile + " 의 services 가 비어 있다 — 훑을 것이 없으면 이 검사는 아무것도 못 지킨다.");
        }
        return byName;
    }

    private static Map<String, Object> service(String name) {
        Object definition = services().get(name);
        if (!(definition instanceof Map<?, ?> service)) {
            throw new IllegalStateException("compose 에 '" + name + "' 서비스가 없다.");
        }
        Map<String, Object> byKey = new LinkedHashMap<>();
        service.forEach((key, value) -> byKey.put(String.valueOf(key), value));
        return byKey;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> load(Path composeFile) {
        try (Reader reader = Files.newBufferedReader(composeFile, StandardCharsets.UTF_8)) {
            Object loaded = new Yaml().load(reader);
            if (!(loaded instanceof Map)) {
                throw new IllegalStateException(composeFile + " 를 YAML 맵으로 읽지 못했다.");
            }
            return (Map<String, Object>) loaded;
        } catch (IOException e) {
            throw new UncheckedIOException("compose 파일을 읽지 못했다: " + composeFile, e);
        }
    }
}
