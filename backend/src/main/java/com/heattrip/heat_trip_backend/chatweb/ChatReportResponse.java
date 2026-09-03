package com.heattrip.heat_trip_backend.chatweb;

import java.time.Instant;

/**
 * 신고 접수 응답 — 이슈 #82.
 *
 * <h2>이 record 에 필드가 둘뿐인 것이 안전장치다</h2>
 * <p>신고자 신원은 물론이고 <b>피신고자 id 도, 스냅샷 본문도 없다.</b> 문서로 "싣지 마세요"
 * 라고 적는 것과 <b>실을 수 없게 만드는 것</b>은 다르다 — 여기 필드가 없으면 어떤 코드도
 * 그것을 응답에 넣을 수 없다(#82 완료 조건 2).
 *
 * <p>신고에 성공한 쪽은 이미 누구를 왜 신고했는지 안다. 서버가 그것을 되돌려 줄 이유가 없다.
 *
 * @param reportId  접수 번호. 앱이 "접수됐습니다" 뒤에 붙일 수 있고 문의 시 좌표가 된다
 * @param createdAt 접수 시각. <b>{@link Instant} 다</b> — 2026-09-03 이전에는
 *                  {@code LocalDateTime.toString()} 이라 오프셋이 없었고, 그래서
 *                  "계약의 다른 시각 필드들과 같은 모양" 이라는 이 줄이 거짓이었다(#248)
 */
public record ChatReportResponse(long reportId, Instant createdAt) {
}
