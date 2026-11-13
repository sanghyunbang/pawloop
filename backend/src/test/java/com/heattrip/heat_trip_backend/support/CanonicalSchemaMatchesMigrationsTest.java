package com.heattrip.heat_trip_backend.support;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 읽기용 사본이 <b>마이그레이션과 같은 스키마를 말하는가</b> — 이슈 #592 조각 2.
 *
 * <h2>왜 아직 두 벌인가</h2>
 *
 * <p>{@code db/migration/V*.sql} 이 <b>실제로 스키마를 만드는 쪽</b>이다. 그런데
 * {@code mysql/init/01_schema.sql} 도 아직 남아 있고, 스물여덟 개 검사와 문서 여러 곳이 그
 * 파일을 읽는다 — 마이그레이션 실행 검사들이 "표가 이미 있는 상태" 를 만들 때 쓰고,
 * {@code DocDriftTest} 가 표 목록을 그 파일에서 센다.
 *
 * <p>그래서 이번 조각에서는 지우지 않는다. 대신 <b>둘이 같은 스키마를 말하는지</b>를 여기서
 * 잠근다. 어긋나면 그 스물여덟 개가 <b>실제와 다른 바닥</b> 위에서 돌기 시작한다.
 *
 * <h2>왜 파일 비교가 아니라 결과 비교인가</h2>
 *
 * <p>앞서 있던 {@code BaselineMatchesCanonicalSchemaTest} 는 {@code V1} 과
 * {@code 01_schema.sql} 의 <b>글자</b>를 비교했다. {@code V1} 하나뿐일 때는 그것으로 됐지만
 * {@code V2} 가 생기는 순간 못 쓴다 — 사본에는 {@code V2} 의 변경이 녹아 있고
 * {@code V1} 에는 없으니 글자가 다른 것이 정상이다.
 *
 * <p>그래서 <b>둘을 각각 빈 DB 에 적용해 나온 스키마</b>를 비교한다. 이러면 {@code V} 가 몇
 * 개로 늘든 계속 유효하다.
 *
 * <h2>컬럼만으로는 모자란다 — 이슈 #718</h2>
 *
 * <p>통합 테스트는 Flyway 를 끄고 <b>엔티티에서</b> 표를 만든다({@code AbstractMySqlIntegrationTest}).
 * 그래서 {@code V} 파일에 손으로 적은 CHECK·FK·인덱스가 엔티티와 다르면, 테스트가 확인한 규칙과
 * <b>운영 DB 가 지키는 규칙이 달라지는데</b> 어떤 검사도 그것을 안 봤다. 컬럼 비교는 타입과
 * 널허용만 본다. 둘째 검사가 그 셋을 이름까지 대조한다.
 */
class CanonicalSchemaMatchesMigrationsTest {

    @Test
    @DisplayName("01_schema.sql 을 적용한 결과가 마이그레이션을 다 돌린 결과와 같다")
    void theCopyAgreesWithTheMigrations() throws Exception {
        Map<String, List<String>> fromMigrations;
        try (ScratchDatabase migrated = ScratchDatabase.withMigrations()) {
            fromMigrations = describe(migrated.connection());
        }

        Map<String, List<String>> fromCopy;
        try (ScratchDatabase copied = ScratchDatabase.withCommittedSchema()) {
            fromCopy = describe(copied.connection());
        }

        assertThat(fromCopy)
                .as("""
                        읽기용 사본(mysql/init/01_schema.sql)이 마이그레이션과 어긋났다.

                        마이그레이션을 쓴 뒤 사본을 다시 안 뽑았을 때 이렇게 된다. 이 파일을 \
                        바닥으로 쓰는 검사가 스물여덟 개라, 어긋난 채로 두면 그것들이 실제와 \
                        다른 스키마 위에서 돈다.

                        고치는 법:
                          ./gradlew test --tests '*SchemaDdlDriftTest*'
                          cp build/generated-schema.sql mysql/init/01_schema.sql""")
                .isEqualTo(fromMigrations);
    }

