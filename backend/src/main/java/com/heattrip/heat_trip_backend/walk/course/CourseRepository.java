package com.heattrip.heat_trip_backend.walk.course;

import org.springframework.data.domain.Limit;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Collection;
import java.util.List;
import java.util.Optional;

/** 코스 조회 — 이슈 #339. 소유권 조건은 <b>쿼리 안에</b> 있다(남의 코스는 없는 코스와 같다). */
public interface CourseRepository extends JpaRepository<Course, Long> {

    /** 내 코스, 최근 순. */
    @Query("""
            select c from Course c
             where c.userId = :userId
             order by c.createdAt desc, c.id desc
            """)
    List<Course> findMine(@Param("userId") long userId, Limit limit);

    /**
     * 하나. <b>내 것이거나 공개된 것</b>만 준다.
     *
     * <p>남의 비공개 코스와 없는 코스를 같은 404 로 만드는 자리다 — 여기서 갈라 주면
     * "그 번호는 있는데 남의 것" 이 응답으로 새어 나간다.
     */
    @Query("""
            select c from Course c
             where c.id = :courseId
               and (c.userId = :userId or c.visibility = 'public')
            """)
    Optional<Course> findVisible(@Param("courseId") long courseId, @Param("userId") long userId);

    /**
     * 글에 붙은 코스들 — <b>공개된 것만</b> (#339).
     *
     * <p>목록이 한 번에 물어보는 이유는 N+1 을 만들지 않기 위해서다. 비공개로 되돌린 코스는
     * 결과에서 빠지고, 그 글의 카드에는 그림이 없다.
     */
    @Query("""
            select c from Course c
             where c.id in :ids and c.visibility = 'public'
            """)
    List<Course> findPublicByIds(@Param("ids") Collection<Long> ids);

    /**
     * 공개 코스 한 벌 — 지도의 "이웃 코스" 가 쓴다.
     *
     * <p><b>좌표로 거르지 않는다.</b> 앱이 한 벌을 받아 기기에서 가까운 것을 고른다 —
     * 서버로 좌표를 보내지 않는 A안(#235)이고, 장소 카탈로그(#273)와 같은 방식이다.
     */
    @Query("""
            select c from Course c
             where c.visibility = 'public'
             order by c.createdAt desc, c.id desc
            """)
    List<Course> findPublic(Limit limit);
}
