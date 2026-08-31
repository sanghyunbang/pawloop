package com.heattrip.heat_trip_backend;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Arrays;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.modulith.core.ApplicationModules;
import org.springframework.modulith.core.Violations;

/**
 * 모듈 경계의 <b>기준선</b>을 박아 둔다. 게이트가 아니라 눈금자다. (#100 · ADR-0012 · #97 · #98)
 *
 * <p><b>왜 {@code verify()} 를 바로 부르지 않는가.</b> 지금 위반이 {@value #BASELINE_VIOLATIONS} 건이다.
 * {@code verify()} 는 하나라도 있으면 던지므로, 그대로 걸면 이 저장소는 첫날부터 빨간불이고 아무
 * 작업도 못 한다. 실패하는 게이트는 며칠 안에 무시당하고, 그러면 없느니만 못하다. 같은 이유로
 * 커버리지 하한도 목표치가 아니라 실측치에서 시작했다({@code build.gradle} 의 jacoco 블록).
 * 게이트 승격은 위반을 실제로 줄인 뒤 #109 에서 한다.
 *
 * <p><b>양방향으로 막는다.</b> 늘어나면 새 빚이 생긴 것이라 실패한다. 줄어들면 빚을 갚은 것인데
 * 기준선을 안 내리면 그만큼 게이트가 다시 무뎌지므로 역시 실패시키고 숫자를 내리게 한다.
 *
 * <p><b>스프링 컨텍스트를 띄우지 않는다.</b> {@code @SpringBootTest} 도 {@code @DataJpaTest} 도
 * 없다. 컴파일된 {@code .class} 를 ArchUnit 으로 읽는 정적 분석이라 컨텍스트 캐시 항목이 늘지
 * 않고 MySQL 컨테이너도 뜨지 않는다.
 * 문서: https://docs.spring.io/spring-modulith/reference/1.4/verification.html
 *
 * <p><b>모듈 개수는 단언하지 않는다.</b> 최상위 패키지 하나가 곧 모듈 하나라, 패키지를 지우거나
 * 더하는 것만으로 숫자가 바뀐다(#96 이 {@code login} 을 지우면 20 에서 19 가 된다). 그건 경계가
 * 나빠진 것이 아니므로 여기서 잡을 일이 아니다. 새 패키지가 남의 내부를 부르면 아래 위반 수가
 * 대신 잡는다.
 *
 * <p><b>{@code BootstrapRunner} 도 검사 대상이다.</b> 메인 패키지 직속 클래스인데 실측해 보니
 * {@code root:com.heattrip.heat_trip_backend -> tour} 8건으로 잡힌다. 문서에 명시가 없어서 몰랐고
 * 돌려 보고 알았다.
 */
class ModularityBaselineTest {

    /**
     * 남의 모듈 내부(하위 패키지)를 부르거나 순환을 만든 건수. 2026-08-31 실측.
     *
     * <p>소스의 {@code import} 를 세면 100건 남짓인데 여기가 훨씬 큰 이유는, 도구가 바이트코드의
     * <b>타입 참조</b>를 세기 때문이다 — 필드 타입 · 파라미터 · 반환형 · 애노테이션 값 · 생성자
     * 시그니처가 각각 한 건이다. 같은 {@code User} 한 타입을 네 곳에서 쓰면 4건이다.
     *
     * <p><b>620 에서 588 로 내렸다. 빚을 갚아서가 아니라 집계 방식이 바뀌어서다.</b> (#103)
     * {@code chatweb} 에 {@code allowedDependencies = { "chat" }} 를 선언하자 그 패키지의
     * 위반이 다른 종류로 바뀌었다.
     *
     * <ul>
     *   <li>선언 전 — "non-exposed type" 위반. <b>바이트코드 참조마다 1건.</b>
     *       {@code chatweb -> user} 31건 + {@code chatweb -> OAuth} 7건 = 38건</li>
     *   <li>선언 후 — "depends on module ... Allowed targets: chat" 위반.
     *       <b>(부르는 클래스 → 불리는 타입) 쌍마다 1건.</b> 6건</li>
     * </ul>
     *
     * <p>{@code 620 - 38 + 6 = 588}. <b>같은 문제가 더 적은 줄로 보고될 뿐 하나도 안 고쳐졌다.</b>
     * 남은 6건은 {@code chatweb} 의 잘못이 아니라 {@code OAuth} 와 {@code user} 가 공개 표면을
     * 안 갖고 있어서 생기는 것이고, 표면을 정하는 것은 #104 · #105 다.
     *
     * <p>그러니 다른 모듈에 {@code allowedDependencies} 를 붙일 때마다 이 수가 또 내려간다.
     * <b>내려갔다고 좋아질 일이 아니다</b> — 어느 쪽 이유로 내려갔는지 매번 확인해라.
     */
    private static final int BASELINE_VIOLATIONS = 588;

