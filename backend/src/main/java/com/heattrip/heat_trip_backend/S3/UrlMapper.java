package com.heattrip.heat_trip_backend.S3;

/** key ↔ CloudFront URL 변환 유틸 */
public final class UrlMapper {
    private UrlMapper() {}

    public static String cfUrl(String domain, String key) {
        String base = domain.endsWith("/") ? domain.substring(0, domain.length()-1) : domain;
        return base + "/" + key;
    }

    public static String keyFromUrl(String url) {
        return url.replaceFirst("^https?://[^/]+/", "");
    }
}
