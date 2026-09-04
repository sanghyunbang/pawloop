package com.heattrip.heat_trip_backend.contract;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;

import com.heattrip.heat_trip_backend.support.TestProjectPaths;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 마이그레이션의 검사가 <b>표의 전체 컬럼 수</b>를 세지 않는지 본다 — 이슈 #267.
 *
 * <h2>무엇이 문제였나</h2>
 * <p>런북이 <b>"전부 멱등이라 이미 적용된 항목은 아무 변경 없이 메시지만 출력합니다"</b> 라고
 * 약속한다({@code mysql/README.md}). 그런데 세 자리가 이렇게 적혀 있었다.
 *
 * <pre>
 * SET &#64;d_report_cols := (
 *     SELECT COUNT(*) FROM information_schema.columns
 *     WHERE table_schema = DATABASE() AND table_name = 'report');
 * ...
 * IF(... AND &#64;d_report_cols = 8 ...)
 * </pre>
 *
 * <p>지금은 맞는다. 그런데 <b>다음 마이그레이션이 그 표에 컬럼을 하나 더하는 순간, 그 뒤로
 * 이 스크립트를 다시 못 돌린다</b> — 사후 검증이 ABORT 한다. 런북이 약속한 성질이 그날로
 * 깨지고, 그것을 알아차리는 방법은 누군가 실제로 다시 돌려 보는 것뿐이다.
 *
 * <p>{@code #254}(chat_report 흡수)가 정확히 {@code report_snapshot} 에 컬럼을 더하는
 * 작업이라 거기서 터질 참이었다.
 *
 * <h2>무엇으로 바꿨나</h2>
 * <p>{@code column_name IN (...)} 으로 <b>그 스크립트가 만든 컬럼이 있는지</b>를 센다.
 * 앞으로 컬럼이 늘어도 참이고, <b>지금보다 강하다</b> — 개수만 맞고 이름이 틀린 경우도 걸린다.
 *
 * <p>도커도 스프링도 안 쓴다. SQL 파일만 읽는다(#21).
 */
class MigrationPostChecksNameColumnsTest {

    /**
     * {@code information_schema.columns} 를 세는 한 덩어리.
     *
     * <p>{@code SELECT COUNT(*) FROM information_schema.columns} 부터 그 서브쿼리를 닫는
     * {@code );} 까지. 그 안에 {@code column_name} 이 없으면 표 전체를 센 것이다.
     */
    private static final Pattern COLUMN_COUNT = Pattern.compile(
            "(?s)SELECT\\s+COUNT\\(\\*\\)\\s+FROM\\s+information_schema\\.columns(.*?)\\);");

    /** 어느 표를 셌는지 — 실패 메시지에 싣는다. */
    private static final Pattern TABLE_NAME =
            Pattern.compile("table_name\\s*=\\s*'([a-z_]+)'");

    @Test
    @DisplayName("post-start 의 검사가 표의 전체 컬럼 수를 안 센다 — 컬럼이 늘면 재실행이 깨진다")
    void noPostCheckCountsEveryColumnOfATable() {
        List<String> offenders = new ArrayList<>();
        int scanned = 0;

        for (Path file : sqlFiles()) {
            scanned++;
            String sql = stripComments(read(file));
            Matcher block = COLUMN_COUNT.matcher(sql);
            while (block.find()) {
                String body = block.group(1);
                if (body.contains("column_name")) {
                    continue;
                }
                Matcher table = TABLE_NAME.matcher(body);
                offenders.add("%s  →  %s 의 컬럼을 전부 셌다".formatted(
                        file.getFileName(), table.find() ? table.group(1) : "(표 이름 못 읽음)"));
            }
        }

        assertThat(scanned)
                .as("post-start 에서 SQL 을 하나도 못 읽었다면 이 검사는 아무것도 지키지 않는다")
                .isGreaterThan(10);

        assertThat(offenders)
                .as("""
                        표의 전체 컬럼 수를 리터럴과 견주면, 나중에 컬럼이 하나 늘 때 이 \
                        스크립트를 다시 못 돌린다 — 런북이 약속한 "전부 멱등" 이 그날로 \
                        깨진다 (#267).

                        column_name IN ('a', 'b', ...) 으로 **이 스크립트가 만든 컬럼이 \
                        있는가** 를 세라. 앞으로 컬럼이 늘어도 참이고, 개수만 맞고 이름이 \
                        틀린 경우까지 걸리므로 더 강하다.""")
                .isEmpty();
    }

    // ─────────────────────────── 도구 ───────────────────────────

    private static List<Path> sqlFiles() {
        Path dir = TestProjectPaths.requireDirectory("mysql/post-start");
        try (Stream<Path> files = Files.list(dir)) {
            return files
                    .filter(Files::isRegularFile)
                    .filter(path -> path.getFileName().toString().endsWith(".sql"))
                    .sorted()
                    .toList();
        } catch (IOException e) {
            throw new UncheckedIOException(dir + " 를 훑지 못했다", e);
        }
    }

    /**
     * {@code --} 주석을 걷는다 — 머리 주석이 이 패턴을 <b>설명하려고</b> 적는다.
     * 15·14 가 정확히 그렇게 적어 뒀다. 줄바꿈은 남긴다.
     */
    private static String stripComments(String sql) {
        StringBuilder out = new StringBuilder(sql.length());
        for (String line : sql.split("\\R", -1)) {
            int comment = line.indexOf("--");
            out.append(comment < 0 ? line : line.substring(0, comment)).append('\n');
        }
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
