package com.heattrip.heat_trip_backend.user;

import java.time.LocalDateTime;
import java.util.List;

/**
 * 필수 약관에 <b>한 번도 다 동의하지 않은</b> 계정을 찾는 자리 — 이슈 #660 완료 조건 4.
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
 * <h2>왜 시각을 함께 받나</h2>
 *
 * <p>"동의 안 한 계정 전부" 를 받아 여기서 시각을 거르면 <b>동의 안 한 사람 전부</b>가 매일 밤
 * 이 모듈로 건너온다. 방금 가입해 동의 화면을 보고 있는 사람까지. 답하는 쪽이 {@code users}
 * 엔티티를 볼 수 있으므로({@code consent} 는 {@code user :: entity} 를 연다) 한 문장으로 거른다.
 */
public interface UnconsentedAccounts {

    /**
     * {@code createdBeforeUtc} 보다 먼저 만들어졌고, 필수 약관 중 하나라도 <b>동의한 행이 한 줄도
     * 없는</b> 계정의 id — 오름차순.
     *
     * <p>{@code users.created_at} 은 UTC 를 담은 {@code LocalDateTime} 이다({@link UserTime}).
     * 그 컬럼이 비어 있는 행은 <b>대상이 아니다</b> — 언제 만들어졌는지 모르는 계정을 지우지 않는다.
     *
     * @param createdBeforeUtc 이 시각보다 먼저 만들어진 계정만. 담긴 값이 UTC 여야 한다
     */
    List<Long> idsCreatedBefore(LocalDateTime createdBeforeUtc);
}
