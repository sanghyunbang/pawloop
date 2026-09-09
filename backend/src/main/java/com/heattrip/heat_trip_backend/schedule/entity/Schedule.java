package com.heattrip.heat_trip_backend.schedule.entity;

import com.heattrip.heat_trip_backend.dog.entity.Dog;
import com.heattrip.heat_trip_backend.schedule.ScheduleTime;
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
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.Version;

import org.hibernate.annotations.Check;
import org.hibernate.annotations.OnDelete;
import org.hibernate.annotations.OnDeleteAction;

import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;

/**
 * 앞으로 할 일 하나 — 이슈 #418, 부모 #416. 문서는 {@code docs/03-database/schema.md}.
 *
 * <h2>이 표가 없어서 결정이 채팅에 흩어지고 있었다</h2>
 * <p>지금 앱은 <b>지나간 일만</b> 안다. {@code care_log} 는 "누가 언제 했다" 이고
 * ({@code occurred_at} 이 서버 시계라 미래를 못 넣는다), {@code walk} 은 끝난 산책이다.
 * 앞으로 할 일을 적을 자리가 한 곳도 없었다.
 *
 * <p>그래서 가족은 병원 일정을 <b>채팅으로</b> 조율하고, 그 결정은 스크롤 위로 사라진다.
 * {@code docs/00-product/feature-family-care.md} 의 S3 가 그 장면을 그대로 적고 있고, 같은
 * 문서가 문제로 꼽은 것이 "전달 누락·중복 질문" 이다.
 *
 * <h2>{@code ownerKind} + {@code ownerRef} — 세 주인을 한 표에</h2>
 * <p>{@link ScheduleOwnerKind} 의 javadoc 에 이유를 적었다. 요약하면 {@code chat_room} 이
 * {@code origin_kind}/{@code origin_ref} 로 푼 것과 같은 문제이고 같은 답이다.
 *
 * <p><b>FK 를 안 건다.</b> 세 도메인을 가리키는 컬럼 하나에 FK 를 걸 수 없다. 대신 서비스가
 * 소유권을 확인한다 — {@code chat_room} 도 같은 자리에서 같은 선택을 했다.
 *
 * <h2>{@code dog} 는 {@code owner} 와 별개다</h2>
 * <p>"가족 소유인데 보리 것" 이 흔하다("토요일 보리 병원, 아빠 담당"). {@code owner} 로만
 * 두면 어느 아이 것인지 적을 자리가 없고, {@code dog} 로만 두면 "사료 주문" 처럼 아이 하나에
 * 안 묶이는 일을 못 적는다.
 *
 * <p>{@code ON DELETE SET NULL} — 아이를 지워도 그날 병원에 갔다는 계획은 남는다.
 * {@code care_log.dog_id} 가 같은 답을 골랐다(#154).
 *
 * <h2>{@code atTime} 이 {@code null} 일 수 있다</h2>
 * <p>시각 없는 일정이 많다 — "이번 주말 목욕". 0시로 채워 넣으면 화면이 <b>"00:00 목욕"</b>
 * 이라고 적게 되고, 그건 사용자가 안 정한 것을 정한 것처럼 보이게 한다.
 *
 * <h2>{@link Version} — 낙관적 잠금</h2>
 * <p>가족 여럿이 같은 일정을 고친다. 실시간 공동 편집은 안 한다(소켓 #84 가 아직 없고,
 * 일정은 초당 여러 번 고치는 것이 아니다). 대신 뒤에 온 쪽이 <b>409</b> 를 받고 최신 값을
 * 본다 — 조용히 덮어쓰면 아빠가 옮긴 병원 시각이 엄마의 옛 화면으로 되돌아간다.
 *
 * <h2>좌표가 없다</h2>
 * <p>일정에 위치 컬럼을 두지 않는다. A안(#235)에서 좌표는 기기를 안 떠나고, 일정은 그것이
 * 필요한 기능이 아니다 — 장소가 필요해지는 날에는 {@code walk} 처럼 카탈로그 참조
 * (출처 + contentId)를 쓴다.
 */
@Entity
@Table(
        name = "schedule",
        indexes = {
                // 달력이 묻는 유일한 질문 — "이 주인의 이 기간". 세 컬럼이 그 순서다.
                @Index(name = "idx_schedule_owner_date", columnList = "owner_kind, owner_ref, on_date"),
                // "보리 것만" 필터. dog_id 로 시작하지 않으면 위 인덱스를 못 쓴다.
                @Index(name = "idx_schedule_dog_date", columnList = "dog_id, on_date")
        })
@Check(name = "ck_schedule_owner_kind", constraints = "owner_kind in ('dog','group','room')")
@Check(name = "ck_schedule_kind",
        constraints = "kind in ('walk','vet','med','groom','bath','food','etc')")
@Check(name = "ck_schedule_status", constraints = "status in ('planned','done','skipped')")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PRIVATE)
@Builder
public class Schedule {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Convert(converter = ScheduleOwnerKind.Codec.class)
    @Column(name = "owner_kind", nullable = false, length = 10)
    private ScheduleOwnerKind ownerKind;

