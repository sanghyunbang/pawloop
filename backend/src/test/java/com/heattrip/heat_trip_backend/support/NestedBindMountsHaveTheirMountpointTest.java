package com.heattrip.heat_trip_backend.support;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.yaml.snakeyaml.Yaml;

import java.io.IOException;
import java.io.Reader;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * mount 안에 mount 를 겹칠 때 <b>그 자리가 미리 있는가</b> — 이슈 #639.
 *
 * <h2>왜 이 검사가 생겼나</h2>
 *
 * <p>2026-09-17 prod 배포에서 Caddy 컨테이너가 <b>시작조차 못 했습니다.</b> 부팅 스크립트는
 * 끝까지 갔는데 80·443 이 조용했고, Caddy 가 {@code api.pawloop.app} 과 {@code pawloop.app}
 * 양쪽의 앞문이라 <b>API 까지 같이 죽었습니다.</b>
 *
 * <pre>
 * error mounting "/opt/pawloop-backend/repo/app/assets/terms" to rootfs at "/srv/site/doc":
 * create mountpoint for /srv/site/doc mount: read-only file system
 * </pre>
 *
 * <p>{@code docker-compose.prod.yml} 이 mount 를 둘 겹쳐 겁니다.
 *
 * <pre>
 * - ./site:/srv/site:ro
 * - ../app/assets/terms:/srv/site/doc:ro
 * </pre>
 *
 * <p>둘째가 놓이는 자리가 첫째 mount <b>안</b>입니다. 도커는 거기 얹으려면 {@code doc} 을 먼저
 * 만들어야 하는데, {@code /srv/site} 가 이미 <b>읽기 전용</b>이라 못 만듭니다. 그리고
 * {@code backend/site/} 에 {@code doc} 이 없었습니다.
 *
 * <h2>규칙은 "모든 mount" 가 아니라 "겹친 mount" 다</h2>
 *
 * <p>직접 재 봤습니다. 겹치지 <b>않는</b> mount 는 자리가 없어도 도커가 만들어 줍니다 —
 * {@code /nowhere/deep/doc} 로 걸어도 잘 뜹니다. 못 만드는 것은 <b>읽기 전용으로 덮인 자리
 * 안</b>일 때뿐입니다. 그래서 이 검사는 겹친 짝만 골라 봅니다. 전부를 재면 {@code /mnt/data}
 * 처럼 서버에만 있는 경로에서 없는 빨간불이 납니다.
 *
 * <h2>이미 있던 검사 셋이 전부 초록이었다</h2>
 *
 * <p>{@link LegalSiteActuallyRendersTest} 는 <b>같은 파일 둘을 같은 자리에</b> 올려 페이지를
 * 그려 보고 있었습니다. 그런데 그 검사는 mount 가 아니라 <b>복사</b>를 씁니다
 * ({@code withCopyFileToContainer}). 복사는 컨테이너의 쓰기 가능한 층에 들어가므로 {@code doc}
 * 이 그냥 만들어집니다 — 운영이 하는 일과 다른 일을 하고 있었던 겁니다.
 * {@link CaddyfileActuallyParsesTest} 는 Caddyfile 문법만 보고 compose 를 안 봅니다.
 *
 * <p>그래서 이 검사는 <b>compose 파일 자체를 읽습니다.</b> 운영이 그 파일로 뜨기 때문입니다.
 *
 * <h2>왜 파일을 전부 훑나</h2>
 *
 * <p>겹친 짝은 <b>한 서비스의 최종 mount 목록</b>에서 생깁니다. 어느 덧붙임 조합으로 띄우는지를
 * 여기에 또 적으면 조합이 늘 때마다 이 검사가 낡습니다. 그래서 {@code backend/} 의 compose 를
 * 전부 읽고 서비스별로 <b>합집합</b>을 봅니다 — 넓게 잡는 쪽으로 틀립니다. 못 보고 넘어가는
 * 것보다 낫습니다.
 *
 * @see BootAssetsTravelWithTheCloneTest 같은 모양의 실패 — 새로 클론한 곳에 없어서 부팅이 막힘
 */
