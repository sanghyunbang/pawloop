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
 * 그 상태가 문제였다. 그래서 두 가지를 따로 잰다.
 *
 * <ol>
 *   <li>파일이 있고 비어 있지 않다 — 자산이 깨지면 지도가 빈다
 *   <li>{@code .gitignore} 가 그 경로를 <b>예외로 뚫어 두었다</b> — 그래야 클론을 따라간다
 * </ol>
 *
 * <p>둘째가 이 파일의 요점이다. 무시 규칙이 다시 넓어지는 날, 여기가 빨간불이 된다.
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
