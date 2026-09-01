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
}
