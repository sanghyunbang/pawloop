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

    /**
     * 이 종류를 완료했을 때 케어 기록으로 남길 값 — 이슈 #420. 케어가 아니면 {@code null}.
     *
     * <h2>왜 여기인가</h2>
     * <p>"어떤 일정이 케어인가" 는 <b>일정의 지식</b>이다. {@code care} 가 알면 그 모듈이
     * 일정의 어휘를 들게 되고, 일정 종류를 하나 늘릴 때마다 남의 모듈을 고쳐야 한다.
     *
     * <p>돌려주는 것이 {@code CareType} 이 아니라 <b>문자열</b>인 것도 같은 이유다 — 그
     * 타입은 {@code care.entity} 라 하위 패키지이고, 여기서 들면 모듈 경계를 넘는다. 두
     * 도메인이 이미 공유하는 것은 {@code wire} 값이다({@code CareLogging} javadoc).
     *
     * <h2>넷은 케어가 아니다</h2>
     * <p>{@code groom}(미용) · {@code bath}(목욕) · {@code food}(사료 주문) · {@code etc} 는
     * 케어 종류가 <b>아니다</b> — {@code care_log} 의 CHECK 가 받는 일곱에 없다. 억지로
     * {@code etc} 같은 값을 만들어 넣으면 "오늘의 케어" 가 물·밥·산책이 아닌 것으로 채워진다.
     */
    public String careWire() {
        return switch (this) {
            case WALK, VET, MED -> wire;
            case GROOM, BATH, FOOD, ETC -> null;
        };
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
