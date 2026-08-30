package com.heattrip.heat_trip_backend.chat.entity;

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

import org.hibernate.annotations.ColumnDefault;
import org.hibernate.annotations.OnDelete;
import org.hibernate.annotations.OnDeleteAction;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.LocalDateTime;

/**
 * 초대코드 한 행 — 이슈 #74, 근거 ADR-0011 결정 8.
 *
 * <h2>왜 {@code family_group.invite_code} 컬럼이 아닌가</h2>
 * <p>그건 <b>그룹당 코드 하나가 영구히 사는 모양</b>이다. 만료·사용횟수·폐기를 걸 자리가
 * 컬럼 하나에는 없고, 코드를 바꾸려면 그룹 행을 UPDATE 해야 해서 <b>누가 언제 발급했는지가
 * 남지 않는다.</b> 별도 표로 두면 세 가지가 처음부터 생긴다 — 유효기간·사용횟수·회수.
 *
 * <h2>회수·재발급이 유출 대응의 전부다</h2>
 * <p>방장이 재발급하면 이전 코드에 {@link #revokedAt} 이 찍히고 <b>기존 멤버는 그대로
 * 남는다.</b> 폐기한 {@link #code} 는 UNIQUE 라 재사용하지 않는다.
 *
 * <h2>기본값을 여기 적지 않는다</h2>
 * <p>7일 · 사용 횟수 무제한은 {@code ChatLimits} 가 답한다. 이 엔티티에 상수를 두면
 * 나중에 플랜이 생겼을 때 값이 두 곳에 살게 된다. {@link #expiresAt} 이 {@code null} 이면
 * 무기한, {@link #maxUses} 가 {@code null} 이면 무제한이라는 뜻만 여기 있다.
 *
 * <p>{@link #createdBy} 는 {@code users.id} 를 <b>값으로만</b> 든다 — chat 경계 밖으로 FK 를
 * 내지 않는 규칙 그대로다({@code refresh_token.user_id}, #9 와 같은 계열).
 */
@Entity
@Table(
        name = "chat_room_invite",
        uniqueConstraints = {
                @UniqueConstraint(name = "uq_chat_invite_code", columnNames = {"code"})
        },
        indexes = {
                @Index(name = "idx_chat_invite_room", columnList = "room_id, created_at")
        }
)
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class ChatRoomInvite {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** 대상 방. chat 경계 <b>안</b>이라 FK 를 건다. */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(
            name = "room_id",
            nullable = false,
            foreignKey = @ForeignKey(name = "fk_chat_invite_room"))
    @OnDelete(action = OnDeleteAction.CASCADE)
    private ChatRoom room;

    /** 초대코드. UNIQUE 다 — 폐기한 코드도 재사용하지 않는다. */
    @Column(name = "code", nullable = false, length = 32)
    private String code;

    /** 발급한 방장의 {@code users.id}. <b>FK 없음</b>(경계). */
    @Column(name = "created_by", nullable = false)
    private Long createdBy;

    /** {@code null} 이면 무기한. 만료된 코드로 참여하면 {@code INVITE_EXPIRED}(410). */
    @Column(name = "expires_at")
    private LocalDateTime expiresAt;

    /** {@code null} 이면 무제한. 넘으면 {@code INVITE_USES_EXHAUSTED}(409). */
    @Column(name = "max_uses")
    private Integer maxUses;

    @Builder.Default
    @ColumnDefault("0")
    @Column(name = "used_count", nullable = false)
    private Integer usedCount = 0;

    /** 회수·재발급 시각. 찍히면 {@code INVITE_REVOKED}(410). */
    @Column(name = "revoked_at")
    private LocalDateTime revokedAt;

    @ColumnDefault("CURRENT_TIMESTAMP(6)")
    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    @PrePersist
    void fillCreatedAt() {
        if (createdAt == null) {
            createdAt = LocalDateTime.now();
        }
    }
}
