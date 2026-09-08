package com.heattrip.heat_trip_backend.walksafety;

import java.net.URI;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.walksafety.service.AirKoreaClient;
import com.heattrip.heat_trip_backend.walksafety.service.PublicDataJson;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.reactive.function.client.ClientResponse;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.util.DefaultUriBuilderFactory;

import reactor.core.publisher.Mono;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * {@link AirKoreaClient} 가 <b>어느 주소로</b> 나가는가 — 이슈 #336 · #393.
 *
 * <h2>왜 뒤늦게 생겼나</h2>
 * <p>{@code WalkSafetyEndpointIntegrationTest} 는 이 클라이언트를 통째로 가짜로 바꾸고,
 * {@code WalkSafetyParserTest} 는 <b>응답</b>만 본다. 그래서 <b>요청 주소를 보는 눈이 하나도
 * 없었다</b>. 그 사이 실시간 측정의 오퍼레이션 이름에 글자 둘이 더 붙어 있었고
 * ({@code getMsrstnAcct<b>nt</b>RltmMesureDnsty}), 게이트웨이는 그것을
 * {@code NO_OPENAPI_SERVICE_ERROR}(해당 오픈API 서비스가 없거나 폐기됨)로 돌려줬다.
 *
 * <p>그 실패가 <b>승인 대기와 똑같이 보였다</b> — 둘 다 "PM 이 null" 이다. 그래서 2026-09-08
 * 에 활용신청이 승인된 뒤에도 미세먼지가 안 붙었고, 진짜 주소로 직접 불러 보고서야 알았다.
 *
 * <h2>네트워크를 타지 않는다</h2>
 * <p>{@code WebClient} 의 교환 함수를 가짜로 끼워 <b>나간 URI 를 적어 둔다</b>. 서버를 띄우지
 * 않으므로 키·쿼터·시각에 안 묶인다. 진짜로 응답이 오는지는 {@code scripts/check-external-keys.sh}
 * 가 사람의 손으로 확인한다 — 그건 이 테스트가 할 일이 아니다.
 */
class AirKoreaClientTest {

    private static final String STATIONS_JSON = """
        {"response":{"header":{"resultCode":"00"},"body":{"items":[
          {"stationName":"성수","dmX":"37.5449","dmY":"127.0436"}]}}}
        """;
    private static final String AIR_JSON = """
        {"response":{"header":{"resultCode":"00"},"body":{"items":[
          {"stationName":"성수","pm10Value":"31","pm25Value":"18"}]}}}
        """;

    /** 나간 URI 를 적어 두는 가짜 교환 함수. 운영 빈과 같은 base URL · 같은 인코딩 모드다. */
    private record Spy(AirKoreaClient client, List<URI> sent) {
    }

    private static Spy spy(String body, String serviceKey) {
        List<URI> sent = new ArrayList<>();
        DefaultUriBuilderFactory uriFactory =
                new DefaultUriBuilderFactory("https://apis.data.go.kr/B552584");
        // 운영 빈과 같다(KtoWebClientConfig.build) — 키가 이미 인코딩돼 있어 다시 인코딩하면 안 된다.
        uriFactory.setEncodingMode(DefaultUriBuilderFactory.EncodingMode.NONE);

        WebClient webClient = WebClient.builder()
                .uriBuilderFactory(uriFactory)
                .exchangeFunction(request -> {
                    sent.add(request.url());
                    return Mono.just(ClientResponse.create(HttpStatus.OK)
                            .header("Content-Type", MediaType.APPLICATION_JSON_VALUE)
                            .body(body)
                            .build());
                })
                .build();

        return new Spy(new AirKoreaClient(webClient, new ObjectMapper(), serviceKey), sent);
    }

    @Test
    @DisplayName("실시간 측정은 getMsrstnAcctoRltmMesureDnsty 로 나간다 — 이름이 틀리면 게이트웨이가 '폐기됨' 을 준다")
    void realtime_usesTheOperationNameThatActuallyExists() {
        Spy spy = spy(AIR_JSON, "KEY");

        Optional<PublicDataJson.AirQuality> air = spy.client().realtime("성수");

        assertThat(spy.sent()).hasSize(1);
        String uri = spy.sent().get(0).toString();
        assertThat(uri)
                .as("""
                        오퍼레이션 이름 한 글자가 틀리면 NO_OPENAPI_SERVICE_ERROR 가 오고, 그 응답은 \
                        '아직 활용신청을 안 했다' 와 화면에서 구별되지 않는다(둘 다 PM 이 null). \
                        2026-09-08 에 실제로 그랬다 — 승인이 났는데도 미세먼지가 안 붙었다.""")
                .contains("/ArpltnInforInqireSvc/getMsrstnAcctoRltmMesureDnsty");
        assertThat(air).contains(new PublicDataJson.AirQuality(31, 18));
    }

    @Test
    @DisplayName("측정소 목록은 getMsrstnList 로 나간다 — 여기는 서비스도 이름도 다르다")
    void stations_useTheirOwnService() {
        Spy spy = spy(STATIONS_JSON, "KEY");

        List<PublicDataJson.Station> stations = spy.client().stations();

        assertThat(spy.sent().get(0).toString())
                .contains("/MsrstnInfoInqireSvc/getMsrstnList");
        assertThat(stations).hasSize(1);
    }

    @Test
    @DisplayName("측정소 이름을 URL 로 인코딩해 보낸다 — 한글이 날것으로 나가면 400 이다")
    void realtime_encodesTheStationName() {
        Spy spy = spy(AIR_JSON, "KEY");

        spy.client().realtime("성수");

        String uri = spy.sent().get(0).toString();
        assertThat(uri)
                .as("""
                        WebClient 의 인코딩 모드가 NONE 이다(키가 이미 인코딩돼 있어서). \
                        여기서 직접 안 감싸면 한글이 날것으로 나간다.""")
                .contains("stationName=%EC%84%B1%EC%88%98")
                .doesNotContain("stationName=성수");
    }

    @Test
    @DisplayName("실시간 측정에 dataTerm·ver 가 함께 간다 — 빠지면 게이트웨이가 빈 목록을 준다")
    void realtime_carriesTheRequiredParameters() {
        Spy spy = spy(AIR_JSON, "KEY");

        spy.client().realtime("성수");

        assertThat(spy.sent().get(0).toString())
                .contains("returnType=json")
                .contains("dataTerm=DAILY")
                .contains("ver=1.3");
    }

    @Test
    @DisplayName("키가 비어 있으면 아예 안 부른다 — 승인 전에는 요청 한 번도 안 나간다")
    void noKey_noCall() {
        Spy spy = spy(AIR_JSON, "  ");

        assertThat(spy.client().stations()).isEmpty();
        assertThat(spy.client().realtime("성수")).isEmpty();
        assertThat(spy.sent()).isEmpty();
    }

    @Test
    @DisplayName("측정소 이름이 없으면 안 부른다 — 격자 근처에 측정소가 없을 때다")
    void blankStation_noCall() {
        Spy spy = spy(AIR_JSON, "KEY");

        assertThat(spy.client().realtime(null)).isEmpty();
        assertThat(spy.client().realtime("   ")).isEmpty();
        assertThat(spy.sent()).isEmpty();
    }
}
