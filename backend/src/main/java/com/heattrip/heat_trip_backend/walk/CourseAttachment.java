package com.heattrip.heat_trip_backend.walk;

import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * "이 코스를 글에 붙여도 되는가" · "붙어 있는 코스를 어떻게 그리나" — {@code walk} 모듈이
 * 밖으로 내놓는 <b>코스에 관한 유일한 표면</b>이다. 이슈 #339.
 *
 * <h2>왜 {@code CourseService} 를 그대로 열지 않는가</h2>
 * <p>{@code community} 가 필요한 것은 둘뿐이다 — 붙일 수 있는지 판정, 그리고 카드에 그릴
 * 만큼의 값. {@code CourseService} 를 열면 생성·삭제·공개 범위 변경까지 따라 나가고, 그러면
 * 다음 사람이 <b>커뮤니티 코드에서 코스를 지울</b> 수도 있게 된다. {@code dog.DogOwnership}
 * 이 같은 이유로 만들어졌다.
 *
 * <p>모듈 패키지 <b>바로 아래</b> 타입은 Spring Modulith 가 공개 표면으로 본다.
 * {@code walk.course.CourseService} 는 하위 패키지라 밖에서 쓰면 경계 위반이다.
 *
 * <h2>공개된 것만 나간다</h2>
 * <p>{@link #cards} 는 <b>공개 코스만</b> 준다. 글을 쓴 뒤 코스를 비공개로 되돌리면 글에서도
 * 그림이 사라진다 — 글쓴이 자신에게도 그렇다. 보는 사람마다 다른 그림을 그리면 "왜 내
 * 글만 다르게 보이나" 가 되고, 무엇보다 <b>비공개로 되돌린 사람의 뜻</b>이 그것이다.
 */
public interface CourseAttachment {

    /**
     * 글에 붙일 수 있는 코스인가. <b>내 것이면서 공개된 것</b>만 준다.
     *
     * <p>비공개를 붙이면 남들에게는 빈 자리로 보인다. 그래서 붙이는 순간에 막고, 앱이
     * "공개하고 붙이기" 를 권한다 — 서버가 몰래 공개로 바꾸지 않는다.
     */
    Optional<AttachedCourse> forAttaching(long courseId, long userId);

    /**
     * 글 목록·상세에 그릴 코스들. <b>공개 코스만</b> 돌려주고, 없는 id 는 결과에서 빠진다.
     *
     * <p>목록이 한 번에 물어보는 이유는 N+1 을 만들지 않기 위해서다 — 글 스무 개짜리 피드가
     * 코스를 스무 번 물으면 그 화면이 느려진다.
     */
    Map<Long, AttachedCourse> cards(Collection<Long> courseIds);

    /**
     * 카드에 그릴 만큼의 코스.
     *
     * @param path 이미 잘라 낸 선을 <b>더 줄인</b> 것(최대 {@code 40} 점). 카드 크기의 그림에는
     *             그것으로 충분하고, 피드 응답에 300점짜리 선을 스무 개 싣지 않는다
     */
    record AttachedCourse(long id, String name, int distanceM, List<List<Double>> path) {
    }
}
