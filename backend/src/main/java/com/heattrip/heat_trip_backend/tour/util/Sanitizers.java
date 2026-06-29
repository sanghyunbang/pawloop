package com.heattrip.heat_trip_backend.tour.util;

public final class Sanitizers {
    private Sanitizers() {}

    /** 공통 truncate */
    public static String truncate(String s, int maxLen) {
        if (s == null) return null;
        if (maxLen <= 0) return "";
        return (s.length() > maxLen) ? s.substring(0, maxLen) : s;
    }

    /** 전화번호: 허용문자만 유지 + 공백 정리 + 길이 자르기 */
    public static String cleanTel(String s, int maxLen) {
        if (s == null) return null;
        String cleaned = s
            // 숫자/일반 기호/구분자만 남김. 필요시 허용 문자 조정
            .replaceAll("[^0-9+()\\-\\s/.,~]", "")
            .replaceAll("\\s{2,}", " ")
            .trim();
        return truncate(cleaned, maxLen);
    }
}
