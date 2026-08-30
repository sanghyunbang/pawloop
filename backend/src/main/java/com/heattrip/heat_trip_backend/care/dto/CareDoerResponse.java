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
 * @param nickname {@link User#displayName()} — 닉네임 · 이름 · {@code 알 수 없음} 순서다.
 *                 표시 이름을 고르는 규칙이 저장소에 한 벌만 있게 하려고 엔티티에서 읽는다
 */
public record CareDoerResponse(long userId, String nickname) {

    static CareDoerResponse of(User user) {
        return new CareDoerResponse(user.getId(), user.displayName());
    }
}
