package com.heattrip.heat_trip_backend.docs;

import static org.assertj.core.api.Assertions.assertThat;

import com.heattrip.heat_trip_backend.support.TestProjectPaths;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Stream;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 패키지 구조 규약 문서가 <b>실제 소스와 맞는지</b> 본다. (#108 · #95 · ADR-0012)
 *
 * <p><b>왜 필요한가.</b> 규약은 원래 문서로 있었는데 아무도 안 읽었고, 그래서 {@code chat} 과
 * {@code chatweb} 이 다른 도메인과 다른 모양이 된 것을 다섯 이슈 동안 못 봤다(#93). 규약을
 * 적는 것만으로는 같은 일이 또 생긴다 — <b>문서가 낡아도 아무도 모르기 때문이다.</b>
 *
 * <p>그래서 셋으로 나눠 확인한다.
 * <ol>
 *   <li>규칙 문장이 있는가 — 없어졌으면 누군가 지운 것이다.</li>
 *   <li>문서가 가리키는 파일이 실제로 있는가 — 죽은 링크는 렌더링이 안 알려 준다.</li>
 *   <li><b>문서의 표가 실제 소스와 같은가</b> — 이게 핵심이다.</li>
 * </ol>
 *
 * <p>3번을 설명하면 이렇다. 문서는 {@code chat} 루트 16개가 밖에서 부르는 12개와 아무도 안
 * 부르는 4개로 갈린다고 적었고, 그 구분이 {@code api} 하위 패키지의 내용을 그대로 정한다.
 * 숫자가 낡으면 <b>틀린 설계가 지시된다.</b> 그래서 여기서 소스를 다시 세어 대조한다.
 *
 * <p>네트워크를 타지 않는다. 저장소 안의 파일만 읽는다.
 */
class PackageConventionDocTest {

    private static final String GUIDE = "02-architecture/backend-implementation-guide.md";

    private static final String QUOTE = String.valueOf((char) 34);
    private static final char LF = (char) 10;
    private static final char SLASH = (char) 47;
    private static final char STAR = (char) 42;
    private static final char UNDERSCORE = (char) 95;

    /** 문서가 링크로 가리키는 파일들. */
    private static final List<String> LINKED_FILES = List.of(
            "backend/src/main/java/com/heattrip/heat_trip_backend/chatweb/package-info.java",
            "backend/src/test/java/com/heattrip/heat_trip_backend/chat/ChatBoundaryArchitectureTest.java");

    /**
     * 2026-08-31 실측 — chat 루트에서 <b>밖의 소스에 이름이 안 적힌</b> 여섯.
     *
     * <p><b>"내부로 옮겨도 된다" 는 목록이 아니다.</b> 세는 방식이 "밖에 이름이 적혀 있는가"
     * 라서 맹점이 하나 있다 — {@code ChatReportedMessageView} 는 밖 어디에도 안 적혀 있지만
     * {@code ChatReportView} 가 들고 있는 리스트의 원소 타입이라, 내부로 내리면 공개 record 의
     * 시그니처가 깨진다(#82). 그 사실을 문서 2.4 절에도 적어 뒀다.
     *
     * <p>{@code ChatReportReason} 은 사정이 다르다 — 밖으로 나가는 것은 그 enum 이 아니라
     * {@code wireValue()} 문자열이라 <b>진짜로 내부다</b>. 같은 칸에 있어도 이유가 다르다.
     */
    private static final List<String> EXPECTED_UNUSED_ROOT_TYPES =
            List.of("ChatErrorCode", "ChatLimits", "FixedChatLimits", "InviteCodeGenerator",
                    // #254 로 접수가 moderation 으로 옮겨가면서 밖에서 부르는 곳이 없어졌다.
                    // 지우지 않는 것은 chat_report 표를 지울지 말지가 아직 사람의 판단이기
                    // 때문이다 — 표가 남아 있는 동안 그것을 읽는 모양도 남겨 둔다.
                    "ChatReportedMessageView", "ChatReportReason", "ChatReportView");

    private static String guide;

    @BeforeAll
    static void loadGuide() {
        guide = RepositoryDocs.requireDoc(GUIDE);
    }

    // ─────────────────────────── 1. 규칙 문장 ───────────────────────────

    @Test
    @DisplayName("api 하위 패키지에 이름을 붙인다는 규칙이 문서에 있다")
    void guide_statesTheNamedInterfacePairing() {
        assertThat(guide)
                .as("2단 구조를 쓰면서 이 규칙이 없으면, 다음 사람은 규약대로 나눈 뒤 검사에서 "
                        + "빨간불을 보고 도구가 틀렸다고 판단하게 된다")
                .contains("@NamedInterface(" + QUOTE + "api" + QUOTE + ")");

        assertThat(guide)
                .as("루트와 이름 붙은 표면을 따로 열어야 한다는 것은 실제로 걸려 본 함정이다 (#105)")
                .contains("루트와 이름 붙은 표면은 따로 열어야 한다");
    }

    @Test
    @DisplayName("1단 도메인에서 무엇을 여는가에 대한 결론이 문서에 있다")
    void guide_answersWhatToExposeForSimpleCrud() {
        assertThat(guide)
                .as("열지 않는다가 기본값이라는 결론이 없으면 각자 다르게 판단한다")
                .contains("아무것도 안 연다");
    }

    @Test
    @DisplayName("구조 검사가 잡지 못하는 것이 무엇인지 문서에 적혀 있다")
    void guide_statesWhatTheModuleCheckCannotCatch() {
        assertThat(guide)
                .as("도구를 넣었다고 ChatBoundaryArchitectureTest 를 지우면 안 되는 이유다")
                .contains("공개인데 아무도 안 쓰는 표면");
    }

    // ─────────────────────────── 2. 링크 ───────────────────────────

    @Test
    @DisplayName("문서가 가리키는 파일이 실제로 있다 — 죽은 링크는 렌더링이 알려 주지 않는다")
    void guide_linksResolveToRealFiles() {
        Path repositoryRoot = TestProjectPaths.backendDir().getParent();

        for (String relative : LINKED_FILES) {
            Path target = repositoryRoot.resolve(relative);
            assertThat(Files.isRegularFile(target))
                    .as("문서가 %s 를 가리키는데 그 파일이 없다. 옮겼다면 문서도 함께 고쳐라", relative)
                    .isTrue();

            // 파일명만 보면 안 된다. 이 문서에는 `// care/api/package-info.java` 같은 코드
            // 예시가 있어서 파일명 하나로는 링크가 깨져도 통과한다 — 실제로 그렇게 통과했다.
            // 그래서 마지막 두 조각(디렉터리/파일명)을 본다.
            assertThat(guide)
                    .as("문서에 %s 링크가 남아 있어야 한다 — 예시가 사라지면 규칙만 남고 "
                            + "실제로 이렇게 쓴다를 보여 줄 것이 없어진다", relative)
                    .contains(lastTwoSegments(relative));
        }
    }

    // ─────────────────────────── 3. 표 ↔ 소스 ───────────────────────────

    @Test
    @DisplayName("문서의 chat 공개 표면 구분이 실제 소스와 같다 — 낡으면 틀린 설계가 지시된다")
    void guide_chatPublicSurfaceTableMatchesTheSource() {
        Path chatDir = TestProjectPaths.backendDir()
                .resolve("src/main/java/com/heattrip/heat_trip_backend/chat");

        List<String> rootTypes = new ArrayList<>();
        try (Stream<Path> files = Files.list(chatDir)) {
            files.filter(path -> path.getFileName().toString().endsWith(".java"))
                    .map(path -> {
                        String name = path.getFileName().toString();
                        return name.substring(0, name.length() - ".java".length());
                    })
                    .filter(name -> !name.equals("package-info"))
                    .forEach(rootTypes::add);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }

        assertThat(rootTypes)
                .as("chat 루트를 하나도 못 읽었다면 아래 대조는 아무것도 지키지 못한다")
                .hasSizeGreaterThan(5);

        String outside = readAllOutsideChat();

        List<String> used = new ArrayList<>();
        List<String> unused = new ArrayList<>();
        for (String type : rootTypes) {
            if (referencesType(outside, type)) {
                used.add(type);
            } else {
                unused.add(type);
            }
        }

        for (String type : used) {
            assertThat(guide)
                    .as("%s 는 밖에서 실제로 부른다. 문서의 밖에서 부름 칸에 있어야 한다", type)
                    .contains(type);
        }

        assertThat(unused)
                .as("""
                        문서가 적은 목록과 실측 %s 가 갈렸다.

                        이 목록이 바뀌면 chat 을 2단 구조로 옮길 때 api 하위 패키지에 들어갈 것도
                        바뀐다. 문서의 2.4 절 표를 함께 고쳐라.
                        """.formatted(unused))
                .containsExactlyInAnyOrderElementsOf(EXPECTED_UNUSED_ROOT_TYPES);
    }

    /** {@code a/b/c.java} 에서 {@code b/c.java}. 파일명 하나로는 다른 예시와 겹친다. */
    private static String lastTwoSegments(String path) {
        int last = path.lastIndexOf(SLASH);
        int secondLast = path.lastIndexOf(SLASH, last - 1);
        return path.substring(secondLast + 1);
    }

    /**
     * {@code chat.<type>} 참조가 있는가. 정규식을 안 쓰는 이유는 뒤 글자를 직접 봐야 하기
     * 때문이다 — {@code chat.ChatRoom} 을 찾다가 {@code chat.ChatRoomService} 에 걸리면 안 된다.
     */
    private static boolean referencesType(String haystack, String type) {
        String needle = "chat." + type;
        int from = 0;
        while (true) {
            int at = haystack.indexOf(needle, from);
            if (at < 0) {
                return false;
            }
            int after = at + needle.length();
            boolean boundary = after >= haystack.length()
                    || !(Character.isLetterOrDigit(haystack.charAt(after))
                         || haystack.charAt(after) == UNDERSCORE);
            if (boundary) {
                return true;
            }
            from = at + 1;
        }
    }

    /** chat 밖의 main 소스 전부. 주석은 걷어낸다 — 주석 속 이름은 참조가 아니다. */
    private static String readAllOutsideChat() {
        Path mainJava = TestProjectPaths.backendDir().resolve("src/main/java");
        Path chatDir = mainJava.resolve("com/heattrip/heat_trip_backend/chat");

        StringBuilder all = new StringBuilder();
        try (Stream<Path> walk = Files.walk(mainJava)) {
            walk.filter(path -> path.toString().endsWith(".java"))
                    .filter(path -> !path.startsWith(chatDir))
                    .forEach(path -> {
                        try {
                            all.append(stripComments(Files.readString(path, StandardCharsets.UTF_8)));
                            all.append(LF);
                        } catch (IOException e) {
                            throw new UncheckedIOException(e);
                        }
                    });
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        return all.toString();
    }

    /** 블록 주석과 줄 주석을 지운다. */
    private static String stripComments(String source) {
        String blockEnd = String.valueOf(STAR) + SLASH;
        StringBuilder out = new StringBuilder(source.length());
        int i = 0;
        while (i < source.length()) {
            char c = source.charAt(i);
            boolean hasNext = i + 1 < source.length();
            if (c == SLASH && hasNext && source.charAt(i + 1) == STAR) {
                int end = source.indexOf(blockEnd, i + 2);
                i = (end < 0) ? source.length() : end + 2;
            } else if (c == SLASH && hasNext && source.charAt(i + 1) == SLASH) {
                int end = source.indexOf(LF, i);
                i = (end < 0) ? source.length() : end;
            } else {
                out.append(c);
                i++;
            }
        }
        return out.toString();
    }
}
