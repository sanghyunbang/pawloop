package com.heattrip.heat_trip_backend.push.service;

import com.heattrip.heat_trip_backend.push.PushProperties;
import com.heattrip.heat_trip_backend.push.PushTime;
import com.heattrip.heat_trip_backend.push.entity.DeviceToken;
import com.heattrip.heat_trip_backend.push.repository.DeviceTokenRepository;
import lombok.extern.slf4j.Slf4j;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.Clock;
import java.time.LocalDateTime;
import java.util.Collection;
import java.util.List;

/**
 * 기기 토큰 원장의 쓰기 — 등록(upsert) · 폐기 · 탈퇴 삭제 (이슈 #83).
 *
 * <h2>등록은 upsert 다</h2>
 * <p>앱은 시작할 때마다, 로그인할 때마다, FCM 이 토큰을 바꿀 때마다 같은 경로를 부른다. 그래서
 * "있으면 갱신, 없으면 생성" 이고 응답에 새로 만들었는지 여부가 없다 — 앱이 알 필요가 없다.
 * 같은 기기에서 다른 계정으로 들어오면 토큰의 주인이 바뀐다 — 옛 계정의 알림이 새 사람의
 * 기기에 오면 안 되므로 그것이 맞는 답이다.
 *
 * <h2>같은 토큰이 동시에 두 번 들어오면</h2>
 * <p>둘 다 "없다" 고 보고 INSERT 하면 {@code UNIQUE(token)} 이 하나를 거절한다. 그 거절을 받아
 * <b>새 트랜잭션에서</b> 갱신 경로로 한 번 더 간다 — 거절당한 트랜잭션은 이미 롤백 대상이라
 * 그 안에서는 다시 쓸 수 없다. 방어는 인메모리 락이 아니라 DB 제약이다(#86 원칙 5).
 *
 * <p>트랜잭션을 {@link TransactionTemplate} 으로 직접 여는 이유: 같은 빈 안에서 부르는 메서드의
 * {@code @Transactional} 은 프록시를 지나지 않아 붙지 않는다({@code ChatMessageSender} javadoc 과
 * 같은 함정). 처음 짰을 때 정확히 그렇게 됐고 — 상한 초과분의 {@code revoked_at} 이 영영 안 찍혔다 —
 * {@code PushRegistrationIntegrationTest.activeTokensAreCapped} 가 그것을 잡았다.
 */
@Slf4j
@Service
public class DeviceTokenService {

    private final DeviceTokenRepository tokens;
    private final PushProperties properties;
    private final Clock clock;
    private final TransactionTemplate transaction;

    public DeviceTokenService(DeviceTokenRepository tokens, PushProperties properties, Clock clock,
                              PlatformTransactionManager transactionManager) {
        this.tokens = tokens;
        this.properties = properties;
        this.clock = clock;
        this.transaction = new TransactionTemplate(transactionManager);
    }

    /** 등록 또는 갱신. 사용자당 상한을 넘치면 가장 오래 안 보인 토큰부터 폐기한다. */
    public void register(long userId, String token, String platform) {
        try {
            transaction.executeWithoutResult(status -> upsert(userId, token, platform));
        } catch (DataIntegrityViolationException raced) {
            // 같은 토큰의 INSERT 둘이 겹쳤다 — 진 쪽은 새 트랜잭션에서 갱신으로 다시 간다.
            log.debug("기기 토큰 등록이 겹쳤다 — 갱신으로 다시 간다");
            transaction.executeWithoutResult(status -> upsert(userId, token, platform));
        }
    }

    private void upsert(long userId, String token, String platform) {
        LocalDateTime now = PushTime.nowUtc(clock);
        DeviceToken row = tokens.findByToken(token).orElseGet(() -> DeviceToken.builder().token(token).build());
        row.setUserId(userId);
        row.setPlatform(platform);
        row.setLastSeenAt(now);
        row.setRevokedAt(null);
        tokens.saveAndFlush(row);

        List<DeviceToken> active = tokens.findByUserIdAndRevokedAtIsNullOrderByLastSeenAtAscIdAsc(userId);
        int overflow = active.size() - properties.getMaxActiveTokensPerUser();
        for (int i = 0; i < overflow; i++) {
            active.get(i).setRevokedAt(now);
        }
        if (overflow > 0) {
            tokens.flush();
        }
    }

    /** 이 사용자들의 살아 있는 토큰 전부. 발송 대상이다. */
    @Transactional(readOnly = true)
    public List<DeviceToken> activeTokensOf(Collection<Long> userIds) {
        if (userIds.isEmpty()) {
            return List.of();
        }
        return tokens.findByUserIdInAndRevokedAtIsNull(userIds);
    }

    /** FCM 이 죽었다고 답한 토큰들을 폐기한다. 이미 폐기된 것은 그대로다. */
    @Transactional
    public int revokeTokens(Collection<String> deadTokens) {
        if (deadTokens.isEmpty()) {
            return 0;
        }
        return tokens.revokeTokens(deadTokens, PushTime.nowUtc(clock));
    }

    /** 로그아웃 — 전 기기. 멱등이다. */
    @Transactional
    public int revokeAllOf(long userId) {
        return tokens.revokeAllOf(userId, PushTime.nowUtc(clock));
    }

    /** 탈퇴 — 행을 지운다. */
    @Transactional
    public int deleteAllOf(long userId) {
        return tokens.deleteAllOf(userId);
    }
}
