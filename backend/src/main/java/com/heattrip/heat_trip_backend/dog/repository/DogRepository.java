package com.heattrip.heat_trip_backend.dog.repository;

import com.heattrip.heat_trip_backend.dog.entity.Dog;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Collection;
import java.util.List;
import java.util.Optional;

/**
 * {@code dog} 조회 — 이슈 #145.
 *
 * <p>공간 쿼리도 네이티브 쿼리도 없다. 이 표에 좌표가 없다.
 *
 * <p>소유자 조건을 <b>쿼리 안</b>에 두는 것이 이 인터페이스의 규칙이다. {@code findById} 로
 * 가져와 나중에 비교하면 "없는 것" 과 "남의 것" 을 가르는 분기가 생기고, 그 분기는 결국
 * 응답 코드로 샌다. 여기서는 둘이 똑같이 {@code Optional.empty()} 다.
 */
public interface DogRepository extends JpaRepository<Dog, Long> {

    // 세 쿼리 전부 `deletedAt is null` 을 건다(#156). 하나만 빠져도 지운 아이가 어딘가에서
    // 되살아난다 — 목록에는 없는데 상세는 열리거나, 상세는 404 인데 산책은 저장되는 식으로.
    // DogIntegrationTest 가 세 경로(목록·상세·소유권)를 각각 잰다.

    /**
     * 내 반려동물 목록. 등록순이다 — 앱이 첫 마리를 기본 선택으로 쓴다.
     *
     * <p>{@code join fetch} 로 주인을 함께 끌어온다. 없으면 {@code user} 가 지연 로딩이라
     * 목록 크기만큼 {@code users} 왕복이 붙는다({@code WalkNoteRepository} 와 같은 이유).
     */
    @Query("""
            select d from Dog d
              join fetch d.user
             where d.user.id = :userId
               and d.deletedAt is null
             order by d.id asc
            """)
    List<Dog> findMine(@Param("userId") long userId);

    @Query("""
            select d from Dog d
              join fetch d.user
             where d.id = :dogId and d.user.id = :userId
               and d.deletedAt is null
            """)
    Optional<Dog> findMineById(@Param("dogId") long dogId, @Param("userId") long userId);

    /**
     * 이 사람들이 등록한 아이 전부 — <b>집 아이</b>를 구하는 자리다(#563).
     *
     * <p>정렬이 {@code (user.id, id)} 인 이유는 <b>한 사람의 아이들이 흩어지지 않게</b> 하려는
     * 것이다. 홈의 아이 스위처가 이 순서로 그려지는데, 엄마 아이 · 아빠 아이 · 엄마 아이 로
     * 섞이면 누구 아이인지 읽는 데 매번 이름을 봐야 한다.
     *
     * <p>빈 목록을 주면 빈 결과다 — {@code in ()} 은 DB 마다 다르게 죽으므로 부르는 쪽이
     * 먼저 거른다({@code DogService.ofFamily}).
     */
    @Query("""
            select d from Dog d
              join fetch d.user
             where d.user.id in :userIds
               and d.deletedAt is null
             order by d.user.id asc, d.id asc
            """)
    List<Dog> findOfUsers(@Param("userIds") Collection<Long> userIds);

    /**
     * 그 사용자의 반려동물인가. 산책 저장이 {@code dogId} 를 받을 때 쓴다 — 행 전체를
     * 끌어올 이유가 없다.
     */
    @Query("select count(d) > 0 from Dog d where d.id = :dogId and d.user.id = :userId and d.deletedAt is null")
    boolean isMine(@Param("dogId") long dogId, @Param("userId") long userId);
}
