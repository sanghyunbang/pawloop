package com.heattrip.heat_trip_backend.support;

import java.nio.file.Files;
import java.nio.file.Path;

/**
 * 테스트가 리포지토리 안의 <b>운영 파일</b>(docker-compose.yml, mysql/post-start/*.sql)을
 * 찾을 때 쓰는 경로 해석기.
 *
 * <p>왜 필요한가: 이 프로젝트의 테스트용 MySQL 컨테이너는 compose 의 mysql 서비스와
 * 똑같은 서버 플래그로 떠야 한다(이슈 #26). 그러려면 테스트가 compose 파일을 직접
 * 읽어 비교할 수 있어야 하고, 그 경로가 실행 위치(Gradle / IDE)에 따라 흔들리면 안 된다.</p>
 *
 * <p>{@code user.dir} 에서 시작해 위로 올라가며 {@code docker-compose.yml} 과
 * {@code build.gradle} 이 함께 있는 디렉터리를 찾는다. 저장소 루트에서 실행하는
 * 경우를 위해 각 단계에서 {@code backend} 하위도 함께 본다.</p>
 */
public final class TestProjectPaths {

    private TestProjectPaths() {
    }

    /** backend 모듈 루트. */
    public static Path backendDir() {
        Path start = Path.of(System.getProperty("user.dir")).toAbsolutePath().normalize();
        for (Path cur = start; cur != null; cur = cur.getParent()) {
            if (looksLikeBackendDir(cur)) {
                return cur;
            }
            Path nested = cur.resolve("backend");
            if (looksLikeBackendDir(nested)) {
                return nested;
            }
        }
        throw new IllegalStateException(
                "backend 모듈 디렉터리를 찾지 못했다. user.dir=" + start
                        + " — docker-compose.yml 과 build.gradle 이 함께 있는 디렉터리를 기준으로 찾는다.");
    }

    /**
     * backend 루트 기준 상대 경로를 절대 경로로 바꾼다.
     *
     * <p>파일이 없으면 즉시 실패한다. 조용히 건너뛰면 "통과는 하는데 아무것도 검증하지 않는"
     * 테스트가 되기 때문이다.</p>
     */
    public static Path requireFile(String relativePath) {
        Path resolved = backendDir().resolve(relativePath);
        if (!Files.isRegularFile(resolved)) {
            throw new IllegalStateException(
                    "테스트가 요구하는 리포지토리 파일이 없다: " + resolved
                            + " — 파일이 옮겨졌거나 이름이 바뀌었다면 이 테스트도 함께 고쳐야 한다.");
        }
        return resolved;
    }

    private static boolean looksLikeBackendDir(Path candidate) {
        return Files.isRegularFile(candidate.resolve("docker-compose.yml"))
                && Files.isRegularFile(candidate.resolve("build.gradle"));
    }
}
