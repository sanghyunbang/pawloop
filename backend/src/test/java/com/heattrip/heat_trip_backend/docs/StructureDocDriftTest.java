package com.heattrip.heat_trip_backend.docs;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;

import com.heattrip.heat_trip_backend.support.TestProjectPaths;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * "구현하는 사람이 베끼는 문서" 가 코드와 갈리는 것을 막는다 — 이슈 #201.
 *
 * <h2>왜 따로 있는가</h2>
 * <p>{@link DocDriftTest} 는 <b>문장</b>이 낡았는지 본다("네이버가 공급자로 남아 있나").
 * 여기는 <b>목록</b>이 빠졌는지 본다 — 패키지 스물둘 중 여덟이 문서에 없었고, 화면 스물다섯 중
 * 절반이 없었다. 문장 검사로는 "없는 것" 을 못 잡는다. 없는 줄은 grep 에 안 걸리기 때문이다.
 *
 * <h2>세는 방법을 테스트가 갖는다</h2>
 * <p>#93 이 "개수를 제목에 박지 말라" 고 했다. 그래서 여기 어디에도 22·25 같은 숫자가 없다.
 * 디렉터리를 실제로 읽어 그 결과를 문서와 대조한다 — 패키지가 늘면 검사도 알아서 늘어난다.
 *
 * <h2>느슨하게 잡는다</h2>
 * <p>"문서에 이 이름이 어딘가 나온다" 까지만 본다. 표의 모양이나 설명의 내용은 안 본다.
 * 더 조이면 문서를 다듬을 때마다 빨간불이 나고, 그런 테스트는 며칠 안에 지워진다.
 * 이 테스트가 지키는 것은 <b>"빠뜨리지 않았다"</b> 하나다.
 *
 * <p>네트워크를 타지 않는다. 저장소 안의 파일만 읽는다.
 */
class StructureDocDriftTest {

    /** 백엔드 기저 패키지. 이 아래 1단 디렉터리가 곧 "패키지 목록" 이다. */
    private static final String BASE_PACKAGE = "src/main/java/com/heattrip/heat_trip_backend";

    /**
     * 시뮬 이동을 <b>현재 동작</b>이라고 말하는 표현들.
     *
     * <p>낱말 "시뮬" 자체는 금지하지 않는다 — {@code monetization.md} 의 "수익 시뮬레이션",
     * {@code setup.md} 의 "iOS 시뮬레이터", 로드맵 M0 의 역사 서술은 전부 정당하다.
     * 잡아야 하는 것은 <b>"지금 그렇게 동작한다"</b> 고 읽히는 표현뿐이다.
     */
    private static final List<String> SIMULATION_AS_PRESENT_TENSE =
            List.of("시뮬 폴백", "시뮬 이동", "더미 시뮬레이션", "시뮬 경로를 그리", "경로 영속화 없음");

    /**
     * 같은 표현을 <b>부정</b>하거나 <b>역사</b>로 말하는 줄. 이건 남아 있어야 하는 문장이다.
     *
     * <p>이 예외가 없으면 "위치 판정 전에는 시뮬 경로를 그리지 않는다" 가 걸린다 — 실제로
     * 걸렸다. 그 문장은 고쳐야 할 거짓이 아니라 <b>왜 판정 전에 지도를 안 만드는지</b>를
     * 설명하는 문장이다. {@code DocDriftTest.DECISION_NOTE} 와 같은 장치다.
     *
     * <p><b>이슈 번호는 여기 넣지 않는다.</b> 처음엔 {@code "#160"} 이 있었는데, 빨간불을
     * 보려고 vision.md 에 "시뮬 폴백" 을 되살렸더니 <b>통과했다</b> — 그 줄이 #160 을
     * 인용하고 있었기 때문이다. 이 기능을 서술하는 줄은 거의 다 그 이슈를 인용하므로,
     * 가장 위험한 자리에 통과증을 주는 셈이었다. 면제는 <b>문장의 모양</b>으로만 준다.
     */
    private static final List<String> NEGATED_OR_HISTORICAL =
            List.of("않는다", "않았다", "없앴", "지웠", "더는", "예전", "그때는");

    /** 현재 동작을 서술하는 문서들. 역사를 적는 로드맵은 여기 없다. */
    private static final List<String> CURRENT_BEHAVIOUR_DOCS = List.of(
            "00-product/vision.md",
            "01-design/feature-spec.md",
            "01-design/information-architecture.md",
            "01-design/user-flows.md",
            "02-architecture/system-overview.md",
            "04-api/api-spec.md",
            "05-build/implementation-status.md",
            "05-build/mvp-scope.md",
            "06-testing/test-checklist.md");

