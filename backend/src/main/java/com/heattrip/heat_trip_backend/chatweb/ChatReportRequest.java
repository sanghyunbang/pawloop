package com.heattrip.heat_trip_backend.chatweb;

import java.util.List;

/**
 * 신고 요청 본문 — 이슈 #82.
 *
 * <p><b>{@code roomSeqs} 로 받는 이유</b>: 앱이 들고 있는 좌표가 그것이다. 메시지 목록도
 * 폴링 커서도 전부 {@code room_seq} 라, 신고만 {@code id} 를 요구하면 앱이 좌표 두 벌을
 * 들고 다녀야 한다({@code ChatMessage} javadoc).
 *
 * <p>검증은 여기 애너테이션이 아니라 {@code ChatReportService} 가 한다. 개수·발신자 일치·
 * 자기 신고 셋이 <b>서로 다른 코드</b>로 갈려야 앱이 다른 화면을 보여줄 수 있는데
 * ({@code ChatErrorCode}), {@code @Size} 로 막으면 전부 같은 검증 실패로 뭉친다.
 *
 * @param roomSeqs 신고할 메시지의 방 안 번호. 하나 이상 세 개 이하
 * @param reason   분류. 계약이 정한 닫힌 목록이고 <b>필수</b>다 — {@code ChatReportReason}
 * @param memo     덧붙이는 말. 비워도 된다. 500자를 넘기면 잘린다
 */
public record ChatReportRequest(List<Long> roomSeqs, String reason, String memo) {
}
