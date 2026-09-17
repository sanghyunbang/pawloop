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
 * prod 부팅 스크립트가 <b>살아 있는 DB 를 포맷하지 않는가</b> — 이슈 #609.
 *
 * <h2>왜 이 검사가 있나</h2>
 *
 * <p>prod 는 DB 를 서버와 다른 디스크(별도 EBS 볼륨)에 둡니다. 부팅 스크립트를 고치면
 * {@code user_data_replace_on_change} 때문에 인스턴스가 교체되는데, 그때 root 볼륨은
 * 사라지고 이 볼륨만 남습니다. 새 인스턴스가 그 볼륨을 다시 붙입니다.
 *
 * <p>그 "다시 붙이는" 코드가 이 저장소에서 <b>가장 위험한 자리</b>입니다. 한 줄만 어긋나면
 * 데이터가 든 볼륨을 새 볼륨으로 착각해 포맷합니다. 그리고 그 실패는 <b>그 서버 안
 * 로그에만</b> 남습니다 — 밖에서는 "DB 가 비었다" 로만 보입니다.
 *
 * <h2>이 검사가 못 하는 것</h2>
 *
 * <p>스크립트를 돌리지 않습니다 — 글자만 봅니다. 실제 동작은 리눅스에서 가짜 명령을 끼워
 * 네 경우(빈 볼륨 / 기존 파일시스템 / 볼륨 없음 / 마운트 실패)를 돌려 확인했고, 그 기록은
 * PR 에 있습니다. 여기서 막는 것은 <b>다음 사람이 이 안전장치를 지우는 것</b>입니다.
 */
class ProdBootstrapKeepsTheDatabaseTest {

    private static final String TEMPLATE =
            "infra/terraform/envs/prod/backend/user_data_backend.sh.tftpl";

    @Test
    @DisplayName("실패가 조용히 지나가지 않는다 — set -euo pipefail 을 받는 자리에 있다")
    void theScriptRunsUnderSetE() {
        // 이 조각은 모듈의 user_data.sh.tftpl 안으로 들어가고, 거기서 set -e 가 걸린다.
        // 그 파일이 그 줄을 유지하는지는 Ec2BootstrapInstallsWhatComposeNeedsTest 가 잰다.
        assertThat(code())
                .as("모듈 템플릿이 이 조각을 ${startup_commands} 로 받는다는 전제가 깨졌다")
                .contains("docker compose -f docker-compose.yml -f docker-compose.prod.yml");
    }

    /**
     * 이 파일에서 제일 중요한 한 줄.
     *
     * <p>{@code blkid} 가 성공하면 그 장치에는 이미 파일시스템이 있다는 뜻이고, 그러면
     * <b>절대 {@code mkfs} 를 부르면 안 된다.</b> 이 조건이 사라지면 인스턴스를 교체할
     * 때마다 DB 가 초기화된다.
     */
    @Test
    @DisplayName("이미 파일시스템이 있으면 포맷하지 않는다")
    void anExistingFilesystemIsNeverReformatted() {
        List<String> lines = code().lines().map(String::strip).toList();

        int guard = indexOfLineStartingWith(lines, "if blkid \"$DATA_DEV\"");
        assertThat(guard)
                .as("""
                        blkid 로 기존 파일시스템을 확인하는 줄이 없다. 이 확인이 없으면 \
                        인스턴스를 교체할 때마다 DB 를 포맷한다 (#609).""")
                .isGreaterThanOrEqualTo(0);

        // 순서만 보면 안 된다 — 되돌려 재 보고 알았다.
        //
        // 처음에는 "확인이 포맷보다 앞에 있다" 로 물었는데, mkfs 를 `fi` **바깥으로**
        // 옮겨 조건 없이 돌게 만들어도 통과했다. 순서는 그대로였기 때문이다.
        // 그래서 포맷이 그 if 블록 **안에** 있는지를 본다.
        int closing = matchingFi(lines, guard);
        assertThat(closing).as("blkid 확인의 fi 를 못 찾았다 — 스크립트 구조가 바뀌었다")
                .isGreaterThan(guard);

        List<String> guarded = lines.subList(guard, closing);
        assertThat(guarded)
                .as("""
                        포맷하는 줄이 blkid 확인 블록 밖에 있다. 그러면 조건과 무관하게 \
                        매번 돌고, 인스턴스를 교체할 때마다 DB 가 초기화된다 (#609).""")
                .anyMatch(line -> line.startsWith("mkfs "));

        assertThat(lines)
                .as("포맷하는 줄이 블록 밖에도 있다")
                .filteredOn(line -> line.startsWith("mkfs "))
                .hasSize(1);
    }

    /** {@code prefix} 로 시작하는 첫 줄의 번호. 없으면 -1. */
    private static int indexOfLineStartingWith(List<String> lines, String prefix) {
        for (int i = 0; i < lines.size(); i++) {
            if (lines.get(i).startsWith(prefix)) {
                return i;
            }
        }
        return -1;
    }

