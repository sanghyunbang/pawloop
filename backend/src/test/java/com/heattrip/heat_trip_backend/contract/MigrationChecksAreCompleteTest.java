package com.heattrip.heat_trip_backend.contract;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.stream.Stream;

import com.heattrip.heat_trip_backend.support.TestProjectPaths;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * {@code scripts/check-migrations.sh} 가 <b>모든</b> {@code post-start} SQL 을 묻는지 본다.
 *
 * <h2>무엇이 있었나</h2>
 * <p>2026-09-08, 로컬 dev DB 에 마이그레이션 둘이 조용히 빠져 있었다. {@code 24} 의 옛 CHECK
 * 가 안 지워져 부팅마다 인허가 8,110행을 받아 놓고 저장에서 통째로 버렸고, {@code 29} 가 안
 * 들어가 배변·마킹 기록이 실패했다. <b>둘 다 부팅 로그를 우연히 읽다 찾았다.</b>
 *
 * <h2>왜 아무 검사도 못 잡았나</h2>
 * <p>dev 는 {@code ddl-auto=update} 라 <b>Hibernate 가 표와 컬럼을 만들어 준다</b> — 새 표도
 * 새 컬럼도 저절로 생겨 "다 들어간 것처럼" 보인다. 그런데 Hibernate 는 <b>CHECK 제약을 절대
 * 안 건드리고</b>, prod 의 {@code validate} 도 CHECK 와 PK 는 안 본다. CHECK 만 고치는
 * 마이그레이션은 그래서 양쪽 어디서도 안 잡힌다.
 *
 * <h2>{@link MigrationRunbookIsCompleteTest} 와 무엇이 다른가</h2>
 * <p>그쪽은 <b>런북(문서)에 적혔는지</b>를 본다. 여기는 <b>확인하는 스크립트가 있는지</b>를
 * 본다. 문서에 적혀 있어도 아무도 안 돌리면 DB 는 그대로다 — 그게 이번에 일어난 일이다.
 *
 * <p>DB 에 붙지 않는다. 저장소의 파일만 읽는다(#21) — 실제로 들어갔는지는 스크립트가
 * 사람의 손에서 답한다.
 */
class MigrationChecksAreCompleteTest {

    private static List<String> migrationFiles;
    private static String script;

    @BeforeAll
    static void readRepository() {
        Path root = TestProjectPaths.backendDir().getParent();
        assertThat(root).as("저장소 루트를 못 찾았다").isNotNull();

        Path dir = root.resolve("backend/mysql/post-start");
        assertThat(Files.isDirectory(dir))
                .as("마이그레이션 디렉터리가 없다: %s — 옮겼다면 이 테스트도 함께 고친다. skip 하지 않는다", dir)
                .isTrue();

        try (Stream<Path> walk = Files.list(dir)) {
            migrationFiles = walk.map(p -> p.getFileName().toString())
                    .filter(name -> name.endsWith(".sql"))
                    .sorted()
                    .toList();
        } catch (IOException e) {
            throw new UncheckedIOException("마이그레이션 목록을 읽지 못했다: " + dir, e);
        }

        Path path = root.resolve("scripts/check-migrations.sh");
        assertThat(Files.isRegularFile(path))
                .as("점검 스크립트가 없다: %s", path)
                .isTrue();
        try {
            script = Files.readString(path, StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException("점검 스크립트를 읽지 못했다: " + path, e);
        }
    }

    @Test
    @DisplayName("마이그레이션마다 DB 에 물어보는 줄이 하나씩 있다")
    void everyMigrationHasACheck() {
        assertThat(migrationFiles)
                .as("파일을 하나도 못 찾았다면 아래 단언이 조용히 통과한다")
                .isNotEmpty();

        List<String> unchecked = migrationFiles.stream()
                .filter(name -> !script.contains("step \"" + name + "\""))
                .toList();

        assertThat(unchecked)
                .as("""
                        이 스크립트들이 DB 에 들어갔는지 확인할 방법이 없다. \
                        scripts/check-migrations.sh 에 `step "<파일>"` 과 want 한 줄을 더한다 — \
                        그 파일의 [D] 사후 검증 절에서 "들어갔으면 반드시 참인 사실" 을 하나 가져오면 된다. \
                        CHECK 만 고치는 마이그레이션은 Hibernate 도 validate 도 안 잡으므로 \
                        여기 없으면 아무 데서도 안 잡힌다(2026-09-08 에 실제로 24·29 가 그랬다).""")
                .isEmpty();
    }

    @Test
    @DisplayName("점검 스크립트가 없는 파일을 묻지 않는다 — 이름이 바뀌면 함께 고친다")
    void checksNameOnlyRealMigrations() {
        List<String> asked = script.lines()
                .filter(line -> line.startsWith("step \""))
                .map(line -> line.substring("step \"".length(), line.lastIndexOf('"')))
                .toList();

        assertThat(asked)
                .as("스크립트가 아무것도 안 묻고 있다")
                .isNotEmpty();

        assertThat(migrationFiles)
                .as("""
                        점검 스크립트가 저장소에 없는 파일을 묻고 있다. 이름을 바꿨거나 지웠다면 \
                        여기도 함께 고친다 — 안 고치면 그 줄은 영원히 ✗ 로 남아 사람이 무시하게 된다.""")
                .containsAll(asked);
    }

    @Test
    @DisplayName("스크립트가 접속값을 화면에 찍지 않는다")
    void checksDoNotPrintSecrets() {
        assertThat(script)
                .as("비밀번호는 MYSQL_PWD 로만 넘긴다 — 명령줄에 쓰면 프로세스 목록에 남는다")
                .doesNotContain("-p$DB_PASS")
                .doesNotContain("--password=");

        // 찾는 것은 **값의 전개**($DB_PASS)이지 이름이 아니다. 도움말이 "DB_PASS 로 덮는다"
        // 라고 적는 것은 값을 찍는 것이 아니다 — 처음에 이름만 보고 걸러서 그 줄이 걸렸다.
        assertThat(script.lines()
                .filter(line -> line.contains("echo"))
                .filter(line -> line.contains("$DB_PASS") || line.contains("${DB_PASS"))
                .toList())
                .as("비밀번호 값을 찍는 줄이 있다")
                .isEmpty();
    }
}
