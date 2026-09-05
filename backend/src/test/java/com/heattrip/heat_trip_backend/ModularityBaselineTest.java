package com.heattrip.heat_trip_backend;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Arrays;
import java.util.List;
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
     *
     * <p><b>588 에서 534 로 내렸다. 이번에는 진짜로 줄었다.</b> (#104)
     * {@code OAuth.principal.CurrentUser} 와 {@code UnauthenticatedException} 두 타입에
     * {@code @NamedInterface("principal")} 을 붙여 <b>공개 표면으로 선언</b>했다. 그 둘을 부르던
     * 54건이 위반이 아니게 됐다 — 자리를 옮긴 것이 아니라 "밖에서 불러도 되는 것" 이라고
     * 정한 것이다.
     *
     * <p>구분하는 법은 간단하다. <b>위반 종류가 사라졌으면 진짜, 종류가 바뀌었으면 집계다.</b>
     * 이번에는 {@code OAuth.principal} 을 가리키는 줄이 목록에서 통째로 없어졌다.
     * <p><b>231 에서 232 로 올렸다. 빚이 늘어서가 아니라 코드가 옮겨져서다.</b> (#80)
     * 429 본문을 쓰는 코드를 {@code ApiRateLimitFilter} 에서 {@code TooManyRequestsWriter} 로
     * 꺼냈다 — 채팅 필터가 같은 본문을 써야 하는데 복사하면 계약이 두 벌이 되기 때문이다.
     * {@code security -> S3.media.error.GlobalExceptionHandler} 라는 <b>모듈 쌍은 그대로이고</b>
     * 바이트코드 참조가 하나 늘었다. 위반 목록을 직접 확인했고 새 모듈 쌍은 없다.
     *
     * <p>이 참조 자체를 없애는 것은 #114 다 — 전 애플리케이션의 에러 계약이 외부 서비스 패키지
     * 밑 3단계에 있는 것이 원인이고, 그것을 옮기면 이 두 줄이 함께 사라진다.
     *
     * <p>반면 열지 않은 {@code OAuth.jwt}(14) · {@code handler}(6) · {@code state}(5) ·
     * {@code code}(4) · {@code service}(3)는 <b>그대로 위반으로 남아 있다.</b> 이게
     * {@code ::} 가 "지정한 표면만 열고 나머지는 닫는다" 는 증거다.
     *
     * <p><b>534 에서 245 로 내렸다. 한 타입 때문이다.</b> (#105)
     * {@code user.entity.User} 에 {@code @NamedInterface("entity")} 를 붙였다. {@code user} 밖의
     * 파일 34개가 이 타입을 부른다 — 사실상 이 애플리케이션의 공용 어휘다. 289건이 사라졌다.
     *
     * <p><b>같은 패키지의 {@code RefreshToken} 은 열지 않았다.</b> 밖에서의 참조가 0건이고
     * 리프레시 토큰 원장이라, 패키지째 열었다면 그게 공개 API 가 됐을 것이다.
     *
     * <p><b>중첩 타입은 부모의 표면을 물려받지 않는다.</b> {@code User$Gender} 와
     * {@code User$UserBuilder}(Lombok 생성)는 여전히 위반이다. 둘을 쓰는 곳은
     * {@code OAuth/service/CustomOAuth2UserService} 하나뿐이고 그건 #107 이 손댈 자리라 열지 않았다.
     *
     * <p><b>{@code chatweb} 에 {@code "user :: entity"} 를 더해도 이 수는 안 움직인다.</b>
     * 실제로 두 상태를 각각 재 봤고 둘 다 245 였다. 이유는 이렇다 — {@code User} 3건이 합법이
     * 되는 동시에, 남은 {@code UserRepository} 위반이 "모듈 단위 1줄" 에서 "참조별 4줄" 로
     * 되돌아간다. {@code -3 + 3 = 0}. <b>총계만 보면 아무 일도 안 일어난 것처럼 보이지만
     * 실제로는 바뀌었다</b> — 이 수 하나만 믿지 말고 위반 목록을 봐야 하는 이유다.
     *
     * <p><b>232 에서 234 로 올렸다. 이번엔 진짜 빚이다.</b> (#170)
     * 늘어난 둘은 전부 같은 줄이다 —
     * {@code community -> OAuth.principal.AuthenticatedUser}. 목록을 직접 떠서 확인했고
     * 커뮤니티가 만든 다른 모듈 쌍은 없다.
     *
     * <p>나온 자리는 {@code CommunityController.viewerId()} 하나다. 커뮤니티 읽기 셋은
     * <b>인증이 선택</b>이라 {@code @CurrentUser} 를 못 쓴다 — 그건 주입 실패를 401 로
     * 만드는 것이 설계라 게스트를 못 받는다. 그래서 {@code SecurityContext} 의 principal 을
     * 직접 읽고, 그 타입이 {@code AuthenticatedUser} 다.
     *
     * <p><b>우회로가 있는데 안 갔다.</b> {@code security.ChatRateLimitFilter} 는 같은 자리에서
     * {@code authentication.getName()} 을 써 이 위반을 피한다. 커뮤니티가 그 길을 가려면
     * 그 문자열에서 id 를 <b>파싱</b>해야 하는데(principal 이 record 라 그 값은
     * {@code AuthenticatedUser[id=7, role=ROLE_USER]} 이다), {@code AuthenticatedUser}
     * javadoc 이 <b>"principal 을 문자열로 두면 … 그 한 줄이 이 이슈의 버그였다"</b> 고
     * 적어 둔 바로 그 방향이다. 위반 2건이 그 버그로 되돌아가는 것보다 싸다.
     *
     * <p><b>{@code @NamedInterface("principal")} 로 열면 이 둘은 사라진다.</b> 그렇게 안 한
     * 이유는 그게 {@code OAuth} 의 공개 표면을 바꾸는 일이고, 그 표면은 #104 가 정했기
     * 때문이다. 커뮤니티 API 를 붙이는 PR 이 조용히 뒤집을 자리가 아니다. 제안은 #223 으로
     * 따로 냈다.
     *
     * <p><b>234 에서 232 로 내렸다 — 타입을 연 것이 아니라 자리를 만들었다.</b> (#223, ADR-0021)
     * {@code user.ViewerId} 애노테이션과 {@code OAuth.principal.ViewerIdArgumentResolver} 가
     * "보는 사람의 id" 를 주고, 커뮤니티는 {@code @ViewerId Long viewerId} 로 받는다.
     * {@code AuthenticatedUser} 를 밖에서 부르는 자리가 0 이 됐고 그 타입은 여전히 닫혀 있다.
     * 위반 목록을 떠서 사라진 둘이 정확히 그 둘인지 확인했다.
     */
    private static final int BASELINE_VIOLATIONS = 232;

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

    /**
     * <b>순환은 기준선이 아니라 게이트다.</b> (#109)
     *
     * <p>다른 검사와 달리 여기에는 숫자가 없다. #106 과 #107 이 다섯을 전부 끊어 0이 됐고,
     * 0을 숫자로 들고 있으면 <b>그 숫자를 올리고 싶은 유혹</b>이 생긴다. 숫자를 없애면 올릴
     * 자리가 없다.
     *
     * <p>순환은 다른 방법으로 끌 수 없는 유일한 검사다 — {@code type = OPEN} 으로도
     * {@code @NamedInterface} 로도 안 꺼지고, 코드를 옮겨야만 없어진다. 그래서 게이트로 올릴
     * 값이 가장 크다.
     *
     * <p><b>이 단언만으로는 부족하다.</b> 도구의 순환 보고는 순환 기저라 큰 덩어리가 쪼개지면
     * 작은 쌍을 빠뜨린다 — #106 에서 실제로 겪었다. 그래서 {@code ModuleCycleTest} 가 메시지가
     * 아니라 <b>간선</b>을 직접 훑는 검사를 따로 갖고 있다. 둘 다 있어야 한다.
     */
    @Test
    @DisplayName("모듈 간 순환이 하나도 없다 — 여기에는 기준선 숫자가 없다")
    void thereAreNoCyclesAtAll() {
        String message = detect().getMessage();
        List<String> cycles = Arrays.stream(message.split(String.valueOf(NL)))
                .map(String::trim)
                .filter(line -> line.startsWith("- Cycle detected:"))
                .toList();

        assertThat(cycles)
                .as("""
                        모듈 간 순환이 생겼다. 이 저장소는 2026-08-31 이후 순환이 0개다.

                        순환이 있으면 그 덩어리는 하나로만 떼어낼 수 있다. 그리고 읽기도 어려워진다 —
                        A 를 이해하려면 B 를 읽어야 하고 B 를 이해하려면 다시 A 를 읽어야 한다.

                        모듈 사이는 한 방향으로만 부른다. 양쪽이 서로 필요하면 공통 타입을 제3의
                        자리로 빼거나, 부르는 쪽이 인터페이스를 정의하고 상대가 구현하게 한다.
                        실제로 그렇게 끊은 기록이 #106 · #107 이다.
                        """)
                .isEmpty();
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
