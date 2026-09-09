package com.heattrip.heat_trip_backend.schedule.entity;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

import java.time.LocalDate;

/**
 * 얼마나 자주 되풀이하나 — 이슈 #421, 부모 #416.
 *
 * <h2>규칙 한 줄만 저장한다</h2>
 * <p>행을 미리 만들어 두지 않는다. 1년치 심장사상충 약이 365행이 되고, 규칙을 고치면 그
 * 전부를 손봐야 한다 — 그 손보기를 한 번 빠뜨리면 옛 값이 남은 행이 조용히 생긴다.
 *
 * <p>대신 <b>조회할 때 서버가 펼친다</b>. 앱이 펼치면 규칙 해석이 두 벌이 되고, 그중 하나가
 * 언젠가 다르게 센다(윤년·말일·주 경계가 그 자리다).
 *
 * <h2>요일·날짜를 따로 안 든다</h2>
 * <p>{@code weekly} 는 <b>{@code on_date} 의 요일</b>이고 {@code monthly} 는 그 <b>날짜</b>다.
 * 컬럼을 따로 두면 "매주 화요일인데 시작일은 수요일" 같은 모순을 저장할 수 있게 되고,
 * 그 행을 무엇으로 읽을지 아무도 못 정한다.
 */
public enum ScheduleRepeat {

    /** 되풀이하지 않는다. <b>기본값</b>이다. */
    NONE("none"),

    DAILY("daily"),

    /** {@code on_date} 와 같은 요일마다. */
    WEEKLY("weekly"),

    /**
     * {@code on_date} 와 같은 <b>날짜</b>마다.
     *
     * <p>그 날짜가 없는 달은 <b>건너뛴다</b> — 31일 규칙이 2월에 28일로 당겨지면, 사용자가
     * 안 정한 날에 알림이 온다. 말일로 밀어 주는 달력도 있지만 그건 "31일" 이라고 적은
     * 사람의 뜻이 아니다.
     */
    MONTHLY("monthly");

    private final String wire;

    ScheduleRepeat(String wire) {
        this.wire = wire;
    }

    @JsonValue
    public String wire() {
        return wire;
    }

    @JsonCreator
    public static ScheduleRepeat of(String value) {
        for (ScheduleRepeat repeat : values()) {
            if (repeat.wire.equals(value)) {
                return repeat;
            }
        }
        throw new IllegalArgumentException("반복 주기는 none · daily · weekly · monthly 중 하나여야 합니다.");
    }

    public boolean repeats() {
        return this != NONE;
    }

    /**
     * {@code start} 에서 시작한 규칙이 {@code day} 에 오는가.
     *
     * <p>펼치기의 <b>유일한 판정</b>이다 — 날짜를 하나씩 올리며 이것을 묻는다. 규칙을 세는
     * 코드를 두 곳에 두면 한쪽만 고쳐지는 날이 온다.
     */
    public boolean fallsOn(LocalDate start, LocalDate day) {
        if (day.isBefore(start)) {
            return false;
        }
        return switch (this) {
            case NONE -> day.equals(start);
            case DAILY -> true;
            case WEEKLY -> day.getDayOfWeek() == start.getDayOfWeek();
            // 31일 규칙은 30일까지인 달을 그냥 건너뛴다 — 클래스 javadoc 참조.
            case MONTHLY -> day.getDayOfMonth() == start.getDayOfMonth();
        };
    }

    /**
     * DB 에는 {@link #wire} 값이 들어간다.
     *
     * <p>{@code @Enumerated(STRING)} 을 쓰면 자바 상수 이름({@code WEEKLY})이 저장돼 CHECK
     * 제약과 계약의 소문자와 갈린다 — {@code CareType} 이 같은 함정을 적어 뒀다.
     */
    @Converter(autoApply = false)
    public static class Codec implements AttributeConverter<ScheduleRepeat, String> {
        @Override
        public String convertToDatabaseColumn(ScheduleRepeat attribute) {
            return attribute == null ? null : attribute.wire;
        }

        @Override
        public ScheduleRepeat convertToEntityAttribute(String dbData) {
            return dbData == null ? null : of(dbData);
        }
    }
}
