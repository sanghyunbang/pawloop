package com.heattrip.heat_trip_backend.walk.course;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;

import org.locationtech.jts.geom.LineString;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;

/**
 * 코스 — 내가 걸은 길 중에 "여기 좋다" 고 남긴 것. 이슈 #339.
 *
 * <h2>산책과 무엇이 다른가</h2>
 * <p>{@code walk} 는 "그날 내가 걸었다" 이고 코스는 "여기를 이렇게 걸으면 좋다" 다. 그래서
 * <b>선을 베껴 온다</b> — {@link CoursePath#trimEnds} 로 양 끝 100m 를 버린 선이다. 집 앞이
 * 그대로 남으면 코스를 나누는 일이 사는 곳을 알리는 일이 된다.
 *
 * <p>산책을 지워도 코스는 남는다({@code fk_course_walk ... ON DELETE SET NULL}). 그래서
 * {@link #walkId} 가 {@code null} 일 수 있다 — "어느 산책에서 왔는지 이제 모른다" 는 뜻이지
 * 코스가 반쪽이라는 뜻이 아니다.
 *
 * <h2>주인을 연관으로 두지 않는 이유</h2>
 * <p>{@code user_id} 를 {@code @ManyToOne} 이 아니라 <b>값</b>으로 둔다. 이 클래스가 사는
 * {@code walk} 모듈이 {@code user} 모듈의 엔티티를 들고 있을 이유가 없고, 소유권 판정은
 * 어차피 쿼리 안에서 id 로 한다. DB 에는 FK 가 있다(CASCADE) — 탈퇴하면 함께 사라진다.
 */
@Entity
@Table(
        name = "course",
        indexes = {
                @Index(name = "idx_course_user", columnList = "user_id, created_at"),
                @Index(name = "idx_course_public", columnList = "visibility, created_at")
        })
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PRIVATE)
@Builder
public class Course {

    /** 공개 범위 — 기본은 나만 본다. 공개는 사용자가 명시적으로 하는 일이다(#339). */
    public static final String PRIVATE = "private";
    public static final String PUBLIC = "public";

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    /** 어느 산책에서 왔나. 그 산책을 지우면 {@code null} 이 된다 — 코스는 남는다. */
    @Column(name = "walk_id")
    private Long walkId;

    @Column(name = "name", nullable = false, length = 60)
    private String name;

    @Column(name = "note", length = 200)
    private String note;

    /**
     * 반려견 관점 셋을 콤마로 — {@code leash}(목줄 규정) · {@code poopbag}(배변봉투통) ·
     * {@code shade}(그늘·물). 표를 새로 만들지 않는다: 값이 셋으로 닫혀 있다.
     */
    @Column(name = "tags", length = 60)
    private String tags;

    /** 잘라 낸 선. <b>없는 코스는 없다</b> — 선이 곧 코스다. */
    @Column(name = "path", columnDefinition = "linestring srid 4326", nullable = false)
    private LineString path;

    /** 잘라 낸 뒤의 길이(m). 화면이 이 값을 그대로 쓴다 — 원래 산책의 거리가 아니다. */
    @Column(name = "distance_m", nullable = false)
    private int distanceM;

    /** 원래 산책의 소요(초). 잘라 낸 만큼을 빼지 않는다 — 그 값은 알 수 없다. */
    @Column(name = "duration_s", nullable = false)
    private int durationS;

    @Column(name = "visibility", nullable = false, length = 10)
    private String visibility;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    void onCreate() {
        if (createdAt == null) {
            createdAt = LocalDateTime.ofInstant(Instant.now(), ZoneOffset.UTC);
        }
        if (visibility == null) {
            visibility = PRIVATE;
        }
    }

    public boolean isPublic() {
        return PUBLIC.equals(visibility);
    }

    public Instant createdAtInstant() {
        return createdAt == null ? null : createdAt.toInstant(ZoneOffset.UTC);
    }

    /** 공개 범위를 바꾼다. 값이 둘 중 하나가 아니면 바꾸지 않는다 — 호출부가 이미 검증한다. */
    public void changeVisibility(String next) {
        if (PRIVATE.equals(next) || PUBLIC.equals(next)) {
            this.visibility = next;
        }
    }
}
