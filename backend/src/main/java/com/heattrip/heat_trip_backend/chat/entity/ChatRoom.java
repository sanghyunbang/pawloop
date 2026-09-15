package com.heattrip.heat_trip_backend.chat.entity;

import com.heattrip.heat_trip_backend.chat.ChatTime;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

import org.hibernate.annotations.ColumnDefault;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.LocalDateTime;

/**
 * 채팅방 한 행 — 이슈 #74, 근거 ADR-0011.
 *
 * <h2>방은 가족 그룹에 종속되지 않는다</h2>
 * <p>가족방도 산책 크루 방도 같은 표에 산다. 출처는 {@link #originKind}(방을 만든 도메인)와
 * {@link #originRef}(그 도메인의 id 를 문자열로) <b>한 쌍</b>으로만 든다.
 *
 * <p><b>이 두 값은 불투명 문자열이다.</b> chat 은 그 값을 파싱하지도, 역참조하지도,
 * 존재를 확인하지도 않는다. 다시 말해 {@code originKind.equals("FAMILY")} 로 갈라져
 * {@code FamilyGroupRepository} 를 부르는 코드를 쓰면 그 순간 이 설계가 사라진다.
 * chat 이 family 를 아는 통로는 이 쌍 하나이고 그 반대는 없다.
 * {@code ChatBoundaryArchitectureTest} 가 chat 패키지의 import 를 훑어 그것을 막는다.
 *
 * <h2>{@code UNIQUE (origin_kind, origin_ref)} 가 이 표의 핵심 제약이다</h2>
 * <p>"이 그룹의 방이 이미 있나 보고 없으면 만든다" 를 애플리케이션 조건문으로 두면
 * 두 요청이 동시에 통과해 같은 그룹에 방이 둘 생긴다. 그 순간 멤버십이 갈라지고
 * 어느 방이 진짜인지 아무도 모른다. 확인-후-쓰기를 DB 유니크 제약으로 받치는 것은
 * 이 저장소의 규칙이고({@code users(provider, social_id)} · {@code refresh_token.token_hash}
 * 와 같은 계열), 실제로 두 번째 INSERT 가 거부되는 것을
 * {@code ChatRoomRepositoryTest} 가 실제 MySQL 위에서 확인한다.
 * {@code ddl-auto=validate} 도 {@code SchemaDdlDriftTest} 도 UNIQUE 를 보지 않는다 —
 * 그 테스트가 없으면 제약이 빠져도 아무도 모른다.
 *
 * <h2>{@link #lastSeq} 는 발급기이자 미읽음 뺄셈의 좌변이다</h2>
 * <p>한 컬럼으로 둔 이유는 두 값이 서로 다른 문장에서 움직여 어긋날 여지를 없애기
 * 위해서다(ADR-0011 결정 2·3). <b>발급 로직은 이 이슈의 범위가 아니다</b> —
 * {@code UPDATE chat_room SET last_seq = LAST_INSERT_ID(last_seq + 1) WHERE id = ?} 는
 * 이슈 #78 이 넣는다. 여기서는 컬럼과 기본값 0 까지다.
 */
@Entity
@Table(
        name = "chat_room",
        uniqueConstraints = {
                @UniqueConstraint(
                        name = "uq_chat_room_origin",
                        columnNames = {"origin_kind", "origin_ref"})
        }
)
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class ChatRoom {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * 방을 만든 도메인 이름. {@code 'FAMILY'} 같은 문자열이다.
     *
     * <p><b>enum 으로 만들지 않았다.</b> enum 으로 두면 새 방 종류가 생길 때마다 chat 을
     * 고쳐야 하고, 그건 "방을 도메인에서 뗀다" 는 결정을 되돌리는 것이다.
     */
    @Column(name = "origin_kind", nullable = false, length = 20)
    private String originKind;

    /** 출처 도메인의 id 를 문자열로. <b>FK 가 아니다</b> — 위 javadoc 참조. */
    @Column(name = "origin_ref", nullable = false, length = 64)
    private String originRef;

    /**
     * 방 이름. 앱의 {@code ChatRoom(name:)}(`app/lib/v2/domain/pet.dart`)과 같은 자리다.
     */
    @Column(name = "name", nullable = false, length = 50)
    private String name;

    /**
     * 이름을 고친다. 검증은 {@code ChatRoomService#renameRoom} 이 한다 — 이슈 #417.
     *
     * <p>{@code @Setter} 를 안 붙이는 것이 요점이다. 붙이면 {@code originKind}·{@code lastSeq}
     * 까지 밖에서 바꿀 수 있게 되고, 그 둘은 바뀌면 안 되는 값이다.
     */
    public void rename(String name) {
        this.name = name;
    }

    /**
     * 방 종류를 화면에서 가르는 꼬리표 — '가족' · '산책 크루'.
     *
     * <p>{@link #originKind} 와 역할이 다르다. {@code originKind} 는 기계가 읽는 출처이고
     * 이건 사람이 읽는 이름표다. 앱의 {@code chat_list_screen.dart} 가 방별 화면을
     * 하나로 쓰면서 종류를 이 값으로만 가른다(ADR-0011 맥락).
     */
    @Column(name = "tag", nullable = false, length = 20)
    private String tag;

    /**
     * {@code chat_message.room_seq} 발급 카운터이자 미읽음 뺄셈의 좌변.
     *
     * <p>발급은 #78 이다. 여기서는 컬럼과 기본값 0 만 둔다.
     */
    @Builder.Default
    @ColumnDefault("0")
    @Column(name = "last_seq", nullable = false)
    private Long lastSeq = 0L;

    /**
     * 이 방에서 <b>이미 보낸 말이 바뀐 횟수</b>의 발급 카운터 — ADR-0023(#500).
     *
     * <p>{@link #lastSeq} 와 축이 다르다. 그건 "방에 들어온 순서" 이고 이건 "바뀐 순서" 다. 삭제(#197)나
     * 앞으로의 반응은 번호를 늘리지 않으므로 델타 폴링({@code afterSeq})이 영영 못 따라잡는다 — 그 변화를
     * 흘려보내는 축이 이 카운터다. 발급은 {@code room_seq} 와 같은 한 문장이라 시계가 필요 없다.
     *
     * <p>미읽음 뺄셈에는 들어가지 않는다. 남이 지운 말이 내 뱃지를 올리면 안 된다.
     */
    @Builder.Default
    @ColumnDefault("0")
    @Column(name = "last_change_seq", nullable = false)
    private Long lastChangeSeq = 0L;

    @ColumnDefault("CURRENT_TIMESTAMP(6)")
    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    /**
     * 애플리케이션이 값을 안 넣어도 행이 만들어지게 한다.
     *
     * <p>DB 기본값({@code CURRENT_TIMESTAMP})만으로는 부족하다 — Hibernate 는 INSERT 에
     * 컬럼을 항상 실어 보내므로 필드가 {@code null} 이면 NOT NULL 위반으로 죽는다.
     * 기본값은 운영자가 손으로 INSERT 할 때를 위한 것이고, 이쪽이 앱 경로를 받친다.
     */
    @PrePersist
    void fillCreatedAt() {
        if (createdAt == null) {
            createdAt = ChatTime.nowUtc();
        }
    }
}
