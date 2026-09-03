package com.heattrip.heat_trip_backend.moderation.entity;

import com.heattrip.heat_trip_backend.moderation.ModerationTime;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.LocalDateTime;

/**
 * 한 사람이 다른 사람을 가린 것 — 이슈 #82, 근거 ADR-0011.
 *
 * <h2>차단이 아니라 <b>가리기</b>다</h2>
 * <p>이름은 {@code block} 이지만 하는 일은 <b>내 화면에서만 접는 것</b>이다. 그 사람의
 * 메시지를 지우지 않고, 다른 멤버 화면에는 그대로 남는다. 방에서 내보내지도 않는다.
 *
 * <p><b>여기가 업계 표준에서 벗어나는 유일한 지점이다.</b> 왓츠앱은 그룹에서는 차단이 안
 * 통한다고 문장으로 써 놨고(https://faq.whatsapp.com/414631957536067) 해결책이 "방을
 * 나가라" 다. 우리는 방이 둘뿐이라 나가면 갈 데가 없다. 동작은 카카오 오픈채팅의
 * "가리기" 와 같다.
 *
 * <h2>방이 아니라 사람 단위다</h2>
 * <p>계약의 경로가 {@code /api/blocks} 이고 방 id 가 없다. 가족 방에서 가린 사람을
 * 반려동물 방에서는 봐야 할 이유가 없고, 방마다 따로 걸게 하면 방이 늘 때마다 사용자가
 * 같은 일을 다시 해야 한다.
 *
 * <h2>{@code users} 로 FK 를 내지 않는다</h2>
 * <p>{@code chat} 경계다(ADR-0011 결정 4). 여기서는 이유가 하나 더 있다 — 가린 사람이
 * 탈퇴해도 <b>가린 상태는 남아야</b> 한다. 탈퇴한 계정의 과거 메시지는 방에 남아 있고
 * ({@code chat_message} 는 {@code users} 로 CASCADE 하지 않는다), 그 메시지가 다시
 * 펼쳐지면 가린 사람에게는 되돌아온 것으로 보인다.
 */
@Entity
@Table(
        name = "user_block",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_user_block",
                columnNames = {"blocker_user_id", "blocked_user_id"})
)
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Block {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * 가린 사람의 {@code users.id}.
     *
     * <p>{@code UNIQUE (blocker_user_id, blocked_user_id)} 가 선두 컬럼 인덱스라 "내가 가린
     * 사람들" 조회가 그것을 쓴다. 인덱스를 따로 달지 않는다 — 같은 컬럼에 둘을 만들면
     * 쓰기마다 둘 다 갱신된다({@code chat_message.room_id} 와 같은 판단).
     */
    @Column(name = "blocker_user_id", nullable = false)
    private Long blockerUserId;

    /** 가려진 사람의 {@code users.id}. */
    @Column(name = "blocked_user_id", nullable = false)
    private Long blockedUserId;

    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    @PrePersist
    void fillCreatedAt() {
        if (createdAt == null) {
            createdAt = ModerationTime.nowUtc();
        }
    }
}