class NestedBindMountsHaveTheirMountpointTest {

    /** compose 의 bind mount 한 줄. {@code source} 는 compose 에 적힌 그대로다. */
    private record Mount(String service, String composeFile, String source, String target) {

        /** 이 mount 가 {@code outer} <b>안</b>에 놓이는가. 같은 자리는 겹친 것이 아니다. */
        boolean isNestedIn(Mount outer) {
            return target.startsWith(outer.target + "/");
        }

        /**
         * {@code outer} 안에 겹칠 때, 호스트에 <b>미리 있어야 하는 디렉터리</b>.
         *
         * <p>{@code /srv/site} 가 {@code ./site} 에서 오고 내가 {@code /srv/site/doc} 이면,
         * 있어야 하는 것은 {@code backend/site/doc} 이다.
         */
        Path mountpointUnder(Mount outer) {
            String relative = target.substring(outer.target.length() + 1);
            return hostPathOf(outer.source).resolve(relative);
        }
    }

    /**
     * compose 에 적힌 경로를 실제 경로로 바꾼다.
     *
     * <p>compose 의 상대 경로는 <b>프로젝트 디렉터리</b>(= 이 저장소에서는 {@code backend/})
     * 기준이다. 절대 경로({@code /mnt/data/...})면 {@code resolve} 가 그대로 돌려준다.
     */
    private static Path hostPathOf(String source) {
        return TestProjectPaths.backendDir().resolve(source).normalize();
    }

    @Test
    @DisplayName("겹친 mount 의 자리가 저장소에 있다 — 없으면 컨테이너가 시작조차 못 한다")
    void everyNestedMountHasItsMountpoint() {
        List<String> missing = new ArrayList<>();
        for (Nesting nesting : findNestings()) {
            if (!Files.isDirectory(nesting.mountpoint())) {
                missing.add(nesting.describe() + "\n      → 없다: " + nesting.mountpoint());
            }
        }

        assertThat(missing)
                .as("""
                        겹친 mount 의 자리가 없다. 도커는 읽기 전용으로 덮인 디렉터리 안에 \
                        마운트포인트를 만들지 못하므로, 이대로 배포하면 그 컨테이너가 \
                        **시작조차 못 한다**. Caddy 가 그렇게 죽으면 api 까지 같이 죽는다 (#639).
                        빈 디렉터리는 git 이 저장하지 못하니 `.gitkeep` 같은 파일을 하나 둔다.""")
                .isEmpty();
    }

    /**
     * 자리가 <b>비어 있지 않아야</b> 하는 이유.
     *
     * <p>git 은 빈 디렉터리를 저장하지 못한다. 안에 파일이 없으면 <b>내 기계에만</b> 남고
     * 새로 클론한 곳에는 없다 — EC2 부팅은 매번 새 {@code git clone} 이라 거기서 죽는다.
     * {@code .gitkeep} 을 "안 쓰는 빈 파일" 로 보고 지우는 것이 가장 쉬운 되돌림이라, 그
     * 한 걸음을 따로 잡는다. #591 이 정확히 이 함정이었다.
     */
    @Test
    @DisplayName("그 자리가 비어 있지 않다 — git 은 빈 디렉터리를 클론에 실어 주지 않는다")
    void everyMountpointSurvivesAFreshClone() {
        List<String> empty = new ArrayList<>();
        for (Nesting nesting : findNestings()) {
            Path mountpoint = nesting.mountpoint();
            if (Files.isDirectory(mountpoint) && isEmpty(mountpoint)) {
                empty.add(nesting.describe() + "\n      → 비어 있다: " + mountpoint);
            }
        }

        assertThat(empty)
                .as("""
                        자리는 있는데 비어 있다. 지금 이 기계에서는 되지만 **새로 클론한 곳에는 \
                        그 디렉터리가 없다** — git 이 빈 디렉터리를 저장하지 않기 때문이다. \
                        EC2 는 매번 새로 클론하므로 인스턴스를 교체하는 날 죽는다 (#639 · #591).
                        왜 있어야 하는지 적은 `.gitkeep` 을 둔다.""")
                .isEmpty();
    }

