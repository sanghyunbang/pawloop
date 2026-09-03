package com.heattrip.heat_trip_backend.support;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;
import java.util.stream.Stream;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * UTC 로 저장하는 모듈에서 <b>{@code LocalDateTime.now(...)} 를 직접 부르지 않는다</b> —
 * 이슈 #248.
 *
 * <h2>왜 이 검사가 따로 필요한가</h2>
 * <p>{@link StoredTimestampsAreUtcTest} 는 엔티티의 {@code @PrePersist} 를 불러서 잰다.
 * 그런데 <b>빌더가 값을 넣으면 그 훅이 안 걸린다</b> — 가드가
 * {@code if (createdAt == null)} 이기 때문이다. 그래서 서비스가
 * {@code .createdAt(LocalDateTime.now(clock))} 로 넣으면 훅 검사는 초록불인데 실제 저장값은
 * 다른 존이다.
 *
 * <p><b>실제로 그렇게 새어 나갔다.</b> #248 을 머지한 직후 셋을 찾았다.
 *
 * <ul>
 *   <li>{@code ChatReportService} 가 {@code LocalDateTime.now(clock)}({@code Asia/Seoul})을
 *       넣는데 {@code ChatReportResponse} 는 그것을 UTC 로 세웠다 — <b>9시간 뒤의 시각</b>이
 *       응답으로 나갔다. 형식 검사(오프셋이 붙는가)는 통과한다. 값이 틀린 것이라서다.</li>
 *   <li>{@code CustomOAuth2UserService} 가 {@code LocalDateTime.now()}(JVM 기본 존)를
 *       {@code User.createdAt}·{@code updatedAt} 에 넣었다. <b>v2 앱의 유일한 가입 경로다.</b></li>
 *   <li>{@code moderation} 은 한 모듈 안에 존이 셋이었다 — {@code Reports} 는 UTC,
 *       {@code Blocks} 는 {@code Asia/Seoul}, {@code Block} 엔티티는 JVM 기본 존.</li>
 * </ul>
 *
 * <h2>규칙</h2>
 * <p>이 모듈들에서 "지금" 을 얻는 길은 그 모듈의 {@code nowUtc(...)} 하나다. 예외는
 * {@link #ALLOWED} 에 <b>이유와 함께</b> 적는다 — 이유를 적게 하면 다음 사람이 그냥 늘리지
 * 못한다({@code PublicPathsAreRateLimitedTest} 가 같은 모양이다).
 *
 * <p>네트워크도 스프링도 없다. 소스만 읽는다(#21).
 */
class TimeWritersAreUtcTest {

    /** UTC 로 저장하기로 한 모듈들. 케어는 서비스 존이 규약이라(#247) 여기 없다. */
    private static final List<String> UTC_MODULES = List.of(
            "chat", "chatweb", "user", "OAuth", "group", "moderation", "moderationweb");

    /** {@code LocalDateTime.now()} · {@code LocalDateTime.now(clock)} 둘 다. */
    private static final Pattern DIRECT_NOW = Pattern.compile("LocalDateTime\\s*\\.\\s*now\\s*\\(");

    /**
     * 예외 — <b>파일 이름 → 왜 괜찮은가.</b>
     *
     * <p>줄 번호가 아니라 파일로 적는다. 줄이 밀릴 때마다 이 목록을 고치게 하면 사람이
     * 목록을 믿지 않게 된다.
     */
    private static final Map<String, String> ALLOWED = Map.of(
            "RefreshTokenService.java",
            """
            만료 비교에만 쓰인다 — 쓴 값(expires_at)과 읽는 값(now)이 같은 시계에서 나오므로 \
            존이 무엇이든 자기 완결적이고, 이 표의 어느 컬럼도 응답에 안 실린다. \
            옮기면 dev 에 살아 있는 18행의 실효 만료가 9시간 움직이고, RefreshTokenServiceTest 가 \
            ZoneId.systemDefault() 로 시계를 고정하고 있어 개발 기계에서만 빨간불이 난다 — \
            그 헛초록이 이 저장소에서 이미 한 번 났다(#247).""");

    @Test
    @DisplayName("UTC 모듈이 LocalDateTime.now 를 직접 부르지 않는다 — 빌더 경로는 @PrePersist 가드를 비켜 간다")
    void utcModulesDoNotCallLocalDateTimeNowDirectly() {
        List<String> offenders = new ArrayList<>();
        int scanned = 0;

        for (Path file : sourcesOf(UTC_MODULES)) {
            scanned++;
            String name = file.getFileName().toString();
            if (ALLOWED.containsKey(name)) {
                continue;
            }
            String[] lines = stripComments(read(file)).split("\\R", -1);
            for (int i = 0; i < lines.length; i++) {
                if (DIRECT_NOW.matcher(lines[i]).find()) {
                    offenders.add("%s:%d  %s".formatted(name, i + 1, lines[i].strip()));
                }
            }
        }

        assertThat(scanned)
                .as("소스를 하나도 못 읽었다면 이 검사는 아무것도 지키지 않는다")
                .isGreaterThan(30);

        assertThat(offenders)
                .as("""
                        이 모듈들은 표에 UTC 를 넣는다. "지금" 은 그 모듈의 nowUtc(...) 로 얻어라 \
                        — ChatTime · UserTime · ModerationTime.

                        LocalDateTime.now() 는 JVM 기본 존이라 개발 기계(KST)와 배포 컨테이너(UTC)가 \
                        같은 코드로 다른 값을 넣는다. LocalDateTime.now(clock) 은 ClockConfig 가 박은 \
                        Asia/Seoul 이라 응답에서 UTC 로 세우는 순간 9시간 어긋난다.

                        정말 예외라면 ALLOWED 에 **이유와 함께** 적어라.""")
                .isEmpty();
    }

    @Test
    @DisplayName("예외 목록에 죽은 항목이 없다 — 남으면 그 파일이 규칙 밖에 영원히 남는다")
    void theAllowListHasNoDeadEntries() {
        Set<String> present = new LinkedHashSet<>();
        for (Path file : sourcesOf(UTC_MODULES)) {
            present.add(file.getFileName().toString());
        }

        List<String> dead = new ArrayList<>();
        ALLOWED.forEach((name, reason) -> {
            if (!present.contains(name)) {
                dead.add(name + " (파일이 없다)");
                return;
            }
            boolean stillCalls = sourcesOf(UTC_MODULES).stream()
                    .filter(path -> path.getFileName().toString().equals(name))
                    .anyMatch(path -> DIRECT_NOW.matcher(stripComments(read(path))).find());
            if (!stillCalls) {
                dead.add(name + " (더 이상 LocalDateTime.now 를 안 부른다 — 예외를 지워라)");
            }
        });

        assertThat(dead)
                .as("예외가 죽은 채 남으면, 그 파일에 새 위반이 생겨도 이 검사가 눈감아 준다")
                .isEmpty();
    }

    @Test
    @DisplayName("예외마다 이유가 적혀 있다 — 이유 없는 예외는 다음 사람이 그냥 늘린다")
    void everyExemptionCarriesAReason() {
        Map<String, String> thin = new LinkedHashMap<>();
        ALLOWED.forEach((name, reason) -> {
            if (reason == null || reason.strip().length() < 40) {
                thin.put(name, String.valueOf(reason));
            }
        });

        assertThat(thin)
                .as("한 줄짜리 '괜찮음' 은 이유가 아니다. 무엇과 무엇을 견줘서 괜찮은지 적어라")
                .isEmpty();
    }

    // ─────────────────────────── 도구 ───────────────────────────

    private static List<Path> sourcesOf(List<String> modules) {
        List<Path> found = new ArrayList<>();
        for (String module : modules) {
            Path dir = TestProjectPaths.backendDir()
                    .resolve("src/main/java/com/heattrip/heat_trip_backend/" + module);
            if (!Files.isDirectory(dir)) {
                throw new IllegalStateException(dir + " 가 없다. 모듈 이름이 바뀌었나?");
            }
            try (Stream<Path> walk = Files.walk(dir)) {
                walk.filter(Files::isRegularFile)
                        .filter(path -> path.getFileName().toString().endsWith(".java"))
                        .forEach(found::add);
            } catch (IOException e) {
                throw new UncheckedIOException(dir + " 를 훑지 못했다", e);
            }
        }
        return found;
    }

    /**
     * 주석을 걷는다 — javadoc 이 {@code LocalDateTime.now()} 를 <b>설명하려고</b> 적는다.
     * {@code ChatTime} 이 정확히 그렇게 적어 뒀다. 줄바꿈은 남겨 줄 번호를 지킨다.
     */
    private static String stripComments(String source) {
        StringBuilder out = new StringBuilder(source.length());
        java.util.regex.Matcher matcher =
                Pattern.compile("(?s)/\\*.*?\\*/|//[^\\n]*").matcher(source);
        int last = 0;
        while (matcher.find()) {
            out.append(source, last, matcher.start());
            for (char c : matcher.group().toCharArray()) {
                out.append(c == '\n' ? '\n' : ' ');
            }
            last = matcher.end();
        }
        out.append(source.substring(last));
        return out.toString();
    }

    private static String read(Path file) {
        try {
            return Files.readString(file, StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException(file + " 를 읽지 못했다", e);
        }
    }
}
