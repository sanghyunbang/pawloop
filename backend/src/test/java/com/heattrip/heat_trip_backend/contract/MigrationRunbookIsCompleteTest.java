package com.heattrip.heat_trip_backend.contract;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;

import com.heattrip.heat_trip_backend.support.TestProjectPaths;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 런북({@code mysql/README.md})이 <b>모든</b> {@code post-start} SQL 을 가리키는지 본다 —
 * 이슈 #265.
 *
 * <h2>무엇이 있었나</h2>
 * <p>런북의 실행 목록이 <b>14 에서 끝나 있었다.</b> {@code 15_report.sql}(#166 · #232)과
 * {@code 16_user_block.sql}(#166)이 등재되지 않았고, <b>그래서 아무도 안 돌렸다</b> —
 * dev 3306 에 {@code report}·{@code report_snapshot}·{@code user_block} 표가 없고
 * {@code chat_block} 이 그대로 남아 있었다(2026-09-04 실측).
 *
 * <h2>왜 기존 검사가 못 잡았나</h2>
 * <p>마이그레이션 실행 테스트마다 <b>"런북이 이 파일의 실행 커맨드를 담고 있다"</b> 가 하나씩
 * 있다({@code CommunitySchemaMigrationExecutionTest} 는 두 번 잰다). 그런데 그건
 * <b>파일마다 사람이 기억해서 넣는 검사</b>다. {@code ReportSchemaMigrationExecutionTest} 에는
 * 그 검사가 없었고, {@code 16_user_block.sql} 은 실행 테스트 자체가 없다.
 *
 * <p>즉 새 SQL 을 더하면서 그 검사를 안 쓰면 아무 데서도 안 걸린다. <b>두 번 연속 그렇게 됐다.</b>
 * 그래서 여기는 파일 목록을 <b>디렉터리에서</b> 읽는다 — 기억할 것이 없다.
 *
 * <h2>왜 아픈가</h2>
 * <p>{@code CommunitySchemaMigrationExecutionTest} 가 이미 적어 뒀다 — <b>"런북에 없는
 * 스크립트는 새 환경을 세울 때 통째로 빠진다."</b> dev 는 {@code ddl-auto=update} 라
 * Hibernate 가 표를 만들어 주지만, 그러면 {@code 16} 의 {@code RENAME} 이 안 일어나
 * {@code chat_block} 과 빈 {@code user_block} 이 둘 다 남는다 — 그 스크립트가 "사람이
 * 정해야 한다" 로 멈추도록 막아 둔 상태다. prod 는 {@code validate} 라 아예 안 뜬다.
 *
 * <p>스프링도 도커도 안 쓴다. 저장소의 파일만 읽는다(#21).
 */
class MigrationRunbookIsCompleteTest {

    /** 실행 커맨드 블록의 한 줄에서 파일 이름만. 경로 구분자는 윈도우 역슬래시다. */
    private static final Pattern COMMAND_LINE =
            Pattern.compile("post-start[\\\\/]([0-9]{2}_[a-z0-9_]+\\.sql)");

    /** 설명 표의 첫 칸. {@code | `15_report.sql` | …} 꼴. */
    private static final Pattern TABLE_ROW =
            Pattern.compile("(?m)^\\|\\s*`([0-9]{2}_[a-z0-9_]+\\.sql)`\\s*\\|");

    private static String runbook;
    private static List<String> onDisk;

    @BeforeAll
    static void read() {
        runbook = readFile(TestProjectPaths.requireFile("mysql/README.md"));
        onDisk = sqlFiles();
    }

    @Test
    @DisplayName("post-start 의 모든 SQL 이 런북의 실행 커맨드에 있다 — 없으면 아무도 안 돌린다")
    void everySqlHasARunCommand() {
        assertThat(onDisk)
                .as("post-start 에서 SQL 을 하나도 못 읽었다면 이 검사는 아무것도 지키지 않는다")
                .hasSizeGreaterThan(10);

        Set<String> commanded = matches(COMMAND_LINE, runbook);
        List<String> missing = onDisk.stream().filter(name -> !commanded.contains(name)).toList();

        assertThat(missing)
                .as("""
                        런북에 없는 스크립트는 새 환경을 세울 때 통째로 빠진다. 실제로 15·16 이 \
                        그렇게 빠져서 dev 에 report·user_block 표가 없었다 (#265).

                        mysql/README.md 의 실행 커맨드 블록에 번호 순으로 한 줄씩 더하라.""")
                .isEmpty();
    }

    @Test
    @DisplayName("모든 SQL 이 런북의 설명 표에도 있다 — 커맨드만 있으면 무엇을 하는지 모른다")
    void everySqlHasATableRow() {
        Set<String> described = matches(TABLE_ROW, runbook);
        List<String> missing = onDisk.stream().filter(name -> !described.contains(name)).toList();

        assertThat(missing)
                .as("""
                        커맨드만 있으면 돌리는 사람이 무엇이 일어나는지 모른 채 돌린다. \
                        되돌릴 수 있는지, 먼저 돌아야 하는 것이 있는지가 그 표에 있다.""")
                .isEmpty();
    }

    @Test
    @DisplayName("런북이 없는 파일을 가리키지 않는다 — 죽은 줄은 돌리는 사람을 멈춰 세운다")
    void theRunbookPointsAtNothingMissing() {
        Set<String> mentioned = new LinkedHashSet<>(matches(COMMAND_LINE, runbook));
        mentioned.addAll(matches(TABLE_ROW, runbook));

        List<String> dead = mentioned.stream().filter(name -> !onDisk.contains(name)).toList();

        assertThat(dead)
                .as("파일을 옮기거나 이름을 바꿨으면 런북도 함께 고쳐라 — 없는 파일을 "
                        + "리다이렉트하면 커맨드가 빈 입력으로 돌아 조용히 아무것도 안 한다")
                .isEmpty();
    }

    @Test
    @DisplayName("실행 커맨드가 번호 순이다 — 순서가 곧 의존 관계다")
    void theCommandsAreInNumericOrder() {
        List<String> commanded = new ArrayList<>(matches(COMMAND_LINE, runbook));

        assertThat(commanded)
                .as("""
                        런북이 "번호 순으로 실행합니다" 라고 적어 뒀고, 실제로 04 가 05 보다 \
                        먼저여야 한다(users 의 소셜 컬럼이 없으면 그 뒤가 전부 죽는다). \
                        블록의 순서가 그 약속이다.""")
                .isSorted();
    }

    // ─────────────────────────── 도구 ───────────────────────────

    /** 나온 순서를 지키는 집합 — 순서 단언이 이것을 쓴다. */
    private static Set<String> matches(Pattern pattern, String text) {
        Set<String> found = new LinkedHashSet<>();
        Matcher matcher = pattern.matcher(text);
        while (matcher.find()) {
            found.add(matcher.group(1));
        }
        return found;
    }

    private static List<String> sqlFiles() {
        Path dir = TestProjectPaths.requireDirectory("mysql/post-start");
        try (Stream<Path> files = Files.list(dir)) {
            return files
                    .filter(Files::isRegularFile)
                    .map(path -> path.getFileName().toString())
                    .filter(name -> name.endsWith(".sql"))
                    .sorted()
                    .toList();
        } catch (IOException e) {
            throw new UncheckedIOException(dir + " 를 훑지 못했다", e);
        }
    }

    private static String readFile(Path file) {
        try {
            return Files.readString(file, StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException(file + " 를 읽지 못했다", e);
        }
    }
}