    /**
     * 이 검사가 <b>무언가를 보고 있는지</b> 확인한다.
     *
     * <p>YAML 모양이 바뀌거나 내 파싱이 틀리면 겹친 짝을 0개 찾고, 그러면 위 둘은 빈 목록을
     * 재며 <b>조용히 초록</b>이 된다. 아무것도 검증하지 않는 초록은 게이트가 아니다 —
     * {@link TestProjectPaths} 의 주석이 같은 말을 하고 있다.
     */
    @Test
    @DisplayName("겹친 짝을 실제로 찾아냈다 — 0개를 훑고 초록이면 이 검사는 없는 것이다")
    void theScanActuallySeesTheNesting() {
        List<Nesting> nestings = findNestings();

        assertThat(nestings)
                .as("""
                        compose 에서 겹친 mount 를 하나도 못 찾았다. 겹침이 정말 사라졌거나, \
                        YAML 모양이 바뀌어 파싱이 헛돌고 있다. 후자면 이 검사는 초록인 채로 \
                        아무것도 안 지킨다 — 어느 쪽인지 확인하고 이 검사를 고친다.""")
                .isNotEmpty();

        assertThat(nestings)
                .extracting(n -> n.inner().target())
                .as("약관 원문이 site 안에 겹쳐 들어가는 그 자리를 못 봤다 (#611 · #639)")
                .contains("/srv/site/doc");
    }

    // ── compose 읽기 ────────────────────────────────────────────────────────

    /** 겹친 짝 하나. {@code inner} 가 {@code outer} 안에 놓인다. */
    private record Nesting(Mount outer, Mount inner) {

        Path mountpoint() {
            return inner.mountpointUnder(outer);
        }

        String describe() {
            return "  [%s] %s\n      %s:%s  안에\n      %s:%s  이 겹친다"
                    .formatted(inner.composeFile(), inner.service(),
                            outer.source(), outer.target(),
                            inner.source(), inner.target());
        }
    }

    /**
     * {@code backend/} 의 compose 를 전부 읽어 <b>서비스별로</b> 겹친 짝을 찾는다.
     *
     * <p>서로 다른 서비스의 mount 는 겹칠 수 없다 — 각자 다른 컨테이너다. 같은 서비스의
     * mount 는 덧붙임 파일을 가로질러 합친다(compose 가 자리 기준으로 병합한다).
     */
    private static List<Nesting> findNestings() {
        Map<String, Map<String, Mount>> byServiceThenTarget = new LinkedHashMap<>();
        for (Path compose : composeFiles()) {
            for (Mount mount : bindMountsOf(compose)) {
                byServiceThenTarget
                        .computeIfAbsent(mount.service(), s -> new LinkedHashMap<>())
                        .put(mount.target(), mount);
            }
        }

        List<Nesting> nestings = new ArrayList<>();
        for (Map<String, Mount> mounts : byServiceThenTarget.values()) {
            for (Mount inner : mounts.values()) {
                for (Mount outer : mounts.values()) {
                    if (inner.isNestedIn(outer)) {
                        nestings.add(new Nesting(outer, inner));
                    }
                }
            }
        }
        return nestings;
    }

    private static List<Path> composeFiles() {
        Path backend = TestProjectPaths.backendDir();
        try (Stream<Path> entries = Files.list(backend)) {
            List<Path> found = entries
                    .filter(p -> p.getFileName().toString().startsWith("docker-compose"))
                    .filter(p -> p.getFileName().toString().endsWith(".yml"))
                    .sorted()
                    .toList();
            assertThat(found)
                    .as("backend/ 에 compose 파일이 하나도 없다 — 검사가 볼 곳이 사라졌다")
                    .isNotEmpty();
            return found;
        } catch (IOException e) {
            throw new UncheckedIOException("backend 디렉터리를 못 읽었다: " + backend, e);
        }
    }

