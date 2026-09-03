package com.heattrip.heat_trip_backend.docs;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;
import java.util.stream.Stream;

import com.heattrip.heat_trip_backend.support.TestProjectPaths;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 문서에 <b>내 기계의 절대경로</b>가 남지 않는다 — 이슈 #178.
 *
 * <h2>무엇이 있었나</h2>
 * <p>문서 일곱의 <b>마지막 줄</b>에 {@code 완료: C:/Users/<이름>/git_projects/...} 가 한 줄씩
 * 커밋돼 있었다. 도구가 붙인 자국이고 본문이 아니다.
 *
 * <h2>왜 검사를 다나</h2>
 * <p><b>기존 검사 중 아무것도 이 줄에 안 닿았다.</b> {@code DocDriftTest} 는 문서 다섯을
 * 읽지만 특정 문장만 보고, 마지막 줄은 어떤 단언도 지나가지 않는다. 그래서 이 일곱 줄은
 * <b>사람이 눈으로 볼 때까지</b> 남아 있었다.
 *
 * <p>남으면 두 가지가 샌다 — 저장소 소유자의 <b>사용자 이름</b>과 작업 디렉터리 구조다.
 * 공개 저장소가 되는 날 그대로 나간다.
 *
 * <h2>왜 "완료:" 만 안 세나</h2>
 * <p>자국의 모양은 도구가 바뀌면 달라진다. 세는 것은 <b>절대경로 자체</b>다 —
 * {@code C:\}·{@code C:/}·{@code /Users/}·{@code /home/} 로 시작하는 것들.
 *
 * <p>네트워크를 안 탄다. 저장소 안의 파일만 읽는다.
 */
class DocsHaveNoLocalPathsTest {

    /**
     * 사람의 기계를 가리키는 경로.
     *
     * <p>{@code C:\Users\누구} · {@code C:/Users/누구} · {@code /Users/누구} ·
     * {@code /home/누구} 를 잡는다. 뒤에 이름이 따라와야 하므로 {@code /home} 만 적힌
     * 산문은 안 걸린다.
     */
    private static final Pattern LOCAL_PATH = Pattern.compile(
            "(?i)([A-Z]:[\\\\/]Users[\\\\/]|(?<![\\w-])/Users/|(?<![\\w-])/home/)[A-Za-z0-9._-]+");

    /**
     * 예외 — <b>이유와 함께</b> 적는다.
     *
     * <p>비어 있다. 비워 두는 것이 이 검사의 값이다 — 목록을 늘리는 것으로 언제든 통과시킬
     * 수 있게 되면 다음 사람이 그렇게 한다.
     */
    private static final List<String> ALLOWED = List.of();

    @Test
    @DisplayName("docs/ 에 내 기계의 절대경로가 없다 — 사용자 이름과 디렉터리 구조가 샌다")
    void noLocalAbsolutePathsInDocs() {
        List<String> offenders = new ArrayList<>();

        for (Path file : markdownFiles()) {
            List<String> lines = readLines(file);
            for (int i = 0; i < lines.size(); i++) {
                String line = lines.get(i);
                if (!LOCAL_PATH.matcher(line).find()) {
                    continue;
                }
                if (ALLOWED.stream().anyMatch(line::contains)) {
                    continue;
                }
                offenders.add(relative(file) + ":" + (i + 1) + "  " + line.strip());
            }
        }

        assertThat(offenders)
                .as("""
                        도구가 붙인 자국이지 본문이 아니다. 남으면 저장소 소유자의 사용자 \
                        이름과 작업 디렉터리 구조가 함께 커밋된다 — 공개 저장소가 되는 날 \
                        그대로 나간다. 문서 일곱의 마지막 줄이 그 상태였다 (#178).""")
                .isEmpty();
    }

    @Test
    @DisplayName("문서가 본문이 아닌 줄로 끝나지 않는다 — 마지막 줄은 어떤 검사도 안 지나간다")
    void docsDoNotEndWithToolMarkers() {
        List<String> offenders = new ArrayList<>();

        for (Path file : markdownFiles()) {
            List<String> lines = readLines(file);
            String last = lastNonBlank(lines);
            if (last == null) {
                continue;
            }
            // "완료: ..." 같은 도구 자국. 본문이라면 마크다운 문법이나 문장으로 끝난다.
            if (last.startsWith("완료:") || last.startsWith("Done:")) {
                offenders.add(relative(file) + "  → " + last.strip());
            }
        }

        assertThat(offenders)
                .as("""
                        마지막 줄은 어떤 단언도 지나가지 않는 자리라, 여기 쌓인 것은 사람이 \
                        눈으로 볼 때까지 남는다.""")
                .isEmpty();
    }

    // ─────────────────────────── 도구 ───────────────────────────

    /** 저장소의 모든 마크다운. {@code docs/} 아래 전부를 본다 — 다섯만 보면 나머지가 낡는다. */
    private static List<Path> markdownFiles() {
        Path docs = TestProjectPaths.requireDirectory("../docs");
        try (Stream<Path> walk = Files.walk(docs)) {
            List<Path> found = walk
                    .filter(Files::isRegularFile)
                    .filter(path -> path.getFileName().toString().endsWith(".md"))
                    .sorted()
                    .toList();
            assertThat(found)
                    .as("문서를 하나도 못 읽었다면 이 검사는 아무것도 지키지 않는다")
                    .isNotEmpty();
            return found;
        } catch (IOException e) {
            throw new UncheckedIOException("docs/ 를 훑지 못했다", e);
        }
    }

    private static List<String> readLines(Path file) {
        try {
            return Files.readAllLines(file, StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException(file + " 를 읽지 못했다", e);
        }
    }

    private static String lastNonBlank(List<String> lines) {
        for (int i = lines.size() - 1; i >= 0; i--) {
            if (!lines.get(i).isBlank()) {
                return lines.get(i);
            }
        }
        return null;
    }

    private static String relative(Path file) {
        return file.toString().replace('\\', '/').replaceAll(".*?/docs/", "docs/");
    }
}
