package com.heattrip.heat_trip_backend.S3;

import org.springframework.web.multipart.MultipartFile;

/** S3 키 생성 전략 인터페이스 */
public interface KeyStrategy {

    /** multipart 로 받은 파일의 키. 파일에서 쓰는 것은 이름뿐이라 {@link #buildKey(String, UploadRequest)} 와 같다. */
    default String buildKey(MultipartFile file, UploadRequest req) {
        return buildKey(file.getOriginalFilename(), req);
    }

    /** 파일 없이 이름만으로 — 서명 PUT 은 파일이 아직 없다 (#429). */
    String buildKey(String originalFilename, UploadRequest req);
}
