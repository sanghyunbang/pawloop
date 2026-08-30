package com.heattrip.heat_trip_backend.care.dto;

import com.heattrip.heat_trip_backend.user.entity.User;

/**
 * 케어를 한 사람 / 주의사항을 고친 사람 — 계약({@code openapi.yaml})의 {@code CareDoer} 다.
 *
 * <p>이슈 본문은 "응답에 {@code doneByName}" 이라고 적었는데 <b>이름만으로는 부족하다.</b>
 * 앱은 "아빠가 줬습니다" 와 "내가 줬습니다" 를 갈라 그려야 하고, 그 판정은 이름이 아니라
 * {@code userId} 로 한다 — 가족 중에 같은 닉네임이 둘일 수 있고, 닉네임은 언제든 바뀐다.
 * 그래서 {@code userId} 를 함께 싣는다({@code GroupMember} 도 같은 모양이다).
 *
 * <h2>탈퇴한 사람의 자리</h2>
 * <p>{@code care_log.done_by}·{@code walk_note.updated_by} 는 {@code ON DELETE SET NULL} 이다 —
 * 한 사람이 탈퇴했다고 가족이 함께 보는 기록과 메모를 지우지 않는다(그 이유는 두 엔티티의
 * javadoc). 그래서 <b>사람은 없는데 기록은 있는</b> 상태가 정상으로 존재하고, 그때 이 레코드는
 * {@link #WITHDRAWN} 이다.
 *
 * <p>{@code null} 을 싣지 않는 이유: 계약의 {@code CareLog.doneBy} 는 {@code CareDoer} 가
 * <b>반드시 있는</b> 필드다. 여기서 {@code null} 을 내보내면 앱이 "누가" 자리를 빈 칸으로
 * 그리고, 그러면 이 카드가 답해야 하는 질문("오늘 누가 무엇을 했나")에 아무 말도 못 한다.
 * {@code 알 수 없음} 은 최소한 <b>누군가는 했다</b>고 말한다.
 *
 * @param userId   {@code users.id}. <b>탈퇴했으면 0</b> 이다 — 어떤 {@code users.id} 와도 같지
 *                 않아서, 앱의 "내가 했는가" 판정({@code doneBy.userId == 내 id})이 조용히
 *                 참이 되는 일이 없다
 * @param nickname {@link User#displayName()} — 닉네임 · 이름 · {@code 알 수 없음} 순서다.
 *                 표시 이름을 고르는 규칙이 저장소에 한 벌만 있게 하려고 엔티티에서 읽는다
 */
public record CareDoerResponse(long userId, String nickname) {

    /**
     * 탈퇴한 계정의 자리. 문구를 여기 적지 않고 {@link User#UNKNOWN_DISPLAY_NAME} 을 가리키는
     * 것이 요점이다 — {@code FamilyGroupService.WITHDRAWN_MEMBER} 도 같은 상수를 가리킨다.
     * 문구를 각자 적으면 같은 사람이 가족 화면과 케어 카드에서 다른 이름으로 보인다.
     */
    static final CareDoerResponse WITHDRAWN =
            new CareDoerResponse(0L, User.UNKNOWN_DISPLAY_NAME);

    static CareDoerResponse of(User user) {
        return user == null ? WITHDRAWN : new CareDoerResponse(user.getId(), user.displayName());
    }
}
