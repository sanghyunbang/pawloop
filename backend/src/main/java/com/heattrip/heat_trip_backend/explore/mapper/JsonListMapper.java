package com.heattrip.heat_trip_backend.explore.mapper;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.mapstruct.Named;
import org.springframework.stereotype.Component;

import java.util.List;

// 스프링 컴포넌트로 등록되고, MapStruct의 uses=JsonListMapper.class로 연결됩니다.
// 네이티브 쿼리에서 s.hashtags AS hashtagsJson, s.simple_tags AS simpleTagsJson처럼 문자열이 들어오면, 이 매퍼가 List<String>으로 바꿔 DTO에 채워줍니다.

@Component
public class JsonListMapper {
    private final ObjectMapper om = new ObjectMapper();

    @Named("jsonToList")
    public List<String> jsonToList(String json) {
        if (json == null || json.isBlank()) return List.of();
        try {
            return om.readValue(json, new TypeReference<List<String>>(){});
        } catch (Exception e) {
            return List.of(); // 파싱 실패 시 빈 리스트
        }
    }
}
