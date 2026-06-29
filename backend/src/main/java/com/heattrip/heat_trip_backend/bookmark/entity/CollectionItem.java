package com.heattrip.heat_trip_backend.bookmark.entity;

import com.heattrip.heat_trip_backend.user.entity.User;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.OnDelete;
import org.hibernate.annotations.OnDeleteAction;

import java.time.LocalDateTime;

/** 컬렉션-관광지 매핑(중복 방지) */
@Entity
@Table(name = "collection_items",
        uniqueConstraints = @UniqueConstraint(columnNames = {"user_id", "collection_id", "content_id"}))
@Getter @Setter
@NoArgsConstructor @AllArgsConstructor @Builder
public class CollectionItem {

    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** 소유자 (쿼리 편의를 위해 함께 보관) */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false)
    @OnDelete(action = OnDeleteAction.CASCADE)
    private User user;

    /** 부모 컬렉션 */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "collection_id", nullable = false)
    @OnDelete(action = OnDeleteAction.CASCADE) // 컬렉션 삭제 시 아이템도 삭제
    private Collection collection;

    /** 관광지 식별자 */
    @Column(name = "content_id", nullable = false, length = 64)
    private String contentId;

    /** 생성 시각(최신 정렬 기준) */
    private LocalDateTime createdAt;

    @PrePersist
    void onCreate() {
        this.createdAt = LocalDateTime.now();
    }
}
