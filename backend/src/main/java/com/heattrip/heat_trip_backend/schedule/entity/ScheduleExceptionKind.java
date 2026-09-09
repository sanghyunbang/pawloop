package com.heattrip.heat_trip_backend.schedule.entity;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

/**
 * 예외가 어떤 종류인가 — 이슈 #421.
 *
 * <p>펼치기에서는 <b>둘이 같다</b>(그날은 규칙에서 빠진다). 자세한 것은
 * {@link ScheduleException} 의 javadoc.
 */
public enum ScheduleExceptionKind {

    /** 그날은 안 한다. 대신할 행이 없다. */
    SKIP("skip"),

    /** 그날은 <b>따로 만든 행</b>이 대신한다. */
    OVERRIDE("override");

    private final String wire;

    ScheduleExceptionKind(String wire) {
        this.wire = wire;
    }

    @JsonValue
    public String wire() {
        return wire;
    }

    @JsonCreator
    public static ScheduleExceptionKind of(String value) {
        for (ScheduleExceptionKind kind : values()) {
            if (kind.wire.equals(value)) {
                return kind;
            }
        }
        throw new IllegalArgumentException("예외 종류는 skip · override 중 하나여야 합니다.");
    }

    @Converter(autoApply = false)
    public static class Codec implements AttributeConverter<ScheduleExceptionKind, String> {
        @Override
        public String convertToDatabaseColumn(ScheduleExceptionKind attribute) {
            return attribute == null ? null : attribute.wire;
        }

        @Override
        public ScheduleExceptionKind convertToEntityAttribute(String dbData) {
            return dbData == null ? null : of(dbData);
        }
    }
}
