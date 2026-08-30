package com.heattrip.heat_trip_backend.observability.logging;

import org.springframework.stereotype.Component;

import java.util.regex.Pattern;

/**
 * 로그·알림으로 나가는 문자열에서 <b>비밀값을 가린다</b>.
 *
 * <h2>초대코드도 비밀값이다 (이슈 #75)</h2>
 * <p>{@code InviteCodeGenerator} 의 javadoc 이 초대코드를 "인증 없이 방에 들어오는 유일한
 * 열쇠" 라고 부른다. 그런데 그 값이 <b>경로에 실려</b> 서버 로그·오류 로그·Slack 알림에
 * 평문으로 찍히고 있었다 — 실제로 찍힌 줄 셋:
 * <pre>
 *   [REQ] POST /api/chat/invites/Y9VAQ-VV852/join failed in 43ms: ...
 *   [ALERT] slack send skipped/failed for POST /api/chat/invites/Y9VAQ-VV852/join
 *   처리되지 않은 예외 — uri=/api/chat/invites/KH24R-JZBXC/join ...
 * </pre>
 * <p>로그·알림 채널에 접근할 수 있는 사람은 계정 하나만 있으면 남의 가족방에 들어갈 수 있다.
 * 이 저장소는 #6 에서 refresh 토큰·이메일이 응답과 로그로 새는 것을 통째로 걷어낸 전력이
 * 있고 이 마스커까지 갖춰 뒀는데, 새 비밀값이 그 장치를 그냥 지나갔다.
 *
 * <p><b>경로 모양 자체는 계약이 정한 것이라 바꾸지 않는다.</b> 계약은
 * {@code POST /api/chat/invites/{code}/join} 이고, 그 URL 을 바꾸면 앱과 링크가 함께 깨진다.
 * 가리는 것은 <b>로그에 남는 값</b>뿐이다.
 *
 * <h2>왜 {@link #maskUri(String)} 이 {@code static} 인가</h2>
 * <p>{@code GlobalExceptionHandler} 가 이 규칙을 써야 하는데, 그 클래스는 지금 생성자
 * 의존성이 없고 {@code ChatErrorCodeTest} 가 {@code new GlobalExceptionHandler()} 로 직접
 * 만든다. 주입을 더하면 그 테스트와 앞으로의 직접 생성이 전부 함께 흔들린다. 이 규칙은
 * 상태가 없으므로 정적 메서드가 맞고, 인스턴스 {@link #mask(String)} 도 같은 것을 부른다 —
 * 사본이 생기지 않는다.
 */
@Component
public class SensitiveDataMasker {

    private static final Pattern BEARER = Pattern.compile("(?i)Bearer\\s+[A-Za-z0-9._\\-]+\\.?[A-Za-z0-9._\\-]*\\.?[A-Za-z0-9._\\-]*");
    private static final Pattern SECRET = Pattern.compile("(?i)(api[_-]?key|secret|token|password)\\s*[:=]\\s*[^\\s,]+");

    /**
     * 참여 경로의 초대코드 세그먼트 — {@code /api/chat/invites/<code>/join}.
     *
     * <p>{@code /join} 을 요구하는 것이 의도다. 그래야 코드가 실제로 있는 요청만 잡고,
     * 코드가 없는 경로를 잘못 가리지 않는다.
     */
    private static final Pattern INVITE_JOIN_PATH =
            Pattern.compile("(/api/chat/invites/)[^/\\s?\"']+(/join)");

    /**
     * 회수 경로의 초대코드 세그먼트 — {@code /api/chat/rooms/{roomId}/invites/<code>}.
     *
     * <p>발급 경로({@code .../invites} — 뒤에 세그먼트가 없다)는 코드를 싣지 않으므로 잡히지
     * 않는다. 그 경로까지 가리면 로그에서 "어느 방에 발급했나" 가 사라져 조사가 어려워진다.
     */
    private static final Pattern INVITE_REVOKE_PATH =
            Pattern.compile("(/api/chat/rooms/\\d+/invites/)[^/\\s?\"']+");

    private static final String MASK = "***";

    public String mask(String input) {
        if (input == null || input.isBlank()) {
            return input;
        }
        String masked = BEARER.matcher(input).replaceAll("Bearer " + MASK);
        masked = SECRET.matcher(masked).replaceAll("$1=" + MASK);
        return maskUri(masked);
    }

    /**
     * 경로에 실린 비밀값을 가린다. 경로가 아닌 문자열에 부르는 것도 안전하다 — 안 맞으면
     * 그대로 돌려준다.
     *
     * <p>이 메서드가 <b>지워지면 초대코드가 다시 평문으로 로그에 남는다.</b>
     * {@code SensitiveDataMaskerTest} 가 그것을 잡는다.
     */
    public static String maskUri(String input) {
        if (input == null || input.isBlank()) {
            return input;
        }
        String masked = INVITE_JOIN_PATH.matcher(input).replaceAll("$1" + MASK + "$2");
        return INVITE_REVOKE_PATH.matcher(masked).replaceAll("$1" + MASK);
    }
}
