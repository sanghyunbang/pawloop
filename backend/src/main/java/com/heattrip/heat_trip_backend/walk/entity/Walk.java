package com.heattrip.heat_trip_backend.walk.entity;

import com.heattrip.heat_trip_backend.dog.entity.Dog;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.ForeignKey;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

import org.hibernate.annotations.OnDelete;
import org.hibernate.annotations.OnDeleteAction;
import org.locationtech.jts.geom.LineString;

import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;

/**
 * 산책 한 건 — 이슈 #145, 문서는 {@code docs/03-database/schema.md §4}.
 *
 * <h2>이 표가 없어서 산책이 사라지고 있었다</h2>
 * <p>{@code walk_tracking_screen} 은 경로·거리·시간을 제대로 쌓는데, 종료 시트의
 * "기록 저장하기" 가 그걸 버리고 스낵바만 띄웠다. 앱을 껐다 켜면 아무것도 남지 않았다.
 *
 * <h2>시각은 전부 UTC 로 저장한다</h2>
 * <p><b>{@code LocalDateTime} 인데 담긴 값이 UTC 다.</b> 이상해 보이지만 의도다.
 *
 * <p>이 저장소의 다른 표들은 {@code LocalDateTime.now()} 를 쓴다 — 즉 <b>JVM 의 기본
 * 시간대</b>가 무엇이냐에 따라 담기는 값이 달라진다. 개발 기계는 KST 이고 CI 컨테이너는
 * UTC 라, 같은 코드가 환경마다 다른 값을 넣는다. 평소에는 안 보이지만
 * <b>주 경계·날 경계를 계산하는 순간 드러난다</b> — #40 에서 예산 테스트가
 * <b>00:00–09:00 KST 에만</b> 빨간불이 나던 것이 정확히 그 문제였다.
 *
 * <p>그래서 여기서는 {@link Instant} 를 받아 <b>UTC 로 눕혀</b> 넣고, 읽을 때 다시
 * {@code Instant} 로 세운다({@link #startedAtInstant()}). {@code LocalDateTime} 은 드라이버가
 * 시간대 변환을 하지 않는 유일한 타입이라, JDBC URL 의 {@code serverTimezone} 이나 컨테이너
 * 시계가 무엇이든 <b>넣은 값이 그대로 나온다.</b>
 *
 * <p><b>주(週) 경계는 Java 에서 만든다.</b> MySQL 의 {@code WEEKDAY()}·{@code CURDATE()} 를
 * 쓰지 않는다 — 그것들은 세션 시간대를 읽고, 위에 적은 이유로 그 값을 믿을 수 없다.
 *
 * <h2>{@code path} 는 NULL 일 수 있다 (ADR-0015)</h2>
 * <p>손으로 입력한 기록과 위치 권한을 거부한 기록에는 경로가 없다. 그리고 LINESTRING 은
 * <b>점 하나로 만들 수 없다</b> — 점이 0~1개면 {@code null} 로 둔다. 시작점을 두 번 넣어
 * 길이 0 짜리 선을 만들지 않는다(지도에 점이 찍힌다).
 *
 * <p>{@code columnDefinition} 을 <b>반드시</b> 적는다. 빼면 Hibernate 가 {@code geometry} 로
 * 만들고, 그건 점이든 다각형이든 받으며 SRID 도 없다(ADR-0015 에서 실측).
 *
 * <h2>{@code @ManyToOne Dog} 여야 FK 가 생긴다</h2>
 * <p>스칼라 {@code Long dogId} 로 두면 {@code 01_schema.sql} 을 재생성할 때
 * <b>{@code fk_walk_dog} 가 조용히 사라진다</b> — 그 파일은 살아 있는 DB 에서
 * {@code SHOW CREATE TABLE} 로 뽑은 것이라 엔티티가 만들지 않은 제약은 담기지 않는다.
 * 모듈 경계는 {@code Dog} 에 붙은 {@code @NamedInterface("entity")} 가 연다.
 *
 * <h2>같은 산책이 두 줄이 되지 않는다</h2>
 * <p>{@code client_walk_id} 에 {@code UNIQUE(dog_id, client_walk_id)} 가 걸려 있다.
 * 없으면 전송이 타임아웃 났을 때 앱이 "안 닿음" 과 "저장됐는데 응답만 못 받음" 을 구분할
 * 수 없고, 다시 보내면 두 줄이 되고 안 보내면 사라진다. {@code chat_message.client_msg_id}
 * 와 같은 장치다.
 */
