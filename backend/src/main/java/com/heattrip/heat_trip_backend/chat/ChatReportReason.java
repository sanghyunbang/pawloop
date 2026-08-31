package com.heattrip.heat_trip_backend.chat;

import java.util.Locale;
import java.util.Optional;

/**
 * 신고 사유의 닫힌 목록 — 이슈 #82. 어휘의 출처는 계약이다
 * ({@code docs/04-api/openapi.yaml} 의 신고 오퍼레이션).
 *
 * <h2>왜 자유 서술이 아닌가</h2>
 * <p>처음에는 자유 서술 한 칸으로 만들었다가 되돌렸다. <b>계약이 이미 어휘를 정해 뒀는데</b>
 * 서버가 그것을 무시하면, 앱이 무엇을 보내야 하는지가 계약이 아니라 서버 구현에서 정해진다.
 *
 * <p>분류가 있으면 운영자가 <b>세어서 볼 수 있다.</b> 자유 서술만 있으면 같은 종류의 신고가
 * 열 가지 표현으로 흩어져서, "이 방에 성적 내용 신고가 몇 건인가" 를 물을 수 없다.
 *
 * <p>그래서 둘 다 받는다 — 분류({@code reason})는 <b>필수</b>이고 사람이 덧붙이는 말
 * ({@code memo})은 선택이다.
 *
 * <h2>이 목록을 늘릴 때</h2>
 * <p>계약과 앱의 신고 화면을 함께 고쳐야 한다. 서버만 늘리면 앱이 못 보내는 값이 생기고,
 * 앱만 늘리면 서버가 400 을 낸다.
 *
 * <p>저장은 {@link #wireValue()} 문자열이다. {@code ordinal()} 을 저장하면 목록 가운데에
 * 하나를 끼우는 순간 <b>이미 저장된 신고의 뜻이 바뀐다.</b>
 */
public enum ChatReportReason {

    /** 광고·도배. */
    SPAM,

    /** 욕설·괴롭힘. */
    ABUSE,

    /** 성적인 내용. */
    SEXUAL,

    /** 사기·금전 요구. */
    FRAUD,

    /** 위 넷에 안 맞는 것. {@code memo} 가 사실상 필수가 되는 자리다. */
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
    public static Optional<ChatReportReason> fromWire(String value) {
        if (value == null) {
            return Optional.empty();
        }
        String normalized = value.trim().toUpperCase(Locale.ROOT);
        for (ChatReportReason reason : values()) {
            if (reason.name().equals(normalized)) {
                return Optional.of(reason);
            }
        }
        return Optional.empty();
    }
}
