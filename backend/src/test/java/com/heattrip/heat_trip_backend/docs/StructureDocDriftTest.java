package com.heattrip.heat_trip_backend.docs;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
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
 *
 * <h2>여기서 읽는 파일은 {@code build.gradle} 에 입력으로 선언돼 있다</h2>
 * <p><b>{@code app/lib/v2/screens} 와 {@code docs/01-design} 이 그것이다.</b> #177 에서
 * 이 선언이 없었고, {@code main_shell.dart} 의 탭 라벨을 '통계' 로 되돌려 놓고 돌렸는데
 * {@code test} 가 {@code UP-TO-DATE} 로 건너뛰어 <b>깨 놓고도 초록불</b>이 났다. 두 번
 * 속은 뒤에야 알았다 — {@code cleanTest} 도 안 통한다(결과가 캐시에서 복원된다).
 *
 * <p>선언을 지우면 그 거짓 초록불로 돌아간다. {@code SpecTestInputsDeclaredTest} 가
 * 같은 이유로 그 목록을 잠근다(#46).
 */
class StructureDocDriftTest {

    /** 백엔드 기저 패키지. 이 아래 1단 디렉터리가 곧 "패키지 목록" 이다. */
    private static final String BASE_PACKAGE = "src/main/java/com/heattrip/heat_trip_backend";

    /**
     * mermaid flowchart 의 <b>노드 정의</b> — {@code id[라벨]} · {@code id(라벨)} ·
     * {@code id{라벨}} · {@code id([라벨])} · {@code id[[라벨]]}.
     */
    private static final Pattern MERMAID_NODE = Pattern.compile(
            "(?<![\\w\"])([A-Za-z][A-Za-z0-9_]*)(\\[\\[|\\(\\[|\\(\\(|\\[|\\(|\\{)");

    /** 여는 괄호마다 짝이 되는 닫는 괄호. */
    private static final Map<String, String> MERMAID_NODE_CLOSERS = Map.of(
            "[[", "]]", "([", "])", "((", "))", "[", "]", "(", ")", "{", "}");

    /** 흐름도를 그리는 문서. {@code build.gradle} 이 입력으로 선언한 {@code docs/01-design} 안이다. */
    private static final List<String> FLOWCHART_DOCS = List.of(
            "01-design/user-flows.md",
            "01-design/information-architecture.md");

    /** 탭 표를 <b>표 모양까지</b> 지키는 문서. 여기 한 곳만 조인다. */
    private static final String TAB_TABLE_DOC = "01-design/information-architecture.md";

    /** {@code | 탭 3 | 채팅 | ...} 행. {@code FAB(가운데)} · {@code 글로벌} 행은 안 걸린다. */
    private static final Pattern TAB_TABLE_ROW =
            Pattern.compile("\\|\\s*탭\\s+(\\d+)\\s*\\|([^|]+)\\|");

    /**
     * {@code item(Icons.chat_bubble_outline, '채팅', 4)} — 뒤에 이름 붙은 인자가 더 올 수 있다
     * ({@code dot: ChatUnread.any}, #452 의 안 읽음 점). 라벨과 번호만 읽는다.
     */
    private static final Pattern SHELL_TAB_ITEM = Pattern.compile(
            "item\\(\\s*Icons\\.\\w+\\s*,\\s*'([^']+)'\\s*,\\s*(\\d+)\\s*(?:,[^)]*)?\\)");

    /** 탭을 <b>나열</b>하는 문서들. 라벨이 나오는지만 본다. */
    private static final List<String> TAB_LISTING_DOCS = List.of(
            "01-design/information-architecture.md",
            "01-design/feature-spec.md",
            "01-design/screen-spec.md",
            "01-design/user-flows.md",
            "02-architecture/system-overview.md",
            "05-build/implementation-status.md");

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
    @DisplayName("화면 목록 문서 셋이 실제 화면 파일을 하나도 빠뜨리지 않는다")
    void screenDocs_nameEveryScreenFile() {
        List<String> screens = screenFileNames();

        assertThat(screens)
                .as("화면을 하나도 못 찾았다면 아래 단언들이 조용히 통과한다")
                .isNotEmpty();

        for (String docPath : List.of(
                "02-architecture/frontend-structure.md",
                "01-design/screen-spec.md",
                "01-design/user-flows.md")) {
            String doc = RepositoryDocs.requireDoc(docPath);
            List<String> missing = screens.stream().filter(name -> !doc.contains(name)).toList();

            assertThat(missing)
                    .as("""
                            %s 가 실제 화면의 절반만 알고 있었다(#201). 문서에 없는 화면은 \
                            없는 것으로 취급되고, 그중 하나가 위치정보법 동의 게이트였다. \
                            화면을 추가했으면 이 표에도 한 줄 적는다. user-flows.md 가 셋째로 \
                            들어온 것도 같은 일을 겪어서다 — 동네 고르기 화면이 빠진 채로 \
                            "화면을 다 적었다" 고 말하고 있었다(#345).""", docPath)
                    .isEmpty();
        }
    }

    /**
     * 흐름도의 노드 id 가 겹치면 mermaid 는 <b>두 노드를 하나로 합친다</b>.
     *
     * <p>#345 에서 실제로 그러고 있었다 — 플로우 4 의 {@code S} 가 스플래시와 위치 사전 안내
     * 시트 둘이었고, 플로우 10 의 {@code S} 가 사전 안내 시트와 위치 이용중지 둘이었다.
     * 그림은 아무 경고 없이 그려진다. 문장 검사로는 못 잡는다 — 틀린 <b>줄</b>이 없기 때문이다.
     */
    @Test
    @DisplayName("흐름도에서 한 노드 이름이 두 화면을 겸하지 않는다")
    void flowcharts_doNotMergeTwoNodesIntoOne() {
        List<String> offenders = new ArrayList<>();

        for (String docPath : FLOWCHART_DOCS) {
            for (String chart : mermaidFlowcharts(RepositoryDocs.requireDoc(docPath))) {
                Map<String, Collection<String>> labels = new LinkedHashMap<>();
                for (String line : chart.split("\\R")) {
                    collectNodeLabels(line, labels);
                }
                labels.forEach((id, texts) -> {
                    if (texts.size() > 1) {
                        offenders.add(docPath + " — \"" + id + "\" : " + texts);
                    }
                });
            }
        }

        assertThat(offenders)
                .as("""
                        같은 노드 이름에 서로 다른 라벨이 붙었다. mermaid 는 둘을 한 상자로 \
                        합쳐 그리고, 그러면 흐름도가 조용히 거짓말을 한다(#345). \
                        한쪽의 이름을 바꾼다.""")
                .isEmpty();
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

    @Test
    @DisplayName("탭 표가 main_shell.dart 의 라벨·화면과 1:1 로 맞는다")
    void tabDocs_matchTheShell() {
        Map<Integer, String> code = shellTabs();

        assertThat(code)
                .as("main_shell.dart 에서 탭을 하나도 못 읽었다면 아래 단언들이 조용히 통과한다")
                .isNotEmpty();

        String doc = RepositoryDocs.requireDoc(TAB_TABLE_DOC);
        Map<Integer, String> table = new LinkedHashMap<>();
        Matcher row = TAB_TABLE_ROW.matcher(doc);
        while (row.find()) {
            table.put(Integer.parseInt(row.group(1)), row.group(2).trim());
        }

        assertThat(table)
                .as("""
                        %s 의 탭 표를 한 행도 못 읽었다. 표의 모양이 바뀐 것이라면 이 검사도 \
                        함께 고친다 — 못 읽는 검사는 통과하는 검사와 구별되지 않는다.""", TAB_TABLE_DOC)
                .isNotEmpty();

        assertThat(table)
                .as("""
                        5번째 탭을 '통계' 라고 적은 문서가 여섯 개 남아 있었다(#177). 통계는 \
                        2026-08 에 탭에서 내려갔고 그 자리에 채팅이 들어왔다(#78~#81). 그 사이 \
                        수동 회귀 항목 둘(test-checklist N2·N3)이 없는 라벨을 찾으라고 \
                        지시하고 있었다. 탭을 바꿨으면 이 표도 함께 고친다.""")
                .containsExactlyInAnyOrderEntriesOf(code);
    }

    @Test
    @DisplayName("탭을 나열하는 문서들이 실제 탭 라벨을 하나도 빠뜨리지 않는다")
    void tabDocs_nameEveryTabLabel() {
        Collection<String> labels = shellTabs().values();
        assertThat(labels).as("라벨을 하나도 못 읽었다").isNotEmpty();

        List<String> missing = new ArrayList<>();
        for (String docPath : TAB_LISTING_DOCS) {
            String doc = RepositoryDocs.requireDoc(docPath);
            labels.stream().filter(label -> !doc.contains(label))
                    .forEach(label -> missing.add(docPath + " — " + label));
        }

        assertThat(missing)
                .as("""
                        느슨하게 잡는다 — 라벨이 문서 어딘가 나오는지만 본다. 표의 모양은 \
                        위 검사가 한 문서에서만 조인다. 여기가 잡는 것은 '탭을 하나 더 \
                        늘렸는데 문서 여덟 곳을 안 고쳤다' 쪽이다.""")
                .isEmpty();
    }

    // ─────────────────────────── 지그 ───────────────────────────

    /**
     * {@code main_shell.dart} 의 바텀네비에서 (탭 번호 → 라벨) 을 읽는다.
     *
     * <p>{@code item(Icons.chat_bubble_outline, '채팅', 3)} 한 줄이 원본이다. 스위치(화면)가
     * 아니라 <b>라벨</b>을 읽는 이유는 #177 이 틀렸던 것이 라벨이기 때문이다 — 화면 클래스는
     * {@code ChatListScreen} 으로 맞게 적혀 있었는데 사람이 보는 이름만 '통계' 였다.
     */
    private static Map<Integer, String> shellTabs() {
        Path repositoryRoot = TestProjectPaths.backendDir().getParent();
        assertThat(repositoryRoot).as("저장소 루트를 못 찾았다").isNotNull();

        Path shell = repositoryRoot.resolve("app/lib/v2/screens/main_shell.dart");
        assertThat(Files.isRegularFile(shell))
                .as("셸을 못 찾았다: %s — 옮겼다면 이 테스트도 함께 고친다. skip 하지 않는다", shell)
                .isTrue();

        String source;
        try {
            source = Files.readString(shell, StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException("셸을 읽지 못했다: " + shell, e);
        }

        Map<Integer, String> tabs = new LinkedHashMap<>();
        Matcher item = SHELL_TAB_ITEM.matcher(source);
        while (item.find()) {
            tabs.put(Integer.parseInt(item.group(2)), item.group(1));
        }
        return tabs;
    }

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
    /** 문서 안의 mermaid {@code flowchart}/{@code graph} 블록들. ER·시퀀스는 노드 문법이 다르다. */
    private static List<String> mermaidFlowcharts(String document) {
        List<String> charts = new ArrayList<>();
        Matcher matcher = Pattern.compile("```mermaid\\R(.*?)```", Pattern.DOTALL).matcher(document);
        while (matcher.find()) {
            String chart = matcher.group(1).stripLeading();
            if (chart.startsWith("flowchart") || chart.startsWith("graph")) {
                charts.add(chart);
            }
        }
        return charts;
    }

    /**
     * 한 줄에서 노드 정의를 걷어 {@code id → 라벨들} 에 담는다.
     *
     * <p>라벨 <b>안</b>을 다시 훑지 않는다(닫는 괄호 뒤부터 이어 본다) — 훑으면
     * {@code T[GET /api/x/{id}]} 의 {@code id} 를 노드로 잘못 센다.
     * 화살표 라벨({@code |…|})도 노드가 아니라 먼저 지운다.
     */
    private static void collectNodeLabels(String line, Map<String, Collection<String>> labels) {
        String bare = line.replaceAll("\\|[^|]*\\|", " ");
        Matcher matcher = MERMAID_NODE.matcher(bare);
        int from = 0;
        while (from <= bare.length() && matcher.find(from)) {
            String closer = MERMAID_NODE_CLOSERS.get(matcher.group(2));
            int end = bare.indexOf(closer, matcher.end());
            if (end < 0) {
                return;
            }
            String label = bare.substring(matcher.end(), end).trim();
            if (!label.isEmpty()) {
                labels.computeIfAbsent(matcher.group(1), key -> new LinkedHashSet<>()).add(label);
            }
            from = end + closer.length();
        }
    }

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
