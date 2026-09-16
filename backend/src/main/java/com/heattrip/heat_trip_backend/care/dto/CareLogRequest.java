package com.heattrip.heat_trip_backend.care.dto;

import com.heattrip.heat_trip_backend.care.entity.CareType;

/**
 * 케어 기록 요청 — 계약({@code openapi.yaml})의 {@code CareLogInput} 이다. 이슈 #76.
 *
 * <h2>필드가 둘뿐이다 — 나머지는 서버가 정한다</h2>
 * <p>계약에는 예전에 {@code dogId}(필수)와 {@code occurredAt} 이 있었다. 이 커밋이 둘을
 * 걷어냈고 이유가 다르다.
 * <ul>
 *   <li><b>{@code occurredAt}</b> 이 여기 없는 이유는 아래에.</li>
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
 * <h2>{@code dogId} 는 <b>선택</b>이다 (#563)</h2>
 *
 * <p>2026-09-15 부터 받는다. 이 앱의 목적이 업무 분담과 누락 방지라서(#76), "해당 동물을
 * 누르면 누가 산책시켰고 누가 물 줬는지" 가 보여야 하는데 그러려면 기록에 아이가 붙어야 한다.
 *
 * <p><b>필수가 아닌 이유는 둘이다.</b> (1) 아이를 한 마리도 등록 안 한 집도 케어를 기록한다 —
 * 필수로 두면 그 집은 아무것도 못 적는다. (2) 이미 나가 있는 앱이 이 필드를 모르고, 그 앱의
 * 기록이 400 이 되면 안 된다 — <b>하위 호환은 서버가 지는 짐</b>이다({@code WalkRequest.dogIds}
 * 와 같은 판단).
 *
 * <p>보낸 값은 <b>그 집 아이여야</b> 한다. 아니면 400 이다({@code DogOwnership.requireInFamilyEntity}) —
 * 누구 것인지는 안 따진다. 엄마가 등록한 보리에게 아빠가 물을 주는 것이 정상이다.
 *
 * @param type {@code water|meal|walk|med|vet|poop|pee}. 다른 값이면 400 — {@link CareType#of} 가
 *             역직렬화에서 던진다
 * @param memo 선택. 500자까지. 넘으면 400 이다
 * @param dogId 선택. 우리 집 아이가 아니면 400
 *
 * <h2>{@code type} 과 {@code careItemId} 는 <b>정확히 하나</b>다 (#560)</h2>
 *
 * <p>둘 다 없으면 400 이다 — 어느 칸의 기록도 아닌 행은 화면에 안 뜨고, 안 뜨니 지울 수도
 * 없다. 둘 다 보내도 400 이다: 서로 다른 것을 가리키면 어느 쪽을 믿을지 정해야 하고, 그
 * 규칙은 적는 순간 둘 중 하나가 조용히 버려지는 자리가 된다.
 *
 * <p><b>{@code type} 만 보내는 길은 그대로 남는다.</b> 산책 트래킹이 {@code type='walk'} 로,
 * 일정 완료가 {@code CareService.recordLinked} 로 남기는 경로가 그렇다 — 이미 나가 있는 앱도
 * 이 필드를 모른 채 계속 기록한다. <b>하위 호환은 서버가 지는 짐</b>이다.
 *
 * @param careItemId 선택. 그 집 항목이 아니면 404. 기본 일곱을 가리키면 서버가 그 항목의
 *                   종류를 {@code type} 에 함께 적는다 — 그래야 옛 기록과 같은 축으로 세어지고
 *                   산책 화면의 {@code type='walk'} 조회도 그대로 돈다
 */
public record CareLogRequest(CareType type, String memo, Long dogId, Long careItemId) {
}
