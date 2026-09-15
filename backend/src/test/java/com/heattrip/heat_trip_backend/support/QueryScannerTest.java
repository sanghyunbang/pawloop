package com.heattrip.heat_trip_backend.support;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 주석 걷기 자체를 잰다 — 이슈 #540. #538 을 고치다가 이 자리가 <b>StackOverflowError</b> 로 죽었다.
 *
 * <h2>무슨 일이 있었나</h2>
 * <p>{@code stripComments} 가 정규식 한 줄이라 {@code "https://appleid.apple.com"} 안의
 * {@code //} 를 주석으로 보고 <b>닫는 따옴표까지</b> 지웠다. 짝을 잃은 여는 따옴표는 다음
 * 따옴표까지 800자를 한 문자열로 만들었고, {@code queryLiteralsIn} 의 문자열 정규식이 글자마다
 * 재귀하다 스택을 다 썼다.
 *
 * <p><b>그 죽음은 남은 스택에 달려 있었다.</b> 그래서 관계없는 파일에 주석 몇 줄이 늘자 초록이던
 * 검사가 빨개졌다. 흔들리는 검사는 며칠 안에 지워진다 — 그래서 여기서 못을 박는다.
 */
class QueryScannerTest {

    private static final Path MAIN = Path.of("src", "main", "java", "com", "heattrip",
            "heat_trip_backend");

    /**
     * 한 문자열 리터럴의 길이 상한. 실제 소스에서 가장 긴 것이 이 아래면 문자열 정규식의 재귀도
     * 얕다. 넘는 것이 생기면 <b>따옴표 짝이 깨졌다는 신호</b>다 — 그때 스택이 아니라 이 단언이 터진다.
     */
    private static final int LONGEST_ALLOWED_LITERAL = 400;

    @Test
    @DisplayName("문자열 속 // 는 주석이 아니다 — 닫는 따옴표를 안 지운다")
    void slashesInsideAStringAreNotAComment() {
        String stripped = QueryScanner.stripComments(
                "String u = \"https://appleid.apple.com\"; // 이건 진짜 주석\nint x = 1;");

        assertThat(stripped).contains("\"https://appleid.apple.com\"");
        assertThat(stripped).doesNotContain("진짜 주석");
        assertThat(quoteCountIn(stripped)).as("따옴표는 짝이 맞아야 한다").isEven();
    }

    @Test
    @DisplayName("문자열 속 /* 도 주석이 아니다")
    void blockCommentOpenerInsideAStringIsNotAComment() {
        String stripped = QueryScanner.stripComments("String s = \"a /" + "* b\"; int x = 1;");

        assertThat(stripped).contains("\"a /" + "* b\"").contains("int x = 1;");
    }

    @Test
    @DisplayName("줄 수는 그대로다 — 위반을 파일:줄 로 가리켜야 한다")
    void keepsTheLineCount() {
        String source = "a\n/" + "*\n둘\n셋\n*" + "/\nb\n// 넷\nc";

        assertThat(QueryScanner.stripComments(source).split("\n", -1)).hasSameSizeAs(source.split("\n", -1));
    }

    @Test
    @DisplayName("텍스트 블록은 통째로 그대로 둔다 — 쿼리가 거기 산다")
    void keepsTextBlocks() {
        String source = "var q = \"\"\"\nselect w from Walk w\n// 이건 블록 안이라 주석이 아니다\n\"\"\";";

        String stripped = QueryScanner.stripComments(source);

        assertThat(stripped).isEqualTo(source);
        assertThat(QueryScanner.queryLiteralsIn(stripped))
                .containsExactly("select w from Walk w // 이건 블록 안이라 주석이 아니다");
    }

    @Test
    @DisplayName("URL 이 있어도 그 뒤의 쿼리를 그대로 뽑는다 — 예전에는 둘이 한 문자열로 붙었다")
    void findsQueriesAfterAUrl() {
        String source = """
                static final String AUDIENCE = "https://appleid.apple.com";
                static final String Q = "select w from Walk w where w.id = :id";
                """;

        assertThat(QueryScanner.queryLiteralsIn(QueryScanner.stripComments(source)))
                .containsExactly("select w from Walk w where w.id = :id");
    }

    @Test
    @DisplayName("안 닫힌 따옴표는 줄 끝에서 멈춘다 — 파일 끝까지 삼키면 그 뒤 주석이 안 걷힌다")
    void anUnclosedQuoteStopsAtTheLineEnd() {
        String stripped = QueryScanner.stripComments("char c = '\n// 이 줄은 주석이다\nint x = 1;");

        assertThat(stripped)
                .as("따옴표가 줄을 넘어 삼키면 이 주석이 코드로 남는다")
                .doesNotContain("이 줄은 주석이다");
        assertThat(stripped).contains("int x = 1;");
    }

    @Test
    @DisplayName("실제 소스에서 가장 긴 문자열이 상한 아래다 — 넘으면 따옴표 짝이 깨진 것이다 (#540)")
    void noRunawayLiteralInTheRealSources() throws IOException {
        String worstFile = null;
        String worst = "";

        try (Stream<Path> files = Files.walk(MAIN)) {
            for (Path file : files.filter(f -> f.toString().endsWith(".java")).toList()) {
                String stripped = QueryScanner.stripComments(
                        Files.readString(file, StandardCharsets.UTF_8));
                for (String literal : QueryScanner.stringLiteralsIn(stripped)) {
                    if (literal.length() > worst.length()) {
                        worst = literal;
                        worstFile = file.getFileName().toString();
                    }
                }
            }
        }

        assertThat(worst.length())
                .as("""
                        가장 긴 문자열: %s (%d자). 진짜로 긴 문자열이면 상한을 올리세요. 아니라면 \
                        주석 걷기가 닫는 따옴표를 지운 것입니다 — 그대로 두면 문자열 정규식이 \
                        글자마다 재귀하다 StackOverflowError 로 죽고, 그 죽음은 남은 스택에 달려 \
                        있어 관계없는 파일이 바뀔 때마다 초록과 빨강을 오갑니다 (#540).""",
                        worstFile, worst.length())
                .isLessThan(LONGEST_ALLOWED_LITERAL);
    }

    @Test
    @DisplayName("이 검사가 실제로 잰다 — 닫는 따옴표가 없으면 긴 문자열이 나온다")
    void theGuardActuallyMeasures() {
        // 닫는 따옴표가 사라진 모습 — 예전 주석 걷기가 URL 뒤를 통째로 지워 만들던 그 상태다.
        // 상한을 조금만 넘긴다. 여기서 수천 자를 심으면 이 테스트가 바로 그 StackOverflowError 로 죽는다.
        String planted = "String u = \"https://a.b;\n" + "int x = 1;\n".repeat(50) + "String v = \"끝\";";

        List<String> literals = QueryScanner.stringLiteralsIn(planted);

        assertThat(literals.stream().mapToInt(String::length).max().orElse(0))
                .as("따옴표 하나가 사라지면 다음 따옴표까지가 한 문자열이 된다 — 그 길이를 이 검사가 잡는다")
                .isGreaterThan(LONGEST_ALLOWED_LITERAL);
    }

    private static int quoteCountIn(String s) {
        return (int) s.chars().filter(c -> c == '"').count();
    }
}
