package com.heattrip.heat_trip_backend.user;

import java.util.Collection;
import java.util.Set;

/**
 * 이 계정들 중 필수 약관에 <b>한 번도 다 동의하지 않은</b> 것을 가려내는 자리 — 이슈 #660 완료 조건 4.
 * <b>{@code user} 가 묻고 {@code consent} 가 답한다.</b>
 *
 * <h2>왜 인터페이스인가 — 방향이 뒤집혀 있다</h2>
 *
 * <p>계정을 지우는 일({@code UserService.deleteMe})은 이 모듈의 것이고, 누가 동의했는지는
 * {@code consent} 모듈만 안다. 그런데 이 모듈은 {@code allowedDependencies = {}} 라 아무 모듈도
 * 못 부른다 — {@code consent.ConsentStatus} 조차 못 부른다. 그래서 필요한 쪽이 자리를 선언하고
 * 아는 쪽이 구현한다. {@code service.AccessTokenIssuer}(#107, {@code OAuth} 가 구현)와
 * {@code security.AuthenticatedUserIds}(#660, {@code OAuth} 가 구현)가 같은 모양이다.
 *
 * <p>반대로 {@code consent} 가 계정을 지우게 하면 "계정 삭제" 를 루트에 내놓아야 하고, 그러면
 * 아무 모듈이나 계정을 지울 수 있게 된다. 읽기 한 마디를 여는 쪽이 싸다 — {@link KnownUsers} 와
 * {@link WithdrawnUsers} 가 읽기만 여는 것과 같은 판단이다.
 *
 * <h2>"지금 동의 상태" 가 아니라 "한 번이라도 동의했는가" 다</h2>
 *
 * <p>{@code consent.ConsentStatus#hasAgreedToRequired} 는 <b>지금</b>을 본다 — 철회하면
 * {@code false} 다. 여기는 다르다. 철회는 기록이지 이탈이 아니고(ADR-0020), 철회한 사람의 처지는
 * {@code security.ConsentRequiredFilter}(403)가 이미 정한다. 철회를 "동의 없음" 으로 세면
 * <b>1년 된 계정이 철회한 다음 날 새벽에 사라진다</b>. 이 자리가 겨냥하는 것은 동의 화면에서
 * 앱을 지운 사람 — 아무 동의도 받지 않은 개인정보를 오래 들고 있지 않기 위한 것이다.
 *
 * <h2>왜 id 목록으로 묻나 — 시각은 넘기지 않는다</h2>
 *
 * <p>"유예가 지난 계정" 은 {@code users.created_at} 의 이야기라 이 모듈이 자기 표에서 고른다.
 * 그 시각을 넘겨 {@code consent} 가 {@code User} 를 JPQL 로 묻게 하면 한 문장으로 끝나지만, 그건
 * {@code consent} 가 남의 표에 묶이는 것이다 — {@code CrossModuleQueryJoinsTest} 가 그 쿼리를 세고
 * 있고, 지금 그 기준선에는 원자성 때문에 어쩔 수 없는 {@code walk → dog} 하나뿐이다. 여기는
 * 야간 배치라 그럴 이유가 없다. 대신 {@code user} 가 id 를 한 장씩({@code UnconsentedAccountSweeper}
 * 의 키셋 페이지) 넘기고, 답하는 쪽은 {@code user_consent} 만 본다.
 */
public interface UnconsentedAccounts {

    /**
     * {@code userIds} 중 필수 약관 하나라도 <b>동의한 행이 한 줄도 없는</b> 계정 — id 오름차순.
     *
     * @param userIds 비면 빈 집합이고 <b>쿼리를 보내지 않는다</b>
     */
    Set<Long> among(Collection<Long> userIds);
}
