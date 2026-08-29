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
 * refresh_token 마이그레이션 스크립트 자체를 검증한다 — 이슈 #9.
 *
 * <p>왜 테스트인가: 운영 스키마에 {@code UNIQUE(token_hash)} 를 거는 것은 이 SQL 파일 하나뿐이다.
 * {@code spring.jpa.hibernate.ddl-auto=validate} 는 테이블·컬럼만 보고 <b>UNIQUE 제약도
 * 인덱스도 검사하지 않으므로</b>, 이 파일이 사라지거나 제약 문장이 빠져도 앱은 멀쩡히 뜬다.
 * 그러면 재사용 감지의 전제("해시 1개 = 행 1개")가 운영에서만 조용히 무너진다.
 * {@code RefreshTokenRepositoryTest} 의 초록불은 <b>엔티티가 만든</b> 스키마만 보증한다.
 *
 * <p>파일이 <b>실행되는 자리</b>에 있는지도 함께 잠근다. 사람이 손으로 돌리는 SQL 은 전부
 * {@code backend/mysql/post-start} 에 번호 순으로 있고 런북({@code mysql/README.md})이 그
 * 디렉터리만 가리킨다. 런북이 가리키지 않는 SQL 은 아무도 돌리지 않는다.
 *
 * <p>단언에 쓰는 문자열은 <b>파일 안에서 유일한 것</b>으로 골랐다. #7 에서 §C 가드와 §D 검증에
 * 똑같이 있는 문자열로 잠근 탓에 검증 블록을 통째로 지워도 초록불이던 전례가 있다.
 *
 * <h2>이 테스트가 <b>하지 않는</b> 것 — 후속 작업</h2>
 * <p>여기 있는 것은 전부 <b>텍스트 검사</b>다. 파일이 제자리에 있고 핵심 문장이 남아 있는지만
 * 본다. 그래서 문법 오류·{@code PREPARE} 조립 실패·"중단 관문이 실제로는 중단하지 않는 형태"
 * 는 전부 초록불로 통과한다. 스크립트 자체는 실 MySQL 8 에서 손으로 돌려
 * 정상 동작·멱등을 확인했지만, 그건 CI 가 매번 확인해 주는 것이 아니다.
 *
 * <p>이 브랜치가 갈라진 뒤 {@code main} 에 이슈 #57(`test/56-migration-sql-execution`)이 들어와
 * {@code 04_users_social_account_model.sql} 은 이제 Testcontainers 위에서 저장소의 운영
 * 스크립트를 그대로 <b>실행</b>해 검증한다({@code UserSchemaMigrationExecutionTest}).
 * <b>05 도 같은 형태로 올려야 한다</b> — 최소 세 가지면 충분하다:
 * ①빈 스키마에 적용 후 UNIQUE·인덱스가 실제로 걸리는가 ②재실행 멱등 ③Hibernate 가 UNIQUE
 * 없이 먼저 만든 테이블에 중복 {@code token_hash} 를 심어 두면 §0-5 가 스키마를 건드리기
 * 전에 중단하는가.
 *
 * <p><b>여기서 하지 않은 이유:</b> 그 실행 인프라는 이 브랜치의 분기점에 존재하지 않는다.
 * {@code main} 을 머지해야 쓸 수 있고, 그 머지는 리뷰 중인 diff 의 범위를 바꾼다.
 * 후속 작업으로 남긴다 — 이 문단이 그 기록이다.
 *
 * <p>네트워크를 타지 않는다. 저장소 안의 파일만 읽는다.
 */
class RefreshTokenSchemaMigrationSpecTest {

    private static final String MIGRATION_FILE = "05_refresh_token.sql";

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
    @DisplayName("마이그레이션이 엔티티와 같은 컬럼 정의로 refresh_token 테이블을 만든다")
    void migration_createsTheTableMatchingTheEntity() {
        // 타입이 엔티티와 어긋나면 prod 의 ddl-auto=validate 가 부팅을 막는다.
        // token_hash 가 CHAR 가 아니라 VARCHAR 인 것도 그 때문이다 — Hibernate 는 String 을
        // VARCHAR 로 매핑한다.
        assertThat(migrationSql).contains("CREATE TABLE IF NOT EXISTS refresh_token");
        assertThat(migrationSql).contains("token_hash VARCHAR(64) NOT NULL");
        assertThat(migrationSql).contains("expires_at DATETIME(6) NOT NULL");
        assertThat(migrationSql).contains("revoked_at DATETIME(6) NULL");
    }

    @Test
    @DisplayName("마이그레이션이 엔티티와 같은 이름의 UNIQUE(token_hash) 제약과 두 인덱스를 만든다")
    void migration_createsUniqueConstraintAndIndexes() {
        // 이름은 RefreshToken 엔티티의 @Table(uniqueConstraints/indexes) 와 같아야 한다.
        assertThat(migrationSql)
                .as("이 제약이 없으면 findByTokenHash 가 어느 행을 줄지 미정이 되고 재사용 감지가 무너진다")
                .contains("ADD CONSTRAINT uk_refresh_token_token_hash UNIQUE (token_hash)");
        assertThat(migrationSql)
                .as("전 기기 폐기·탈퇴 삭제가 타는 인덱스다")
                .contains("CREATE INDEX idx_refresh_token_user_id ON refresh_token (user_id)");
        assertThat(migrationSql)
                .as("야간 만료 정리가 타는 범위 스캔 인덱스다")
                .contains("CREATE INDEX idx_refresh_token_expires_at ON refresh_token (expires_at)");
    }

