package com.heattrip.heat_trip_backend.observability.error;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;

public final class ErrorFingerprint {

    private ErrorFingerprint() {
    }

    public static String of(ErrorEvent event) {
        String raw = String.join("|",
                nullSafe(event.getExceptionClass()),
                nullSafe(event.getPath()),
                firstLine(event.getStackTraceSnippet()));
        return sha256(raw);
    }

    private static String firstLine(String s) {
        if (s == null) {
            return "";
        }
        int idx = s.indexOf('\n');
        return idx > 0 ? s.substring(0, idx) : s;
    }

    private static String nullSafe(String s) {
        return s == null ? "" : s;
    }

    private static String sha256(String input) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            return HexFormat.of().formatHex(digest.digest(input.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 unavailable", e);
        }
    }
}
