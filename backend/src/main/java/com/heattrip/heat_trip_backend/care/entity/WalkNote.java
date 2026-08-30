package com.heattrip.heat_trip_backend.care.entity;

import com.heattrip.heat_trip_backend.group.entity.FamilyGroup;
import com.heattrip.heat_trip_backend.user.entity.User;

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

import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

/**
 * 산책 주의사항 — <b>그룹당 한 장</b>. 이슈 #76, 문서는 {@code docs/03-database/schema.md §16}.
 *
 * <h2>왜 한 장인가 — 문서 셋이 여러 장이라고 적고 있었다</h2>
 * <p>이슈 #76 이 정한 모양은 {@code walk_note(id, group_id FK, body, updated_by, updated_at)}
 * <b>그룹당 한 장</b>이다. 그런데 {@code schema.md §16}·{@code openapi.yaml}·{@code api-spec.md}
 * 는 1:N 목록(행마다 {@code created_at}, PUT 은 {@code {notes: [...]}} 로 전량 교체)으로 적혀
 * 있었다. 이 커밋이 셋을 이슈에 맞췄다. 고른 이유:
 * <ul>
 *   <li>목록을 <b>전량 교체</b>로 다루면 PUT 때마다 행을 지우고 다시 넣게 되고, 그러면
 *       행마다 붙는 {@code updated_by}·{@code id} 가 매번 갈린다 — "누가 고쳤는지" 가
 *       사실은 아무것도 가리키지 않게 된다.</li>
 *   <li>완료 조건 4 가 요구하는 것은 <b>"한쪽이 고치면 다른 쪽에 보인다"</b> 이지 항목별
 *       이력이 아니다. 한 장이면 그 문장이 그대로 표가 된다.</li>
 * </ul>
 *
 * <p><b>앱이 이것을 줄 단위 목록으로 그리는 것은 화면의 표현이다.</b> {@code family_screen}
 * 은 {@code body} 를 줄바꿈으로 나눠 항목처럼 보여주고, 추가·삭제는 편집된 전체 본문을 PUT
 * 한다. 서버가 아는 것은 <b>메모 한 장과 그것을 마지막으로 고친 사람</b>뿐이다.
 *
 * <h2>{@code UNIQUE (group_id)} 가 "한 장" 을 지킨다</h2>
 * <p>애플리케이션의 "있으면 고치고 없으면 만든다" 는 확인-후-쓰기라, 두 요청이 정확히 동시에
 * 오면 둘 다 없다고 보고 둘 다 INSERT 할 수 있다. 그때 두 번째를 거절하는 것은 이 제약이다
 * (📌 #86 원칙 5 — 마지막 방어선은 DB).
 */
@Entity
@Table(
        name = "walk_note",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_walknote_group", columnNames = "group_id"))
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PRIVATE)
@Builder
public class WalkNote {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * 소속 그룹. <b>NOT NULL</b> 이다 — {@code care_log.group_id} 와 다른 점이 여기다.
     * 주의사항은 <b>가족과 공유하는 메모</b>라서 그룹 없이는 존재할 이유가 없다.
     *
     * <p>{@code ON DELETE CASCADE} — 그룹이 사라지면 그 그룹의 메모도 사라진다. 남겨 두면
     * 아무도 못 보고 아무도 못 지우는 행이 된다.
     */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "group_id", nullable = false,
            foreignKey = @ForeignKey(name = "fk_walknote_group"))
    @OnDelete(action = OnDeleteAction.CASCADE)
    private FamilyGroup group;

    /**
     * 메모 본문. 빈 문자열이 될 수 있다 — 가족이 내용을 다 지운 상태다.
     *
     * <p>행을 지우지 않고 빈 본문으로 두는 이유: 지우면 "한 번도 안 쓴 그룹" 과 "다 지운
     * 그룹" 이 구별되지 않고, 다시 쓸 때마다 id 가 갈린다.
     */
    @Column(name = "body", nullable = false, length = 500)
    private String body;

    /**
     * 마지막으로 고친 사람. 토큰의 사용자다. <b>그 사람이 탈퇴하면 {@code null} 이 된다.</b>
     *
     * <h2>{@code ON DELETE SET NULL} — CASCADE 였을 때 실제로 무슨 일이 났는가</h2>
     * <p>여기는 2026-08 까지 {@code ON DELETE CASCADE} 였다. 그 상태에서 엄마가 메모를 쓰고
     * {@code DELETE /auth/me} 로 탈퇴하면({@code UserService.deleteMe} 는 {@code users} 행을
     * 실제로 지운다) <b>그룹의 메모 행이 통째로 사라졌다.</b> 남은 가족의 화면은 "아직
     * 주의사항이 없어요" 를 그리므로 <b>지워진 것과 한 번도 안 쓴 것을 구별할 수 없다</b> —
     * 사라졌다는 신호가 아무 데도 없다. 지워지는 내용이 "계단 피하기"·"대형견 만나면 리드줄
     * 짧게" 같은 안전 메모라 실사용 피해가 크다.
     *
     * <p>판단의 요점은 <b>이 컬럼이 문서의 소유자가 아니라 메타데이터</b>라는 것이다.
     * 메모의 주인은 {@link #group} 이고, 그 그룹은 멀쩡히 살아 있다. "마지막으로 고친 사람"
     * 하나 때문에 가족 공유 문서를 지우는 것은 {@code care_log.group} 이 이미 같은 질문에
     * 답한 것과 정확히 반대 방향이었다 — 그쪽 javadoc 은 "가족을 해산했다는 이유로 개인의
     * 케어 이력이 통째로 증발한다" 고 적고 {@code SET NULL} 을 골랐다.
     *
     * <p>그래서 <b>사람이 사라지면 이름만 잃는다.</b> 응답의 표시 이름은
     * {@code CareDoerResponse} 가 {@link User#UNKNOWN_DISPLAY_NAME}({@code 알 수 없음})으로
     * 떨어뜨린다 — {@code GroupMemberResponse.nickname} 이 같은 상황에서 이미 그 문구를 쓴다.
     * {@code CareSharingIntegrationTest.whenOneMemberWithdraws_theFamilysNotesAndLogsSurvive}
     * 가 이 판단을 잠근다.
     *
     * <p><b>{@code updatedBy == null} 과 "행이 없다" 는 다른 상태다.</b> 아직 아무도 안 쓴
     * 그룹은 행 자체가 없어 {@code WalkNoteResponse.empty} 로 답하고 거기서만
     * {@code updatedBy} 가 JSON {@code null} 이다. 여기의 {@code null} 은 "쓴 사람이 있었는데
     * 지금은 가리킬 수 없다" 이고 응답에는 {@code 알 수 없음} 으로 나간다.
     */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "updated_by",
            foreignKey = @ForeignKey(name = "fk_walknote_updatedby"))
    @OnDelete(action = OnDeleteAction.SET_NULL)
    private User updatedBy;

    /** 마지막으로 고친 시각. 서버 시계다. */
    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;

    /** 본문과 "누가 언제" 를 함께 바꾼다 — 셋이 따로 움직이면 남의 이름이 붙는다. */
    public void rewrite(String newBody, User editor, LocalDateTime at) {
        this.body = newBody;
        this.updatedBy = editor;
        this.updatedAt = at;
    }
}
