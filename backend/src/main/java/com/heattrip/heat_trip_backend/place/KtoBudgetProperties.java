package com.heattrip.heat_trip_backend.place;

import lombok.Getter;
import lombok.Setter;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/**
 * KTO 호출 예산과 캐시 수명 — 이슈 #40 완료 조건 6.
 *
 * <h2>일 총량이 1,000 이 아니라 500 인 근거</h2>
 * <p>KTO 한도는 일 1,000콜이다. 그런데 <b>상대의 리셋 시각을 모른다</b> — KST 자정인지
 * UTC 자정인지 data.go.kr 콘솔에서 확인하지 못했다.
 *
 * <p>우리 날 경계는 KST 자정이다. 상대의 경계가 Δ 시간 어긋나면, 상대의 어떤 24시간 창도
 * <b>우리의 날 D 전부 + 인접한 날의 일부</b>를 담을 수 있고, 최악에는 두 날의 전량이 한
 * 창에 들어온다.
 *
 * <pre>
 *   안전 조건:  2 × (우리 일 총량) ≤ 1,000
 *   ⇒ 우리 일 총량 ≤ 500
 * </pre>
 *
 * <p><b>이것이 이 설계가 지불한 가장 큰 대가다.</b> 리셋 시각이 확인되면 800 까지 올릴 수
 * 있고, 그때 바꿔야 할 것은 이 프로퍼티 둘뿐이다 — 재배포로만 바꿀 수 있는 값이 아니다.
 *
 * <h2>300 / 50 / 150 인 근거</h2>
 * <table>
 *   <caption>일 배분</caption>
 *   <tr><th>풀</th><th>상한</th><th>무엇을 사는가</th></tr>
 *   <tr><td>{@code nearby}</td><td>300</td>
 *       <td>서울 전역이 <b>154셀</b>이라 하루에 다 데워도 51%. 사용자가 몇 명이든 같다 —
 *           상한을 만드는 것이 사람 수가 아니라 땅 넓이다({@link
 *           com.heattrip.heat_trip_backend.place.service.GridCell})</td></tr>
 *   <tr><td>{@code detail}</td><td>150</td>
 *       <td>1건이 2콜이므로 콜드 기준 하루 <b>75건</b>. TTL 30일이라 <b>전부</b> 캐시된
 *           상태의 갱신 수요는 2N/30 콜/일이고, N=2,250 이 손익분기다.
 *           <b>N 을 이제 안다 — 9,684곳이다</b>(실측 2026-09-04). 그 손익분기의 4.3배다.
 *           그래도 150 을 안 올린다: 상세는 <b>사용자가 연 장소만</b> 채워지므로 실제
 *           수요는 2N/30 이 아니라 2×(연 장소 수)/30 이다. 전부 캐시되는 날이 오면
 *           그때는 상한이 아니라 TTL 을 늘리는 것이 답이다</td></tr>
 *   <tr><td>{@code catalog}</td><td>50</td>
 *       <td>전국 한 벌이 <b>10콜</b>이다(9,684곳 ÷ numOfRows 1000, 실측 2026-09-04).
 *           하루 한 번 데우면 10콜이고, 데이터가 다섯 배로 늘어도 들어온다.
 *           예비 50 에서 가져왔다 — 아래 참조</td></tr>
 *   <tr><td>예비</td><td>0</td><td>{@code catalog} 가 가져갔다. 300+50+150 = 500</td></tr>
 * </table>
 *
 * <p><b>모르는 값을 가정으로 덮지 않았다.</b> 예상 DAU 도 전국 장소 수 N 도 모른다.
 * 위 상한은 그 둘 중 어느 것에도 의존하지 않는다 — 상한을 만드는 것은 DB 행 하나이고,
 * 그 행을 통과하지 않고 KTO 로 나가는 코드 경로가 없다.
 *
 * <h2>한도가 서비스별인지도 모른다</h2>
 * <p>{@code KorService2} 와 {@code KorPetTourService2} 는 활용신청이 서로 다른 API 인데,
 * 1,000콜을 나눠 쓰는지 각각 갖는지 확인하지 못했다. <b>나눠 쓰는 쪽(불리한 쪽)으로</b>
 * 가정했다. 별개라면 여유가 두 배다.
 */
@Component
@ConfigurationProperties(prefix = "app.kto.budget")
@Getter
@Setter
public class KtoBudgetProperties {

