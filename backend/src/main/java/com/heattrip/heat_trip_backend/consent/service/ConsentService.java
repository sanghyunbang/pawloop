package com.heattrip.heat_trip_backend.consent.service;

import com.heattrip.heat_trip_backend.consent.ConsentKind;
import com.heattrip.heat_trip_backend.consent.ConsentTime;
import com.heattrip.heat_trip_backend.consent.dto.ConsentEntryRequest;
import com.heattrip.heat_trip_backend.consent.dto.ConsentResponse;
import com.heattrip.heat_trip_backend.consent.entity.UserConsent;
import com.heattrip.heat_trip_backend.consent.repository.UserConsentRepository;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDateTime;
import java.util.ArrayList;
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
public class ConsentService {

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
