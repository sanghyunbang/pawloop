package com.heattrip.heat_trip_backend.place.service;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.List;

/**
 * 카탈로그 한 벌들을 <b>파싱 없이</b> 하나의 JSON 배열로 잇는다 — 이슈 #291.
 *
 * <p>각 한 벌은 {@code [ ... ]} 문자열이다. 바깥 대괄호를 벗겨 콤마로 잇고 다시 감싼다.
 * 2.8MB 짜리를 객체로 만들었다가 다시 쓰지 않는 것이 카탈로그 경로의 원칙이고
 * ({@code PlaceCatalog} javadoc), 이어 붙이는 데도 그 원칙이 그대로다.
 */
final class CatalogPayloads {

    /** ETag 길이 — {@code CatalogSnapshotStore.etagOf} 와 같다. */
    private static final int ETAG_HEX_LENGTH = 32;

    private CatalogPayloads() {
    }

    /** 빈 배열({@code []})은 건너뛴다. 전부 비면 {@code []} 다. */
    static String concat(List<String> arrays) {
        StringBuilder sb = new StringBuilder();
        sb.append('[');
        boolean first = true;
        for (String array : arrays) {
            String inner = stripBrackets(array);
            if (inner.isEmpty()) {
                continue;
            }
            if (!first) {
                sb.append(',');
            }
            sb.append(inner);
            first = false;
        }
        return sb.append(']').toString();
    }

    /** 한 벌들의 ETag 를 다시 해시한다. 어느 하나가 바뀌면 값이 바뀐다. */
    static String combinedEtag(List<String> etags) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(String.join("|", etags).getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest).substring(0, ETAG_HEX_LENGTH);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 을 못 찾았다.", e);
        }
    }

    private static String stripBrackets(String array) {
        if (array == null) {
            return "";
        }
        String s = array.strip();
        if (s.length() < 2 || s.charAt(0) != '[' || s.charAt(s.length() - 1) != ']') {
            throw new IllegalArgumentException("카탈로그 한 벌이 JSON 배열이 아니다.");
        }
        return s.substring(1, s.length() - 1).strip();
    }
}
