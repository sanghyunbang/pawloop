package com.heattrip.heat_trip_backend.crew.entity;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

/**
 * 품앗이의 <b>시간대</b> — 이슈 #417.
 *
 * <h2>왜 시각이 아니라 시간대인가</h2>
 * <p>부탁은 "12/24 <b>오후</b>, 보리 두 시간만" 이지 "14시 00분" 이 아니다. 시각을 받으면
 * 부탁하는 사람이 없는 정밀도를 지어내야 하고, 맡는 사람은 그 시각에 묶인다. 실제로 정하는
 * 것은 둘이 대화방에서 정한다 — 그래서 이 값은 <b>대략</b>을 말하는 데까지만 쓴다.
 *
 * <p>같은 이유로 크루 일정에도 {@code at_time} 을 안 채운다. 시간대는 메모로 간다.
 */
public enum CrewFavorSlot {

    MORNING("morning", "오전"),
    AFTERNOON("afternoon", "오후"),
    EVENING("evening", "저녁");

    private final String wire;

    /** 화면과 일정 메모에 그대로 쓰는 말. */
    private final String label;

    CrewFavorSlot(String wire, String label) {
        this.wire = wire;
        this.label = label;
    }

    @JsonValue
    public String wire() {
        return wire;
    }

    public String label() {
        return label;
    }

    @JsonCreator
    public static CrewFavorSlot of(String value) {
        for (CrewFavorSlot slot : values()) {
            if (slot.wire.equals(value)) {
                return slot;
            }
        }
        throw new IllegalArgumentException("시간대는 오전·오후·저녁 중 하나여야 합니다.");
    }

    /**
     * DB 에는 {@link #wire} 값이 들어간다 — {@code CrewVisibility.Codec} 과 같은 규약이다.
     *
     * <p>{@code @Enumerated(STRING)} 을 쓰면 자바 상수 이름({@code MORNING})이 저장돼
     * CHECK 제약·계약의 소문자와 갈린다.
     */
    @Converter(autoApply = false)
    public static class Codec implements AttributeConverter<CrewFavorSlot, String> {
        @Override
        public String convertToDatabaseColumn(CrewFavorSlot attribute) {
            return attribute == null ? null : attribute.wire;
        }

        @Override
        public CrewFavorSlot convertToEntityAttribute(String dbData) {
            return dbData == null ? null : of(dbData);
        }
    }
}
