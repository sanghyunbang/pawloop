package com.heattrip.heat_trip_backend.walk.ai;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/**
 * AI 주간 요약의 손잡이 — 이슈 #486. {@code app.ai.weekly-insight.*}.
 *
 * <h2>상한이 둘인 이유 (#538)</h2>
 * <p>예전에는 <b>한 주에 세 번</b>이라는 상한 하나였다. 그 상한에 닿으면 새 산책이 와도 문장을 다시
 * 만들지 않고 <b>옛 문장을 그대로 내보냈다</b> — 화요일에 카드가 "이번 주 0km" 라고 말하는데 바로 위
 * 카드는 "이번 주 3회 · 1.9km" 였다. 주 3회는 주 초에 다 써 버리기 쉬워서, 한 번 닿으면 그 주가 끝날
 * 때까지 틀린 숫자가 남았다.
 *
 * <p>그래서 상한을 <b>날 단위 둘</b>로 바꿨다 — 서버 전체({@link #dailyCap})와 한 줄({@link #perRowDailyCap}).
 * 둘 다 날이 바뀌면 0 부터 다시 센다. 상한에 닿았을 때 하는 일도 바꿨다: 옛 문장을 내보내지 않고
 * <b>카드를 안 그린다</b>. 규칙으로 만든 "이번 주 요약" 카드는 그대로 있으니 숫자를 잃지 않는다.
 *
 * @param enabled         끄면 키가 있어도 부르지 않는다
 * @param dailyCap        하루에 모델을 부르는 횟수 상한(서버 전체). 넘기면 조용히 1단계 문장만 — 로그 한 줄
 * @param perRowDailyCap  한 사람 · 한 아이 · 한 주의 요약 하나가 <b>하루에</b> 다시 만들어지는 횟수 상한.
 *                        한 사람이 서버 하루치({@link #dailyCap})를 혼자 쓰지 못하게 막는 자리다.
 *                        통계 화면을 열 때, 그것도 숫자가 바뀌었을 때만 세므로 실제 사용자는 하루 두세 번이다
 * @param timeoutSeconds  모델 응답을 기다리는 시간. 넘기면 이번엔 없이 나가고 다음 요청이 다시 시도한다
 * @param async           모델 호출을 요청 밖에서. false 면 통계 요청이 모델을 기다린다(테스트 · 비상 스위치)
 */
@ConfigurationProperties(prefix = "app.ai.weekly-insight")
public record WeeklyInsightProperties(
        @DefaultValue("true") boolean enabled,
        @DefaultValue("200") int dailyCap,
        @DefaultValue("10") int perRowDailyCap,
        @DefaultValue("12") int timeoutSeconds,
        @DefaultValue("true") boolean async) {
}
