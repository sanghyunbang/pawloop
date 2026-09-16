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
 * <p><b>2026-09-16(#563)부터 값이 실제로 들어간다.</b> {@code CareService.record} 가 요청의
 * {@code dogId} 를 {@code DogOwnership.requireInFamilyEntity} 로 확인해 여기에 넣는다. 그
 * 전에는 쓰기 경로가 {@code dogId} 를 안 받아 <b>항상 {@code null}</b> 이었고, 그래서 아이가
 * 둘인 집의 카드가 두 아이 기록을 한 칸에서 섞어 셌다.
 *
 * <p><b>옛 행은 여전히 {@code null} 이다.</b> 조회가 그걸 안다 — {@code CareService.logsOf} 의
 * {@code matchesDog} 가 "아이를 안 물었거나, 행에 아이가 없거나, 같으면" 으로 센다. 옛
 * 기록을 지어낸 아이로 채우지 않는 이유는 그때 어느 아이였는지 아무도 모르기 때문이다.
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
// 누가 손으로 INSERT 해도 여덟 번째 종류는 들어가지 못한다.
//
// **이 문자열을 늘리는 것만으로는 운영 DB 가 안 바뀐다.** ddl-auto=validate 는 CHECK 를
// 보지 않아 부팅은 그대로 뜨고, 첫 기록이 실패한다 — poop·pee 를 더할 때
// mysql/post-start/29_care_type_poop.sql 을 함께 돌리는 이유다(#340).
// ── "종류도 항목도 없는 행" 은 DB 가 못 막는다 (#560, 실측) ──────────────────
//
// 그런 행은 어느 칸의 기록도 아니라서 화면에 안 뜨고, 안 뜨니 지울 수도 없다. 그래서
// CHECK (type IS NOT NULL OR care_item_id IS NOT NULL) 을 걸려고 했는데 **MySQL 8 이
// 거절한다**:
//
//   Column 'care_item_id' cannot be used in a check constraint 'ck_carelog_source':
//   needed in a foreign key constraint 'fk_carelog_item' referential action.
//
// SET NULL 로 값을 쓰는 FK 가 걸린 컬럼은 CHECK 에서 못 읽는다. fk_carelog_item 의
// SET NULL 은 "항목을 지워도 기록은 남는다" 라서 포기할 수 없는 쪽이다.
//
// **더 나쁜 것은 조용히 실패했다는 점이다.** CREATE TABLE 안에 함께 적으면 MySQL 이 받아
// 주는데(ALTER 로 더할 때만 거절한다), 그러면 Hibernate 가 나중에 ALTER 로 거는
// fk_carelog_item 이 실패하고 **정본에서 FK 가 통째로 사라진다.** 01_schema.sql 을 재생성해
// 보고 알았다 — 커밋 전에 되돌렸고, 그 자리를 막는 게이트를 DeclaredForeignKeysExistTest 로
// 만들었다.
//
// 그래서 이 불변식은 CareService.record 가 지킨다(type 과 careItemId 는 정확히 하나).
@Check(name = "ck_carelog_type",
        constraints = "type in ('water','meal','walk','med','vet','poop','pee')")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PRIVATE)
@Builder
public class CareLog {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * 대상 반려동물. FK 는 {@code fk_carelog_dog}({@code ON DELETE SET NULL}) 다.
     *
     * <p><b>2026-09-15(#563)부터 값이 들어간다.</b> {@code CareService.record} 가 요청의
     * {@code dogId} 를 {@code DogOwnership.requireInFamilyEntity} 로 확인해 넣는다. 그 전에
     * 쌓인 행은 여전히 {@code null} 이고, 조회가 그걸 안다 — 클래스 javadoc 의 {@code dog_id} 절.
     */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "dog_id",
            foreignKey = @ForeignKey(name = "fk_carelog_dog"))
    @OnDelete(action = OnDeleteAction.SET_NULL)
    private Dog dog;

    /**
     * 어느 항목의 기록인가 — 이슈 #560. <b>직접 만든 항목일 때만 채워진다.</b>
     *
     * <p>기본 일곱({@code water}…{@code pee})은 {@link #type} 으로 세므로 여기가 비어 있다.
     * 그래서 이 컬럼이 생기기 전의 행도, 산책 트래킹이 {@code type='walk'} 로 남기는 행도
     * <b>고칠 것이 없다.</b> {@code CareItem} 의 javadoc "기존 기록을 한 행도 안 건드린다" 절이
     * 그 이야기다.
     *
     * <p>{@code ON DELETE SET NULL} 이다. 항목을 지우는 길은 화면에 없고(접기만 있다), 그래도
     * 언젠가 정말 지우는 날이 오면 <b>그 기록까지 사라지면 안 된다</b> — "무엇을 했는지" 의
     * 이름표를 잃을 뿐 "누가 언제 했다" 는 사실은 남는다. {@code dog}·{@code group}·
     * {@code doneBy} 가 같은 질문에 같은 답을 했다.
     */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "care_item_id",
            foreignKey = @ForeignKey(name = "fk_carelog_item"))
    @OnDelete(action = OnDeleteAction.SET_NULL)
    private CareItem careItem;

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

    /**
     * 기본 일곱이면 그 종류, <b>직접 만든 항목이면 {@code null}</b> — 이슈 #560.
     *
     * <h2>왜 NULL 을 열었나</h2>
     *
     * <p>2026-09-16 전에는 {@code NOT NULL} 이었다. 그런데 사용자가 만든 "양치" 를 누르면
     * <b>넣을 값이 없다</b> — 일곱 중 아무거나 넣으면 그 칸이 양치 기록을 함께 세고,
     * {@code 'custom'} 같은 값을 더하면 종류가 아닌 것이 종류 목록에 들어앉는다.
     *
     * <p>그래서 "종류" 를 <b>기본 일곱일 때만 있는 것</b>으로 정했다. 대신 행마다 {@code type}
     * 과 {@code careItem} 중 <b>적어도 하나</b>는 있어야 하는데, <b>그것을 DB 가 못 막는다</b> —
     * 클래스 위 주석에 그 실측을 적어 뒀다. {@code CareService.record} 가 그 불변식을 진다.
     *
     * <p><b>옛 행은 한 줄도 안 바뀐다.</b> 컬럼을 넓히는 쪽이라 이미 쌓인 값은 그대로이고,
     * 산책 트래킹이 {@code type='walk'} 로 남기는 경로도 그대로다.
     */
    @Convert(converter = CareType.Codec.class)
    @Column(name = "type", length = 10)
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

    /**
     * 대상 반려동물 id. {@link #groupId()} 와 같은 좁은 창이다.
     *
     * <p>2026-09-15(#563) 전에 쌓인 행은 {@code null} 이다 — {@link #dog} 의 javadoc.
     */
    public Long dogId() {
        return dog == null ? null : dog.getId();
    }

    /**
     * 이 행에 <b>적혀 있는</b> 항목 id — 직접 만든 항목의 기록일 때만 있다(#560).
     *
     * <p><b>"어느 칸에 세어지는가" 와 다르다.</b> 그 답은 {@code CareService.itemIdOf} 가
     * 내놓는다 — 기본 일곱의 기록은 여기가 비어 있고 {@link #type} 으로 세어지기 때문이다.
     * 응답에 실리는 값은 그쪽이다.
     */
    public Long careItemId() {
        return careItem == null ? null : careItem.getId();
    }
}
