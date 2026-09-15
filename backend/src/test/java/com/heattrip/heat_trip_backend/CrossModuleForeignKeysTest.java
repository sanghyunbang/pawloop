package com.heattrip.heat_trip_backend;

import com.heattrip.heat_trip_backend.support.ModuleTables;
import com.heattrip.heat_trip_backend.support.ScratchDatabase;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeSet;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * <b>모듈 밖으로 나가는 FK 가 지금 어디에 몇 개 있는가</b> — 이슈 #518 §2.
 *
 * <h2>Modulith 는 이것을 위반으로 세지 않는다</h2>
 * <p>{@code dog.entity.Dog} 와 {@code user.entity.User} 는 {@code @NamedInterface} 로 <b>열린
 * 표면</b>이라, 다섯 모듈이 그 엔티티를 부르는 것은 경계 위반이 아니다({@link ModularityBaselineTest}
 * 가 0 으로 센다). 그런데 <b>DB 의 FK 는 코드의 표면과 무관하게 표를 묶는다</b> — 그 줄은
 * 삭제 정책({@code CASCADE}·{@code SET NULL})까지 함께 정하므로, 한 모듈의 행을 지우는 일이
 * 남의 모듈 행을 지운다.
 *
 * <p>같은 것을 보는 검사는 {@code ChatBoundaryArchitectureTest} §D 뿐이었고 <b>{@code chat}
 * 전용</b>이었다. 그쪽은 "밖으로 나가는 FK 가 0 이어야 한다" 는 <b>게이트</b>다(ADR-0011 결정 4).
 * 여기는 다르다 — 나머지 모듈에는 FK 가 <b>이미 있고</b>, 그것을 걷어내는 것은 별건이다.
 * 그래서 이 검사는 게이트가 아니라 <b>기준선</b>이다: 지금 있는 것을 세어 박아 두고, 새로
 * 생기면 그때 이유를 묻는다.
 *
 * <h2>표를 분류하지 않으면 빨간불이다</h2>
 * <p>새 표를 만들고 이 목록에 안 적으면 {@link #everyTableBelongsToAModule} 이 잡는다. 안
 * 그러면 그 표의 FK 가 <b>조용히 안 세어진다</b> — "0건" 과 "안 봤다" 가 구별되지 않는다.
 *
 * <p>텍스트가 아니라 <b>적용한 결과</b>를 읽는 이유는 §D 와 같다: 정규식은
 * {@code ALTER TABLE ... ADD CONSTRAINT} 를 못 보고, 손으로 고치는 사람이 가장 자연스럽게
 * 쓰는 문법이 그것이다.
 */
class CrossModuleForeignKeysTest {

    /**
     * 표 → 그 표를 소유한 모듈. 지도는 {@link ModuleTables} 한 곳에 있다 — 쿼리 검사
     * ({@code CrossModuleQueryJoinsTest})와 같은 것을 본다. 둘이 각자 분류하면 한쪽만 낡는다.
     */
    private static final Map<String, String> TABLE_MODULE = ModuleTables.BY_TABLE;

    /**
     * 지금 모듈 밖으로 나가는 FK 전부. <b>줄이는 것이 목표다.</b>
     *
     * <p>대부분이 {@code users} 와 {@code dog} 로 간다 — 둘은 이 애플리케이션의 공용 어휘라
     * 코드에서도 열린 표면이다({@code @NamedInterface}). 나머지 둘({@code family_group})은
     * {@code care} 가 가족 그룹에 매달려 있는 자리이고, 그건 #120 이 소유한다.
     *
     * <p><b>{@code chat_*} 가 여기 하나도 없는 것이 요점이다.</b> 그 모듈만 "밖으로 나가는 FK
     * 0" 을 게이트로 지킨다(ADR-0011 결정 4) — 탈퇴 한 번에 남의 대화가 사라지지 않게.
     */
    private static final List<String> BASELINE = List.of(
            "care_log → dog",
            "care_log → family_group",
            "care_log → users",
            "comment → users",
            "crew_favor → dog",
            "crew_favor → users",
            "dog → users",
            "post → dog",
            "post → users",
            "post_bookmark → users",
            "reaction → users",
            "schedule → dog",
            "schedule → users",
            "walk → dog",
            "walk_dog → dog",
            "walk_note → family_group",
            "walk_note → users",
            "weekly_insight → users");

    @Test
    @DisplayName("정본 스키마의 모든 표가 어느 모듈의 것인지 적혀 있다 — 안 적힌 표는 안 세어진다")
    void everyTableBelongsToAModule() throws Exception {
        try (ScratchDatabase db = ScratchDatabase.withCommittedSchema()) {
            List<String> tables = db.queryStrings("""
                    SELECT table_name FROM information_schema.tables
                    WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE'
                    ORDER BY table_name
                    """);

            assertThat(tables).as("표를 하나도 못 읽었으면 아래 검사는 공허하다").isNotEmpty();
            assertThat(tables.stream().filter(t -> !TABLE_MODULE.containsKey(t)).toList())
                    .as("""
                            새 표가 TABLE_MODULE 에 없다. 그 표의 FK 는 지금 **안 세어지고 있다** — \
                            "밖으로 나가는 FK 가 0건" 과 "그 표를 안 봤다" 가 구별되지 않는다. \
                            엔티티의 패키지를 보고 모듈 이름을 적어라.""")
                    .isEmpty();
            assertThat(TABLE_MODULE.keySet().stream().filter(t -> !tables.contains(t)).toList())
                    .as("없는 표가 목록에 남아 있다 — 지운 표의 줄은 함께 지워라")
                    .isEmpty();
        }
    }

    @Test
    @DisplayName("모듈 밖으로 나가는 FK 가 기록과 같다 — 늘었으면 그 줄이 왜 필요한지 적어라")
    void foreignKeysThatLeaveTheirModuleMatchTheBaseline() throws Exception {
        try (ScratchDatabase db = ScratchDatabase.withCommittedSchema()) {
            List<String> all = db.queryStrings("""
                    SELECT CONCAT(table_name, ' → ', referenced_table_name)
                    FROM information_schema.referential_constraints
                    WHERE constraint_schema = DATABASE()
                    ORDER BY table_name, referenced_table_name
                    """);

            assertThat(all).as("FK 를 하나도 못 읽었으면 아래 비교는 공허하다").isNotEmpty();

            List<String> crossing = new ArrayList<>(new TreeSet<>(crossingOf(all)));

            assertThat(crossing)
                    .as("""
                            모듈 밖으로 나가는 FK 목록이 기록과 다르다.

                            늘었다면 — 한 모듈의 행을 지우는 일이 남의 모듈 행을 지우게 됐다는 뜻이다. \
                              (CASCADE 인지 SET NULL 인지가 그만큼 중요해진다.) 정말 필요하면 \
                              BASELINE 에 적고, 왜 그 줄이 필요한지 마이그레이션 주석에 남겨라.

                            줄었다면 — 걷어낸 것이니 그 줄을 지워라.

                            chat_* 가 여기 끼면 그건 다른 문제다 — ChatBoundaryArchitectureTest §D \
                              가 그쪽을 0 으로 지키고 있고, 그 게이트가 먼저 빨개져야 한다.""")
                    .isEqualTo(BASELINE);
        }
    }

    @Test
    @DisplayName("같은 모듈 안의 FK 는 세지 않는다 — 이 검사가 무엇을 안 보는지도 분명히 한다")
    void foreignKeysInsideOneModuleAreNotCounted() {
        Map<String, String> sample = new LinkedHashMap<>();
        sample.put("chat_message → chat_room", "");
        sample.put("post → users", "");

        assertThat(crossingOf(List.copyOf(sample.keySet())))
                .as("경계 안쪽 FK 는 이 검사의 대상이 아니다 — 그건 그 모듈이 알아서 할 일이다")
                .containsExactly("post → users");
    }

    /** {@code A → B} 중 A 와 B 의 모듈이 다른 것만. 모르는 표는 남긴다 — 위 검사가 잡는다. */
    private static List<String> crossingOf(List<String> pairs) {
        List<String> crossing = new ArrayList<>();
        for (String pair : pairs) {
            String[] sides = pair.split(" → ");
            String from = TABLE_MODULE.get(sides[0]);
            String to = TABLE_MODULE.get(sides[1]);
            if (from == null || to == null || !from.equals(to)) {
                crossing.add(pair);
            }
        }
        return crossing;
    }
}
