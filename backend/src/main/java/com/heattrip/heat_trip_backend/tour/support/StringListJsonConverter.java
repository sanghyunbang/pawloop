// src/main/java/com/heattrip/heat_trip_backend/tour/support/StringListJsonConverter.java
package com.heattrip.heat_trip_backend.tour.support;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;
import java.util.Collections;
import java.util.List;

@Converter
public class StringListJsonConverter implements AttributeConverter<List<String>, String> {
  private static final ObjectMapper om = new ObjectMapper();
  @Override public String convertToDatabaseColumn(List<String> attribute) {
    try { return om.writeValueAsString(attribute == null ? Collections.emptyList() : attribute); }
    catch (Exception e) { return "[]"; }
  }
  @Override public List<String> convertToEntityAttribute(String dbData) {
    try { return dbData == null || dbData.isBlank() ? List.of()
        : om.readValue(dbData, new TypeReference<List<String>>(){}); }
    catch (Exception e) { return List.of(); }
  }
}
