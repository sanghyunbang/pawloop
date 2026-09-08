package com.heattrip.heat_trip_backend.walksafety;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;

import com.heattrip.heat_trip_backend.walksafety.dto.WalkSafetyNowResponse;
import com.heattrip.heat_trip_backend.walksafety.service.AirKoreaClient;
import com.heattrip.heat_trip_backend.walksafety.service.KmaNowcastClient;
import com.heattrip.heat_trip_backend.walksafety.service.PublicDataJson;
import com.heattrip.heat_trip_backend.walksafety.service.WalkSafetyService;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * 측정소 목록을 <b>못 받았을 때 얼마나 오래 기억하는가</b> — 이슈 #336.
 *
 * <h2>왜 생겼나</h2>
 * <p>2026-09-08 활용신청이 승인된 날, 부팅 직후 첫 요청의 측정소 목록이 5초 읽기 제한을 넘겨
 * 실패했다(실측 5,812ms — 같은 순간 인허가 레이어 적재가 같은 호스트에서 8,110행을 받고 있었다).
 * 그 <b>빈 목록을 한 시간</b> 기억하게 돼 있어서, 그 한 번의 겹침 때문에 미세먼지가 한 시간
 * 동안 화면에서 사라졌다. 승인 전에는 맞는 설계였지만 승인된 지금은 아니다.
 *
 * <p>여기서 재는 것은 "빈 목록의 수명이 짧다" 하나다. 시계를 주입해 시간을 흉내내지 않고
 * 실제로 앞으로 민다 — {@link Clock#offset}.
 */
class WalkSafetyStationCacheTest {

    private static final Instant NOON_KST = Instant.parse("2026-09-08T03:00:00Z");

    private static final PublicDataJson.Nowcast WEATHER =
            new PublicDataJson.Nowcast(27.0, 32, 0.0, 0);
    private static final PublicDataJson.Station SEONGSU =
            new PublicDataJson.Station("성수", 37.5449, 127.0436);
    private static final PublicDataJson.AirQuality AIR =
            new PublicDataJson.AirQuality(31, 18);

    /** 손으로 미는 시계. */
    private static final class MovableClock extends Clock {
        private Instant now;

        private MovableClock(Instant start) {
            this.now = start;
        }

        void advance(Duration by) {
            now = now.plus(by);
        }

        @Override
        public ZoneOffset getZone() {
            return ZoneOffset.UTC;
        }

        @Override
        public Clock withZone(java.time.ZoneId zone) {
            return this;
        }

        @Override
        public Instant instant() {
            return now;
        }
    }

    @Test
    @DisplayName("측정소 목록을 못 받아도 5분 뒤엔 다시 물어본다 — 한 번 놓쳤다고 한 시간을 비우지 않는다")
    void emptyStationsAreForgottenQuickly() {
        MovableClock clock = new MovableClock(NOON_KST);
        KmaNowcastClient kma = mock(KmaNowcastClient.class);
        AirKoreaClient air = mock(AirKoreaClient.class);
        when(kma.fetch(anyInt(), anyInt(), anyString(), anyString())).thenReturn(Optional.of(WEATHER));
        when(air.realtime(anyString())).thenReturn(Optional.of(AIR));
        // 첫 번은 못 받고(읽기 제한), 그다음부터는 받는다.
        when(air.stations()).thenReturn(List.of(), List.of(SEONGSU));

        WalkSafetyService service = new WalkSafetyService(kma, air, clock);

        WalkSafetyNowResponse first = service.now(61, 126);
        assertThat(first.pm10()).as("측정소를 못 받았으니 이번엔 미세먼지가 없다").isNull();
        assertThat(first.station()).isNull();

        // 격자 캐시(10분)를 넘겨야 다시 계산한다. 측정소 캐시(5분)는 그 사이에 이미 만료된다.
        clock.advance(Duration.ofMinutes(11));

        WalkSafetyNowResponse later = service.now(61, 126);
        assertThat(later.pm10())
                .as("""
                        빈 목록을 한 시간 기억하면 부팅 때 한 번 겹친 것 때문에 미세먼지가 \
                        한 시간 동안 사라진다(2026-09-08 에 실제로 그랬다).""")
                .isEqualTo(31);
        assertThat(later.pm25()).isEqualTo(18);
        assertThat(later.station()).isEqualTo("성수");
    }

    @Test
    @DisplayName("받은 목록은 오래 기억한다 — 하루에 한 번만 묻는다")
    void goodStationsAreKept() {
        MovableClock clock = new MovableClock(NOON_KST);
        KmaNowcastClient kma = mock(KmaNowcastClient.class);
        AirKoreaClient air = mock(AirKoreaClient.class);
        when(kma.fetch(anyInt(), anyInt(), anyString(), anyString())).thenReturn(Optional.of(WEATHER));
        when(air.realtime(anyString())).thenReturn(Optional.of(AIR));
        when(air.stations()).thenReturn(List.of(SEONGSU), List.of());

        WalkSafetyService service = new WalkSafetyService(kma, air, clock);

        assertThat(service.now(61, 126).station()).isEqualTo("성수");
        clock.advance(Duration.ofHours(3));

        assertThat(service.now(61, 126).station())
                .as("세 시간 뒤에도 같은 목록을 쓴다 — 두 번째 응답(빈 목록)을 받으러 가지 않는다")
                .isEqualTo("성수");
    }
}
