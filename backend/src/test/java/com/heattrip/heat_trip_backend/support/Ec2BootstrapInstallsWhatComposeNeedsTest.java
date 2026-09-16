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
import java.util.stream.Collectors;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * EC2 부팅 스크립트가 <b>compose 가 실제로 쓰는 것</b>을 쓸 수 있는 상태로 갖춰 두는가
 * — 이슈 #601 · #603.
 *
 * <h2>같은 자리에서 두 번 죽었다</h2>
 *
 * <p>둘 다 이 한 줄로 끝났다.
 *
 * <pre>compose build requires buildx 0.17.0 or later</pre>
 *
 * <p><b>첫 번째(#601)</b> — 템플릿이 buildx 를 아예 안 깔았다. Amazon Linux 2023 기본
 * 저장소에는 compose 플러그인이 없어서 그건 따로 챙겼는데, buildx 는 챙기지 않았다.
 *
 * <p><b>두 번째(#603)</b> — 깔긴 깔았는데 <b>존재만 확인했다.</b>
 *
 * <pre>if ! docker buildx version &gt;/dev/null 2&gt;&amp;1; then … 최신판을 받는다 … fi</pre>
 *
 * <p>AL2023 의 {@code docker-buildx-plugin} 은 <b>0.12.1</b> 이다(2026-09-17 실측). dnf 가
 * 그걸 깔아 두니 저 조건문이 "있네" 하며 최신판 설치를 건너뛰었고, compose 는 그대로 죽었다.
 * 에러 문구에 <b>요구 버전이 적혀 있었는데도</b> "없어서 나는 에러" 로 읽은 것이다 — 없어도,
 * 있는데 낡아도 문구가 같다.
 *
 * <p>그래서 물어야 할 것은 <b>"있는가" 가 아니라 "충분히 새로운가"</b> 다. 그리고 깐 뒤에도
 * 다시 물어야 한다 — 낡은 플러그인이 검색 순서에서 이길 수 있고, 그러면 설치는 성공한 것처럼
 * 보이는데 실제로 도는 것은 여전히 낡은 것이다.
 *
 * <h2>이 검사가 못 하는 것</h2>
 *
 * <p>스크립트를 <b>돌리지 않는다</b> — 글자만 본다. "이 템플릿으로 서버가 진짜 뜬다" 는
 * {@code terraform apply} 로 인스턴스를 교체해 봐야 안다. 여기서 막는 것은 그보다 좁다:
 * <b>다음 사람이 버전 비교를 존재 확인으로 되돌리거나, 체크섬을 빼거나, 설치 뒤 확인을
 * 지우는 것.</b>
 *
 * <p>부팅 스크립트의 실패는 그 서버 안 로그에만 남는다. 밖에서는 "안 뜬다" 로만 보인다.
 */
class Ec2BootstrapInstallsWhatComposeNeedsTest {

    private static final String TEMPLATE =
            "infra/terraform/modules/ec2-docker-host/user_data.sh.tftpl";

    /**
     * {@code docker compose up --build} 한 줄이 실제로 요구하는 도커 CLI 플러그인들.
     *
     * <p>{@code name} 은 {@code docker <name>} 으로 부르는 이름이고, {@code prefix} 는
     * 템플릿이 그 플러그인의 값들을 담는 셸 변수 앞머리다 — {@code <prefix>_VERSION} ·
     * {@code <prefix>_SHA256} · {@code <prefix>_MINIMUM}.
     */
    private record Plugin(String name, String prefix) {

        String versionVar() {
            return prefix + "_VERSION";
        }

        String sha256Var() {
            return prefix + "_SHA256";
        }

        String minimumVar() {
            return prefix + "_MINIMUM";
        }
    }

    private static final List<Plugin> PLUGINS = List.of(
            new Plugin("compose", "COMPOSE"),
            new Plugin("buildx", "BUILDX"));

    @Test
    @DisplayName("실패가 조용히 지나가지 않는다 — set -euo pipefail")
    void theScriptStopsOnFailure() {
        assertThat(code())
                .as("""
                        set -e 가 없으면 중간 실패가 무시되고 부팅이 끝까지 간다. 반쯤 설정된 \
                        서버가 남고, 밖에서는 그냥 "안 뜬다" 로만 보인다.""")
                .contains("set -euo pipefail");
    }

    /**
     * 플러그인 이름으로 {@code ensure_docker_plugin} 을 부르는 줄이 있는가.
     *
     * <p>{@code contains} 로 이름만 묻지 않는다 — 되돌려 재 보고 알았다. {@code docker-buildx}
     * 를 {@code docker-buildxMUT} 로 비틀어도 비튼 이름 <b>안에</b> 원래 이름이 들어 있어서
     * 검사가 초록이었다. 그래서 줄 단위로, 그 줄이 호출로 <b>시작하는지</b>까지 본다.
     */
    @Test
    @DisplayName("compose 와 buildx 를 둘 다 갖춘다")
    void everyPluginIsEnsured() {
        String script = code();

        List<String> missing = new ArrayList<>();
        for (Plugin plugin : PLUGINS) {
            String call = "ensure_docker_plugin " + plugin.name() + " ";
            boolean ensured = script.lines().map(String::strip).anyMatch(line -> line.startsWith(call));
            if (!ensured) {
                missing.add(plugin.name());
            }
        }

        assertThat(missing)
                .as("""
                        AL2023 는 compose 플러그인이 없고 buildx 는 0.12.1 이다. 템플릿이 직접 \
                        갖추지 않으면 `docker compose up --build` 가 부팅 중에 죽는다 (#601·#603).""")
                .isEmpty();

        assertThat(script)
                .as("설치 자리가 cli-plugins 가 아니면 docker 가 그 플러그인을 못 찾는다")
                .contains("/usr/local/lib/docker/cli-plugins/docker-$name");
    }

    /**
     * 이 PR 이 생긴 이유 그 자체다 — 존재가 아니라 버전을 묻는가.
     *
     * <p>최소 버전이 없으면 "낡음" 을 정의할 수 없고, 정의할 수 없으면 있는 것을 그냥 쓴다.
     */
    @Test
    @DisplayName("플러그인마다 최소 버전이 있다 — '있는가' 가 아니라 '충분히 새로운가' 를 묻는다")
    void everyPluginDeclaresAMinimumVersion() {
        String script = code();

        List<String> missing = new ArrayList<>();
        for (Plugin plugin : PLUGINS) {
            boolean declared = script.contains(plugin.minimumVar() + "=");
            boolean used = script.contains("\"$" + plugin.minimumVar() + "\"");
            if (!declared || !used) {
                missing.add(plugin.name());
            }
        }

        assertThat(missing)
                .as("""
                        최소 버전을 정해 두고 그걸로 비교하지 않으면, dnf 가 깔아 둔 낡은 \
                        플러그인을 "있네" 하며 그대로 쓴다. 2026-09-17 에 buildx 0.12.1 로 \
                        정확히 그랬다 (#603).""")
                .isEmpty();

        assertThat(script)
                .as("버전 비교 자체가 없다 — sort -V 로 두 버전을 견주는 자리가 사라졌다")
                .contains("sort -V");
    }

    /**
     * 받은 파일을 root 로 실행한다. 확인 없이 받아 쓰면 중간에 바뀐 파일을 돌리는 셈이다.
     *
     * <p>{@code --status} 를 붙여도 종료 코드는 남으므로 {@code set -e} 가 부팅을 멈춘다.
     * 조용히 넘어가는 것이 아니라 <b>거기서 서는 것</b>이 맞다.
     */
    @Test
    @DisplayName("버전과 sha256 을 박아 두고, 깔기 전에 확인한다")
    void everyDownloadIsPinnedAndChecksummed() {
        String script = code();

        List<String> unpinned = new ArrayList<>();
        for (Plugin plugin : PLUGINS) {
            boolean pinned = script.contains(plugin.versionVar() + "=")
                    && script.contains(plugin.sha256Var() + "=");
            boolean passed = script.contains("\"$" + plugin.versionVar() + "\"")
                    && script.contains("\"$" + plugin.sha256Var() + "\"");
            if (!pinned || !passed) {
                unpinned.add(plugin.name());
            }
        }

        assertThat(unpinned)
                .as("버전·sha256 을 박아 두고 설치에 넘기는 줄이 없다")
                .isEmpty();

        int check = script.indexOf("sha256sum --check");
        int install = script.indexOf("install -m 755 \"$tmp\"");
        assertThat(check).as("sha256 확인이 없다 — 확인 없이 받아 root 로 실행하게 된다").isGreaterThan(0);
        assertThat(install).as("플러그인을 까는 줄이 없다").isGreaterThan(0);
        assertThat(check)
                .as("확인이 설치 뒤에 있다 — 확인 전에 이미 깔렸으면 확인의 뜻이 없다")
                .isLessThan(install);
    }

    /**
     * 버전을 올릴 때 주소를 같이 고치는 것을 잊으면, 새 sha256 과 옛 파일이 만나 부팅이
     * 선다. 주소를 버전 변수로 만들어 두면 그 실수 자체가 생기지 않는다.
     */
    @Test
    @DisplayName("받는 주소를 버전 변수로 만든다 — 버전만 바꾸면 주소가 따라간다")
    void downloadUrlsAreBuiltFromTheVersionVariable() {
        String script = code();

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

    /**
     * 설치는 성공했는데 도는 것은 여전히 낡은 것일 수 있다.
     *
     * <p>dnf 가 깐 플러그인은 {@code /usr/libexec/docker/cli-plugins} 에 있고 우리가 까는 것은
     * {@code /usr/local/lib/docker/cli-plugins} 에 있다. 어느 쪽이 이기는지를 <b>믿지 않고
     * 물어본다.</b> 그래야 틀렸을 때 그 자리에서, 그 이유로 선다 — 30분 뒤 compose 에러로
     * 만나는 것보다 낫다.
     */
    @Test
    @DisplayName("깔고 나서 다시 물어보고, 그래도 낡으면 거기서 부팅을 세운다")
    void theInstallIsVerifiedAfterwards() {
        String script = code();

        int install = script.indexOf("install -m 755 \"$tmp\"");
        assertThat(install).as("플러그인을 까는 줄을 못 찾았다 — 이 검사가 볼 곳이 사라졌다")
                .isGreaterThan(0);

        String afterInstall = script.substring(install);

        // 호출을 통째로 묻는다. `at_least` 만 물으면 `at_leastX` 로 비틀어도 맞는다 —
        // 이 파일에서 이미 한 번 당한 함정이다.
        assertThat(afterInstall)
                .as("""
                        깐 뒤에 버전을 다시 확인하는 줄이 없다. 낡은 플러그인이 검색 순서에서 \
                        이기면 설치는 성공한 것처럼 보이고, 실제로 도는 것은 여전히 낡은 것이다.""")
                .contains("at_least \"$minimum\" \"$have\"");

        assertThat(afterInstall)
                .as("""
                        확인만 하고 넘어간다. 여기서 서지 않으면 그 실패를 30분 뒤 compose \
                        에러로 만난다 — 그때는 원인이 안 보인다 (#603).""")
                .contains("exit 1");
    }

    /**
     * 주석 줄을 뺀 스크립트.
     *
     * <p>주석이 만족시킬 수 있는 검사는 검사가 아니다. 되돌려 재 보고 알았다 —
     * {@code sort -V} 를 코드에서 {@code sort -n} 으로 비틀었는데도 초록이었다.
     * 바로 위 주석에 "sort -V 로 정렬해" 라고 적어 둔 그 글자에 맞은 것이다.
     *
     * <p>줄 전체가 {@code #} 로 시작하는 것만 뺀다. 코드 뒤에 붙은 {@code # 설명} 까지
     * 떼려면 따옴표를 따라가며 걸어야 하는데, 여기서 재는 것들은 전부 줄 앞머리에 있어서
     * 그렇게까지 할 일이 없다.
     */
    private static String code() {
        return template().lines()
                .filter(line -> !line.strip().startsWith("#"))
                .collect(Collectors.joining("\n"));
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
