package com.heattrip.heat_trip_backend.walk.repository;

import com.heattrip.heat_trip_backend.walk.entity.Walk;

import org.springframework.data.domain.Limit;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

/**
 * {@code walk} 조회 — 이슈 #145.
 *
 * <h2>소유자 조건이 전부 쿼리 안에 있다</h2>
 * <p>{@code findById} 로 가져와 나중에 비교하면 "없는 것" 과 "남의 것" 을 가르는 분기가
 * 생기고, 그 분기는 결국 응답 코드로 샌다. 여기서는 둘이 똑같이 {@code Optional.empty()} 이고
 * 부르는 쪽은 404 하나만 안다.
 *
 * <p>산책에는 사용자 컬럼이 없다 — {@code walk → dog → users} 를 탄다. 컬럼을 따로 두면
 * 그 둘이 어긋나는 날이 온다.
 *
 * <h2>모든 시각 파라미터는 UTC 다</h2>
 * <p>{@code Walk} javadoc 참조. 주 경계는 <b>Java 에서 만들어</b> 넘긴다 — MySQL 의
 * {@code WEEKDAY()}·{@code CURDATE()} 는 세션 시간대를 읽고, 그 값을 믿을 수 없다
 * (#40 에서 같은 함정이 00:00–09:00 KST 에만 터졌다).
 */
public interface WalkRepository extends JpaRepository<Walk, Long> {

    /**
     * 목록 첫 장. 정렬은 {@code (createdAt, id)} 내림차순이다 — {@code startedAt} 이 아니다.
     *
     * <p>{@code dogId} 가 {@code null} 이면 내 반려동물 전체를 섞는다.
     *
     * <p><b>{@code limit + 1} 을 읽어서 {@code hasMore} 를 정한다.</b> 별도 {@code count}
     * 쿼리를 돌리지 않는 이유는 그 값이 다음 장을 여는 사이에 바뀔 수 있고, 두 번 읽는
     * 비용이 한 줄 더 읽는 비용보다 크기 때문이다({@code ChatRoomService} 와 같은 방식).
     */
    @Query("""
            select w from Walk w
              join fetch w.dog d
             where d.user.id = :userId
               and (:dogId is null or d.id = :dogId)
             order by w.createdAt desc, w.id desc
            """)
    List<Walk> findPage(@Param("userId") long userId,
                        @Param("dogId") Long dogId,
                        Limit limit);

    /**
     * 목록 다음 장. 커서보다 <b>엄격히 뒤</b>인 것만 준다.
     *
     * <p>{@code createdAt} 이 같은 두 행이 있을 수 있어서 {@code id} 로 한 번 더 가른다.
     * 그게 없으면 같은 시각의 행들이 장 경계에서 <b>중복되거나 건너뛰어진다.</b>
     */
    @Query("""
            select w from Walk w
              join fetch w.dog d
             where d.user.id = :userId
               and (:dogId is null or d.id = :dogId)
               and (w.createdAt < :cursorAt
                    or (w.createdAt = :cursorAt and w.id < :cursorId))
             order by w.createdAt desc, w.id desc
            """)
    List<Walk> findPageAfter(@Param("userId") long userId,
                             @Param("dogId") Long dogId,
                             @Param("cursorAt") LocalDateTime cursorAt,
                             @Param("cursorId") long cursorId,
                             Limit limit);

    /** 상세. 남의 것과 없는 것이 똑같이 비어 있다. */
    @Query("""
            select w from Walk w
              join fetch w.dog d
             where w.id = :walkId and d.user.id = :userId
            """)
    Optional<Walk> findMineById(@Param("walkId") long walkId, @Param("userId") long userId);

    /**
     * 멱등키로 찾는다. 재전송이면 이 행을 그대로 돌려준다.
     *
     * <p>소유자 조건이 함께 있는 이유: 키는 앱이 만든 UUID 라 <b>남의 키를 찍어 볼 수</b>
     * 있다. 없으면 남의 산책이 200 으로 새어 나간다.
     */
    @Query("""
            select w from Walk w
              join fetch w.dog d
             where d.id = :dogId and w.clientWalkId = :clientWalkId and d.user.id = :userId
            """)
    Optional<Walk> findByClientKey(@Param("dogId") long dogId,
                                   @Param("clientWalkId") String clientWalkId,
                                   @Param("userId") long userId);

    /**
     * 한 주치 원본 행. 요일별로 접는 것은 <b>Java 가</b> 한다.
     *
     * <p>{@code group by WEEKDAY(...)} 로 DB 에 맡기지 않는 이유는 클래스 javadoc 에 있다.
     * 한 사람의 일주일치는 수십 행이라 끌어와도 싸다.
     */
    @Query("""
            select w from Walk w
             where w.dog.user.id = :userId
               and (:dogId is null or w.dog.id = :dogId)
               and w.startedAt >= :fromUtc and w.startedAt < :toUtc
            """)
    List<Walk> findStartedBetween(@Param("userId") long userId,
                                  @Param("dogId") Long dogId,
                                  @Param("fromUtc") LocalDateTime fromUtc,
                                  @Param("toUtc") LocalDateTime toUtc);

    /**
     * 전체 기간 집계. 행을 끌어오지 않는다 — 몇 년치가 될 수 있다.
     *
     * <p>{@code Object[]} 로 받지 않는다 — {@link WalkTotals} javadoc 참조(실측으로 500 이
     * 났던 자리다).
     */
    @Query("""
            select new com.heattrip.heat_trip_backend.walk.repository.WalkTotals(
                       coalesce(sum(w.distanceM), 0L),
                       count(w),
                       coalesce(sum(w.durationS), 0L))
              from Walk w
             where w.dog.user.id = :userId
               and (:dogId is null or w.dog.id = :dogId)
            """)
    WalkTotals sumAllTime(@Param("userId") long userId, @Param("dogId") Long dogId);

    /** 삭제. 소유자 조건이 안에 있어서 남의 산책은 0행이 지워진다. */
    @Query("""
            delete from Walk w
             where w.id = :walkId
               and w.dog.id in (select d.id from Dog d where d.user.id = :userId)
            """)
    @org.springframework.data.jpa.repository.Modifying
    int deleteMine(@Param("walkId") long walkId, @Param("userId") long userId);
}
