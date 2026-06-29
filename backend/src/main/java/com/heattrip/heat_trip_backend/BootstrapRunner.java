// src/main/java/com/heattrip/heat_trip_backend/BootstrapRunner.java
package com.heattrip.heat_trip_backend;

import com.heattrip.heat_trip_backend.tour.repository.PlaceTraitSnapshotRepo;
import com.heattrip.heat_trip_backend.tour.service.TraitSnapshotService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Slf4j
@Configuration
@RequiredArgsConstructor
public class BootstrapRunner {

  private final TraitSnapshotService snapshotService;
  private final PlaceTraitSnapshotRepo snapshotRepo;

  @Value("${app.snapshot.rebuild-on-startup:false}")
  private boolean rebuildOnStartup;

  @Value("${app.snapshot.rebuild-page-size:5000}")
  private int pageSize;

  @Bean
  ApplicationRunner snapshotBootstrap() {
    return args -> {
      boolean empty = snapshotRepo.count() == 0;
      if (rebuildOnStartup || empty) {
        log.info("[BOOT] snapshot rebuild trigger: rebuildOnStartup={}, empty={}", rebuildOnStartup, empty);
        snapshotService.rebuildAllSnapshots(pageSize);
      } else {
        log.info("[BOOT] snapshot exists. skip rebuild.");
      }
    };
  }
}
