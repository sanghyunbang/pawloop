package com.heattrip.heat_trip_backend.place.service;

import com.heattrip.heat_trip_backend.place.KtoBudgetProperties;
import com.heattrip.heat_trip_backend.place.dto.PetInfoDto;
import com.heattrip.heat_trip_backend.place.dto.PlaceDetailDto;
import com.heattrip.heat_trip_backend.place.dto.PlaceDto;
import com.heattrip.heat_trip_backend.place.entity.PetPlaceDetailRow;
import com.heattrip.heat_trip_backend.place.repository.PetPlaceDetailRepository;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDateTime;
import java.util.Optional;

/**
 * 장소 상세 — 이슈 #40. 계약의 {@code GET /api/places/&#123;contentId&#125;} 다.
 *
 * <h2>허용목록을 먼저 통과해야 한다</h2>
 * <p>{@code pet_place_detail} 에 행이 <b>없는</b> {@code contentId} 는 아웃바운드 호출 없이
 * 404 다. 행은 셀 스냅샷을 저장할 때 함께 만들어지므로, "우리가 한 번이라도 목록에 실어
 * 보낸 장소" 만 상세를 받을 수 있다.
 *
 * <p>이게 없으면 <b>무작위 id 를 던지는 것만으로 상세 예산이 사라진다.</b> 상세 1건이
 * 2콜이므로 75번이면 하루치다.
 *
 * <h2>1건이 2콜이다</h2>
 * <p>{@code detailCommon2}(개요)와 {@code detailPetTour2}(반려동반 정보)를 각각 부른다.
 * 그래서 예산도 <b>2 단위</b>를 예약한다 — 1 로 잡으면 상한이 두 배로 무너진다.
 *
 * <h2>부분 성공을 부분으로 기록한다</h2>
 * <p>개요만 받고 반려동반 정보가 타임아웃 나면 <b>개요만</b> 시각을 찍는다. 시각이 하나면
 * 그 상태가 완전 성공과 구분되지 않아 30일 동안 눌어붙고, 사용자에게는 "이 장소는 동반
 * 정보가 없다" 로 보인다.
 *
 * <h2>{@code detailIntro2} 를 안 부른다</h2>
 * <p>앱의 상세 매퍼가 그 응답에서 쓰는 것은 <b>추가 이미지</b>뿐이다
 * ({@code useTime}·{@code parking} 등은 DTO 로 파싱만 되고 화면에 안 간다). 넣으면 1건이
 * 3콜이 되어 하루 상세가 75건에서 50건으로 준다. 계약의 {@code PlaceDetail} 도 그 필드를
 * 선언하지 않았다 — <b>갤러리 이미지가 줄어드는 것을 받아들인 결정</b>이고, 되돌리려면
 * 계약과 예산을 함께 고쳐야 한다.
 */
@Service
public class PlaceDetailService {

    /** 상세 1건이 내는 아웃바운드 호출 수. {@code detailCommon2 + detailPetTour2}. */
    static final int CALLS_PER_DETAIL = 2;

    private final PetPlaceDetailRepository details;
    private final KtoApiClient kto;
    private final KtoCallBudget budget;
    private final UpstreamGate gate;
    private final KtoBudgetProperties properties;
    private final PlaceDetailStore store;
    private final Clock clock;

    public PlaceDetailService(PetPlaceDetailRepository details,
                              KtoApiClient kto,
                              KtoCallBudget budget,
                              UpstreamGate gate,
                              KtoBudgetProperties properties,
                              PlaceDetailStore store,
                              Clock clock) {
        this.details = details;
        this.kto = kto;
        this.budget = budget;
        this.gate = gate;
        this.properties = properties;
        this.store = store;
        this.clock = clock;
    }

