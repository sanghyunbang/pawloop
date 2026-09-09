package com.heattrip.heat_trip_backend.schedule.entity;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

import java.util.Arrays;
import java.util.stream.Collectors;

/**
 * 일정 하나의 상태 — 이슈 #418.
 *
 * <h2>왜 셋인가</h2>
 * <p>{@code planned} 와 {@code done} 만 두면 <b>"안 했다" 를 적을 자리가 없다.</b> 비 와서
 * 산책을 건너뛴 날은 실패가 아니라 그냥 안 한 날이고, 그것을 지우게 하면 다음 주에 같은
 * 일정을 다시 만들어야 한다. {@code skipped} 는 "봤고, 안 했다" 를 남기는 자리다.
 *
 * <p>지우기와도 다르다. 지우면 그 일이 있었다는 것 자체가 사라진다.
 */
public enum ScheduleStatus {

    /** 아직 안 했다. 만들면 이 상태다. */
    PLANNED("planned"),

    /** 했다. 종류에 따라 케어 로그로 이어진다(#420). */
    DONE("done"),

    /** 봤고, 안 했다. <b>지우기와 다르다</b> — 지우면 있었다는 것 자체가 사라진다. */
    SKIPPED("skipped");

    private final String wire;

    ScheduleStatus(String wire) {
        this.wire = wire;
    }

    @JsonValue
    public String wire() {
        return wire;
    }

    @JsonCreator
    public static ScheduleStatus of(String value) {
        for (ScheduleStatus status : values()) {
            if (status.wire.equals(value)) {
                return status;
            }
        }
        throw new IllegalArgumentException("일정 상태는 " + allowed() + " 중 하나여야 합니다.");
    }

    private static String allowed() {
        return Arrays.stream(values()).map(ScheduleStatus::wire).collect(Collectors.joining(" · "));
    }

    @Converter
    public static class Codec implements AttributeConverter<ScheduleStatus, String> {

        @Override
        public String convertToDatabaseColumn(ScheduleStatus attribute) {
            return attribute == null ? null : attribute.wire;
        }

        @Override
        public ScheduleStatus convertToEntityAttribute(String dbData) {
            return dbData == null ? null : of(dbData);
        }
    }
}