    @Test
    @DisplayName("backend-structure.md 가 실제 패키지를 하나도 빠뜨리지 않는다")
    void backendStructure_namesEveryPackage() {
        String doc = RepositoryDocs.requireDoc("02-architecture/backend-structure.md");
        List<String> missing = new ArrayList<>();

        for (String pkg : subdirectoriesOf(TestProjectPaths.backendDir().resolve(BASE_PACKAGE))) {
            if (!doc.contains(pkg)) {
                missing.add(pkg);
            }
        }

        assertThat(missing)
                .as("""
                        이 문서는 스스로 "현재 실제 코드 구조를 서술한다" 고 선언한다. 그런데 \
                        패키지 여덟이 빠져 있었고(#201) 어떤 테스트도 이 파일을 안 봤다. \
                        새 패키지를 만들었으면 이 문서에도 한 줄 적는다 — 구현하는 사람이 \
                        이 트리를 베낀다.""")
                .isEmpty();
    }

    // "지운 login/ 패키지가 되살아났는지" 를 검사하지 않는 이유
    //
    // 처음엔 doesNotContain("login/") 을 넣으려 했다. 그런데 그 문자열은 이 문서에 정당하게
    // 세 번 나온다 — #110 이 지웠다는 역사 서술 두 줄과, 시큐리티 표의 `/login/**` 경로다.
    // 그대로 뒀으면 첫 실행부터 빨간불이었고, 그런 테스트는 며칠 안에 지워진다.
    // DocDriftTest 의 머리말이 "순진한 grep 이 오탐을 낸다" 고 적은 것과 같은 함정이다.
    //
    // 진짜 위험은 "지운 것이 남는 것" 이 아니라 "있는 것이 빠지는 것" 이었다(패키지 여덟).
    // 그건 바로 위 검사가 잡는다.

    @Test
    @DisplayName("화면 목록 문서 둘이 실제 화면 파일을 하나도 빠뜨리지 않는다")
    void screenDocs_nameEveryScreenFile() {
        List<String> screens = screenFileNames();

        assertThat(screens)
                .as("화면을 하나도 못 찾았다면 아래 단언들이 조용히 통과한다")
                .isNotEmpty();

        for (String docPath : List.of("02-architecture/frontend-structure.md", "01-design/screen-spec.md")) {
            String doc = RepositoryDocs.requireDoc(docPath);
            List<String> missing = screens.stream().filter(name -> !doc.contains(name)).toList();

            assertThat(missing)
                    .as("""
                            %s 가 실제 화면의 절반만 알고 있었다(#201). 문서에 없는 화면은 \
                            없는 것으로 취급되고, 그중 하나가 위치정보법 동의 게이트였다. \
                            화면을 추가했으면 이 표에도 한 줄 적는다.""", docPath)
                    .isEmpty();
        }
    }

    @Test
    @DisplayName("현재 동작을 적는 문서에 시뮬 이동이 살아 있다고 적힌 곳이 없다")
    void currentBehaviourDocs_doNotDescribeTheSimulationAsAlive() {
        List<String> offenders = new ArrayList<>();

        for (String docPath : CURRENT_BEHAVIOUR_DOCS) {
            for (String line : RepositoryDocs.requireDoc(docPath).split("\\R")) {
                if (NEGATED_OR_HISTORICAL.stream().anyMatch(line::contains)) {
                    continue;
                }
                for (String phrase : SIMULATION_AS_PRESENT_TENSE) {
                    if (line.contains(phrase)) {
                        offenders.add(docPath + " — " + phrase);
                    }
                }
            }
        }

        assertThat(offenders)
                .as("""
                        #160 이 코드에서 가짜 경로를 지웠는데 문서 열셋이 안 따라왔다(#201). \
                        지금 동작은 이렇다 — 위치를 못 쓰는 여섯 경우를 구분해 이유를 말하는 \
                        화면을 띄우고 직접 입력으로 넘긴다. 그리고 끝내면 walk.path 에 남는다. \
                        역사를 적는 문서(로드맵 M0)는 이 목록에 없다 — 거기서는 옛 동작을 \
                        적는 것이 맞다.""")
                .isEmpty();
    }

