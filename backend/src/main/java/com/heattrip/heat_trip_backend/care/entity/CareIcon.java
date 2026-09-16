package com.heattrip.heat_trip_backend.care.entity;

import java.util.Arrays;
import java.util.stream.Collectors;

/**
 * 항목 칸에 그려지는 그림의 열쇠말 — 이슈 #560.
 *
 * <h2>왜 자유 입력이 아닌가</h2>
 *
 * <p>사장님이 정하신 것이다 — "아이콘은 고르는 목록". 이모지를 자유로 받으면 기기마다 다르게
 * 그려지고, 흰 바탕에 코랄 하나로 맞춰 둔 화면에 색이 섞인다. 고르는 목록이면 앱이 제 그림을
 * 쓰므로 어느 기기에서나 같고, 카드의 칸 하나가 어디서나 같은 폭을 갖는다(#561).
 *
 * <h2>쓰기는 닫고 읽기는 연다</h2>
 *
 * <p>{@code CareItem.icon} 은 <b>{@code String} 이지 이 enum 이 아니다.</b> 쓰는 자리에서만
 * {@link #of} 로 거른다. 컬럼을 enum 으로 변환해 두면 <b>이 목록에 없는 값이 한 행이라도
 * 있는 순간 그 집의 목록 조회 전체가 500</b> 이 된다 — 마이그레이션이 심은 값, 손으로 고친
 * 값, 나중에 이 목록에서 뺀 값이 그 자리다. 그림 하나를 못 그리는 것과 화면이 통째로 안
 * 뜨는 것은 무게가 다르다.
 *
 * <p>앱도 같은 규칙이다 — 모르는 열쇠말이면 기본 그림으로 떨어진다. 그래서 서버가 목록을
 * 넓혀도 옛 앱이 깨지지 않는다.
 *
 * <h2>앞의 일곱은 {@link CareType} 의 표기 그대로다</h2>
 *
 * <p>기본 일곱이 {@code CareItem.defaultsFor} 에서 {@code types[i].wire()} 를 그대로 아이콘에
 * 넣는다. 같은 값을 두 벌로 적으면 한쪽만 고치는 날이 온다.
 */
public enum CareIcon {

    /** 물 — {@link CareType#WATER} 와 같은 표기. */
    WATER("water"),

    /** 밥. */
    MEAL("meal"),

    /** 산책. */
    WALK("walk"),

    /** 투약. */
    MED("med"),

    /** 병원. */
    VET("vet"),

    /** 배변. */
    POOP("poop"),

    /** 마킹. */
    PEE("pee"),

    /** 간식. */
    SNACK("snack"),

    /** 양치 — 이슈 본문이 든 예시다. */
    TOOTH("tooth"),

    /** 목욕. */
    BATH("bath"),

    /** 빗질. */
    BRUSH("brush"),

    /** 발톱. */
    NAIL("nail"),

    /** 심장사상충처럼 달마다 하는 일. */
    HEART("heart"),

    /** 놀이. */
    PLAY("play"),

    /** 몸무게 재기. */
    WEIGHT("weight"),

    /** 위 어느 것도 아닐 때. */
    ETC("etc");

    private final String wire;

    CareIcon(String wire) {
        this.wire = wire;
    }

    /** 밖으로 나가는 값. DB·JSON·앱이 같은 문자열을 쓴다. */
    public String wire() {
        return wire;
    }

    /**
     * 열쇠말을 이 목록에서 찾는다.
     *
     * @throws IllegalArgumentException 목록에 없으면 — 전역 처리기가 400 {@code VALIDATION} 으로 옮긴다
     */
    public static CareIcon of(String value) {
        for (CareIcon icon : values()) {
            if (icon.wire.equals(value)) {
                return icon;
            }
        }
        throw new IllegalArgumentException("아이콘은 " + allWireValues() + " 중 하나여야 합니다.");
    }

    /** 오류 메시지용 — 값 한 벌이 이 파일에만 있게 한다. */
    public static String allWireValues() {
        return Arrays.stream(values()).map(CareIcon::wire).collect(Collectors.joining(" · "));
    }
}
