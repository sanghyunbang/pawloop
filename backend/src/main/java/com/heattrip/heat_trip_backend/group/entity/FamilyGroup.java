package com.heattrip.heat_trip_backend.group.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

import org.hibernate.annotations.ColumnDefault;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.LocalDateTime;

/**
 * 가족 케어 그룹 한 행 — 이슈 #75, 근거 ADR-0011. 문서는 {@code docs/03-database/schema.md §11}.
 *
 * <h2>컬럼이 셋뿐인 것이 이 표의 요점이다</h2>
 * <p>{@code invite_code} 도 멤버십도 여기 없다.
 * <ul>
 *   <li><b>초대코드</b>는 {@code chat_room_invite} 다. 컬럼 하나로 두면 그룹당 코드 하나가
 *       영구히 살고, 만료·사용횟수·회수를 걸 자리가 없다. 코드를 바꾸려면 그룹 행을
 *       UPDATE 해야 해서 누가 언제 발급했는지도 안 남는다.</li>
 *   <li><b>멤버십</b>은 {@code chat_room_member} 다. {@code group_member} 를 따로 만들면
 *       "가족인데 방에 없는 사람"·"방에 있는데 가족이 아닌 사람" 이라는 상태가 생기고,
 *       그걸 막는 코드를 영원히 쓴다(ADR-0011 결정 1).</li>
 * </ul>
 *
 * <h2>방을 가리키는 필드가 없다 — 화살표는 반대 방향이다</h2>
 * <p>{@code chat_room} 이 {@code origin_kind='FAMILY'} · {@code origin_ref=<이 행의 id>} 로
 * 이 그룹을 <b>불투명하게</b> 가리킨다. 그 반대 방향(여기서 {@code chat_room} 으로 가는
 * 필드나 FK)은 두지 않는다 — 두는 순간 두 표가 서로를 알게 되어 어느 쪽도 혼자 못 움직인다.
 * {@code ChatBoundaryArchitectureTest} 가 양쪽 방향을 다 잠근다.
 *
 * <p>그래서 <b>이 표에는 FK 가 하나도 없다.</b> {@code walk_note}·{@code care_log}(M2.5 나머지)가
 * 이 표를 가리키게 되고, 그건 그때 그 표들이 거는 것이다.
 */
@Entity
@Table(name = "family_group")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class FamilyGroup {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * 그룹 이름. 방 이름과 같은 길이({@code varchar(50)})다 — 그룹을 만들면 같은 이름의 방이
     * 함께 생기므로, 여기만 길면 그룹은 만들어지고 방 생성이 실패한다.
     */
    @Column(name = "name", nullable = false, length = 50)
    private String name;

    @ColumnDefault("CURRENT_TIMESTAMP(6)")
    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    /**
     * 애플리케이션이 값을 안 넣어도 행이 만들어지게 한다.
     *
     * <p>DB 기본값만으로는 부족하다 — Hibernate 는 INSERT 에 컬럼을 항상 실어 보내므로
     * 필드가 {@code null} 이면 NOT NULL 위반으로 죽는다. chat 세 표가 쓰는 것과 같은 방식이다.
     */
    @PrePersist
    void fillCreatedAt() {
        if (createdAt == null) {
            createdAt = LocalDateTime.now();
        }
    }
}
