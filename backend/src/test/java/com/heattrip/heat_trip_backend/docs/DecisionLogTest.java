package com.heattrip.heat_trip_backend.docs;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * ADR 로그({@code docs/99-decisions/decision-log.md})의 <b>인덱스와 본문이 서로 맞는지</b>
 * 잠근다 — 이슈 #15.
 *
 * <h2>무엇을 지키고 무엇을 못 지키는가</h2>
 * <p>문서의 <i>내용이 옳은가</i>는 테스트로 판정할 수 없다. ADR-0010 이 "Redis 를 지금 하지
 * 않는 이유" 를 설득력 있게 담았는지는 리뷰만이 거른다. 여기서 지키는 것은 그 아래 층이다 —
 * <b>인덱스 행 수와 본문 ADR 수가 같은가 · 각 행의 앵커가 실제 제목에서 생성되는 앵커와
 * 같은가 · 필수 4개 절이 있는가 · 하지 않기로 한 것이 대안으로 검토된 흔적이 있는가.</b>
 *
 * <p>사람 눈으로 보던 것을 옮긴 이유: 링크는 깨져도 렌더링이 실패하지 않는다. 앵커에 오타가
 * 나면 클릭했을 때 문서 맨 위로 갈 뿐이고, 그걸 알아채는 사람은 없다.
 *
 * <h2>앵커 규칙</h2>
 * <p>GitHub 는 제목을 소문자로 바꾸고, 글자·숫자·{@code _}·공백·{@code -} 를 뺀 나머지를
 * 지운 다음 공백을 {@code -} 로 바꾼다. 그래서 {@code ADR-0005 — Flutter 3.32 → 3.44}
 * 는 {@code adr-0005--flutter-332--344} 가 된다 — 점과 화살표는 사라지고, 지워진 em dash
 * 양옆의 공백 둘이 하이픈 둘로 남는다. 이 규칙을 {@link #githubAnchor(String)} 이 구현한다.
 *
 * <p>네트워크를 타지 않는다. 저장소 안의 파일만 읽는다.
 */
class DecisionLogTest {

    /** 인덱스 표의 한 행: {@code | [0009](#adr-0009--...) | 결정 | 상태 | 날짜 |} */
    private static final Pattern INDEX_ROW =
            Pattern.compile("(?m)^\\|\\s*\\[(\\d{4})\\]\\(#([^)]+)\\)\\s*\\|");

    /** 본문 ADR 제목: {@code ## ADR-0009 — 소셜 로그인에 PKCE 를 도입하지 않는다} */
    private static final Pattern ADR_HEADING =
            Pattern.compile("(?m)^## (ADR-(\\d{4})\\b.*)$");

    private static String log;

    @BeforeAll
    static void loadDecisionLog() {
        // 파일이 없으면 여기서 던진다. skip 이 아니다 (완료 조건 10).
        log = RepositoryDocs.requireDoc("99-decisions/decision-log.md");
    }

    // ─────────────────────────── A. 인덱스 ↔ 본문 정합 ───────────────────────────

    @Test
    @DisplayName("ADR 인덱스 행 수와 본문 ADR 제목 수가 같고 번호가 같은 순서로 이어진다")
    void index_coversEveryAdrExactlyOnce() {
        List<String> indexedNumbers = indexRows().stream().map(row -> row.number).toList();
        List<String> headingNumbers = headings().stream().map(heading -> heading.number).toList();

        assertThat(headingNumbers)
                .as("본문에 ADR 제목이 하나도 없다면 이 테스트는 아무것도 지키지 못한다")
                .isNotEmpty();
        assertThat(indexedNumbers)
                .as("인덱스에 없는 ADR 은 검색되지 않고, 본문에 없는 인덱스 행은 죽은 링크다")
                .containsExactlyElementsOf(headingNumbers);
    }

    @Test
    @DisplayName("인덱스 각 행의 앵커가 실제 제목에서 생성되는 앵커와 같다")
    void index_anchorsResolveToRealHeadings() {
        List<Heading> headings = headings();
        List<IndexRow> rows = indexRows();

        for (int i = 0; i < rows.size(); i++) {
            IndexRow row = rows.get(i);
            Heading heading = headings.get(i);

            assertThat(row.anchor)
                    .as("ADR-%s 인덱스 행의 앵커가 제목 '%s' 에서 생성되는 앵커와 다르다 — "
                            + "클릭하면 문서 맨 위로 간다 (완료 조건 9)", row.number, heading.text)
                    .isEqualTo(githubAnchor(heading.text));
        }
    }

    // ─────────────────────────── B. ADR-0010 ───────────────────────────

    @Test
    @DisplayName("ADR-0010 이 인덱스와 본문 양쪽에 있고 상태·날짜와 맥락·결정·대안·결과 4개 절을 갖춘다")
    void adr0010_existsWithTheRequiredSections() {
        assertThat(indexRows().stream().map(row -> row.number))
                .as("인덱스에 없으면 다음 사람이 이 결정을 검색으로 찾지 못한다 (완료 조건 1·9)")
                .contains("0010");

        String body = adrBody("0010");

        assertThat(body).as("상태가 없으면 이 결정이 아직 유효한지 알 수 없다").contains("- **상태**:");
        assertThat(body).as("날짜가 없으면 무엇이 먼저였는지 알 수 없다").contains("- **날짜**:");
        assertThat(body)
                .as("부록의 ADR 작성 규칙이 요구하는 4개 절이다")
                .contains("### 맥락", "### 결정", "### 대안", "### 결과");
    }

    @Test
    @DisplayName("ADR-0010 의 결정 절이 이 Epic 의 되돌리기 비싼 결정 다섯 개를 모두 담는다")
    void adr0010_recordsAllFiveDecisions() {
        String decision = section(adrBody("0010"), "### 결정");

        // 공급자 · JWT subject · RT 형태 · Redis · 딥링크 — 다섯 결정의 식별 문자열.
        assertThat(decision)
                .as("공급자 집합이 빠지면 로드맵의 '카카오/네이버' 가 왜 바뀌었는지 남지 않는다")
                .contains("카카오", "구글");
        assertThat(decision)
                .as("subject 를 email·소셜 ID 로 되돌리자는 제안이 다시 나온다")
                .contains("users.id");
        assertThat(decision)
                .as("'JWT 면 DB 없이 되는데 왜' 라는 질문이 반드시 나온다")
                .contains("불투명");
        assertThat(decision)
                .as("안 한 결정은 코드에 안 남는다 — 가장 잊히기 쉬운 항목이다")
                .contains("Redis");
        assertThat(decision)
                .as("딥링크에 토큰 대신 1회용 코드를 실은 대가를 왜 치렀는지")
                .contains("1회용 코드");
    }

    @Test
    @DisplayName("하지 않기로 한 것(네이버·Redis)이 대안으로 검토되고 이유가 남아 있다")
    void adr0010_explainsWhatItRefusedAndWhy() {
        String body = adrBody("0010");
        String alternatives = section(body, "### 대안");

        assertThat(alternatives)
                .as("네이버를 '지금 켠다' 가 대안으로 검토되지 않았다면 보류는 결정이 아니라 방치다 (완료 조건 2)")
                .contains("네이버");
        assertThat(alternatives)
                .as("Redis 를 '지금 넣는다' 가 대안으로 검토되지 않았다면 같은 논의가 반복된다 (완료 조건 2)")
                .contains("Redis");

        // "나중에" 는 이유가 아니다. 근거가 저장소의 사실에 걸려 있는지 본다.
        assertThat(body)
                .as("네이버 보류의 근거 — 앱은 #3 에서 이미 버튼을 내렸다는 실측이 사라지면 산문만 남는다")
                .contains("#3");
        assertThat(body)
                .as("Redis 보류의 근거 — 배포가 하나뿐이라 캐시가 아직 값을 못 한다는 사실")
                .contains("단일 인스턴스");
        assertThat(body)
                .as("카카오 이메일 null 문제(#7)가 subject 결정의 근거다")
                .contains("#7");
        assertThat(body)
                .as("재사용 감지에 영속 원장이 필요하다는 것이 RT 결정의 근거다(#9)")
                .contains("#9");
    }

    @Test
    @DisplayName("PKCE 판단은 ADR-0009 가 소유하고 ADR-0010 은 링크만 건다")
    void adr0010_defersPkceToAdr0009() {
        // #14 가 이미 ADR-0009 로 썼다. 여기에 두 번째 판본을 만들면 계약 두 곳
        // (openapi.yaml·api-spec.md)이 거는 링크와 어긋난다.
        assertThat(adrBody("0010"))
                .as("같은 결정을 두 번 쓰지 않는다 — 상호 링크로 잇는다")
                .contains("ADR-0009");
        assertThat(adrBody("0009"))
                .as("ADR-0009 는 #14 의 결정이다. 이 이슈가 덮어쓰면 계약의 링크가 깨진다")
                .contains("PKCE");
    }

    // ─────────────────────────── 파싱 유틸 ───────────────────────────

    private record IndexRow(String number, String anchor) {
    }

    private record Heading(String number, String text) {
    }

    private static List<IndexRow> indexRows() {
        List<IndexRow> rows = new ArrayList<>();
        Matcher matcher = INDEX_ROW.matcher(log);
        while (matcher.find()) {
            rows.add(new IndexRow(matcher.group(1), matcher.group(2)));
        }
        assertThat(rows).as("인덱스 표를 한 행도 못 읽었다면 이 테스트는 아무것도 지키지 못한다").isNotEmpty();
        return rows;
    }

    private static List<Heading> headings() {
        List<Heading> headings = new ArrayList<>();
        Matcher matcher = ADR_HEADING.matcher(log);
        while (matcher.find()) {
            headings.add(new Heading(matcher.group(2), matcher.group(1)));
        }
        return headings;
    }

    /** {@code ## ADR-XXXX} 제목부터 다음 {@code ## } 제목 직전까지. */
    private static String adrBody(String number) {
        Matcher matcher = ADR_HEADING.matcher(log);
        while (matcher.find()) {
            if (!matcher.group(2).equals(number)) {
                continue;
            }
            int start = matcher.start();
            int next = log.indexOf("\n## ", start + 1);
            return (next < 0) ? log.substring(start) : log.substring(start, next);
        }
        throw new AssertionError("ADR-" + number + " 본문을 찾지 못했다 — 제목이 '## ADR-"
                + number + " — …' 형태여야 한다.");
    }

    /** ADR 본문 안에서 {@code ### 결정} 같은 한 절만 잘라낸다. */
    private static String section(String adrBody, String heading) {
        int start = adrBody.indexOf(heading);
        assertThat(start).as("'%s' 절이 없다", heading).isNotNegative();
        int next = adrBody.indexOf("\n### ", start + 1);
        return (next < 0) ? adrBody.substring(start) : adrBody.substring(start, next);
    }

    /**
     * GitHub 이 마크다운 제목에서 만드는 앵커.
     *
     * <p>소문자화 → 글자·숫자·결합기호·{@code _}·공백·{@code -} 외 전부 제거 → 공백을
     * {@code -} 로. 한글은 그대로 남는다(그래서 기존 앵커가 한글이다).
     */
    private static String githubAnchor(String heading) {
        return heading.toLowerCase(Locale.ROOT)
                .replaceAll("[^\\p{L}\\p{N}\\p{M}_ -]", "")
                .replace(' ', '-');
    }
}
