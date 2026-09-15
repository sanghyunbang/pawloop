package com.heattrip.heat_trip_backend.chat;

/**
 * 말 하나에 붙은 반응 한 종류의 집계 — #452, ADR-0023(#500) 셋째 줄.
 *
 * <h2>{@link #count} 는 "몇 번" 이지 "몇 명" 이 아니다</h2>
 * <p>한 사람이 한 말에 여러 종류를 누를 수 있다({@code ChatMessageReaction} javadoc). 종류마다 세므로
 * 한 종류 안에서는 사람 수와 같지만, 줄 전체의 합을 "N명이 반응했어요" 로 읽으면 거짓말이 된다.
 * 탈퇴한 사람의 반응도 남아서 세어진다 — 그 사람의 말이 방에 남는 것과 같은 규칙이다.
 *
 * <h2>{@link #mine} 은 <b>읽는 사람마다 다른 값</b>이다</h2>
 * <p>{@code ChatMessageResponse.hiddenByBlock} 과 같은 종류의 값이라 캐시할 수 없고, 조립할 때마다
 * 읽는 사람을 알아야 한다.
 *
 * <p>0 인 종류는 아예 오지 않는다 — 아무도 안 누른 종류까지 실으면 말마다 다섯 줄이 나가고, 앱은
 * 어차피 숫자가 있는 것만 그린다.
 */
public record ChatReactionView(String kind, int count, boolean mine) {
}
