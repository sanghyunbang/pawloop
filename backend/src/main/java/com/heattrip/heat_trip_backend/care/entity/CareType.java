package com.heattrip.heat_trip_backend.care.entity;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

import java.util.Arrays;
import java.util.stream.Collectors;

/**
 * 케어 한 건의 종류 — 이슈 #76. 물·밥·산책·투약·병원 다섯이다.
 *
 * <h2>표기가 하나다 — {@code water} 다</h2>
 * <p>DB({@code care_log.type})와 JSON({@code CareLog.type}) 이 <b>같은 문자열</b>을 쓴다.
 * 계약({@code openapi.yaml} 의 {@code CareType})이 소문자로 선언했고 앱의 Dart {@code enum
 * CareType} 도 {@code water} 다. 여기서만 {@code WATER} 로 저장하면 같은 값에 표기가 둘이
 * 되고, 그 순간 "어느 쪽이 정본인가" 를 매번 물어야 한다. #75 가 {@code GroupRole} 의
 * 대소문자 두 벌을 걷어낸 것과 같은 이유다.
 *
 * <p>자바 상수 이름은 관례대로 대문자로 두고, <b>밖으로 나가는 값은 {@link #wire} 하나</b>로
 * 만든다. 저장은 {@link Codec}, 직렬화는 {@link JsonValue}·{@link JsonCreator} 가 같은
 * 필드를 읽는다 — 문자열 리터럴이 이 파일 안에 한 벌만 있다.
 *
 * <h2>다섯뿐인 것이 지금의 계약이다</h2>
 * <p>앱의 Dart {@code CareType} 에는 {@code snack}·{@code etc} 가 더 있지만 그건 화면 안에서만
 * 사는 값이고 서버 계약에는 없다. 건강·식사·병원 상세는 M4({@code care_log} 확장)이며,
 * 그때 여기에 상수를 더하고 CHECK 제약과 계약의 {@code enum} 을 함께 넓힌다.
 */
public enum CareType {

    /** 물 갈아주기. */
    WATER("water"),

    /** 밥. 이중 급여를 막는 것이 이 이슈의 출발점이다. */
    MEAL("meal"),

    /** 산책. 서로 상대가 다녀왔겠거니 하는 누락을 막는다. */
    WALK("walk"),

    /** 투약. */
    MED("med"),

    /** 병원. */
    VET("vet");

    private final String wire;

    CareType(String wire) {
        this.wire = wire;
    }

    /** DB 에도 JSON 에도 이 값이 그대로 들어간다. */
    @JsonValue
    public String wire() {
        return wire;
    }

    /**
     * 계약이 정한 다섯 중 하나로 해석한다. 아닌 값은 <b>400</b> 이다.
     *
     * <p>{@link IllegalArgumentException} 을 던지면 {@code GlobalExceptionHandler} 가
     * 400 으로 옮긴다. 메시지에 <b>입력값을 되싣지 않는다</b> — 이 문구는 그대로 응답 본문이
     * 된다(#6). 대신 허용 목록을 적어 준다: 그건 계약에 이미 공개된 값이다.
     */
    @JsonCreator
    public static CareType of(String value) {
        for (CareType type : values()) {
            if (type.wire.equals(value)) {
                return type;
            }
        }
        throw new IllegalArgumentException("케어 종류는 " + allowed() + " 중 하나여야 합니다.");
    }

    private static String allowed() {
        return Arrays.stream(values()).map(CareType::wire).collect(Collectors.joining(" · "));
    }

    /**
     * {@code care_log.type} 컬럼과의 변환기.
     *
     * <p>{@code @Enumerated(STRING)} 을 쓰지 않는 이유가 이 클래스의 존재 이유다 — 그 애너테이션은
     * <b>자바 상수 이름</b>을 저장하므로 컬럼에 {@code WATER} 가 들어간다. 그러면 CHECK 제약과
     * 계약과 앱이 소문자를 말하는데 DB 만 대문자인 상태가 된다.
     *
     * <p>{@code autoApply} 를 켜지 않는다. 켜면 앞으로 이 저장소에 생길 모든 {@code CareType}
     * 필드가 조용히 이 변환을 받는다 — 필드마다 {@code @Convert} 를 적는 편이 읽는 사람에게
     * 보인다.
     */
    @Converter
    public static class Codec implements AttributeConverter<CareType, String> {

        @Override
        public String convertToDatabaseColumn(CareType attribute) {
            return attribute == null ? null : attribute.wire;
        }

        @Override
        public CareType convertToEntityAttribute(String dbData) {
            return dbData == null ? null : of(dbData);
        }
    }
}
