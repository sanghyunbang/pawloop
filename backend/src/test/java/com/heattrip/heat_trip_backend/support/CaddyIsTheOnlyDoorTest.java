package com.heattrip.heat_trip_backend.support;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.stream.Collectors;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * prod 의 바깥문이 제 일을 하는가 — 이슈 #609 · #613.
 *
 * <p>prod 는 443 을 <b>세상에 엽니다.</b> 지금까지는 방화벽이 IP 하나만 열어 둬서 무엇이
 * 잘못돼도 밖에서 보이지 않았습니다. 앞에 세우는 Caddy 가 두 가지를 합니다.
 *
 * <ol>
 *   <li><b>{@code X-Real-IP} 주입</b> — 없으면 rate limit 이 통째로 무너진다</li>
 *   <li><b>actuator 차단</b> — {@code /actuator/prometheus} 는 밖에서 보이면 안 된다</li>
 * </ol>
 *
 * <p>둘 다 <b>지워도 아무 에러가 안 나는</b> 종류입니다. 그래서 검사로 잠급니다.
 *
 * <h2>이 검사가 못 하는 것</h2>
 *
 * <p>Caddy 를 띄우지 않습니다 — 설정 글자만 봅니다. "진짜로 막혔는가" 는 서버가 뜬 뒤
 * 밖에서 찔러 봐야 압니다. #601·#603 에서 <b>글자 검사가 전부 초록인데 서버가 안 뜬</b>
 * 일을 두 번 겪었습니다. 그 확인은 #613 의 완료 조건에 있습니다.
 */
class CaddyIsTheOnlyDoorTest {

    private static final String CADDYFILE = "Caddyfile";

    /**
     * 앱으로 넘기는 자리마다 실제 클라이언트 주소를 붙이는가.
     *
     * <p>{@code ClientIpResolver} 는 벽을 둘 세워 뒀다(#14) — 연결 상대가 신뢰 프록시가
     * 아니면 헤더를 아예 안 읽고, 읽을 때는 목록의 마지막 원소를 쓴다. Caddy 는 도커
     * 네트워크(172.x) 안이라 신뢰 프록시로 인정되지만, <b>기본으로 {@code X-Real-IP} 를
     * 붙이지 않는다.</b>
     *
     * <p>그러면 {@code resolve()} 가 연결 상대(= Caddy 의 IP)로 떨어지고 <b>전 세계가
     * 카운터 하나를 공유한다.</b> 로그인 한도 10/분이 서비스 전체 합계가 된다 — 증상은
     * "가끔 로그인이 429" 로만 보인다.
     */
    @Test
    @DisplayName("앱으로 넘기는 자리마다 X-Real-IP 를 붙인다 — 하나라도 빠지면 그 경로의 한도가 사라진다")
    void everyReverseProxySetsTheRealClientIp() {
        List<String> lines = code();

        long proxies = lines.stream().filter(line -> line.startsWith("reverse_proxy ")).count();
        long headers = lines.stream().filter(line -> line.equals("header_up X-Real-IP {remote_host}")).count();

        assertThat(proxies)
                .as("앱으로 넘기는 자리가 하나도 없다 — 이 검사가 볼 곳이 사라졌다")
                .isGreaterThan(0);
        assertThat(headers)
                .as("""
                        X-Real-IP 를 붙이는 줄 수가 앱으로 넘기는 자리 수와 다르다. 빠진 \
                        경로는 rate limit 이 전 세계 공용 카운터 하나로 무너진다 (#613).""")
                .isEqualTo(proxies);
    }

    /**
     * {@code /actuator/prometheus} 는 <b>공개이면서 rate limit 까지 면제</b>다.
     *
     * <p>지표 수집기가 주기적으로 부르라고 그렇게 둔 것이고({@code
     * PublicPathsAreRateLimitedTest} 가 그 예외를 적어 뒀다), 그 판단의 전제가 "내부망"
     * 이었다. 밖에 열리면 엔드포인트 이름·호출 수·에러율·JVM·DB 커넥션 상태가 누구에게나,
     * 횟수 제한 없이 나간다.
     */
    @Test
    @DisplayName("actuator 는 health 만 통과시키고 나머지는 막는다")
    void actuatorIsClosedExceptHealth() {
        List<String> lines = code();
        String joined = String.join("\n", lines);

        assertThat(joined)
                .as("health 를 통과시키는 matcher 가 없다 — 우리 확인 스크립트가 이 경로를 쓴다")
                .contains("@actuator_public path /actuator/health /actuator/health/*");

        assertThat(joined)
                .as("""
                        나머지 actuator 를 막는 handle 이 없다. /actuator/prometheus 는 \
                        공개이면서 한도까지 면제라 그대로 열리면 안 된다 (#613).""")
                .contains("handle /actuator /actuator/*");

        // 순서가 뒤집히면 차단이 먼저 걸려 health 까지 404 가 된다.
        assertThat(joined.indexOf("@actuator_public"))
                .as("health 를 통과시키는 자리가 차단보다 뒤에 있다 — 그러면 health 도 막힌다")
                .isLessThan(joined.indexOf("handle /actuator /actuator/*"));

        assertThat(joined)
                .as("막는 자리가 404 를 돌려주지 않는다")
                .contains("respond 404");
    }

    /**
     * 인증서 만료 경고를 받을 주소가 있는가.
     *
     * <p>비워 두면 Caddy 가 익명으로 발급받는다. 그러면 자동 갱신이 조용히 실패해도 알 수
     * 없고, <b>어느 날 갑자기 로그인이 전부 죽는다</b> — 구글·카카오·애플의 리다이렉트가
     * 전부 이 도메인의 https 다.
     */
    @Test
    @DisplayName("인증서 만료 경고를 받을 주소를 설정한다")
    void certificateExpiryWarningsHaveSomewhereToGo() {
        assertThat(String.join("\n", code()))
                .as("email 설정이 없다 — 익명 발급이라 갱신 실패를 알 방법이 없다")
                .contains("email {$ACME_EMAIL}");
    }

    /**
     * 도메인을 파일에 박아 두지 않는다.
     *
     * <p>terraform 의 {@code domain_name} 이 정본이고 부팅 스크립트가 {@code .env} 에 써
     * 넣는다. 여기 박아 두면 두 곳이 갈라지고, 갈라진 쪽이 인증서를 못 받는다.
     */
    @Test
    @DisplayName("도메인은 환경변수로 받는다 — 파일에 박아 두지 않는다")
    void theDomainComesFromTheEnvironment() {
        List<String> lines = code();

        assertThat(String.join("\n", lines))
                .as("도메인을 환경변수로 받지 않는다")
                .contains("{$PAWLOOP_DOMAIN}");

        assertThat(lines)
                .as("도메인을 파일에 박아 뒀다. terraform 의 domain_name 이 정본이다")
                .noneMatch(line -> line.contains("pawloop.app {"));
    }

    /** 주석 줄을 뺀 설정 — 주석이 만족시킬 수 있는 검사는 검사가 아니다. */
    private static List<String> code() {
        Path path = TestProjectPaths.requireFile(CADDYFILE);
        try {
            return Files.readString(path, StandardCharsets.UTF_8)
                    .replace("\r\n", "\n")
                    .lines()
                    .map(String::strip)
                    .filter(line -> !line.startsWith("#"))
                    .filter(line -> !line.isEmpty())
                    .collect(Collectors.toList());
        } catch (IOException e) {
            throw new UncheckedIOException("Caddyfile 을 읽지 못했다: " + path, e);
        }
    }
}
