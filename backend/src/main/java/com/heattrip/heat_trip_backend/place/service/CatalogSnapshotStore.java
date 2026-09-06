package com.heattrip.heat_trip_backend.place.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.place.CatalogSource;
import com.heattrip.heat_trip_backend.place.dto.PlaceDto;
import com.heattrip.heat_trip_backend.place.entity.PlaceCatalog;
import com.heattrip.heat_trip_backend.place.repository.PetPlaceDetailBatchWriter;
import com.heattrip.heat_trip_backend.place.repository.PlaceCatalogRepository;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Clock;
import java.time.LocalDateTime;
import java.util.HexFormat;
import java.util.List;
import java.util.Optional;

/**
 * 전국 카탈로그를 읽고 쓰는 자리 — 이슈 #273.
 *
 * <h2>왜 {@link PlaceCatalogService} 와 <b>다른 빈</b>인가</h2>
 * <p>{@link CellSnapshotStore} 와 같은 이유다. 여기 메서드들이 {@code REQUIRES_NEW} 여야
 * 하는데, <b>같은 빈 안에서 부르면 그 애너테이션이 아무 일도 안 한다</b> — 스프링의
 * 트랜잭션은 프록시로 걸리고 자기 호출은 프록시를 안 거친다. 조용히 안 걸리는 종류의
 * 실수라 <b>클래스를 나누는 것</b>이 유일하게 확실한 방법이다.
 *
 * <h2>{@code read} 가 없다</h2>
 * <p>{@link CellSnapshotStore#read} 는 JSON 을 객체로 되돌린다. 여기는 안 한다 —
 * {@code payload} 가 <b>응답 본문 그대로</b>라 파싱할 이유가 없다({@link PlaceCatalog}).
 */
@Service
public class CatalogSnapshotStore {

    private static final Logger log = LoggerFactory.getLogger(CatalogSnapshotStore.class);

    /** 실패 백오프의 기준이 되는, "아주 오래된" 시각. 카탈로그가 없을 때의 자리표시다. */
    private static final int PLACEHOLDER_AGE_YEARS = 1;

    /** ETag 로 쓰는 해시 길이(hex 문자 수). SHA-256 앞 16바이트다. */
    private static final int ETAG_HEX_LENGTH = 32;

    private final PlaceCatalogRepository catalogs;
    private final PetPlaceDetailBatchWriter details;
    private final ObjectMapper objectMapper;
    private final Clock clock;

    public CatalogSnapshotStore(PlaceCatalogRepository catalogs,
                                PetPlaceDetailBatchWriter details,
                                ObjectMapper objectMapper,
                                Clock clock) {
        this.catalogs = catalogs;
        this.details = details;
        this.objectMapper = objectMapper;
        this.clock = clock;
    }

    /** 이 출처의 저장된 한 벌. 없으면 비어 있다. */
    @Transactional(readOnly = true)
    public Optional<PlaceCatalog> find(CatalogSource source) {
        return catalogs.findById(source.id());
    }

    /**
     * 한 벌을 쓰고, KTO 면 그 안의 장소들을 <b>상세 허용목록에 등재</b>한다. 인허가·두루누비
     * 항목은 상세 경로가 없으므로 등재하지 않는다(#291).
     *
     * <p>등재를 빠뜨리면 <b>카탈로그로 받은 장소는 상세를 못 연다.</b> "우리가 목록에 실어
     * 보낸 장소" 만 상세를 받을 수 있게 해 둔 것이 그 목록이고({@link CellSnapshotStore}),
     * 새 목록 경로가 생기면 그쪽도 등재해야 같은 규칙 안에 있다.
     *
     * <p><b>빈 목록은 저장하지 않는다.</b> 셀 스냅샷과 반대다 — 셀은 "이 동네에 장소가
     * 없다" 가 정상적인 답이지만, 전국이 0곳인 것은 <b>정상이 아니다.</b> 저장하면 지도가
     * 통째로 비고, 그 상태가 캐시 수명만큼 굳는다.
     *
     * @return 저장된 행. 빈 목록이라 안 저장했으면 비어 있다
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public Optional<PlaceCatalog> store(CatalogSource source, List<PlaceDto> places, int totalCount) {
        if (places.isEmpty()) {
            log.error("카탈로그({})가 0곳으로 왔다. 저장하지 않는다 — 그 칩이 통째로 빈다.", source);
            return Optional.empty();
        }

        String payload;
        try {
            payload = objectMapper.writeValueAsString(places);
        } catch (Exception e) {
            log.error("카탈로그를 쓰지 못했다.", e);
            return Optional.empty();
        }

        PlaceCatalog row = catalogs.save(PlaceCatalog.builder()
                .id(source.id())
                .source(source.wireValue())
                .payload(payload)
                .etag(etagOf(payload))
                .itemCount(places.size())
                .totalCount(totalCount)
                .fetchedAt(LocalDateTime.now(clock))
                .failedAt(null)
                .failStreak(0)
                .build());

        int registered = source == CatalogSource.KTO ? details.registerAll(places) : 0;

        if (totalCount > places.size()) {
            log.warn("카탈로그가 잘렸다 — 받은 것 {} / 전체 {}. 페이지 상한이나"
                            + " app.kto.budget.catalog-max-calls-per-day 를 올려야 한다.",
                    places.size(), totalCount);
        }
        log.info("카탈로그({})를 갱신했다 — {}곳, {}바이트, 허용목록 {}건, etag={}",
                source, places.size(), payload.length(), registered, row.getEtag());
        return Optional.of(row);
    }

    /**
     * 실패를 기록한다. <b>한 벌은 안 건드린다</b> — 있으면 계속 서빙해야 한다.
     *
     * <p>아직 한 벌이 없으면 빈 자리표시를 만들어 둔다. 없으면 실패한 뒤 매 요청마다 다시
     * 부르고, 그것만으로 하루 예산이 사라진다.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void recordFailure(CatalogSource source) {
        LocalDateTime now = LocalDateTime.now(clock);

        if (catalogs.recordFailure(source.id(), now) > 0) {
            return;
        }

        catalogs.save(PlaceCatalog.builder()
                .id(source.id())
                .source(source.wireValue())
                .payload("[]")
                .etag(etagOf("[]"))
                .itemCount(0)
                .totalCount(0)
                // 갱신 대상으로 남겨 둔다. 백오프가 지나면 다시 시도한다.
                .fetchedAt(now.minusYears(PLACEHOLDER_AGE_YEARS))
                .failedAt(now)
                .failStreak(1)
                .build());
    }

    /**
     * 내용 해시. <b>{@code fetchedAt} 이 아니라 내용이어야 한다</b> — 시각으로 만들면
     * KTO 데이터가 그대로여도 갱신할 때마다 값이 바뀌어 앱이 2.83MB 를 다시 받는다.
     *
     * <p>보안용이 아니라 동일성 판정용이라 앞 16바이트면 충분하다.
     */
    static String etagOf(String payload) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(payload.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest).substring(0, ETAG_HEX_LENGTH);
        } catch (NoSuchAlgorithmException e) {
            // SHA-256 은 모든 JVM 이 갖는다. 여기 오면 플랫폼이 깨진 것이다.
            throw new IllegalStateException("SHA-256 을 못 찾았다.", e);
        }
    }
}
