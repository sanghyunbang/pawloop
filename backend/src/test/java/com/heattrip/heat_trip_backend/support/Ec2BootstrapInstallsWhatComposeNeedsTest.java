package com.heattrip.heat_trip_backend.support;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * EC2 부팅 스크립트가 <b>compose 가 실제로 쓰는 것</b>을 다 깔아 두는가 — 이슈 #601.
 *
 * <h2>왜 이 검사가 생겼나</h2>
 *
 * <p>2026-09-16 첫 staging 배포에서 인스턴스는 떴는데 앱이 없었다. 원인은 이 한 줄이었다.
 *
 * <pre>compose build requires buildx 0.17.0 or later</pre>
 *
 * <p>Amazon Linux 2023 기본 저장소에는 compose 플러그인도 buildx 플러그인도 없다. 템플릿은
 * compose 만 챙겼고 buildx 는 챙기지 않았다. 지금의 {@code docker compose} 는 이미지를 직접
 * 만들지 않고 buildx 에 넘기므로, <b>이미지를 "받는" 데까지는 지나가고 "만드는" 자리에서만
 * 걸린다.</b> 로그가 한참 진행되다 끝나서 성공처럼 보였다.
 *
 * <h2>무엇을 재는가</h2>
 *
 * <p>이 검사는 스크립트를 <b>돌리지 않는다</b> — 글자만 본다. 그러니 "이 템플릿으로 서버가
 * 진짜 뜬다" 를 증명하지는 못한다. 그건 {@code terraform apply} 로 인스턴스를 교체해 봐야
 * 안다. 여기서 막는 것은 그보다 좁다: <b>다음 사람이 플러그인 설치 블록을 지우거나, 체크섬
 * 확인을 빼거나, 실패를 조용히 삼키게 바꾸는 것</b>이다.
 *
 * <p>부팅 스크립트의 실패는 그 서버 안 로그에만 남는다. 밖에서는 "안 뜬다" 로만 보인다 —
 * 그래서 이 계열의 실수는 언제나 비싸다.
 */
class Ec2BootstrapInstallsWhatComposeNeedsTest {

    private static final String TEMPLATE =
            "infra/terraform/modules/ec2-docker-host/user_data.sh.tftpl";

    /**
     * {@code docker compose up --build} 한 줄이 실제로 요구하는 도커 CLI 플러그인들.
     *
     * <p>{@code name} 은 {@code docker <name>} 으로 부르는 이름이자 {@code cli-plugins} 에
     * 놓이는 파일 이름이고, {@code versionVar} 는 템플릿이 버전을 담는 셸 변수다.
     */
    private record Plugin(String name, String versionVar) {
    }

    private static final List<Plugin> PLUGINS = List.of(
            new Plugin("compose", "COMPOSE_VERSION"),
            new Plugin("buildx", "BUILDX_VERSION"));

    @Test
    @DisplayName("실패가 조용히 지나가지 않는다 — set -euo pipefail")
    void theScriptStopsOnFailure() {
        String script = template();

        assertThat(script)
                .as("""
                        set -e 가 없으면 중간 실패가 무시되고 부팅이 끝까지 간다. 반쯤 설정된 \
                        서버가 남고, 밖에서는 그냥 "안 뜬다" 로만 보인다.""")
                .contains("set -euo pipefail");
    }

    /**
     * 경로를 {@code contains} 로 물으면 안 된다 — 되돌려 재 보고 알았다.
     *
     * <p>{@code docker-buildx} 를 {@code docker-buildxMUT} 로 비틀어도 검사가 초록이었다.
     * 비튼 이름 <b>안에</b> 원래 이름이 그대로 들어 있어서다. 그래서 줄 단위로, 그 줄이
     * 실제 {@code install} 명령이고 그 경로로 <b>끝나는지</b>까지 본다.
     */
    @Test
    @DisplayName("compose 와 buildx 를 둘 다 cli-plugins 에 깐다")
    void everyPluginGetsInstalled() {
        String script = template();

        List<String> missing = new ArrayList<>();
        for (Plugin plugin : PLUGINS) {
            String target = "/usr/local/lib/docker/cli-plugins/docker-" + plugin.name();
            boolean installed = script.lines()
                    .map(String::strip)
                    .anyMatch(line -> line.startsWith("install ") && line.endsWith(target));
            if (!installed) {
                missing.add(plugin.name());
            }
        }

        assertThat(missing)
                .as("""
                        AL2023 기본 저장소에는 이 플러그인들이 없다. 템플릿이 직접 깔지 않으면 \
                        `docker compose up --build` 가 부팅 중에 죽는다 (#601).""")
                .isEmpty();
    }

    /**
     * 받은 파일을 root 로 실행한다. 확인 없이 받아 쓰면 중간에 바뀐 파일을 돌리는 셈이다.
     *
     * <p>{@code --status} 를 붙여도 종료 코드는 남으므로 {@code set -e} 가 부팅을 멈춘다.
     * 조용히 넘어가는 것이 아니라 <b>거기서 서는 것</b>이 맞다.
     */
    @Test
    @DisplayName("받은 바이너리를 sha256 으로 확인한 뒤에 깐다")
    void everyDownloadIsChecksumVerified() {
        String script = template();

        List<String> unverified = new ArrayList<>();
        for (Plugin plugin : PLUGINS) {
            String shaVar = plugin.versionVar().replace("_VERSION", "_SHA256");
            boolean pinned = script.contains(shaVar + "=");
            boolean checked = script.contains("\"$" + shaVar + "  $")
                    && script.contains("sha256sum --check");
            if (!pinned || !checked) {
                unverified.add(plugin.name());
            }
        }

        assertThat(unverified)
                .as("""
                        sha256 을 박아 두고 확인하는 줄이 없다. 확인 없이 받아 root 로 실행하면 \
                        중간에 바뀐 파일을 그대로 돌린다.""")
                .isEmpty();
    }

    /**
     * 버전을 올릴 때 주소를 같이 고치는 것을 잊으면, 새 sha256 과 옛 파일이 만나 부팅이
     * 선다. 주소를 버전 변수로 만들어 두면 그 실수 자체가 생기지 않는다.
     */
    @Test
    @DisplayName("받는 주소를 버전 변수로 만든다 — 버전만 바꾸면 주소가 따라간다")
    void downloadUrlsAreBuiltFromTheVersionVariable() {
        String script = template();

        List<String> hardcoded = new ArrayList<>();
        for (Plugin plugin : PLUGINS) {
            boolean built = script.lines()
                    .filter(line -> line.contains("https://github.com/docker/" + plugin.name()))
                    .anyMatch(line -> line.contains("$" + plugin.versionVar()));
            if (!built) {
                hardcoded.add(plugin.name());
            }
        }

        assertThat(hardcoded)
                .as("""
                        받는 주소에 버전이 그대로 박혀 있다. 버전만 올리면 새 sha256 과 옛 \
                        파일이 만나 부팅이 선다.""")
                .isEmpty();
    }

    private static String template() {
        Path path = TestProjectPaths.requireFile(TEMPLATE);
        try {
            return Files.readString(path, StandardCharsets.UTF_8).replace("\r\n", "\n");
        } catch (IOException e) {
            throw new UncheckedIOException("부팅 스크립트 템플릿을 읽지 못했다: " + path, e);
        }
    }
}
