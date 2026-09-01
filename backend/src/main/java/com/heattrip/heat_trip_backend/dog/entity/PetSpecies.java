package com.heattrip.heat_trip_backend.dog.entity;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

import java.util.Arrays;
import java.util.stream.Collectors;

/**
 * 반려동물의 종 — 이슈 #145, 계약의 {@code PetSpecies}.
 *
 * <h2>표 이름이 {@code dog} 인데 왜 종이 있나</h2>
 * <p>없으면 <b>고양이를 키우는 사람은 반려동물을 서버에 올릴 수 없고, 그 사람의 산책은
 * 붙을 곳이 없다.</b> 앱에는 {@code PetSpecies {dog, cat, other}} 가 이미 있고 더미 시드에
 * 고양이가 들어 있다({@code v2/domain/pet.dart}). #24 가 이것을 high 로 올려 뒀다.
 *
 * <p>표와 경로 이름을 {@code pet} 으로 옮기지 않은 이유는 {@code walk.dog_id} ·
 * {@code care_log.dog_id} · {@code /api/dogs} · {@code WalkInput.dogId} 가 이미 여러 곳에
 * 박혀 있어서다. 이름을 바꾸면 그 전부를 같은 변경에서 함께 옮겨야 한다.
 *
 * <h2>표기가 하나다</h2>
 * <p>저장({@link Codec})과 JSON 이 <b>같은 소문자 문자열</b>을 쓴다.
 * {@code care.entity.CareType} 과 같은 모양이고 이유도 같다 —
 * {@code @Enumerated(STRING)} 은 <b>자바 상수 이름</b>({@code DOG})을 저장하므로,
 * 그것을 쓰면 CHECK 제약과 계약과 앱이 소문자를 말하는데 DB 만 대문자가 된다.
 */
public enum PetSpecies {

    /** 개. 값을 안 보내면 이것이다 — 이 필드가 없던 때 만들어진 앱과 맞춘다. */
    DOG("dog"),

    /** 고양이. 이 상수가 이 enum 의 존재 이유다. */
    CAT("cat"),

    /** 그 밖. 앱의 {@code PetSpecies.other} 와 같다. */
    OTHER("other");

    /** 값을 주지 않았을 때. 계약의 {@code PetSpecies.default} 와 같아야 한다. */
    public static final PetSpecies DEFAULT = DOG;

    private final String wire;

    PetSpecies(String wire) {
        this.wire = wire;
    }

    /** DB 에도 JSON 에도 이 값이 그대로 들어간다. */
    @JsonValue
    public String wire() {
        return wire;
    }

    /**
     * 계약이 정한 셋 중 하나로 해석한다. {@code null} 이면 {@link #DEFAULT} 다.
     *
     * <p>아닌 값은 <b>400</b> 이다 — {@link IllegalArgumentException} 을
     * {@code GlobalExceptionHandler} 가 옮긴다. 메시지에 <b>입력값을 되싣지 않는다</b>(#6):
     * 이 문구가 그대로 응답 본문이 된다.
     */
    @JsonCreator
    public static PetSpecies of(String value) {
        if (value == null) {
            return DEFAULT;
        }
        for (PetSpecies species : values()) {
            if (species.wire.equals(value)) {
                return species;
            }
        }
        throw new IllegalArgumentException("반려동물 종은 " + allowed() + " 중 하나여야 합니다.");
    }

    private static String allowed() {
        return Arrays.stream(values()).map(PetSpecies::wire).collect(Collectors.joining(" · "));
    }

    /**
     * {@code dog.species} 컬럼과의 변환기.
     *
     * <p>{@code autoApply} 를 켜지 않는 것은 {@code CareType.Codec} 과 같은 판단이다 — 켜면
     * 앞으로 생길 모든 {@code PetSpecies} 필드가 조용히 이 변환을 받는다. 필드마다
     * {@code @Convert} 를 적는 편이 읽는 사람에게 보인다.
     */
    @Converter
    public static class Codec implements AttributeConverter<PetSpecies, String> {

        @Override
        public String convertToDatabaseColumn(PetSpecies attribute) {
            return attribute == null ? null : attribute.wire;
        }

        @Override
        public PetSpecies convertToEntityAttribute(String dbData) {
            return dbData == null ? null : of(dbData);
        }
    }
}
