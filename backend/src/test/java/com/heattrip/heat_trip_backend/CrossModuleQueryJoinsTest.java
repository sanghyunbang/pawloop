package com.heattrip.heat_trip_backend;

import com.heattrip.heat_trip_backend.support.ModuleTables;
import com.heattrip.heat_trip_backend.support.QueryScanner;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.TreeSet;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * <b>어느 모듈의 쿼리가 남의 모듈 표를 부르는가</b> — 이슈 #518 §2.
 *
 * <h2>바이트코드를 보는 검사에 안 걸린다</h2>
 * <p>JPQL 은 엔티티 이름을, 네이티브는 표 이름을 <b>문자열로</b> 쓴다 — import 도 필드도 아니라
 * ArchUnit 도 Modulith 도 못 본다. FK 가 없어도 조인 하나면 그 모듈이 남의 스키마에 묶이고,
 * 되돌리려 할 때는 이미 쿼리가 여럿이다(📌 #86 원칙 6).
 *
 * <h2>게이트가 아니라 기준선이다</h2>
 * <p>{@code ChatBoundaryArchitectureTest} §C 는 <b>chat 전용 게이트</b>다 — "밖을 부르는 쿼리가
 * 0" 이어야 한다. 나머지 모듈은 다르다: 이미 있는 것을 걷어내는 것은 별건이고, 여기서는 이슈가
 * 적은 대로 <b>"지금 어디에 몇 개 있는지"</b> 를 먼저 박는다. 새로 생기면 그때 이유를 묻는다.
 *
 * <p>표·엔티티의 소유는 {@link ModuleTables} 한 곳에서 읽는다 — FK 검사
 * ({@link CrossModuleForeignKeysTest})와 같은 지도를 본다. 둘이 각자 분류하면 한쪽만 낡는다.
 *
 * <p>스프링을 안 띄운다(#21). 소스를 파일로 읽는다.
 */
class CrossModuleQueryJoinsTest {

    private static final Path MAIN = Path.of("src", "main", "java", "com", "heattrip",
            "heat_trip_backend");

    /**
     * 지금 남의 모듈 표·엔티티를 부르는 쿼리 전부. <b>줄이는 것이 목표다.</b>
     *
     * <p>하나뿐이다 — {@code WalkRepository.deleteMine} 의
     * {@code w.dog.id in (select d.id from Dog d where d.user.id = :userId)}. 소유권 조건을
     * <b>삭제 문장 안에</b> 넣어 "남의 산책은 0행이 지워진다" 를 만드는 자리다(#86 원칙 5 —
     * 확인-후-쓰기 대신 조건이 판정한다). 그 조건을 밖으로 빼면 <b>확인과 삭제 사이의 틈</b>이
     * 생기므로, 이 줄은 걷어내는 것이 목적이 아니다.
     *
     * <p>{@code Dog} 는 {@code @NamedInterface("entity")} 로 열린 표면이라 Modulith 는 이것을
     * 위반으로 안 센다. 이 검사가 따로 보는 이유가 그것이다 — <b>쿼리는 표면과 무관하게
     * 스키마에 묶인다.</b>
     *
     * <p><b>{@code chat} 이 여기 하나도 없는 것이 요점이다.</b> 그 모듈만 게이트로 0 을 지킨다.
     */
    private static final List<String> BASELINE = List.of("walk → dog (Dog)");

    @Test
    @DisplayName("남의 모듈 표를 부르는 쿼리가 기록과 같다 — 새로 생기면 왜 필요한지 적어라")
    void queriesThatReachIntoAnotherModuleMatchTheBaseline() throws IOException {
        Map<String, String> byEntity = ModuleTables.byEntityName();
        assertThat(byEntity).as("엔티티를 하나도 못 찾았으면 아래 비교는 공허하다").isNotEmpty();

        Scan scan = scan(byEntity);

        assertThat(scan.queries())
                .as("쿼리 문자열을 하나도 못 뽑았으면 이 검사는 빈 목록을 빈 목록과 비교한다")
                .isGreaterThan(20);

        assertThat(new ArrayList<>(new TreeSet<>(scan.crossing())))
                .as("""
                        모듈 밖의 표·엔티티를 부르는 쿼리가 기록과 다르다.

                        새로 생겼다면 — 그 모듈이 남의 스키마에 묶인 것이다. 그 모듈이 표면을 \
                          내주게 하거나(#104 · #105 · #120), 정말 필요하면 BASELINE 에 적어라.

                        줄었다면 — 걷어낸 것이니 그 줄을 지워라.

                        chat 이 여기 끼면 그건 다른 문제다 — ChatBoundaryArchitectureTest §C 가 \
                          그쪽을 0 으로 지키고 있고, 그 게이트가 먼저 빨개져야 한다.""")
                .isEqualTo(BASELINE);
    }

    @Test
    @DisplayName("모르는 이름은 남겨서 보여 준다 — 조용히 넘기면 그만큼 검사가 무뎌진다")
    void namesThatBelongToNobodyAreVisible() throws IOException {
        Scan scan = scan(ModuleTables.byEntityName());

        assertThat(new ArrayList<>(new TreeSet<>(scan.unknown())))
                .as("""
                        표 자리에 나온 이름인데 표 지도에도 엔티티에도 없다. 새 표를 만들고 \
                        ModuleTables 에 안 적었거나, 이 검사의 이름 뽑기가 헛것을 잡은 것이다. \
                        둘 다 그냥 넘기면 안 된다 — 넘기는 순간 "0건" 과 "안 봤다" 가 같아진다.""")
                .isEmpty();
    }


    @Test
    @DisplayName("장치가 실제로 잡는다 — 지금 걸리는 것이 하나뿐이라 심어서 본다")
    void theScannerActuallyCatchesWhatItClaimsTo() {
        Map<String, String> byEntity = ModuleTables.byEntityName();

        assertThat(crossingIn("community",
                "select p.id from post p join users u on u.id = p.user_id", byEntity))
                .as("네이티브 조인이 안 걸리면 이 기준선은 아무것도 지키지 않는다")
                .containsExactly("community → user (users)");
        assertThat(crossingIn("community",
                "select p from Post p join User u on u.id = p.userId", byEntity))
                .as("JPQL 조인도 같은 결합이다 — 엔티티 이름만 다르다")
                .containsExactly("community → user (User)");
        assertThat(unknownIn("community",
                "select p.id from post p join nosuchtable n on n.id = p.id", byEntity))
                .as("""
                        모르는 이름을 조용히 넘기면 "0건" 과 "안 봤다" 가 같아진다. 지금 저장소에 \
                        그런 이름이 하나도 없어서, 심어 보지 않으면 그 단언은 빈 목록을 빈 목록과 \
                        비교할 뿐이다.""")
                .containsExactly("nosuchtable");

        assertThat(crossingIn("community",
                "select p.id from post p join comment c on c.post_id = p.id", byEntity))
                .as("같은 모듈 안의 조인은 이 검사의 대상이 아니다 — 시끄러운 게이트는 지워진다")
                .isEmpty();
        assertThat(unknownIn("walk",
                "select w from Walk w join fetch w.dog d where w.id = :id", byEntity))
                .as("별칭으로 시작하는 경로식은 이름이 아니다")
                .isEmpty();
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private record Scan(int queries, List<String> crossing, List<String> unknown) { }

    private static Scan scan(Map<String, String> byEntity) throws IOException {
        List<String> crossing = new ArrayList<>();
        List<String> unknown = new ArrayList<>();
        int queries = 0;

        try (Stream<Path> files = Files.walk(MAIN)) {
            for (Path file : files.filter(f -> f.toString().endsWith(".java")).toList()) {
                String module = moduleOf(file);
                if (module == null) {
                    continue; // 최상위 파일(애플리케이션 클래스 등)은 모듈이 아니다
                }
                String source = QueryScanner.stripComments(
                        Files.readString(file, StandardCharsets.UTF_8));
                for (String query : QueryScanner.queryLiteralsIn(source)) {
                    queries++;
                    crossing.addAll(crossingIn(module, query, byEntity));
                    for (String name : unknownIn(module, query, byEntity)) {
                        unknown.add("%s  →  %s   (%s)".formatted(file.getFileName(), name, query));
                    }
                }
            }
        }
        return new Scan(queries, crossing, unknown);
    }

    /** 이 쿼리가 부르는 <b>남의 모듈</b> 이름들. 파일을 안 읽으므로 손으로 심어서 잴 수 있다. */
    private static List<String> crossingIn(String module, String query,
                                           Map<String, String> byEntity) {
        List<String> out = new ArrayList<>();
        for (String name : QueryScanner.tableReferencesIn(query)) {
            String owner = ModuleTables.ownerOf(name, byEntity);
            if (owner != null && !owner.equals(module)) {
                out.add("%s → %s (%s)".formatted(module, owner, name));
            }
        }
        return out;
    }

    /** 표 자리에 나왔는데 <b>주인을 모르는</b> 이름들. */
    private static List<String> unknownIn(String module, String query,
                                          Map<String, String> byEntity) {
        List<String> out = new ArrayList<>();
        for (String name : QueryScanner.tableReferencesIn(query)) {
            if (ModuleTables.ownerOf(name, byEntity) == null) {
                out.add(name);
            }
        }
        return out;
    }

    /** {@code .../heat_trip_backend/<module>/...} 의 첫 칸. 최상위 파일이면 {@code null}. */
    private static String moduleOf(Path file) {
        Path relative = MAIN.relativize(file);
        return relative.getNameCount() < 2 ? null : relative.getName(0).toString();
    }
}
