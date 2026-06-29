package com.heattrip.heat_trip_backend.S3;

/**
 * 업로드 결과 DTO. 컨트롤러/서비스/프런트 간 표준 응답으로 사용합니다. [4]
 */
public record StoredObject(
    String key,          // S3 "키" (폴더 개념 X, 경로처럼 보이는 문자열) [5]
    String url,          // CDN(CloudFront) 또는 S3 퍼블릭 URL [6]
    String contentType,  // MIME 타입 (image/jpeg 등)
    long size            // 바이트 단위 파일 크기
) {}
