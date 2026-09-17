package com.heattrip.heat_trip_backend.consent.service;

import com.heattrip.heat_trip_backend.consent.ConsentKind;
import com.heattrip.heat_trip_backend.consent.ConsentTime;
import com.heattrip.heat_trip_backend.consent.dto.ConsentEntryRequest;
import com.heattrip.heat_trip_backend.consent.dto.ConsentResponse;
import com.heattrip.heat_trip_backend.consent.entity.UserConsent;
import com.heattrip.heat_trip_backend.consent.ConsentStatus;
import com.heattrip.heat_trip_backend.consent.repository.UserConsentRepository;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.EnumSet;
import java.util.Set;
import java.util.stream.Collectors;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;

/**
 * 동의를 적고 읽는다 — 이슈 #190.
 *
 * <h2>서버는 판정하지 않는다</h2>
 * <p>"필수 셋이 다 있는가", "지금 버전에 동의했는가" 는 앱이 정한다. 문서와 그 버전을 앱이
 * 들고 있기 때문이다. 서버가 하는 일은 둘뿐이다 — <b>받은 대로 적고, 문서별 마지막 행을
 * 돌려준다.</b> 그래서 {@code agreed = false} 도, 옛 버전에 대한 동의도 그대로 적는다.
 *
 * <h2>한 요청의 여러 항목은 같은 시각이다</h2>
 * <p>동의 화면에서 넷을 한 번에 누른다. 항목마다 시계를 다시 읽으면 같은 화면의 동의가
 * 밀리초 단위로 갈리고, "언제 동의했는가" 를 셀 때 그 차이가 뜻이 있는 것처럼 보인다.
 */
@Service
public class ConsentService implements ConsentStatus {

    private final UserConsentRepository consents;
    private final Clock clock;

    public ConsentService(UserConsentRepository consents, Clock clock) {
        this.consents = consents;
        this.clock = clock;
    }

    /** 문서별 마지막 행. 한 번도 안 적은 문서는 목록에 없다. */
    @Transactional(readOnly = true)
    public List<ConsentResponse> current(long userId) {
        return latestPerKind(userId);
    }

    /**
     * 필수 셋({@code TERMS}·{@code PRIVACY}·{@code LOCATION})에 <b>지금</b> 동의한 상태인가 — 이슈 #660.
     *
     * <p>이 모듈은 받은 사실을 적기만 한다는 원칙은 그대로다({@code ConsentKind} 의 주석). 이 메서드도
     * 막지 않는다 — <b>묻는 말에 답할 뿐</b>이고, 막는 것은 시큐리티 체인의
     * {@code ConsentRequiredFilter} 다. 기록과 강제를 한 클래스에 섞지 않는다.
     *
     * <p>{@link ConsentStatus} 를 구현하는 모양인 것은 모듈 경계 때문이다 — 필터가 이 클래스를
     * 직접 부르면 {@code security -> consent.service} 로 남의 모듈 <b>안쪽</b>을 부르는 것이 된다.
     * 그래서 필요한 한 마디만 모듈 표면에 내놓고, 밖은 그것만 안다.
     *
     * <p>철회를 세는 방식이 요점이다. 동의는 이력이라 같은 문서에 여러 행이 쌓이고, 마지막 행이
     * {@code agreed = false} 면 철회한 것이다({@code latestPerKind} 가 최신 한 줄만 남긴다).
     * 그래서 "행이 있는가" 가 아니라 <b>"마지막 행이 동의인가"</b> 를 본다.
     *
     * <p>버전은 보지 않는다. 약관이 바뀌어 다시 받아야 하는지는 앱이 정한다(ADR-0020) — 여기서
     * 버전까지 따지면 서버가 문서 버전을 알아야 하고, 그건 그 ADR 이 일부러 피한 것이다.
     */
    @Override
    public boolean hasAgreedToRequired(long userId) {
        Set<ConsentKind> agreed = latestPerKind(userId).stream()
                .filter(ConsentResponse::agreed)
                .map(ConsentResponse::kind)
                .collect(Collectors.toCollection(() -> EnumSet.noneOf(ConsentKind.class)));
        return agreed.containsAll(REQUIRED);
    }

    /** 필수 셋. {@code MARKETING} 은 선택이라 없다. */
    public static final Set<ConsentKind> REQUIRED =
            Collections.unmodifiableSet(EnumSet.of(ConsentKind.TERMS, ConsentKind.PRIVACY, ConsentKind.LOCATION));

    /**
     * 받은 항목을 <b>전부 새 행으로</b> 적고 지금 상태를 돌려준다.
     *
     * <p>같은 문서가 한 요청에 두 번 오면 둘 다 적는다 — 뒤의 것이 마지막 행이 된다.
     * 거르지 않는 이유: 거르는 규칙을 두는 순간 "서버가 받았다고 한 것과 적은 것" 이
     * 달라지는 갈래가 생긴다.
     */
    @Transactional
    public List<ConsentResponse> record(long userId, List<ConsentEntryRequest> entries) {
        LocalDateTime now = ConsentTime.nowUtc(clock);
        List<UserConsent> rows = new ArrayList<>(entries.size());
        for (ConsentEntryRequest entry : entries) {
            rows.add(UserConsent.builder()
                    .userId(userId)
                    .kind(entry.kind().name())
                    .version(entry.version())
                    .agreed(entry.agreed())
                    .createdAt(now)
                    .build());
        }
        consents.saveAll(rows);
        return latestPerKind(userId);
    }

    private List<ConsentResponse> latestPerKind(long userId) {
        Map<ConsentKind, ConsentResponse> latest = new EnumMap<>(ConsentKind.class);
        for (UserConsent row : consents.findByUserIdOrderByIdDesc(userId)) {
            // 최신이 앞이라 처음 본 문서가 마지막 행이다.
            latest.putIfAbsent(row.kind(), ConsentResponse.of(row));
        }
        return List.copyOf(latest.values());
    }
}
