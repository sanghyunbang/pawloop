package com.heattrip.heat_trip_backend.walk.ai;

import java.math.BigDecimal;
import java.util.HashSet;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 모델이 낸 문장의 숫자가 전부 입력에 있던 숫자인지 본다 — 이슈 #486.
 *
 * <p>LLM 은 말만 만들고 숫자는 1단계(규칙)가 만든 것만 쓴다. 출력에 입력에 없는 숫자가 하나라도
 * 있으면 그 문장은 <b>통째로 폐기</b>한다 — "3.2km" 를 "5km" 로 지어내는 순간이 정확히 여기다.
 *
 * <p>비교는 값으로 한다({@code 3.0} 과 {@code 3} 은 같다). 단위나 조사는 보지 않는다 — "3회" 든
 * "3km" 든 3 이 입력에 있으면 통과다. 그래서 "7시" 같은 시각도 7 이 입력에 없으면 막힌다 —
 * 입력에는 시간대만 있지 시각은 없으니 맞는 판정이다.
 */
public final class InsightNumberGuard {

    private static final Pattern NUMBER = Pattern.compile("\\d+(?:[.,]\\d+)?");

    private InsightNumberGuard() {
    }

    /** 출력의 모든 숫자가 입력에 있으면 true. 숫자가 하나도 없는 출력도 true 다. */
    public static boolean allowed(String output, String input) {
        Set<BigDecimal> allowed = numbersIn(input);
        for (BigDecimal n : numbersIn(output)) {
            if (!allowed.contains(n)) {
                return false;
            }
        }
        return true;
    }

    /** 문장 속 숫자들 — 값으로 정규화한 집합. "1,200" 같은 천 단위 쉼표는 소수점으로 읽지 않는다. */
    static Set<BigDecimal> numbersIn(String text) {
        Set<BigDecimal> out = new HashSet<>();
        if (text == null) {
            return out;
        }
        Matcher m = NUMBER.matcher(text);
        while (m.find()) {
            String token = m.group();
            if (token.contains(",")) {
                String[] parts = token.split(",");
                // "1,200" 은 천 단위, "3,2" 는 유럽식 소수 — 뒤가 세 자리면 천 단위로 본다.
                token = parts[1].length() == 3 ? parts[0] + parts[1] : parts[0] + "." + parts[1];
            }
            out.add(new BigDecimal(token).stripTrailingZeros());
        }
        return out;
    }
}
