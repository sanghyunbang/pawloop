package com.heattrip.heat_trip_backend.contract;

import com.heattrip.heat_trip_backend.support.TestProjectPaths;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 못 쓰는 데이터가 저장소에 들어오지 않았는지 — 이슈 #346 완료 조건 3.
 *
 * <h2>왜 검사로 잠그나</h2>
 * <p><b>서울시 둘레길 선형 위치정보</b>({@code OA-11986})는 공공누리 <b>제4유형</b>이다 —
 * 출처표시 + <b>상업적 이용금지</b> + <b>변경금지</b>. 우리는 상업 앱이고, 좌표계를 WGS84 로
 * 바꾸는 것 자체가 "변경" 이라 둘 중 하나만 걸려도 못 쓴다.
 *
 * <p>"안 쓰기로 했다" 는 결정은 문서에만 있으면 반년 뒤에 잊힌다. 누군가 "서울 산책로가
 * 부족한데 이거 있네" 하고 받아 넣는 순간, <b>오류 없이</b> 라이선스 위반이 된다.
 * {@code docs/02-architecture/external-data.md} 가 스스로 적어 둔 검사가 이것이다 —
 * "{@code grep -r OA-11986} 이 0 이어야 합니다".
 *
 * <h2>문서 한 곳은 예외다</h2>
 * <p>그 결정을 <b>설명하는</b> 문서에는 식별자가 나와야 한다. 그것까지 막으면 왜 안 쓰는지를
 * 적을 수 없다. 그래서 그 파일 하나만 빼고 나머지 전부를 본다.
 *
 * <p>네트워크도 스프링도 없다(#21).
 */
class RestrictedGeoDataTest {

    /** 공공누리 제4유형 — 상업적 이용금지 + 변경금지. */
    private static final String RESTRICTED_DATASET = "OA-11986";

    /**
     * 식별자가 나와도 되는 두 곳.
     *
     * <ul>
     *   <li>결정을 <b>설명하는</b> 문서 — 여기까지 막으면 왜 안 쓰는지를 적을 수 없다</li>
     *   <li><b>이 테스트 자신</b> — 무엇을 막는지 적으려면 그 이름을 써야 한다</li>
     * </ul>
     *
     * <p>둘 다 <b>이름으로</b> 적는다. 문자열을 쪼개 숨기는 방법(`"OA" + "-11986"`)도 있지만,
     * 그러면 검사가 무엇을 막는지 읽는 사람이 알아보기 어려워진다.
     */
    private static final String EXPLAINER = "docs/02-architecture/external-data.md";

    private static final String SELF =
            "backend/src/test/java/com/heattrip/heat_trip_backend/contract/RestrictedGeoDataTest.java";

    /**
     * 뒤지지 않는 곳 — 빌드 산출물과 의존성. 우리가 커밋한 것이 아니다.
     *
     * <p>{@code .claude} 가 여기 낀 이유는 조금 다르다. 작업용 worktree 가 그 아래 만들어지는데,
     * 그것은 <b>이 저장소의 사본</b>이다. 그래서 이 검사 파일과 설명 문서가 한 벌씩 더 생기고,
     * 경로가 달라 예외 목록에 걸리지 않아 <b>위반으로 잡힌다.</b> 2026-09-16 에 실제로 이것으로
     * 빨간불이 났다 — 받아 온 데이터가 아니라 우리 파일의 사본이었다.
     *
     * <pre>
     * Expecting empty but was: [".claude/worktrees/…/RestrictedGeoDataTest.java",
     *                           ".claude/worktrees/…/docs/02-architecture/external-data.md"]
     * </pre>
     *
     * <p>{@code .gitignore:30} 의 {@code /.claude/worktrees/} 가 이미 무시하는 경로다. "저장소에
     * 들어왔는가" 를 묻는 검사가 볼 곳이 아니다.
     */
    private static final List<String> SKIPPED_DIRS =
            List.of(".git", ".claude", "build", "node_modules", ".gradle", ".dart_tool", "Pods");

    @Test
    @DisplayName("제4유형 데이터가 저장소에 없다 — 설명 문서 한 곳만 예외다")
    void restrictedDatasetIsNotInTheRepository() throws IOException {
        Path root = TestProjectPaths.backendDir().getParent();
        List<String> offenders = new ArrayList<>();

        try (Stream<Path> files = Files.walk(root)) {
            files.filter(Files::isRegularFile)
                    .filter(RestrictedGeoDataTest::isSearchable)
                    .forEach(file -> {
                        String relative = root.relativize(file).toString().replace('\\', '/');
                        if (relative.equals(EXPLAINER) || relative.equals(SELF)) {
                            return;
                        }
                        try {
                            if (Files.readString(file, StandardCharsets.UTF_8)
                                    .contains(RESTRICTED_DATASET)) {
                                offenders.add(relative);
                            }
                        } catch (IOException | RuntimeException notText) {
                            // 텍스트가 아니면 지나간다 — 이 검사는 사람이 적은 글을 본다.
                        }
                    });
        }

        assertThat(offenders)
                .as("""
                        서울시 둘레길 선형(OA-11986)은 공공누리 제4유형이라 못 쓴다 — \
                        상업적 이용금지 + 변경금지. 저장소에 들어오면 오류 없이 위반이 된다. \
                        왜 안 쓰는지는 %s 에 적혀 있다.""", EXPLAINER)
                .isEmpty();
    }

    @Test
    @DisplayName("왜 안 쓰는지는 문서에 남아 있다 — 검사만 있고 이유가 없으면 다음 사람이 지운다")
    void theReasonIsWrittenDown() throws IOException {
        Path doc = TestProjectPaths.backendDir().getParent().resolve(EXPLAINER);
        assertThat(doc).as("이 결정을 설명하는 문서가 사라졌다").exists();
        String text = Files.readString(doc, StandardCharsets.UTF_8);

        assertThat(text).contains(RESTRICTED_DATASET);
        assertThat(text).contains("제4유형");
        assertThat(text).contains("상업적 이용금지");
    }

    private static boolean isSearchable(Path file) {
        for (Path part : file) {
            if (SKIPPED_DIRS.contains(part.toString())) {
                return false;
            }
        }
        String name = file.getFileName().toString().toLowerCase();
        return name.endsWith(".java") || name.endsWith(".dart") || name.endsWith(".md")
                || name.endsWith(".yaml") || name.endsWith(".yml") || name.endsWith(".json")
                || name.endsWith(".sql") || name.endsWith(".py") || name.endsWith(".sh")
                || name.endsWith(".txt") || name.endsWith(".csv") || name.endsWith(".gradle");
    }
}