    /** {@link #ownerKind} 도메인의 id. <b>FK 가 아니다</b> — 클래스 javadoc 참조. */
    @Column(name = "owner_ref", nullable = false)
    private Long ownerRef;

    /** 어느 아이 것인가. <b>{@code null} 일 수 있다</b> — "사료 주문" 은 아이에 안 묶인다. */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "dog_id", foreignKey = @ForeignKey(name = "fk_schedule_dog"))
    @OnDelete(action = OnDeleteAction.SET_NULL)
    private Dog dog;

    @Convert(converter = ScheduleKind.Codec.class)
    @Column(name = "kind", nullable = false, length = 10)
    private ScheduleKind kind;

    @Column(name = "title", nullable = false, length = 100)
    private String title;

    @Column(name = "memo", length = 500)
    private String memo;

    /**
     * 날짜는 <b>사용자의 날짜</b>다(KST). {@code created_at} 과 달리 UTC 로 눕히지 않는다 —
     * 눕히면 밤 일정이 하루 넘어가고 달력이 다른 칸에 그린다({@link ScheduleTime} 참조).
     */
    @Column(name = "on_date", nullable = false)
    private LocalDate onDate;

    /** 시각. <b>{@code null} 이면 "하루 종일"</b> 이다 — 클래스 javadoc 참조. */
    @Column(name = "at_time")
    private LocalTime atTime;

    /**
     * 맡기로 한 사람. <b>{@code null} 일 수 있다</b> — 정하지 않은 일도 적어 둬야 한다.
     *
     * <p>탈퇴하면 {@code null} 이 된다({@code ON DELETE SET NULL}). 담당자가 사라졌다고
     * 일정까지 지우면, 그 일이 남아 있다는 사실을 아무도 모르게 된다.
     */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "assignee", foreignKey = @ForeignKey(name = "fk_schedule_assignee"))
    @OnDelete(action = OnDeleteAction.SET_NULL)
    private User assignee;

    @Convert(converter = ScheduleStatus.Codec.class)
    @Column(name = "status", nullable = false, length = 10)
    private ScheduleStatus status;

    /** 완료·건너뜀으로 바꾼 시각. {@code planned} 로 되돌리면 다시 {@code null} 이다. */
    @Column(name = "done_at")
    private LocalDateTime doneAt;

    @Version
    @Column(name = "version", nullable = false)
    private Integer version;

    /** 적은 사람. 탈퇴하면 그 사람이 적은 일정도 함께 사라진다 — 그 사람의 계획이다. */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "created_by", nullable = false,
            foreignKey = @ForeignKey(name = "fk_schedule_created_by"))
    @OnDelete(action = OnDeleteAction.CASCADE)
    private User createdBy;

    /**
     * 마지막으로 고친 사람. 화면이 "○○님이 방금 고쳤어요" 를 이 값으로 만든다.
     *
     * <p>{@code walk_note.updated_by} 와 같은 자리다 — 여럿이 고치는 것에는 누가 고쳤는지가
     * 함께 있어야 한다.
     */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "updated_by", foreignKey = @ForeignKey(name = "fk_schedule_updated_by"))
    @OnDelete(action = OnDeleteAction.SET_NULL)
    private User updatedBy;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at")
    private LocalDateTime updatedAt;

    @PrePersist
    void onCreate() {
        if (createdAt == null) {
            createdAt = ScheduleTime.nowUtc();
        }
        if (status == null) {
            status = ScheduleStatus.PLANNED;
        }
    }

    @PreUpdate
    void onUpdate() {
        updatedAt = ScheduleTime.nowUtc();
    }

    /**
     * 내용을 고친다. <b>상태는 여기서 안 바꾼다</b> — {@link #markStatus} 가 따로 있다.
     *
     * <p>둘을 한 메서드로 두면 "제목만 고치려다 상태가 함께 바뀌는" 호출이 생긴다.
     */
    public void edit(ScheduleKind kind, String title, String memo, LocalDate onDate,
                     LocalTime atTime, Dog dog, User assignee, User editor) {
        this.kind = kind;
        this.title = title;
        this.memo = memo;
        this.onDate = onDate;
        this.atTime = atTime;
        this.dog = dog;
        this.assignee = assignee;
        this.updatedBy = editor;
    }

    /**
     * 상태를 바꾼다.
     *
     * <p>{@code planned} 로 되돌리면 {@link #doneAt} 을 <b>지운다</b> — 안 지우면 "아직 안 한
     * 일" 에 완료 시각이 붙어 있게 되고, 그 값을 읽는 화면이 언젠가 그것을 그린다.
     */
    public void markStatus(ScheduleStatus next, LocalDateTime now, User editor) {
        this.status = next;
        this.doneAt = next == ScheduleStatus.PLANNED ? null : now;
        this.updatedBy = editor;
    }
}
