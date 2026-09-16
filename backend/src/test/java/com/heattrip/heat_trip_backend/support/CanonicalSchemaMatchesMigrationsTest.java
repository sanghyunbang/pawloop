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
