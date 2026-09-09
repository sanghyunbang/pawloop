package com.heattrip.heat_trip_backend.schedule.dto;

import com.heattrip.heat_trip_backend.error.GlobalExceptionHandler.ErrorResponse.ErrorBody;

/**
 * 편집 충돌(409)의 본문 — 이슈 #418.
 *
 * <h2>봉투를 깨지 않는다</h2>
 * <p>앱은 오류를 {@code error.code} 로 분기한다({@code GlobalExceptionHandler.ErrorResponse}
 * javadoc). 그래서 이 응답도 {@code error} 를 <b>그대로</b> 들고, 최신 값은 그 <b>옆에</b>
 * 붙인다. 봉투 안으로 밀어 넣으면 오류 스키마가 엔드포인트마다 달라지고, 최상위로 펼치면
 * 앱의 공통 오류 처리가 이 응답만 못 읽는다.
 *
 * @param error   평소와 같은 오류 봉투. {@code code} 는 {@code CONFLICT} 다
 * @param current <b>지금 서버에 있는 값</b>. 화면이 다시 묻지 않고 "○○님이 방금 고쳤어요" 를
 *                그 자리에서 그릴 수 있게 한다 — 다시 물으면 그 사이에 또 바뀔 수 있다
 */
public record ScheduleConflictResponse(ErrorBody error, ScheduleResponse current) {
}
