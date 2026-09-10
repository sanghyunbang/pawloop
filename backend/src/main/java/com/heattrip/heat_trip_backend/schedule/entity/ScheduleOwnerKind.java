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
 * <h2>{@code room} 이 열렸다 — 그런데 이 모듈은 크루를 모른다</h2>
 * <p>#417 품앗이가 이 값을 쓴다. 판정은 "그 크루 방의 살아 있는 멤버인가" 하나이고,
 * 그것은 {@code chat_room} 만 알면 답할 수 있다 — 그래서 {@code schedule} 은
 * <b>{@code crew} 를 부르지 않는다.</b>
 *
 * <p>부르면 <b>고리가 생긴다</b>: {@code crew} 는 품앗이를 맡을 때 일정 한 줄을 남기려고
 * {@code schedule} 을 부른다. 두 모듈이 서로를 부르면 {@code ModuleCycleTest} 가 잡는다.
 * 그래서 출처 이름({@link #CREW_ORIGIN_KIND})만 여기서 들고, 그 문자열이 크루 쪽과 같은지는
 * {@code CrewOriginKindMatchesScheduleTest} 가 잰다 — 같이 안 움직이면 크루 일정이
 * 조용히 404 가 된다.
 */
public enum ScheduleOwnerKind {

    /** 아이 하나의 일정. {@code owner_ref} 는 {@code dog.id} 다. */
    DOG("dog"),

    /** 가족 그룹의 일정. {@code owner_ref} 는 {@code family_group.id} 다. */
    GROUP("group"),

    /**
     * 크루의 일정 (#417). {@code owner_ref} 는 <b>{@code crew.id}</b> 다 — 방 id 가 아니다.
     *
     * <p>{@code GROUP} 이 {@code family_group.id} 를 드는 것과 같은 자리다. 방 id 를 들면
     * 화면이 크루를 찾으려고 방을 한 번 더 되짚어야 한다.
     */
    ROOM("room");

    /**
     * 크루 방이 {@code chat_room.origin_kind} 에 적는 이름. <b>{@code CrewService.ORIGIN_KIND}
     * 와 같아야 한다</b> — 클래스 javadoc 참조. 여기 적어 두는 이유는 그 상수를 가져오면
     * 모듈 고리가 생기기 때문이다.
     */
    public static final String CREW_ORIGIN_KIND = "CREW";

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
