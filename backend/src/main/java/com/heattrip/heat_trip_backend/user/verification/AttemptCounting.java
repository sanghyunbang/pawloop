package com.heattrip.heat_trip_backend.user.verification;

import java.time.LocalDateTime;

/**
 * 메일로 보낸 <b>한 번 쓰는 코드</b>를 들고 있는 행 — 이슈 #635.
 *
 * <p>가입 인증({@code pending_signup})과 비밀번호 재설정({@code password_reset})이 같은
 * 모양이다: 해시된 여섯 자리, 만료 시각, 틀린 횟수. 그래서 <b>세는 일과 죽이는 일</b>을
 * {@link VerificationAttempts} 하나가 맡는다.
 *
 * <p>공통으로 뽑은 것은 그 둘뿐이다. 코드가 맞았을 때 무엇을 하는가 — 계정을 만드는가,
 * 비밀번호를 바꾸는가 — 는 서로 완전히 다른 일이라 각 서비스가 갖는다.
 */
public interface AttemptCounting {

    Long getId();

    String getCodeHash();

    LocalDateTime getExpiresAt();

    int getAttempts();

    void setAttempts(int attempts);

    default boolean isExpired(LocalDateTime now) {
        return getExpiresAt().isBefore(now);
    }
}
