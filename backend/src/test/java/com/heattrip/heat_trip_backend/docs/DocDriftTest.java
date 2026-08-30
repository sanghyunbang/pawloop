package com.heattrip.heat_trip_backend.docs;

import java.util.List;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 로드맵·구현현황·ERD·스키마 문서가 <b>지금의 코드</b>와 어긋난 채 남아 있는지 본다 — 이슈 #15.
 *
 * <h2>⚠️ 순진한 grep 이 오탐을 낸다 — 여기가 이 테스트의 핵심이다</h2>
 * <p>{@code docs/05-build/implementation-status.md} 에는 "네이버" 가 여러 번 나오는데
 * <b>전부 지도 SDK</b>({@code flutter_naver_map}) 이야기다 — 소셜 로그인과 무관하다.
 *
 * <pre>
 *   :34 네이버맵 마커·바텀시트          :35 네이버맵 위 경로 폴리라인
 *   :64 flutter_naver_map. Client ID   :99 flutter_naver_map (pubspec ^1.3.1)
 * </pre>
 *
 * <p>그래서 "네이버" 를 그냥 금지하면 <b>지도 SDK 때문에 영원히 빨간불</b>이고, 그 테스트는
 * 며칠 안에 지워진다. 검사는 <b>소셜 로그인 문맥</b>으로 한정한다 —
 * {@link #SOCIAL_CONTEXT} 를 함께 가진 줄만 보고, {@link #MAP_CONTEXT} 가 있으면 뺀다.
 * 지도 SDK 를 쓰는 한 이 예외는 사라지지 않는다. 지우지 말 것.
 *
 * <p>"네이버는 보류다" 같은 <b>결정 서술</b>도 통과시킨다({@link #DECISION_NOTE}). 그건
 * 지워야 할 거짓이 아니라 남겨야 할 맥락이다 — ADR-0010 이 그렇게 적으라고 했다.
 *
 * <p>네트워크를 타지 않는다. 저장소 안의 파일만 읽는다.
 */
class DocDriftTest {

    /** 이 줄이 소셜 로그인 이야기인지 가르는 낱말. */
    private static final List<String> SOCIAL_CONTEXT =
            List.of("로그인", "소셜", "oauth", "공급자", "provider", "카카오", "kakao", "구글", "google");

    /** 지도 SDK 이야기라 소셜 로그인 검사 대상이 아닌 줄. */
    private static final List<String> MAP_CONTEXT =
            List.of("지도", "맵", "map", "sdk", "폴리라인", "마커", "client id", "좌표");

    /** 네이버를 "보류/제외" 로 서술하는 줄. 이건 남아 있어야 하는 문장이다. */
    private static final List<String> DECISION_NOTE =
            List.of("보류", "adr-0010", "예전", "내렸", "걷어냈", "제외");

    private static String roadmap;
    private static String implementationStatus;
    private static String schema;
    private static String erd;

    @BeforeAll
    static void loadDocs() {
        // 하나라도 없으면 여기서 던진다. skip 이 아니다 (완료 조건 10).
        roadmap = RepositoryDocs.requireDoc("05-build/roadmap.md");
        implementationStatus = RepositoryDocs.requireDoc("05-build/implementation-status.md");
        schema = RepositoryDocs.requireDoc("03-database/schema.md");
        erd = RepositoryDocs.requireDoc("03-database/erd.md");
    }

    // ─────────────────────────── A. 공급자 서술 ───────────────────────────

    @Test
    @DisplayName("로드맵의 소셜 로그인 서술에 네이버가 공급자로 남아 있지 않다")
    void roadmap_noLongerAdvertisesNaverAsAProvider() {
        assertThat(socialLoginNaverLines(roadmap))
                .as("M2 는 카카오·구글이다(ADR-0010). 로드맵이 셋을 광고하면 되돌리는 논의가 반복된다")
                .isEmpty();
    }

    @Test
    @DisplayName("로드맵 M2 가 실제 구현 공급자(카카오·구글)를 말한다")
    void roadmap_namesTheProvidersWeActuallyShip() {
        // 네이버만 지우고 구글을 안 적으면 "공급자가 하나" 로 읽힌다. 지운 자리를 채웠는지 본다.
        String m2 = section(roadmap, "## M2 — 로그인");
        assertThat(m2).contains("카카오");
        assertThat(m2).contains("구글");
    }

    @Test
    @DisplayName("구현현황의 소셜 로그인 서술에 네이버가 남아 있지 않다 — 지도 SDK 언급은 그대로 둔다")
    void implementationStatus_socialLoginMentionsAreProviderAccurate() {
        assertThat(socialLoginNaverLines(implementationStatus))
                .as("여기서 걸린 줄이 지도 SDK 이야기라면 MAP_CONTEXT 를 넓혀라 — 문서를 고칠 일이 아니다")
                .isEmpty();

        // 오탐 방지 장치가 살아 있는지 스스로 확인한다. 지도 SDK 줄은 여전히 문서에 있어야 하고,
        // 그 줄들이 이 검사에 걸리지 않아야 한다.
        assertThat(implementationStatus)
                .as("지도 SDK 언급까지 지워 버리면 이 테스트의 오탐 방지 장치가 검증되지 않는다")
                .contains("flutter_naver_map");
    }

    @Test
    @DisplayName("구현현황의 로그인 항목이 더 이상 '미구현' 이 아니다")
    void implementationStatus_loginIsNoLongerMarkedUnimplemented() {
        // #11·#12·#14 가 앱 로그인 화면·상태 머신·1회용 코드 교환을 실었다.
        // "❌ 미구현" 이 남으면 다음 사람이 이미 있는 것을 또 만든다.
        assertThat(loginRows(implementationStatus))
                .as("로그인 항목을 한 줄도 못 찾았다면 이 검사는 아무것도 지키지 못한다")
                .isNotEmpty();
        assertThat(loginRows(implementationStatus))
                .as("로그인은 구현됐다 — 미구현 표기가 남으면 로드맵과 현황이 서로 다른 말을 한다")
                .noneMatch(line -> line.contains("❌ 미구현"));
    }

    // ─────────────────────────── B. users / refresh_token ───────────────────────────

    @Test
    @DisplayName("스키마 문서가 실제 테이블 users 를 정의하고 app_user 라는 이름은 남기지 않는다")
    void schema_definesTheRealUsersTable() {
        assertThat(schema)
                .as("실제 테이블은 users 다 — @Table(name=\"users\"), backend/mysql/init/01_schema.sql")
                .contains("CREATE TABLE users (");
        assertThat(schema)
                .as("app_user 는 피벗 당시의 계획 이름이다. 각주로만 남고 정의로 남으면 안 된다")
                .doesNotContain("CREATE TABLE app_user");
        assertThat(schema)
                .as("FK 가 없는 테이블을 가리키면 이 문서만 보고 만든 DDL 이 실행되지 않는다")
                .doesNotContain("REFERENCES app_user");
    }

    @Test
    @DisplayName("users 정의에 provider·social_id·role 이 있고 email 은 nullable 이다")
    void schema_usersCarriesTheSocialAccountColumns() {
        String users = createTable(schema, "users");

        assertThat(users)
                .as("소셜 계정의 식별 키는 (provider, social_id) 다. 이메일이 아니다 (#7)")
                .contains("provider", "social_id");
        assertThat(users)
                .as("role 은 #7 이 추가한 컬럼이고 토큰 발급이 이 값을 쓴다")
                .contains("role");
        assertThat(users)
                .as("uk_users_provider_social_id 가 '한 소셜 계정 = 한 행' 을 DB 수준에서 보증한다")
                .containsIgnoringCase("provider, social_id");

        // 카카오 account_email 은 선택 동의라서 이메일 없는 가입이 성공해야 한다 (#7 완료 조건 1).
        assertThat(emailColumnLine(users))
                .as("email 을 NOT NULL 로 적으면 이 문서만 보고 만든 DB 는 카카오 가입을 거절한다")
                .doesNotContain("NOT NULL");
    }

    @Test
    @DisplayName("스키마 문서에 refresh_token 테이블이 있다 — #9 가 만든 원장이다")
    void schema_documentsTheRefreshTokenLedger() {
        assertThat(schema).contains("CREATE TABLE refresh_token (");

        String refreshToken = createTable(schema, "refresh_token");
        assertThat(refreshToken)
                .as("RT 는 원문이 아니라 SHA-256 해시로 저장된다")
                .contains("token_hash");
        assertThat(refreshToken)
                .as("폐기는 삭제가 아니다 — revoked_at 이 없으면 재사용 감지가 무력해진다 (#9)")
                .contains("revoked_at");
        assertThat(refreshToken).contains("expires_at");
    }

    @Test
    @DisplayName("ERD 가 users 엔티티를 그리고 refresh_token 을 포함한다")
    void erd_drawsUsersAndTheRefreshTokenLedger() {
        assertThat(erd)
                .as("ERD 의 엔티티 이름이 실제 테이블과 다르면 그림을 보고 만든 쿼리가 전부 틀린다")
                .doesNotContain("app_user");
        assertThat(erd).contains("users {");
        assertThat(erd)
                .as("#9 가 만든 테이블이 ERD 에 없으면 인증 데이터 모델이 그림에서 통째로 빠진다")
                .contains("refresh_token {");

        String users = mermaidEntity(erd, "users");
        assertThat(users).contains("provider", "social_id", "role", "email");
    }

    // ─────────────────────────── 스캐너·파싱 유틸 ───────────────────────────

    /**
     * "소셜 로그인 공급자로서의 네이버" 를 말하는 줄만 골라낸다.
     *
     * <p>지도 SDK 줄({@code flutter_naver_map}·네이버맵)과 보류를 서술하는 줄은 뺀다.
     * 이 두 예외가 이 스캐너의 존재 이유다 — 위 클래스 주석 참조.
     */
    private static List<String> socialLoginNaverLines(String document) {
        return document.lines()
                .filter(line -> {
                    String lower = line.toLowerCase(Locale.ROOT);
                    if (!lower.contains("네이버") && !lower.contains("naver")) {
                        return false;
                    }
                    if (MAP_CONTEXT.stream().anyMatch(lower::contains)) {
                        return false;
                    }
                    if (DECISION_NOTE.stream().anyMatch(lower::contains)) {
                        return false;
                    }
                    return SOCIAL_CONTEXT.stream().anyMatch(lower::contains);
                })
                .toList();
    }

    /** 표에서 "로그인" 을 항목명으로 쓰는 행들. */
    private static List<String> loginRows(String document) {
        return document.lines()
                .filter(line -> line.startsWith("|"))
                .filter(line -> line.contains("로그인"))
                .toList();
    }

    /** {@code ## 제목} 부터 다음 {@code ## } 직전까지. */
    private static String section(String document, String headingPrefix) {
        int start = document.indexOf(headingPrefix);
        assertThat(start).as("'%s' 절을 찾지 못했다 — 제목이 바뀌었다면 이 테스트도 함께 고쳐라", headingPrefix)
                .isNotNegative();
        int next = document.indexOf("\n## ", start + 1);
        return (next < 0) ? document.substring(start) : document.substring(start, next);
    }

    /** {@code CREATE TABLE <name> (} 부터 짝이 되는 {@code );} 까지. */
    private static String createTable(String document, String table) {
        String opening = "CREATE TABLE " + table + " (";
        int start = document.indexOf(opening);
        assertThat(start).as("%s 의 CREATE TABLE 을 찾지 못했다", table).isNotNegative();
        int end = document.indexOf("\n)", start);
        assertThat(end).as("%s 의 CREATE TABLE 이 닫히지 않았다", table).isNotNegative();
        return document.substring(start, end);
    }

    /** mermaid {@code erDiagram} 의 {@code <name> { … }} 블록. */
    private static String mermaidEntity(String document, String entity) {
        Matcher matcher = Pattern.compile("(?m)^\\s*" + Pattern.quote(entity) + "\\s*\\{")
                .matcher(document);
        assertThat(matcher.find()).as("ERD 에 %s 엔티티 블록이 없다", entity).isTrue();
        int end = document.indexOf("\n    }", matcher.start());
        assertThat(end).as("%s 엔티티 블록이 닫히지 않았다", entity).isNotNegative();
        return document.substring(matcher.start(), end);
    }

    /** users DDL 안에서 email 컬럼을 선언한 줄. */
    private static String emailColumnLine(String createTableBody) {
        return createTableBody.lines()
                .filter(line -> line.trim().startsWith("email"))
                .findFirst()
                .orElseThrow(() -> new AssertionError(
                        "users 정의에 email 컬럼 줄이 없다 — nullable 여부를 확인할 수 없다"));
    }
}
