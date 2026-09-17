package com.heattrip.heat_trip_backend.contract;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

import com.heattrip.heat_trip_backend.support.TestProjectPaths;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 스펙 테스트가 읽는 저장소 파일이 Gradle {@code test} 태스크의 입력으로 선언돼 있는지 잠근다
 * — 이슈 #46.
 *
 * <h2>왜 이게 테스트여야 하나</h2>
 * <p>이 저장소에는 <b>저장소 파일을 읽는 테스트</b>가 여럿 있다.
 * {@link AuthContractSpecTest} 는 {@code docs/04-api/openapi.yaml} 을,
 * {@link UserSchemaMigrationSpecTest} 는 {@code mysql/post-start/*.sql} 과
 * {@code mysql/README.md} 를, {@code MySqlComposeParityTest} 는
 * {@code docker-compose.yml} 을 읽는다.
 *
 * <p>Gradle 은 그 파일들을 <b>모른다</b>. 선언하지 않으면 자바 소스가 그대로인 채 계약 문서만
 * 바뀌었을 때 {@code test} 태스크가 {@code UP-TO-DATE} 로 건너뛴다 —
 * <b>계약이 깨졌는데 빌드가 초록이다.</b> 실측으로 확인했다: 선언을 지우고
 * {@code openapi.yaml} 에 한 줄을 더한 뒤 {@code ./gradlew test} 를 돌리면
 * {@code Task :test UP-TO-DATE / BUILD SUCCESSFUL in 2s} 다.
 *
 * <p>선언이 있으면 같은 상황에서 테스트가 다시 돈다. 그래서 이건 속도 최적화가 아니라
 * <b>정확성 장치</b>이고, 지워지면 조용히 거짓 초록불로 돌아간다. 그래서 잠근다.
 *
 * <h2>새 스펙 테스트를 만들 때</h2>
 * <p>저장소 파일을 새로 읽는 테스트를 추가했다면 {@code build.gradle} 의
 * {@code tasks.named('test')} 안에 그 경로도 {@code inputs.files(...)} 로 더해야 한다.
 * 이 테스트는 <b>이미 아는 경로</b>만 지킨다 — 새 경로까지 자동으로 알 수는 없다.
 * (지금 아는 것: {@code mysql/} · {@code docker-compose.yml} · {@code .gitignore} ·
 * {@code .dockerignore} · {@code infra/terraform/**}{@code /*.tftpl} · {@code Caddyfile} ·
 * {@code docker-compose.prod.yml} · {@code docs/04-api} ·
 * {@code docs/02-architecture/backend} · {@code docs/99-decisions} · {@code docs/05-build} ·
 * {@code docs/03-database})
 *
 * <p>네트워크를 타지 않는다. 저장소 안의 파일만 읽는다.
 */
class SpecTestInputsDeclaredTest {

    private static String buildGradle;

    @BeforeAll
    static void loadBuildFile() throws IOException {
        Path path = TestProjectPaths.requireFile("build.gradle");
        buildGradle = Files.readString(path, StandardCharsets.UTF_8);
    }

    @Test
    @DisplayName("계약 문서(docs/04-api)가 test 태스크의 입력으로 선언돼 있다")
    void apiContract_isDeclaredAsTestInput() {
        assertThat(buildGradle)
                .as("선언이 없으면 openapi.yaml 이 깨져도 test 가 UP-TO-DATE 로 건너뛴다 (#46)")
                .contains("file('../docs/04-api')")
                .contains("withPropertyName('apiContract')");
    }

    @Test
    @DisplayName("운영 SQL 과 런북(mysql/)이 test 태스크의 입력으로 선언돼 있다")
    void operationalSql_isDeclaredAsTestInput() {
        // UserSchemaMigrationSpecTest 가 post-start/*.sql 과 README.md 를 읽고,
        // AbstractMySqlIntegrationTest 는 01_add_places_search_fulltext.sql 을 실제로 실행한다.
        assertThat(buildGradle)
                .contains("file('mysql')")
                .contains("withPropertyName('operationalSqlAndRunbook')");
    }

    @Test
    @DisplayName("ADR 로그·로드맵·DB 문서가 test 태스크의 입력으로 선언돼 있다")
    void repositoryDocs_areDeclaredAsTestInputs() {
        // DecisionLogTest 는 docs/99-decisions/ 를, DocDriftTest 는 docs/05-build/ 와
        // docs/03-database/ 를 읽는다 (#15). 선언하지 않으면 문서만 고쳤을 때 test 가
        // UP-TO-DATE 로 건너뛴다.
        //
        // 이걸 실측으로 확인했다. ADR-0010 의 제목 한 줄을 깨고 `./gradlew test` 를 돌리면
        //   선언 전: Task :test UP-TO-DATE / BUILD SUCCESSFUL in 2s   ← 드리프트를 놓친다
        //   선언 후: DecisionLogTest … FAILED / BUILD FAILED in 14s
        assertThat(buildGradle)
                .as("선언이 없으면 ADR 인덱스 앵커가 깨져도 test 가 UP-TO-DATE 로 건너뛴다 (#15)")
                .contains("file('../docs/99-decisions')")
                .contains("withPropertyName('decisionLog')");
        assertThat(buildGradle)
                .contains("file('../docs/05-build')")
                .contains("withPropertyName('roadmapAndStatus')");
        assertThat(buildGradle)
                .contains("file('../docs/03-database')")
                .contains("withPropertyName('databaseDocs')");
    }

    @Test
    @DisplayName("운영 스크립트(scripts/*.sh)가 test 태스크의 입력으로 선언돼 있다")
    void opsScripts_areDeclaredAsTestInputs() {
        // MigrationChecksAreCompleteTest 가 scripts/check-migrations.sh 를 읽어 "빠뜨린
        // 마이그레이션이 없다" 를 지킨다. 선언이 없으면 그 스크립트에서 검사 한 줄을 지워도
        // test 가 UP-TO-DATE 로 건너뛴다 — 지키는 것이 없어진다.
        assertThat(buildGradle)
                .contains("file('../scripts')")
                .contains("withPropertyName('opsScripts')");
    }

    @Test
    @DisplayName("docker-compose.yml 이 test 태스크의 입력으로 선언돼 있다")
    void dockerCompose_isDeclaredAsTestInput() {
        // MySqlComposeParityTest 가 컨테이너 플래그를 compose 와 대조한다(#26).
        assertThat(buildGradle)
                .contains("file('docker-compose.yml')")
                .contains("withPropertyName('dockerCompose')");
    }

    @Test
    @DisplayName("무시 규칙(.gitignore/.dockerignore)이 test 태스크의 입력으로 선언돼 있다")
    void ignoreRules_areDeclaredAsTestInputs() {
        // BootAssetsTravelWithTheCloneTest 가 둘 다 읽어 "부팅 자산이 클론과 이미지를
        // 따라간다" 를 지킨다(#591·#601). 선언이 없으면 무시 규칙을 다시 넓혀 놓고도
        // test 가 UP-TO-DATE 로 건너뛴다 — 지키는 것이 없어진다.
        assertThat(buildGradle)
                .as("선언이 없으면 무시 규칙만 고쳤을 때 자산 검사가 아예 돌지 않는다 (#601)")
                .contains("file('.gitignore'), file('.dockerignore')")
                .contains("withPropertyName('ignoreRules')");
    }

    @Test
    @DisplayName("EC2 부팅 스크립트 템플릿이 test 태스크의 입력으로 선언돼 있다")
    void bootstrapTemplates_areDeclaredAsTestInputs() {
        // Ec2BootstrapInstallsWhatComposeNeedsTest 가 user_data.sh.tftpl 을 읽는다(#601).
        // 부팅 스크립트의 실패는 그 서버 안 로그에만 남아서, 게이트가 조용히 꺼지면
        // 다음에 또 서버 안에 들어가 로그를 파야 한다.
        assertThat(buildGradle)
                .contains("dir: file('infra/terraform'), include: '**/*.tftpl'")
                .contains("withPropertyName('bootstrapTemplates')");
    }

    @Test
    @DisplayName("prod 바깥문(Caddyfile · docker-compose.prod.yml)이 test 태스크의 입력으로 선언돼 있다")
    void prodEdge_isDeclaredAsTestInput() {
        // CaddyIsTheOnlyDoorTest 가 Caddyfile 을, ComposeWaitsAndReportsHealthTest 가
        // 덧붙임을 읽는다(#609). 둘 다 지워도 에러가 안 나는 설정이라, 검사가 안 돌면
        // 지키는 것이 없어진다 — Caddy 의 X-Real-IP 가 빠지면 rate limit 이 무너진다(#613).
        assertThat(buildGradle)
                .contains("file('Caddyfile'), file('docker-compose.prod.yml')")
                .contains("withPropertyName('prodEdge')");
    }

    @Test
    @DisplayName("입력 선언에 경로 민감도가 지정돼 있다 — 절대 경로가 캐시 키에 섞이지 않는다")
    void inputs_useRelativePathSensitivity() {
        // 절대 경로가 캐시 키에 들어가면 다른 디렉터리에 클론한 순간 캐시가 전부 무효가 된다.
        // CI 러너는 매번 다른 경로를 쓴다.
        assertThat(buildGradle)
                .as("PathSensitivity.RELATIVE 가 없으면 빌드 캐시가 CI 에서 사실상 동작하지 않는다")
                .contains("withPathSensitivity(PathSensitivity.RELATIVE)");
    }

    @Test
    @DisplayName("빌드 캐시가 켜져 있고, 왜 그 값인지 근거가 gradle.properties 에 적혀 있다")
    void buildCache_isOnWithRecordedReason() throws IOException {
        String properties = Files.readString(
                TestProjectPaths.requireFile("gradle.properties"), StandardCharsets.UTF_8);

        assertThat(properties).contains("org.gradle.caching=true");
        assertThat(properties)
                .as("값만 있고 근거가 없으면 다음 사람이 지울 수도 유지할 수도 없다 (#4)")
                .contains("#");
    }
}
