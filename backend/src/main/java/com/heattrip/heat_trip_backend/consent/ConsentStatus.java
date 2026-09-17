package com.heattrip.heat_trip_backend.consent;

/**
 * 이 모듈이 밖으로 내주는 한 마디 — "이 사람이 필수 약관에 동의했는가". 이슈 #660.
 *
 * <h2>왜 인터페이스를 따로 두나</h2>
 *
 * <p>답을 가진 것은 {@code consent.service.ConsentService} 인데, 그건 이 모듈의 <b>안쪽</b>이다.
 * 밖에서 그것을 직접 부르면 모듈 경계 위반이다({@code ModularityBaselineTest}). 그래서 필요한
 * 한 마디만 모듈 패키지 바로 아래에 내놓는다 — #104 · #105 · #120 이 다른 모듈에서 한 것과 같다.
 *
 * <p>지금 부르는 곳은 {@code security.ConsentRequiredFilter} 하나다. 그쪽이 막고, 이쪽은 답한다.
 * <b>기록 모듈은 판정하지 않는다</b>는 원칙({@code ConsentKind} 의 주석)이 그래서 그대로 산다 —
 * "동의했는가" 에 답하는 것과 "그러니 막는다" 는 다른 일이다.
 *
 * <h2>무엇이 필수인지는 이쪽이 안다</h2>
 *
 * <p>필수 셋의 목록을 밖으로 내놓지 않는다. 내놓으면 부르는 쪽마다 그 목록을 해석해야 하고,
 * 문서가 하나 늘 때 고칠 자리가 여러 곳이 된다. 밖은 <b>예/아니오</b>만 받는다.
 */
public interface ConsentStatus {

    /**
     * {@code userId} 가 <b>지금</b> 필수 약관 전부에 동의한 상태인가.
     *
     * <p>"동의한 적이 있는가" 가 아니다. 철회하면 {@code false} 로 돌아온다.
     */
    boolean hasAgreedToRequired(long userId);
}