    @Test
    @DisplayName("도메인 문서가 자기 컨트롤러의 엔드포인트를 하나도 빠뜨리지 않는다")
    void domainDocs_nameEveryEndpointOfTheirController() {
        record Pair(String doc, String controller) {
        }
        List<Pair> pairs = List.of(
                new Pair("02-architecture/backend/walks.md", BASE_PACKAGE + "/walk/controller/WalkController.java"),
                new Pair("02-architecture/backend/dogs.md", BASE_PACKAGE + "/dog/controller/DogController.java"));

        List<String> missing = new ArrayList<>();
        for (Pair pair : pairs) {
            String doc = RepositoryDocs.requireDoc(pair.doc());
            List<String> endpoints = endpointsOf(TestProjectPaths.backendDir().resolve(pair.controller()));

            assertThat(endpoints)
                    .as("%s 에서 매핑을 하나도 못 읽었다 — 그러면 이 검사는 아무것도 안 지킨다", pair.controller())
                    .isNotEmpty();

            for (String endpoint : endpoints) {
                if (!doc.contains(endpoint)) {
                    missing.add(pair.doc() + " — " + endpoint);
                }
            }
        }

        assertThat(missing)
                .as("""
                        walks.md 는 넷을 적는데 컨트롤러에는 여섯이 있었다 — 메모 수정(#187)과 \
                        삭제가 문서에 없었다(#201). 문서에 없는 엔드포인트는 앱이 안 쓰고 지나간다. \
                        반대 방향(문서에는 있는데 구현이 없는 것)은 GeneratedOpenApiSpecTest 가 \
                        계약에서 잡는다.""")
                .isEmpty();
    }

    // ─────────────────────────── 지그 ───────────────────────────

    /** 디렉터리 바로 아래의 하위 디렉터리 이름들. */
    private static List<String> subdirectoriesOf(Path dir) {
        assertThat(Files.isDirectory(dir))
                .as("패키지를 셀 디렉터리가 없다: %s", dir)
                .isTrue();
        try (Stream<Path> children = Files.list(dir)) {
            return children.filter(Files::isDirectory)
                    .map(path -> path.getFileName().toString())
                    .sorted()
                    .toList();
        } catch (IOException e) {
            throw new UncheckedIOException("패키지 목록을 읽지 못했다: " + dir, e);
        }
    }

    /** {@code app/lib/v2/screens} 아래 모든 {@code .dart} 파일 이름(하위 디렉터리 포함). */
    private static List<String> screenFileNames() {
        Path repositoryRoot = TestProjectPaths.backendDir().getParent();
        assertThat(repositoryRoot).as("저장소 루트를 못 찾았다").isNotNull();

        Path screens = repositoryRoot.resolve("app/lib/v2/screens");
        assertThat(Files.isDirectory(screens))
                .as("화면 디렉터리가 없다: %s — 옮겼다면 이 테스트도 함께 고친다. skip 하지 않는다", screens)
                .isTrue();

        try (Stream<Path> walk = Files.walk(screens)) {
            return walk.filter(Files::isRegularFile)
                    .map(path -> path.getFileName().toString())
                    .filter(name -> name.endsWith(".dart"))
                    .sorted()
                    .toList();
        } catch (IOException e) {
            throw new UncheckedIOException("화면 목록을 읽지 못했다: " + screens, e);
        }
    }

    /** 컨트롤러 소스에서 {@code GET /api/walks/{walkId}} 꼴의 엔드포인트를 읽는다. */
    private static List<String> endpointsOf(Path controller) {
        String source = read(controller);

        Matcher base = Pattern.compile("@RequestMapping\\(\\s*\"([^\"]*)\"").matcher(source);
        String prefix = base.find() ? base.group(1) : "";

        List<String> out = new ArrayList<>();
        Matcher mapping = Pattern
                .compile("@(Get|Post|Put|Patch|Delete)Mapping(?:\\(\\s*(?:value\\s*=\\s*)?\"([^\"]*)\")?")
                .matcher(source);
        while (mapping.find()) {
            String method = mapping.group(1).toUpperCase(Locale.ROOT);
            String sub = mapping.group(2) == null ? "" : mapping.group(2);
            out.add(method + " " + prefix + sub);
        }
        return out;
    }

    private static String read(Path path) {
        assertThat(Files.isRegularFile(path))
                .as("컨트롤러를 못 찾았다: %s — 옮겼다면 이 테스트도 함께 고친다", path)
                .isTrue();
        try {
            return Files.readString(path, StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException("컨트롤러를 읽지 못했다: " + path, e);
        }
    }
}
