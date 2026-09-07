package com.heattrip.heat_trip_backend.care.dto;

import com.heattrip.heat_trip_backend.care.entity.CareType;

/**
 * 케어 기록 요청 — 계약({@code openapi.yaml})의 {@code CareLogInput} 이다. 이슈 #76.
 *
 * <h2>필드가 둘뿐이다 — 나머지는 서버가 정한다</h2>
 * <p>계약에는 예전에 {@code dogId}(필수)와 {@code occurredAt} 이 있었다. 이 커밋이 둘을
 * 걷어냈고 이유가 다르다.
 * <ul>
 *   <li><b>{@code dogId}</b> — <b>이 경로는 그룹 단위 기록이다.</b>
 *       {@code POST /api/groups/&#123;groupId&#125;/care-logs} 는 "가족이 오늘 무엇을 했나" 를
 *       적는 자리라, 대상 개체를 아직 요구하지 않는다. 필수로 두면 앱은 더미 id 를 지어내
 *       보내야 한다. 개체를 지목하는 경로(M4 의 개인 기록)가 열리는 날 함께 판단한다.
 *       (2026-09 이전에는 이 자리에 "{@code dog} 표가 없어서" 라고 적혀 있었는데,
 *        #145 가 그 표를 만들었다 — 자세한 것은 {@code CareLog} 클래스 javadoc.)</li>
 *   <li><b>{@code occurredAt}</b> — 이 값이 곧 "오늘 누가 했는지" 를 가르는 기준이다.
 *       클라이언트가 정할 수 있으면 오늘 기록을 어제로 밀어 이중 급여 경고를 지우거나,
 *       남의 화면에 없던 시각의 기록을 만들어 넣을 수 있다. 지난 일을 나중에 적는 화면은
 *       M4 이고, 그때 "얼마나 과거까지 허용하는가" 와 함께 연다.</li>
 * </ul>
 *
 * <p><b>{@code doneBy} 도 여기 없다.</b> 수행자는 토큰의 사용자다 — 본문으로 받으면
 * 남의 이름으로 기록을 남길 수 있고, 그러면 화면의 "아빠가 줬습니다" 를 믿을 수 없다.
 *
 * <p><b>위치도 여기 없다 (#340).</b> 배변·마킹은 산책 중에 눌리지만 <b>어디서</b> 눌렀는지는
 * 기기에만 남는다(A안 #235). 이 레코드에 좌표 필드를 더하지 않는 것이 그 약속의 자리다 —
 * {@code CareContractSpecTest} 가 계약의 {@code CareLogInput} 속성 집합을 이 레코드와 견준다.
 *
 * @param type {@code water|meal|walk|med|vet|poop|pee}. 다른 값이면 400 — {@link CareType#of} 가
 *             역직렬화에서 던진다
 * @param memo 선택. 500자까지. 넘으면 400 이다
 */
public record CareLogRequest(CareType type, String memo) {
}
