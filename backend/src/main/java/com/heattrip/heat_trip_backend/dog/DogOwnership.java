package com.heattrip.heat_trip_backend.dog;

import com.heattrip.heat_trip_backend.dog.entity.Dog;

/**
 * "이 반려동물이 그 사람의 것인가" — {@code dog} 모듈이 밖으로 내놓는 <b>유일한 판정</b>이다.
 * 이슈 #145.
 *
 * <h2>왜 {@code DogService} 를 그대로 열지 않는가</h2>
 * <p>{@code walk} 가 필요한 것은 소유권 판정 하나다. {@code DogService} 를 통째로 열면
 * {@code register}·{@code mine}·{@code one} 까지 따라 나가고, 그러면 다음 사람이 산책
 * 코드에서 반려동물을 <b>등록</b>할 수도 있게 된다. 필요한 만큼만 연다.
 *
 * <p>모듈 패키지 <b>바로 아래</b> 타입은 Spring Modulith 가 공개 표면으로 본다. 그래서 이
 * 인터페이스에는 애너테이션이 없다 — {@code dog.entity.Dog} 가 하위 패키지라
 * {@code @NamedInterface("entity")} 를 따로 붙여야 했던 것과 대비된다.
 * ({@code tour/KnownPlaceIds}·{@code tour/PlaceBasics} 가 같은 방식으로 만들어졌다.)
 *
 * <h2>판정이 한 곳에 있어야 한다</h2>
 * <p>{@code walk} 가 {@code DogRepository} 를 직접 부르게 두면 소유권 판정이 두 곳에 생기고,
 * <b>한쪽만 고쳐지는 날이 온다.</b> 남의 반려동물에 산책을 붙일 수 있게 되는 것이 그 날의
 * 모습이다.
 *
 * <h2>왜 "내 아이" 판정이 여기 없나</h2>
 * <p>#563 이 아이를 <b>집</b>의 것으로 옮기면서 밖에서 부르던 {@code requireMine} —
 * {@code requireMineEntity} 를 지웠다. 둘을 남겨 두면 다음 사람이 그쪽을 집고, 그러면
 * 판정이 다시 두 벌이 된다 — 실제로 그 날이 하루에 두 번 왔다(주간 통계 404 · 일정 404).
 *
 * <p>"등록한 사람만" 이 맞는 일(아이 정보 고치기 — 지우기)은 {@code dog} 모듈 <b>안에서</b>
 * 끝난다. 밖으로 낼 이유가 없다.
 */
public interface DogOwnership {

    /**
     * <b>그 집 아이</b>를 꺼낸다 — 이슈 #563. 아니면 <b>400</b>.
     *
     * <p><b>누구 것인지 안 따진다.</b> 엄마가
     * 등록한 보리에게 아빠가 물을 줄 수 있어야 한다 — 그게 이 앱의 목적(업무 분담)이다.
     *
     * <p><b>인가를 하지 않는다.</b> 부르는 쪽이 이미 "그 그룹의 식구인가" 를 지났다는 전제다
     * ({@code CareService.requireMemberGroup}). 여기서 한 번 더 보면 같은 판정이 두 곳에
     * 생기고, 그때부터 한쪽만 고쳐지는 날을 기다리게 된다.
     *
     * <p>404 가 아니라 400 인 이유: 여기까지 온 요청은 <b>그 가족의 식구</b>가 보낸 것이고,
     * 그 집 아이 목록은 이미 {@code GET /api/groups/&#123;id&#125;/dogs} 로 볼 수 있다. 숨길
     * 것이 없으므로 "잘못된 입력" 이라고 말해 주는 편이 낫다.
     *
     * @throws org.springframework.web.server.ResponseStatusException 그 집 아이가 아니면 400
     */
    Dog requireInFamilyEntity(long groupId, Long dogId);

    /**
     * <b>우리 집 아이</b>를 꺼낸다 — 그룹이 아니라 <b>사람</b> 기준이다. 이슈 #563.
     *
     * <p>산책은 그룹 경로가 아니다({@code POST /api/walks}). 부르는 쪽이 그룹 id 를 모르므로
     * 여기서 {@code FamilyMembership.householdUserIds} 로 집을 찾는다 — 가족이 없으면 자기
     * 아이만이라, 1인 사용자에게는 "내 아이인가" 와 똑같이 동작한다.
     *
     * <p>404 다(400 이 아니다). 산책 저장은 <b>그룹 안에서 벌어지는 일이 아니라</b> 내 요청이고,
     * 여기서 400 을 주면 "그 id 는 있다" 를 알려 주는 셈이 된다 — {@code requireMineEntity} 와
     * 같은 규칙을 지킨다.
     *
     * @throws org.springframework.web.server.ResponseStatusException 우리 집 아이가 아니면 404
     */
    Dog requireInHouseholdEntity(long actorUserId, Long dogId);

    /**
     * 우리 집 아이가 맞는지만 확인한다. 행이 필요 없을 때 쓴다.
     *
     * @throws org.springframework.web.server.ResponseStatusException 아니면 404
     */
    void requireInHousehold(long actorUserId, long dogId);

    /**
     * <b>우리 집</b> 아이 id 전부 — 이슈 #418 이 더했고 #563 이 집 기준으로 넓혔다.
     * 지운 아이는 안 들어간다(#156). 가족이 없으면 자기 아이만이라 1인 사용자는 전과 같다.
     *
     * <p><b>왜 여기인가.</b> 일정표의 기본이 "합쳐 보기" 다 — 아이들 것과 우리 가족 것이
     * 한 목록으로 나온다. 그러려면 "우리 집 아이가 누구누구인가" 를 물어야 하는데,
     * {@code DogRepository} 를 직접 부르면 소유권 판정이 두 곳에 생긴다 — 이 인터페이스의
     * 클래스 javadoc 이 경계하는 것이 정확히 그것이다.
     *
     * <p>{@code DogResponse} 목록을 주는 조회는 이미 있지만 그것은 화면용 모양이다. 여기
     * 필요한 것은 <b>id 뿐</b>이라, 이름·품종까지 실어 나르지 않는다.
     */
    java.util.List<Long> householdDogIds(long actorUserId);

    /**
     * 아이의 크기 · 나이대만(#486). [dogId] 가 있으면 그 아이, 없으면 <b>우리 집</b> 첫째 아이.
     * 집에 아이가 하나도 없으면 null.
     *
     * <p><b>우리 집 기준이다</b>(#563) — {@link #requireInHouseholdEntity} 와 같은 범위다.
     * 이 값을 읽는 주간 통계가 이미 집 산책을 세므로, 여기만 "내가 등록한 아이인가" 로 두면
     * 아빠가 엄마의 보리를 고른 순간 통계 전체가 404 로 죽는다.
     *
     * @throws org.springframework.web.server.ResponseStatusException 우리 집 아이가 아니면 404
     */
    DogProfileView profileOf(long userId, Long dogId);
}
