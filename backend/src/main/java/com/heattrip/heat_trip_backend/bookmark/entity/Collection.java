package com.heattrip.heat_trip_backend.bookmark.entity;

import com.heattrip.heat_trip_backend.user.entity.User;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.OnDelete;
import org.hibernate.annotations.OnDeleteAction;

import java.time.LocalDateTime;

/** 사용자별 컬렉션(폴더) */
@Entity
@Table(name = "collections",
        uniqueConstraints = @UniqueConstraint(columnNames = {"user_id", "name"})) // 사용자 내 이름 중복 방지
@Getter @Setter
@NoArgsConstructor @AllArgsConstructor @Builder
public class Collection {

    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** 소유자 */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false)
    @OnDelete(action = OnDeleteAction.CASCADE) // 사용자가 삭제되면 컬렉션도 삭제
    private User user;

    /** 컬렉션 이름 */
    @Column(nullable = false, length = 60)
    private String name;

    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;

    @PrePersist
    void onCreate() {
        this.createdAt = LocalDateTime.now();
        this.updatedAt = LocalDateTime.now();
    }

    @PreUpdate
    void onUpdate() {
        this.updatedAt = LocalDateTime.now();
    }
}
