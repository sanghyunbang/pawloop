package com.heattrip.heat_trip_backend.tour.domain;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

import java.util.List;

/**
 * {@code List<String>}과 JSON 문자열을 자동 변환하는 JPA 컨버터.
 * - 스냅샷 테이블의 해시태그/심플태그 컬럼에 적용하여
 *   DB에는 TEXT(JSON)로 저장, 애플리케이션에서는 {@code List<String>}으로 사용.
 */
@Converter(autoApply = false)
public class StringListJsonConverter implements AttributeConverter<List<String>, String> {
    private static final ObjectMapper M = new ObjectMapper();

    @Override
    public String convertToDatabaseColumn(List<String> attribute) {
        try { return attribute == null ? null : M.writeValueAsString(attribute); }
        catch (Exception e) { throw new IllegalArgumentException("JSON serialize failed", e); }
    }

    @Override
    public List<String> convertToEntityAttribute(String dbData) {
        try { return dbData == null ? null : M.readValue(dbData, new TypeReference<List<String>>() {}); }
        catch (Exception e) { throw new IllegalArgumentException("JSON deserialize failed", e); }
    }
}
