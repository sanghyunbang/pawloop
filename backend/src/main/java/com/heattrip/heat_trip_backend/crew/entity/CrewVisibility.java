package com.heattrip.heat_trip_backend.crew.entity;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

/**
 * 크루를 누가 찾을 수 있나 — 이슈 #417.
 *
 * <h2>기본이 {@link #INVITE} 다</h2>
 * <p>처음부터 아무나 들어오면 관리가 안 된다. 동네 모임은 <b>아는 사람 몇으로 시작해서</b>
 * 열리는 것이지, 열어 놓고 사람을 거르는 것이 아니다.
 *
 * <p>공개로 바꾸는 것은 방장이 언제든 할 수 있다. 반대(공개 → 초대)도 되지만 <b>이미 든
 * 사람은 안 나간다</b> — 공개 범위는 "누가 새로 들어올 수 있나" 이지 "누가 있나" 가 아니다.
 */
public enum CrewVisibility {

    /** 초대 코드로만. <b>기본값</b>이다. */
    INVITE("invite"),

    /** 우리 동네 목록에 뜨고, 누구나 바로 들어온다. */
    PUBLIC("public");

    private final String wire;

    CrewVisibility(String wire) {
        this.wire = wire;
    }

    @JsonValue
    public String wire() {
        return wire;
    }

    @JsonCreator
    public static CrewVisibility of(String value) {
        for (CrewVisibility visibility : values()) {
            if (visibility.wire.equals(value)) {
                return visibility;
            }
        }
        throw new IllegalArgumentException("공개 범위는 invite · public 중 하나여야 합니다.");
    }

    public boolean isPublic() {
        return this == PUBLIC;
    }

    /**
     * DB 에는 {@link #wire} 값이 들어간다 — {@code CareType} 과 같은 규약이다.
     *
     * <p>{@code @Enumerated(STRING)} 을 쓰면 자바 상수 이름({@code PUBLIC})이 저장돼 CHECK
     * 제약·계약의 소문자와 갈린다.
     */
    @Converter(autoApply = false)
    public static class Codec implements AttributeConverter<CrewVisibility, String> {
        @Override
        public String convertToDatabaseColumn(CrewVisibility attribute) {
            return attribute == null ? null : attribute.wire;
        }

        @Override
        public CrewVisibility convertToEntityAttribute(String dbData) {
            return dbData == null ? null : of(dbData);
        }
    }
}
