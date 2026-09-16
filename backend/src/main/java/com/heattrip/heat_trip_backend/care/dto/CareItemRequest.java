package com.heattrip.heat_trip_backend.care.dto;

/**
 * 항목 하나를 만들거나 고칠 때 보내는 것 — 계약({@code openapi.yaml})의 {@code CareItemInput} 이다.
 * 이슈 #560.
 *
 * <h2>{@code POST} 와 {@code PUT} 이 같은 모양을 쓴다</h2>
 *
 * <p>고치기가 <b>부분 수정({@code PATCH})이 아니라 전량 교체({@code PUT})</b>다. 부분 수정으로
 * 두면 "안 보낸 필드" 와 "비우려고 보낸 필드" 가 JSON 에서 <b>둘 다 {@code null}</b> 이라
 * 구분이 안 된다 — 그런데 이 화면에는 비워야 하는 필드가 둘이나 있다({@code dogId} 를 비우면
 * 모든 아이, {@code dailyTarget} 을 비우면 횟수만 세기). {@code walk-notes} 가 같은 이유로
 * {@code PUT} 이다.
 *
 * <p>고치기 화면에는 어차피 네 값이 모두 떠 있으므로 앱이 전부 보내는 것이 자연스럽다.
 *
 * <h2>{@code sortOrder} · {@code systemType} 이 여기 없다</h2>
 *
 * <p>순서는 <b>목록 전체</b>를 한 번에 정해야 뜻이 있다 — 한 항목만 3번이라고 말하면 나머지가
 * 어떻게 밀리는지 서버가 지어내야 한다. {@code PUT /care-items/order} 가 그 자리다.
 *
 * <p>종류({@code systemType})는 "이 항목이 옛 기록을 어떻게 세는가" 라서, 바꾸면 지난 기록이
 * 통째로 다른 칸으로 옮겨 간다. 만들 때도 못 정한다 — 직접 만든 항목은 <b>언제나</b> 비어
 * 있고, 기본 일곱은 가족을 만들 때만 심긴다.
 *
 * @param name        1~20자. 비거나 넘으면 400 이다. 칸 폭이 390dp 에서 73dp 라 그보다 길면
 *                    어차피 잘린다
 * @param icon        고르는 목록의 열쇠말({@code CareIcon}). 목록에 없으면 400 이다
 * @param dogId       선택. 그 집 아이가 아니면 400. <b>비우면 모든 아이</b>
 * @param dailyTarget 선택. 1~20. 비우면 횟수만 센다
 * @param archived    접혔나. {@code POST} 에서는 무시한다 — 만들자마자 접는 것은 화면에 없는
 *                    동작이고, 받아 두면 "안 보이는 항목이 왜 생겼나" 를 설명할 자리가 없다
 */
public record CareItemRequest(
        String name,
        String icon,
        Long dogId,
        Integer dailyTarget,
        Boolean archived) {
}
