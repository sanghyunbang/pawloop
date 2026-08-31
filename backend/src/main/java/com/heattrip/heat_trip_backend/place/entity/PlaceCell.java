package com.heattrip.heat_trip_backend.place.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Lob;
import jakarta.persistence.Table;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.io.Serializable;
import java.time.LocalDateTime;

/**
 * 격자 셀 하나의 장소 스냅샷 — 이슈 #40.
 *
 * <h2>만료가 없다</h2>
 * <p>{@link #fetchedAt} 은 <b>"갱신을 시도해도 되는가"</b> 만 정한다. 오래됐어도 예산이
 * 없으면 이 스냅샷을 그대로 준다.
 *
 * <p>만료를 두면 이런 경로가 생긴다 — 좌표를 훑는 요청이 며칠 이어져 예산이 매일 소진되면,
 * 만료된 셀들이 하나씩 사라지고 결국 <b>지도가 영구히 빈 화면</b>이 된다. 만료가 없으면
 * 그 경로 자체가 없다. <b>오래된 좌표를 보여 주는 것이 빈 지도보다 낫다.</b>
 *
 * <h2>{@link #payload} 는 우리 계약의 모양이다</h2>
 * <p>KTO 응답 원문이 아니라 {@code Place} 스키마로 정규화한 JSON 배열이다. 원문을 두면
 * 서빙할 때마다 KTO 의 모양을 다시 해석해야 하고, <b>그 해석이 두 곳에 살게 된다</b> —
 * 한쪽만 고치면 조용히 갈라진다.
 *
 * <h2>{@link #totalCount} 는 관측용이다</h2>
 * <p>KTO 가 말한 전체 수다. {@link #itemCount} 보다 크면 <b>잘렸다</b>는 뜻이고, 그러면
 * 셀 바깥 테두리의 장소가 빠진다. {@code numOfRows} 를 올려야 하는지를 추측이 아니라
 * 관측으로 알 수 있게 하는 값이다.
 */
@Entity
@Table(name = "place_cell")
@IdClass(PlaceCell.Key.class)
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class PlaceCell {

    @Id
    @Column(name = "lat_idx", nullable = false)
    private Integer latIdx;

    @Id
    @Column(name = "lng_idx", nullable = false)
    private Integer lngIdx;

    /** 정규화된 {@code Place} 배열 JSON. */
    @Lob
    @Column(name = "payload", nullable = false, columnDefinition = "LONGTEXT")
    private String payload;

    /** {@link #payload} 에 실제로 든 장소 수. */
    @Column(name = "item_count", nullable = false)
    private int itemCount;

    /** KTO 가 말한 전체 수. {@link #itemCount} 보다 크면 잘린 것이다. */
    @Builder.Default
    @Column(name = "total_count", nullable = false)
    private int totalCount = 0;

    /** 마지막으로 <b>성공</b>한 시각. 갱신을 시도할지의 기준이다. */
    @Column(name = "fetched_at", nullable = false)
    private LocalDateTime fetchedAt;

    /** 마지막으로 실패한 시각. 백오프의 기준이다. */
    @Column(name = "failed_at")
    private LocalDateTime failedAt;

    /** 연속 실패 횟수. 성공하면 0 으로 돌아간다. */
    @Builder.Default
    @Column(name = "fail_streak", nullable = false)
    private int failStreak = 0;

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    public static class Key implements Serializable {
        private Integer latIdx;
        private Integer lngIdx;

        @Override
        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Key key)) {
                return false;
            }
            return java.util.Objects.equals(latIdx, key.latIdx)
                    && java.util.Objects.equals(lngIdx, key.lngIdx);
        }

        @Override
        public int hashCode() {
            return java.util.Objects.hash(latIdx, lngIdx);
        }
    }
}