    /**
     * 이 장소의 상세.
     *
     * <p>기본 필드(제목·좌표·주소…)는 캐시 행이 든다 — 셀 스냅샷과 카탈로그(#273)가 목록에
     * 실은 장소마다 행을 만들어 두기 때문이다. 상세 응답이 계약의 {@code allOf: [Place, ...]} 라
     * 그 필드들이 함께 실려야 하는데, 부르는 쪽이 넘기게 하면 컨트롤러가 장소를 먼저
     * 찾아야 하고 그 조회가 두 번이 된다.
     *
     * <p>예전에는 행이 없을 때 감정 여행 시절의 {@code tour} 수집 표({@code places})를 한 번 더
     * 물었다 — 레거시 탐색 화면이 그 표의 id 로 상세에 들어왔기 때문이다. 그 화면과 표의 코드를
     * #94 로 지웠다(2026-09-06). v2 가 보내는 id 는 전부 목록·카탈로그를 거친 것이라 폴백이
     * 필요 없다.
     *
     * @return 우리가 모르는 {@code contentId} 면 비어 있다 — <b>아웃바운드 0콜로</b> 404 다
     */
    public Optional<PlaceDetailDto> detail(String contentId) {
        PetPlaceDetailRow row = details.findById(contentId).orElse(null);
        if (row == null) {
            // 허용목록 밖이다. 아웃바운드 0콜로 404 — 무작위 id 가 예산에 닿지 않는다.
            return Optional.empty();
        }
        if (isNegativeCached(row)) {
            return Optional.empty();
        }

        if (needsFetch(row)) {
            PetPlaceDetailRow refreshed = fetch(contentId, row);
            if (refreshed != null) {
                row = refreshed;
            }
        }

        // 아직 못 받았어도 200 이다. 기본 필드는 목록에서 왔으므로 화면이 뜬다 —
        // overview 가 null 이고 petInfo 의 세 필드가 null 일 뿐이다.
        return Optional.of(new PlaceDetailDto(
                base(row),
                row.getOverview(),
                new PetInfoDto(row.getAcmpyPsblCpam(), row.getAcmpyNeedMtr(), row.getEtcAcmpyInfo())));
    }

    /**
     * 계약의 {@code allOf: [Place, ...]} 중 {@code Place} 쪽.
     *
     * <p>{@code distM} 은 항상 {@code null} 이다 — 상세 경로에는 <b>기준점이 없다.</b>
     * 사용자가 어디서 이 장소를 눌렀는지 서버가 모른다.
     */
    private static PlaceDto base(PetPlaceDetailRow row) {
        String contentTypeId = row.getContentTypeId();
        return new PlaceDto(
                row.getContentId(),
                orElse(row.getTitle(), ""),
                PlaceDto.SOURCE_KTO,
                contentTypeId != null && PlaceDto.KNOWN_CATEGORIES.contains(contentTypeId)
                        ? contentTypeId : null,
                contentTypeId,
                row.getLat() != null ? row.getLat() : 0,
                row.getLng() != null ? row.getLng() : 0,
                orElse(row.getAddr(), ""),
                orElse(row.getTel(), null),
                orElse(row.getImage(), null),
                null);
    }

    private static String orElse(String value, String fallback) {
        return value != null && !value.isBlank() ? value : fallback;
    }

    // ─────────────────────────── 내부 ───────────────────────────

    /** KTO 가 모른다고 답했고, 그 기억이 아직 유효한가. */
    private boolean isNegativeCached(PetPlaceDetailRow row) {
        return row.getNotFoundAt() != null
                && row.getNotFoundAt().plusDays(properties.getNotFoundCacheDays())
                        .isAfter(LocalDateTime.now(clock));
    }

    /** 둘 중 하나라도 없거나 낡았으면 받아 온다. */
    private boolean needsFetch(PetPlaceDetailRow row) {
        LocalDateTime stale = LocalDateTime.now(clock).minusDays(properties.getDetailRefreshDays());
        return row.getCommonFetchedAt() == null || row.getCommonFetchedAt().isBefore(stale)
                || row.getPetFetchedAt() == null || row.getPetFetchedAt().isBefore(stale);
    }

