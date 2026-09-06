package com.heattrip.heat_trip_backend.chat.entity;

import com.heattrip.heat_trip_backend.chat.ChatTime;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
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
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.annotations.OnDelete;
import org.hibernate.annotations.OnDeleteAction;
import org.hibernate.type.SqlTypes;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.LocalDateTime;

/**
 * 방 멤버십 한 행 — 이슈 #74, 근거 ADR-0011 결정 1·6.
 *
 * <h2>멤버십 표는 이것 하나다</h2>
 * <p>{@code group_member} 를 따로 만들지 않는다. 둘을 두면 "가족인데 방에 없는 사람" ·
 * "방에 있는데 가족이 아닌 사람" 이라는 상태가 생기고, 그걸 막는 코드를 영원히 쓴다.
 * 강퇴·재입장 금지·차단이 전부 여기 붙으므로 멤버십이 둘이면 강퇴가 어느 쪽인지를
 * 매번 물어야 한다.
 *
 * <h2>FK 는 {@code chat_room} 쪽에만 있다</h2>
 * <p>{@link #room} 은 chat 경계 <b>안</b>이라 FK 를 걸고 {@code ON DELETE CASCADE} 까지 준다 —
 * 방이 지워지면 그 방의 멤버십도 의미가 없다.
 *
 * <p>반대로 {@link #userId} 와 {@link #removedBy} 는 <b>값만 든다.</b> {@code users} 로 FK 를
 * 내지 않는 것이 이 도메인의 규칙이고, {@code refresh_token.user_id}(#9)가 이미 같은 방식이다.
 * 이유도 같다 — 탈퇴 경로가 DB 삭제 순서에 묶이는 것을 피한다. 특히
 * {@code ON DELETE CASCADE} 는 안 된다: 탈퇴 한 번에 그 사람이 속했던 방의 멤버십 행이
 * 사라지고, 미읽음이 {@code last_read_seq} 뺄셈이라 되돌릴 수 없다.
 * {@code ChatBoundaryArchitectureTest} 가 이 규칙을 잠근다.
 *
 * <h2>행을 지우지 않는다</h2>
 * <p>강퇴는 {@link #removedAt} · {@link #removedBy} 를 찍는 것이고 행은 남는다. 지우면
 * {@link #lastReadSeq} 가 사라져 재입장했을 때 미읽음을 복원할 수 없고, 신고 근거도 없어진다.
 */
@Entity
@Table(
        name = "chat_room_member",
        uniqueConstraints = {
                @UniqueConstraint(
                        name = "uq_chat_member",
                        columnNames = {"room_id", "user_id"})
        },
        indexes = {
                @Index(name = "idx_chat_member_user", columnList = "user_id")
        }
)
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class ChatRoomMember {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** 소속 방. chat 경계 <b>안</b>이라 FK 를 건다. */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(
            name = "room_id",
            nullable = false,
            foreignKey = @ForeignKey(name = "fk_chat_member_room"))
    @OnDelete(action = OnDeleteAction.CASCADE)
    private ChatRoom room;

    /** {@code users.id}. <b>연관 매핑이 아니다</b> — 위 javadoc 참조. */
    @Column(name = "user_id", nullable = false)
    private Long userId;

    /**
     * 문자열로 저장한다. {@code @JdbcTypeCode(VARCHAR)} 가 없으면 Hibernate 6 이
     * MySQL 네이티브 {@code enum} 컬럼을 만든다 — 값이 늘 때 {@code ALTER TABLE} 이 필요해진다.
     *
     * <p>값을 잠그는 {@code CHECK (role in ('OWNER','MEMBER'))} 는 Hibernate 가 이 매핑에서
     * <b>스스로 만든다.</b> {@code @Check} 를 손으로 하나 더 붙였더니 같은 내용의 제약이
     * 두 개 생겼다(실측: {@code chat_room_member_chk_1} 과 이름 붙인 것). 그래서 뗐다.
     */
    @Builder.Default
    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.VARCHAR)
    @ColumnDefault("'MEMBER'")
    @Column(name = "role", nullable = false, length = 10)
    private ChatRoomMemberRole role = ChatRoomMemberRole.MEMBER;

    @Column(name = "joined_at", nullable = false)
    @ColumnDefault("CURRENT_TIMESTAMP(6)")
    private LocalDateTime joinedAt;

    /**
     * 이 사람이 어디까지 읽었는가. 미읽음은 {@code room.last_seq − 이 값}이다.
     *
     * <p>갱신은 {@code GREATEST}(뒤로 못 감) 와 {@code LEAST}({@code room.last_seq} 를 못 넘음)
     * 로만 한다 — ADR-0011 결정 3. 그 로직은 #79 다.
     */
    @Builder.Default
    @ColumnDefault("0")
    @Column(name = "last_read_seq", nullable = false)
    private Long lastReadSeq = 0L;

    /** 강퇴 시각. null 이면 방에 있다. <b>행은 지우지 않는다.</b> */
    @Column(name = "removed_at")
    private LocalDateTime removedAt;

    /** 강퇴한 방장의 {@code users.id}. <b>FK 없음</b>(경계). */
    @Column(name = "removed_by")
    private Long removedBy;

    /** 유효한 초대코드로도 다시 못 들어온다. 강퇴 = 재입장 금지(ADR-0011 결정 6). */
    @Builder.Default
    @ColumnDefault("b'0'")
    @Column(name = "rejoin_blocked", nullable = false)
    private boolean rejoinBlocked = false;

    /** 방별 음소거 시각 — 이 방의 알림이 안 간다(#83). {@code null} 이면 켜져 있다. 멤버십의 속성이라 여기 있다. */
    @Column(name = "muted_at")
    private LocalDateTime mutedAt;

    @PrePersist
    void fillJoinedAt() {
        if (joinedAt == null) {
            joinedAt = ChatTime.nowUtc();
        }
    }
}
