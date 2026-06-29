// src/main/java/com/heattrip/heat_trip_backend/tour/service/TraitSnapshotService.java
package com.heattrip.heat_trip_backend.tour.service;

import com.heattrip.heat_trip_backend.tour.domain.*;
import com.heattrip.heat_trip_backend.tour.repository.*;

import com.heattrip.heat_trip_backend.curation.entity.PlaceTrait; // ★ curation 엔티티 사용
import com.heattrip.heat_trip_backend.curation.repository.PlaceTraitRepository; // ★ curation 리포 사용

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.*;
import java.util.function.Function;
import java.util.stream.Collectors;

@Slf4j
@Service
@RequiredArgsConstructor
public class TraitSnapshotService {

  private final PlaceRepository placeRepo;

  // ▼ 기존 PlaceTraitRepo 대신 curation의 Repository를 주입
  private final PlaceTraitRepository traitRepo;

  private final PlaceHashtagRepo hashtagRepo;
  private final PlaceSimpleTagRepo simpleTagRepo;
  private final PlaceDescriptionRepo descRepo;
  private final PlaceTraitSnapshotRepo snapshotRepo;

  /**
   * places에 실제로 등장하는 CAT3만 대상으로 스냅샷을 재생성.
   * 조건:
   *  - cat3가 null인 place → 제외
   *  - PlaceTrait.name(cat3name)이 null/blank → 제외
   */
  @Transactional
  public int rebuildAllSnapshots(int pageSize) {
    long t0 = System.currentTimeMillis();
    log.info("[SNAPSHOT] rebuild start (by CAT3, pageSize={})", pageSize);

    // 1) 실제로 쓰이는 CAT3 집합 수집 (cat3=null 은 제외)
    Set<String> cat3s = new HashSet<>();
    int page = 0;
    while (true) {
      Page<Place> p = placeRepo.findAll(PageRequest.of(page, pageSize));
      if (!p.hasContent()) break;
      p.getContent().stream()
          .map(Place::getCat3)
          .filter(Objects::nonNull)
          .forEach(cat3s::add);
      if (p.isLast()) break;
      page++;
    }
    log.info("[SNAPSHOT] distinct cat3 count (non-null) = {}", cat3s.size());

    // 2) 기존 스냅샷 비움
    snapshotRepo.deleteAllInBatch();

    if (cat3s.isEmpty()) {
      log.info("[SNAPSHOT] nothing to build; done in {} ms", System.currentTimeMillis() - t0);
      return 0;
    }

    // 3) cat3 → 소스 데이터 맵 구성 (curation 엔티티 PlaceTrait 활용)
    Map<String, PlaceTrait> traitMap = traitRepo.findAllById(cat3s).stream()
        .collect(Collectors.toMap(PlaceTrait::getPlaceId, Function.identity()));

    Map<String, List<String>> hashMap = hashtagRepo.findByPlaceIdIn(cat3s).stream()
        .collect(Collectors.groupingBy(
            PlaceHashtag::getPlaceId,
            Collectors.mapping(PlaceHashtag::getHashtag, Collectors.toList())
        ));

    Map<String, List<String>> simpleMap = simpleTagRepo.findByPlaceIdIn(cat3s).stream()
        .collect(Collectors.groupingBy(
            PlaceSimpleTag::getPlaceId,
            Collectors.mapping(PlaceSimpleTag::getTag, Collectors.toList())
        ));

    Map<String, PlaceDescription> descMap = descRepo.findByPlaceIdIn(cat3s).stream()
        .collect(Collectors.toMap(PlaceDescription::getPlaceId, Function.identity()));

    // 4) 스냅샷 생성 (cat3name이 null/blank면 skip)
    LocalDateTime now = LocalDateTime.now();
    List<PlaceTraitSnapshot> batch = new ArrayList<>(cat3s.size());
    long skippedNoName = 0;

    for (String cat3 : cat3s) {
      PlaceTrait t = traitMap.get(cat3);
      String cat3Name = (t == null ? null : t.getName());

      if (cat3Name == null || cat3Name.isBlank()) {
        skippedNoName++;
        continue;
      }

      PlaceDescription d = descMap.get(cat3);

      batch.add(PlaceTraitSnapshot.builder()
          .cat3(cat3)
          .cat3Name(cat3Name)
          .pScore(n(t.getPScore()))
          .aScore(n(t.getAScore()))   // Lombok이 getAScore() 생성
          .dScore(n(t.getDScore()))
          .sociality(n(t.getSociality()))
          .noise(n(t.getNoise()))
          .crowdness(n(t.getCrowdness()))
          .hashtags(hashMap.getOrDefault(cat3, List.of()))
          .simpleTags(simpleMap.getOrDefault(cat3, List.of()))
          .shortDesc1(d == null ? null : d.getShortDesc1())
          .shortDesc2(d == null ? null : d.getShortDesc2())
          .snapshotAt(now)
          .build());
    }

    snapshotRepo.saveAll(batch);
    placeRepo.refreshAllSearchTexts();

    log.info("[SNAPSHOT] rebuild done: inserted={}, skipped(cat3name null/blank)={}, elapsed={} ms",
        batch.size(), skippedNoName, System.currentTimeMillis() - t0);

    return batch.size();
  }

  private Double n(Number x) { return x == null ? null : x.doubleValue(); }
}
