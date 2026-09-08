package com.heattrip.heat_trip_backend.place.dto;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonInclude;

import java.util.Set;

/**
 * 계약({@code openapi.yaml})의 {@code Place} 모양 — 이슈 #40.
 *
 * <h2>{@link #category} 가 {@code null} 일 수 있다</h2>
 * <p>계약이 {@code PlaceCategory} 를 <b>닫힌 enum</b>(12·14·28·32·38·39·vet·shop·trail)으로
 * 선언했는데, KTO 는 그 여섯 밖의 {@code contenttypeid} 를 줄 수 있다. 모르는 값을 그대로
 * 실으면 <b>계약을 깨는 응답</b>이 되고, 아무 값으로 눕히면 화면이 엉뚱한 아이콘을 그린다.
 *
 * <p>그래서 모르면 <b>필드를 생략</b>한다({@code JsonInclude.NON_NULL}). 앱은 이미
 * {@code petCatByType} 로 모르는 값을 "기타" 로 폴백하므로 화면이 깨지지 않는다.
 *
 * <p>{@link #contentTypeId} 는 KTO 값을 <b>그대로</b> 싣는다 — 계약이 자유 문자열이고,
 * 앱의 카테고리 필터가 이 값으로 비교한다. <b>KTO 가 아닌 출처에서는 {@code null}</b> 이고
 * 그때 앱이 보는 것은 {@link #category} 다({@link #categoryKey()} — #291).
 *
 * <h2>출처가 넷이다 (#291)</h2>
 * <p>{@code kto} 하나였던 {@link #source} 에 {@code vet}·{@code shop}(행정안전부 인허가)·
 * {@code trail}(두루누비)이 붙었다. 그 셋은 {@code source} 와 {@code category} 가 같은 값이고
 * {@code contentId} 가 {@code 출처:원본키} 다 — KTO 의 숫자 키와 겹치지 않게.
 *
 * <h2>{@link #distM} 은 캐시에 안 들어간다</h2>
 * <p>거리는 <b>묻는 사람의 좌표</b>에 따라 달라진다. 셀 스냅샷은 셀 중심에서 받은 것이라
 * 그때의 거리를 그대로 실으면 같은 셀의 모든 사용자가 같은 거리를 본다. 서빙 시점에
 * 사용자 실좌표로 다시 계산한다.
 *
 * <h2>{@link #summary} — 산책로의 한 줄</h2>
 * <p>"12.3km · 약 4시간 · 보통" 처럼 카드에 그대로 얹는 문장이다. KTO 항목에는 없다
 * ({@code null} 이라 생략된다). 판매업은 상세 업무 구분(동물판매업/동물미용업)이 여기 온다.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record PlaceDto(
        String contentId,
        String title,
        String source,
        String category,
        String contentTypeId,
        double lat,
        double lng,
        String addr,
        String tel,
        String image,
        Double distM,
        String summary) {

    /** 관광공사 반려동반 장소. {@code contentId} 가 KTO 의 {@code contentid} 그대로다. */
    public static final String SOURCE_KTO = "kto";

    /** 동물병원 — 행정안전부 인허가(#291). {@code contentId} = {@code vet:관리번호}. */
    public static final String SOURCE_VET = "vet";

    /** 동물판매업(펫샵) — 행정안전부 인허가(#291). {@code contentId} = {@code shop:관리번호}. */
    public static final String SOURCE_SHOP = "shop";

    /** 산책로 — 두루누비 걷기여행길(#291)과 동네 길(#346). {@code contentId} = {@code trail:…}. */
    public static final String SOURCE_TRAIL = "trail";

    /**
     * 반려견 놀이터 — 지자체 현황(#346). {@code contentId} = {@code playground:해시}.
     *
     * <p>다른 레이어와 달리 <b>전국 표준데이터가 없다.</b> 시·군·구가 각자 올린 파일을
     * 모아 자산으로 만든다({@code backend/tools/build_playgrounds.py}).
     */
    public static final String SOURCE_PLAYGROUND = "playground";

    /**
     * KTO 가 아닌 출처 — 계약 {@code PlaceCategory} 의 문자 값 셋과 같다. 이 값이 {@code category}
     * 로 오면 서버는 KTO 셀을 부르지 않고 레이어 한 벌에서 거른다({@code PlaceQueryService}).
     */
    public static final Set<String> LAYER_SOURCES =
            Set.of(SOURCE_VET, SOURCE_SHOP, SOURCE_TRAIL, SOURCE_PLAYGROUND);

    /**
     * 계약의 {@code PlaceCategory} 가 아는 KTO 콘텐츠타입 — 이슈 #210({@code Places-low-1}).
     *
     * <p><b>이 목록 밖의 값이 오면 {@code category} 를 생략한다.</b> 필드를 빼면
     * {@code @JsonInclude(NON_NULL)} 이 통째로 지우므로 닫힌 enum 을 위반하지 않는다.
     * 원래 값은 {@code contentTypeId} 에 그대로 남는다. KTO 체계에는 15·25 도 있지만
     * 이 앱의 필터 칩에 없어서 뺐다.
     *
     * <p><b>사본이 셋이었다.</b> {@code KtoApiClient}·{@code PlaceDetailService} 가 각자 들고
     * 계약이 또 들고 있었다. 여기로 모으고, 계약과 같은 집합인지는
     * {@code PlacesContractSpecTest} 가 잰다 — 셋이 갈리면 KTO 가 준 값을 서버가 실어
     * 보내고 앱이 라벨을 못 찾는다.
     */
    public static final Set<String> KNOWN_CATEGORIES = Set.of("12", "14", "28", "32", "38", "39");

    /** Jackson 이 <b>이 생성자</b>로 읽게 한다 — 아래 편의 생성자와 헷갈리지 않도록. */
    @JsonCreator
    public PlaceDto {
    }

    /** KTO 항목의 편의 생성자 — {@code summary} 가 없다. 호출부 열 곳을 안 바꾸려고 남긴다. */
    public PlaceDto(String contentId, String title, String source, String category,
                    String contentTypeId, double lat, double lng, String addr,
                    String tel, String image, Double distM) {
        this(contentId, title, source, category, contentTypeId, lat, lng, addr, tel, image, distM, null);
    }

    /**
     * 앱의 필터·아이콘이 보는 값 — KTO 면 {@code contentTypeId}, 아니면 {@code category}.
     *
     * <p>앱({@code PetPlace.categoryKey})과 같은 규칙이다. 갈리면 서버가 거른 것과 앱이 그리는
     * 것이 다른 칩이 된다.
     */
    public String categoryKey() {
        return contentTypeId != null ? contentTypeId : category;
    }

    /** KTO 가 아닌 출처인가 — 상세 경로({@code /api/places/{contentId}})가 없다. */
    public boolean isLayer() {
        return LAYER_SOURCES.contains(source);
    }

    /** 거리를 채운 사본. 캐시에서 꺼낸 뒤 서빙 직전에 부른다. */
    public PlaceDto withDistance(double meters) {
        return new PlaceDto(contentId, title, source, category, contentTypeId,
                lat, lng, addr, tel, image, meters, summary);
    }
}
