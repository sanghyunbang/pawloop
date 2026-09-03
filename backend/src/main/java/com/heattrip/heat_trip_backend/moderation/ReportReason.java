package com.heattrip.heat_trip_backend.moderation;

import java.util.Locale;
import java.util.Optional;

/**
 * 신고 사유 — 계약의 {@code ReportReason}.
 *
 * <p><b>채팅과 같은 어휘다.</b> 값이 두 벌이 되면 앱이 분기를 두 번 짜고, 운영자가 세는
 * 숫자가 두 표에서 다른 뜻이 된다.
 */
public enum ReportReason {

    /** 광고 · 도배 */
    SPAM,
    /** 욕설 · 괴롭힘 */
    ABUSE,
    /** 성적인 내용 */
    SEXUAL,
    /** 사기 · 금전 요구 */
    FRAUD,
    /** 기타 */
    OTHER;

    /** DB 와 계약에 쓰는 문자열. 소문자인 것은 계약이 그렇게 선언했기 때문이다. */
    public String wireValue() {
        return name().toLowerCase(Locale.ROOT);
    }

    /**
     * 계약의 문자열을 값으로. 모르는 값이면 비어 있다.
     *
     * <p><b>모르는 값을 {@link #OTHER} 로 눕히지 않는다.</b> 그러면 앱의 오타가 조용히
     * 통과해서, 운영자가 세는 숫자가 소리 없이 틀어진다.
     */
    public static Optional<ReportReason> fromWire(String value) {
        if (value == null) {
            return Optional.empty();
        }
        String normalized = value.trim().toUpperCase(Locale.ROOT);
        for (ReportReason reason : values()) {
            if (reason.name().equals(normalized)) {
                return Optional.of(reason);
            }
        }
        return Optional.empty();
    }
}
