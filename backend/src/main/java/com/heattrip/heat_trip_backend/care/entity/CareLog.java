package com.heattrip.heat_trip_backend.care.entity;

import com.heattrip.heat_trip_backend.group.entity.FamilyGroup;
import com.heattrip.heat_trip_backend.user.entity.User;

import jakarta.persistence.Column;
import jakarta.persistence.Convert;
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

import org.hibernate.annotations.Check;
import org.hibernate.annotations.ColumnDefault;
import org.hibernate.annotations.OnDelete;
import org.hibernate.annotations.OnDeleteAction;

import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

/**
 * 케어 한 건 — 누가 · 언제 · 무엇을 했는가. 이슈 #76, 문서는 {@code docs/03-database/schema.md §17}.
 *
 * <h2>이 표가 막으려는 사고는 둘이다</h2>
 * <p><b>이중 급여</b>(엄마가 밥을 줬는데 아빠가 또 준다)와 <b>산책 누락</b>(서로 상대가 다녀왔겠거니
 * 한다). 둘 다 "오늘 누가 무엇을 했는지" 를 한 화면에 놓으면 사라진다. 그래서 이 표는
 * <b>지우지 않는 사건 기록</b>이다 — 같은 종류를 하루에 두 번 찍어도 두 행이 남는다.
 * 두 번째를 막지 않는 이유는 {@code CareService.record} 에 있다.
 *
 * <h2>⚠️ {@code dog_id} 에는 FK 가 없고, 값도 <b>항상 {@code null}</b> 이다</h2>
 *
 * <p><b>2026-09-01 에 이 절의 전제가 바뀌었다.</b> 예전에는 "{@code dog} 표가 정본 스키마에
 * 없다" 가 이유였는데, #145 가 그 표를 만들었다({@code 01_schema.sql} 의
 * {@code CREATE TABLE dog}, {@code docs/03-database/schema.md §3} 은 이제 <b>실재</b>다).
 * 앱도 {@code POST /api/dogs} 로 서버에 반려동물을 등록한다.
 *
 * <p>그래서 <b>"없는 표에는 FK 를 걸 수 없다" 는 더 이상 이유가 아니다.</b> 지금 안 거는
 * 이유는 다른 것이다.
 *
 * <p>{@code mysql/init/01_schema.sql} 은 살아 있는 DB 에서 {@code SHOW CREATE TABLE} 로
 * <b>뽑은</b> 파일이고, 그 DB 는 Hibernate 가 엔티티로 만든 것이다. 이 클래스가
 * {@code dogId} 를 스칼라 {@code Long} 으로 들고 있어서 <b>Hibernate 가 그 FK 를 만들지
 * 않는다.</b> 마이그레이션에서 {@code ALTER} 로 더하면 운영 DB 에는 있고 커밋된 스키마에는
 * 없는 제약이 생기고, 다음 재생성 때 조용히 사라진다.
 *
 * <p>제대로 걸려면 이 클래스가 {@code @ManyToOne Dog} 를 들어야 하고, 그건 {@code care} 가
 * {@code dog} 모듈을 참조한다는 뜻이라 별도 판단이다. <b>지금 {@code dog_id} 가 항상
 * {@code null} 이라 무결성 위험은 없다</b> — 미룬 것이 안전한 드문 경우다.
 * <b>그 판단은 이슈 #154 가 소유한다.</b>
 *
 * <p><b>#9 와 헷갈리지 말 것.</b> #9({@code refresh_token})는 탈퇴 경로가 DB 삭제 순서에
 * 묶이는 것을 피하려고 <b>일부러</b> 안 걸었다. 여기는 "매핑을 안 바꿔서 못 거는" 것이라
 * 성격이 다르다 — 그날이 오면 여기는 FK 를 걸고 #9 는 안 건다.
 *
 * <h2>여기는 chat 경계 밖이라 나머지 FK 는 정상적으로 건다</h2>
 * <p>"chat 밖으로 나가는 FK 0개"(ADR-0011 결정 4)는 {@code chat_*} 세 표에만 걸리는 규칙이다.
 * {@code group_id}·{@code done_by} 는 평범한 FK 이고, {@code ChatBoundaryArchitectureTest}
 * 가 그 둘을 <b>허용 목록</b>으로 명시한다.
 */
@Entity
@Table(
        name = "care_log",
        indexes = {
                // "오늘의 케어" 조회가 이 인덱스 하나로 그룹·당일 범위를 훑는다.
                @Index(name = "idx_carelog_group", columnList = "group_id, occurred_at"),
                // 사용자 탈퇴 시 SET NULL 이 훑는 자리. 없으면 users 삭제가 이 표 전체 스캔이다.
                @Index(name = "idx_carelog_doneby", columnList = "done_by")
        })
