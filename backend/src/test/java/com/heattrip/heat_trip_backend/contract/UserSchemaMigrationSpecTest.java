package com.heattrip.heat_trip_backend.contract;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 마이그레이션 스크립트 자체를 검증한다 — 이슈 #7.
 *
 * <p>왜 테스트인가: 운영 스키마의 {@code UNIQUE(provider, social_id)} 를 만드는 것은 이 SQL 파일
 * 하나뿐이다. {@code spring.jpa.hibernate.ddl-auto=validate} 는 테이블·컬럼만 보고 유니크 제약은
 * 검사하지 않으므로, 이 파일이 사라지거나 제약 문장이 빠져도 앱은 멀쩡히 뜬다. 그러면 이슈 #7 의
 * 완료 조건 5("같은 (provider, social_id) 로 INSERT 하면 DB 가 거부한다")가 운영에서만 조용히
 * 깨진 채로 남는다. {@code UserRepositoryTest} 의 초록불은 엔티티가 H2 에 만든 스키마만 보증한다.
 *
 * <p>그리고 파일이 <b>실행되는 자리</b>에 있는지도 함께 잠근다. 이 저장소에서 사람이 손으로 돌리는
 * SQL 은 전부 {@code backend/mysql/post-start} 에 번호 순으로 있고 런북({@code mysql/README.md})이
 * 그 디렉터리만 가리킨다. 문서 디렉터리에 두면 배포 담당자가 영원히 실행하지 않는다.
 *
 * <p>SQL 을 실제 MySQL 에 돌려 보는 검증은 이 테스트의 범위가 아니다(실 DB 가 필요하다 — #26
 * Testcontainers). 여기서 막는 것은 '파일이 사라지거나 핵심 문장이 빠지는' 드리프트다.
 *
 * <p>네트워크를 타지 않는다. 저장소 안의 파일만 읽는다.
 */
class UserSchemaMigrationSpecTest {

    private static final String MIGRATION_FILE = "04_users_social_account_model.sql";

    private static String migrationSql;
    private static String runbook;

    @BeforeAll
    static void loadFiles() throws IOException {
        Path mysqlDir = locateMysqlDir();
        migrationSql = Files.readString(
                mysqlDir.resolve("post-start").resolve(MIGRATION_FILE), StandardCharsets.UTF_8);
        runbook = Files.readString(mysqlDir.resolve("README.md"), StandardCharsets.UTF_8);
    }

    /** 테스트 작업 디렉터리(backend/)에서 위로 올라가며 mysql/post-start 를 찾는다. */
    private static Path locateMysqlDir() {
        Path cursor = Paths.get("").toAbsolutePath();
        while (cursor != null) {
            Path candidate = cursor.resolve("mysql");
            if (Files.exists(candidate.resolve("post-start").resolve(MIGRATION_FILE))) {
                return candidate;
            }
            candidate = cursor.resolve("backend").resolve("mysql");
            if (Files.exists(candidate.resolve("post-start").resolve(MIGRATION_FILE))) {
                return candidate;
            }
            cursor = cursor.getParent();
        }
        throw new IllegalStateException("backend/mysql/post-start/" + MIGRATION_FILE
                + " 을 찾지 못했다. 실행되는 자리는 mysql/post-start 다(문서 디렉터리가 아니다)."
                + " 작업 디렉터리: " + Paths.get("").toAbsolutePath());
    }

    @Test
    @DisplayName("마이그레이션이 엔티티와 같은 이름의 UNIQUE(provider, social_id) 제약을 만든다")
    void migration_createsUniqueConstraintMatchingTheEntity() {
        // 이름은 User 엔티티의 @Table(uniqueConstraints = @UniqueConstraint(name = ...)) 와 같아야 한다.
        assertThat(migrationSql)
                .contains("ADD CONSTRAINT uk_users_provider_social_id UNIQUE (provider, social_id)");
    }

    @Test
    @DisplayName("마이그레이션이 provider·social_id·role 컬럼을 추가한다")
    void migration_addsNewColumns() {
        assertThat(migrationSql).contains("ADD COLUMN provider VARCHAR(20)");
        assertThat(migrationSql).contains("ADD COLUMN social_id VARCHAR(191)");
        assertThat(migrationSql).contains("ADD COLUMN role VARCHAR(20) NOT NULL DEFAULT ''ROLE_USER''");
    }

    @Test
    @DisplayName("DDL 은 재실행해도 안전하다 — 01~03 과 같은 information_schema 가드를 쓴다")
    void migration_isIdempotent() {
        // MySQL 에는 ADD COLUMN/ADD CONSTRAINT 용 IF NOT EXISTS 가 없다. 이 저장소는
        // information_schema 조회 + PREPARE/EXECUTE 로 그 문제를 이미 풀어 놨다.
        assertThat(migrationSql).contains("information_schema.columns");
        assertThat(migrationSql).contains("information_schema.statistics");
        assertThat(migrationSql).contains("PREPARE stmt FROM @stmt");
        assertThat(migrationSql).contains("DEALLOCATE PREPARE stmt");
    }

