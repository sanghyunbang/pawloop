package com.heattrip.heat_trip_backend.S3;

import org.springframework.stereotype.Component;
import org.springframework.web.multipart.MultipartFile;

/** 이미지 전용 검증기 (타입/용량/빈 파일) */
@Component
public class ImageValidator implements UploadValidator {

    @Override
    public void validate(MultipartFile f, UploadRequest r) {
        if (f == null || f.isEmpty()) {
            throw new IllegalArgumentException("빈 파일입니다.");
        }
        if (f.getSize() > r.category().max) {
            throw new IllegalArgumentException("파일 용량 초과(최대 " + r.category().max + " 바이트)");
        }
        String ct = f.getContentType();
        if (ct == null || !r.category().allowed.contains(ct)) {
            throw new IllegalArgumentException("허용되지 않는 MIME 타입: " + ct);
        }
    }
}
