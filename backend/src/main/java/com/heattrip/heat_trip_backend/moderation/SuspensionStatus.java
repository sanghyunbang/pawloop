package com.heattrip.heat_trip_backend.moderation;

import java.time.Instant;
import java.util.Optional;

/**
 * 이 사람이 지금 정지 중인가 — 이슈 #718 셋째 조각.
 *
 * <h2>판정</h2>
 * <p>그 사람의 <b>마지막 정지·해제 줄</b>({@code moderation_action} 의 {@code suspend} · {@code lift})로 정한다.
 * 마지막이 정지이고, 끝나는 시각이 없거나(무기한) 아직 오지 않았으면 정지 중이다. 기한이 지나면 해제 줄이 없어도
 * 저절로 풀린다 — 풀어 주는 작업을 따로 돌리지 않는다.
 *
 * <h2>막는 자리는 여기가 아니다</h2>
 * <p>이 모듈은 판정만 한다. 요청을 막는 것은 {@code security.AccountSuspensionFilter} 다 — 동의가
 * {@code consent.ConsentStatus} 와 {@code ConsentRequiredFilter} 로 나뉜 것과 같은 모양이다.
 */
public interface SuspensionStatus {

    /** 지금 정지 중이면 그 정지. 정지된 적이 없거나, 풀렸거나, 기한이 지났으면 빈 값. */
    Optional<Suspension> currentSuspensionOf(long userId);

    /**
     * 지금 걸려 있는 정지.
     *
     * @param actionId 그 정지 줄의 id
     * @param since    정지한 시각(UTC)
     * @param endsAt   풀리는 시각(UTC). 무기한이면 {@code null}
     */
    record Suspension(long actionId, Instant since, Instant endsAt) {
    }
}
