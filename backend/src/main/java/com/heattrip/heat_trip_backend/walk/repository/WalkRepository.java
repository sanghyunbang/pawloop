package com.heattrip.heat_trip_backend.walk.repository;

import com.heattrip.heat_trip_backend.walk.entity.Walk;

import org.springframework.data.domain.Limit;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.Collection;
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

    /*
     * ── 아이별 조회는 walk.dog_id 가 아니라 walk_dog 를 본다 (#343) ──────────────
     *
     * 한 번의 산책에 여러 마리가 들어올 수 있게 되면서, `w.dog.id = :dogId` 는 **두 번째
     * 이후 아이의 산책을 통째로 빠뜨린다.** 초코와 보리를 함께 데리고 나간 산책은
     * `walk.dog_id` 가 보리 하나뿐이라, 초코의 통계에서 그 산책이 사라진다.
     *
     * 그래서 `exists (walk_dog)` 로 묻는다. 대표 아이도 그 표에 한 줄 들어 있으므로
     * (`33_walk_dog.sql` 이 기존 기록까지 채운다) 한 마리짜리 산책도 그대로 나온다.
     *
     * **`findByClientKey` 만 예외다.** 그것은 멱등키 `uq_walk_client (dog_id, client_walk_id)`
     * 를 찾는 자리라 `walk.dog_id` 그대로여야 한다 — 이음매로 바꾸면 함께 나간 다른 아이의
     * id 로도 같은 산책이 잡혀, 재전송이 아닌 것을 재전송으로 본다.
     *
     * ── `w.dog.id = :dogId or exists(...)` 인 이유 ─────────────────────
     *
     * 이음매만 보면 **이음매가 없는 산책이 통째로 사라진다.** 배포 순서가 그 창을 연다:
     * 마이그레이션을 먼저 돌리고(문서가 그렇게 적었다) 새 코드를 배포하기 전까지, 옛 코드가
     * 저장한 산책에는 이음매 행이 없다. 그 산책은 대표 아이의 통계에서도 영영 안 보인다 —
     * **오류 없이** 조용히.
     *
     * 실제로 겪었다. 개발 서버가 옛 빌드로 떠 있는 줄 모르고 산책을 하나 저장했더니,
     * `walk` 에는 있고 `walk_dog` 에는 없는 행이 생겼다.
     *
     * 대표 아이 조건을 함께 두면 그 창이 닫힌다. 자료가 온전할 때는 **아무것도 더 잡지
     * 않는다** — 대표 아이는 어차피 이음매에도 한 줄 있다.
     */

    /**
     * 목록 첫 장. 정렬은 {@code (createdAt, id)} 내림차순이다 — {@code startedAt} 이 아니다.
     *
     * <p>{@code dogId} 가 {@code null} 이면 <b>우리 집 아이 전체</b>를 섞는다(#563).
     * 예전에는 "내가 등록한 아이" 였다 — 그 상태에서는 아빠가 엄마 아이 보리를 산책시켜도
     * 아빠 목록에 안 보였다. 업무 분담이 목적인 앱에서 그건 화면이 거짓말하는 것이다.
     *
     * <p><b>{@code limit + 1} 을 읽어서 {@code hasMore} 를 정한다.</b> 별도 {@code count}
     * 쿼리를 돌리지 않는 이유는 그 값이 다음 장을 여는 사이에 바뀔 수 있고, 두 번 읽는
     * 비용이 한 줄 더 읽는 비용보다 크기 때문이다({@code ChatRoomService} 와 같은 방식).
     */
    @Query("""
            select w from Walk w
              join fetch w.dog d
              left join fetch w.walkedBy
             where d.user.id in :householdIds
               and (:dogId is null or w.dog.id = :dogId or exists (
                    select 1 from WalkDog wd where wd.walk = w and wd.dog.id = :dogId))
             order by w.createdAt desc, w.id desc
            """)
    List<Walk> findPage(@Param("householdIds") Collection<Long> householdIds,
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
             where d.user.id in :householdIds
               and (:dogId is null or w.dog.id = :dogId or exists (
                    select 1 from WalkDog wd where wd.walk = w and wd.dog.id = :dogId))
               and (w.createdAt < :cursorAt
                    or (w.createdAt = :cursorAt and w.id < :cursorId))
             order by w.createdAt desc, w.id desc
            """)
    List<Walk> findPageAfter(@Param("householdIds") Collection<Long> householdIds,
                             @Param("dogId") Long dogId,
                             @Param("cursorAt") LocalDateTime cursorAt,
                             @Param("cursorId") long cursorId,
                             Limit limit);

    /** 상세 — <b>우리 집 아이의 산책</b>이면 보인다(#563). 남의 집 것과 없는 것이 똑같이 비어 있다. */
    @Query("""
            select w from Walk w
              join fetch w.dog d
             where w.id = :walkId and d.user.id in :householdIds
            """)
    Optional<Walk> findInHouseholdById(@Param("walkId") long walkId, @Param("householdIds") Collection<Long> householdIds);

    /**
     * 멱등키로 찾는다. 재전송이면 이 행을 그대로 돌려준다.
     *
     * <p>소유자 조건이 함께 있는 이유: 키는 앱이 만든 UUID 라 <b>남의 키를 찍어 볼 수</b>
     * 있다. 없으면 남의 산책이 200 으로 새어 나간다.
     */
    @Query("""
            select w from Walk w
              join fetch w.dog d
             where d.id = :dogId and w.clientWalkId = :clientWalkId and d.user.id in :householdIds
            """)
    Optional<Walk> findByClientKey(@Param("dogId") long dogId,
                                   @Param("clientWalkId") String clientWalkId,
                                   @Param("householdIds") Collection<Long> householdIds);

    /**
     * 한 주치 원본 행. 요일별로 접는 것은 <b>Java 가</b> 한다.
     *
     * <p>{@code group by WEEKDAY(...)} 로 DB 에 맡기지 않는 이유는 클래스 javadoc 에 있다.
     * 한 사람의 일주일치는 수십 행이라 끌어와도 싸다.
     */
    @Query("""
            select w from Walk w
             where w.dog.user.id in :householdIds
               and (:dogId is null or w.dog.id = :dogId or exists (
                    select 1 from WalkDog wd where wd.walk = w and wd.dog.id = :dogId))
               and w.startedAt >= :fromUtc and w.startedAt < :toUtc
            """)
    List<Walk> findStartedBetween(@Param("householdIds") Collection<Long> householdIds,
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
             where w.dog.user.id in :householdIds
               and (:dogId is null or w.dog.id = :dogId or exists (
                    select 1 from WalkDog wd where wd.walk = w and wd.dog.id = :dogId))
            """)
    WalkTotals sumAllTime(@Param("householdIds") Collection<Long> householdIds, @Param("dogId") Long dogId);

    /**
     * 자주 간 곳 — 이슈 #338.
     *
     * <p><b>카탈로그에서 고른 곳만 센다.</b> 손으로 적은 이름은 계약의 {@code PlaceRef} 를
     * 만들 수 없어(출처·id 가 없다) 여기 안 들어간다. 그래서 세 컬럼이 모두 있는 행만 본다.
     *
     * <p>묶는 기준이 이름이 아니라 {@code (source, contentId)} 인 이유는 {@link TopPlaceRow}
     * 에 적었다. 같은 횟수면 이름순으로 갈라 <b>순서가 매번 달라지지 않게</b> 한다 —
     * 흔들리는 목록은 사용자가 "내가 뭘 잘못 눌렀나" 로 읽는다.
     */
    @Query("""
            select new com.heattrip.heat_trip_backend.walk.repository.TopPlaceRow(
                       w.placeSource, w.placeContentId, max(w.placeName), count(w))
              from Walk w
             where w.dog.user.id in :householdIds
               and (:dogId is null or w.dog.id = :dogId or exists (
                    select 1 from WalkDog wd where wd.walk = w and wd.dog.id = :dogId))
               and w.placeSource is not null
               and w.placeContentId is not null
               and w.placeName is not null
             group by w.placeSource, w.placeContentId
             order by count(w) desc, max(w.placeName) asc
            """)
    List<TopPlaceRow> topPlaces(@Param("householdIds") Collection<Long> householdIds,
                                @Param("dogId") Long dogId,
                                Limit limit);

    /**
     * 삭제 — <b>걸은 사람이거나 아이 주인</b>만. 조건이 안에 있어서 남의 산책은 0행이 지워진다.
     *
     * <p>보기는 집 전체인데 지우기는 왜 좁은가(#563): <b>공유되는 것은 돌봄이지 남의 기록이
     * 아니다.</b> 아빠가 걸은 경로와 회고를 엄마가 지울 수 있으면, 분담을 보이게 하려던 화면이
     * 서로의 기록을 지우는 자리가 된다. 케어 로그도 같은 규칙이다 — 길게 눌러 지우는 것은
     * 내 기록뿐이다(#209).
     *
     * <p>아이 주인을 함께 두는 이유는 <b>주인 없는 행을 막기 위해서</b>다. 걸은 사람이
     * 탈퇴하면 {@code walked_by} 가 {@code NULL} 이 되는데, 그때 아무도 못 지우면 그 행은
     * 영원히 남는다.
     */
    @Query("""
            delete from Walk w
             where w.id = :walkId
               and (w.walkedBy.id = :userId
                    or w.dog.id in (select d.id from Dog d where d.user.id = :userId))
            """)
    @org.springframework.data.jpa.repository.Modifying
    int deleteMine(@Param("walkId") long walkId, @Param("userId") long userId);

    /** 장소에서 한 산책의 수 — 모든 사람의 것(#729, {@code PlaceWalks}). 산책은 소프트 삭제가 없어 그대로 센다. */
    @Query("select count(w) from Walk w where w.placeContentId = :contentId")
    long countByPlaceContentId(@Param("contentId") String contentId);
}
