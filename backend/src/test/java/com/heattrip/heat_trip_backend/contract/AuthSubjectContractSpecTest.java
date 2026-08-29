package com.heattrip.heat_trip_backend.contract;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 인증 주체 해석이 <b>한 곳뿐</b>이라는 것을 소스 텍스트로 잠근다 — 이슈 #5 완료 조건 5.
 *
 * <p>세 겹의 잠금 중 두 번째다.
 * <ol>
 *   <li><b>컴파일 불가</b> — {@code UserService.emailFromAuth} 와 public {@code findByEmail} 을
 *       지웠으므로 소비처 어디를 되돌려도 빌드가 죽는다. 가장 강하고 비용이 0 이다.</li>
 *   <li><b>이 테스트</b> — 컴파일이 못 잡는 것을 잡는다. 특히 {@code @AuthenticationPrincipal String}
 *       재도입은 예외도 경고도 컴파일 에러도 없이 <b>200 OK 인 채로 null 이 주입</b>되는
 *       유일한 조용한 회귀다(실측 확인).</li>
 *   <li><b>행동 잠금</b> — {@code AuthMeIntegrationTest} 가 소셜 토큰으로 실제 200 을 확인한다.</li>
 * </ol>
 *
 * <p>이 테스트만으로는 부족하다는 점을 분명히 해 둔다 — <b>텍스트를 잠그지 행동을 잠그지 않는다.</b>
 * 헬퍼 이름만 바꾸면 우회할 수 있다. 반드시 1·3 과 함께여야 한다.
 *
 * <p>스프링 컨텍스트도 네트워크도 없다. 저장소 안의 .java 파일만 읽는다.
 */
class AuthSubjectContractSpecTest {

    /** 유일하게 Authorization 헤더를 읽고 토큰을 해석해도 되는 파일. */
    private static final String THE_ONLY_EXTRACTION_POINT = "JWTAuthenticationFilter.java";

    /** 파일 이름 → 주석을 걷어낸 소스. */
    private static Map<String, String> sources;

    @BeforeAll
    static void loadMainSources() throws IOException {
        Path mainJava = locateBackendMainJava();
        try (Stream<Path> walk = Files.walk(mainJava)) {
            sources = new LinkedHashMap<>();
            for (Path file : walk.filter(p -> p.toString().endsWith(".java")).toList()) {
                sources.put(file.getFileName().toString(),
                        stripComments(Files.readString(file, StandardCharsets.UTF_8)));
            }
        }
        assertThat(sources)
                .as("소스를 한 개도 못 읽었다면 이 테스트는 아무것도 지키지 못한다")
                .hasSizeGreaterThan(50);
    }

    @Test
    @DisplayName("src/main 어디에도 emailFromAuth 가 남아 있지 않다")
    void noSourceMentionsEmailFromAuth() {
        assertThat(filesContaining("emailFromAuth"))
                .as("완료 조건 5 를 문자 그대로: grep -rn \"emailFromAuth\" backend/src/main 이 0건이어야 한다")
                .isEmpty();
    }

    @Test
    @DisplayName("인증 주체를 이메일로 조회하는 userService.findByEmail 호출이 src/main 에 없다")
    void noSourceResolvesPrincipalByEmail() {
        // userRepository.findByEmail 은 남아 있어도 된다 — 가입·로그인·소셜 이메일 충돌 검사가 쓴다.
        // 금지되는 것은 "토큰 주체를 이메일로 되찾는" 모양뿐이다.
        assertThat(filesContaining("userService.findByEmail("))
                .as("소셜 계정은 email 이 null 일 수 있다 — 이메일로 주체를 찾으면 그 계정은 영원히 찾아지지 않는다")
                .isEmpty();
    }

    @Test
    @DisplayName("Authorization 헤더를 직접 읽는 코드는 JWTAuthenticationFilter 한 곳뿐이다")
    void onlyTheFilterReadsTheAuthorizationHeader() {
        assertThat(filesContaining("getHeader(\"Authorization\")"))
                .as("컨트롤러가 헤더를 다시 읽기 시작하면 주체 해석 지점이 다시 갈라진다")
                .containsExactly(THE_ONLY_EXTRACTION_POINT);
        assertThat(filesContaining("@RequestHeader(\"Authorization\")"))
                .as("@RequestHeader 로 받는 것도 헤더를 다시 읽는 것이다")
                .isEmpty();
        assertThat(filesContaining("\"Authorization\", required = false"))
                .as("선택적 인증은 컨트롤러 파라미터가 아니라 SecurityConfig.publicMatchers 가 정한다 (#23)")
                .isEmpty();
    }