    /** {@code locationBasedList2} 의 하루 상한. 1건 = 1콜. */
    private int nearbyMaxCallsPerDay = 300;

    /**
     * {@code areaBasedList2} 의 하루 상한. <b>1페이지 = 1콜</b>. 이슈 #273.
     *
     * <p>전국이 9,684곳이고 {@code numOfRows} 가 1000 이라 한 벌이 <b>10콜</b>이다
     * (실측 2026-09-04). 하루 한 번 데우므로 정상 운영에서 쓰는 것은 10콜이다.
     *
     * <p>50 인 이유: 데이터가 지금의 다섯 배로 늘어도(48,000곳) 한 벌이 들어온다.
     * 그보다 크게 잡을 이유가 없다 — 이 풀이 태울 수 있는 최대가 곧 다른 풀에서
     * 빼앗을 수 있는 최대이기 때문이다.
     */
    private int catalogMaxCallsPerDay = 50;

    /** 상세의 하루 상한. <b>1건이 2콜</b>이므로 하루 75건이다. */
    private int detailMaxCallsPerDay = 150;

    /**
     * 인허가 API 의 하루 상한 — 이슈 #291. 1페이지(100건) = 1콜. 영업 중 동물병원·판매업이
     * 합쳐 1만 곳 안팎이라 한 벌이 100콜 남짓이고, 월 1회다. 상대 한도는 10,000 이다.
     */
    private int localdataMaxCallsPerDay = 500;

    /** 두루누비 코스 목록의 하루 상한 — 이슈 #291. 1페이지(100건) = 1콜, 상대 한도 1,000. */
    private int durunubiMaxCallsPerDay = 100;

    /**
     * ORS 왕복 경로의 하루 상한 — 이슈 #725. 시도 하나 = 1콜. 상대 한도 200(실측)에서 50 을 남긴다 —
     * 손으로 확인할 몫과 헤더가 말한 수가 틀렸을 때의 여유다.
     */
    private int orsLoopMaxCallsPerDay = 150;

    /**
     * 셀 스냅샷을 다시 받아 보려는 주기(시간).
     *
     * <p><b>만료가 아니다.</b> 이 시간이 지나도 예산이 없으면 옛 스냅샷을 <b>그대로 계속
     * 준다.</b> 만료를 두면 좌표를 훑는 요청이 며칠 이어졌을 때 셀이 전부 비고 지도가
     * 영구히 빈 화면이 된다 — 만료가 없으면 그 경로 자체가 없다.
     *
     * <p>24시간인 이유: 서울 154셀 × 1콜 = 154콜/일이라 {@code nearbyMaxCallsPerDay} 안에
     * 들어온다. 더 짧게 하면(12h) 308콜이 되어 상한을 넘고, 그때 깨지는 것은 한도가 아니라
     * 신선도다 — 게이트가 이긴다.
     */
    private int cellRefreshHours = 24;

    /**
     * 상세를 다시 받아 보려는 주기(일). 이것도 만료가 아니다.
     *
     * <p>30일인 이유: 장소의 개요와 반려동반 정보는 거의 안 바뀐다. 짧게 잡으면 갱신 수요가
     * {@code 2N/TTL} 로 늘어 상한에 먼저 부딪힌다.
     */
    private int detailRefreshDays = 30;

    /**
     * 없는 {@code contentId} 를 기억해 두는 기간(일).
     *
     * <p><b>짧게 잡으면 오히려 비싸다.</b> 무작위 id 공격이 캐시가 만료될 때마다 다시
     * 아웃바운드를 부르기 때문이다. 30일이면 그 경로가 사실상 닫힌다.
     */
    private int notFoundCacheDays = 30;

    /**
     * 한 셀이 연속으로 실패했을 때 다시 시도하기까지 기다리는 시간(분).
     *
     * <p>실패한 호출도 예산을 태운다. 백오프가 없으면 KTO 가 아픈 동안 예산이 순식간에
     * 사라지고, 회복된 뒤에 쓸 것이 남지 않는다.
     */
    private int failureBackoffMinutes = 10;

    /**
     * KTO 로 동시에 나가는 호출의 최대 수.
     *
     * <p>이 수만큼의 톰캣 스레드만 외부 소켓에 묶인다. 없으면 KTO 가 느려질 때
     * <b>요청 수만큼</b> 스레드가 묶여 서버 전체가 함께 멈춘다.
     */
    private int maxConcurrentUpstreamCalls = 6;
}
