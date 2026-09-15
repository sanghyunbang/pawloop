package com.heattrip.heat_trip_backend.support;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 자바 소스에서 <b>쿼리 문자열</b>을 뽑고, 그 안의 <b>표·엔티티 이름</b>을 찾는다.
 *
 * <h2>왜 이 자리가 따로 있는가</h2>
 * <p>원래 {@code ChatBoundaryArchitectureTest} 안의 private 헬퍼였다(§C, #75). 그 검사는
 * <b>chat 모양</b>이었다 — 표 접두사 하나({@code chat_})와 chat 엔티티 이름 집합을 전제로 한다.
 * 같은 눈을 다른 모듈에도 쓰려면 그 전제를 밖으로 빼야 한다(#518 §2).
 *
 * <p><b>"밖인가" 를 여기서 판단하지 않는다.</b> 이 클래스는 <b>이름을 꺼내 주기만</b> 하고,
 * 그것이 경계 밖인지는 부르는 쪽의 규칙이다 — chat 은 "0 이어야 한다" 는 게이트이고
 * 나머지 모듈은 "지금 이만큼" 이라는 기준선이라, 판단이 서로 다르기 때문이다.
 *
 * <h2>JPQL 도 네이티브도 문자열이다</h2>
 * <p>JPQL 은 엔티티 이름을, 네이티브는 표 이름을 <b>문자열로</b> 쓴다 — import 도 필드도 아니라
 * 바이트코드를 보는 검사(ArchUnit · Modulith)에는 안 걸린다. FK 가 없어도 조인 하나면 경계가
 * 사라지고, 되돌리려 할 때는 이미 쿼리가 여럿이다.
 */
public final class QueryScanner {

    private QueryScanner() {
    }

    // ── 쿼리 문자열 뽑기 ──

    /** 텍스트 블록. 먼저 떼어 내야 아래 일반 문자열 정규식이 헷갈리지 않는다. */
    private static final Pattern TEXT_BLOCK = Pattern.compile("(?s)\"\"\"(.*?)\"\"\"");

    /** 한 줄짜리 문자열 리터럴. 이스케이프된 따옴표를 넘어간다. */
    private static final Pattern STRING_LITERAL = Pattern.compile("\"((?:\\\\.|[^\"\\\\])*)\"");

    /** {@code "a" + "b"} 를 잇는다. 안 이으면 FROM 과 표 이름이 갈라져 아무것도 못 잡는다. */
    private static final Pattern CONCATENATION = Pattern.compile("\"\\s*\\+\\s*\"");

    /** 쿼리로 볼 문자열 — 동사와 절이 함께 있어야 한다. 산문 메시지를 훑지 않으려는 것이다. */
    private static final Pattern LOOKS_LIKE_A_QUERY = Pattern.compile(
            "(?is)^(?=.*\\b(select|insert|update|delete)\\b)(?=.*\\b(from|join|into|set)\\b).*$");

    /**
     * 소스에서 <b>쿼리로 보이는</b> 문자열만 뽑는다.
     *
     * <p>주석은 부르는 쪽이 {@link #stripComments} 로 먼저 걷는다. 이어 붙인 문자열을 잇고,
     * 텍스트 블록도 함께 본다 — {@code @Query} 뿐 아니라 {@code createNativeQuery("…")} 도
     * 같은 그물에 들어온다.
     */
    public static List<String> queryLiteralsIn(String source) {
        List<String> out = new ArrayList<>();

        Matcher blocks = TEXT_BLOCK.matcher(source);
        StringBuilder withoutBlocks = new StringBuilder();
        int last = 0;
        while (blocks.find()) {
            withoutBlocks.append(source, last, blocks.start());
            collectIfQuery(blocks.group(1), out);
            last = blocks.end();
        }
        withoutBlocks.append(source.substring(last));

        Matcher literals = STRING_LITERAL.matcher(
                CONCATENATION.matcher(withoutBlocks).replaceAll(""));
        while (literals.find()) {
            collectIfQuery(literals.group(1), out);
        }
        return out;
    }

    private static void collectIfQuery(String candidate, List<String> out) {
        String flattened = candidate.replaceAll("\\s+", " ").strip();
        if (LOOKS_LIKE_A_QUERY.matcher(flattened).matches()) {
            out.add(flattened);
        }
    }

    // ── 쿼리 안의 표·엔티티 이름 ──

    /** {@code FROM}·{@code JOIN}·{@code UPDATE}·{@code INSERT INTO} 뒤의 이름과 그 별칭. */
    private static final Pattern TABLE_POSITION = Pattern.compile(
            "(?is)\\b(?:from|join|update|insert\\s+into)\\s+"
                    + "([A-Za-z_][\\w$]*(?:\\.[A-Za-z_][\\w$]*)*)"
                    + "(?:\\s+(?:as\\s+)?([A-Za-z_][\\w$]*))?");

    /** 별칭 자리에 올 수 있는 예약어. 이것들을 별칭으로 오해하면 경로식 검사가 헐거워진다. */
    private static final Set<String> CLAUSE_KEYWORDS = Set.of(
            "on", "where", "join", "inner", "left", "right", "outer", "cross", "full",
            "group", "order", "having", "limit", "offset", "set", "values", "union",
            "and", "or", "as", "using", "fetch", "select", "from", "into");

    /**
     * 쿼리가 <b>표 자리에서 부르는 이름</b>들. 별칭으로 시작하는 경로식은 뺀다.
     *
     * <ul>
     *   <li>{@code FROM chat_room r} → {@code chat_room}</li>
     *   <li>{@code join m.room r} → <b>없음</b>. 별칭으로 시작하는 경로식은 그 별칭이 가리키는
     *       엔티티의 필드라, 무엇을 가리키는지는 매핑이 정한다(chat 은 §A 가 리플렉션으로 잠근다).</li>
     *   <li>{@code FROM heat_trip.users} → {@code heat_trip.users}. 스키마를 앞에 붙인 것은
     *       별칭 경로식이 아니므로 그대로 돌려준다 — 부르는 쪽이 판단한다.</li>
     * </ul>
     */
    public static List<String> tableReferencesIn(String query) {
        String normalized = query
                .replaceAll("(?i)\\bon\\s+duplicate\\s+key\\s+update\\b", "on duplicate key")
                .replaceAll("(?i)\\bjoin\\s+fetch\\b", "join");

        Set<String> aliases = new LinkedHashSet<>();
        Matcher aliasScan = TABLE_POSITION.matcher(normalized);
        while (aliasScan.find()) {
            String alias = aliasScan.group(2);
            if (alias != null && !CLAUSE_KEYWORDS.contains(alias.toLowerCase())) {
                aliases.add(alias);
            }
        }

        List<String> names = new ArrayList<>();
        Matcher targets = TABLE_POSITION.matcher(normalized);
        while (targets.find()) {
            String name = targets.group(1);
            if (CLAUSE_KEYWORDS.contains(name.toLowerCase())) {
                continue;
            }
            if (name.contains(".") && aliases.contains(name.substring(0, name.indexOf('.')))) {
                continue;
            }
            names.add(name);
        }
        return names;
    }

    /**
     * 주석을 걷는다 — 주석 속 예시 문구가 검사에 걸리면 그 테스트는 며칠 안에 지워진다.
     *
     * <p>줄 수는 그대로 둔다. 위반을 파일:줄 로 가리켜야 고칠 자리를 찾는다.
     */
    public static String stripComments(String source) {
        Matcher m = Pattern.compile("(?s)/\\*.*?\\*/|//[^\\n]*").matcher(source);
        StringBuilder out = new StringBuilder(source.length());
        int last = 0;
        while (m.find()) {
            out.append(source, last, m.start());
            out.append("\n".repeat((int) m.group().chars().filter(c -> c == '\n').count()));
            last = m.end();
        }
        return out.append(source.substring(last)).toString();
    }
}
