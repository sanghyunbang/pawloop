package com.heattrip.heat_trip_backend.S3;

import org.springframework.web.multipart.MultipartFile;

/** S3 키 생성 전략 인터페이스 */
public interface KeyStrategy {
    String buildKey(MultipartFile file, UploadRequest req);
}
