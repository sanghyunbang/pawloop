package com.heattrip.heat_trip_backend.place;

import com.heattrip.heat_trip_backend.place.dto.PetInfoDto;
import com.heattrip.heat_trip_backend.place.dto.PlaceDto;
import com.heattrip.heat_trip_backend.place.service.KtoApiClient;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ContextConfiguration;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.zip.GZIPInputStream;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 카탈로그 응답이 <b>실제로 압축돼 나가는가</b> — 이슈 #273.
 *
 * <h2>왜 MockMvc 가 아니라 진짜 포트인가</h2>
 * <p><b>MockMvc 로는 이 검사가 원리적으로 불가능하다.</b> 커넥터가 없어서 톰캣의 압축
 * 밸브를 아예 지나지 않는다. {@code PlaceCatalogIntegrationTest} 의 16개가 전부 초록인
 * 채로, 이 경로는 <b>압축이 하나도 안 걸린 상태로</b> 돌고 있었다(실측 2026-09-04).
 *
 * <h2>무엇이 잘못돼 있었나</h2>
 * <p>응답에 <b>강한 ETag</b> 를 붙이고 있었다. 톰캣의 {@code CompressionConfig} 는 강한
 * ETag 가 붙은 응답을 압축하지 않는다 — gzip 은 바이트열을 바꾸는데 강한 검증자는
 * 바이트열이 같다는 뜻이라 그 약속이 깨지기 때문이다.
 *
 * <p>같은 서버의 다른 경로는 멀쩡히 압축됐다. 즉 설정은 맞았고 <b>이 경로만</b> 2.97MB 를
 * 그대로 내보내고 있었다. 이 설계의 근거가 "gzip 0.44MB" 였으므로, 그 상태로는
 * <b>전제가 통째로 거짓</b>이었다.
 *
 * <h2>그래서 여기서 재는 것</h2>
 * <ol>
 *   <li>{@code Content-Encoding: gzip} 이 실제로 붙는가</li>
 *   <li>푼 내용이 원본과 같은가 (압축이 내용을 안 바꾸는가)</li>
 *   <li>그래도 {@code If-None-Match} 로 <b>304</b> 가 나오는가</li>
 * </ol>
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ContextConfiguration(classes = PlaceCatalogCompressionTest.StubbedKto.class)
class PlaceCatalogCompressionTest extends AbstractMySqlIntegrationTest {

    /**
     * 압축 하한(2KB)을 넘기려면 본문이 그보다 커야 한다.
     *
     * <p>작게 만들면 톰캣이 <b>압축할 이유가 없어서</b> 안 하고, 그러면 이 테스트가
     * 강한 ETag 를 되돌려도 초록불이 된다 — 아무것도 안 재는 검사가 된다.
     */
    private static final int PLACE_COUNT = 200;

    @TestConfiguration
    static class StubbedKto {
        @Bean
        @Primary
        FakeBulkKto fakeBulkKto() {
            return new FakeBulkKto();
        }
    }

    /** 한 페이지에 {@link #PLACE_COUNT} 곳을 주는 가짜 KTO. */
    static class FakeBulkKto extends KtoApiClient {

        FakeBulkKto() {
            super(null, null, null, "unused", PLACE_COUNT);
        }

        @Override
        public Result<List<PlaceDto>> fetchCatalogPage(int pageNo) {
            if (pageNo > 1) {
                return new Result.Empty<>();
            }
            List<PlaceDto> places = new ArrayList<>(PLACE_COUNT);
            for (int i = 0; i < PLACE_COUNT; i++) {
                places.add(new PlaceDto(String.valueOf(9000 + i),
                        "반려동반 장소 " + i, PlaceDto.SOURCE_KTO, "12", "12",
                        37.5 + i * 0.001, 127.0 + i * 0.001,
                        "서울특별시 어딘가 " + i + "길 " + i, null, null, null));
            }
            return new Result.Ok<>(places, PLACE_COUNT);
        }

        @Override
        public Result<String> fetchOverview(String contentId) {
            return new Result.Ok<>("개요입니다", 1);
        }

        @Override
        public Result<PetInfoDto> fetchPetInfo(String contentId) {
            return new Result.Ok<>(new PetInfoDto("소형견", "목줄 필수", null), 1);
        }
    }

    @LocalServerPort
    private int port;

    @Autowired
    private JdbcTemplate jdbc;

