package com.heattrip.heat_trip_backend.place.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Table;

import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.io.Serializable;
import java.time.LocalDate;

/**
 * 하루치 KTO 호출 예산 — 이슈 #40.
 *
 * <h2>이 행이 상한을 지키는 유일한 장치다</h2>
 * <p>KTO 일 한도는 1,000콜이고 넘기면 지도 탭이 죽는다. 카운터를 프로세스 안에 두면
 * <b>재기동할 때마다 0 이 된다</b> — 하루 세 번 배포하면 상한이 구조적으로 3배가 되고,
 * 인스턴스가 둘이면 각자 센다. 그래서 DB 행이다.
 *
 * <p><b>이 엔티티로 읽고 쓰지 않는다.</b> 예약은 조건부 UPDATE 한 문장이라
 * {@code KtoCallBudgetRepository} 의 네이티브 쿼리가 한다 — 읽어서 비교하고 쓰면 두 문장
 * 사이가 열리고, 그 틈으로 두 요청이 같은 값을 읽어 둘 다 통과한다(📌 #86 원칙 5).
 * 이 클래스가 있는 이유는 <b>스키마를 엔티티가 소유하게</b> 하기 위해서다
 * ({@code SchemaDdlDriftTest} 가 커밋된 DDL 과 엔티티를 대조한다).
 *
 * <h2>{@code day} 는 KST 날짜다</h2>
 * <p>애플리케이션이 {@code LocalDate.now(ZoneId.of("Asia/Seoul"))} 로 만들어 넘긴다.
 * DB 세션 타임존을 믿지 않는다 — 운영과 로컬이 다를 수 있고, 그 차이는 <b>날 경계에서만</b>
 * 드러나서 찾기 어렵다.
 */
@Entity
@Table(name = "kto_call_budget")
@IdClass(KtoCallBudgetRow.Key.class)
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
public class KtoCallBudgetRow {

    /** KST 기준 날짜. */
    @Id
    @Column(name = "day", nullable = false)
    private LocalDate day;

    /** {@code nearby} | {@code detail}. */
    @Id
    @Column(name = "pool", nullable = false, length = 16)
    private String pool;

    /**
     * 오늘 이 풀이 예약한 호출 수.
     *
     * <p><b>실패해도 환불하지 않는다.</b> 환불하면 타임아웃을 유도하는 것만으로 무한히
     * 호출할 수 있고, 무엇보다 우리 카운터와 KTO 의 카운터가 갈라진다 — 상대는 실패한
     * 호출도 센다.
     */
    @Column(name = "used", nullable = false)
    private int used;

    /** 복합 키. {@code @IdClass} 규약상 public 기본 생성자와 equals/hashCode 가 필요하다. */
    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    public static class Key implements Serializable {
        private LocalDate day;
        private String pool;

        @Override
        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Key key)) {
                return false;
            }
            return java.util.Objects.equals(day, key.day) && java.util.Objects.equals(pool, key.pool);
        }

        @Override
        public int hashCode() {
            return java.util.Objects.hash(day, pool);
        }
    }
}
