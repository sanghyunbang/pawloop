package com.heattrip.heat_trip_backend.crew.entity;

import com.heattrip.heat_trip_backend.crew.CrewTime;
import com.heattrip.heat_trip_backend.dog.entity.Dog;
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

/**
 * 품앗이 한 건 — "12/24 오후, 보리 두 시간만 봐 주실 분". 이슈 #417.
 *
 * <h2>돈이 안 붙는다</h2>
 * <p>이슈가 스스로 그은 선이다 — <b>결제·평점·보증·중개는 안 한다.</b> 돈이 오가면 우리가
 * 중개자가 되고 사고 시 배상·신고 의무가 따라온다. 그래서 이 표에는 금액도, 평점도, 후기도
 * 없다. 여기서 하는 일은 <b>약속을 적는 것</b>까지다.
 *
 * <h2>끝났는지는 이 표가 모른다</h2>
 * <p>맡으면 크루 소유 일정 한 줄이 생기고({@code schedule_id}), <b>그 줄의 완료 표시가
 * "했다" 를 말한다.</b> 여기에 상태를 하나 더 두면 같은 사실이 두 곳에 살고 한쪽만
 * 고쳐진다({@link CrewFavorStatus} javadoc).
 *
 * <h2>{@code schedule_id} 에 FK 가 없다</h2>
 * <p>걸려면 이 엔티티가 {@code schedule.entity.Schedule} 을 들어야 하고 그건 모듈 경계를
 * 넘는다. SQL 에만 적어 두면 {@code 01_schema.sql} 재생성에서 조용히 사라진다 —
 * {@code schedule.care_log_id} 가 #420 에서 같은 자리였다.
 *
 * <h2>아이는 <b>부탁한 사람</b>의 것이다</h2>
 * <p>맡는 사람 눈으로는 남의 아이다. 그래서 소유권은 <b>올릴 때</b> 한 번 확인하고
 * ({@code DogOwnership.requireMineEntity}) 행을 든다. {@code ON DELETE SET NULL} 이라
 * 아이를 보내도 부탁은 남는다 — 이미 맡은 사람이 있는 약속이 조용히 사라지면 안 된다.
 */
@Entity
@Table(
        name = "crew_favor",
        indexes = {
                // 크루 홈이 묻는 유일한 질문 — "이 크루의 부탁을 가까운 날짜부터".
                @Index(name = "idx_crew_favor_crew", columnList = "crew_id, on_date")
        })
@Check(name = "ck_crew_favor_slot", constraints = "slot in ('morning','afternoon','evening')")
@Check(name = "ck_crew_favor_status", constraints = "status in ('open','taken')")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PRIVATE)
@Builder
public class CrewFavor {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** 어느 크루의 부탁인가. 크루를 지우면 함께 사라진다. */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "crew_id", nullable = false,
            foreignKey = @ForeignKey(name = "fk_crew_favor_crew"))
    @OnDelete(action = OnDeleteAction.CASCADE)
    private Crew crew;

    /**
     * 부탁한 사람. 탈퇴하면 {@code null} 이 되고 화면은 "알 수 없음" 으로 그린다 —
     * 이미 맡은 사람이 있는 약속을 지우면 그 사람의 달력에서만 사라진다.
     */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "asked_by", foreignKey = @ForeignKey(name = "fk_crew_favor_asker"))
    @OnDelete(action = OnDeleteAction.SET_NULL)
    private User askedBy;

    /** 맡은 사람. {@code null} 이면 아직 아무도 안 맡았다. */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "taken_by", foreignKey = @ForeignKey(name = "fk_crew_favor_taker"))
    @OnDelete(action = OnDeleteAction.SET_NULL)
    private User takenBy;

    /** 어느 아이를 맡기나. 없어도 된다 — 아이를 아직 등록 안 한 사람도 부탁할 수 있다. */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "dog_id", foreignKey = @ForeignKey(name = "fk_crew_favor_dog"))
    @OnDelete(action = OnDeleteAction.SET_NULL)
    private Dog dog;

    /** 사람이 고른 날짜(KST). {@code schedule.on_date} 와 같은 규약이다 — UTC 로 안 눕힌다. */
    @Column(name = "on_date", nullable = false)
    private LocalDate onDate;

    @Convert(converter = CrewFavorSlot.Codec.class)
    @Column(name = "slot", nullable = false, length = 10)
    private CrewFavorSlot slot;

    /** 한 줄. "두 시간만 부탁드려요". */
    @Column(name = "note", length = 200)
    private String note;

    @Convert(converter = CrewFavorStatus.Codec.class)
    @Column(name = "status", nullable = false, length = 10)
    private CrewFavorStatus status;

    /**
     * 맡았을 때 생긴 크루 일정. <b>FK 가 없다</b> — 클래스 javadoc 참조.
     *
     * <p>무르면 이 id 로 그 줄을 거둔다. 안 들고 있으면 무엇을 거둘지 모른다.
     */
    @Column(name = "schedule_id")
    private Long scheduleId;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at")
    private LocalDateTime updatedAt;

    public static final int MAX_NOTE_LENGTH = 200;

    @PrePersist
    void onCreate() {
        if (createdAt == null) {
            createdAt = CrewTime.nowUtc();
        }
        if (status == null) {
            status = CrewFavorStatus.OPEN;
        }
    }

    @PreUpdate
    void onUpdate() {
        updatedAt = CrewTime.nowUtc();
    }

    /**
     * 한 명이 맡는다. <b>이미 맡은 것은 다시 못 맡는다</b> — 부르는 쪽이 그 판정을 하고,
     * 여기서는 상태만 옮긴다.
     */
    public void takenBy(User taker, long scheduleId) {
        this.takenBy = taker;
        this.scheduleId = scheduleId;
        this.status = CrewFavorStatus.TAKEN;
    }

    /** 무른다. 달력의 줄을 거두는 것은 부르는 쪽이다 — 그쪽이 {@code schedule} 을 안다. */
    public void released() {
        this.takenBy = null;
        this.scheduleId = null;
        this.status = CrewFavorStatus.OPEN;
    }

    public boolean isOpen() {
        return status != null && status.isOpen();
    }
}
