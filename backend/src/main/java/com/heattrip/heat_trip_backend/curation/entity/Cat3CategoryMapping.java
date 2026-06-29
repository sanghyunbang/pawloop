package com.heattrip.heat_trip_backend.curation.entity;

import jakarta.persistence.*;
import lombok.*;

/**
 * 관광 API의 CAT3 코드 → 감정 카테고리 ID 매핑.
 * - emotion 카테고리 집계용
 */
@Entity
@Table(name = "cat3_category_mapping")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class Cat3CategoryMapping {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "mapping_id")
    private Long id;

    @Column(name = "category_id")
    private Integer categoryId;  // FK to emotion_categories

    @Column(name = "cat3_code")
    private String cat3Code;     // ex) A01010800
}
