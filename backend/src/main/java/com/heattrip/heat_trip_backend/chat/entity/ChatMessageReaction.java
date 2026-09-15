package com.heattrip.heat_trip_backend.chat.entity;

import com.heattrip.heat_trip_backend.chat.ChatTime;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.ForeignKey;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

import org.hibernate.annotations.OnDelete;
import org.hibernate.annotations.OnDeleteAction;

import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

/**
 * 말 하나에 누른 반응 하나 — #452, ADR-0023(#500) 셋째 줄. 마이그레이션 {@code 48_chat_reaction.sql}.
 *
 * <h2>사람은 id 로만 안다 — {@code users} 로 FK 를 내지 않는다</h2>
 * <p>ADR-0011 결정 4 다. {@code chat_message.sender_user_id} 도 {@code chat_room_member.user_id} 도
 * 같은 모양이고, {@code ChatBoundaryArchitectureTest} 가 이 규칙을 정본 DDL 에 적용해서 잰다.
 * FK 를 걸면 탈퇴 경로가 DB 삭제 순서에 묶이고, {@code ON DELETE CASCADE} 면 탈퇴 한 번에 남의
 * 대화에 남아 있던 반응이 사라진다. <b>탈퇴한 사람의 반응은 그 사람의 말과 같은 규칙으로 남는다</b>
 * (처리방침 §3 — 보낸 것은 받은 사람의 대화방에 남는다). 그래서 집계는 "몇 번" 이지 "지금 방에
 * 있는 몇 명" 이 아니다.
 *
 * <h2>한 사람이 한 말에 <b>여럿</b>을 누를 수 있다</h2>
 * <p>{@code UNIQUE (message_id, user_id, kind)} 가 이 표의 불변식이다 — 커뮤니티 {@code reaction}
 * 과 같은 판단이다(ADR-0016 결정 2). {@code (message_id, user_id)} 로 좁히면 라디오가 되고, 나중에
 * 넓히려면 계약의 파괴적 변경이다. 반대로 넓게 두었다가 좁히는 것은 <b>행을 지우는 마이그레이션</b>
 * 이라 어느 반응을 남길지 제품이 다시 답해야 한다. 넓은 쪽이 되돌리기 싸다.
 *
 * <p>이 UNIQUE 가 멱등을 딛는다 — 켜기({@code POST})와 끄기({@code DELETE})가 따로이고 둘 다 두 번
 * 눌러도 같은 결과다({@link com.heattrip.heat_trip_backend.chat.repository.ChatMessageReactionRepository}).
 *
 * <h2>종류에 {@code CHECK} 를 걸지 않는다</h2>
 * <p>커뮤니티 {@code Reaction} 과 같은 이유다. 반응 종류는 제품이 늘릴 수 있는 목록이고 계약의
 * {@code ChatReactionKind} 가 단일 출처다 — 값이 늘 때마다 마이그레이션이 따라오면 그 자체가 비용이다.
 * 아는 종류만 받는 문은 서버에 있다({@code ChatRoomService.REACTION_KINDS}).
 *
 * <h2>지운 말의 반응은 지운다</h2>
 * <p>FK 의 {@code CASCADE} 는 <b>행을 하드 삭제할 때</b>의 이야기다. 소프트 삭제(톰스톤)는 행이 남으므로
 * 서버가 반응을 따로 지운다({@code ChatRoomService#deleteMessage}) — 지운 말 밑에 "5명이 공감" 이
 * 남으면 지운 사람에게는 지워지지 않은 것이나 같다.
 */
@Entity
@Table(
        name = "chat_message_reaction",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_chat_reaction",
                columnNames = {"message_id", "user_id", "kind"}))
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PRIVATE)
@Builder
public class ChatMessageReaction {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** 반응이 붙은 말. 말이 <b>정말로</b> 사라지면 이 행도 사라진다(운영 정리 · CASCADE). */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "message_id", nullable = false,
            foreignKey = @ForeignKey(name = "fk_chat_reaction_message"))
    @OnDelete(action = OnDeleteAction.CASCADE)
    private ChatMessage message;

    /** 누른 사람. <b>FK 가 아니다</b> — 클래스 javadoc. */
    @Column(name = "user_id", nullable = false)
    private Long userId;

    /** {@code like} · {@code heart} · {@code laugh} · {@code sad} · {@code check}. 계약이 단일 출처다. */
    @Column(name = "kind", nullable = false, length = 20)
    private String kind;

    /** UTC 다 — 이유는 {@link ChatTime}. 응답에 안 싣는다(집계만 나간다). */
    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    @PrePersist
    void onCreate() {
        if (createdAt == null) {
            createdAt = ChatTime.nowUtc();
        }
    }
}
