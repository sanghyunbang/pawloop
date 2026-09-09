package com.heattrip.heat_trip_backend.schedule.entity;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

import java.util.Arrays;
import java.util.stream.Collectors;

/**
 * 일정의 주인이 어느 도메인인가 — 이슈 #418.
 *
 * <h2>{@code chat_room} 과 같은 방식이다</h2>
 * <p>일정의 주인이 셋이다: <b>아이</b>("보리 심장사상충 약") · <b>가족 그룹</b>("토요일 병원,
 * 아빠 담당") · <b>크루</b>("토요일 합동 산책", #417). 셋을 표 셋으로 나누면 "합쳐 보기" 가
 * 매번 UNION 이 되고, 화면 하나가 그중 하나를 빠뜨리는 날이 온다.
 *
 * <p>{@code chat_room} 이 이미 이 문제를 {@code origin_kind} + {@code origin_ref} 로 풀었다
 * (ADR-0011). 같은 방식을 쓴다 — 어느 도메인인지와 그 도메인의 id 를 <b>불투명하게</b> 든다.
 *
 * <h2>{@code room} 은 자리만 열어 뒀다</h2>
 * <p>크루(#417)가 서기 전까지 이 값으로는 아무것도 만들 수 없다 — 서비스가 <b>거절한다</b>.
 * 값만 미리 두는 이유는 나중에 CHECK 제약을 넓히는 마이그레이션을 한 번 더 돌리지 않기
 * 위해서다. {@code chk_place_catalog_source} 를 두 번 넓히며 배운 것이다(#346).
 */
public enum ScheduleOwnerKind {

    /** 아이 하나의 일정. {@code owner_ref} 는 {@code dog.id} 다. */
    DOG("dog"),

    /** 가족 그룹의 일정. {@code owner_ref} 는 {@code family_group.id} 다. */
    GROUP("group"),

    /** 크루의 일정 (#417). <b>아직 못 쓴다</b> — 서비스가 거절한다. */
    ROOM("room");

    private final String wire;

    ScheduleOwnerKind(String wire) {
        this.wire = wire;
    }

    @JsonValue
    public String wire() {
        return wire;
    }

    @JsonCreator
    public static ScheduleOwnerKind of(String value) {
        for (ScheduleOwnerKind kind : values()) {
            if (kind.wire.equals(value)) {
                return kind;
            }
        }
        throw new IllegalArgumentException("일정 주인은 " + allowed() + " 중 하나여야 합니다.");
    }

    private static String allowed() {
        return Arrays.stream(values()).map(ScheduleOwnerKind::wire).collect(Collectors.joining(" · "));
    }

    @Converter
    public static class Codec implements AttributeConverter<ScheduleOwnerKind, String> {

        @Override
        public String convertToDatabaseColumn(ScheduleOwnerKind attribute) {
            return attribute == null ? null : attribute.wire;
        }

        @Override
        public ScheduleOwnerKind convertToEntityAttribute(String dbData) {
            return dbData == null ? null : of(dbData);
        }
    }
}
