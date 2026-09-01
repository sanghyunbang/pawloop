package com.heattrip.heat_trip_backend.dog.repository;

import com.heattrip.heat_trip_backend.dog.entity.Dog;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

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
             order by d.id asc
            """)
    List<Dog> findMine(@Param("userId") long userId);

    @Query("""
            select d from Dog d
              join fetch d.user
             where d.id = :dogId and d.user.id = :userId
            """)
    Optional<Dog> findMineById(@Param("dogId") long dogId, @Param("userId") long userId);

    /**
     * 그 사용자의 반려동물인가. 산책 저장이 {@code dogId} 를 받을 때 쓴다 — 행 전체를
     * 끌어올 이유가 없다.
     */
    @Query("select count(d) > 0 from Dog d where d.id = :dogId and d.user.id = :userId")
    boolean isMine(@Param("dogId") long dogId, @Param("userId") long userId);
}
