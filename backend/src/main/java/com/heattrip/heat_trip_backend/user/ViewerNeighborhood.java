package com.heattrip.heat_trip_backend.user;

import java.util.Optional;

/**
 * 보는 사람의 동네를 묻는 자리 — 이슈 #342.
 *
 * <h2>왜 인터페이스 하나를 두나</h2>
 * <p>커뮤니티의 "우리 동네" 는 <b>보는 사람이 고른 구</b>로 목록을 좁힌다. 그 값을 알려면
 * {@code users} 를 읽어야 하는데, 커뮤니티가 {@code user.repository} 를 직접 잡으면 모듈의
 * 속을 건드리게 된다({@code ModularityBaselineTest}). 그래서 <b>사용자 모듈의 기본 패키지에</b>
 * 물어보는 면만 둔다 — {@code walk.CourseAttachment} 가 커뮤니티에 코스를 열어 준 것과 같은
 * 모양이다.
 *
 * <h2>왜 쿼리로 안 받나</h2>
 * <p>구를 파라미터로 받으면 아무 구나 골라 훑을 수 있고, 그건 "우리 동네" 가 아니라 남의
 * 동네 구경이다. 값의 출처는 <b>그 사람이 저장해 둔 동네</b> 하나뿐이어야 한다.
 */
public interface ViewerNeighborhood {

    /**
     * 그 사람이 고른 동네의 <b>시군구 앞 다섯 자리</b>. 안 골랐거나 없는 사용자면 비어 있다.
     */
    Optional<String> sggOf(long userId);
}
