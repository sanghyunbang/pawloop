package com.heattrip.heat_trip_backend.explore.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder

// 상세 페이지 관련
public class PlaceDetailDto {
  private Long contentid;
  private String title;
  private String addr1;
  private Double mapx, mapy;
  private String firstimage;
  private String detail;

}