    @Test
    @DisplayName("CHECK·FK·인덱스도 이름까지 같다 — 통합 테스트는 엔티티에서 표를 만들어 이것들을 안 본다")
    void theConstraintsAgreeToo() throws Exception {
        Map<String, List<String>> fromMigrations;
        try (ScratchDatabase migrated = ScratchDatabase.withMigrations()) {
            fromMigrations = constraints(migrated);
        }

        Map<String, List<String>> fromCopy;
        try (ScratchDatabase copied = ScratchDatabase.withCommittedSchema()) {
            fromCopy = constraints(copied);
        }

        for (Map.Entry<String, List<String>> expected : fromMigrations.entrySet()) {
            // 조회가 조용히 0줄을 돌려주면 아래 비교가 빈 목록끼리 초록이 된다.
            assertThat(expected.getValue())
                    .as("마이그레이션에서 %s 를 하나도 못 읽었다 — 조회가 늙었다", expected.getKey())
                    .isNotEmpty();
            assertThat(fromCopy.get(expected.getKey()))
                    .as("""
                            %s 가 마이그레이션(운영)과 읽기용 사본(엔티티)에서 다르다.

                            통합 테스트는 엔티티에서 표를 만든다. 이대로 두면 테스트가 확인한 규칙과 \
                            운영 DB 가 지키는 규칙이 다르다.

                            고치는 법: 어느 쪽이 맞는지 정한다. 아직 운영에 안 나간 V 파일이 틀렸으면 그 \
                            파일을 고치고, 이미 나간 것이면 새 V 파일로 따라오게 한다. 엔티티가 틀렸으면 \
                            엔티티를 고치고 사본을 다시 뽑는다.""", expected.getKey())
                    .containsExactlyElementsOf(expected.getValue());
        }
    }

    /**
     * 종류 → 한 줄씩. <b>이름까지</b> 넣는다 — 위반 메시지(MySQL 3819)와 되돌리기 문장이 이름으로
     * 그것을 가리키므로, 규칙이 같아도 이름이 다르면 운영에서 찾을 수가 없다.
     */
    private static Map<String, List<String>> constraints(ScratchDatabase db) throws SQLException {
        Map<String, List<String>> out = new LinkedHashMap<>();
        out.put("CHECK", db.queryStrings("""
                SELECT CONCAT_WS(' ', tc.table_name, cc.constraint_name, cc.check_clause)
                FROM information_schema.check_constraints cc
                JOIN information_schema.table_constraints tc
                  ON tc.constraint_schema = cc.constraint_schema
                 AND tc.constraint_name = cc.constraint_name
                 AND tc.constraint_type = 'CHECK'
                WHERE cc.constraint_schema = DATABASE()
                ORDER BY 1
                """));
        out.put("FK", db.queryStrings("""
                SELECT CONCAT_WS(' ', k.table_name, k.constraint_name, k.column_name, '->',
                                 k.referenced_table_name, k.referenced_column_name,
                                 'on delete', r.delete_rule, 'on update', r.update_rule)
                FROM information_schema.key_column_usage k
                JOIN information_schema.referential_constraints r
                  ON r.constraint_schema = k.constraint_schema
                 AND r.constraint_name = k.constraint_name
                 AND r.table_name = k.table_name
                WHERE k.table_schema = DATABASE()
                  AND k.referenced_table_name IS NOT NULL
                ORDER BY 1
                """));
        out.put("인덱스", db.queryStrings("""
                SELECT CONCAT_WS(' ', table_name, index_name,
                                 IF(non_unique = 0, 'unique', 'non-unique'),
                                 GROUP_CONCAT(column_name ORDER BY seq_in_index))
                FROM information_schema.statistics
                WHERE table_schema = DATABASE()
                  AND table_name <> 'flyway_schema_history'
                GROUP BY table_name, index_name, non_unique
                ORDER BY 1
                """));
        return out;
    }

    /** 표 → "컬럼 타입 널허용" 목록. {@code SchemaDdlDriftTest} 와 같은 방식으로 읽는다. */
    private static Map<String, List<String>> describe(Connection connection) throws SQLException {
        Map<String, List<String>> out = new LinkedHashMap<>();
        try (Statement st = connection.createStatement();
             ResultSet rs = st.executeQuery("""
                     SELECT table_name, column_name, column_type, is_nullable
                     FROM information_schema.columns
                     WHERE table_schema = DATABASE()
                       AND table_name <> 'flyway_schema_history'
                     ORDER BY table_name, column_name
                     """)) {
            while (rs.next()) {
                out.computeIfAbsent(rs.getString(1).toLowerCase(), k -> new ArrayList<>())
                        .add(rs.getString(2).toLowerCase() + " "
                                + rs.getString(3).toLowerCase() + " " + rs.getString(4));
            }
        }
        return out;
    }
}
