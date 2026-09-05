package com.heattrip.heat_trip_backend.care.entity;

import com.heattrip.heat_trip_backend.care.CareTime;
import com.heattrip.heat_trip_backend.dog.entity.Dog;
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
 * <h2>{@code dog_id} — FK 는 걸려 있고({@code fk_carelog_dog}, #154), 값은 아직 <b>항상 {@code null}</b> 이다</h2>
 *
 * <p>2026-09-06(#154)에 이 필드가 스칼라 {@code Long} 에서 {@code @ManyToOne Dog} 로 바뀌었다.
 * 그 전에는 Hibernate 가 FK 를 만들지 않아서, 마이그레이션에서 {@code ALTER} 로 더하면
 * 운영 DB 에는 있고 커밋된 스키마({@code 01_schema.sql} — 엔티티로 만든 DB 에서 뽑은 파일)에는
 * 없는 제약이 되어 다음 재생성 때 조용히 사라졌다. 이제는 엔티티에서 나오므로 재생성에
 * 살아남고, 이미 있는 DB 에는 {@code 22_care_log_dog_fk.sql} 이 같은 모양으로 건다.
 *
 * <p>모듈 경계는 {@code Dog} 에 붙은 {@code @NamedInterface("entity")} 가 열고, {@code walk} 가
 * 같은 길로 참조한다. {@code ModularityBaselineTest} 는 이 참조로 움직이지 않았다 —
 * 실측 232 → 232 (#154 PR 에 위반 목록 대조를 적었다).
 *
 * <p><b>{@code ON DELETE SET NULL} 이다.</b> 케어는 "누가 언제 무엇을 했는가" 의 기록이라
 * 반려동물이 지워져도 그 사실은 남아야 한다 — {@code group_id}·{@code done_by} 가 같은 질문에
 * 같은 답을 했다. {@code walk.dog_id} 가 CASCADE 인 것과 다른 이유는 산책은 그 개의 기록이고
 * 케어는 가족의 기록이기 때문이다. 사용자 탈퇴({@code users} 하드 삭제)는 {@code dog} 을
 * CASCADE 로 지우고 그 삭제가 여기를 SET NULL 로 훑는다 — {@code idx_carelog_dog} 가 그 자리다.
 *
 * <p><b>값이 아직 {@code null} 인 이유는 쓰기 경로가 {@code dogId} 를 안 받아서다.</b>
 * 받으려면 "가족 구성원이 남의 반려동물 id 를 알 수 있는가" 가 먼저 정해져야 하고, 그것은
 * #209 의 {@code Dogs-high-3}(가족 공유 가시성)이 소유한다. 그날 {@code CareService.record} 가
 * 대상 개체를 검증해 여기에 넣는다. 그때까지 FK 는 "잘못된 id 는 못 들어간다" 만 지킨다.
 *
 * <p><b>#9 와 헷갈리지 말 것.</b> #9({@code refresh_token})는 탈퇴 경로가 DB 삭제 순서에
 * 묶이는 것을 피하려고 <b>일부러</b> 안 걸었고 지금도 안 건다. 여기는 걸었다.
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
                @Index(name = "idx_carelog_doneby", columnList = "done_by"),
                // dog 삭제 시 SET NULL 이 훑는 자리이자, 언젠가 "이 반려동물의 케어 기록" 을
                // 기간으로 훑을 자리(#154). idx_carelog_group 과 같은 모양이다.
                @Index(name = "idx_carelog_dog", columnList = "dog_id, occurred_at")
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
     * 대상 반려동물. FK 는 있고({@code fk_carelog_dog}, {@code ON DELETE SET NULL}) 값은 아직
     * <b>항상 {@code null}</b> 이다 — 클래스 javadoc 의 {@code dog_id} 절.
     *
     * <p>{@code CareService.record} 가 요청 본문의 {@code dogId} 를 <b>읽지 않는다.</b>
     * 이 경로가 <b>그룹 단위 기록</b>이라 대상 개체를 아직 받지 않기 때문이고, 받는 날의
     * 전제(가족 공유 가시성)는 #209 {@code Dogs-high-3} 이 정한다.
     */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "dog_id",
            foreignKey = @ForeignKey(name = "fk_carelog_dog"))
    @OnDelete(action = OnDeleteAction.SET_NULL)
    private Dog dog;

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
     * 애플리케이션이 값을 안 넣어도 행이 만들어지게 한다. 값은 <b>UTC</b> 다({@link CareTime}, #306) —
     * {@code occurred_at} 이 서비스 존인 것과 다르다.
     *
     * <p>DB 기본값만으로는 부족하다 — Hibernate 는 INSERT 에 컬럼을 항상 실어 보내므로
     * 필드가 {@code null} 이면 NOT NULL 위반으로 죽는다. {@code family_group}·chat 세 표가
     * 쓰는 것과 같은 방식이다.
     */
    @PrePersist
    void fillCreatedAt() {
        if (createdAt == null) {
            createdAt = CareTime.nowUtc();
        }
    }

    /** 그룹 id. 연관을 밖으로 흘리지 않기 위한 좁은 창이다(개인 기록이면 {@code null}). */
    public Long groupId() {
        return group == null ? null : group.getId();
    }

    /** 대상 반려동물 id. {@link #groupId()} 와 같은 좁은 창이다 — 아직은 항상 {@code null}. */
    public Long dogId() {
        return dog == null ? null : dog.getId();
    }
}
