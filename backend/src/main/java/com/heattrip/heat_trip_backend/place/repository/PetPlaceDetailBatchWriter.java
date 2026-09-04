package com.heattrip.heat_trip_backend.place.repository;

import com.heattrip.heat_trip_backend.place.dto.PlaceDto;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;

/**
 * 상세 허용목록에 <b>수천 건을 한꺼번에</b> 등재한다 — 이슈 #273.
 *
 * <h2>왜 {@code registerFromSnapshot} 을 반복하지 않는가</h2>
 * <p>그 메서드는 한 건짜리 {@code @Modifying} 네이티브 upsert 다. 셀 스냅샷은 한 번에
 * 최대 1,000건이라 그걸로 충분했다. <b>전국 카탈로그는 9,684건이다</b>(실측 2026-09-04).
 * 한 건씩 부르면 왕복이 9,684번이고, 그게 <b>사용자 요청 안에서</b> 일어난다.
 *
 * <p>JDBC 배치로 묶으면 왕복이 {@link #CHUNK} 단위가 된다.
 *
 * <h2>왜 JPA 가 아니라 {@link JdbcTemplate} 인가</h2>
 * <p>{@code on duplicate key update} 는 MySQL 문법이라 JPQL 로 못 쓴다. 그리고 이 쓰기는
 * 영속성 컨텍스트에 남을 이유가 없다 — 9,684개 엔티티를 1차 캐시에 쌓으면 힙만 먹는다.
 *
 * <h2>{@code overview}·{@code petInfo} 는 안 건드린다</h2>
 * <p>{@code registerFromSnapshot} 과 같은 규칙이다. 이미 받아 둔 상세를 지우면 그것을
 * 다시 받는 데 예산이 든다.
 */
@Component
public class PetPlaceDetailBatchWriter {

    /**
     * 한 배치에 묶는 행 수.
     *
     * <p>행당 자리표시자가 8개다. 1,000행이면 8,000개로, MySQL 의 상한(65,535)에 한참
     * 못 미친다. 더 키워도 왕복만 줄고 메모리는 그만큼 는다.
     */
    static final int CHUNK = 1_000;

    private static final String UPSERT = """
            insert into pet_place_detail
                   (content_id, title, addr, tel, image, lat, lng, content_type_id)
            values (?, ?, ?, ?, ?, ?, ?, ?)
            on duplicate key update
                   title = values(title),
                   addr = values(addr),
                   tel = values(tel),
                   image = values(image),
                   lat = values(lat),
                   lng = values(lng),
                   content_type_id = values(content_type_id)
            """;

    private final JdbcTemplate jdbc;

    public PetPlaceDetailBatchWriter(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /**
     * 이 장소들을 허용목록에 등재한다.
     *
     * <p>{@code contentId} 가 없는 항목은 조용히 건너뛴다 — 등재할 키가 없다.
     *
     * @return 실제로 보낸 행 수
     */
    public int registerAll(List<PlaceDto> places) {
        List<Object[]> args = new ArrayList<>(Math.min(places.size(), CHUNK));
        int sent = 0;

        for (PlaceDto place : places) {
            if (place.contentId() == null || place.contentId().isBlank()) {
                continue;
            }
            args.add(new Object[] {
                    place.contentId(), place.title(), place.addr(), place.tel(),
                    place.image(), place.lat(), place.lng(), place.contentTypeId()});

            if (args.size() == CHUNK) {
                jdbc.batchUpdate(UPSERT, args);
                sent += args.size();
                args.clear();
            }
        }

        if (!args.isEmpty()) {
            jdbc.batchUpdate(UPSERT, args);
            sent += args.size();
        }
        return sent;
    }
}
