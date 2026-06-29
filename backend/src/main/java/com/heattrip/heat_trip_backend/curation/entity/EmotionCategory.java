package com.heattrip.heat_trip_backend.curation.entity;

import jakarta.persistence.*;
import lombok.*;

@Entity
@Table(name = "emotion_categories")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class EmotionCategory {
    @Id
    @Column(name = "category_id")
    private Integer id;

    @Column(name = "category_name")
    private String name;

    @Column(name = "category_emoji")
    private String emoji;

    @Column(name = "characteristic")
    private String characteristic;
}