    @Test
    @DisplayName("DDL 은 재실행해도 안전하다 — 01~04 와 같은 information_schema 가드를 쓴다")
    void migration_isIdempotent() {
        // MySQL 에는 ADD COLUMN/ADD CONSTRAINT 용 IF NOT EXISTS 가 없다.
        assertThat(migrationSql).contains("information_schema.columns");
        assertThat(migrationSql).contains("information_schema.statistics");
        assertThat(migrationSql).contains("PREPARE stmt FROM @stmt");
        assertThat(migrationSql).contains("DEALLOCATE PREPARE stmt");
    }

    @Test
    @DisplayName("실행 전 사전 점검이 있고, UNIQUE 를 못 걸 데이터가 있으면 스키마를 건드리기 전에 중단한다")
    void migration_hasPreflightGate() {
        // dev 는 ddl-auto=update 라 앱이 먼저 뜨면 Hibernate 가 테이블을 이미 만들어 둔다.
        // 엔티티 초안이 다른 상태로 만든 테이블에 중복 해시가 있으면 UNIQUE 를 걸 수 없다.
        assertThat(migrationSql).contains("SIGNAL SQLSTATE '45000'");
        assertThat(migrationSql).contains("heattrip_migration_abort");
        assertThat(migrationSql)
                .as("중복과 NULL 을 한 번에 모은다")
                .contains("HAVING COUNT(*) > 1 OR r.token_hash IS NULL");
        // 중단 조건은 §0-5 에만 있다. 진단 SELECT 만 남기고 중단을 지우면 여기서 걸린다.
        assertThat(migrationSql)
                .as("걸린 것이 하나라도 있으면 실제로 중단한다")
                .contains("IF(@bad_hashes > 0,");
        assertThat(migrationSql).contains("ABORT: token_hash 중복/NULL ");
    }

    @Test
    @DisplayName("실행 후 사후 검증이 있고, 컬럼·UNIQUE·인덱스 중 하나라도 빠지면 실패로 끝낸다")
    void migration_hasPostflightGate() {
        // 아래 문자열들은 §D 에만 있다. §C 의 멱등 가드는 index_name 만 보고 non_unique 는 쓰지 않는다.
        assertThat(migrationSql)
                .as("UNIQUE 인덱스가 '실제로 유니크한지' 를 센다 — 이름만 같은 일반 인덱스와 구별된다")
                .contains("non_unique = 0");
        assertThat(migrationSql)
                .as("컬럼 6개·UNIQUE 1컬럼·인덱스 2개를 한 조건으로 검사한다")
                .contains("IF(@rt_columns <> 6 OR @unique_cols <> 1 "
                        + "OR @user_idx < 1 OR @expires_idx < 1,");
        assertThat(migrationSql)
                .as("어긋나면 성공이 아니라 실패로 끝난다")
                .contains("ABORT: 반쯤 적용됨");
    }

    @Test
    @DisplayName("두 관문의 중단 메시지가 서로 다르고 각각 한 번씩만 나온다 — 어느 관문에서 멈췄는지 로그로 구분된다")
    void migration_abortMessagesAreDistinguishable() {
        // 같은 메시지를 쓰면 운영자가 '데이터가 더러워서 시작도 못 한 것'과 '반쯤 적용되고 멈춘 것'을
        // 구분할 수 없다. 후자는 즉시 복구가 필요하다.
        assertThat(migrationSql.split("ABORT: token_hash 중복/NULL ", -1).length - 1).isEqualTo(1);
        assertThat(migrationSql.split("ABORT: 반쯤 적용됨", -1).length - 1).isEqualTo(1);
    }

    @Test
    @DisplayName("트랜잭션으로 되돌아간다고 서술하지 않고, DOWN SQL 과 실행 순서를 남긴다")
    void migration_documentsIrreversibilityAndDownSql() {
        assertThat(migrationSql).contains("암묵적 커밋");
        assertThat(migrationSql).contains("DROP TABLE refresh_token;");
        assertThat(migrationSql)
                .as("SQL 을 앱 배포 전에 돌려야 한다는 사실이 파일 안에 있어야 한다")
                .contains("앱 배포 **전**");
    }

    @Test
    @DisplayName("만료 행을 누가 지우는지가 스크립트에 적혀 있다 — 이 SQL 은 만들기만 한다")
    void migration_recordsWhoPurgesExpiredRows() {
        // 이걸 적어 두지 않으면 다음 사람이 여기에 DELETE 이벤트나 EVENT SCHEDULER 를 붙인다.
        assertThat(migrationSql).contains("RefreshTokenPurgeScheduler");
        assertThat(migrationSql).contains("auth.refresh-token.purge-cron");
    }

    @Test
    @DisplayName("런북(mysql/README.md)이 이 파일의 실행 커맨드와 실패 시 동작을 담고 있다")
    void runbook_listsTheMigration() {
        // 실행 절차가 가리키지 않는 SQL 은 아무도 돌리지 않는다.
        assertThat(runbook).contains("post-start\\" + MIGRATION_FILE);
        assertThat(runbook)
                .as("05 의 관문이 왜 필요한지가 런북에 있어야 한다 — 04 절만 읽고 넘어가지 않도록")
                .contains("### 05는 실패하면 멈춥니다");
    }
}
