package com.heattrip.heat_trip_backend.dog.entity;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

import java.util.Arrays;
import java.util.stream.Collectors;

/**
 * 몸집 — 계약의 {@code DogSize}, {@code schema.md §3} 의 {@code ck_dog_size}.
 *
 * <p>이름이 "Dog" 지만 <b>고양이에도 쓴다</b>({@link PetSpecies} 참조). 계약이 이 이름으로
 * 이미 선언돼 있어서 그대로 둔다.
 *
 * <p>표기·변환기의 이유는 {@link PetSpecies} 와 같다.
 */
public enum DogSize {

    SMALL("small"),
    MEDIUM("medium"),
    LARGE("large");

    private final String wire;

    DogSize(String wire) {
        this.wire = wire;
    }

    @JsonValue
    public String wire() {
        return wire;
    }

    /** 계약이 정한 셋 중 하나. 아니면 400 이다. {@code null} 도 400 — 계약이 필수로 선언했다. */
    @JsonCreator
    public static DogSize of(String value) {
        for (DogSize size : values()) {
            if (size.wire.equals(value)) {
                return size;
            }
        }
        throw new IllegalArgumentException("몸집은 " + allowed() + " 중 하나여야 합니다.");
    }

    private static String allowed() {
        return Arrays.stream(values()).map(DogSize::wire).collect(Collectors.joining(" · "));
    }

    @Converter
    public static class Codec implements AttributeConverter<DogSize, String> {

        @Override
        public String convertToDatabaseColumn(DogSize attribute) {
            return attribute == null ? null : attribute.wire;
        }

        @Override
        public DogSize convertToEntityAttribute(String dbData) {
            return dbData == null ? null : of(dbData);
        }
    }
}
