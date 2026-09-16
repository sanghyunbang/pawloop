package com.heattrip.heat_trip_backend.care.dto;

import java.util.List;

/**
 * 목록의 순서 — 계약({@code openapi.yaml})의 {@code CareItemOrderInput} 이다. 이슈 #560.
 *
 * <h2>왜 목록 전체를 받나</h2>
 *
 * <p>"3번 항목을 1번으로" 처럼 한 건만 받으면 <b>나머지가 어떻게 밀리는지를 서버가 지어내야
 * 한다</b> — 그리고 그 지어낸 규칙이 앱의 끌어 놓기 애니메이션과 한 칸이라도 다르면, 손을 뗀
 * 자리와 다시 그려진 자리가 어긋난다. 화면이 이미 최종 순서를 알고 있으니 그것을 그대로
 * 보내는 쪽이 맞다.
 *
 * <p><b>빠진 항목이 있으면 400 이다.</b> 조용히 뒤에 붙이면 두 사람이 동시에 순서를 바꿨을 때
 * 나중 요청이 먼저 요청의 새 항목을 맨 뒤로 보낸다. 거절하면 앱이 목록을 다시 읽는다.
 *
 * <p><b>접힌 항목도 포함한다.</b> 고치기 화면이 접힌 것까지 한 목록으로 보여 주고 거기서도
 * 끌어 옮길 수 있다 — 다시 켰을 때 맨 뒤로 튀지 않게 하려면 접힌 동안에도 자리가 있어야 한다.
 *
 * @param itemIds 그 집 항목의 {@code id} <b>전부</b>를, 화면에 보이는 순서대로
 */
public record CareItemOrderRequest(List<Long> itemIds) {
}