    @Test
    @DisplayName("토큰에서 사용자 식별자를 꺼내는 코드는 JWTAuthenticationFilter 한 곳뿐이다")
    void onlyTheFilterExtractsTheSubject() {
        // JWTProvider.java 는 이 메서드를 **선언**하는 곳이라 당연히 이름이 나온다.
        // 호출부가 필터 하나뿐인 것이 이 단언의 내용이다.
        assertThat(filesContaining("getUserIdFromToken("))
                .as("추출 지점이 하나여야 규약이 바뀔 때 고칠 곳도 하나다 — 예전에는 8곳이었다")
                .containsExactlyInAnyOrder(THE_ONLY_EXTRACTION_POINT, "JWTProvider.java");
    }

    @Test
    @DisplayName("@AuthenticationPrincipal String 은 src/main 어디에도 없다")
    void noSourceInjectsThePrincipalAsString() {
        // 필터의 principal 은 AuthenticatedUser 다. 타입이 맞지 않는 @AuthenticationPrincipal 은
        // 예외도 경고도 없이 null 을 주입하고 요청은 200 으로 끝난다 — MediaController 의
        // 소유권 검사 4곳이 통째로 무력화되는데 컴파일도 다른 테스트도 이를 잡지 못한다.
        Pattern principalAsString = Pattern.compile("@AuthenticationPrincipal\\s+String\\b");
        assertThat(filesMatching(principalAsString))
                .as("이 이슈에서 유일하게 '조용한' 회귀다 — 이 단언이 그것을 잡는 유일한 자동 장치다")
                .isEmpty();
    }

    // ─────────────────────────── helpers ───────────────────────────

    private static List<String> filesContaining(String needle) {
        return sources.entrySet().stream()
                .filter(entry -> entry.getValue().contains(needle))
                .map(Map.Entry::getKey)
                .sorted()
                .toList();
    }

    private static List<String> filesMatching(Pattern pattern) {
        return sources.entrySet().stream()
                .filter(entry -> pattern.matcher(entry.getValue()).find())
                .map(Map.Entry::getKey)
                .sorted()
                .toList();
    }

    /**
     * 주석을 걷어낸다. 이 저장소는 결정의 이력을 주석으로 남기는 규약(#4)이라
     * "예전에는 이랬다" 는 설명이 본문에 자주 등장한다 — 그건 회귀가 아니다.
     *
     * <p>완전한 자바 렉서가 아니다. {@code "http://..."} 같은 문자열 안의 {@code //} 만 예외로 둔다.
     * 잘라 낸 자리가 과하면 <b>단언이 통과하는</b> 방향으로만 틀리므로, 이 테스트는 언제나
     * 컴파일 잠금·행동 잠금과 함께 쓴다.
     */
    private static String stripComments(String source) {
        String withoutBlocks = source.replaceAll("(?s)/\\*.*?\\*/", " ");
        Matcher lineComment = Pattern.compile("(?<!:)//.*").matcher(withoutBlocks);
        return lineComment.replaceAll(" ");
    }

    /** 테스트 작업 디렉터리(backend/)에서 위로 올라가며 backend/src/main/java 를 찾는다. */
    private static Path locateBackendMainJava() {
        Path cursor = Paths.get("").toAbsolutePath();
        while (cursor != null) {
            for (Path candidate : List.of(
                    cursor.resolve("src").resolve("main").resolve("java"),
                    cursor.resolve("backend").resolve("src").resolve("main").resolve("java"))) {
                if (Files.isDirectory(candidate)) {
                    return candidate;
                }
            }
            cursor = cursor.getParent();
        }
        throw new IllegalStateException("backend/src/main/java 를 찾지 못했다. 작업 디렉터리: "
                + Paths.get("").toAbsolutePath());
    }
}
