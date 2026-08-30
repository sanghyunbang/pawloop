package com.heattrip.heat_trip_backend.care.dto;

import com.heattrip.heat_trip_backend.care.entity.CareType;

/**
 * 케어 기록 요청 — 계약({@code openapi.yaml})의 {@code CareLogInput} 이다. 이슈 #76.
 *
 * <h2>필드가 둘뿐이다 — 나머지는 서버가 정한다</h2>
 * <p>계약에는 예전에 {@code dogId}(필수)와 {@code occurredAt} 이 있었다. 이 커밋이 둘을
 * 걷어냈고 이유가 다르다.
 * <ul>
 *   <li><b>{@code dogId}</b> — 확인할 표가 없다. {@code dog} 표가 정본 스키마에 없어서
 *       (자세한 것은 {@code CareLog} javadoc) 클라이언트가 보낸 숫자를 검증할 방법이
 *       없고, 검증 못 하는 외래 id 를 저장하면 <b>아무도 해석할 수 없는 값</b>이 남는다.
 *       필수 필드로 두면 앱은 더미 id 를 지어내 보내야 한다.</li>
 *   <li><b>{@code occurredAt}</b> — 이 값이 곧 "오늘 누가 했는지" 를 가르는 기준이다.
 *       클라이언트가 정할 수 있으면 오늘 기록을 어제로 밀어 이중 급여 경고를 지우거나,
 *       남의 화면에 없던 시각의 기록을 만들어 넣을 수 있다. 지난 일을 나중에 적는 화면은
 *       M4 이고, 그때 "얼마나 과거까지 허용하는가" 와 함께 연다.</li>
 * </ul>
 *
 * <p><b>{@code doneBy} 도 여기 없다.</b> 수행자는 토큰의 사용자다 — 본문으로 받으면
 * 남의 이름으로 기록을 남길 수 있고, 그러면 화면의 "아빠가 줬습니다" 를 믿을 수 없다.
 *
 * @param type {@code water|meal|walk|med|vet}. 다른 값이면 400 — {@link CareType#of} 가
 *             역직렬화에서 던진다
 * @param memo 선택. 500자까지. 넘으면 400 이다
 */
public record CareLogRequest(CareType type, String memo) {
}
