package com.heattrip.heat_trip_backend.support;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 기준점과 정본이 <b>같은 스키마를 말하는가</b> — 이슈 #592.
 *
 * <h2>왜 같은 내용이 두 파일에 있나</h2>
 *
 * <p>스키마를 만드는 길이 지금 둘이다.
 *
 * <ul>
 *   <li>{@code mysql/init/01_schema.sql} — compose 가 <b>새 볼륨</b>에 넣는다
 *       ({@code docker-entrypoint-initdb.d}).
 *   <li>{@code db/migration/V1__baseline.sql} — Flyway 가 <b>빈 DB</b>에 넣는다.
 * </ul>
 *
 * <p>둘이 어긋나면 <b>compose 로 띄운 곳과 운영이 다른 스키마로 뜬다.</b> 그리고 그 차이는
 * 표가 하나 없는 날이 아니라 <b>한참 뒤 컬럼 하나가 없는 날</b> 드러난다.
 *
 * <h2>언제 사라지나</h2>
 *
 * <p>#592 조각 2 가 {@code SchemaDdlDriftTest} 의 정본을 "V 파일을 다 적용한 결과" 로 바꾸면
 * {@code 01_schema.sql} 은 할 일이 없어진다. 그때 이 검사도 같이 지운다. 그때까지는
 * <b>둘을 손으로 맞추지 않게</b> 여기가 잡는다.
 *
 * <h2>왜 바이트 비교가 아닌가</h2>
 *
 * <p>머리말이 다르다 — {@code V1} 은 "절대 고치지 않는다" 고 말하고, {@code 01_schema.sql} 은
 * "다시 뽑아라" 고 말한다. 둘 다 사실이라 같게 만들 수 없다. 그래서 <b>주석을 걷어낸 DDL</b> 만
 * 비교한다.
 */
class BaselineMatchesCanonicalSchemaTest {

    private static final Path CANONICAL =
            TestProjectPaths.backendDir().resolve("mysql/init/01_schema.sql");

    private static final Path BASELINE =
            TestProjectPaths.backendDir().resolve("src/main/resources/db/migration/V1__baseline.sql");

    @Test
    @DisplayName("V1 과 01_schema.sql 의 DDL 이 한 글자도 다르지 않다")
    void theyDeclareTheSameSchema() {
        List<String> canonical = ddlOf(CANONICAL);
        List<String> baseline = ddlOf(BASELINE);

        assertThat(canonical).as("정본에서 DDL 을 한 줄도 못 읽었다 — 주석 걷기가 늙었다").isNotEmpty();
        assertThat(baseline)
                .as("""
                        기준점과 정본이 어긋났다. 엔티티를 고친 뒤 01_schema.sql 만 다시 뽑고 \
                        V 파일을 안 썼을 때 이렇게 된다 — 그러면 compose 로 띄운 곳과 운영이 \
                        다른 스키마로 뜬다.

                        고치는 법: V1 을 고치는 것이 아니라 **새 V 파일**을 쓰고, 그 결과가 \
                        01_schema.sql 과 같아지게 한다 (#592).""")
                .isEqualTo(canonical);
    }

    /** 주석과 빈 줄을 걷어낸 DDL 줄. 머리말이 서로 달라도 되게 한다. */
    private static List<String> ddlOf(Path path) {
        return read(path).lines()
                .map(String::strip)
                .filter(line -> !line.isEmpty())
                .filter(line -> !line.startsWith("--"))
                .toList();
    }

    private static String read(Path path) {
        try {
            return Files.readString(path, StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException("읽지 못했다: " + path, e);
        }
    }
}
