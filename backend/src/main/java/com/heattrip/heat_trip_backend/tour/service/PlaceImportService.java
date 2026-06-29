package com.heattrip.heat_trip_backend.tour.service;

import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;

import org.springframework.stereotype.Service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.tour.domain.Place;
import com.heattrip.heat_trip_backend.tour.dto.PlaceItemDto;
import com.heattrip.heat_trip_backend.tour.mapper.PlaceMapper;
// import com.heattrip.heat_trip_backend.tour.util.XmlParser;

import lombok.RequiredArgsConstructor;

@Service
@RequiredArgsConstructor
public class PlaceImportService {
    
    private final PlaceService placeService;
    private final TourApiClient tourApiClient;
    private final ObjectMapper objectMapper; // 주입으로 변경

    private static final List<Integer> AREAS = List.of(1,2,3,4,5,6,7,8,31,32,33,34,35,36,37,38,39);

    public void fullImportAllAreas() throws Exception {
        for (int area : AREAS) {
            fetchParseSaveByArea(area);
        }
    }

    private void fetchParseSaveByArea(int areaCode) throws Exception {
        int pageNo = 1;
        int numOfRows = 1000;

        while (true) {
            // 1) 외부 API 호출하기
            String json = tourApiClient.fetchAreaBasedList(areaCode, pageNo, numOfRows);

            // 2) JSON -> DTO 리스트
            JsonNode items = objectMapper.readTree(json)
                        .path("response").path("body").path("items").path("item");

            if (items.isMissingNode() || !items.isArray() || items.size() == 0) break;

            List<PlaceItemDto> dtos = new ArrayList<>(items.size());

            for (JsonNode n : items) {
                dtos.add(objectMapper.treeToValue(n, PlaceItemDto.class));
            }

            // 3) DTO -> Entity -> 배치저장
            List<Place> entities = dtos.stream()
                .map(PlaceMapper::toEntity)
                .toList();

            placeService.saveInBatches(entities, 200);

            if (items.size() < numOfRows) break; // 마지막이면 끝
            pageNo++;
        }
    }
}
