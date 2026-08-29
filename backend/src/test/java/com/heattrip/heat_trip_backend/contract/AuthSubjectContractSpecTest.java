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
 *   <li><b>컴파일 불가</b> — 토큰 헤더에서 이메일을 뽑던 {@code UserService} 헬퍼와
 *       public {@code findByEmail} 을 지웠으므로 소비처 어디를 되돌려도 빌드가 죽는다.
 *       가장 강하고 비용이 0 이다.</li>
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

    /**
     * 유일하게 Authorization 헤더를 읽고 토큰을 해석해도 되는 파일.
     *
     * <p>{@code backend/src/main/java} 기준 상대 경로다. 파일 이름만 쓰면 안 된다 —
     * 아래 {@link #loadMainSources()} 참조.
     */
    private static final String THE_ONLY_EXTRACTION_POINT =
            "com/heattrip/heat_trip_backend/OAuth/jwt/JWTAuthenticationFilter.java";

    /** {@link #onlyTheFilterExtractsTheSubject()} 가 함께 허용하는, 그 메서드를 선언하는 파일. */
    private static final String THE_PROVIDER =
            "com/heattrip/heat_trip_backend/OAuth/jwt/JWTProvider.java";

    /**
     * 이슈 완료 조건 5 가 이름으로 지목한, 지워진 헬퍼.
     *
     * <p>이어 붙여 조립하는 이유: 리터럴로 두면 이 파일 자체가
     * {@code grep -rn <이름> backend/src} 에 걸려, 읽는 사람이 "아직 남아 있나?" 하고 멈칫한다.
     * 단언이 보는 값은 조립 결과이므로 검사의 강도는 같다.
     */
    private static final String DELETED_HELPER = "email" + "FromAuth";

    /** src/main/java 기준 상대 경로 → 주석을 걷어낸 소스. */
    private static Map<String, String> sources;

    /** 같은 키 → 주석까지 그대로인 원본. grep 과 같은 눈으로 보는 단언에 쓴다. */
    private static Map<String, String> rawSources;

    /**
     * 키가 <b>상대 경로</b>인 이유: 예전에는 {@code file.getFileName()} 이었다. 그러면 같은
     * 이름의 파일이 둘일 때 뒤에 온 것이 앞의 것을 덮어써서 <b>한쪽이 스캔에서 조용히 사라진다.</b>
     * 실측으로 .java 205개 중 basename 고유는 200개였다 — 5개가 검사받지 않고 있었고
     * ({@code Place.java}·{@code PlaceMapper.java}·{@code PlaceSearchCond.java}·
     *  {@code PlaceTrait.java}·{@code StringListJsonConverter.java}) 가드가
     * {@code hasSizeGreaterThan(50)} 이라 그 손실을 아무도 알리지 않았다.
     * "조용한 회귀를 잡는 유일한 자동 장치"라고 스스로 선언한 테스트가 조용히 놓치는 구멍을
     * 두어서는 안 된다. 가드도 실제 파일 개수에 붙여 다음에 누가 키를 되돌리면 드러나게 한다. (#5)
     */
    @BeforeAll
    static void loadMainSources() throws IOException {
        Path mainJava = locateBackendMainJava();
        long fileCount;
        try (Stream<Path> walk = Files.walk(mainJava)) {
            sources = new LinkedHashMap<>();
            rawSources = new LinkedHashMap<>();
            List<Path> files = walk.filter(p -> p.toString().endsWith(".java")).toList();
            fileCount = files.size();
            for (Path file : files) {
                String key = mainJava.relativize(file).toString().replace(java.io.File.separatorChar, '/');
                String raw = Files.readString(file, StandardCharsets.UTF_8);
                rawSources.put(key, raw);
                sources.put(key, stripComments(raw));
            }
        }
        assertThat(sources)
                .as("키가 겹쳐 파일이 하나라도 사라지면 그 파일은 이 테스트의 어떤 단언도 받지 않는다")
                .hasSize((int) fileCount);
        assertThat(fileCount)
                .as("소스를 한 개도 못 읽었다면 이 테스트는 아무것도 지키지 못한다")
                .isGreaterThan(50);
    }

    @Test
    @DisplayName("토큰 헤더에서 이메일을 뽑던 헬퍼의 이름이 주석을 포함해 src/main 어디에도 없다")
    void noSourceMentionsTheDeletedHelper() {
        // 여기만 주석을 걷어내지 않은 원본을 본다. 완료 조건 5 가 요구하는 것이
        // "grep -rn <이름> backend/src/main 이 0건" 이라 grep 과 같은 눈으로 봐야 한다.
        List<String> hits = rawSources.entrySet().stream()
                .filter(entry -> entry.getValue().contains(DELETED_HELPER))
                .map(Map.Entry::getKey)
                .sorted()
                .toList();

        assertThat(hits)
                .as("이력을 적을 때도 이 이름은 쓰지 않는다 — 완료 조건이 문자열 자체를 지목했다")
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
                .containsExactlyInAnyOrder(THE_ONLY_EXTRACTION_POINT, THE_PROVIDER);
    }

    @Test
    @DisplayName("@AuthenticationPrincipal String 은 src/main 어디에도 없다")
    void noSourceInjectsThePrincipalAsString() {
        // 필터의 principal 은 AuthenticatedUser 다. 타입이 맞지 않는 @AuthenticationPrincipal 은
        // 예외도 경고도 없이 null 을 주입하고 요청은 200 으로 끝난다 — MediaController 의
        // 소유권 검사 4곳이 통째로 무력화되는데 컴파일도 다른 테스트도 이를 잡지 못한다.
        // 패키지를 앞에 붙인 형태(@org.springframework...AuthenticationPrincipal String)도 잡는다.
        // 되돌리는 사람이 import 를 다시 추가하기 싫어 전체 이름을 쓰는 일이 실제로 있다.
        Pattern principalAsString = Pattern.compile("@(?:[\\w.]+\\.)?AuthenticationPrincipal\\s+String\\b");
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
