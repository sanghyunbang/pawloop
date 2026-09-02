package com.heattrip.heat_trip_backend.community.entity;

import com.heattrip.heat_trip_backend.community.CommunityTime;
import com.heattrip.heat_trip_backend.user.entity.User;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.ForeignKey;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.Lob;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

import org.hibernate.annotations.Check;
import org.hibernate.annotations.OnDelete;
import org.hibernate.annotations.OnDeleteAction;

import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.Instant;
import java.time.LocalDateTime;

/**
 * 커뮤니티 글 한 편 — 이슈 #169, 문서는 {@code docs/03-database/schema.md §7}.
 *
 * <h2>여기는 엔티티까지다</h2>
 * <p>리포지토리·서비스·컨트롤러는 <b>#170</b> 이다. 그런데 엔티티는 표와 <b>같은 PR 에
 * 있어야 한다</b> — {@code SchemaDdlDriftTest} 가 "엔티티에 없는 테이블이 커밋된 스키마에
 * 있다" 를 빨간불로 내기 때문이다. 이슈 #169 본문의 "엔티티를 만들지 않습니다" 는 그
 * 검사를 안 본 것이다.
 *
 * <h2>{@code board} 는 ASCII 키다</h2>
 * <p>{@code walk_review} · {@code pet_place} · {@code health} · {@code free} · {@code brag}.
 * 2026-09 이전 계약은 값 자체가 한글 표시 문자열이었는데({@code "산책로 후기"} 등),
 * 그 값이 <b>query 파라미터로 나가고 이 컬럼에 들어간다.</b> 표시 문구를 저장하면
 * 게시판 이름을 다듬는 날 <b>쌓인 행을 전부 고쳐야 한다.</b> {@code CareType} 이 이미
 * 같은 모양이다 — 값은 {@code water|meal|walk|med|vet} 이고 "물/밥/산책/투약/병원" 은
 * 앱이 붙인다.
 *
 * <p><b>{@code @Check} 를 걸지 않는다.</b> {@code CareLog.type} 은 걸었는데 여기는 안 거는
 * 이유가 있다 — 게시판은 <b>제품이 늘리는 목록</b>이라 값이 늘 때마다 마이그레이션이 따라오면
 * 그 자체가 비용이다. 케어 종류는 다섯으로 굳었고 늘리는 날이 M4 로 못 박혀 있다.
 *
 * <h2>{@code content_id} 에 FK 가 없다</h2>
 * <p>계약의 {@code Post.contentId} 는 문자열이고 {@code Place.contentId} 와 같은 키다
 * (ADR-0017). 반려 앱의 장소는 KTO 프록시 <b>캐시</b>({@code pet_place_detail})에서 오는데,
 * 사용자가 고른 장소의 캐시 행이 아직 없거나 지워질 수 있다. FK 를 걸면 <b>그때 글 작성이
 * 실패한다</b> — 장소는 글의 부속물이지 전제가 아니다.
 *
 * <p>레거시 {@code places} 표({@code contentid bigint})에는 걸지 않는다. 감정 여행 시절의
 * 다른 키 공간이다.
 *
 * <h2>{@code handle} 은 저장 전용이다</h2>
 * <p>작성 시점 닉네임 스냅샷이고 <b>응답에는 싣지 않는다.</b> 응답의 {@code author} 는
 * {@code PersonRef{userId, nickname}} 이고 그 {@code nickname} 은 <b>조회 시점의 현재 값</b>이다
 * (ADR-0017 규약 5). 탈퇴한 계정이면 {@code userId=0} · "알 수 없음" 이다.
 *
 * <p>둘을 섞으면 <b>저장은 스냅샷, 표시는 현재값이라는 두 규칙이 한 화면에서 만난다</b> —
 * 같은 사람의 글 둘이 다른 이름으로 보인다.
 *
 * <h2>{@code users} 로의 FK 는 {@code ON DELETE SET NULL} 이다 — 양쪽으로 틀릴 수 있다</h2>
 * <p><b>{@code CASCADE}</b> 면 탈퇴 한 번에 그 사람의 글이 사라지고 <b>거기 달린 남의 댓글도
 * 함께</b> 사라진다. 반대로 <b>아무것도 안 적으면</b>({@code RESTRICT}) <b>글을 한 번 쓴 사람이
 * 영원히 탈퇴하지 못한다</b> — {@code UserService.deleteMe} 가 {@code users} 행을 <b>물리
 * 삭제</b>하기 때문이다.
 *
 * <p>후자가 이 표를 처음 낸 모양이었고 실측으로 확인했다 — {@code DELETE FROM users} 가
 * {@code ERROR 1451} 로 죽었다. {@code 11_dog.sql} 이 {@code dog} 에 대해 적어 둔 것과 같은
 * 실패인데, {@code dog} 은 {@code CASCADE} 로 풀고 여기는 {@code SET NULL} 로 푼다 —
 * <b>반려동물은 그 사람의 것이지만 글에는 남의 댓글이 매달려 있다.</b>
 *
 * <p>{@code care_log.done_by} 가 이미 이 모양이다. {@code user} 가 {@code null} 인 행은
 * "탈퇴한 사람이 쓴 것" 이고, 응답의 {@code author} 는 {@code userId=0} · "알 수 없음" 이다
 * (ADR-0017 규약 5). 그때 {@link #handle} 이 <b>그 글을 누가 썼는지 아는 유일한 기록</b>이 된다.
 */
