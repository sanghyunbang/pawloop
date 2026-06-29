package com.heattrip.heat_trip_backend.tour.service;

import java.util.List;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.heattrip.heat_trip_backend.tour.domain.Place;
import com.heattrip.heat_trip_backend.tour.repository.PlaceRepository;

import lombok.RequiredArgsConstructor;

@Service
@RequiredArgsConstructor

/**
 * Upsert(중복 contentid 갱신)
해당 방식은 PK가 같으면 JPA가 merge 성격으로 업데이트합니다. 
대량 upsert가 더 빠르길 원하면 별도 Native Query 하나를 만들어 
INSERT ... ON DUPLICATE KEY UPDATE를 쓰는 방법도 있습니다(최고속). 
 */
public class PlaceService {
    private final PlaceRepository repo;

    @Transactional
    public void saveInBatches(List<Place> places, int batchSize) {
        for (int i = 0 ; i < places.size(); i += batchSize) {
            int end = Math.min(i+batchSize, places.size());

            List<Place> chunk = places.subList(i, end);

            repo.saveAll(chunk); // Hibernate batch insert/update
            repo.flush(); // Optional: JPA flush (if extends JpaRepository+JpaSpecificationExecutor)
        }
    }
   
}

