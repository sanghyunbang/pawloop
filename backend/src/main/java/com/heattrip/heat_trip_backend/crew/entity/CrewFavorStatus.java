package com.heattrip.heat_trip_backend.crew.entity;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

/**
 * 품앗이 한 건의 상태 — 이슈 #417.
 *
 * <h2>둘뿐이다</h2>
 * <p>{@link #OPEN} 과 {@link #TAKEN}. "끝났다"({@code done})를 안 둔다 — <b>끝났는지는 일정이
 * 안다.</b> 맡으면 크루 일정에 한 줄이 생기고, 그 줄의 완료 표시가 "했다" 를 말한다. 여기에
 * 또 두면 같은 사실이 두 곳에 살고, 한쪽만 고쳐지는 날이 온다.
 *
 * <p>지우는 것은 상태가 아니라 삭제다 — 부탁을 거둬들이면 행이 사라진다. "취소됨" 을 남기면
 * 목록이 안 지워지는 카드로 점점 길어진다.
 */
public enum CrewFavorStatus {

    /** 아직 아무도 안 맡았다. */
    OPEN("open"),

    /** 한 명이 맡았다. {@code taken_by} 와 {@code schedule_id} 가 함께 찬다. */
    TAKEN("taken");

    private final String wire;

    CrewFavorStatus(String wire) {
        this.wire = wire;
    }

    @JsonValue
    public String wire() {
        return wire;
    }

    @JsonCreator
    public static CrewFavorStatus of(String value) {
        for (CrewFavorStatus status : values()) {
            if (status.wire.equals(value)) {
                return status;
            }
        }
        throw new IllegalArgumentException("품앗이 상태는 open · taken 중 하나여야 합니다.");
    }

    public boolean isOpen() {
        return this == CrewFavorStatus.OPEN;
    }

    /** DB 에는 {@link #wire} 값이 들어간다 — {@code CrewVisibility.Codec} 과 같은 규약이다. */
    @Converter(autoApply = false)
    public static class Codec implements AttributeConverter<CrewFavorStatus, String> {
        @Override
        public String convertToDatabaseColumn(CrewFavorStatus attribute) {
            return attribute == null ? null : attribute.wire;
        }

        @Override
        public CrewFavorStatus convertToEntityAttribute(String dbData) {
            return dbData == null ? null : of(dbData);
        }
    }
}