// DB 가 마지막 방어선이다 (📌 #86 원칙 5). 애플리케이션의 CareType 검증이 뚫리거나
// 누가 손으로 INSERT 해도 여섯 번째 종류는 들어가지 못한다.
@Check(name = "ck_carelog_type", constraints = "type in ('water','meal','walk','med','vet')")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PRIVATE)
@Builder
public class CareLog {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * 대상 강아지. <b>오늘은 항상 {@code null} 이고 FK 도 없다</b> — 이유는 클래스 javadoc.
     *
     * <p>{@code CareService.record} 가 요청 본문의 {@code dogId} 를 <b>읽지 않는다.</b>
     * 이 경로가 <b>그룹 단위 기록</b>이라 대상 개체를 아직 받지 않기 때문이다 — 표가 없어서가
     * 아니다({@code dog} 는 #145 가 만들었다). FK 를 안 거는 진짜 이유는 위 클래스 javadoc 에 있다.
     */
    @Column(name = "dog_id")
    private Long dogId;

    /**
     * 공유 대상 가족 그룹. <b>nullable</b> 이다 — 그룹에 속하지 않은 1인 사용자도 자기 기록을
     * 남기기 때문이다(이슈 본문).
     *
     * <p><b>지금 {@code null} 인 행은 0건이다.</b> 이 이슈가 여는 경로는
     * {@code /api/groups/{groupId}/care-logs} 뿐이라 여기서 만들어지는 행은 전부 그룹을 든다.
     * 개인 기록을 만드는 경로({@code POST /api/dogs/{dogId}/care-logs}, M4)는 아직 없고,
     * 조회 필터가 {@code group_id = :groupId} 라서 만약 {@code null} 행이 생겨도
     * <b>어떤 조회에도 나오지 않는다.</b> 그 경로가 생기는 날 개인 기록 조회도 함께 온다 —
     * 컬럼을 지금 nullable 로 두는 것은 그 자리를 비워 두는 것이다.
     *
     * <p>{@code ON DELETE SET NULL} 이다. 그룹이 사라져도 "내가 밥을 줬다" 는 사실은 남는다 —
     * 그 행은 개인 기록이 된다. CASCADE 로 지우면 가족을 해산했다는 이유로 개인의 케어 이력이
     * 통째로 증발한다.
     *
     * <p>연관을 {@code FamilyGroup} 으로 든 것은 <b>Hibernate 가 FK 를 만들게 하려는 것</b>이다.
     * 스칼라 {@code Long} 으로 두면 {@code mysql/init/01_schema.sql} 이 엔티티에서 재생성될 때
     * FK 가 조용히 사라진다({@code SchemaDdlDriftTest} 는 FK 를 보지 않는다). 값으로 쓰는 것은
     * {@code getId()} 뿐이라 지연 프록시가 DB 를 다시 치지 않는다.
     */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "group_id",
            foreignKey = @ForeignKey(name = "fk_carelog_group"))
    @OnDelete(action = OnDeleteAction.SET_NULL)
    private FamilyGroup group;

    /** 물·밥·산책·투약·병원. 저장되는 문자열은 {@link CareType#wire()} 다. */
    @Convert(converter = CareType.Codec.class)
    @Column(name = "type", nullable = false, length = 10)
    private CareType type;

    /**
     * 수행자. <b>토큰의 사용자</b>이지 요청 본문의 값이 아니다 — 남의 이름으로 기록을 남길 수
     * 있으면 "오늘 아빠가 밥을 줬다" 라는 화면 문구 자체를 믿을 수 없게 된다.
     *
     * <p><b>그 사람이 탈퇴하면 {@code null} 이 된다</b>({@code ON DELETE SET NULL}).
     * 여기는 2026-08 까지 {@code CASCADE} 였고, 그러면 엄마가 탈퇴하는 순간 "오늘 엄마가
     * 산책을 다녀왔다" 가 <b>아빠 화면에서도</b> 사라졌다 — 이 표가 막으려는 사고(산책 누락)가
     * 정확히 그 자리에서 생긴다. 기록은 엄마의 소유물이 아니라 <b>가족이 함께 보는 사건</b>이고,
     * 그래서 {@link #group} 이 이미 고른 답({@code SET NULL} — "가족을 해산했다는 이유로 개인의
     * 케어 이력이 통째로 증발한다")과 같은 답을 여기서도 고른다.
     *
     * <p>사람이 사라지면 <b>이름만</b> 잃는다. {@code CareDoerResponse} 가
     * {@link User#UNKNOWN_DISPLAY_NAME}({@code 알 수 없음})으로 떨어뜨린다.
     *
     * <p>⚠️ {@code CareLogRepository.findDayOfGroup} 의 fetch join 이 <b>left</b> 여야 한다.
     * inner join 이면 이 값이 {@code null} 인 행이 조회에서 조용히 빠지고, CASCADE 로 지우던
     * 것과 화면에서 구별되지 않는다.
     */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "done_by",
            foreignKey = @ForeignKey(name = "fk_carelog_doneby"))
    @OnDelete(action = OnDeleteAction.SET_NULL)
    private User doneBy;

    /**
     * 언제 했는가. <b>서버 시계</b>다({@code CareService} 의 {@code Clock}).
     *
     * <p>클라이언트가 보낸 시각을 받지 않는 이유: 이 값이 곧 "오늘 누가 했는지" 를 가르는
     * 기준이라, 임의로 정할 수 있으면 남의 화면에 없던 기록을 만들어 넣거나 오늘 기록을
     * 어제로 밀어 이중 급여 경고를 없앨 수 있다. 지난 일을 나중에 적는 것은 M4 다.
     */
    @Column(name = "occurred_at", nullable = false)
    private LocalDateTime occurredAt;

    /** 자유 메모. 길이는 {@code walk_note.body} 와 같은 500자다. */
    @Column(name = "memo", length = 500)
    private String memo;

    @ColumnDefault("CURRENT_TIMESTAMP(6)")
    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    /**
     * 애플리케이션이 값을 안 넣어도 행이 만들어지게 한다.
     *
     * <p>DB 기본값만으로는 부족하다 — Hibernate 는 INSERT 에 컬럼을 항상 실어 보내므로
     * 필드가 {@code null} 이면 NOT NULL 위반으로 죽는다. {@code family_group}·chat 세 표가
     * 쓰는 것과 같은 방식이다.
     */
    @PrePersist
    void fillCreatedAt() {
        if (createdAt == null) {
            createdAt = LocalDateTime.now();
        }
    }

    /** 그룹 id. 연관을 밖으로 흘리지 않기 위한 좁은 창이다(개인 기록이면 {@code null}). */
    public Long groupId() {
        return group == null ? null : group.getId();
    }
}
