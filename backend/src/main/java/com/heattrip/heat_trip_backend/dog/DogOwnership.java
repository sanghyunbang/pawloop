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
 */
public interface DogOwnership {

    /**
     * 내 반려동물이 맞는지 확인한다. 행이 필요 없을 때 쓴다.
     *
     * @throws org.springframework.web.server.ResponseStatusException 아니면 <b>404</b>.
     *         403 이 아닌 이유는 "그 id 는 존재한다" 를 알려 주지 않기 위해서다
     */
    void requireMine(Long userId, long dogId);

    /**
     * 내 반려동물을 꺼낸다.
     *
     * <p>행을 돌려주는 이유는 {@code Walk} 가 {@code @ManyToOne Dog} 를 <b>들어야</b>
     * Hibernate 가 {@code fk_walk_dog} 를 만들기 때문이다. 스칼라 {@code Long} 으로 두면
     * {@code 01_schema.sql} 재생성 때 그 FK 가 조용히 사라진다.
     *
     * @param dogId {@code null} 이면 404 다 — 계약이 필수로 선언했고, 여기까지 온 이상
     *              "안 보냈다" 와 "없는 id" 를 나눌 이유가 없다
     * @throws org.springframework.web.server.ResponseStatusException 내 것이 아니면 404
     */
    Dog requireMineEntity(Long userId, Long dogId);

    /**
     * <b>그 집 아이</b>를 꺼낸다 — 이슈 #563. 아니면 <b>400</b>.
     *
     * <p>{@link #requireMineEntity} 와 다른 점은 <b>누구 것인지 안 따진다</b>는 것이다. 엄마가
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
     * 아이만이라, 1인 사용자에게는 {@link #requireMineEntity} 와 똑같이 동작한다.
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
     * 이 사람의 아이 id 전부 — 이슈 #418 이 이 표면에 더했다. 지운 아이는 안 들어간다(#156).
     *
     * <p><b>왜 여기인가.</b> 일정표의 기본이 "합쳐 보기" 다 — 내 아이들 것과 우리 가족 것이
     * 한 목록으로 나온다. 그러려면 "내 아이가 누구누구인가" 를 물어야 하는데,
     * {@code DogRepository} 를 직접 부르면 소유권 판정이 두 곳에 생긴다({@link #requireMine}
     * 의 javadoc 이 경계하는 것이 정확히 그것이다).
     *
     * <p>{@code DogResponse} 목록을 주는 조회는 이미 있지만 그것은 화면용 모양이다. 여기
     * 필요한 것은 <b>id 뿐</b>이라, 이름·품종까지 실어 나르지 않는다.
     */
    java.util.List<Long> myDogIds(long userId);

    /**
     * 아이의 크기 · 나이대만(#486). [dogId] 가 있으면 그 아이(내 아이가 아니면 404), 없으면 첫째 아이.
     * 아이가 없으면 null.
     */
    DogProfileView profileOf(long userId, Long dogId);
}
