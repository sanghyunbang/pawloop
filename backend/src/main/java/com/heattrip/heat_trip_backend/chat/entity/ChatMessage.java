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
 * 메시지 한 행 — 이슈 #78, 근거 ADR-0011 결정 2·4.
 *
 * <h2>{@link #id} 를 커서로 쓰지 않는다</h2>
 * <p>{@code AUTO_INCREMENT} 는 <b>INSERT 시점</b>에 배정되고 남에게 보이는 것은 <b>커밋
 * 시점</b>이다. 두 전송이 겹치면 105 가 먼저 보이고 104 가 나중에 보이는 순간이 실제로
 * 있다. 클라이언트가 {@code afterId=105} 로 다음 폴링을 하면 104 는 <b>다시는 오지
 * 않는다</b> — 앱을 지웠다 깔아도 안 온다. 그래서 커서는 {@link #roomSeq} 다.
 *
 * <p>{@code room_seq} 는 방 단위로 빈틈 없이 1씩 오르고, 그 값을 발급하는 곳은
 * {@code ChatRoomRepository#assignNextSeq} 한 곳이다. 발급이 실패하거나 뒤이은 검사에
 * 걸려 롤백되면 발급도 함께 되돌아간다 — {@code AUTO_INCREMENT} 와 갈리는 지점이 그것이다.
 *
 * <h2>{@link #senderUserId} 는 값만 든다</h2>
 * <p>{@code users} 로 FK 를 내지 않는 것이 이 도메인의 규칙이고({@code refresh_token.user_id}
 * (#9)가 같은 방식), 여기서는 이유가 하나 더 있다: <b>{@code ON DELETE CASCADE} 면 탈퇴 한
 * 번에 그 사람이 방에 쓴 말이 전부 사라진다.</b> 남는 것은 대답만 있고 질문이 없는 대화다.
 * 슬랙·카카오·라인 중 그렇게 하는 곳은 없다. {@code ChatBoundaryArchitectureTest} 가 잠근다.
 *
 * <h2>{@link #senderName} 은 <b>보낸 시점의 스냅샷</b>이고, 응답에 그대로 쓰이지 않는다</h2>
 * <p>이 구분을 흐리면 두 가지가 한꺼번에 틀린다. 응답의 이름은 <b>지금 {@code users} 에
 * 있는 이름</b>이다(#78 완료 조건 4 — 닉네임을 바꾸면 과거 메시지도 따라 바뀐다. 카카오·
 * 라인이 그렇다). 탈퇴해서 없으면 {@code User.UNKNOWN_DISPLAY_NAME}("알 수 없음")이다
 * (완료 조건 3). 그 해석은 <b>chat 밖</b>에서 한다 — chat 은 {@code users} 를 이름으로
 * 부를 수 없기 때문이다(경계). {@code ChatSenderNames} 가 그 자리다.
 *
 * <p>그러면 이 컬럼은 무엇을 위한 것인가. <b>방 안의 사람들이 그때 실제로 본 이름</b>이다.
 * 닉네임은 언제든 바뀌므로, 신고를 받아 {@code idx_chat_sender} 로 발신자의 메시지를 훑는
 * 시점에는 "무슨 이름으로 그 말을 했는가" 가 이미 사라져 있다. 그 한 줄을 남기는 것이
 * 이 컬럼이고, {@code emotion_card.handle}·{@code card_comment.handle} 이 같은 모양이다.
 * <b>응답 경로가 이 값을 읽지 않는다는 사실을 그대로 적어 둔다</b> — 다음 사람이 "스냅샷이
 * 있는데 왜 안 쓰지" 라고 물을 자리이고, 답은 위 두 완료 조건이다.
 *
 * <h2>{@link #deletedAt} 은 톰스톤이다 — 조회에서 거르지 않는다</h2>
 * <p>삭제된 메시지를 조회에서 <b>빼면</b> 그 {@code room_seq} 가 클라이언트에 도달하지
 * 않는다. 미읽음이 {@code room.last_seq − member.last_read_seq} 뺄셈이라, 읽음 커서가 그
 * 번호를 넘지 못하고 <b>뱃지가 영원히 안 지워진다.</b> 그래서 삭제는 소프트이고 조회는
 * 그 행을 <b>톰스톤으로 돌려준다</b>(ADR-0011). 본문을 가리는 것은 응답을 만드는 쪽의
 * 일이지 조회에서 빼는 것이 아니다. 이 이슈는 컬럼까지고 삭제 엔드포인트는 M2.7 이다.
 */
@Entity
@Table(
        name = "chat_message",
        uniqueConstraints = {
                @UniqueConstraint(
                        name = "uq_chat_room_seq",
                        columnNames = {"room_id", "room_seq"}),
                @UniqueConstraint(
                        name = "uq_chat_msg_client",
                        columnNames = {"room_id", "client_msg_id"})
        },
        indexes = {
                @Index(name = "idx_chat_sender", columnList = "sender_user_id")
        }
)
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class ChatMessage {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * 소속 방. chat 경계 <b>안</b>이라 FK 를 걸고 {@code ON DELETE CASCADE} 까지 준다 —
     * 방이 지워지면 그 방의 대화도 갈 곳이 없다.
     *
     * <p>인덱스를 따로 달지 않는다. {@code UNIQUE (room_id, room_seq)} 가 {@code room_id} 를
     * 선두로 갖는 인덱스라 FK 검사도 #79 의 델타 범위 스캔도 그것을 쓴다. 하나 더 만들면
     * 같은 컬럼에 인덱스가 둘이고 쓰기마다 둘 다 갱신된다.
     */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(
            name = "room_id",
            nullable = false,
            foreignKey = @ForeignKey(name = "fk_chat_room"))
    @OnDelete(action = OnDeleteAction.CASCADE)
    private ChatRoom room;

    /** 방 안에서 빈틈 없이 1씩 오르는 번호. 순서·델타·미읽음이 전부 이 하나에서 나온다. */
    @Column(name = "room_seq", nullable = false)
    private Long roomSeq;

    /**
     * {@code users.id}. <b>연관 매핑이 아니다</b> — 위 javadoc 참조.
     *
     * <p>{@code idx_chat_sender} 를 다는 이유는 조회 화면이 아니라 <b>신고 처리</b>다.
     * "이 사람이 이 방들에 무엇을 썼나" 를 물을 때 이 인덱스가 없으면 표 전체를 훑는다
     * (schema.md 인덱스 요약).
     */
    @Column(name = "sender_user_id", nullable = false)
    private Long senderUserId;

    /**
     * 보낸 시점의 표시 이름 스냅샷. 폭은 {@code users.nickname} 과 같은 255 다.
     *
     * <p><b>응답의 {@code senderName} 이 아니다</b> — 위 javadoc 참조.
     */
    @Column(name = "sender_name", nullable = false, length = 255)
    private String senderName;

    /**
     * 본문 종류. 지금은 {@code text} 하나이고, 이미지·시스템 메시지가 오면 값이 는다.
     *
     * <p>enum 으로 두지 않는 이유는 {@code origin_kind} 와 같다 — 값이 늘 때마다 chat 을
     * 고치고 배포해야 한다. 대신 폭을 16 으로 좁혀 둔다.
     */
    @Builder.Default
    @ColumnDefault("'text'")
    @Column(name = "content_type", nullable = false, length = 16)
    private String contentType = "text";

    /**
     * 본문. {@code LONGTEXT} 가 아니라 {@code TEXT}(64KB) 다.
     *
     * <p>한 줄 채팅에 4GB 를 열어 둘 이유가 없고, 폭을 좁히면 실수로 파일을 통째로 밀어
     * 넣는 경로가 DB 에서 막힌다. 길이 상한 자체는 {@code ChatRoomService#postMessage} 가
     * 먼저 거절한다 — 컬럼은 마지막 방어선이다.
     */
    @Column(name = "body", nullable = false, columnDefinition = "TEXT")
    private String body;

    /**
     * 클라이언트가 만든 재전송 멱등키. {@code NULL} 이면 멱등을 요구하지 않는 전송이다.
     *
     * <p><b>{@code UNIQUE (room_id, client_msg_id)} 를 건다.</b> 이슈 본문의 컬럼 목록에는
     * 이 컬럼이 있는데 UNIQUE 는 안 적혀 있어서 판단이 필요했다. 걸지 않으면 지하철에서
     * 타임아웃된 전송을 앱이 재시도할 때 같은 말이 두 줄 남고, 그 둘은 <b>서로 다른
     * {@code room_seq}</b> 를 가져 어느 쪽도 지울 근거가 없다. #79 완료 조건 3·8 이 이
     * 제약을 이름으로 요구하므로, 표를 세우는 지금 함께 건다 — 나중에 걸려면 이미 쌓인
     * 중복을 먼저 정리해야 한다.
     *
     * <p>MySQL 의 UNIQUE 인덱스는 {@code NULL} 을 여러 번 허용한다. 그래서 멱등키 없이
     * 보낸 메시지들은 서로 충돌하지 않는다 — 그것이 이 컬럼을 {@code NOT NULL} 로 두지
     * 않은 이유다.
     */
    @Column(name = "client_msg_id", length = 64)
    private String clientMsgId;

    @ColumnDefault("CURRENT_TIMESTAMP(6)")
    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    /** 소프트 삭제 시각. 조회에서 <b>거르지 않는다</b> — 위 javadoc 참조. */
    @Column(name = "deleted_at")
    private LocalDateTime deletedAt;

    /**
     * 애플리케이션이 값을 안 넣어도 행이 만들어지게 한다.
     *
     * <p>{@code ChatRoom#fillCreatedAt} 과 같은 이유다 — DB 기본값만으로는 부족하다.
     * Hibernate 는 INSERT 에 컬럼을 항상 실어 보내므로 필드가 {@code null} 이면 NOT NULL
     * 위반으로 죽는다.
     */
    @PrePersist
    void fillCreatedAt() {
        if (createdAt == null) {
            createdAt = LocalDateTime.now();
        }
    }
}
