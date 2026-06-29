package com.heattrip.heat_trip_backend.tour.dto;

import java.time.LocalDateTime;

import com.fasterxml.jackson.annotation.JsonFormat;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

import lombok.*;

@Getter 
@Setter 
@NoArgsConstructor 
@AllArgsConstructor 
@Builder
@JsonIgnoreProperties(ignoreUnknown = true)

public class PlaceItemDto {
    private Long contentid;
    private String title;
    private String addr1;
    private String addr2;
    private String zipcode;
    private Double mapx;
    private Double mapy;
    private String firstimage;
    private String firstimage2;
    private String cat1, cat2, cat3;
    private Integer areacode, sigungucode, lDongRegnCd, lDongSignguCd;
    private String tel;
    private String contenttypeid;

//    @JsonFormat(shape = JsonFormat.Shape.STRING, pattern = "yyyyMMddHHmmss") // 예: "20230918141849"
    private LocalDateTime createdtime;

//    @JsonFormat(shape = JsonFormat.Shape.STRING, pattern = "yyyyMMddHHmmss")
    private LocalDateTime modifiedtime;

    private String mlevel;
}