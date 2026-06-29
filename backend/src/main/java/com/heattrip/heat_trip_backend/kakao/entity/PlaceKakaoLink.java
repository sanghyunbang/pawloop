package com.heattrip.heat_trip_backend.kakao.entity;

import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.CreationTimestamp;
import java.time.LocalDateTime;

@Entity
@Table(
    name = "place_kakao_links",
    indexes = { @Index(name = "idx_place_kakao_created", columnList = "created") }
)
@Getter @Setter @Builder
@NoArgsConstructor @AllArgsConstructor
public class PlaceKakaoLink {

    @Id
    @Column(name = "id")
    private Long id;                      // places.contentid

    @Column(nullable = false, length = 255)
    private String title;

    @Column(name = "place_url", length = 512)
    private String placeUrl;              // 매칭 실패 시 NULL

    @Column(name = "kakao_mapx")
    private Double kakaoMapx;             // longitude

    @Column(name = "kakao_mapy")
    private Double kakaoMapy;             // latitude

    @CreationTimestamp
    @Column(nullable = false)
    private LocalDateTime created;
}
