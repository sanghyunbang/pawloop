package com.heattrip.heat_trip_backend.dog.entity;

import java.util.Arrays;
import java.util.stream.Collectors;

/**
 * 사진이 없을 때 그 아이의 얼굴이 되는 <b>캐릭터</b> — 이슈 #585.
 *
 * <h2>왜 필요했나</h2>
 *
 * <p>얼굴이 <b>종류당 하나</b>였다 — 강아지면 모두 같은 그림. 사진을 안 올린 집은 아이가
 * 둘이어도 홈의 고르기 칩이 같은 얼굴 둘로 서고, 이름을 읽기 전에는 못 가른다. 사진을
 * 강요할 수는 없다(사장님, 2026-09-16).
 *
 * <h2>왜 {@code avatar} 컬럼을 같이 안 쓰나</h2>
 *
 * <p>거기는 S3 키 자리다. 한 칸에 두 가지 뜻을 담으면 읽는 곳마다 "이 값이 사진인가
 * 캐릭터인가" 를 물어야 하고, 그 판정이 코드 여러 곳에 흩어진다.
 *
 * <h2>쓰기는 닫고 읽기는 연다</h2>
 *
 * <p>{@code Dog.characterKey} 는 <b>{@code String} 이지 이 enum 이 아니다.</b> 쓰는 자리에서만
 * {@link #of} 로 거른다 — 컬럼을 enum 으로 변환해 두면 이 목록에서 뺀 값이 한 행이라도 있는
 * 순간 그 사람의 아이 목록 전체가 500 이 된다. {@code CareIcon} 이 같은 이유로 같은 판단을
 * 했다(#560).
 *
 * <p>앱도 같은 규칙이다 — 모르는 열쇠말이면 종류 기본 그림으로 떨어진다. 그래서 서버가
 * 목록을 넓혀도 옛 앱이 안 깨진다.
 */
public enum PetCharacter {

    /** 🐶 강아지 얼굴 — 종류 기본값과 같은 그림이다. */
    DOG_FACE("dog_face"),

    /** 🐕 강아지. */
    DOG("dog"),

    /** 🐩 푸들. */
    POODLE("poodle"),

    /** 🐱 고양이 얼굴 — 종류 기본값과 같은 그림이다. */
    CAT_FACE("cat_face"),

    /** 🐈 고양이. */
    CAT("cat"),

    /** 🐈‍⬛ 검은 고양이. */
    BLACK_CAT("black_cat"),

    /** 🐰 토끼. */
    RABBIT("rabbit"),

    /** 🐹 햄스터. */
    HAMSTER("hamster"),

    /** 🐦 새. */
    BIRD("bird"),

    /** 🦜 앵무새. */
    PARROT("parrot"),

    /** 🐢 거북이. */
    TURTLE("turtle"),

    /** 🦔 고슴도치. */
    HEDGEHOG("hedgehog"),

    /** 🐾 발바닥 — 종류를 안 밝히고 싶을 때. */
    PAW("paw");

    private final String wire;

    PetCharacter(String wire) {
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
    public static PetCharacter of(String value) {
        for (PetCharacter character : values()) {
            if (character.wire.equals(value)) {
                return character;
            }
        }
        throw new IllegalArgumentException("캐릭터는 " + allWireValues() + " 중 하나여야 합니다.");
    }

    /** 오류 메시지용 — 값 한 벌이 이 파일에만 있게 한다. */
    public static String allWireValues() {
        return Arrays.stream(values()).map(PetCharacter::wire).collect(Collectors.joining(" · "));
    }
}
