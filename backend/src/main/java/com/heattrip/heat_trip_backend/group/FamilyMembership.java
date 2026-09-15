package com.heattrip.heat_trip_backend.group;

import java.util.List;

/**
 * "이 사람이 그 가족의 식구인가" 와 "그 가족의 식구는 누구누구인가" — {@code group} 모듈이
 * 밖으로 내놓는 판정이다. 이슈 #563.
 *
 * <h2>왜 이 표면이 필요한가</h2>
 *
 * <p>이 앱의 목적은 <b>업무 분담과 누락 방지</b>다(#76). 한 집에서 한 아이를 여럿이 돌볼 때
 * 누가 무엇을 했는지 보이게 하는 것. 그러려면 <b>"우리 집 아이"</b> 가 있어야 하는데, 지금
 * 아이는 사람 것이다({@code dog.user_id}). 엄마가 보리를 등록하고 아빠가 가족에 들어오면
 * <b>아빠 홈은 "아직 등록된 아이가 없어요" 다</b> — 같이 키우는데도.
 *
 * <p>그래서 {@code dog} 모듈이 "이 그룹의 식구들" 을 물어볼 자리가 필요하다. 그 답의 원본은
 * {@code chat_room_member} 하나이고(ADR-0011), 그 표를 아는 것은 {@code group} 이다.
 *
 * <h2>표를 안 바꾼다 — 집 아이는 파생이다</h2>
 *
 * <p>{@code dog} 에 {@code group_id} 를 더하지 않는다. 더하면 <b>승계 문제가 따라온다</b> —
 * 가족에 들어올 때 내 아이를 옮기고, 나갈 때 되돌리고, 두 가족에 걸친 사람을 정해야 한다.
 * 식구 목록에서 파생하면 그 코드가 통째로 없다: 들어오는 순간 보이고 나가는 순간 빠진다.
 *
 * <p><b>공유되는 것은 돌봄이지 소유가 아니다.</b> 등록 · 수정 · 삭제는 그대로 등록한 사람만이고
 * 남의 것은 404 다(#209 가 정한 "남의 것과 없는 것은 같은 404").
 */
public interface FamilyMembership {

    /**
     * 그 가족의 식구가 맞는지 확인한다.
     *
     * @throws org.springframework.web.server.ResponseStatusException 아니면 <b>403</b>.
     *         없는 그룹도 같은 403 이다 — {@code CareService.requireMemberGroup} 과 같은 규칙으로,
     *         id 를 훑어 남의 가족이 있는지 세지 못하게 한다
     */
    void requireMember(long groupId, long actorUserId);

    /**
     * 그 가족 식구들의 {@code users.id} — 나간 사람은 빠진다.
     *
     * <p><b>인가를 하지 않는다.</b> 부르는 쪽이 {@link #requireMember} 를 먼저 지나야 한다 —
     * 두 가지를 한 메서드에 묶으면 "식구 목록만 필요한 자리" 가 생길 때 인가가 조용히 빠진다.
     */
    List<Long> memberUserIds(long groupId);

    /**
     * <b>이 사람과 같은 집 식구들</b>의 {@code users.id} — 가족이 없으면 자기 자신 하나.
     * 이슈 #563.
     *
     * <p>{@link #memberUserIds} 와 다른 점은 <b>그룹 id 를 안 받는다</b>는 것이다. 산책
     * 목록처럼 "내가 보는 화면" 의 범위를 정할 때는 그룹을 먼저 찾아야 하는데, 그 찾기를
     * 부르는 쪽마다 적으면 "가족이 없으면 어떻게 하나" 의 답이 여러 벌이 된다.
     *
     * <p><b>가족이 없어도 빈 목록이 아니다.</b> 1인 사용자의 화면이 통째로 비면 안 된다 —
     * 그 사람에게 "우리 집" 은 자기 자신이다.
     */
    List<Long> householdUserIds(long actorUserId);
}
