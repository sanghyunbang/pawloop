package com.heattrip.heat_trip_backend.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.config.PublicSecurityProperties;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

@Component
@RequiredArgsConstructor
public class ApiRateLimitFilter extends OncePerRequestFilter {

    private record CounterWindow(long startedAtEpochSecond, int count) {}
    private record Rule(String bucket, int limit) {}

    private final PublicSecurityProperties props;
    private final ObjectMapper objectMapper;
    private final Map<String, CounterWindow> counters = new ConcurrentHashMap<>();

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {
        var rule = resolveRule(request);
        if (!props.getRateLimit().isEnabled() || rule == null || rule.limit() <= 0) {
            filterChain.doFilter(request, response);
            return;
        }

        long now = Instant.now().getEpochSecond();
        long windowSeconds = Math.max(1, props.getRateLimit().getWindowSeconds());
        long currentWindow = now / windowSeconds;
        String key = resolveClientIp(request) + "|" + rule.bucket();

        CounterWindow result = counters.compute(key, (k, current) -> {
            if (current == null || current.startedAtEpochSecond() != currentWindow) {
                return new CounterWindow(currentWindow, 1);
            }
            return new CounterWindow(current.startedAtEpochSecond(), current.count() + 1);
        });

        if (result != null && result.count() > rule.limit()) {
            writeTooManyRequests(response, rule, windowSeconds);
            return;
        }

        cleanupStaleEntries(currentWindow);
        filterChain.doFilter(request, response);
    }

    private Rule resolveRule(HttpServletRequest request) {
        String method = request.getMethod();
        String path = request.getRequestURI();
        var rateLimit = props.getRateLimit();

        if ("POST".equals(method) && "/auth/login".equals(path)) {
            return new Rule("login", rateLimit.getLoginMaxRequests());
        }
        if (path.startsWith("/api/curation/")) {
            return new Rule("curation", rateLimit.getCurationMaxRequests());
        }
        if ("GET".equals(method) && "/api/explore/places/search".equals(path)) {
            return new Rule("search", rateLimit.getSearchMaxRequests());
        }
        if ("POST".equals(method) && "/feedback".equals(path)) {
            return new Rule("feedback", rateLimit.getFeedbackMaxRequests());
        }
        if ("POST".equals(method) && path.matches("^/api/explore/places/\\d+/feedback$")) {
            return new Rule("feedback", rateLimit.getFeedbackMaxRequests());
        }
        if (path.startsWith("/media")) {
            return new Rule("upload", rateLimit.getUploadMaxRequests());
        }
        if (path.startsWith("/journeys/v2/entries/") && path.endsWith("/images")) {
            return new Rule("upload", rateLimit.getUploadMaxRequests());
        }
        if ("POST".equals(method) && "/journeys/v2/entries/with-images".equals(path)) {
            return new Rule("upload", rateLimit.getUploadMaxRequests());
        }
        return null;
    }

    private String resolveClientIp(HttpServletRequest request) {
        String headerName = props.getRateLimit().getIpHeader();
        String forwarded = request.getHeader(headerName);
        if (forwarded != null && !forwarded.isBlank()) {
            return forwarded.split(",")[0].trim();
        }
        return request.getRemoteAddr();
    }

    private void writeTooManyRequests(HttpServletResponse response, Rule rule, long windowSeconds) throws IOException {
        response.setStatus(HttpStatus.TOO_MANY_REQUESTS.value());
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("status", HttpStatus.TOO_MANY_REQUESTS.value());
        body.put("error", "Too Many Requests");
        body.put("message", "Rate limit exceeded for bucket: " + rule.bucket());
        body.put("windowSeconds", windowSeconds);
        body.put("limit", rule.limit());

        objectMapper.writeValue(response.getWriter(), body);
    }

    private void cleanupStaleEntries(long currentWindow) {
        counters.entrySet().removeIf(entry -> entry.getValue().startedAtEpochSecond() + 2 < currentWindow);
    }
}
