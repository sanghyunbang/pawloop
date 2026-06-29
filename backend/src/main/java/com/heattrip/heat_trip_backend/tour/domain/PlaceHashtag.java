package com.heattrip.heat_trip_backend.tour.domain;

import jakarta.persistence.*;
import lombok.*;

/**
 * [place_hashtags] : CAT3별 해시태그를 "행 단위"로 저장.
 * - 예: (#고즈넉함, #한옥정취, #시간여행)
 * - 스냅샷 생성 시 CAT3로 묶어 {@code List<String>}로 합쳐 JSON으로 저장.
 */
@Entity @Table(name = "place_hashtags",
        indexes = { @Index(name="idx_ph_place", columnList = "place_id"),
                    @Index(name="idx_ph_hashtag", columnList = "hashtag") })
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class PlaceHashtag {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** CAT3 코드 */
    @Column(name="place_id", length = 16, nullable = false)
    private String placeId;

    /** "#고즈넉함" 등 */
    @Column(name="hashtag", length = 100, nullable = false)
    private String hashtag;
}
