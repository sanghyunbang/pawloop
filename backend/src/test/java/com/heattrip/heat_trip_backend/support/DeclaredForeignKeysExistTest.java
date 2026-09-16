package com.heattrip.heat_trip_backend.support;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;

import javax.sql.DataSource;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 엔티티가 <b>이름 붙여 선언한 FK 가 실제로 만들어졌는지</b> 본다 — 이슈 #560.
 *
 * <h2>이 테스트가 생긴 이유 — 실측</h2>
 *
 * <p>{@code CareLog} 에 {@code @Check(ck_carelog_source)} 를 더했더니
 * {@code fk_carelog_item} 이 <b>정본에서 통째로 사라졌다.</b> MySQL 은 {@code SET NULL} 로 값을
 * 쓰는 FK 가 걸린 컬럼을 CHECK 에서 못 읽는데, Hibernate 는 표를 만든 뒤 FK 를 {@code ALTER}
 * 로 걸므로 그 {@code ALTER} 만 실패하고 <b>부팅은 그대로 이어졌다.</b> 로그 한 줄이 전부다.
 *
 * <p><b>그리고 아무 게이트도 안 울렸다.</b> {@code SchemaDdlDriftTest} 는 엔티티가 만든 DB 와
 * 커밋된 {@code 01_schema.sql} 을 대조하는데, 그 파일은 <b>엔티티가 만든 DB 에서 뽑는다</b> —
 * 재생성하는 순간 두 쪽이 같은 오답에 합의한다. 사람이 파일을 눈으로 보고 찾았다.
 *
 * <p>그래서 여기는 <b>바깥에 기준을 둔다.</b> 소스에 적힌 {@code @ForeignKey(name = "…")} 가
 * 기준이고, 살아 있는 DB 가 답이다. 둘은 서로에게서 나오지 않는다.
 *
 * <h2>훑은 개수를 따로 잰다</h2>
 *
 * <p>전수 검사의 실패 모드는 "틀린 답" 이 아니라 <b>"아무것도 안 봄"</b> 이다. 경로가 바뀌어
 * 파일을 0개 읽어도 "위반 없음" 으로 초록불이 난다. 그래서 훑은 이름 수에 바닥을 둔다 —
 * 그 값은 짐작이 아니라 <b>실측</b>이다(아래 상수의 주석).
 */
@SpringBootTest
class DeclaredForeignKeysExistTest extends AbstractMySqlIntegrationTest {

    /** {@code @ForeignKey(name = "fk_carelog_item")} 의 이름만 뽑는다. */
    private static final Pattern DECLARED = Pattern.compile(
            "@ForeignKey\\s*\\(\\s*name\\s*=\\s*\"([A-Za-z0-9_]+)\"");

    /**
     * 소스에서 읽어야 하는 FK 이름의 최소 개수.
     *
     * <p>2026-09-16 실측 <b>38</b> 개. 절반쯤인 20 으로 둔다 — 엔티티를 크게 정리해 수가 줄어도
     * 바닥이 먼저 빨간불이 되지 않게 하되, 경로가 틀려 0~몇 개만 읽히는 사고는 잡는다.
     * <b>짐작해서 올리지 마라</b> — 한 번 짐작했다가 그 게이트에 잡힌 적이 있다(#573).
     */
    private static final int MINIMUM_DECLARED = 20;

    @Autowired
    private DataSource dataSource;

    @Test
    @DisplayName("엔티티가 이름 붙인 FK 가 전부 DB 에 있다 — Hibernate 는 FK 를 못 걸어도 부팅을 막지 않는다")
    void everyDeclaredForeignKeyExists() throws Exception {
        Set<String> declared = declaredForeignKeyNames();

        assertThat(declared)
                .as("소스에서 FK 이름을 %d개보다 적게 읽었다면 경로가 틀린 것이고, "
                        + "이 검사는 아무것도 지키지 않는다", MINIMUM_DECLARED)
                .hasSizeGreaterThanOrEqualTo(MINIMUM_DECLARED);

        Set<String> actual;
        try (Connection live = dataSource.getConnection()) {
            actual = foreignKeyNames(live);
        }

        List<String> missing = declared.stream().filter(name -> !actual.contains(name)).sorted()
                .toList();

        assertThat(missing)
                .as("""
                        엔티티가 이 이름으로 FK 를 선언했는데 DB 에 없다. Hibernate 의 \
                        ALTER TABLE ADD FOREIGN KEY 가 실패하고도 부팅은 이어졌다는 뜻이고, \
                        그 상태로 01_schema.sql 을 재생성하면 **정본에서 FK 가 사라진다** — \
                        새로 세우는 운영 DB 부터 지운 행이 남의 표에 떠돈다.
                        실제로 겪은 원인: 같은 컬럼에 CHECK 를 걸었다(MySQL 은 SET NULL 로 값을 \
                        쓰는 FK 의 컬럼을 CHECK 에서 못 읽는다). 빌드 로그에서 그 표 이름을 찾아라.""")
                .isEmpty();
    }

    // ─────────────────────────── 지그 ───────────────────────────

    /** 소스에 적힌 {@code @ForeignKey(name = "…")} 전부. */
    private static Set<String> declaredForeignKeyNames() {
        Set<String> found = new LinkedHashSet<>();
        Path base = TestProjectPaths.requireDirectory("src/main/java/com/heattrip/heat_trip_backend");
        try (Stream<Path> walk = Files.walk(base)) {
            List<Path> files = walk.filter(Files::isRegularFile)
                    .filter(p -> p.getFileName().toString().endsWith(".java"))
                    .toList();
            for (Path file : files) {
                Matcher matcher = DECLARED.matcher(read(file));
                while (matcher.find()) {
                    found.add(matcher.group(1));
                }
            }
        } catch (IOException e) {
            throw new UncheckedIOException(base + " 를 훑지 못했다", e);
        }
        return found;
    }

    /** 살아 있는 DB 의 FK 이름 전부. */
    private static Set<String> foreignKeyNames(Connection connection) throws SQLException {
        Set<String> out = new LinkedHashSet<>();
        try (Statement st = connection.createStatement();
             ResultSet rs = st.executeQuery("""
                     SELECT constraint_name FROM information_schema.referential_constraints
                     WHERE constraint_schema = DATABASE()
                     """)) {
            while (rs.next()) {
                out.add(rs.getString(1));
            }
        }
        return out;
    }

    private static String read(Path file) {
        try {
            return Files.readString(file, StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException(file + " 를 읽지 못했다", e);
        }
    }

    /** 훑기 결과를 눈으로 확인할 자리 — 실패했을 때 몇 개를 봤는지 알아야 한다. */
    @Test
    @DisplayName("소스에서 FK 이름을 실제로 긁어 온다 — 목록이 비면 위 검사는 아무것도 안 지킨다")
    void theScanActuallyReadsNames() {
        Set<String> declared = declaredForeignKeyNames();

        assertThat(declared)
                .as("이 셋은 이 저장소에 분명히 있는 이름이다 — 안 나오면 정규식이나 경로가 틀렸다")
                .contains("fk_carelog_item", "fk_careitem_group", "fk_dog_user");
        assertThat(new ArrayList<>(declared))
                .as("실측 38개(2026-09-16). 크게 달라졌으면 MINIMUM_DECLARED 를 다시 재라")
                .hasSizeGreaterThanOrEqualTo(MINIMUM_DECLARED);
    }
}
