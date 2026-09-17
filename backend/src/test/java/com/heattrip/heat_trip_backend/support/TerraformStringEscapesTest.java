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
import java.util.Set;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * terraform 파일의 문자열 이스케이프가 <b>HCL 이 받아들이는 것뿐인지</b> — 이슈 #634.
 *
 * <h2>왜 필요한가 — 실제로 밟았다</h2>
 *
 * <p>2026-09-17, {@code variables.tf} 의 두 줄이 정규식에 {@code \.} 를 적고 있었다. HCL 의
 * 따옴표 문자열에서 그것은 <b>없는 이스케이프</b>라 파서가 거부한다 — 즉
 * {@code terraform init} 부터 통째로 안 돈다. 그러면 <b>운영 인프라를 아무도 못 고친다.</b>
 *
 * <p>그 오류가 #633 과 함께 들어와 일주일 가까이 살아 있었고, 그동안 {@code pawloop.app} 의
 * A 레코드를 만들 수 없었다 — 스토어가 요구하는 개인정보처리방침 주소가 그래서 안 열렸다.
 * 코드 리뷰도, 앱 검사 1,995개도, 백엔드 검사 1,870개도 그것을 몰랐다.
 *
 * <h2>왜 {@code terraform validate} 가 아닌가</h2>
 *
 * <p>그게 정답이지만 CI 기계에 terraform 이 없다. 없는 도구를 전제하는 검사는 "설치돼 있을
 * 때만" 도는 검사이고, 그건 <b>안 도는 검사</b>와 구별되지 않는다. 여기서는 terraform 없이
 * 잡을 수 있는 것 하나만 잡는다 — <b>문자열 안의 잘못된 이스케이프.</b>
 *
 * <p>문법 전체를 검사하지 않는다. 이 검사가 초록이라고 terraform 이 돈다는 뜻은 아니다.
 */
class TerraformStringEscapesTest {

    /** HCL 의 따옴표 문자열이 받아들이는 이스케이프 — 그 밖은 파서가 거부한다. */
    private static final Set<Character> ALLOWED = Set.of('\\', 'n', 'r', 't', '"', 'u', 'U');

    @Test
    @DisplayName("terraform 문자열에 HCL 이 모르는 이스케이프가 없다 — 있으면 init 부터 안 돈다")
    void noUnknownEscapesInHclStrings() throws IOException {
        List<Path> files = terraformFiles();
        assertThat(files)
                .as("terraform 파일을 하나도 못 찾았다 — 경로가 늙었다. 그러면 이 검사는 공허하다")
                .isNotEmpty();

        List<String> broken = new ArrayList<>();
        for (Path file : files) {
            String text = Files.readString(file, StandardCharsets.UTF_8);
            for (String problem : unknownEscapes(text)) {
                broken.add(file.getFileName() + ": " + problem);
            }
        }

        assertThat(broken)
                .as("""
                        HCL 의 따옴표 문자열에서 백슬래시 뒤에 올 수 있는 것은 \\\\ \\n \\r \\t \\" \\u 뿐이다. \
                        정규식의 점을 막으려면 \\\\. 처럼 백슬래시를 두 개 적는다 — 하나만 적으면 \
                        terraform 이 파일을 아예 못 읽고, 그때는 plan 도 apply 도 안 된다.""")
                .isEmpty();
    }

    /**
     * 따옴표 문자열 안에서 HCL 이 모르는 이스케이프를 찾는다.
     *
     * <p>heredoc({@code <<-EOT})은 건너뛴다 — 거기서는 백슬래시가 그냥 글자다. 설명문에
     * 정규식을 적어 두는 자리가 실제로 있어서, 안 걸러 내면 이 검사가 거짓 빨간불을 낸다.
     */
    private static List<String> unknownEscapes(String text) {
        List<String> found = new ArrayList<>();
        boolean inString = false;
        boolean inHeredoc = false;
        String[] lines = text.split("\r?\n");

        for (int lineNumber = 1; lineNumber <= lines.length; lineNumber++) {
            String line = lines[lineNumber - 1];

            if (inHeredoc) {
                if (line.strip().equals("EOT")) {
                    inHeredoc = false;
                }
                continue;
            }
            if (line.contains("<<-EOT") || line.contains("<<EOT")) {
                inHeredoc = true;
                continue;
            }
            if (line.stripLeading().startsWith("#")) {
                continue;
            }

            inString = false;
            for (int i = 0; i < line.length(); i++) {
                char c = line.charAt(i);
                if (c == '"') {
                    inString = !inString;
                } else if (c == '\\' && i + 1 < line.length()) {
                    char next = line.charAt(i + 1);
                    if (inString && !ALLOWED.contains(next)) {
                        found.add(lineNumber + "행  \\" + next + "  ← " + line.strip());
                    }
                    // 짝을 이룬 백슬래시는 하나로 소비한다. 안 그러면 \\\\ 의 뒤쪽을
                    // 다시 이스케이프 시작으로 읽어 엉뚱한 곳을 지목한다.
                    if (next == '\\') {
                        i++;
                    }
                }
            }
        }
        return found;
    }

    private static List<Path> terraformFiles() throws IOException {
        Path root = TestProjectPaths.backendDir().resolve("infra/terraform");
        assertThat(Files.isDirectory(root)).as("terraform 폴더가 없다: %s", root).isTrue();
        try (Stream<Path> paths = Files.walk(root)) {
            return paths.filter(Files::isRegularFile)
                    .filter(p -> p.getFileName().toString().endsWith(".tf"))
                    // .terraform/ 아래는 provider 가 내려받은 것이라 우리 코드가 아니다.
                    .filter(p -> !p.toString().contains(".terraform"))
                    .toList();
        } catch (UncheckedIOException e) {
            throw new IOException("terraform 폴더를 못 읽었다", e);
        }
    }
}