    private final HttpClient http = HttpClient.newHttpClient();

    @BeforeEach
    void reset() {
        jdbc.update("delete from kto_call_budget");
        jdbc.update("delete from place_catalog");
        jdbc.update("delete from pet_place_detail");
    }

    // ─────────────────────────── 테스트 ───────────────────────────

    @Test
    @DisplayName("카탈로그가 gzip 으로 나간다 — 이 설계의 근거가 그 숫자다")
    void theCatalogIsCompressed() throws Exception {
        HttpResponse<byte[]> res = get(null, true);

        assertThat(res.statusCode()).isEqualTo(200);
        assertThat(res.headers().firstValue("Content-Encoding"))
                .as("""
                        강한 ETag 를 붙이면 톰캣이 이 응답만 압축하지 않는다. 같은 서버의 \
                        다른 경로는 멀쩡히 압축되므로 설정을 봐도 안 보이고, MockMvc 는 \
                        커넥터가 없어 원리적으로 못 잡는다. 여기서 안 보면 아무도 안 알려준다.""")
                .contains("gzip");

        byte[] unzipped = gunzip(res.body());
        assertThat(unzipped.length)
                .as("압축본이 원본보다 작아야 한다 — 그게 이 경로를 한 덩어리로 둔 근거다")
                .isGreaterThan(res.body().length);
    }

    @Test
    @DisplayName("압축해도 내용이 같다 — 푼 것이 안 받은 것과 같아야 한다")
    void compressionDoesNotChangeTheContent() throws Exception {
        String plain = new String(get(null, false).body(), StandardCharsets.UTF_8);
        String unzipped = new String(gunzip(get(null, true).body()), StandardCharsets.UTF_8);

        assertThat(unzipped).isEqualTo(plain);
        assertThat(unzipped)
                .as("한글이 깨지면 압축·인코딩 어딘가가 틀린 것이다")
                .contains("반려동반 장소 0");
    }

    @Test
    @DisplayName("압축을 켜도 304 는 그대로 나온다 — 약한 검증자로 낮춘 대가가 없어야 한다")
    void conditionalRequestsStillWork() throws Exception {
        HttpResponse<byte[]> first = get(null, true);
        String etag = first.headers().firstValue("ETag").orElseThrow();

        assertThat(etag)
                .as("""
                        W/ 가 빠지면 톰캣이 압축을 멈춘다. 그 두 글자가 이 경로의 \
                        전송량 6배를 정한다.""")
                .startsWith("W/");

        HttpResponse<byte[]> second = get(etag, true);

        assertThat(second.statusCode()).isEqualTo(304);
        assertThat(second.body()).isEmpty();
    }

    @Test
    @DisplayName("압축을 안 받겠다고 하면 원본이 온다 — 옛 클라이언트도 읽을 수 있어야 한다")
    void aClientThatCannotUnzipStillGetsTheBody() throws Exception {
        HttpResponse<byte[]> res = get(null, false);

        assertThat(res.statusCode()).isEqualTo(200);
        assertThat(res.headers().firstValue("Content-Encoding")).isEmpty();
        assertThat(new String(res.body(), StandardCharsets.UTF_8)).startsWith("[{");
    }

    // ─────────────────────────── 지그 ───────────────────────────

    /**
     * {@code HttpClient} 는 gzip 을 <b>스스로 풀지 않는다.</b> 그래서 이 테스트가
     * 헤더와 바이트를 있는 그대로 볼 수 있다 — 자동으로 푸는 클라이언트를 쓰면
     * 압축이 걸렸는지 아닌지를 구분하지 못한다.
     */
    private HttpResponse<byte[]> get(String ifNoneMatch, boolean acceptGzip) throws Exception {
        HttpRequest.Builder req = HttpRequest.newBuilder()
                .uri(URI.create("http://127.0.0.1:" + port + "/api/places/catalog"))
                .header("Accept-Encoding", acceptGzip ? "gzip" : "identity")
                .GET();
        if (ifNoneMatch != null) {
            req.header("If-None-Match", ifNoneMatch);
        }
        return http.send(req.build(), HttpResponse.BodyHandlers.ofByteArray());
    }

    private static byte[] gunzip(byte[] compressed) throws Exception {
        try (InputStream in = new GZIPInputStream(new java.io.ByteArrayInputStream(compressed));
             ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            in.transferTo(out);
            return out.toByteArray();
        }
    }
}
