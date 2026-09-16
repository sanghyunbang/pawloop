package com.heattrip.heat_trip_backend.support;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 부팅에 쓰는 자산이 <b>클론을 따라가는가</b> — 이슈 #591.
 *
 * <h2>왜 이 검사가 필요했나</h2>
 *
 * <p>{@code backend/.gitignore} 의 {@code **}{@code /src/main/resources/data/**} 가 이 폴더를
 * 통째로 막고 있었다. 파일은 <b>내 기계에만</b> 있었고, 그래서 여기서는 모든 검사가 초록이었다.
 * 새로 클론한 곳에서는 {@code sigungu.json} 이 없어 {@link
 * com.heattrip.heat_trip_backend.user.NeighborhoodCatalog} 가 던지고 <b>스프링 컨텍스트가 통째로
 * 죽는다.</b> EC2 부트스트랩이 {@code git clone} + {@code docker compose up} 이라, 그대로 띄우면
 * 서버가 부팅부터 막힌다.
 *
 * <h2>왜 "파일이 있다" 만으로는 모자라나</h2>
 *
 * <p>내 기계에는 있다. 클래스패스에 있는지만 물으면 <b>이 검사도 같이 초록이 된다</b> — 정확히
 * 그 상태가 문제였다. 그래서 세 가지를 따로 잰다.
 *
 * <ol>
 *   <li>파일이 있고 비어 있지 않다 — 자산이 깨지면 지도가 빈다
 *   <li>{@code .gitignore} 가 그 경로를 <b>예외로 뚫어 두었다</b> — 그래야 클론을 따라간다
 *   <li>{@code .dockerignore} 도 <b>같은 경로를 뚫어 두었다</b> — 그래야 이미지에 들어간다
 * </ol>
 *
 * <h2>관문은 하나가 아니었다 — 이슈 #601</h2>
 *
 * <p>이 검사는 처음에 {@code .gitignore} 만 쟀다. 바로 위 문단에 "EC2 부트스트랩이 {@code git
 * clone} + {@code docker compose up} 이라" 고 적어 두고도 그랬다. 자산이 앱까지 가려면 관문을
 * <b>둘</b> 지나야 한다.
 *
 * <pre>
 * 내 기계 ──.gitignore──&gt; 저장소 ──git clone──&gt; 서버 디스크 ──.dockerignore──&gt; 이미지 ──&gt; 앱
 * </pre>
 *
 * <p>PR #593 이 첫 관문을 뚫었다. 둘째 관문인 {@code backend/.dockerignore} 에는
 * {@code src/main/resources/data/} 가 그대로 남아 있었다 — 그 줄의 주석은 "이 파일들은
 * {@code .gitignore} 로 저장소 밖이라 클론에는 없다" 를 이유로 들고 있었는데, <b>PR #593 이
 * 바로 그 이유를 없앴다.</b> 이유는 사라지고 규칙만 남아, 저장소에 있는 파일을 이미지에서
 * 빼는 줄이 되었다.
 *
 * <p>그래서 2026-09-16 첫 staging 배포에서 앱이 {@code sigungu.json} 을 클래스패스에서 찾지
 * 못하고 컨텍스트째로 죽었다. {@code restart} 가 계속 되살려서 {@code docker compose ps} 에는
 * {@code Up} 으로 보였다.
 *
 * <p>무시 규칙이 어느 쪽에서든 다시 넓어지는 날, 여기가 빨간불이 된다.
 */
class BootAssetsTravelWithTheCloneTest {

    /**
     * 부팅·지도에 쓰는 자산. 경로는 {@code backend/} 기준이다 — {@code .gitignore} 가 그 파일에
     * 있어서 예외 줄도 같은 기준으로 쓴다.
     */
    private static final List<String> ASSETS = List.of(
            "src/main/resources/data/sigungu.json",
            "src/main/resources/data/local_trails.json",
            "src/main/resources/data/playgrounds.json",
            "src/main/resources/data/place_traits.csv");

    @Test
    @DisplayName("자산 파일이 있고 비어 있지 않다")
    void assetsExist() {
        Path backend = TestProjectPaths.backendDir();

        List<String> broken = new ArrayList<>();
        for (String asset : ASSETS) {
            Path path = backend.resolve(asset);
            if (!Files.isRegularFile(path) || sizeOf(path) == 0) {
                broken.add(asset);
            }
        }

        assertThat(broken)
                .as("""
                        없거나 빈 자산이 있다. sigungu.json 이면 앱이 아예 안 뜬다 — \
                        만드는 법은 docs/02-architecture/external-data.md 와 backend/tools/ 에 있다.""")
                .isEmpty();
    }

    @Test
    @DisplayName(".gitignore 가 그 넷을 예외로 뚫어 둔다 — 안 그러면 클론에 안 따라간다")
    void gitignoreLetsThemThrough() {
        Path gitignore = TestProjectPaths.backendDir().resolve(".gitignore");
        assertThat(gitignore).as("backend/.gitignore 가 없다").exists();

        List<String> lines = readLines(gitignore);

        List<String> missing = new ArrayList<>();
        for (String asset : ASSETS) {
            boolean allowed = lines.stream()
                    .map(String::trim)
                    .anyMatch(line -> line.equals("!" + asset));
            if (!allowed) {
                missing.add(asset);
            }
        }

        assertThat(missing)
                .as("""
                        `!<경로>` 예외 줄이 없다. 이 폴더는 통째로 무시되고 있어서, 예외가 없으면 \
                        파일이 이 기계에만 남고 새로 클론한 곳·EC2 에는 없다 (#591).""")
                .isEmpty();
    }

    /**
     * 무시 규칙 자체는 남아 있어야 한다 — 받아 온 원본이나 실험용 덤프까지 들어오면 안 된다.
     *
     * <p>예외를 뚫으면서 규칙을 통째로 지우는 것이 제일 쉬운 실수다. 그러면 다음 사람이 수십 MB
     * 짜리 원본을 무심코 커밋한다.
     */
    @Test
    @DisplayName("폴더를 통째로 여는 것이 아니다 — 무시 규칙은 남아 있다")
    void theBlanketRuleSurvives() {
        List<String> lines = readLines(TestProjectPaths.backendDir().resolve(".gitignore"));

        assertThat(lines.stream().map(String::trim))
                .as("무시 규칙이 사라졌다 — 예외만 두고 규칙을 지우면 덤프가 그대로 들어온다")
                .contains("**/src/main/resources/data/**");
    }

    @Test
    @DisplayName(".dockerignore 도 그 넷을 예외로 뚫어 둔다 — 안 그러면 이미지에 안 들어간다")
    void dockerignoreLetsThemThrough() {
        Path dockerignore = TestProjectPaths.backendDir().resolve(".dockerignore");
        assertThat(dockerignore).as("backend/.dockerignore 가 없다").exists();

        List<String> lines = readLines(dockerignore);

        List<String> missing = new ArrayList<>();
        for (String asset : ASSETS) {
            boolean allowed = lines.stream()
                    .map(String::trim)
                    .anyMatch(line -> line.equals("!" + asset));
            if (!allowed) {
                missing.add(asset);
            }
        }

        assertThat(missing)
                .as("""
                        `!<경로>` 예외 줄이 없다. 파일이 저장소에는 있어도 도커 빌드 컨텍스트에서 \
                        빠져서 이미지에 안 들어간다. 앱은 클래스패스에서 못 찾고 컨텍스트째로 \
                        죽는다 — restart 때문에 `docker compose ps` 에는 Up 으로 보인다 (#601).""")
                .isEmpty();
    }

    /**
     * {@code .gitignore} 쪽과 같은 이유로 무시 규칙 자체는 남아 있어야 한다.
     *
     * <p>여기서는 이유가 하나 더 있다. 받아 온 원본이 이미지에 섞이면 <b>같은 태그의 이미지가
     * 빌드한 기계에 따라 다른 데이터를 담는다.</b> "내 로컬에선 되는데" 가 이미지 레벨에서
     * 재현되는 자리다.
     */
    @Test
    @DisplayName(".dockerignore 도 폴더를 통째로 여는 것이 아니다")
    void theDockerBlanketRuleSurvives() {
        List<String> lines = readLines(TestProjectPaths.backendDir().resolve(".dockerignore"));

        assertThat(lines.stream().map(String::trim))
                .as("""
                        무시 규칙이 사라졌다 — 예외만 두고 규칙을 지우면 커밋하지 않은 덤프가 \
                        빌드한 기계에서만 이미지에 섞여 들어간다""")
                .contains("src/main/resources/data/");
    }

    private static long sizeOf(Path path) {
        try {
            return Files.size(path);
        } catch (IOException e) {
            throw new UncheckedIOException("자산 크기를 못 읽었다: " + path, e);
        }
    }

    private static List<String> readLines(Path path) {
        try {
            return Files.readAllLines(path, StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException("읽지 못했다: " + path, e);
        }
    }
}
