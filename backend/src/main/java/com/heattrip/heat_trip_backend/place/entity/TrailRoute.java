package com.heattrip.heat_trip_backend.place.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Lob;
import jakarta.persistence.Table;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.LocalDateTime;

/**
 * 산책로(두루누비 걷기여행길) 코스 하나의 <b>선</b> — 이슈 #291.
 *
 * <h2>왜 카탈로그와 따로인가</h2>
 * <p>카탈로그({@link PlaceCatalog})는 점 목록이고 앱이 통째로 받아 기기에 둔다. 코스 하나의
 * 선은 줄여도 300 점(약 8KB)이라, 2,000 코스를 카탈로그에 실으면 한 벌이 16MB 가 된다.
 * 그래서 카탈로그에는 <b>시작점 하나</b>만 싣고({@code Place.source=trail}), 선은 여기 두고
 * 사용자가 그 산책로를 눌렀을 때만 {@code GET /api/places/trails/{courseId}/route} 로 준다.
 *
 * <h2>{@link #payload}</h2>
 * <p>{@code [[경도, 위도], ...]} JSON 문자열이다. 응답 본문의 재료 그대로라 꺼내서 객체로
 * 만들지 않는다 — 카탈로그와 같은 이유다. 좌표 순서는 계약의 {@code Walk.path} 와 같다.
 *
 * <p>{@link #fetchedAt} 은 {@code place_catalog.fetched_at} 과 같은 <b>서비스 존 벽시계</b>다 —
 * "다시 받아 볼 때가 됐는가" 에만 쓰고 응답으로 나가지 않는다.
 *
 * <h2>추천 코스도 이 표에 산다 — #725</h2>
 * <p>장소에서 출발해 돌아오는 추천 코스({@code PlaceLoopService})가 같은 모양의 선이라 같은 표에
 * {@code loop:{contentId}:{lengthM}} 번호로 남는다. 그래서 {@link #courseId} 는 두루누비 번호(19자)보다
 * 훨씬 길 수 있다 — 두루누비 장소의 2km 코스가 {@code loop:trail:T_CRS_MNG0000005118:2000}(35자)다.
 */
@Entity
@Table(name = "trail_route")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class TrailRoute {

    /**
     * {@link #courseId} 칸의 크기 — {@code V4__trail_route_course_id_80.sql} 과 같아야 한다(#782).
     *
     * <p>처음에는 두루누비 번호만 담으려고 32 였다. 추천 코스 번호가 들어오며 두루누비·놀이터 장소의 코스가
     * 전부 32자를 넘어 저장이 MySQL 1406 으로 죽었다(응답 500, 실패마다 ORS 세 번).
     *
     * <p><b>80 인 이유:</b> 이 저장소에서 장소 번호({@code contentId})를 담는 칸은 전부 64자다
     * ({@code pet_place_detail.content_id} · {@code post.content_id} · {@code walk.place_content_id}).
     * 64자 번호로 만들 수 있는 가장 긴 코스 번호가 {@code loop:} 5 + 64 + {@code :} 1 + {@code 10000} 5 =
     * 75자라, 그것을 덮는다. {@code TrailRouteCourseIdWidthTest} 가 이 계산을 잠근다.
     */
    public static final int COURSE_ID_LENGTH = 80;

    /**
     * 두루누비의 {@code crsIdx}(카탈로그 항목의 {@code contentId} 는 {@code trail:} + 이 값) 또는
     * 추천 코스 번호 {@code loop:{contentId}:{lengthM}}.
     */
    @Id
    @Column(name = "course_id", nullable = false, length = COURSE_ID_LENGTH)
    private String courseId;

    @Column(name = "name", nullable = false, length = 150)
    private String name;

    /** 줄인 뒤 남은 점 수. */
    @Column(name = "point_count", nullable = false)
    private int pointCount;

    /** 원본 선의 길이(m). 줄이기 전에 잰다. */
    @Column(name = "length_m", nullable = false)
    private int lengthM;

    /**
     * 선의 첫 점. 카탈로그의 {@code Place.lat/lng} 가 이 값이다 — 코스를 "어디서 시작하나" 로
     * 지도에 찍는다. {@code payload} 를 파싱하지 않고 꺼내려고 따로 든다.
     */
    @Column(name = "start_lat", nullable = false)
    private double startLat;

    @Column(name = "start_lng", nullable = false)
    private double startLng;

    /** {@code [[lng, lat], ...]} — 응답의 {@code points} 그대로다. */
    @Lob
    @Column(name = "payload", nullable = false, columnDefinition = "LONGTEXT")
    private String payload;

    @Column(name = "fetched_at", nullable = false)
    private LocalDateTime fetchedAt;
}
