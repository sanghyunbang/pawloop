package com.heattrip.heat_trip_backend.observability.error;

import lombok.Builder;
import lombok.Getter;

import java.time.Instant;

@Getter
@Builder
public class ErrorEvent {
    private Instant occurredAt;
    private String service;
    private String correlationId;
    private String method;
    private String path;
    private String exceptionClass;
    private String message;
    private String stackTraceSnippet;
    private String clientIp;
    private String userAgent;
}
