package com.heattrip.heat_trip_backend.curation.entity;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

import java.util.Map;

/**
 * {@code Map<String, Double>}(감정→가중치)과 JSON 문자열을 자동 변환하는 JPA 컨버터.
 * - places 테이블의 seed_emotion / ugc_emotion 컬럼에 적용한다.
 * - DB에는 JSON 문자열로 저장, 애플리케이션에서는 {@code Map<String, Double>}로 사용.
 *   예) {"평온":0.4,"설렘":0.3}
 *
 * <p>{@link com.heattrip.heat_trip_backend.tour.domain.StringListJsonConverter}의 패턴을 따른다.
 */
@Converter(autoApply = false)
public class EmotionWeightMapJsonConverter implements AttributeConverter<Map<String, Double>, String> {

    private static final ObjectMapper M = new ObjectMapper();

    @Override
    public String convertToDatabaseColumn(Map<String, Double> attribute) {
        try {
            return attribute == null ? null : M.writeValueAsString(attribute);
        } catch (Exception e) {
            throw new IllegalArgumentException("emotion JSON serialize failed", e);
        }
    }

    @Override
    public Map<String, Double> convertToEntityAttribute(String dbData) {
        try {
            return dbData == null ? null : M.readValue(dbData, new TypeReference<Map<String, Double>>() {});
        } catch (Exception e) {
            throw new IllegalArgumentException("emotion JSON deserialize failed", e);
        }
    }
}