@Entity
@Table(
        name = "post",
        indexes = {
                // 목록이 딛는 인덱스. 계약의 커서 페이지네이션이 (created_at, id) 로 내려간다.
                @Index(name = "idx_post_board_created", columnList = "board, created_at, id"),
                // 탈퇴 시 SET NULL 이 훑는 자리. 없으면 users 삭제가 이 표 전체 스캔이다.
                @Index(name = "idx_post_user", columnList = "user_id")
        })
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PRIVATE)
@Builder
@Check(name = "chk_post_board", constraints = "board in ('walk_review','pet_place','health','free','brag')")
public class Post {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** 작성자. 탈퇴해도 글은 남는다 — 클래스 javadoc 참조. */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id",
            foreignKey = @ForeignKey(name = "fk_post_user"))
    @OnDelete(action = OnDeleteAction.SET_NULL)
    private User user;

    /** ASCII 키. 화면 문구는 앱이 든다 — 클래스 javadoc 참조. */
    @Column(name = "board", nullable = false, length = 20)
    private String board;

    @Column(name = "title", nullable = false, length = 200)
    private String title;

    @Lob
    @Column(name = "body", nullable = false, columnDefinition = "text")
    private String body;

    /** 연결 장소. {@code Place.contentId} 와 같은 키이고 FK 는 없다 — 클래스 javadoc 참조. */
    @Column(name = "content_id", length = 64)
    private String contentId;

    /** 표시용 장소 이름. {@code contentId} 와 별개다 — 지도에서 안 고르고 손으로 적을 수 있다. */
    @Column(name = "loc", length = 100)
    private String loc;

    /**
     * 작성 시점 닉네임 스냅샷. <b>응답에는 안 싣는다</b> — 클래스 javadoc 참조.
     *
     * <p><b>폭은 {@code users.nickname} 과 같은 255 다.</b> #169 는 50 으로 좁혔는데, 그러면
     * 51자 닉네임을 가진 사람의 <b>모든 글·댓글 작성이 영구히 500</b> 이 된다 — MySQL 8 의
     * {@code STRICT_TRANS_TABLES} 는 자르지 않고 {@code ERROR 1406} 으로 거절하고, 그 사람은
     * 읽기와 반응은 되는데 쓰기만 죽은 상태에 갇힌다. 실제 DB 에 60자를 넣어 재현했다.
     *
     * <p>닉네임 쪽에 상한이 없다는 것이 진짜 원인이다 — {@code UpdateProfileRequest} 에
     * {@code @Size} 가 없고 컨트롤러에 {@code @Valid} 도 없다. 그건 {@code user} 도메인의 일이라
     * 별도 이슈로 냈다. 여기서는 <b>참조하는 쪽이 원본보다 좁지 않게</b> 맞춘다 —
     * {@code chat_message.sender_name} 이 같은 이유로 255 이고 그 자리에 "users.nickname 과
     * 같은 폭이다" 라고 적혀 있다.
     */
    @Column(name = "handle", length = 255)
    private String handle;

    /**
     * <b>{@code LocalDateTime} 인데 담긴 값이 UTC 다.</b> {@code Walk} 이 #40 에서 정한 것과
     * 같은 규약이고, 그 클래스 javadoc 이 이유를 적어 뒀다 — {@code LocalDateTime.now()} 는
     * <b>JVM 기본 시간대</b>를 읽어서 개발 기계(KST)와 CI 컨테이너(UTC)가 다른 값을 넣는다.
     *
     * <p>#169 는 그 규약을 안 따랐다. 이 컬럼이 <b>커서의 첫 축</b>이라 더 나빴다 — 서버
     * 시간대가 바뀌면 커서가 건너뛰거나 되돌아간다. 그리고 응답의 {@code createdAt} 이
     * 오프셋 없는 문자열로 나가서, 앱이 그것을 자기 지역 시각으로 읽어 <b>9시간 어긋난
     * 시각</b>을 그렸다(계약은 {@code format: date-time} 이라고 선언해 뒀는데도).
     */
    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    /**
     * DB 기본값에 기대지 않는다. {@code created_at} 이 커서의 첫 축이라, 서버 시계와 DB 시계가
     * 다르면 커서가 건너뛰거나 되돌아간다.
     */
    @PrePersist
    void onCreate() {
        if (createdAt == null) {
            createdAt = CommunityTime.nowUtc();
        }
    }

    /** 저장된 값을 다시 시각으로 세운다. 응답이 오프셋을 갖게 하는 자리다. */
    public Instant createdAtInstant() {
        return CommunityTime.toInstant(createdAt);
    }
}
