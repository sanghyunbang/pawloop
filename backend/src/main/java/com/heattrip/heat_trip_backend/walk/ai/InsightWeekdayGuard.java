package com.heattrip.heat_trip_backend.walk.ai;

import java.util.LinkedHashSet;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 모델이 낸 문장이 <b>산책하지 않은 요일</b>을 말하는지 본다 — 이슈 #543.
 *
 * <h2>왜 숫자 검사로는 안 잡혔나</h2>
 *
 * <p>{@link InsightNumberGuard} 는 숫자만 본다. 이런 문장이 그대로 통과했다.
 *
 * <pre>
 * 입력: - 요일별 km: 월 0, 화 1.9, 수 0, 목 0, 금 0, 토 0, 일 0
 * 출력: 이번 주는 월·화에 낮 산책 3회로 1.9km, 2분을 기록했어요.
 * </pre>
 *
 * <p>숫자(3 · 1.9 · 2)는 전부 입력에 있다. 틀린 것은 <b>요일 이름</b>이고, 그건 검사 밖이었다.
 * 숫자가 맞아도 "언제 걸었는지" 가 틀리면 같은 종류의 거짓말이다 — 게다가 사용자는 자기가 언제
 * 걸었는지 안다. 틀린 요일 하나가 나머지 문장의 신뢰를 같이 깎는다.
 *
 * <h2>무엇을 요일로 보나</h2>
 *
 * <p>한국어의 요일 한 글자는 보통 낱말과 심하게 겹친다 — 횟<b>수</b> · <b>목</b>표 · 3<b>일</b> ·
 * <b>금</b>방. 그래서 "그 글자가 있으면 요일" 로 보지 않고 <b>두 가지 모양</b>만 요일로 읽는다.
 *
 * <ol>
 *   <li>{@code 월요일} — 글자 뒤에 곧바로 "요일" 이 붙은 것
 *   <li>{@code 월·화} · {@code 월, 화} · {@code 화~목} · {@code 수와 목} — 요일 글자끼리
 *       이음말로 이어진 <b>줄</b>. 줄 안의 글자는 전부 요일로 센다
 * </ol>
 *
 * <p>줄 안이라도 <b>앞 글자가 숫자면</b> 세지 않는다 — {@code 3일과 월요일} 의 "일" 은 날수다.
 *
 * <h2>왜 제안까지 막나</h2>
 *
 * <p>"금 · 토 · 일에 한 번 더 나가볼까요" 는 참말인데도 막힌다. 그래서 프롬프트가 먼저
 * <b>"요일은 데이터의 요일별 km 가 0 이 아닌 것만 말한다"</b> 고 시킨다 — 모델은 "주말에" ·
 * "남은 날에" 로 쓸 수 있다. 시킨 뒤에 막는 것이라, 걸리는 문장은 모델이 어긴 문장이다.
 *
 * <h2>시간대(새벽 · 아침 · 낮 · 저녁)는 왜 여기 없나</h2>
 *
 * <p>같은 모양으로 막을 수 있지만 안 막는다. 카드의 <b>셋째 줄은 제안</b>이고, 제안은 0회인
 * 시간대를 말하는 것이 정상이다 — "저녁에 한 번 더 나가볼까요" 가 그렇다. 요일과 달리 여기서는
 * 막는 쪽이 더 많이 틀린다. 시간대는 프롬프트 규칙으로만 둔다.
 */
public final class InsightWeekdayGuard {

    /** 입력의 {@code - 요일별 km: 월 0, 화 1.9, ...} 줄. */
    private static final Pattern WEEK_LINE = Pattern.compile("요일별 km:([^\\n]*)");

    /** 그 줄 안의 {@code 월 0} 짝. */
    private static final Pattern DAY_VALUE = Pattern.compile("([월화수목금토일])\\s+(\\d+(?:\\.\\d+)?)");

    /** {@code 월요일}. */
    private static final Pattern NAMED = Pattern.compile("([월화수목금토일])요일");

    /** {@code 월·화} · {@code 수와 목} — 요일 글자 둘 이상이 이음말로 이어진 줄. */
    private static final Pattern RUN = Pattern.compile(
            "[월화수목금토일](?:\\s*[·,/~∙‧・]\\s*[월화수목금토일])+");

