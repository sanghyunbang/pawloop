package com.heattrip.heat_trip_backend.explore.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Getter 
@Setter 
@NoArgsConstructor 
@AllArgsConstructor @Builder

public class PlaceSearchCond {
  private Integer areacode;
  private Integer sigungucode;
  private String cat1;
  private String cat2;
  private String cat3;
}