    /** 순환 경로 개수. 쌍이 아니라 <b>경로</b>다 — 같은 두 모듈이 여러 경로에 걸쳐 나타난다. */
    private static final int BASELINE_CYCLES = 5;

    private static final char NL = (char) 10;

    private static Violations detect() {
        return ApplicationModules.of(HeatTripBackendApplication.class).detectViolations();
    }

    @Test
    @DisplayName("모듈 경계 위반이 기준선보다 늘지 않았다 (줄었으면 기준선을 내려야 한다)")
    void violationCountMatchesTheRecordedBaseline() {
        String message = detect().getMessage();
        long actual = Arrays.stream(message.split(String.valueOf(NL)))
                .filter(line -> line.startsWith("- "))
                .count();

        assertThat(actual)
                .as("""
                        모듈 경계 위반 수가 기준선(%d)과 다르다. 실측 %d.

                        늘었다면 — 남의 모듈 내부(하위 패키지)를 새로 부른 코드가 생겼다.
                          공개 표면은 모듈 패키지 *바로 아래* 타입뿐이다. chat.entity.X 처럼
                          하위 패키지를 부르면 위반이다. 개념은 #97, 우리 저장소 사정은 #98.

                        줄었다면 — 빚을 갚은 것이니 BASELINE_VIOLATIONS 를 %d 로 내려라.
                          안 내리면 그만큼 이 눈금자가 다시 무뎌진다.
                        """.formatted(BASELINE_VIOLATIONS, actual, actual))
                .isEqualTo(BASELINE_VIOLATIONS);
    }

    @Test
    @DisplayName("모듈 간 순환이 기준선보다 늘지 않았다")
    void cycleCountMatchesTheRecordedBaseline() {
        String message = detect().getMessage();
        long actual = Arrays.stream(message.split(String.valueOf(NL)))
                .filter(line -> line.trim().startsWith("- Cycle detected:"))
                .count();

        assertThat(actual)
                .as("""
                        모듈 간 순환 경로 수가 기준선(%d)과 다르다. 실측 %d.

                        2026-08-31 기준 다섯은 전부 인증 언저리다.
                          OAuth -> config -> OAuth
                          OAuth -> config -> security -> S3 -> OAuth
                          OAuth -> config -> security -> S3 -> user -> OAuth
                          OAuth -> user -> OAuth
                          config -> security -> config
                        끊는 작업은 #106 · #107 이다. 여기서 늘리지만 마라.
                        """.formatted(BASELINE_CYCLES, actual))
                .isEqualTo(BASELINE_CYCLES);
    }

    @Test
    @DisplayName("검사가 실제로 무언가를 보고 있다 — 모듈을 하나도 못 찾으면 위 단언은 의미가 없다")
    void theCheckActuallySeesModules() {
        long modules = ApplicationModules.of(HeatTripBackendApplication.class).stream().count();

        assertThat(modules)
                .as("모듈을 한 개도 못 찾았다면 위 두 단언은 0 을 0 과 비교하며 통과한다")
                .isGreaterThan(10);
    }
}
