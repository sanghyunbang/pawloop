package com.heattrip.heat_trip_backend.walk;

/**
 * 장소에서 한 산책의 <b>수</b> — 이슈 #729("이 장소의 글" 머리의 "산책 N회").
 *
 * <p>{@link CourseAttachment} 와 같은 모양의 모듈 루트 공개 표면이다 — {@code community} 가 장소 머리를
 * 채우려고 부른다. 사람이 아니라 <b>장소</b> 기준이라 집(household) 경계가 없고, 세는 것뿐이라 경로도
 * 이름도 밖으로 안 나간다. 산책 기록은 지워지지 않으므로(소프트 삭제 없음) 그대로 센다.
 */
public interface PlaceWalks {

    /** {@code walk.place_content_id} 가 이 값인 산책의 수. 모르는 장소면 0 이다. */
    long countAtPlace(String contentId);
}