    private PetPlaceDetailRow fetch(String contentId, PetPlaceDetailRow row) {
        return gate.runIfOwner("detail:" + contentId, () -> {
            // 1건이 2콜이다. 2 단위를 예약한다 — 1 로 잡으면 상한이 두 배로 무너진다.
            if (!budget.tryAcquire(KtoPool.DETAIL, CALLS_PER_DETAIL)) {
                return null;
            }

            KtoApiClient.Result<String> overview = kto.fetchOverview(contentId);
            KtoApiClient.Result<PetInfoDto> petInfo = kto.fetchPetInfo(contentId);

            closeIfQuotaOrKey(overview);
            closeIfQuotaOrKey(petInfo);

            // 둘 다 "정상인데 내용 없음" 이면 KTO 가 모르는 id 다. 음수 캐시에 남긴다.
            if (overview instanceof KtoApiClient.Result.Empty<String>
                    && petInfo instanceof KtoApiClient.Result.Empty<PetInfoDto>) {
                return store.markNotFound(contentId);
            }

            return store.merge(contentId, row, overview, petInfo);
        });
    }

    private void closeIfQuotaOrKey(KtoApiClient.Result<?> result) {
        if (result instanceof KtoApiClient.Result.Failed<?> failed
                && (KtoApiClient.RESULT_QUOTA_EXCEEDED.equals(failed.resultCode())
                    || KtoApiClient.RESULT_KEY_NOT_REGISTERED.equals(failed.resultCode()))) {
            budget.closeForToday(KtoPool.DETAIL, "resultCode=" + failed.resultCode());
        }
    }

    /**
     * 상세 캐시를 쓰는 자리.
     *
     * <p>{@link PlaceDetailService} 와 <b>다른 빈</b>인 이유는 {@link CellSnapshotStore} 와
     * 같다 — 자기 자신을 부르는 호출은 프록시를 안 거쳐서 {@code REQUIRES_NEW} 가 조용히
     * 안 걸린다.
     */
    @Service
    public static class PlaceDetailStore {

        private final PetPlaceDetailRepository details;
        private final Clock clock;

        public PlaceDetailStore(PetPlaceDetailRepository details, Clock clock) {
            this.details = details;
            this.clock = clock;
        }

        /**
         * 받아 온 것만 덮어쓴다.
         *
         * <p><b>실패한 쪽은 시각을 안 찍는다.</b> 찍으면 다음 요청이 "받은 것" 으로 보고
         * 다시 안 부른다 — 부분 성공이 30일 눌어붙는 경로가 그것이다.
         */
        @Transactional(propagation = Propagation.REQUIRES_NEW)
        public PetPlaceDetailRow merge(String contentId,
                                       PetPlaceDetailRow row,
                                       KtoApiClient.Result<String> overview,
                                       KtoApiClient.Result<PetInfoDto> petInfo) {
            LocalDateTime now = LocalDateTime.now(clock);
            PetPlaceDetailRow target = details.findById(contentId).orElse(row);

            if (overview instanceof KtoApiClient.Result.Ok<String> ok) {
                target.setOverview(ok.value());
                target.setCommonFetchedAt(now);
            } else if (overview instanceof KtoApiClient.Result.Empty<String>) {
                // KTO 가 "이 장소에 개요가 없다" 고 답한 것이다. 받은 것으로 친다 —
                // 안 그러면 개요 없는 장소를 30일마다 계속 다시 묻는다.
                target.setCommonFetchedAt(now);
            }

            if (petInfo instanceof KtoApiClient.Result.Ok<PetInfoDto> ok) {
                target.setAcmpyPsblCpam(ok.value().acmpyPsblCpam());
                target.setAcmpyNeedMtr(ok.value().acmpyNeedMtr());
                target.setEtcAcmpyInfo(ok.value().etcAcmpyInfo());
                target.setPetFetchedAt(now);
            } else if (petInfo instanceof KtoApiClient.Result.Empty<PetInfoDto>) {
                target.setPetFetchedAt(now);
            }

            target.setContentId(contentId);
            target.setNotFoundAt(null);
            return details.save(target);
        }

        /** KTO 가 모르는 id 로 기억해 둔다. 되돌아오는 값은 "없음" 을 뜻한다. */
        @Transactional(propagation = Propagation.REQUIRES_NEW)
        public PetPlaceDetailRow markNotFound(String contentId) {
            PetPlaceDetailRow row = details.findById(contentId)
                    .orElseGet(() -> PetPlaceDetailRow.builder().contentId(contentId).build());
            row.setNotFoundAt(LocalDateTime.now(clock));
            details.save(row);
            return null;
        }
    }
}
