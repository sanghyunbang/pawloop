package com.heattrip.heat_trip_backend.community.dto;

/**
 * 저장·저장 취소의 응답 — 계약의 {@code BookmarkState} (이슈 #451 4번).
 *
 * <p>반응처럼 집계를 싣지 않는다 — 저장은 <b>세지 않는다.</b> "몇 명이 저장했나" 는 화면에
 * 없고, 있으면 글쓴이에게 남의 사진첩을 들여다보는 숫자가 된다. 응답이 상태 하나뿐인데도
 * 본문을 주는 이유는 {@code 204} 로 비우면 앱이 "됐다" 를 상태 코드로만 알아야 해서다 —
 * 멱등 쓰기는 늘 <b>지금 상태</b>를 돌려준다(반응과 같은 모양).
 */
public record BookmarkStateResponse(boolean bookmarked) {
}
