package com.heattrip.heat_trip_backend.moderation;

import java.time.Instant;

/**
 * 접수증 — 신고의 응답이 되는 전부다.
 *
 * <p><b>피신고자 id 도, 대상 정보도 안 돌려준다.</b> 신고자는 익명이고 피신고자에게는 아무
 * 알림도 가지 않는다 — 채팅 신고가 정한 규약이고 여기서도 같다. 응답에 무엇이 더 실리면
 * 그것으로 남의 상태를 물어볼 수 있게 된다.
 *
 * <p>{@code createdAt} 이 {@code Instant} 인 것은 오프셋 때문이다 — 계약이
 * {@code format: date-time} 이라고 선언했고 그건 RFC3339 오프셋이 있어야 성립한다(#209).
 */
public record ReportReceipt(long reportId, Instant createdAt) {
}
