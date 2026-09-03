package com.heattrip.heat_trip_backend.chat.entity;

import com.heattrip.heat_trip_backend.chat.ChatTime;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.OneToMany;
import jakarta.persistence.OrderBy;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

/**
 * 신고 한 건 — 이슈 #82, 근거 ADR-0011.
 *
 * <h2>왜 원본을 참조하지 않고 베껴 두는가</h2>
 * <p>신고는 <b>원본이 사라진 뒤에 읽는 기록</b>이다. 신고당한 사람이 메시지를 지우거나 방이
 * 없어지면, 참조만 들고 있던 신고는 <b>아무것도 가리키지 않는 행</b>이 된다. 그 상태로는
 * 판단이 불가능하다 — 신고를 받아도 무엇이 신고됐는지 알 수 없다.
 *
 * <p>그래서 {@link ChatReportedMessage} 가 본문까지 <b>사본</b>으로 든다. 왓츠앱도 본문뿐
 * 아니라 전송 시각·메시지 유형·대상 ID 까지 받아 둔다
 * (https://faq.whatsapp.com/1142481766359885).
 *
 * <h2>{@link #roomId} 에 FK 를 걸지 않는다</h2>
 * <p>{@code chat} 경계 <b>안</b>이라 걸 수는 있다. 걸지 않는 이유는 경계가 아니라 <b>보존</b>
 * 이다 — {@code chat_message}·{@code chat_room_member} 는 {@code ON DELETE CASCADE} 이므로
 * 방이 지워지면 함께 지워지는 것이 맞지만, <b>신고 기록까지 방과 함께 사라지면 안 된다.</b>
 * 방을 지우는 것으로 신고를 지울 수 있게 되기 때문이다.
 *
 * <p>{@code ChatBoundaryArchitectureTest} 가 "chat_* 의 FK 는 {@code chat_room} 을 가리키는
 * 것뿐" 을 잠그고 있고, 여기는 그 목록에 들어가지 않는다.
 *
 * <h2>앞뒤 5개는 <b>범위만</b> 남긴다</h2>
 * <p>{@link #contextFromSeq}·{@link #contextToSeq} 는 고른 메시지 앞뒤 각 5개를 포함하는
 * {@code room_seq} 구간이다. <b>그 구간의 메시지를 베끼지는 않는다.</b>
 *
 * <p><b>한계를 그대로 적는다.</b> 원본이 지워지면 앞뒤 맥락은 실제로 못 읽는다 — 남는 것은
 * "어디를 봐야 하는가" 뿐이다. 맥락까지 베끼면 신고 한 번에 메시지 11개가 복사되고, 그건
 * 신고당하지 않은 사람들의 말까지 신고 기록으로 옮겨 적는 것이다. 이슈 #82 가 요구한 것도
 * "앞뒤 각 5개의 {@code room_seq} <b>범위</b>를 함께 기록" 이다.
 *
 * <h2>신고자·피신고자는 값이다</h2>
 * <p>{@code users} 로 FK 를 내지 않는다({@code chat} 경계 — ADR-0011 결정 4). 탈퇴해도 신고
 * 기록은 남아야 하므로 여기서는 그 성질이 오히려 필요하다.
 */
@Entity
@Table(
        name = "chat_report",
        indexes = {
                // 운영자가 묻는 것은 "이 사람이 신고를 몇 번 받았나" 다.
                @Index(name = "idx_chat_report_reported", columnList = "reported_user_id"),
                // 신고자 기준 조회는 중복 신고를 볼 때 쓴다.
                @Index(name = "idx_chat_report_reporter", columnList = "reporter_user_id"),
                @Index(name = "idx_chat_report_room", columnList = "room_id")
        }
)
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class ChatReport {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** 신고한 사람의 {@code users.id}. <b>응답에 절대 싣지 않는다</b> — 신고자는 익명이다. */
    @Column(name = "reporter_user_id", nullable = false)
    private Long reporterUserId;

    /** 신고당한 사람의 {@code users.id}. */
    @Column(name = "reported_user_id", nullable = false)
    private Long reportedUserId;

    /** 어느 방이었나. <b>FK 없음</b> — 위 javadoc 참조. */
    @Column(name = "room_id", nullable = false)
    private Long roomId;

    /** 고른 메시지 앞 5개까지 내려간 {@code room_seq}. 1 보다 작아지지 않는다. */
    @Column(name = "context_from_seq", nullable = false)
    private Long contextFromSeq;

    /** 고른 메시지 뒤 5개까지 올라간 {@code room_seq}. */
    @Column(name = "context_to_seq", nullable = false)
    private Long contextToSeq;

    /**
     * 사유 분류. <b>필수</b>이고 어휘는 {@code ChatReportReason} 이 소유한다.
     *
     * <p>{@code ordinal()} 이 아니라 문자열을 저장한다 — 목록 가운데에 하나를 끼우는 순간
     * 이미 저장된 신고의 뜻이 바뀐다.
     */
    @Column(name = "reason", nullable = false, length = 16)
    private String reason;

    /**
     * 신고자가 덧붙인 말. 비워도 된다.
     *
     * <p>분류만으로는 "무엇이 문제였는지" 를 못 적는 경우가 있어서 함께 받는다.
     * 500자를 넘기면 저장 전에 잘린다.
     */
    @Column(name = "memo", length = 500)
    private String memo;

    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    /**
     * 신고에 딸린 메시지 사본 — 최대 3개.
     *
     * <p>{@code CascadeType.ALL} 이라 신고를 저장하면 사본도 함께 저장된다. 사본만 따로
     * 사는 일이 없으므로 {@code orphanRemoval} 까지 준다.
     */
    @Builder.Default
    @OneToMany(mappedBy = "report", cascade = CascadeType.ALL, orphanRemoval = true)
    @OrderBy("roomSeq asc")
    private List<ChatReportedMessage> messages = new ArrayList<>();

    @PrePersist
    void fillCreatedAt() {
        if (createdAt == null) {
            createdAt = ChatTime.nowUtc();
        }
    }

    /** 사본을 붙이면서 양쪽 참조를 맞춘다 — 한쪽만 세우면 저장 시 {@code report_id} 가 빈다. */
    public void addMessage(ChatReportedMessage snapshot) {
        messages.add(snapshot);
        snapshot.setReport(this);
    }
}