    /** {@code ifLine} 에서 시작한 블록을 닫는 {@code fi} 의 줄 번호. 중첩을 센다. */
    private static int matchingFi(List<String> lines, int ifLine) {
        int depth = 0;
        for (int i = ifLine; i < lines.size(); i++) {
            String line = lines.get(i);
            if (line.startsWith("if ")) {
                depth++;
            } else if (line.equals("fi")) {
                depth--;
                if (depth == 0) {
                    return i;
                }
            }
        }
        return -1;
    }

    /**
     * 장치 이름을 믿지 않는다.
     *
     * <p>terraform 은 {@code /dev/sdf} 로 붙이지만 Nitro 인스턴스에서는 {@code /dev/nvme?n?}
     * 로 나타나고 번호 순서도 보장되지 않습니다. 이름으로 찍으면 <b>root 볼륨을 포맷할 수
     * 있습니다.</b> AWS 는 NVMe 시리얼에 볼륨 ID 를 대시 없이 넣어 주므로 그것으로 찾습니다.
     */
    @Test
    @DisplayName("장치를 이름이 아니라 볼륨 ID 로 찾는다")
    void theDeviceIsFoundByVolumeIdNotByName() {
        String script = code();

        assertThat(script)
                .as("""
                        볼륨 ID 에서 대시를 뺀 NVMe 시리얼로 찾지 않는다. /dev/sdf 나 \
                        /dev/nvme1n1 을 그대로 믿으면 root 볼륨을 잡을 수 있다.""")
                .contains("tr -d '-'")
                .contains("lsblk -ndo NAME,SERIAL");

        assertThat(script.lines().map(String::strip))
                .as("장치 경로를 손으로 적은 줄이 있다")
                .noneMatch(line -> line.startsWith("DATA_DEV=/dev/"));
    }

    /**
     * 볼륨이 없거나 마운트가 안 되면 <b>거기서 서야 한다.</b>
     *
     * <p>그냥 넘어가면 MySQL 이 컨테이너 안의 빈 디렉터리에 새 DB 를 만듭니다. 서버는
     * 멀쩡히 뜨고, 앱도 동작하고, 데이터만 없습니다 — 사람이 알아채기까지 오래 걸리는
     * 종류이고 그사이 새 데이터가 그 임시 자리에 쌓입니다.
     */
    @Test
    @DisplayName("볼륨이 없거나 마운트가 안 되면 부팅을 세운다")
    void aMissingVolumeStopsTheBoot() {
        String script = code();

        assertThat(script)
                .as("볼륨을 못 찾았을 때 종료하는 줄이 없다")
                .contains("DB 볼륨을 찾았다");

        assertThat(script)
                .as("""
                        마운트를 확인하지 않는다. 확인 없이 넘어가면 MySQL 이 빈 디렉터리에 \
                        새 DB 를 만들고, 서버는 멀쩡히 뜬다 — 데이터만 없다.""")
                .contains("mountpoint -q");

        // exit 1 이 두 번(볼륨 못 찾음 · 마운트 안 됨) 있어야 한다.
        long stops = script.lines().map(String::strip).filter(line -> line.equals("exit 1")).count();
        assertThat(stops)
                .as("멈추는 자리가 둘(볼륨 못 찾음 · 마운트 안 됨)이어야 한다")
                .isGreaterThanOrEqualTo(2);
    }

    /**
     * 앱 포트를 루프백에만 묶는다.
     *
     * <p>밖에서 오는 것은 전부 Caddy(443)를 지나야 actuator 차단과 X-Real-IP 주입이
     * 적용됩니다(#613). 8080 이 밖으로 열리면 그 둘을 우회할 수 있습니다.
     */
    @Test
    @DisplayName("앱 포트를 루프백에 묶는다 — 밖에서 오는 것은 Caddy 를 지나야 한다")
    void theAppPortIsBoundToLoopback() {
        assertThat(code())
                .as("""
                        APP_PUBLISHED_HOST 를 127.0.0.1 로 고정하지 않는다. 8080 이 밖으로 \
                        열리면 actuator 차단과 X-Real-IP 주입을 우회할 수 있다 (#613).""")
                .contains("set_env_value APP_PUBLISHED_HOST 127.0.0.1");
    }

    /**
     * 덧붙이기 전에 줄바꿈을 확인한다.
     *
     * <p>staging 에서 마지막 줄에 줄바꿈이 없는 {@code .env} 에 한 줄을 덧붙였다가
     * {@code TOUR_API_SECRET=xxxAPP_PUBLISHED_HOST=0.0.0.0} 이 됐습니다 — 마지막 키의
     * 값까지 같이 망가졌습니다 (#600).
     */
    @Test
    @DisplayName(".env 에 덧붙이기 전에 마지막 줄바꿈을 확인한다")
    void appendingToEnvDoesNotGlueLines() {
        assertThat(code())
                .as("줄바꿈 확인 없이 .env 에 덧붙이면 마지막 값에 달라붙는다 (#600)")
                .contains("tail -c1 .env");
    }

    /** 주석 줄을 뺀 스크립트 — 주석이 만족시킬 수 있는 검사는 검사가 아니다. */
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
            throw new UncheckedIOException("prod 부팅 스크립트를 읽지 못했다: " + path, e);
        }
    }
}
