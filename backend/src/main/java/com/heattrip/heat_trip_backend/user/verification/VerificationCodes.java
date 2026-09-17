package com.heattrip.heat_trip_backend.user.verification;

import java.security.SecureRandom;
import java.util.Locale;

/**
 * 메일로 보내는 여섯 자리 — 이슈 #635.
 *
 * <p>가입 인증과 비밀번호 재설정이 같은 길이를 쓴다. 한쪽만 짧아지면 그쪽이 약한 문이 되고,
 * 공격자는 늘 약한 쪽으로 온다.
 *
 * <p>여섯 자리는 한 번에 100만분의 1이다. 그 값이 안전한 것은 <b>시도 횟수를 함께 막기
 * 때문</b>이다({@link VerificationAttempts}) — 횟수 제한이 없으면 자릿수를 늘려도 시간 문제다.
 */
public final class VerificationCodes {

    public static final int DIGITS = 6;

    private static final SecureRandom RANDOM = new SecureRandom();

    private VerificationCodes() {
    }

    /** 앞자리가 0 이어도 여섯 글자를 유지한다. */
    public static String newCode() {
        return String.format(Locale.ROOT, "%0" + DIGITS + "d",
                RANDOM.nextInt((int) Math.pow(10, DIGITS)));
    }
}