    /** 요일 일곱. */
    private static final String DAYS = "월화수목금토일";

    /**
     * 요일 뒤에 붙어도 되는 조사. 이 밖의 한글이 붙어 있으면 요일이 아니라 낱말의 일부다.
     *
     * <p>닫힌 목록이라 빠진 조사가 있으면 그 문장은 <b>통과</b>한다 — 못 잡는 쪽으로 틀린다.
     * 반대로 열어 두면 "목표" 를 목요일로 읽어 멀쩡한 문장을 버린다.
     */
    private static final Set<String> PARTICLES = Set.of(
            "에", "에는", "에도", "에만", "은", "는", "이", "가", "을", "를",
            "와", "과", "도", "만", "나", "이나", "랑", "이랑", "부터", "까지", "요", "로", "으로");

    private InsightWeekdayGuard() {
    }

    /**
     * 출력이 말한 요일이 전부 이번 주에 걸은 요일이면 true.
     *
     * <p>요일을 아예 안 말하는 문장도 true 다. 입력에 요일별 줄이 <b>없으면</b> 요일을 말하는
     * 문장은 전부 false 다 — 근거 없이 요일을 말한 것이니 같은 판정이다.
     */
    public static boolean allowed(String output, String input) {
        Set<Character> mentioned = weekdaysIn(output);
        if (mentioned.isEmpty()) {
            return true;
        }
        Set<Character> walked = walkedDaysIn(input);
        return walked.containsAll(mentioned);
    }

    /** 문장이 말한 요일 글자들 — 위의 두 모양만. */
    static Set<Character> weekdaysIn(String text) {
        Set<Character> out = new LinkedHashSet<>();
        if (text == null) {
            return out;
        }
        Matcher named = NAMED.matcher(text);
        while (named.find()) {
            if (boundedLeft(text, named.start())) {
                out.add(named.group(1).charAt(0));
            }
        }
        Matcher run = RUN.matcher(text);
        while (run.find()) {
            if (!boundedLeft(text, run.start()) || !boundedRight(text, run.end())) {
                continue;
            }
            for (int i = run.start(); i < run.end(); i++) {
                char c = text.charAt(i);
                if (DAYS.indexOf(c) >= 0) {
                    out.add(c);
                }
            }
        }
        return out;
    }

    /**
     * 앞 테두리 — 요일 글자(또는 요일 줄) 바로 앞이 <b>한글 음절이나 숫자면 요일이 아니다.</b>
     *
     * <p>횟<b>수</b> · 3<b>일</b> 이 그렇다. 앞 글자가 붙어 있으면 그 글자는 다른 낱말의 일부다.
     */
    private static boolean boundedLeft(String text, int start) {
        if (start == 0) {
            return true;
        }
        char before = text.charAt(start - 1);
        return !isHangulSyllable(before) && !Character.isDigit(before);
    }

    /**
     * 뒤 테두리 — 요일 줄 바로 뒤에 붙은 한글은 <b>조사여야 한다.</b>
     *
     * <p><b>목</b>표 는 요일이 아니고 {@code 월·화에} 의 "에" 는 조사다. 조사 목록 밖의 한글이
     * 붙어 있으면 그 글자는 다른 낱말의 일부다.
     */
    private static boolean boundedRight(String text, int end) {
        int i = end;
        while (i < text.length() && isHangulSyllable(text.charAt(i))) {
            i++;
        }
        return i == end || PARTICLES.contains(text.substring(end, i));
    }

    /** 한글 음절(가~힣). 자모 하나만 쓰이는 일은 이 글에 없다. */
    private static boolean isHangulSyllable(char c) {
        return c >= 0xAC00 && c <= 0xD7A3;
    }

    /** 입력의 요일별 줄에서 km 가 0 이 아닌 요일들. 줄이 없으면 빈 집합이다. */
    static Set<Character> walkedDaysIn(String input) {
        Set<Character> out = new LinkedHashSet<>();
        if (input == null) {
            return out;
        }
        Matcher line = WEEK_LINE.matcher(input);
        if (!line.find()) {
            return out;
        }
        Matcher pair = DAY_VALUE.matcher(line.group(1));
        while (pair.find()) {
            if (Double.parseDouble(pair.group(2)) > 0) {
                out.add(pair.group(1).charAt(0));
            }
        }
        return out;
    }
}
