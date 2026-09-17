package com.heattrip.heat_trip_backend.walksafety;

import java.time.Duration;
import java.time.Instant;
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
 * 미세먼지가 <b>빠진</b> 응답을 얼마나 오래 기억하는가 — 이슈 #668.
 *
 * <h2>왜 생겼나</h2>
 * <p>2026-09-17 00:01 KST 에 에어코리아 실시간 측정이 <b>한 번</b> 실패했다
 * ({@code WebClientRequestException} — 연결 자체가 안 섰다). 그런데 미세먼지가 빠진 그 응답을
 * 성공한 응답과 <b>똑같이 10분</b> 기억했고, 앱이 그것을 다시 30분 들고 있어서 최대 <b>40분</b>
 * 동안 화면에 "미세먼지 정보 없음" 이 남았다. 키 문제가 아니었다 — 승인은 2026-09-08 에 끝났고
 * 같은 시각에도 값은 잘 왔다.
 *
 * <p>측정소 <b>목록</b>에는 이미 같은 판단이 들어가 있었다(빈 목록은 5분만 —
 * {@code WalkSafetyStationCacheTest}). 실시간 측정에 그 짝이 없었을 뿐이다.
 *
 * <p>여기서 재는 것은 둘이다 — 값 없는 응답은 짧게 살고, 값 있는 응답은 그대로 10분 산다.
 * 시계를 실제로 앞으로 민다({@link MovableClock}).
 */
class WalkSafetyDustCacheTest {

    private static final Instant MIDNIGHT_KST = Instant.parse("2026-09-16T15:01:00Z");

    private static final PublicDataJson.Nowcast WEATHER =
            new PublicDataJson.Nowcast(22.0, 50, 0.0, 0);
    private static final PublicDataJson.Station SEONGSU =
            new PublicDataJson.Station("성수", 37.5449, 127.0436);
    private static final PublicDataJson.AirQuality AIR =
            new PublicDataJson.AirQuality(31, 18);

    @Test
    @DisplayName("미세먼지를 못 받은 응답은 10분을 살지 않는다 — 3분 뒤 사람은 값을 본다")
    void responseWithoutDustIsForgottenQuickly() {
        MovableClock clock = new MovableClock(MIDNIGHT_KST);
        KmaNowcastClient kma = mock(KmaNowcastClient.class);
        AirKoreaClient air = mock(AirKoreaClient.class);
        when(kma.fetch(anyInt(), anyInt(), anyString(), anyString())).thenReturn(Optional.of(WEATHER));
        when(air.stations()).thenReturn(List.of(SEONGSU));
        // 첫 번은 연결이 안 서고(2026-09-17 00:01 에 실제로 그랬다), 그다음부터는 값이 온다.
        when(air.realtime(anyString())).thenReturn(Optional.empty(), Optional.of(AIR));

        WalkSafetyService service = new WalkSafetyService(kma, air, clock);

        WalkSafetyNowResponse first = service.now(61, 126);
        assertThat(first.pm10()).as("이번 호출은 실패했으니 미세먼지가 없다").isNull();
        assertThat(first.station()).isNull();

        // 성공한 응답이었다면 아직 살아 있을 시각이다(NOW_TTL 10분). 값이 빠졌으니 아니어야 한다.
        clock.advance(Duration.ofMinutes(3));

        WalkSafetyNowResponse later = service.now(61, 126);
        assertThat(later.pm10())
                .as("""
                        값 없는 응답을 10분 기억하면, 앱이 다시 30분 들고 있어서 한 번의 실패가 \
                        40분을 간다(2026-09-17 에 실제로 그랬다).""")
                .isEqualTo(31);
        assertThat(later.pm25()).isEqualTo(18);
        assertThat(later.station()).isEqualTo("성수");
    }

    @Test
    @DisplayName("미세먼지가 붙은 응답은 그대로 10분 산다 — 실패만 짧게 기억한다")
    void responseWithDustKeepsTheFullTtl() {
        MovableClock clock = new MovableClock(MIDNIGHT_KST);
        KmaNowcastClient kma = mock(KmaNowcastClient.class);
        AirKoreaClient air = mock(AirKoreaClient.class);
        when(kma.fetch(anyInt(), anyInt(), anyString(), anyString())).thenReturn(Optional.of(WEATHER));
        when(air.stations()).thenReturn(List.of(SEONGSU));
        // 두 번째 값이 다르다 — 캐시를 안 쓰고 다시 불렀다면 여기서 티가 난다.
        when(air.realtime(anyString()))
                .thenReturn(Optional.of(AIR), Optional.of(new PublicDataJson.AirQuality(99, 77)));

        WalkSafetyService service = new WalkSafetyService(kma, air, clock);

        assertThat(service.now(61, 126).pm10()).isEqualTo(31);
        clock.advance(Duration.ofMinutes(3));

        assertThat(service.now(61, 126).pm10())
                .as("성공한 응답까지 짧게 기억하면 공공데이터 쿼터를 다섯 배로 쓴다")
                .isEqualTo(31);
    }
}
