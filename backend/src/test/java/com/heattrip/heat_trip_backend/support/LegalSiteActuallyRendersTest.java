package com.heattrip.heat_trip_backend.support;

import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.utility.MountableFile;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 소개·약관 페이지를 <b>실제로 받아 본다</b> — 이슈 #611.
 *
 * <h2>왜 {@code caddy validate} 로는 모자란가</h2>
 *
 * <p>{@link CaddyfileActuallyParsesTest} 는 설정이 <b>문법에 맞는지</b>만 봅니다. 그런데 이
 * 사이트의 위험은 문법이 아니라 <b>템플릿</b>입니다.
 *
 * <pre>{{markdown (include "/doc/privacy_ko.md")}}</pre>
 *
 * <p>경로가 하나 틀리거나 함수 이름이 바뀌면 설정은 멀쩡히 통과하고 <b>요청할 때</b> 비거나
 * 500 이 됩니다. 그 자리는 스토어 심사에 적어 낸 주소입니다 — 심사관이 열었을 때 비어 있으면
 * 반려입니다.
 *
 * <p>그래서 이 검사는 운영과 같은 이미지로 Caddy 를 <b>띄우고 GET 합니다.</b>
 *
 * <h2>약관 원문을 사본으로 두지 않는다</h2>
 *
 * <p>여기서 마운트하는 {@code /srv/site/doc} 는 {@code app/assets/terms/} 그 자체입니다 —
 * 앱이 설정 화면에서 읽는 바로 그 파일들입니다. 이 검사는 <b>그 파일의 실제 문장</b>이 웹에
 * 나오는지를 봅니다. 사본을 만들면 갈라지고, 갈라진 날 스토어에 올린 쪽이 거짓이 됩니다.
 */
class LegalSiteActuallyRendersTest {

    private static GenericContainer<?> caddy;
    private static HttpClient http;

    @BeforeAll
    static void startCaddy() {
        Path caddyfile = TestProjectPaths.requireFile("Caddyfile");
        Path site = TestProjectPaths.requireDirectory("site");
        Path terms = TestProjectPaths.requireDirectory("../app/assets/terms");

        // 두 사이트 다 평문 HTTP 로 연다. 이름을 주면 Caddy 가 Let's Encrypt 로 나가서
        // 검사가 네트워크에 매달린다 — 여기서 재는 것은 인증서가 아니라 **그려지는가** 다.
        caddy = new GenericContainer<>(CaddyfileActuallyParsesTest.caddyImage())
                .withCopyFileToContainer(MountableFile.forHostPath(caddyfile), "/etc/caddy/Caddyfile")
                .withCopyFileToContainer(MountableFile.forHostPath(site), "/srv/site")
                .withCopyFileToContainer(MountableFile.forHostPath(terms), "/srv/site/doc")
                .withEnv("PAWLOOP_SITE_DOMAIN", "http://:80")
                .withEnv("PAWLOOP_DOMAIN", "http://:8080")
                .withEnv("ACME_EMAIL", "you@example.com")
                .withExposedPorts(80)
                .withStartupTimeout(Duration.ofMinutes(2));
        caddy.start();
        http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();
    }

    @AfterAll
    static void stopCaddy() {
        if (caddy != null) {
            caddy.stop();
        }
    }

    private static String get(String path) {
        try {
            HttpResponse<String> res = http.send(
                    HttpRequest.newBuilder(URI.create("http://" + caddy.getHost() + ":"
                            + caddy.getMappedPort(80) + path)).GET().build(),
                    HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
            assertThat(res.statusCode()).as("%s 가 200 이 아니다", path).isEqualTo(200);
            return res.body();
        } catch (IOException | InterruptedException e) {
            throw new AssertionError(path + " 를 못 받았다", e);
        }
    }

    /**
     * 약관 원문의 <b>버전 줄</b> — 웹에 이 문장이 그대로 나와야 한다.
     *
     * <h3>첫 줄을 쓰면 안 된다</h3>
     * <p>처음에는 첫 줄({@code 개인정보처리방침})로 쟀는데, <b>그 글자가 제 템플릿의
     * {@code <h1>} 에도 있었습니다.</b> 그래서 마크다운 경로를 틀리게 해도 초록이었습니다 —
     * 되돌려 보다가 잡혔습니다. 검사가 문서가 아니라 제가 쓴 제목을 보고 있었던 겁니다.
     *
     * <p>버전 줄({@code 버전: v1.8 · 게시일: …})은 <b>문서에만</b> 있습니다. 템플릿 어디에도
     * 없고 문서마다 달라서, 이 줄이 보이면 그 파일이 실제로 읽힌 것입니다.
     */
    private static String versionLineOf(String file) {
        try {
            String line = Files.readAllLines(
                    TestProjectPaths.requireFile("../app/assets/terms/" + file),
                    StandardCharsets.UTF_8).get(1).strip();
            assertThat(line)
                    .as("%s 의 둘째 줄이 버전 줄이 아니다 — 문서 모양이 바뀌었으면 이 검사도 고친다", file)
                    .startsWith("버전:");
            return line;
        } catch (IOException e) {
            throw new AssertionError(file + " 를 못 읽었다", e);
        }
    }

    @Test
    @DisplayName("개인정보처리방침이 앱이 읽는 그 파일의 문장을 그대로 낸다 — 스토어에 적는 주소다")
    void thePrivacyPageRendersTheSameFileTheAppShips() {
        String body = get("/privacy");

        assertThat(body)
                .as("템플릿이 안 그려졌다. 설정은 통과하는데 요청할 때 비는 자리다")
                .contains(versionLineOf("privacy_ko.md"));
        assertThat(body)
                .as("마크다운이 아니라 글자가 그대로 나왔다 — {{markdown}} 이 안 돌았다")
                .contains("<p>");
    }

    @Test
    @DisplayName("이용약관·위치기반 약관도 같은 자리에서 나온다")
    void theOtherLegalPagesRenderToo() {
        assertThat(get("/terms")).contains(versionLineOf("terms_ko.md"));
        assertThat(get("/location")).contains(versionLineOf("location_ko.md"));
    }

    @Test
    @DisplayName("확장자 없는 주소로 열린다 — /privacy 를 스토어와 약관에 적는다")
    void extensionlessPathsWork() {
        // `.html` 을 붙여야만 열리면 스토어에 적은 주소가 404 가 된다.
        assertThat(get("/privacy")).contains("개인정보처리방침");
        assertThat(get("/support")).contains("mn2068@naver.com");
        assertThat(get("/")).contains("Pawloop");
    }

    @Test
    @DisplayName("소개 페이지가 약관 넷으로 가는 길을 준다 — 심사관이 한 번에 찾는다")
    void theHomePageLinksToEveryDocument() {
        String home = get("/");
        assertThat(home).contains("/terms", "/privacy", "/location", "/support");
    }

    @Test
    @DisplayName("조각 파일은 안 열린다 — 머리 없는 반쪽 문서가 검색에 잡히면 안 된다")
    void partialsAreNotServed() throws Exception {
        HttpResponse<String> res = http.send(
                HttpRequest.newBuilder(URI.create("http://" + caddy.getHost() + ":"
                        + caddy.getMappedPort(80) + "/_head.html")).GET().build(),
                HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));

        assertThat(res.statusCode()).isEqualTo(404);
    }

    @Test
    @DisplayName("원문 .md 도 그대로 열린다 — 가릴 이유가 없다")
    void theMarkdownSourceIsAlsoReadable() {
        assertThat(get("/doc/privacy_ko.md")).contains(versionLineOf("privacy_ko.md"));
    }
}
