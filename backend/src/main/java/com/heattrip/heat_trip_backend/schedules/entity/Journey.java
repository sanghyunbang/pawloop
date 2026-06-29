package com.heattrip.heat_trip_backend.schedules.entity;
import com.heattrip.heat_trip_backend.user.entity.User;

import jakarta.persistence.*;

import lombok.*;
import org.hibernate.annotations.OnDelete;
import org.hibernate.annotations.OnDeleteAction;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

@Entity
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Journey {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Integer id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false)
    @OnDelete(action = OnDeleteAction.CASCADE)  // DB에서 연쇄 삭제
    private User user;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "schedule_id")
    @OnDelete(action = OnDeleteAction.CASCADE)  // DB에서 연쇄 삭제 -> 일정 삭제하면 일기도 삭제
//    @OnDelete(action = OnDeleteAction.SET_NULL) // 🔁 일정 삭제해도 일기는 남게
    private Schedule schedule;

    private String title;
    private LocalDate date;
    private String location;
    private String weatherLabel;
    private String moodLabel;
    private String body;

    /**
     * 추천 장소에서 기록한 다이어리인 경우 해당 장소의 contentid. 그 외에는 null.
     * (구버전 클라이언트는 이 필드를 보내지 않으므로 nullable.)
     * B2-2 UGC 감정 집계에서 placeId 기준으로 그룹핑한다.
     */
    @Column(name = "place_id")
    private Long placeId;

    @ElementCollection
    @CollectionTable(name = "journey_photos", joinColumns = @JoinColumn(name = "journey_id"))
    @Column(name = "photo_url")
    private List<String> photos;

    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;

    @PrePersist
    public void onCreate() {
        this.createdAt = LocalDateTime.now();
        this.updatedAt = LocalDateTime.now();
    }

    @PreUpdate
    public void onUpdate() {
        this.updatedAt = LocalDateTime.now();
    }
}


