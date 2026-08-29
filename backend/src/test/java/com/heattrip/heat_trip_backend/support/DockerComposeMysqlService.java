package com.heattrip.heat_trip_backend.support;

import java.io.IOException;
import java.io.Reader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.List;
import java.util.Map;

import org.yaml.snakeyaml.Yaml;

/**
 * {@code docker-compose.yml} 의 {@code mysql} 서비스 정의를 읽어온다.
 *
 * <p>테스트 컨테이너 설정이 compose 와 갈라졌는지 비교하기 위한 것이므로,
 * 읽기 전용이다. compose 파일은 이 작업의 소유가 아니다.</p>
 */
public record DockerComposeMysqlService(String image, List<String> command) {

    /** compose 의 mysql 서비스를 읽어 값 객체로 만든다. */
    public static DockerComposeMysqlService read() {
        Path composeFile = TestProjectPaths.requireFile(MySqlServerSpec.COMPOSE_FILE);
        Map<String, Object> root = load(composeFile);

        Object servicesNode = root.get("services");
        if (!(servicesNode instanceof Map<?, ?> services)) {
            throw new IllegalStateException(composeFile + " 에 services 블록이 없다.");
        }
        Object serviceNode = services.get(MySqlServerSpec.COMPOSE_SERVICE);
        if (!(serviceNode instanceof Map<?, ?> service)) {
            throw new IllegalStateException(
                    composeFile + " 에 '" + MySqlServerSpec.COMPOSE_SERVICE + "' 서비스가 없다.");
        }

        Object image = service.get("image");
        if (!(image instanceof String imageName)) {
            throw new IllegalStateException("compose 의 mysql 서비스에 image 가 없다.");
        }
        return new DockerComposeMysqlService(imageName.trim(), parseCommand(service.get("command")));
    }

    /** {@code command} 에서 앞의 {@code mysqld} 를 뺀 서버 플래그 목록. */
    public List<String> mysqldFlags() {
        if (command.isEmpty() || !"mysqld".equals(command.get(0))) {
            throw new IllegalStateException(
                    "compose 의 mysql command 가 'mysqld' 로 시작하지 않는다: " + command);
        }
        return command.subList(1, command.size());
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
            throw new IllegalStateException(composeFile + " 를 읽지 못했다.", e);
        }
    }

    /**
     * compose 의 {@code command} 는 문자열(shell/folded 형태)일 수도 리스트일 수도 있다.
     * 둘 다 받아 토큰 목록으로 정규화한다.
     */
    private static List<String> parseCommand(Object commandNode) {
        if (commandNode instanceof String text) {
            return Arrays.stream(text.trim().split("\\s+")).filter(s -> !s.isEmpty()).toList();
        }
        if (commandNode instanceof List<?> items) {
            return items.stream().map(String::valueOf).map(String::trim).filter(s -> !s.isEmpty()).toList();
        }
        throw new IllegalStateException(
                "compose 의 mysql 서비스에 command 가 없다. 서버 플래그 없이 뜨면 "
                        + "innodb_ft_min_token_size 가 기본값 3 이 되어 2글자 한국어 검색이 조용히 0건이 된다.");
    }
}
