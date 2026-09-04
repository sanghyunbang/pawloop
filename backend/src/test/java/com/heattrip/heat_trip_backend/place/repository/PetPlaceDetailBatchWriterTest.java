package com.heattrip.heat_trip_backend.place.repository;

import com.heattrip.heat_trip_backend.place.dto.PlaceDto;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 허용목록 대량 등재 — 이슈 #273.
 *
 * <h2>왜 통합 테스트로 안 재는가</h2>
 * <p>{@code PlaceCatalogIntegrationTest} 는 장소를 서너 개만 쓴다. <b>여기서 틀릴 수 있는
 * 것은 묶음 경계</b>이고(마지막 조각을 안 보내는가, 정확히 {@link PetPlaceDetailBatchWriter#CHUNK}
 * 배수일 때 빈 배치를 한 번 더 보내는가) 그건 수천 개를 넣어야 드러난다. 실제 DB 에
 * 수천 행을 넣는 대신 {@link JdbcTemplate} 를 가로채 <b>무엇을 보냈는지</b>만 본다.
 */
class PetPlaceDetailBatchWriterTest {

    /** 보낸 배치의 크기를 기록하는 {@link JdbcTemplate}. */
    private static final class RecordingJdbc extends JdbcTemplate {
        final List<Integer> batchSizes = new ArrayList<>();
        final List<Object[]> lastBatch = new ArrayList<>();

        @Override
        public int[] batchUpdate(String sql, List<Object[]> batchArgs) {
            batchSizes.add(batchArgs.size());
            lastBatch.clear();
            lastBatch.addAll(batchArgs);
            return new int[batchArgs.size()];
        }
    }

    private static List<PlaceDto> places(int count) {
        List<PlaceDto> out = new ArrayList<>(count);
        for (int i = 0; i < count; i++) {
            out.add(new PlaceDto(String.valueOf(i), "장소" + i, PlaceDto.SOURCE_KTO,
                    "12", "12", 37.5, 127.0, "주소", null, null, null));
        }
        return out;
    }

    @Test
    @DisplayName("CHUNK 를 넘으면 나눠 보내고, 마지막 조각도 보낸다")
    void itSplitsAndFlushesTheRemainder() {
        RecordingJdbc jdbc = new RecordingJdbc();
        int count = PetPlaceDetailBatchWriter.CHUNK * 2 + 7;

        int sent = new PetPlaceDetailBatchWriter(jdbc).registerAll(places(count));

        assertThat(sent).isEqualTo(count);
        assertThat(jdbc.batchSizes)
                .as("""
                        마지막 조각을 안 보내면 그만큼의 장소가 허용목록에 안 들어간다 — \
                        목록에는 뜨는데 상세를 누르면 404 다.""")
                .containsExactly(PetPlaceDetailBatchWriter.CHUNK,
                        PetPlaceDetailBatchWriter.CHUNK, 7);
    }

    @Test
    @DisplayName("정확히 CHUNK 배수면 빈 배치를 더 보내지 않는다")
    void anExactMultipleSendsNoEmptyBatch() {
        RecordingJdbc jdbc = new RecordingJdbc();

        new PetPlaceDetailBatchWriter(jdbc)
                .registerAll(places(PetPlaceDetailBatchWriter.CHUNK));

        assertThat(jdbc.batchSizes)
                .as("빈 배치는 왕복만 쓰고 아무것도 안 한다")
                .containsExactly(PetPlaceDetailBatchWriter.CHUNK);
    }

    @Test
    @DisplayName("빈 목록이면 DB 를 아예 안 부른다")
    void anEmptyListTouchesNothing() {
        RecordingJdbc jdbc = new RecordingJdbc();

        int sent = new PetPlaceDetailBatchWriter(jdbc).registerAll(List.of());

        assertThat(sent).isZero();
        assertThat(jdbc.batchSizes).isEmpty();
    }

    @Test
    @DisplayName("contentId 가 없는 항목은 건너뛴다 — 등재할 키가 없다")
    void placesWithoutAContentIdAreSkipped() {
        RecordingJdbc jdbc = new RecordingJdbc();
        List<PlaceDto> mixed = new ArrayList<>(places(2));
        mixed.add(new PlaceDto(null, "키 없음", PlaceDto.SOURCE_KTO,
                null, null, 37.5, 127.0, null, null, null, null));
        mixed.add(new PlaceDto("  ", "빈 키", PlaceDto.SOURCE_KTO,
                null, null, 37.5, 127.0, null, null, null, null));

        int sent = new PetPlaceDetailBatchWriter(jdbc).registerAll(mixed);

        assertThat(sent)
                .as("널 키를 그대로 보내면 배치 하나가 통째로 실패하고, 그러면 나머지도 안 들어간다")
                .isEqualTo(2);
        assertThat(jdbc.batchSizes).containsExactly(2);
    }

    @Test
    @DisplayName("행당 자리표시자가 여덟이다 — 열 수가 어긋나면 배치가 통째로 실패한다")
    void everyRowCarriesEightColumns() {
        RecordingJdbc jdbc = new RecordingJdbc();

        new PetPlaceDetailBatchWriter(jdbc).registerAll(places(1));

        assertThat(jdbc.lastBatch.get(0))
                .as("insert 의 컬럼 수와 여기 배열 길이가 같아야 한다")
                .hasSize(8);
    }
}
