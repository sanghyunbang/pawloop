package com.heattrip.heat_trip_backend.observability.logging;

import org.springframework.stereotype.Component;

import java.util.regex.Pattern;

@Component
public class SensitiveDataMasker {

    private static final Pattern BEARER = Pattern.compile("(?i)Bearer\\s+[A-Za-z0-9._\\-]+\\.?[A-Za-z0-9._\\-]*\\.?[A-Za-z0-9._\\-]*");
    private static final Pattern SECRET = Pattern.compile("(?i)(api[_-]?key|secret|token|password)\\s*[:=]\\s*[^\\s,]+");

    public String mask(String input) {
        if (input == null || input.isBlank()) {
            return input;
        }
        String masked = BEARER.matcher(input).replaceAll("Bearer ***");
        return SECRET.matcher(masked).replaceAll("$1=***");
    }
}
