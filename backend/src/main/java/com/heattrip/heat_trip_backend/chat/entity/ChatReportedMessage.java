package com.heattrip.heat_trip_backend.chat.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.ForeignKey;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

import org.hibernate.annotations.OnDelete;
import org.hibernate.annotations.OnDeleteAction;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.LocalDateTime;

/**
 * 신고에 딸린 <b>메시지 사본</b> 한 줄 — 이슈 #82.
 *
 * <h2>참조가 아니라 사본이다</h2>
 * <p>{@code chat_message.id} 로 참조만 걸면, 그 메시지가 지워진 순간 신고가 <b>아무것도
 * 가리키지 않는 행</b>이 된다. 신고를 받아도 무엇이 신고됐는지 알 수 없다.
 *
 * <p>그래서 여기에 {@code room_seq}·{@code sender_user_id}·{@code sender_name}·<b>본문</b>·
 * {@code content_type}·{@code created_at} 을 <b>복사</b>한다. 원본이 소프트 삭제되든
 * 방이 통째로 없어지든 이 행은 그대로 남는다.
 *
 * <p>{@code message_id} 를 함께 들되 <b>FK 는 걸지 않는다</b> — 원본이 살아 있는 동안에는
 * 앞뒤 맥락을 실제로 열어 볼 수 있게 하는 실마리이고, 사라지면 그냥 숫자로 남는다.
 * FK 를 걸면 {@code ON DELETE} 가 무엇이든 사본의 수명이 원본에 묶인다.
 *
 * <h2>{@link #senderName} 을 함께 베끼는 이유</h2>
 * <p>{@code ChatMessage.senderName} 은 <b>보낸 시점의 이름 스냅샷</b>이고 응답 경로는 그것을
 * 쓰지 않는다(그쪽은 지금 {@code users} 의 이름을 쓴다). 이 컬럼이 존재하는 이유가 바로
 * 신고 처리다 — 닉네임은 언제든 바뀌므로, 신고를 훑는 시점에는 "무슨 이름으로 그 말을
 * 했는가" 가 이미 사라져 있다({@code ChatMessage} javadoc).
 *
 * <h2>{@code (report_id, room_seq)} 가 유일하다</h2>
 * <p>같은 메시지를 한 신고에 두 번 넣을 수 없다. 없으면 앱이 같은 항목을 두 번 보내는 것만으로
 * "3개까지" 상한을 우회한다.
 */
@Entity
@Table(
        name = "chat_reported_message",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_chat_reported_msg",
                columnNames = {"report_id", "room_seq"})
)
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class ChatReportedMessage {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * 어느 신고에 딸렸나. <b>여기만 FK 다</b> — 신고가 없어지면 사본도 갈 곳이 없다.
     *
     * <p>{@code chat} 경계 안이고 {@code chat_report} 를 가리킨다. 경계 밖으로 나가는
     * 참조가 아니다.
     */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(
            name = "report_id",
            nullable = false,
            foreignKey = @ForeignKey(name = "fk_chat_reported_msg_report"))
    @OnDelete(action = OnDeleteAction.CASCADE)
    private ChatReport report;

    /** 원본 {@code chat_message.id}. <b>FK 없음</b> — 위 javadoc 참조. */
    @Column(name = "message_id")
    private Long messageId;

    /** 방 안에서의 번호. 앞뒤 맥락을 찾는 좌표다. */
    @Column(name = "room_seq", nullable = false)
    private Long roomSeq;

    /** 보낸 사람의 {@code users.id}. 사본이므로 탈퇴해도 남는다. */
    @Column(name = "sender_user_id", nullable = false)
    private Long senderUserId;

    /** 그때 방 사람들이 실제로 본 이름. */
    @Column(name = "sender_name", nullable = false, length = 255)
    private String senderName;

    /** 본문 <b>사본</b>. 원본과 같은 {@code TEXT}(64KB) 다. */
    @Column(name = "body", nullable = false, columnDefinition = "TEXT")
    private String body;

    @Column(name = "content_type", nullable = false, length = 16)
    private String contentType;

    /** 원본이 보내진 시각. 신고 시각이 아니다. */
    @Column(name = "sent_at", nullable = false)
    private LocalDateTime sentAt;
}
