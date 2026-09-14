package com.heattrip.heat_trip_backend.community.entity;

import com.heattrip.heat_trip_backend.community.CommunityTime;
import com.heattrip.heat_trip_backend.user.entity.User;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.ForeignKey;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.OnDelete;
import org.hibernate.annotations.OnDeleteAction;

import java.time.LocalDateTime;

/**
 * 글 저장 — "내 사진첩" 에 넣어 둔 글 (이슈 #451 4번).
 *
 * <h2>{@code reaction} 과 닮았지만 다른 점 둘</h2>
 * <p><b>탈퇴하면 행이 사라진다</b>({@code ON DELETE CASCADE}). 반응은 집계가 남아야 해서
 * {@code SET NULL} 인데, 저장은 그 사람만 보는 목록이라 사람이 없으면 목록도 없다. 그래서
 * {@code user_id} 가 {@code NOT NULL} 이고 유니크는 {@code (post_id, user_id)} 둘이다 —
 * 종류가 없으니 세 번째 축이 없다.
 *
 * <p><b>정렬 축이 이 표의 시각이다.</b> 저장한 글 목록은 "언제 저장했나" 순이지 글이 쓰인
 * 순이 아니다(Instagram 의 저장됨). 그래서 {@code idx_post_bookmark_user (user_id, created_at, id)}
 * 가 커서 축을 그대로 든다.
 *
 * <h2>표 이름이 {@code post_bookmark} 인 이유</h2>
 * <p>{@code bookmark} 는 장소 저장(계획, schema.md §10)이 예약한 이름이다. 글 저장과 장소 저장은
 * 대상이 다른 두 표다.
 */
@Entity
@Table(
        name = "post_bookmark",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_post_bookmark",
                columnNames = {"post_id", "user_id"}),
        indexes = @Index(name = "idx_post_bookmark_user", columnList = "user_id, created_at, id"))
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PRIVATE)
@Builder
public class PostBookmark {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** 저장한 글. 글이 사라지면 이 행도 사라진다. */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "post_id", nullable = false,
            foreignKey = @ForeignKey(name = "fk_post_bookmark_post"))
    @OnDelete(action = OnDeleteAction.CASCADE)
    private Post post;

    /** 저장한 사람. 탈퇴하면 목록째 사라진다 — 남이 볼 수 없는 목록이라 남길 이유가 없다. */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "user_id", nullable = false,
            foreignKey = @ForeignKey(name = "fk_post_bookmark_user"))
    @OnDelete(action = OnDeleteAction.CASCADE)
    private User user;

    /** 저장한 순간 — 목록의 정렬 축. UTC 다({@link CommunityTime}). */
    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    @PrePersist
    void onCreate() {
        if (createdAt == null) {
            createdAt = CommunityTime.nowUtc();
        }
    }
}