    @SuppressWarnings("unchecked")
    private static List<Mount> bindMountsOf(Path compose) {
        String name = compose.getFileName().toString();
        Object loaded;
        try (Reader reader = Files.newBufferedReader(compose, StandardCharsets.UTF_8)) {
            loaded = new Yaml().load(reader);
        } catch (IOException e) {
            throw new UncheckedIOException("compose 를 못 읽었다: " + compose, e);
        }
        if (!(loaded instanceof Map<?, ?> root)) {
            throw new IllegalStateException(compose + " 를 YAML 맵으로 읽지 못했다.");
        }

        // 최상위 volumes 는 **이름 붙인 볼륨** 선언이다. 그 이름이 mount 의 왼쪽에 오면
        // 그건 호스트 경로가 아니므로 이 검사의 대상이 아니다 (예: mysql_data).
        Map<?, ?> namedVolumes = root.get("volumes") instanceof Map<?, ?> m ? m : Map.of();

        if (!(root.get("services") instanceof Map<?, ?> services)) {
            return List.of();
        }

        List<Mount> mounts = new ArrayList<>();
        for (Map.Entry<?, ?> entry : services.entrySet()) {
            String service = String.valueOf(entry.getKey());
            if (!(entry.getValue() instanceof Map<?, ?> service0)
                    || !(service0.get("volumes") instanceof List<?> declared)) {
                continue;
            }
            for (Object volume : declared) {
                Mount mount = parseMount(service, name, volume, namedVolumes);
                if (mount != null) {
                    mounts.add(mount);
                }
            }
        }
        return mounts;
    }

    /**
     * 짧은 꼴({@code SOURCE:TARGET[:MODE]})과 긴 꼴({@code type/source/target}) 둘 다 읽는다.
     *
     * <p>bind 가 아닌 것(이름 붙인 볼륨)은 {@code null} 을 돌려 건너뛴다.
     */
    private static Mount parseMount(
            String service, String composeFile, Object volume, Map<?, ?> namedVolumes) {

        if (volume instanceof Map<?, ?> longForm) {
            Object type = longForm.get("type");
            if (type != null && !"bind".equals(String.valueOf(type))) {
                return null;
            }
            if (longForm.get("source") instanceof String source
                    && longForm.get("target") instanceof String target) {
                return new Mount(service, composeFile, source, normalize(target));
            }
            return null;
        }

        String line = String.valueOf(volume);
        String[] parts = line.split(":");
        if (parts.length < 2) {
            return null;
        }
        String source = parts[0];
        String target = parts[1];
        // 이름 붙인 볼륨은 왼쪽이 경로가 아니라 이름이다. 선언 목록에 있거나, 경로처럼
        // 생기지 않았으면 건너뛴다.
        if (namedVolumes.containsKey(source) || !looksLikePath(source)) {
            return null;
        }
        return new Mount(service, composeFile, source, normalize(target));
    }

    private static boolean looksLikePath(String source) {
        return source.startsWith("/") || source.startsWith("./") || source.startsWith("../");
    }

    /** 끝의 {@code /} 를 떼어 {@code /srv/site} 와 {@code /srv/site/} 를 같게 본다. */
    private static String normalize(String target) {
        String trimmed = target.strip();
        return trimmed.length() > 1 && trimmed.endsWith("/")
                ? trimmed.substring(0, trimmed.length() - 1)
                : trimmed;
    }

    private static boolean isEmpty(Path directory) {
        try (Stream<Path> entries = Files.list(directory)) {
            return entries.findAny().isEmpty();
        } catch (IOException e) {
            throw new UncheckedIOException("디렉터리를 못 읽었다: " + directory, e);
        }
    }
}
