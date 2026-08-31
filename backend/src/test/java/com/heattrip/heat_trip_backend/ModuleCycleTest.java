package com.heattrip.heat_trip_backend;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.modulith.core.ApplicationModules;

/**
 * 모듈 간 <b>순환</b>의 구성을 박아 둔다. (#102 · ADR-0012 · 개념 #97 · 실측 #98)
 *
 * <p><b>{@link ModularityBaselineTest} 와 무엇이 다른가.</b> 저기는 순환의 <b>개수</b>를 센다.
 * 여기는 <b>구성</b>을 본다. 순환 하나가 사라지고 다른 하나가 생기면 개수는 그대로라 저기서는
 * 안 잡힌다. 순환은 개수가 아니라 어느 모듈이 물려 있는가가 중요해서 따로 둔다.
 *
 * <p><b>순환은 다른 방법으로 끌 수 없는 유일한 검사다.</b> {@code type = OPEN} 은 내부 접근
 * 검사만 끄고 순환 검사는 그대로 둔다. {@code @NamedInterface} 로도 안 꺼진다. 검사 대상에서
 * 패키지를 통째로 빼는 방법만이 순환을 피하는데, 그건 인증 계층을 사각지대로 만드는 선택이라
 * 하지 않는다. 문서가 정한 첫 규칙이 "모듈 간 의존은 방향 있는 비순환 그래프여야 한다" 이다.
 * https://docs.spring.io/spring-modulith/reference/1.4/verification.html
 *
 * <p><b>지금 있는 다섯은 전부 인증·설정 계층이다.</b> 각 변의 근거는 이렇다. 전부 열어서
 * 확인한 줄이다.
 *
 * <table>
 *   <caption>순환을 만드는 변</caption>
 *   <tr><th>변</th><th>근거</th></tr>
 *   <tr><td>{@code OAuth -> config}</td>
 *       <td>{@code OAuth/handler/OAuth2FailureHandler.java:15} ·
 *           {@code OAuth/handler/OAuth2SuccessHandler.java:13} 가
 *           {@code config.OAuthSecurityProperties} 를 import.
 *           {@code OAuth/code/AuthCodeStore.java:145} 가 {@code getCodeTtlSeconds()} 호출</td></tr>
 *   <tr><td>{@code config -> OAuth}</td>
 *       <td>{@code config/SecurityConfig.java:25} 가 {@code OAuth.handler.OAuth2FailureHandler} 를 import</td></tr>
 *   <tr><td>{@code config -> security}</td>
 *       <td>{@code config/SecurityConfig.java:31} 이 {@code security.ApiRateLimitFilter} 를 import</td></tr>
 *   <tr><td>{@code security -> config}</td>
 *       <td>{@code security/ApiRateLimitFilter.java:5} 가 {@code config.PublicSecurityProperties} 를 import</td></tr>
 *   <tr><td>{@code security -> S3}</td>
 *       <td>{@code security/ApiRateLimitFilter.java:4} 가 429 본문을 만들려고
 *           {@code S3.media.error.GlobalExceptionHandler} 를 import. 전역 예외 처리기가
 *           외부 서비스 패키지 밑에 있어서 생긴 변이다 (#95 §10)</td></tr>
 *   <tr><td>{@code S3 -> OAuth}</td>
 *       <td>{@code S3/media/MediaController.java:6} 이 {@code OAuth.principal.CurrentUser} 를 import</td></tr>
 *   <tr><td>{@code S3 -> user}</td>
 *       <td>{@code S3/media/MediaController.java:77} 이 {@code user.entity.User} 의 {@code getId()} 호출</td></tr>
 *   <tr><td>{@code user -> OAuth}</td>
 *       <td>{@code user/service/UserService.java:11} ·
 *           {@code user/service/RefreshTokenService.java:3} 이 {@code OAuth.jwt.JWTProvider} 를 import</td></tr>
 * </table>
 *
 * <p><b>여기서 순환을 끊지 않는다.</b> 끊는 것은 코드를 옮기는 일이라 되돌리기가 어렵다.
 * {@code config <-> security <-> OAuth} 는 #106, {@code OAuth <-> user} 는 #107 이다.
 *
 * <p>스프링 컨텍스트를 띄우지 않는다. 컴파일된 {@code .class} 를 읽는 정적 분석이다.
 */
class ModuleCycleTest {

