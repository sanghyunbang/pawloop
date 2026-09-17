package com.heattrip.heat_trip_backend.support;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.output.OutputFrame;
import org.testcontainers.containers.startupcheck.OneShotStartupCheckStrategy;
import org.testcontainers.utility.MountableFile;

import java.io.IOException;
import java.io.Reader;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Caddy 에게 <b>직접 물어본다</b> — 이슈 #609.
 *
 * <h2>왜 이 검사가 생겼나</h2>
 *
 * <p>2026-09-17 첫 prod 부팅에서 Caddy 컨테이너가 시작하자마자 죽었습니다. 서버는 끝까지
 * 부팅했고({@code cloud-init status: done}) 컨테이너 셋이 전부 {@code Started} 였는데,
 * 80·443 이 조용했습니다.
 *
 * <pre>
 * Error: parsing caddyfile tokens for 'handle': wrong argument count
 *        or unexpected line ending after '/actuator/*', at Caddyfile:38
 * </pre>
 *
 * <p>{@code handle} 은 matcher 를 <b>하나만</b> 받는데 경로 둘을 나열했습니다.
 *
 * <h2>글자를 재는 검사는 내 오답에 동의한다</h2>
 *
 * <p>{@link CaddyIsTheOnlyDoorTest} 가 이렇게 묻고 있었습니다.
 *
 * <pre>assertThat(joined).contains("handle /actuator /actuator/*");</pre>
 *
 * <p><b>제가 틀리게 쓴 그 글자와 정확히 일치했으므로 초록이었습니다.</b> 그 검사는 "이 설정이
 * 올바른가" 가 아니라 "내가 쓴 대로 쓰여 있는가" 를 재고 있었습니다 — 이 저장소가
 * {@code 01_schema.sql} 에서 이미 겪은 것과 같은 모양입니다(정본이 제 오답에 합의한다).
 *
 * <p>그래서 이 검사는 글자를 읽지 않습니다. <b>운영에서 쓰는 그 이미지로 {@code caddy
 * validate} 를 실제로 돌립니다.</b> 문법이 틀리면 여기서 빨간불입니다.
 *
 * <h2>도커가 필요하다</h2>
 *
 * <p>이 저장소의 백엔드 테스트는 이미 Testcontainers 로 MySQL 을 띄우므로 도커는 전제입니다
 * (#26). 이미지 태그는 {@code docker-compose.prod.yml} 에서 읽습니다 — 운영과 다른 버전으로
 * 검사하면 검사의 뜻이 줄어듭니다.
 */
class CaddyfileActuallyParsesTest {

    /** 검사에 쓸 값. 실제 값은 terraform 이 정하고 부팅 스크립트가 {@code .env} 에 써 넣는다. */
    private static final Map<String, String> ENV = Map.of(
            "PAWLOOP_DOMAIN", "api.pawloop.app",
            "ACME_EMAIL", "you@example.com");

    @Test
    @DisplayName("운영에서 쓰는 그 이미지로 caddy validate 가 통과한다")
    void theConfigActuallyParses() {
        Path caddyfile = TestProjectPaths.requireFile("Caddyfile");
        StringBuilder output = new StringBuilder();

        try (GenericContainer<?> caddy = new GenericContainer<>(caddyImage())
                .withCopyFileToContainer(MountableFile.forHostPath(caddyfile), "/etc/caddy/Caddyfile")
                .withEnv(ENV)
                .withCommand("caddy", "validate", "--config", "/etc/caddy/Caddyfile")
                .withStartupCheckStrategy(new OneShotStartupCheckStrategy()
                        .withTimeout(Duration.ofMinutes(2)))
                .withLogConsumer((OutputFrame frame) -> output.append(frame.getUtf8String()))) {

            // OneShotStartupCheckStrategy 는 종료 코드가 0 이 아니면 start() 가 던진다.
            // 그때 메시지만으로는 무엇이 틀렸는지 안 보이므로 로그를 함께 붙여 준다.
            try {
                caddy.start();
            } catch (RuntimeException failed) {
                throw new AssertionError(
                        "caddy validate 가 실패했다. 이대로 배포하면 Caddy 컨테이너가 시작하자마자 "
                                + "죽고, 80·443 이 조용해진다 (#609).\n\n" + output, failed);
            }
        }

        assertThat(output.toString())
                .as("caddy 가 설정을 읽었다고 말하지 않았다 — 검사가 무엇을 본 것인지 알 수 없다")
                .contains("Valid configuration");
    }

    /**
     * 운영이 쓰는 이미지 태그를 {@code docker-compose.prod.yml} 에서 읽는다.
     *
     * <p>여기에 태그를 따로 적으면 compose 를 올릴 때 이 검사만 옛 버전으로 남는다 — 그러면
     * "검사는 통과했는데 서버에서 죽는" 자리가 다시 생긴다.
     */
    private static String caddyImage() {
        Path compose = TestProjectPaths.requireFile("docker-compose.prod.yml");
        try (Reader reader = Files.newBufferedReader(compose, StandardCharsets.UTF_8)) {
            Object loaded = new org.yaml.snakeyaml.Yaml().load(reader);
            if (!(loaded instanceof Map<?, ?> root)) {
                throw new IllegalStateException(compose + " 를 YAML 맵으로 읽지 못했다.");
            }
            Object services = root.get("services");
            if (!(services instanceof Map<?, ?> byName)) {
                throw new IllegalStateException(compose + " 에 services 블록이 없다.");
            }
            Object caddy = byName.get("caddy");
            if (!(caddy instanceof Map<?, ?> service) || !(service.get("image") instanceof String image)) {
                throw new IllegalStateException(
                        compose + " 의 caddy 서비스에 image 가 없다 — 이 검사가 볼 곳이 사라졌다.");
            }
            return image;
        } catch (IOException e) {
            throw new UncheckedIOException("compose 덧붙임을 읽지 못했다: " + compose, e);
        }
    }
}