@Entity
@Table(
        name = "walk",
        indexes = {
                @Index(name = "idx_walk_dog", columnList = "dog_id, started_at"),
                @Index(name = "idx_walk_dog_created", columnList = "dog_id, created_at, id")
        },
        uniqueConstraints = @UniqueConstraint(
                name = "uq_walk_client", columnNames = {"dog_id", "client_walk_id"}))
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PRIVATE)
@Builder
public class Walk {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * 누가 걸었나. 소유권은 이 연관을 타고 {@code dog.user_id} 로 간다 — 산책에 사용자
     * 컬럼을 따로 두면 그 둘이 어긋나는 날이 온다.
     */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "dog_id", nullable = false,
            foreignKey = @ForeignKey(name = "fk_walk_dog"))
    @OnDelete(action = OnDeleteAction.CASCADE)
    private Dog dog;

    /** 앱이 만든 멱등키. 재전송이 두 줄이 되지 않게 한다. */
    @Column(name = "client_walk_id", nullable = false, length = 64)
    private String clientWalkId;

    /** <b>UTC</b>. 앱이 보낸 값이라 목록 커서로 쓰지 않는다 — 클래스 javadoc 참조. */
    @Column(name = "started_at", nullable = false)
    private LocalDateTime startedAt;

    /** <b>UTC</b>. 진행 중이거나 앱이 안 보냈으면 {@code null}. */
    @Column(name = "ended_at")
    private LocalDateTime endedAt;

    @Column(name = "distance_m", nullable = false)
    private int distanceM;

    @Column(name = "duration_s", nullable = false)
    private int durationS;

    /**
     * GPS 경로. 자바에서는 <b>{@code (x, y) = (경도, 위도)}</b> 다 — JTS 의 규약이고
     * 계약의 {@code [경도, 위도]} 와 같다.
     *
     * <h3>⚠️ DB 안에는 순서가 <b>반대</b>로 들어간다</h3>
     * <p>MySQL 은 SRID 4326 의 축 순서를 <b>(위도, 경도)</b> 로 본다(EPSG 정의 그대로다).
     * 그래서 hibernate-spatial 이 쓸 때 뒤집고 읽을 때 되돌린다. <b>실측한 것</b>:
     * {@code [[126.978, 37.5665], ...]} 로 보낸 경로가 DB 에서는
     * {@code LINESTRING(37.5665 126.978, ...)} 이고, API 로 다시 꺼내면
     * {@code [126.978, 37.5665]} 로 정확히 돌아온다.
     *
     * <p><b>그래서 네이티브 SQL 을 쓸 때 계약의 순서를 그대로 쓰면 안 된다.</b>
     * 예를 들어 "이 지점에서 가까운 산책" 을 물으려면
     * {@code ST_GeomFromText('POINT(위도 경도)', 4326)} 이지 {@code POINT(경도 위도)} 가
     * 아니다. 뒤집으면 오류가 나지 않고 <b>조용히 엉뚱한 거리</b>가 나온다.
     *
     * <p>저장된 값이 의미상 맞다는 것도 확인했다 — 위 3점에 대해
     * {@code ST_Length(path, 'metre')} 가 393.9m 를 주고, 그것은 그 좌표들의 실제 거리다
     * (구간 185m + 209m).
     */
    @Column(name = "path", columnDefinition = "linestring srid 4326")
    private LineString path;

    /**
     * 점별 시각 — 시작 시각 기준 <b>델타 초</b> 배열. 이슈 #155.
     *
     * <p>{@code path} 의 점 개수와 <b>길이가 같아야 한다.</b> LINESTRING 은 x, y 만 담아서
     * 점마다 몇 초에 찍혔는지가 어디에도 없었고, 시각은 그 순간에만 있는 정보라 나중에
     * 만들 수 없다. 안 넣으면 구간 페이스·일시정지 복원·거리 재계산이 <b>쌓인 행 전체에
     * 대해 영영 불가능</b>해진다.
     *
     * <p><b>DB 제약이 아니라 서비스가 길이를 검사한다.</b> MySQL CHECK 로 쓰려면
     * {@code ST_NumPoints} 와 {@code JSON_LENGTH} 를 함께 부르는 식이 되고 실익 대비
     * 복잡하다. 그래서 {@code WalkService} 의 검사가 <b>유일한 방어선</b>이고, 그 사실이
     * 테스트로 잠겨 있다.
     *
     * <p>{@code path} 와 같이 NULL 을 허용한다 — 손입력 기록과 위치 거부 기록에는 경로가
     * 없고, 그러면 시각도 없다. 13_walk_path_t.sql 이전에 쌓인 행도 영영 NULL 이다.
     *
     * <p><b>응답에는 싣지 않는다.</b> 지금 이 값을 그리는 화면이 없다 — 목록에서 path 를
     * 뺀 것과 같은 이유다.
     */
    @Column(name = "path_t", columnDefinition = "json")
    private String pathT;

    @Column(name = "memo", length = 500)
    private String memo;

    @Column(name = "weather", length = 30)
    private String weather;

    /**
     * <b>UTC</b>, 서버가 찍는다. <b>목록 커서의 기준이다.</b>
     *
     * <p>{@code startedAt} 을 커서로 쓰지 않는 이유: 그건 앱이 보낸 값이라, 오프라인에 쌓아
     * 둔 산책이 며칠 뒤 <b>과거 시각</b>으로 들어온다. 그걸 기준으로 자르면 이미 발급된
     * 커서보다 아래 날짜의 행이 <b>영원히 건너뛰어진다.</b> {@code chat_message} 가
     * {@code room_seq} 로 피한 것과 같은 종류의 실패다.
     */
    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    void onCreate() {
        if (createdAt == null) {
            createdAt = utc(Instant.now());
        }
    }

    /**
     * 회고 글을 다시 쓴다 — 이슈 #187.
     *
     * <p>산책이 끝난 직후에 쓰는 글과 나중에 돌아보며 쓰는 글은 다르다. 예전에는 저장
     * 시점의 한 번이 전부였고, 잘못 쓰면 <b>지우고 다시 만드는 수밖에</b> 없었다.
     *
     * <p><b>빈 문자열은 {@code null} 로 눕힌다.</b> 저장 경로({@code WalkRequest})가 안 보낸
     * 메모를 {@code null} 로 두므로, 여기서 {@code ""} 를 그대로 넣으면 "안 썼다" 가 두
     * 모양이 된다. 그러면 목록 화면이 둘 중 하나만 처리하다 한쪽을 빠뜨린다.
     *
     * <p>거리·시간은 여기서 안 바꾼다. 실측값이거나 사용자가 저장 시점에 정한 값이고,
     * 여기서 열면 "회고를 쓴다" 가 "기록을 고친다" 로 번진다.
     */
    public void rewriteMemo(String newMemo) {
        this.memo = (newMemo == null || newMemo.isBlank()) ? null : newMemo;
    }

    /** 저장된 UTC 벽시계를 다시 시점으로 세운다. 응답은 이 값으로 나간다. */
    public Instant startedAtInstant() {
        return startedAt.toInstant(ZoneOffset.UTC);
    }

    /** @return 종료 시각. 없으면 {@code null} */
    public Instant endedAtInstant() {
        return endedAt == null ? null : endedAt.toInstant(ZoneOffset.UTC);
    }

    public Instant createdAtInstant() {
        return createdAt.toInstant(ZoneOffset.UTC);
    }

    /** 시점을 UTC 벽시계로 눕힌다. 저장 전에 반드시 이것을 지난다. */
    public static LocalDateTime utc(Instant instant) {
        return LocalDateTime.ofInstant(instant, ZoneOffset.UTC);
    }
}
