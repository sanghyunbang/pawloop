package com.heattrip.heat_trip_backend.care;

import com.heattrip.heat_trip_backend.care.entity.CareType;
import com.heattrip.heat_trip_backend.care.service.CareService;
import com.heattrip.heat_trip_backend.user.entity.User;

import org.springframework.stereotype.Component;

/**
 * "다른 기능이 한 일을 케어 기록으로 남긴다" — <b>{@code care} 모듈의 공개 표면이다.</b>
 * 이슈 #420.
 *
 * <h2>왜 이 타입이 있어야 하는가</h2>
 * <p>일정표(#418·#419)에서 "토요일 보리 병원" 을 <b>완료</b>로 바꾸면, 그 사실은 오늘의 케어
 * 칸에도 있어야 한다. 없으면 사람이 <b>같은 일을 두 곳에 두 번 적는다</b> — 일정에서 체크하고,
 * 케어 칸에서 병원 버튼을 또 누른다. 그러면 "오늘 병원 두 번" 이 기록에 남는다.
 *
 * <p>그렇다고 {@code schedule} 이 {@code care.service.CareService} 를 직접 부르면 안 된다 —
 * 규약이 이렇게 적어 뒀다({@code docs/02-architecture/backend-implementation-guide.md} §2.3).
 * {@code user} 가 {@link com.heattrip.heat_trip_backend.user.KnownUsers} 를 내준 것과 같은
 * 자리다.
 *
 * <h2>종류를 문자열로 받는다</h2>
 * <p>{@link CareType} 이 아니라 {@code String} 이다. 그 타입은 {@code care.entity} 라 하위
 * 패키지이고, 부르는 쪽이 그것을 들면 <b>모듈 경계를 넘는다.</b> 대신 두 도메인이 이미
 * 공유하는 것을 쓴다 — {@code wire} 값이다. {@code schedule.kind} 의 {@code walk}·{@code vet}·
 * {@code med} 와 {@code care_log.type} 의 그것이 <b>글자까지 같은 문자열</b>이고, DB 의
 * {@code CHECK} 도 그 값으로 적혀 있다.
 *
 * <p>모르는 값이면 <b>기록하지 않는다</b>. 던지지 않는 이유는, 이 경로에서 케어 기록은
 * <b>곁다리</b>이기 때문이다 — 그것 때문에 일정 완료 자체가 실패하면 사용자는 자기가 한 일을
 * 못 적는다.
 */
@Component
public class CareLogging {

    private final CareService care;

    public CareLogging(CareService care) {
        this.care = care;
    }

    /**
     * 이 그룹에 케어 기록 한 줄을 남긴다.
     *
     * @param careTypeWire {@code water|meal|walk|med|vet|poop|pee}. 그 밖이면 <b>기록하지
     *                     않고 빈 값</b>을 준다 — 부르는 쪽의 어휘가 더 넓을 수 있다
     *                     (일정의 {@code groom}·{@code bath}·{@code food} 는 케어가 아니다)
     * @param actor        <b>실제로 누른 사람</b>이다. 담당자가 아니다 —
     *                     {@code care_log.done_by} 가 이미 그 규칙이고, 그래야 화면의
     *                     "아빠가 줬습니다" 를 믿을 수 있다
     * @param dogId        어느 아이에게 한 일인가 — 일정의 아이(#743). 없으면 {@code null}
     *                     (가족 공통). 그 집의 아이가 아니면 403 이다 — 카드에서 누를 때와
     *                     같은 확인이다. 안 붙이면 뭉치 병원이 "아이 안 정함" 으로 간다
     * @return 남긴 기록의 id. 부르는 쪽이 그것을 들고 있다가 되돌릴 때 쓴다
     * @throws org.springframework.web.server.ResponseStatusException 403 — 그 그룹의 방
     *         멤버가 아니면. 부르는 쪽이 이미 확인했더라도 여기서 한 번 더 본다
     */
    public java.util.Optional<Long> recordFor(long groupId, String careTypeWire, User actor, Long dogId) {
        CareType type;
        try {
            type = CareType.of(careTypeWire);
        } catch (IllegalArgumentException notACareType) {
            return java.util.Optional.empty();
        }
        return java.util.Optional.of(care.recordLinked(groupId, type, actor, dogId).id());
    }

    /**
     * 다른 기능이 남긴 기록을 <b>거둔다</b>.
     *
     * <p>{@code DELETE /api/groups/{id}/care-logs/{id}} 와 달리 <b>본인 기록만</b>이라는
     * 규칙을 안 본다. 이유는 이 경로가 사람이 케어 칸에서 지우는 것이 아니라, <b>그 일이
     * 일어나지 않았다고 되돌리는 것</b>이기 때문이다 — 아빠가 완료로 바꿔 생긴 줄을 엄마가
     * 되돌릴 수 있어야 한다. 되돌릴 권한은 그 일정에 대한 권한이고, 그것은 부르는 쪽이
     * 확인한다.
     *
     * <p>그 id 의 기록이 이미 없으면 <b>조용히 지나간다.</b> 사람이 케어 칸에서 먼저 지웠을
     * 수 있고, 그때 일정을 되돌리는 일이 실패하면 사용자는 이유를 알 수 없다.
     */
    public void withdraw(long groupId, long careLogId, long actorUserId) {
        care.withdrawLinkedLog(groupId, careLogId, actorUserId);
    }
}
