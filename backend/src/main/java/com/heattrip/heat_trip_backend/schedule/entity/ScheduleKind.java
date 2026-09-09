package com.heattrip.heat_trip_backend.schedule.entity;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

import java.util.Arrays;
import java.util.stream.Collectors;

/**
 * 일정 한 건의 종류 — 이슈 #418.
 *
 * <h2>표기가 하나다</h2>
 * <p>DB({@code schedule.kind})와 JSON 이 <b>같은 소문자</b>를 쓴다. {@code CareType} 이 정한
 * 규약을 그대로 따른다 — 자바 상수는 관례대로 대문자이고, 밖으로 나가는 값은 {@link #wire}
 * 하나다. {@code @Enumerated(STRING)} 을 쓰면 컬럼에 {@code WALK} 가 들어가 CHECK 제약·계약·앱이
 * 소문자를 말하는데 DB 만 대문자인 상태가 된다.
 *
 * <h2>케어 종류와 왜 다른가</h2>
 * <p>{@code CareType} 은 <b>한 일</b>이고 이것은 <b>할 일</b>이다. 겹치는 셋
 * ({@code walk}·{@code vet}·{@code med})은 완료할 때 케어 로그로 이어진다(#420). 나머지 넷
 * ({@code groom}·{@code bath}·{@code food}·{@code etc})은 케어 종류가 아니라 이어지지 않는다 —
 * 그것을 억지로 케어에 밀어 넣으면 "오늘의 케어" 칸이 무엇을 세는 표인지 흐려진다.
 *
 * <p>{@code food} 는 <b>사료 주문</b>이지 급여가 아니다. 급여는 {@code CareType.MEAL} 이고 그건
 * 지나간 일이다.
 */
public enum ScheduleKind {

    /** 산책 약속. 완료하면 케어 로그 {@code walk} 로 이어진다(#420). */
    WALK("walk"),

    /** 병원. 완료하면 케어 로그 {@code vet} 로 이어진다. */
    VET("vet"),

    /** 투약. 완료하면 케어 로그 {@code med} 로 이어진다. */
    MED("med"),

    /** 미용. */
    GROOM("groom"),

    /** 목욕. 시각 없는 일정의 전형이다 — "이번 주말 목욕". */
    BATH("bath"),

    /** 사료·용품 주문. <b>급여가 아니다</b>. */
    FOOD("food"),

    /** 나머지. 사용자가 적는 것이 제목이라 종류를 강요하지 않는다. */
    ETC("etc");

    private final String wire;

    ScheduleKind(String wire) {
        this.wire = wire;
    }

    @JsonValue
    public String wire() {
        return wire;
    }

    /**
     * 계약이 정한 일곱 중 하나로 해석한다. 아닌 값은 <b>400</b> 이다.
     *
     * <p>메시지에 <b>입력값을 되싣지 않는다</b> — 이 문구는 그대로 응답 본문이 된다(#6).
     */
    @JsonCreator
    public static ScheduleKind of(String value) {
        for (ScheduleKind kind : values()) {
            if (kind.wire.equals(value)) {
                return kind;
            }
        }
        throw new IllegalArgumentException("일정 종류는 " + allowed() + " 중 하나여야 합니다.");
    }

    private static String allowed() {
        return Arrays.stream(values()).map(ScheduleKind::wire).collect(Collectors.joining(" · "));
    }

    /** {@code schedule.kind} 컬럼과의 변환기. {@code autoApply} 를 켜지 않는 이유는 {@code CareType.Codec}. */
    @Converter
    public static class Codec implements AttributeConverter<ScheduleKind, String> {

        @Override
        public String convertToDatabaseColumn(ScheduleKind attribute) {
            return attribute == null ? null : attribute.wire;
        }

        @Override
        public ScheduleKind convertToEntityAttribute(String dbData) {
            return dbData == null ? null : of(dbData);
        }
    }
}
