package com.heattrip.heat_trip_backend.chat.metrics;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import org.springframework.stereotype.Component;

/**
 * 채팅의 커스텀 메트릭 셋. <b>이 저장소의 첫 커스텀 메트릭이다.</b> (이슈 #80)
 *
 * <h2>이름 규약을 여기서 정한다</h2>
 * <p>다음 도메인이 이 모양을 따라온다.
 * <ul>
 *   <li><b>도메인 접두</b> — {@code chat.} 으로 시작한다. 접두가 없으면 대시보드에서
 *       {@code http.server.requests} 같은 프레임워크 지표와 섞인다.</li>
 *   <li><b>점 표기</b> — snake 가 아니라 dot 이다. Micrometer 가 백엔드마다 알아서 바꾼다 —
 *       Prometheus 로 나갈 때 {@code chat.message.sent} 는 {@code chat_message_sent_total} 이
 *       된다. 우리가 {@code chat_message_sent} 라고 적으면 그 변환이 두 번 일어난다.</li>
 *   <li><b>태그는 카디널리티가 낮은 것만</b> — 방 종류(둘)와 결과(둘)는 되고, {@code roomId} 나
 *       {@code userId} 는 안 된다. 시계열이 사용자 수만큼 늘어난다.</li>
 * </ul>
 *
 * <h2>셋을 고른 이유</h2>
 * <ul>
 *   <li>{@link #messageSent} — 없으면 <b>조용한 것과 고장 난 것을 구분하지 못한다.</b>
 *       사람이 안 보내는 것과 전송이 깨진 것은 둘 다 "그래프가 평평하다" 로 보인다.</li>
 *   <li>{@link #pollEmpty} · {@link #pollHit} — <b>폴링 간격을 조일지 늘릴지의 유일한 근거다.</b>
 *       {@code http.server.requests} 로는 안 나온다 — 빈 응답도 새 메시지도 둘 다 200 이다.</li>
 *   <li>{@link #seqAssign} — 방 단위 <b>직렬화 지점</b>이다. 경합은 여기서만 보인다.
 *       한 방에 사람이 몰리면 이 타이머가 먼저 벌어지고, 커넥션 풀은 그다음에 아프다.</li>
 * </ul>
 *
 * <h2>임계와 그때 할 행동</h2>
 * <table>
 *   <caption>사람이 보는 기준. 경보가 아니다 (알림 규칙은 M5)</caption>
 *   <tr><th>무엇</th><th>기준</th><th>그때 할 것</th></tr>
 *   <tr><td>HTTP p95</td><td>&gt; 500ms 가 5분</td>
 *       <td>{@code chat.seq.assign} 부터 본다. 거기가 벌어져 있으면 방 경합이다</td></tr>
 *   <tr><td>{@code hikaricp_connections_pending}</td><td>&gt; 0 이 1분 지속</td>
 *       <td><b>롤백 조건이다.</b> 채팅 배포를 되돌린다</td></tr>
 *   <tr><td>{@code chat.poll} 의 empty 비율</td><td>&gt; 0.95</td>
 *       <td>한도를 낮추는 것이 아니라 <b>폴링 간격을 늘린다</b>. 비용은 DB 를 읽는 것이 아니라
 *           아무것도 없는데 왕복하는 것이다</td></tr>
 * </table>
 *
 * <h2>왜 하위 패키지인가</h2>
 * <p>{@code chat} 루트는 <b>공개 표면</b>이다(#103 · #108). 이 타입은 모듈 안에서만 쓰므로
 * 루트에 두면 "공개인데 아무도 안 쓰는 표면" 이 하나 늘고, 그건 {@code PackageConventionDocTest}
 * 가 문서와 대조하는 12/4 구분을 깨뜨린다.
 */
@Component
public class ChatMetrics {

    /** 방 종류. 값이 둘뿐이라 태그로 안전하다 — {@code family} · {@code walk_crew} (ADR-0011). */
    private static final String TAG_ROOM_KIND = "room_kind";

    private static final String TAG_RESULT = "result";

    private final MeterRegistry registry;
    private final Counter pollEmpty;
    private final Counter pollHit;
    private final Timer seqAssign;

    public ChatMetrics(MeterRegistry registry) {
        this.registry = registry;
        // 태그 값이 정해져 있는 것은 미리 만든다. 첫 호출 전에도 0 으로 노출되어야
        // "지표가 없는 것" 과 "0인 것" 이 구분된다.
        this.pollEmpty = Counter.builder("chat.poll")
                .description("채팅 폴링 응답. empty 비율이 높으면 간격을 늘려야 한다")
                .tag(TAG_RESULT, "empty")
                .register(registry);
        this.pollHit = Counter.builder("chat.poll")
                .description("채팅 폴링 응답. empty 비율이 높으면 간격을 늘려야 한다")
                .tag(TAG_RESULT, "hit")
                .register(registry);
        this.seqAssign = Timer.builder("chat.seq.assign")
                .description("방 단위 room_seq 발급. 방 경합이 보이는 유일한 자리")
                .register(registry);
    }

    /**
     * 메시지 한 건이 저장됐다.
     *
     * @param roomKind {@code chat_room.origin_kind}. 알 수 없으면 {@code unknown} 으로 들어온다 —
     *                 태그를 비우면 시계열이 갈라져 합계가 안 맞는다
     */
    public void messageSent(String roomKind) {
        Counter.builder("chat.message.sent")
                .description("저장된 채팅 메시지. 조용한 것과 고장 난 것을 구분하는 유일한 지표")
                .tag(TAG_ROOM_KIND, roomKind == null || roomKind.isBlank() ? "unknown" : roomKind)
                .register(registry)
                .increment();
    }

    /** 폴링이 새 메시지를 하나라도 실어 보냈다. */
    public void pollHit() {
        pollHit.increment();
    }

    /** 폴링이 빈손으로 돌아갔다. 이 비율이 이 지표의 존재 이유다. */
    public void pollEmpty() {
        pollEmpty.increment();
    }

    /**
     * {@code room_seq} 발급 한 번의 소요.
     *
     * <p>{@code Duration} 을 만들지 않고 나노초를 그대로 넘긴다. {@code chat} 소스에서 기간을
     * 직접 조립하는 것은 {@code ChatLimitsTest} 가 금지한다 — 초대 유효기간을 그렇게 우회한
     * 적이 있어서 걸어 둔 가드이고, 메트릭은 그 가드의 대상이 아니지만 <b>예외를 여는 대신
     * 애초에 안 만드는 쪽</b>을 골랐다. 예외를 하나 열면 다음 사람이 그 경계를 판단해야 한다.
     */
    public void recordSeqAssign(long nanos) {
        seqAssign.record(nanos, java.util.concurrent.TimeUnit.NANOSECONDS);
    }
}