    /**
     * 2026-08-31 실측. 같은 노드를 두 번 밟지 않는 기본 순환 다섯.
     *
     * <p>순서까지 포함해 문자열로 박는다. {@code A -> B -> A} 와 {@code B -> A -> B} 는 도구가
     * 하나만 내므로 도구가 낸 형태를 그대로 적는다.
     */
    private static final Set<String> KNOWN_CYCLES = new LinkedHashSet<>(List.of(
            "OAuth -> config -> OAuth",
            "OAuth -> config -> security -> S3 -> OAuth",
            "OAuth -> config -> security -> S3 -> user -> OAuth",
            "OAuth -> user -> OAuth",
            "config -> security -> config"));

    private static final String CYCLE_MARK = "- Cycle detected:";
    private static final String SLICE = "Slice ";
    private static final char NL = (char) 10;

    /** 위반 메시지에서 순환 경로만 뽑아 {@code "A -> B -> A"} 형태로 만든다. */
    private static Set<String> detectedCycles() {
        String message = ApplicationModules.of(HeatTripBackendApplication.class)
                .detectViolations()
                .getMessage();
        String[] lines = message.split(String.valueOf(NL));

        Set<String> cycles = new LinkedHashSet<>();
        for (int i = 0; i < lines.length; i++) {
            if (!lines[i].trim().startsWith(CYCLE_MARK)) {
                continue;
            }
            List<String> slices = new ArrayList<>();
            for (int j = i; j < lines.length; j++) {
                String text = lines[j].trim();
                if (text.startsWith(CYCLE_MARK)) {
                    text = text.substring(CYCLE_MARK.length()).trim();
                }
                if (!text.startsWith(SLICE)) {
                    break;
                }
                // "Slice OAuth ->" 에서 모듈 이름만.
                String name = text.substring(SLICE.length()).replace("->", "").trim();
                if (!name.isEmpty()) {
                    slices.add(name);
                }
            }
            if (slices.size() > 1) {
                cycles.add(String.join(" -> ", slices));
            }
        }
        return cycles;
    }

    @Test
    @DisplayName("새로 생긴 순환이 없다")
    void noCycleHasAppeared() {
        Set<String> actual = detectedCycles();
        Set<String> appeared = new LinkedHashSet<>(actual);
        appeared.removeAll(KNOWN_CYCLES);

        assertThat(appeared)
                .as("""
                        모듈 간 순환이 새로 생겼다.

                        순환은 한 모듈만 떼어낼 수 없게 만든다. 지금 있는 다섯은 전부 인증·설정
                        계층이고 끊는 작업이 #106 · #107 로 따로 잡혀 있다. 여기에 새로 더하지 마라.

                        모듈 사이는 한 방향으로만 부른다. 양쪽이 서로 필요하면 공통 타입을 제3의
                        자리로 빼거나, 부르는 쪽이 인터페이스를 정의하고 상대가 구현하게 한다.
                        개념은 #97, 우리 저장소 사정은 #98.
                        """)
                .isEmpty();
    }

    @Test
    @DisplayName("사라진 순환이 있으면 목록에서 지우라고 알린다")
    void noKnownCycleHasSilentlyDisappeared() {
        Set<String> actual = detectedCycles();
        Set<String> gone = new LinkedHashSet<>(KNOWN_CYCLES);
        gone.removeAll(actual);

        assertThat(gone)
                .as("""
                        박아 둔 순환이 실제로는 없다. 빚을 갚았으면 KNOWN_CYCLES 에서 그 줄을 지워라.

                        한 방향으로만 물면 갚아도 목록이 그대로 남고, 그만큼 이 검사가 무뎌진다.
                        나중에 같은 순환이 다시 생겨도 "원래 있던 것" 으로 통과한다.
                        """)
                .isEmpty();
    }

    @Test
    @DisplayName("순환 추출이 실제로 동작한다 — 하나도 못 뽑으면 위 두 단언은 빈 집합끼리 비교한다")
    void theExtractionActuallyFindsCycles() {
        assertThat(detectedCycles())
                .as("순환을 하나도 못 뽑았다면 파싱이 깨진 것이지 순환이 없어진 것이 아닐 수 있다. "
                        + "정말 다 끊었다면 이 단언과 KNOWN_CYCLES 를 함께 지워라")
                .isNotEmpty();
    }
}
