package com.heattrip.heat_trip_backend.schedule.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Convert;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.ForeignKey;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

import org.hibernate.annotations.Check;
import org.hibernate.annotations.OnDelete;
import org.hibernate.annotations.OnDeleteAction;

import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.io.Serializable;
import java.time.LocalDate;
import java.util.Objects;

/**
 * 반복 규칙의 <b>하루짜리 예외</b> — 이슈 #421, 부모 #416.
 *
 * <h2>이 표가 없으면 반복은 못 쓴다</h2>
 * <p>"이번 주 목욕만 하루 미루기" 가 불가능해지고, 사용자는 반복을 지우고 다시 만든다.
 * 그러면 지난 기록도 함께 사라진다.
 *
 * <h2>{@code skip} 과 {@code override} 는 펼치기에서 같다</h2>
 * <p>둘 다 <b>그날은 규칙에서 빠진다</b>. 다른 것은 {@code override} 면 그날짜용 행이
 * 따로 하나 생긴다는 것뿐이고, 그 행은 자기 {@code on_date} 로 평범하게 조회된다.
 *
 * <p>그래도 {@code kind} 를 남기는 이유는 <b>사람이 읽기 위해서</b>다 — DB 를 들여다볼 때
 * "건너뛴 날" 과 "옮긴 날" 이 구별되지 않으면, 옮긴 행이 지워진 뒤 그 자리가 왜 비어
 * 있는지 알 수 없다.
 *
 * <h2>복합 PK 다</h2>
 * <p>한 규칙의 한 날짜에 예외는 <b>하나뿐</b>이다. 대리 키를 두면 같은 날짜에 두 줄이
 * 생길 수 있고, 그러면 펼치기가 그중 무엇을 볼지 정해야 한다.
 */
@Entity
@Table(name = "schedule_exception")
@IdClass(ScheduleException.Key.class)
@Check(name = "ck_schedule_exception_kind", constraints = "kind in ('skip','override')")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PRIVATE)
@Builder
public class ScheduleException {

    /** 어느 규칙의 예외인가. 규칙을 지우면 <b>함께 사라진다</b>. */
    @Id
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "schedule_id", nullable = false,
            foreignKey = @ForeignKey(name = "fk_schedexc_schedule"))
    @OnDelete(action = OnDeleteAction.CASCADE)
    private Schedule schedule;

    /** 어느 날인가. <b>사용자의 날짜</b>다(KST) — {@code Schedule.onDate} 와 같은 규약. */
    @Id
    @Column(name = "on_date", nullable = false)
    private LocalDate onDate;

    @Convert(converter = ScheduleExceptionKind.Codec.class)
    @Column(name = "kind", nullable = false, length = 10)
    private ScheduleExceptionKind kind;

    /** 복합 PK. Hibernate 가 컬럼 순서를 정하므로 {@code 01_schema.sql} 이 정본이다. */
    @NoArgsConstructor
    @AllArgsConstructor
    @Getter
    public static class Key implements Serializable {
        private Long schedule;
        private LocalDate onDate;

        @Override
        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Key key)) {
                return false;
            }
            return Objects.equals(schedule, key.schedule) && Objects.equals(onDate, key.onDate);
        }

        @Override
        public int hashCode() {
            return Objects.hash(schedule, onDate);
        }
    }
}