    @Test
    @DisplayName("실행 전 중복 사전 점검이 있고, 걸리면 users 를 건드리기 전에 중단한다")
    void migration_hasPreflightGate() {
        // DDL 은 MySQL 에서 암묵 커밋을 일으켜 롤백되지 않는다. 트랜잭션 대신 두 관문이
        // '반쯤 적용된 채 성공처럼 끝나는' 상태를 막는다. 이 테스트는 그 첫 번째다.
        assertThat(migrationSql).contains("SIGNAL SQLSTATE '45000'");
        assertThat(migrationSql).contains("heattrip_migration_abort");
        assertThat(migrationSql)
                .as("중복 (provider, social_id) 를 그룹으로 집계해 찾는다")
                .contains("HAVING COUNT(*) > 1");
        // 중단 조건과 메시지는 §0-6 에만 있다. 진단 SELECT 만 남기고 중단을 지우면 여기서 걸린다.
        assertThat(migrationSql)
                .as("중복·길이초과가 하나라도 있으면 실제로 중단한다")
                .contains("IF(@dup_groups > 0 OR @too_long > 0,");
        assertThat(migrationSql).contains("ABORT: 중복 소셜 계정 ");
    }

    @Test
    @DisplayName("실행 후 사후 검증이 있고, 컬럼·제약·백필 중 하나라도 빠지면 실패로 끝낸다")
    void migration_hasPostflightGate() {
        // 왜 별도 테스트인가: 예전에는 사후 검증(§D)을 겨눈 단언이
        // "index_name = 'uk_users_provider_social_id'" 하나뿐이었는데, 그 문자열은 §C 의
        // 멱등 가드에도 똑같이 있다. 그래서 §D 블록을 통째로 지워도 스펙 테스트가 전부
        // 초록불이었다 — 잠근 척만 하는 단언이었다. 아래 문자열들은 §D 에만 있다.
        assertThat(migrationSql)
                .as("UNIQUE 인덱스가 두 컬럼짜리로 실제 걸렸는지 센다(§C 가드는 이 조건을 쓰지 않는다)")
                .contains("non_unique = 0");
        assertThat(migrationSql)
                .as("컬럼 3개·UNIQUE 2컬럼·provider NULL 0행·role 공백 0행을 한 조건으로 검사한다")
                .contains("IF(@new_columns <> 3 OR @unique_cols <> 2 "
                        + "OR @provider_nulls > 0 OR @role_blanks > 0,");
        assertThat(migrationSql)
                .as("어긋나면 성공이 아니라 실패로 끝난다")
                .contains("ABORT: 반쯤 적용됨");
    }

    @Test
    @DisplayName("두 관문의 중단 메시지가 서로 다르다 — 어느 관문에서 멈췄는지 로그로 구분된다")
    void migration_abortMessagesAreDistinguishable() {
        // 같은 메시지를 쓰면 운영자가 '데이터가 더러워서 안 시작한 것'과
        // '반쯤 적용되고 멈춘 것'을 구분할 수 없다. 후자는 즉시 복구가 필요하다.
        assertThat(migrationSql.split("ABORT: 중복 소셜 계정 ", -1).length - 1).isEqualTo(1);
        assertThat(migrationSql.split("ABORT: 반쯤 적용됨", -1).length - 1).isEqualTo(1);
    }

    @Test
    @DisplayName("username 을 참조하는 사전 점검 조각은 전부 컬럼 존재 가드 안에 있다")
    void migration_precheckToleratesDroppedUsernameColumn() {
        // §E 의 후속 이슈가 username 을 지운 뒤 이 스크립트를 다시 돌리면,
        // 가드 없이 조립된 COALESCE(u.provider, … u.username …) 이
        // ERROR 1054 'Unknown column u.username' 로 사전 점검 자체를 죽인다.
        assertThat(migrationSql).contains("@col_username := (");
        assertThat(migrationSql)
                .as("provider 식이 username 가드 안에서만 username 을 참조한다")
                .contains("IF(@col_username = 1, "
                        + "'COALESCE(u.provider, SUBSTRING_INDEX(u.username, ''_'', 1))', 'u.provider')");
        assertThat(migrationSql)
                .as("social_id 식도 마찬가지다")
                .contains("'u.social_id')");
        assertThat(migrationSql)
                .as("둘 다 없으면 INSERT 문장을 아예 만들지 않는다")
                .contains("IF(@col_social_id = 0 AND @col_username = 0,");
    }

    @Test
    @DisplayName("트랜잭션으로 되돌아간다고 서술하지 않고, DOWN SQL 을 남긴다")
    void migration_documentsIrreversibilityAndDownSql() {
        assertThat(migrationSql).contains("암묵적 커밋");
        assertThat(migrationSql).contains("DROP INDEX uk_users_provider_social_id");
        assertThat(migrationSql).contains("DROP COLUMN provider, DROP COLUMN social_id, DROP COLUMN role");
        // 초안에는 '운영자는 어차피 SQL 을 실행하므로 같은 트랜잭션 안에서 끝낸다'는 서술이 있었다.
        // MySQL 에서 성립하지 않는 말이고, 실패해도 되돌아간다고 믿게 만든다.
        assertThat(migrationSql).doesNotContain("같은 트랜잭션 안에서 끝낸다");
    }

    @Test
    @DisplayName("런북(mysql/README.md)이 이 파일의 실행 커맨드를 담고 있다")
    void runbook_listsTheMigration() {
        // 실행 절차가 가리키지 않는 SQL 은 아무도 돌리지 않는다.
        assertThat(runbook).contains("post-start\\" + MIGRATION_FILE);
    }
}
