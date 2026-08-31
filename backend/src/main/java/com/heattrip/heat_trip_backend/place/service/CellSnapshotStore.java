package com.heattrip.heat_trip_backend.place.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.place.dto.PlaceDto;
import com.heattrip.heat_trip_backend.place.entity.PlaceCell;
import com.heattrip.heat_trip_backend.place.repository.PetPlaceDetailRepository;
import com.heattrip.heat_trip_backend.place.repository.PlaceCellRepository;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

/**
 * 셀 스냅샷을 읽고 쓰는 자리 — 이슈 #40.
 *
 * <h2>왜 {@link PlaceQueryService} 와 <b>다른 빈</b>인가</h2>
 * <p>여기 메서드들이 {@code REQUIRES_NEW} 여야 하는데, <b>같은 빈 안에서 부르면 그
 * 애너테이션이 아무 일도 안 한다.</b> 스프링의 트랜잭션은 프록시로 걸리고, 자기 자신을
 * 부르는 호출은 프록시를 거치지 않기 때문이다. 조용히 안 걸리는 종류의 실수라 <b>클래스를
 * 나누는 것</b>이 유일하게 확실한 방법이다.
 *
 * <h2>왜 {@code REQUIRES_NEW} 여야 하는가</h2>
 * <p>스냅샷 저장이 요청 트랜잭션에 얹히면, 그 트랜잭션이 뒤에서 롤백될 때 캐시가 함께
 * 사라진다. <b>그런데 KTO 호출은 이미 나갔다.</b> 예산만 태우고 아무것도 안 남는다.
 */
@Service
public class CellSnapshotStore {

    private static final Logger log = LoggerFactory.getLogger(CellSnapshotStore.class);

    private static final TypeReference<List<PlaceDto>> PLACE_LIST = new TypeReference<>() {};

    /** 실패 백오프의 기준이 되는, "아주 오래된" 시각. 스냅샷이 없는 셀의 자리표시다. */
    private static final int PLACEHOLDER_AGE_YEARS = 1;

    private final PlaceCellRepository cells;
    private final PetPlaceDetailRepository details;
    private final ObjectMapper objectMapper;
    private final Clock clock;

    public CellSnapshotStore(PlaceCellRepository cells,
                             PetPlaceDetailRepository details,
                             ObjectMapper objectMapper,
                             Clock clock) {
        this.cells = cells;
        this.details = details;
        this.objectMapper = objectMapper;
        this.clock = clock;
    }

    /** 이 셀의 행. 없으면 비어 있다. */
    @Transactional(readOnly = true)
    public Optional<PlaceCell> find(GridCell cell) {
        return cells.findById(new PlaceCell.Key(cell.latIdx(), cell.lngIdx()));
    }

    /**
     * 저장된 장소 목록.
     *
     * <p>읽기에 실패해도 던지지 않는다 — 우리가 쓴 JSON 이라 여기 올 일이 없고, 와도
     * 갱신 경로가 다음 요청에서 덮어쓴다. 죽는 것보다 낫다.
     */
    public Optional<List<PlaceDto>> read(PlaceCell row) {
        try {
            return Optional.of(objectMapper.readValue(row.getPayload(), PLACE_LIST));
        } catch (Exception e) {
            log.error("셀 스냅샷을 읽지 못했다. 갱신으로 덮어쓴다.", e);
            return Optional.empty();
        }
    }

    /**
     * 스냅샷을 쓰고, 그 안의 장소들을 <b>상세 허용목록에 등재</b>한다.
     *
     * <p>등재가 여기 있는 이유: "우리가 목록에 실어 보낸 장소" 만 상세를 받을 수 있어야
     * 무작위 {@code contentId} 로 상세 예산을 태우는 경로가 닫힌다.
     *
     * <p><b>빈 목록도 저장한다.</b> 저장하지 않으면 장소가 없는 셀이 매 요청마다 다시
     * 호출되고, 그게 격자가 막으려던 바로 그 일이다.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void store(GridCell cell, List<PlaceDto> places, int totalCount) {
        String payload;
        try {
            payload = objectMapper.writeValueAsString(places);
        } catch (Exception e) {
            log.error("셀 스냅샷을 쓰지 못했다.", e);
            return;
        }

        cells.save(PlaceCell.builder()
                .latIdx(cell.latIdx())
                .lngIdx(cell.lngIdx())
                .payload(payload)
                .itemCount(places.size())
                .totalCount(totalCount)
                .fetchedAt(LocalDateTime.now(clock))
                .failedAt(null)
                .failStreak(0)
                .build());

        for (PlaceDto place : places) {
            if (place.contentId() != null && !place.contentId().isBlank()) {
                details.registerFromSnapshot(place.contentId(), place.title(), place.addr(),
                        place.tel(), place.image(), place.lat(), place.lng(),
                        place.contentTypeId());
            }
        }

        if (totalCount > places.size()) {
            log.warn("셀 스냅샷이 잘렸다 — cell={}:{} 받은 것 {} / 전체 {}. app.kto.num-of-rows 를 올려야 한다.",
                    cell.latIdx(), cell.lngIdx(), places.size(), totalCount);
        }
    }

    /**
     * 실패를 기록한다. <b>스냅샷은 안 건드린다</b> — 있으면 계속 서빙해야 한다.
     *
     * <p>스냅샷이 아직 없는 셀이면 빈 자리표시를 만들어 둔다. 없으면 실패한 셀을 매 요청마다
     * 다시 부르고, 그것만으로 하루 예산이 사라진다.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void recordFailure(GridCell cell) {
        LocalDateTime now = LocalDateTime.now(clock);
        if (cells.recordFailure(cell.latIdx(), cell.lngIdx(), now) > 0) {
            return;
        }

        cells.save(PlaceCell.builder()
                .latIdx(cell.latIdx())
                .lngIdx(cell.lngIdx())
                .payload("[]")
                .itemCount(0)
                .totalCount(0)
                // 갱신 대상으로 남겨 둔다. 백오프가 지나면 다시 시도한다.
                .fetchedAt(now.minusYears(PLACEHOLDER_AGE_YEARS))
                .failedAt(now)
                .failStreak(1)
                .build());
    }
}
