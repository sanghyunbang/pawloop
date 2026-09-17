package com.heattrip.heat_trip_backend.place.layer;

import java.util.ArrayList;
import java.util.List;

/**
 * 동네 길의 <b>경유지 글</b>을 거쳐 가는 곳 목록으로 자른다 — 이슈 #619.
 *
 * <h2>왜 자르는가</h2>
 * <p>동네 길(#346)의 원본에는 선 좌표가 없다. 있는 것은 {@code 보신각 → 보성사 터 → 탑골공원}
 * 꼴의 <b>글 한 덩어리</b>다. 그 글을 그대로 한 줄에 흘리면 화면이 말줄임으로 자르고,
 * 사용자에게는 "화살표 화살표 있다가 끊긴" 문장이 된다 — {@link LocalTrailAsset#summaryOf}
 * 의 설명대로 실제로 그렇게 신고를 받고 카드에서 뺐던 자리다.
 *
 * <p>그래서 <b>한 줄로 흘리지 않고 조각으로 나눈다.</b> 나눠 두면 화면이 목록으로 그릴 수
 * 있고, 한 조각이 길어도 그 조각만 줄바꿈된다. 잘려서 뜻이 깨지는 일이 없다.
 *
 * <h2>구분자가 일곱 가지다 — 그래서 두 층으로 본다</h2>
 * <p>1,302개를 세어 보면 이렇다(2026-09-17).
 *
 * <pre>
 *   →  1008     -  208     ~  52     ,  48     &gt;  46     -&gt;  13     ∼  1
 * </pre>
 *
 * <p>{@code -} 를 늘 구분자로 보면 {@code K-55}(미군기지)나 {@code 한강하류-재두루미도래지}
 * 가 쪼개진다. 반대로 안 보면 {@code 속초등대전망대-영금정쉼터-장사항} 이 한 덩어리로 남는다.
 * 세어 보니 둘이 갈린다 — <b>{@code -} 가 든 208개 중 25개는 화살표를 함께 쓰고, 183개는
 * {@code -} 뿐이다.</b> 화살표를 쓰는 글에서 {@code -} 는 이름의 일부다.
 *
 * <p>그래서 규칙이 이것이다. <b>강한 구분자({@code →} {@code ->} {@code ~} {@code ∼}
 * {@code >})가 하나라도 있으면 그것만 쓰고, 하나도 없을 때만 약한 구분자({@code -}
 * {@code ,} {@code ·})까지 쓴다.</b>
 *
 * <h2>괄호 안은 자르지 않는다</h2>
 * <p>{@code 둘레길(연화산유원지~송이재입구~연화산유원지)} 는 괄호 안이 통째로 한 이름이다.
 * 깊이를 세지 않고 자르면 {@code 둘레길(연화산유원지} 와 {@code 연화산유원지)} 라는 <b>짝이
 * 깨진 조각</b>이 남는다. 전수로 재면 깊이를 안 세면 31개, 세면 3개다 — 남는 셋은
 * {@code 구)군산세관} 처럼 원본이 {@code 구(舊)} 를 그렇게 적은 것이라 자르기가 맞다.
 *
 * <h2>지어내지 않는다</h2>
 * <p>여기서 나온 이름들은 <b>좌표가 아니다.</b> 이것을 지오코딩해 이어 선을 그리면 실제로
 * 걷는 길이 아닌 직선이 그려지고, 사용자는 그 선을 믿고 걷는다. 없는 것보다 나쁘다 —
 * #619 에서 그 방법(A안)을 일부러 버렸다. 이름은 이름으로만 쓴다.
 */
final class LocalTrailWaypoints {

    /** 이것이 하나라도 있으면 이것만 쓴다. 긴 것을 먼저 봐야 {@code ->} 가 {@code -} 로 안 갈린다. */
    private static final String[] STRONG = {"->", "→", "∼", "~", ">"};

    /** 강한 구분자가 하나도 없을 때만 함께 쓴다. */
    private static final String[] WEAK = {",", "·", "—", "–", "-"};

    /** 조각이 이보다 많으면 버린다 — 원본 최대가 51 이라 닿지 않지만, 깨진 글을 막는 울타리다. */
    static final int MAX_STOPS = 80;

    private LocalTrailWaypoints() {
    }

    /**
     * 경유지 글을 거쳐 가는 곳 목록으로. 자를 것이 없으면 <b>통째로 한 조각</b>이고,
     * 글이 비었으면 빈 목록이다 (1,302개 중 20개가 한 조각으로 남는다).
     */
    static List<String> split(String raw) {
        if (raw == null || raw.isBlank()) {
            return List.of();
        }
        String[] seps = hasAny(raw, STRONG) ? STRONG : concat(STRONG, WEAK);

        List<String> stops = new ArrayList<>();
        StringBuilder buf = new StringBuilder();
        int depth = 0;
        int i = 0;
        while (i < raw.length()) {
            char c = raw.charAt(i);
            if (c == '(' || c == '[') {
                depth++;
                buf.append(c);
                i++;
                continue;
            }
            if (c == ')' || c == ']') {
                depth = Math.max(0, depth - 1);
                buf.append(c);
                i++;
                continue;
            }
            if (depth == 0) {
                String hit = matchAt(raw, i, seps);
                if (hit != null) {
                    add(stops, buf);
                    i += hit.length();
                    continue;
                }
            }
            buf.append(c);
            i++;
        }
        add(stops, buf);
        return stops.size() > MAX_STOPS ? List.copyOf(stops.subList(0, MAX_STOPS)) : List.copyOf(stops);
    }

    /** 괄호 <b>밖</b>에 이 구분자들 중 하나라도 있나. 안에 있는 것은 이름의 일부다. */
    private static boolean hasAny(String s, String[] seps) {
        int depth = 0;
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c == '(' || c == '[') {
                depth++;
            } else if (c == ')' || c == ']') {
                depth = Math.max(0, depth - 1);
            } else if (depth == 0 && matchAt(s, i, seps) != null) {
                return true;
            }
        }
        return false;
    }

    private static String matchAt(String s, int at, String[] seps) {
        for (String sep : seps) {
            if (s.startsWith(sep, at)) {
                return sep;
            }
        }
        return null;
    }

    private static void add(List<String> stops, StringBuilder buf) {
        String piece = buf.toString().strip();
        buf.setLength(0);
        if (!piece.isEmpty()) {
            stops.add(piece);
        }
    }

    private static String[] concat(String[] a, String[] b) {
        String[] out = new String[a.length + b.length];
        System.arraycopy(a, 0, out, 0, a.length);
        System.arraycopy(b, 0, out, a.length, b.length);
        return out;
    }
}
