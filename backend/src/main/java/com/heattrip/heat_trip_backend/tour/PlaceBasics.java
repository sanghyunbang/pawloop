package com.heattrip.heat_trip_backend.tour;

/**
 * 적재된 장소 하나의 기본 필드 — 이슈 #40. <b>{@code tour} 모듈의 공개 표면이다.</b>
 *
 * <p>{@code place} 프록시가 상세를 만들 때 제목·좌표·주소가 필요한데, 그 값들은
 * {@code places} 표에 이미 있다. 표를 남이 직접 읽으면 그건 공용 어휘가 아니라 그냥 새는
 * 것이라({@code backend-implementation-guide.md} §2.3) {@code tour} 가 <b>질문에 답하는
 * 모양</b>을 하나 내준다.
 *
 * <p>엔티티({@code tour.domain.Place})를 그대로 내보내지 않는 이유: 그건 하위 패키지라
 * 모듈 경계 밖에서 부르면 위반이고, 무엇보다 <b>적재 배치의 내부 사정</b>(cat1/cat2/
 * search_text/areacode…)이 프록시의 계약에 묻어 나온다.
 */
public record PlaceBasics(
        String contentId,
        String title,
        String addr,
        String tel,
        String image,
        double lat,
        double lng,
        String contentTypeId) {
}
