package com.heattrip.heat_trip_backend.chat.metrics;

import static org.assertj.core.api.Assertions.assertThat;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.Meter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 이 저장소의 첫 커스텀 메트릭이 <b>이름과 태그를 지키는지</b> 본다. (이슈 #80)
 *
 * <p>메트릭은 조용히 망가진다. 이름을 바꿔도, 태그를 빼도, 값을 안 올려도 <b>서버는 정상이다</b> —
 * 대시보드만 비어 있고 그건 다음 장애 때 알게 된다. 그래서 테스트가 지킨다.
 */
class ChatMetricsTest {

    private MeterRegistry registry;
    private ChatMetrics metrics;

    @BeforeEach
    void setUp() {
        registry = new SimpleMeterRegistry();
        metrics = new ChatMetrics(registry);
    }

    @Test
    @DisplayName("첫 호출 전에도 chat.poll 이 empty·hit 둘 다 0 으로 노출된다")
    void pollCountersExistBeforeTheFirstCall() {
        List<Meter> polls = registry.getMeters().stream()
                .filter(meter -> meter.getId().getName().equals("chat.poll"))
                .toList();

        assertThat(polls)
                .as("""
                        지표가 없는 것과 0인 것은 다르다. 없으면 대시보드가 빈칸이고, 그때 사람은
                        "아직 아무도 안 썼나" 와 "계측이 깨졌나" 를 구분하지 못한다.
                        """)
                .hasSize(2);
    }

    @Test
    @DisplayName("chat.poll 의 result 태그가 empty 와 hit 을 가른다 — 태그를 지우면 이 단언이 깨진다")
    void pollIsSplitByResultTag() {
        metrics.pollEmpty();
        metrics.pollEmpty();
        metrics.pollHit();

        Counter empty = registry.find("chat.poll").tag("result", "empty").counter();
        Counter hit = registry.find("chat.poll").tag("result", "hit").counter();

        assertThat(empty).as("result=empty 카운터가 없다").isNotNull();
        assertThat(hit).as("result=hit 카운터가 없다").isNotNull();
        assertThat(empty.count()).isEqualTo(2.0);
        assertThat(hit.count()).isEqualTo(1.0);

        assertThat(empty.count() / (empty.count() + hit.count()))
                .as("""
                        empty 비율이 이 지표의 존재 이유다. 폴링 간격을 조일지 늘릴지의 유일한 근거이고,
                        http.server.requests 로는 안 나온다 — 빈 응답도 새 메시지도 둘 다 200 이다.

                        태그를 지워 둘을 합치면 이 비율을 만들 수 없다. 그러면 이 지표를 둘 이유가 없다.
                        """)
                .isEqualTo(2.0 / 3.0);
    }

    @Test
    @DisplayName("chat.message.sent 가 room_kind 로 갈린다 — 가족과 산책 크루를 구분한다")
    void messageSentIsSplitByRoomKind() {
        metrics.messageSent("family");
        metrics.messageSent("family");
        metrics.messageSent("walk_crew");

        Counter family = registry.find("chat.message.sent").tag("room_kind", "family").counter();
        Counter walkCrew = registry.find("chat.message.sent").tag("room_kind", "walk_crew").counter();

        assertThat(family).isNotNull();
        assertThat(walkCrew).isNotNull();
        assertThat(family.count()).isEqualTo(2.0);
        assertThat(walkCrew.count())
                .as("""
                        방 종류가 둘이다(ADR-0011). 태그가 없으면 "산책 크루 채팅이 죽었는데 가족
                        채팅은 멀쩡한 상태" 를 구분할 수 없다.
                        """)
                .isEqualTo(1.0);
    }

    @Test
    @DisplayName("room_kind 가 비어 있어도 태그를 비우지 않는다 — 시계열이 갈라지면 합계가 안 맞는다")
    void unknownRoomKindStillCarriesATag() {
        metrics.messageSent(null);
        metrics.messageSent("  ");

        Counter unknown = registry.find("chat.message.sent").tag("room_kind", "unknown").counter();

        assertThat(unknown).as("null 이나 공백이면 unknown 으로 들어가야 한다").isNotNull();
        assertThat(unknown.count()).isEqualTo(2.0);
    }

    @Test
    @DisplayName("chat.seq.assign 이 방 단위 직렬화 지점의 소요를 담는다")
    void seqAssignRecordsDuration() {
        metrics.recordSeqAssign(5_000_000L);
        metrics.recordSeqAssign(15_000_000L);

        var timer = registry.find("chat.seq.assign").timer();

        assertThat(timer).as("경합이 보이는 유일한 자리다").isNotNull();
        assertThat(timer.count()).isEqualTo(2);
        assertThat(timer.totalTime(java.util.concurrent.TimeUnit.MILLISECONDS)).isEqualTo(20.0);
    }

    @Test
    @DisplayName("이름이 chat. 으로 시작한다 — 다음 도메인이 따라올 규약이다")
    void everyMeterCarriesTheDomainPrefix() {
        metrics.messageSent("family");
        metrics.recordSeqAssign(1L);

        assertThat(registry.getMeters())
                .as("""
                        접두가 없으면 대시보드에서 http.server.requests 같은 프레임워크 지표와 섞인다.
                        점 표기인 것도 규약이다 — Prometheus 로 나갈 때 Micrometer 가
                        chat_message_sent_total 로 바꾼다. 우리가 snake 로 적으면 변환이 두 번 일어난다.
                        """)
                .isNotEmpty()
                .allSatisfy(meter -> assertThat(meter.getId().getName()).startsWith("chat."));
    }
}
