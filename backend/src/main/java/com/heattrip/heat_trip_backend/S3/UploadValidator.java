package com.heattrip.heat_trip_backend.S3;

import org.springframework.web.multipart.MultipartFile;

/** 업로드 사전 검증 인터페이스 */
public interface UploadValidator {
    void validate(MultipartFile file, UploadRequest req);
}
